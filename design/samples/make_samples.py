"""Builds Sources/Resources/Samples from the downloaded originals (see docs/store/photo-credits.md for sources).

Usage: python design/samples/make_samples.py <folder with the downloaded originals>
Originals: long side capped at 2400 px, JPEG quality 85 (88 for the two historical prints), max ~1.5 MB.
Degraded copies (clearly named, labelled as such in the credits) are made from the sharp originals so the app,
the store slides and the tests have honest, reproducible inputs for upscale, unblur and denoise.
"""
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "Sources", "Resources", "Samples")


def save(im, name, q=85):
    p = os.path.join(OUT, name)
    for qq in (q, 80, 75, 70):
        im.save(p, "JPEG", quality=qq, optimize=True)
        if os.path.getsize(p) <= 1_550_000:
            break
    print(name, im.size, os.path.getsize(p))


def jpeg(im, q):
    b = io.BytesIO()
    im.save(b, "JPEG", quality=q)
    return Image.open(io.BytesIO(b.getvalue())).convert("RGB")


def fit(im, long_side, resample=Image.LANCZOS):
    s = long_side / max(im.size)
    return im.resize((round(im.width * s), round(im.height * s)), resample)


def main(src_dir):
    os.makedirs(OUT, exist_ok=True)
    src = {}
    for f in sorted(os.listdir(src_dir)):
        if not f.endswith(".jpg"):
            continue
        im = Image.open(os.path.join(src_dir, f)).convert("RGB")
        if max(im.size) > 2400:
            im = fit(im, 2400)
        src[f] = im
        save(im, f, 88 if f.startswith("old-") else 85)
    rng = np.random.default_rng(7)

    # 1) low-resolution copy of the historic building: 600 px long side, heavy JPEG (for Upscale)
    save(jpeg(fit(src["historic-building.jpg"], 600, Image.BILINEAR), 40), "historic-building-lowres.jpg", 90)

    # 2) horizontally shaken copy of the street sign: 25 px box motion blur at 1600 px (for Unblur)
    sg = fit(src["street-sign.jpg"], 1600)
    a = np.asarray(sg, np.float32)
    k = 25
    acc = np.zeros_like(a)
    for i in range(k):
        acc += np.roll(a, i - k // 2, axis=1)
    acc /= k
    save(jpeg(Image.fromarray(np.clip(acc, 0, 255).astype(np.uint8)), 88), "street-sign-motion-blur.jpg", 88)

    # 3) darker, noisy copy of the cat: 1600 px, exposure x0.8, luminance + colour noise (for Denoise)
    c = fit(src["tabby-cat.jpg"], 1600)
    a = np.asarray(c, np.float32) * 0.8
    a += rng.normal(0, 14, a.shape[:2])[..., None] + rng.normal(0, 7, a.shape)
    save(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), "tabby-cat-noisy.jpg", 85)

    # 4) small, soft copy of the woman portrait: 800 px, 1.2 px blur, JPEG 55 (for Portrait enhance)
    w = fit(src["portrait-woman.jpg"], 800, Image.BILINEAR).filter(ImageFilter.GaussianBlur(1.2))
    save(jpeg(w, 55), "portrait-woman-lowres.jpg", 90)


if __name__ == "__main__":
    main(sys.argv[1])
