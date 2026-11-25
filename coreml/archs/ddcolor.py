"""DDColor (Kang et al. 2022) loader for Core ML conversion.

Uses the upstream piddnad/DDColor code (Apache-2.0) from a git checkout (path in env DDCOLOR_SRC,
pinned commit in models.yml). Only the architecture modules are imported; BasicSR's package
__init__ (training code, heavy deps) is bypassed with namespace stubs.

Conversion-friendly changes (same math, verified against the unmodified upstream forward):
- spectral norm is folded into plain conv weights (eval-mode weight, no power iteration);
- the final einsum "bqc,bchw->bqhw" is written as a batched matmul.
"""
import importlib
import os
import sys
import types

import torch
from torch import nn


def _import_upstream():
    src = os.environ.get("DDCOLOR_SRC", os.path.join(os.path.dirname(__file__), "..", "..", "build", "DDColor"))
    src = os.path.abspath(src)
    if "basicsr" not in sys.modules:
        for name, rel in (("basicsr", "basicsr"), ("basicsr.archs", "basicsr/archs")):
            m = types.ModuleType(name)
            m.__path__ = [os.path.join(src, rel)]
            sys.modules[name] = m
    sys.path.insert(0, src)
    model_mod = importlib.import_module("ddcolor.model")
    return model_mod


def _fold_spectral_norm(module):
    for m in module.modules():
        for k, hook in list(m._forward_pre_hooks.items()):
            if hook.__class__.__name__ == "SpectralNorm":
                torch.nn.utils.remove_spectral_norm(m)
                break


def load(path, input_size=512):
    mm = _import_upstream()
    model = mm.DDColor(
        encoder_name="convnext-t",
        decoder_name="MultiScaleColorDecoder",
        input_size=[input_size, input_size],
        num_output_channels=2,
        last_norm="Spectral",
        do_normalize=False,
        num_queries=100,
        num_scales=3,
        dec_layers=9,
    )
    sd = torch.load(path, map_location="cpu", weights_only=False)
    sd = sd.get("params", sd)
    missing, unexpected = model.load_state_dict(sd, strict=False)
    # upstream loads with strict=False too; report anything that is not a spectral-norm buffer
    # (the ConvNeXt ImageNet classification head `head_cls` is not used by DDColor)
    bad = [k for k in list(missing) + list(unexpected)
           if not k.endswith(("_u", "_v", "_orig")) and "head_cls" not in k]
    if bad:
        raise RuntimeError(f"DDColor state dict mismatch: {bad[:20]}")
    return model.eval()


def _matmul_color_decoder_forward(self, x, img_features):
    src, pos = self._get_src_and_pos(x)
    bs = src[0].shape[1]
    query_embed = self.query_embed.weight.unsqueeze(1).repeat(1, bs, 1)
    output = self.query_feat.weight.unsqueeze(1).repeat(1, bs, 1)
    for i in range(self.num_layers):
        level_index = i % self.num_feature_levels
        output = self.transformer_cross_attention_layers[i](
            output, src[level_index], memory_mask=None, memory_key_padding_mask=None,
            pos=pos[level_index], query_pos=query_embed)
        output = self.transformer_self_attention_layers[i](
            output, tgt_mask=None, tgt_key_padding_mask=None, query_pos=query_embed)
        output = self.transformer_ffn_layers[i](output)
    decoder_output = self.decoder_norm(output).transpose(0, 1)
    color_embed = self.color_embed(decoder_output)  # b,q,c
    b, c, h, w = img_features.shape
    out = torch.matmul(color_embed, img_features.reshape(b, c, h * w))  # b,q,hw
    return out.reshape(b, -1, h, w)


def make_convertible(model):
    """Return the same model, spectral norm folded and einsum replaced (in place)."""
    _fold_spectral_norm(model)
    dec = model.decoder.color_decoder
    dec.forward = types.MethodType(_matmul_color_decoder_forward, dec)
    return model


def srgb_to_gray_rgb(x):
    """sRGB 0..1 (N,3,H,W) -> gray sRGB with the same CIE L* (what upstream gets from
    Lab2RGB(L, 0, 0)), replicated to 3 channels. Linear RGB (Y,Y,Y) is exactly Lab (L,0,0) for D65."""
    lin = torch.where(x <= 0.04045, x / 12.92, torch.pow((torch.clamp(x, 0.0, 1.0) + 0.055) / 1.055, 2.4))
    y = 0.2126729 * lin[:, 0:1] + 0.7151522 * lin[:, 1:2] + 0.0721750 * lin[:, 2:3]
    g = torch.where(y <= 0.0031308, 12.92 * y, 1.055 * torch.pow(torch.clamp(y, 1e-6, 1.0), 1.0 / 2.4) - 0.055)
    return torch.cat([g, g, g], dim=1)


class DDColorWrapper(nn.Module):
    """Core ML graph: any sRGB image 0..1 (ImageType scale 1/255) -> ab (Lab a*, b*), shape (1,2,H,W).

    The gray conversion upstream does on the CPU (RGB -> L -> Lab(L,0,0) -> RGB) is done in the graph,
    so the app can feed the photo (colour or B&W) resized to 512x512 directly.
    Upstream forward normalises with ImageNet mean/std internally (x.shape[1] == 3)."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, image):
        return self.model(srgb_to_gray_rgb(image))
