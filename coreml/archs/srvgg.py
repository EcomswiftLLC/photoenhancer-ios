"""SRVGGNetCompact, the architecture of Real-ESRGAN `realesr-general-x4v3`.

Re-implemented from xinntao/Real-ESRGAN `realesrgan/archs/srvgg_arch.py`
(BSD 3-Clause License, Copyright (c) 2021, Xintao Wang). State-dict compatible with the
official `realesr-general-x4v3.pth` (key `params`).
"""
import torch
from torch import nn
from torch.nn import functional as F


class SRVGGNetCompact(nn.Module):
    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=32, upscale=4):
        super().__init__()
        self.upscale = upscale
        self.body = nn.ModuleList()
        self.body.append(nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        self.body.append(nn.PReLU(num_parameters=num_feat))
        for _ in range(num_conv):
            self.body.append(nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            self.body.append(nn.PReLU(num_parameters=num_feat))
        self.body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.upsampler = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = x
        for layer in self.body:
            out = layer(out)
        out = self.upsampler(out)
        base = F.interpolate(x, scale_factor=self.upscale, mode="nearest")
        return out + base


class ESRGANWrapper(nn.Module):
    """Core ML graph: RGB 0..1 (ImageType scale 1/255 applied by Core ML) -> RGB 0..255, clamped."""

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, image):
        y = self.net(image)
        return torch.clamp(y, 0.0, 1.0) * 255.0


def load(path):
    net = SRVGGNetCompact()
    sd = torch.load(path, map_location="cpu", weights_only=True)
    sd = sd.get("params_ema", sd.get("params", sd))
    net.load_state_dict(sd, strict=True)
    return net.eval()
