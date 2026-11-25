"""NAFNet (Simple Baselines for Image Restoration, Chen et al. 2022).

Adapted from megvii-research/NAFNet `basicsr/models/archs/NAFNet_arch.py` and `arch_util.py`
(MIT License, Copyright (c) 2022 megvii-model). Changes for Core ML conversion:
- LayerNorm2d uses plain tensor ops instead of a custom autograd.Function (same math).
- No dropout, no padding helper (the Core ML model has a fixed 256x256 input, a multiple of 16).
State-dict compatible with the official `NAFNet-GoPro-width32.pth` (key `params`).
"""
import torch
from torch import nn


class LayerNorm2d(nn.Module):
    def __init__(self, channels, eps=1e-6):
        super().__init__()
        self.weight = nn.Parameter(torch.ones(channels))
        self.bias = nn.Parameter(torch.zeros(channels))
        self.eps = eps

    def forward(self, x):
        mu = x.mean(1, keepdim=True)
        d = x - mu
        var = (d * d).mean(1, keepdim=True)
        y = d / torch.sqrt(var + self.eps)
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
        x = x * self.sca[1](x.mean(dim=(2, 3), keepdim=True))
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
