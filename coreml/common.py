"""Shared helpers: model specs, metrics, Lab conversion (OpenCV float conventions, D65)."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)


def psnr(a, b, peak=255.0):
    a = np.asarray(a, np.float64)
    b = np.asarray(b, np.float64)
    mse = np.mean((a - b) ** 2)
    return float("inf") if mse == 0 else float(10 * np.log10(peak * peak / mse))


def ssim(a, b):
    from skimage.metrics import structural_similarity
    return float(structural_similarity(np.asarray(a), np.asarray(b), channel_axis=2, data_range=255))


def rgb_to_lab(rgb_u8):
    import cv2
    return cv2.cvtColor(rgb_u8.astype(np.float32) / 255.0, cv2.COLOR_RGB2Lab)


def lab_to_rgb_u8(lab):
    import cv2
    rgb = cv2.cvtColor(lab.astype(np.float32), cv2.COLOR_Lab2RGB)
    return np.clip(np.rint(rgb * 255.0), 0, 255).astype(np.uint8)


def combine_l_ab(rgb_u8, ab_small):
    """App post-processing reference: original full-res L + model ab (2,h,w) resized bilinear."""
    import cv2
    h, w = rgb_u8.shape[:2]
    lab = rgb_to_lab(rgb_u8)
    a = cv2.resize(np.asarray(ab_small[0], np.float32), (w, h), interpolation=cv2.INTER_LINEAR)
    b = cv2.resize(np.asarray(ab_small[1], np.float32), (w, h), interpolation=cv2.INTER_LINEAR)
    out = np.stack([lab[..., 0], a, b], -1)
    return lab_to_rgb_u8(out)


def colorfulness(rgb_u8):
    """Hasler & Suesstrunk colourfulness metric."""
    r, g, b = [rgb_u8[..., i].astype(np.float64) for i in range(3)]
    rg = r - g
    yb = 0.5 * (r + g) - b
    return float(np.sqrt(rg.std() ** 2 + yb.std() ** 2) + 0.3 * np.sqrt(rg.mean() ** 2 + yb.mean() ** 2))


MODELS = {
    "ESRGANGeneral": {
        "weights": "realesr-general-x4v3.pth",
        "in_size": 256, "scale": 4, "output": "image",
        "licence": "BSD-3-Clause",
        "source": "https://github.com/xinntao/Real-ESRGAN (weights: releases/download/v0.2.5.0/realesr-general-x4v3.pth)",
        "description": "Real-ESRGAN realesr-general-x4v3 (SRVGGNetCompact) 4x blind super-resolution",
    },
    "NAFNetDeblur": {
        "weights": "NAFNet-GoPro-width32.pth",
        "in_size": 256, "scale": 1, "output": "image",
        "licence": "MIT",
        "source": "https://github.com/megvii-research/NAFNet (NAFNet-GoPro-width32.pth, official Google Drive 1Fr2QadtDCEXg6iwWX8OzeZLbHOx2t5Bj)",
        "description": "NAFNet width32 trained on GoPro motion deblurring, two-pass global channel-attention context",
    },
    "DDColorTiny": {
        "weights": "ddcolor_paper_tiny.pth",
        "in_size": 512, "scale": 1, "output": "ab",
        "licence": "Apache-2.0",
        "source": "https://github.com/piddnad/DDColor (weights: https://huggingface.co/piddnad/DDColor-models ddcolor_paper_tiny.pth)",
        "description": "DDColor tiny (ConvNeXt-T encoder) automatic colorization, predicts Lab ab",
    },
}


def build_torch(name, weights_dir):
    """Return (wrapper nn.Module in eval mode, example input tensor)."""
    import torch
    from archs import ddcolor, nafnet, srvgg
    spec = MODELS[name]
    path = os.path.join(weights_dir, spec["weights"])
    n = spec["in_size"]
    if name == "ESRGANGeneral":
        w = srvgg.ESRGANWrapper(srvgg.load(path))
    elif name == "NAFNetDeblur":
        w = nafnet.NAFNetContext(nafnet.load(path)).eval()
        return w, (torch.rand(1, 3, n, n), torch.rand(1, w.n_stats), torch.ones(1, 1))
    else:
        w = ddcolor.DDColorWrapper(ddcolor.make_convertible(ddcolor.load(path, input_size=n)))
    w.eval()
    return w, torch.rand(1, 3, n, n)
