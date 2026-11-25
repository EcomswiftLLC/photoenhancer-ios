"""Synthetic degradations of real photos for the quality tests."""
import io

import cv2
import numpy as np
from PIL import Image


def jpeg(img, q):
    buf = io.BytesIO()
    Image.fromarray(img).save(buf, "JPEG", quality=int(q))
    return np.asarray(Image.open(io.BytesIO(buf.getvalue())).convert("RGB"))


def sr_degrade(hr, seed=0, factor=4):
    """Blur (sigma 1.0-1.6) -> downscale 1/4 bicubic -> Gaussian noise (sigma 2-5) -> JPEG q 55-75."""
    rng = np.random.default_rng(seed)
    h, w = hr.shape[:2]
    h, w = h - h % factor, w - w % factor
    x = cv2.GaussianBlur(hr[:h, :w], (0, 0), float(rng.uniform(1.0, 1.6)))
    x = cv2.resize(x, (w // factor, h // factor), interpolation=cv2.INTER_CUBIC)
    x = x.astype(np.float32) + rng.normal(0, rng.uniform(2, 5), x.shape)
    x = np.clip(np.rint(x), 0, 255).astype(np.uint8)
    return jpeg(x, rng.uniform(55, 75))


def motion_kernel(length, angle_deg):
    k = np.zeros((length, length), np.float32)
    k[length // 2, :] = 1.0
    m = cv2.getRotationMatrix2D((length / 2 - 0.5, length / 2 - 0.5), angle_deg, 1.0)
    k = cv2.warpAffine(k, m, (length, length), flags=cv2.INTER_LINEAR)
    return k / k.sum()


def motion_blur(img, seed=0, length=None, angle=None, noise=1.5):
    """Linear camera-shake blur, 13-21 px at a random angle, light noise; like a handheld shot."""
    rng = np.random.default_rng(seed)
    length = int(length or rng.integers(13, 22))
    angle = float(angle if angle is not None else rng.uniform(0, 180))
    x = cv2.filter2D(img.astype(np.float32), -1, motion_kernel(length, angle), borderType=cv2.BORDER_REFLECT)
    x = x + rng.normal(0, noise, x.shape)
    return np.clip(np.rint(x), 0, 255).astype(np.uint8)
