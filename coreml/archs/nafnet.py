"""NAFNet (Simple Baselines for Image Restoration, Chen et al. 2022).

Adapted from megvii-research/NAFNet `basicsr/models/archs/NAFNet_arch.py` and `arch_util.py`
(MIT License, Copyright (c) 2022 megvii-model). Changes for Core ML conversion:
- LayerNorm2d uses plain tensor ops instead of a custom autograd.Function (same math).
- No dropout, no padding helper (the Core ML model has a fixed 256x256 input, a multiple of 16).
State-dict compatible with the official `NAFNet-GoPro-width32.pth` (key `params`).
"""
import torch
from torch import nn
from torch.nn import functional as F


def spatial_mean(x):
    """Global average pool, fp16-safe and exact: Core ML may accumulate reduce_mean in float16, and on
    flat 256x256 tiles the plain spatial sum reaches ~78000 > 65504 (overflow -> broken tiles).
    Mean of equal-block means == global mean; pre-scaling by 1/16 keeps every 4x4 partial sum below
    max|x|, so nothing can overflow."""
    y = x * (1.0 / 16.0)
    while y.shape[-1] > 1 or y.shape[-2] > 1:
        kh = 4 if y.shape[-2] % 4 == 0 else (2 if y.shape[-2] % 2 == 0 else y.shape[-2])
        kw = 4 if y.shape[-1] % 4 == 0 else (2 if y.shape[-1] % 2 == 0 else y.shape[-1])
        y = F.avg_pool2d(y, (kh, kw))
    return y * 16.0


class LayerNorm2d(nn.Module):
    def __init__(self, channels, eps=1e-6):
        super().__init__()
        self.weight = nn.Parameter(torch.ones(channels))
        self.bias = nn.Parameter(torch.zeros(channels))
        self.eps = eps

    # fp16 safety: the residual stream of the deep 28-block stage reaches |x| ~ 600 on photos and
    # ~ 18000 on heavy noise, so (x - mu)^2 overflows float16 (max 65504) and blocks output garbage
    # (seen on Core ML as broken tiles on flat backgrounds). Layer norm is scale invariant, so we
    # normalise by the per-pixel channel max m: d' = d / m in [-1, 1], and
    #   d / sqrt(mean(d^2) + eps) == d' / sqrt(mean(d'^2) + eps / m^2),  eps / m^2 = (sqrt(eps) / m)^2
    # which is exact (eps = 1e-6) and every intermediate stays in fp16 range. m is floored at
    # sqrt(eps) = 1e-3 (then d' -> tiny and the result is ~0, as in the original).
    def forward(self, x):
        mu = x.mean(1, keepdim=True)
        d = x - mu
        r = self.eps ** 0.5
        m = torch.clamp(d.abs().amax(dim=1, keepdim=True), min=r)
        dn = d / m
        var = (dn * dn).mean(1, keepdim=True)
        e = (r / m) * (r / m)
        y = dn / torch.sqrt(var + e)
        return self.weight.view(1, -1, 1, 1) * y + self.bias.view(1, -1, 1, 1)


class SimpleGate(nn.Module):
    def forward(self, x):
        x1, x2 = x.chunk(2, dim=1)
        return x1 * x2


