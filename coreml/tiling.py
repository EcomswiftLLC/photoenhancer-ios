"""Reference tiling + feathered blend (the app's Swift implementation must match this).

tile T (model input size), overlap O (input px), scale s (output/input).
- Images smaller than T in a dimension are edge-padded up to T, the output is cropped back.
- Tile origins along an axis of length N: 0, T-O, 2(T-O), ... and the last origin is clamped to N-T.
- Each output tile is weighted by a separable linear ramp over O*s output px on every edge that has
  a neighbour tile (image borders keep weight 1). Accumulate sum(w*out) and sum(w), then divide.
"""
import numpy as np


def origins(n, t, o):
    if n <= t:
        return [0]
    step = t - o
    xs = list(range(0, n - t, step))
    if not xs or xs[-1] != n - t:
        xs.append(n - t)
    return xs


def ramp(length, fade, left, right):
    w = np.ones(length, np.float32)
    j = np.arange(length, dtype=np.float32)
    if left:
        w *= np.clip((j + 0.5) / fade, 0.0, 1.0)
    if right:
        w *= np.clip((length - j - 0.5) / fade, 0.0, 1.0)
    return w


def run_tiled(img, fn, t=256, o=16, s=1):
    """img: HxWx3 uint8. fn: uint8 (t,t,3) -> uint8/float (t*s,t*s,3). Returns uint8 (H*s,W*s,3)."""
    h, w = img.shape[:2]
    ph, pw = max(h, t), max(w, t)
    if (ph, pw) != (h, w):
        img = np.pad(img, ((0, ph - h), (0, pw - w), (0, 0)), mode="edge")
    acc = np.zeros((ph * s, pw * s, 3), np.float32)
    wsum = np.zeros((ph * s, pw * s, 1), np.float32)
    ys, xs = origins(ph, t, o), origins(pw, t, o)
    for yi, y in enumerate(ys):
        for xi, x in enumerate(xs):
            out = np.asarray(fn(np.ascontiguousarray(img[y:y + t, x:x + t])), np.float32)
            wy = ramp(t * s, o * s, yi > 0, yi < len(ys) - 1)
            wx = ramp(t * s, o * s, xi > 0, xi < len(xs) - 1)
            wt = (wy[:, None] * wx[None, :])[..., None]
            acc[y * s:(y + t) * s, x * s:(x + t) * s] += out * wt
            wsum[y * s:(y + t) * s, x * s:(x + t) * s] += wt
    res = acc / np.maximum(wsum, 1e-8)
    return np.clip(np.rint(res), 0, 255).astype(np.uint8)[: h * s, : w * s]