class NAFBlock(nn.Module):
    def __init__(self, c, DW_Expand=2, FFN_Expand=2):
        super().__init__()
        dw = c * DW_Expand
        self.conv1 = nn.Conv2d(c, dw, 1, 1, 0)
        self.conv2 = nn.Conv2d(dw, dw, 3, 1, 1, groups=dw)
        self.conv3 = nn.Conv2d(dw // 2, c, 1, 1, 0)
        self.sca = nn.Sequential(nn.AdaptiveAvgPool2d(1), nn.Conv2d(dw // 2, dw // 2, 1, 1, 0))
        self.sg = SimpleGate()
        ffn = FFN_Expand * c
        self.conv4 = nn.Conv2d(c, ffn, 1, 1, 0)
        self.conv5 = nn.Conv2d(ffn // 2, c, 1, 1, 0)
        self.norm1 = LayerNorm2d(c)
        self.norm2 = LayerNorm2d(c)
        self.beta = nn.Parameter(torch.zeros((1, c, 1, 1)))
        self.gamma = nn.Parameter(torch.zeros((1, c, 1, 1)))

    def forward(self, inp):
        x = self.norm1(inp)
        x = self.conv1(x)
        x = self.conv2(x)
        x = self.sg(x)
        # global average pool written as mean so it converts to a plain reduce op
        x = x * self.sca[1](spatial_mean(x))
        x = self.conv3(x)
        y = inp + x * self.beta
        x = self.conv4(self.norm2(y))
        x = self.sg(x)
        x = self.conv5(x)
        return y + x * self.gamma


class NAFNet(nn.Module):
    def __init__(self, img_channel=3, width=32, middle_blk_num=1, enc_blk_nums=(1, 1, 1, 28), dec_blk_nums=(1, 1, 1, 1)):
        super().__init__()
        self.intro = nn.Conv2d(img_channel, width, 3, 1, 1)
        self.ending = nn.Conv2d(width, img_channel, 3, 1, 1)
        self.encoders = nn.ModuleList()
        self.decoders = nn.ModuleList()
        self.ups = nn.ModuleList()
        self.downs = nn.ModuleList()
        chan = width
        for num in enc_blk_nums:
            self.encoders.append(nn.Sequential(*[NAFBlock(chan) for _ in range(num)]))
            self.downs.append(nn.Conv2d(chan, 2 * chan, 2, 2))
            chan *= 2
        self.middle_blks = nn.Sequential(*[NAFBlock(chan) for _ in range(middle_blk_num)])
        for num in dec_blk_nums:
            self.ups.append(nn.Sequential(nn.Conv2d(chan, chan * 2, 1, bias=False), nn.PixelShuffle(2)))
            chan //= 2
            self.decoders.append(nn.Sequential(*[NAFBlock(chan) for _ in range(num)]))

    def forward(self, inp):
        x = self.intro(inp)
        encs = []
        for encoder, down in zip(self.encoders, self.downs):
            x = encoder(x)
            encs.append(x)
            x = down(x)
        x = self.middle_blks(x)
        for decoder, up, skip in zip(self.decoders, self.ups, encs[::-1]):
            x = up(x)
            x = x + skip
            x = decoder(x)
        x = self.ending(x)
        return x + inp


class NAFNetWrapper(nn.Module):
    """Core ML graph: RGB 0..1 (ImageType scale 1/255) -> RGB 0..255, clamped."""

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, image):
        return torch.clamp(self.net(image), 0.0, 1.0) * 255.0


def load(path):
    net = NAFNet()
    sd = torch.load(path, map_location="cpu", weights_only=True)
    sd = sd.get("params", sd)
    net.load_state_dict(sd, strict=True)
    return net.eval()


def _block_ctx(blk, inp, ctx, mix):
    """NAFBlock forward where the channel-attention pooling uses mix*ctx + (1-mix)*own tile mean."""
    x = blk.norm1(inp)
    x = blk.conv1(x)
    x = blk.conv2(x)
    x = blk.sg(x)
    own = spatial_mean(x)
    pooled = own + mix * (ctx - own)
    x = x * blk.sca[1](pooled)
    x = blk.conv3(x)
    y = inp + x * blk.beta
    x = blk.conv4(blk.norm2(y))
    x = blk.sg(x)
    x = blk.conv5(x)
    return y + x * blk.gamma, own


class NAFNetContext(nn.Module):
    """NAFNet whose channel-attention (SCA) statistics can come from the whole photo.

    NAFNet's SCA pools each block's features over the whole input. Upstream runs whole images; on
    small tiles of dark, flat areas the tile-local statistics are out of distribution and the deep
    blocks explode (garbage tiles, reproduced in fp32 PyTorch). Two passes fix it:
      pass 1: the whole photo resized to 256x256, mix = 0 -> output `stats` (global SCA statistics)
      pass 2: every 256x256 tile with context = stats, mix = 1 -> `result`
    inputs: image (1,3,256,256) 0..1, context (1,N), mix (1,1); outputs: result 0..255, stats (1,N)."""

    def __init__(self, net):
        super().__init__()
        self.net = net
        self.sizes = []
        for blk in self.blocks():
            self.sizes.append(blk.conv3.in_channels)
        self.n_stats = sum(self.sizes)

    def blocks(self):
        n = self.net
        out = []
        for e in n.encoders:
            out += list(e)
        out += list(n.middle_blks)
        for d in n.decoders:
            out += list(d)
        return out

    def forward(self, image, context, mix):
        n = self.net
        m = mix.view(1, 1, 1, 1)
        stats = []
        off = [0]

        def run(seq, x):
            for blk in seq:
                c = blk.conv3.in_channels
                ctx = context[:, off[0]:off[0] + c].reshape(1, c, 1, 1)
                off[0] += c
                x, own = _block_ctx(blk, x, ctx, m)
                stats.append(own.reshape(1, c))
            return x

        x = n.intro(image)
        encs = []
        for enc, down in zip(n.encoders, n.downs):
            x = run(enc, x)
            encs.append(x)
            x = down(x)
        x = run(n.middle_blks, x)
        for dec, up, skip in zip(n.decoders, n.ups, encs[::-1]):
            x = up(x) + skip
            x = run(dec, x)
        x = n.ending(x) + image
        return torch.clamp(x, 0.0, 1.0) * 255.0, torch.cat(stats, dim=1)
