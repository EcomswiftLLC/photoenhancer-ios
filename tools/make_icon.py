"""Draws the Clarivo app icon ("Cold Resolve", see design/icon/philosophy.md).

The mark: a photo tile (a cool mountain scene at first light) cut along its diagonal. The lower-left half shows the scene
as a coarse mosaic of large blocks, the upper-right half shows the same scene smooth and crisp. A thin line of glacier
aqua sits on the cut, and a single viewfinder corner mark points at the clear side. Upscale, unblur, enhance in one
gesture, readable down to 29 px.

Run: python tools/make_icon.py
Writes AppIcon-1024.png, AppIcon-1024-dark.png and AppIcon-1024-tinted.png into the asset catalog, plus
design/icon/preview.png (contact sheet at several sizes). Needs Pillow and numpy.
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/Resources/Assets.xcassets/AppIcon.appiconset"
PREVIEW = ROOT / "design/icon"

S = 4096                    # supersampled canvas
FINAL = 1024

INK = (8, 18, 25)           # #081219
INK_LIFT = (21, 42, 58)
GLACIER = (127, 230, 215)   # #7FE6D7
GLACIER_DEEP = (71, 201, 186)
FROST = (207, 247, 241)

TILE = 0.62                 # tile side, fraction of S
TILE_R = 0.115              # tile corner radius, fraction of S
CELLS = 6                   # mosaic blocks across the tile
GAP = 0.0055                # gap between blocks, fraction of S


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def radial_background(variant):
    if variant == "tinted":
        return np.zeros((S, S, 3), np.float32)
    inner, outer = (INK_LIFT, INK) if variant == "light" else ((15, 30, 42), (4, 10, 14))
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.sqrt((xx - S * 0.62) ** 2 + (yy - S * 0.30) ** 2) / (S * 0.95)
    k = np.clip(1 - d, 0, 1) ** 1.6
    arr = np.zeros((S, S, 3), np.float32)
    for c in range(3):
        arr[..., c] = outer[c] + (inner[c] - outer[c]) * k
    return arr


def scene(n):
    """The photo inside the tile, n x n float RGB: dawn sky, pale sun, two mountain ridges, still water."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    img = np.zeros((n, n, 3), np.float32)
    sky_top, sky_mid, horizon = (18, 46, 70), (40, 116, 132), (150, 226, 214)
    t = np.clip(yy / 0.62, 0, 1)
    for c in range(3):
        a = sky_top[c] + (sky_mid[c] - sky_top[c]) * np.clip(t * 1.4, 0, 1)
        img[..., c] = a + (horizon[c] - a) * np.clip((t - 0.55) / 0.45, 0, 1) ** 1.6
    # pale sun with a soft halo, upper right (the clear side)
    d = np.sqrt((xx - 0.70) ** 2 + (yy - 0.33) ** 2)
    halo = np.exp(-(d / 0.20) ** 2) * 0.35
    disc = np.clip((0.085 - d) / 0.0012, 0, 1)
    for c in range(3):
        img[..., c] += (FROST[c] - img[..., c]) * halo
        img[..., c] = img[..., c] * (1 - disc) + 248 * disc * (FROST[c] / 247)
    # far ridge
    x = xx[0]
    far = 0.56 - 0.13 * np.exp(-((x - 0.30) / 0.17) ** 2) - 0.07 * np.exp(-((x - 0.78) / 0.12) ** 2) + 0.012 * np.sin(x * 31)
    near = 0.70 - 0.16 * np.exp(-((x - 0.62) / 0.16) ** 2) - 0.05 * np.exp(-((x - 0.12) / 0.10) ** 2) + 0.008 * np.sin(x * 47 + 1)
    far_col, near_col = (34, 78, 96), (12, 34, 46)
    m_far = yy > far[None, :]
    m_near = yy > near[None, :]
    for c in range(3):
        img[..., c] = np.where(m_far, far_col[c] + (img[..., c] - far_col[c]) * 0.12 * (1 - yy), img[..., c])
        img[..., c] = np.where(m_near, near_col[c], img[..., c])
    # water with a faint reflected sun streak
    water = yy > 0.82
    streak = np.exp(-((xx - 0.70) / 0.03) ** 2) * 0.55
    for c in range(3):
        top_w, bot_w = (70, 150, 158)[c], (12, 36, 50)[c]
        base = top_w + (bot_w - top_w) * np.clip((yy - 0.82) / 0.18, 0, 1) ** 0.8
        img[..., c] = np.where(water, base + (FROST[c] - base) * streak, img[..., c])
    return np.clip(img, 0, 255)


def mosaic(img, cells, gap_px, ink):
    n = img.shape[0]
    out = np.empty_like(img)
    out[:] = ink
    step = n / cells
    for j in range(cells):
        for i in range(cells):
            y0, y1 = int(j * step), int((j + 1) * step)
            x0, x1 = int(i * step), int((i + 1) * step)
            col = img[y0:y1, x0:x1].reshape(-1, 3).mean(0)
            g = gap_px // 2
            out[y0 + g:y1 - g, x0 + g:x1 - g] = col
    return out


def rounded_mask(n, r):
    m = Image.new("L", (n, n), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, n - 1, n - 1], r, fill=255)
    return np.asarray(m, np.float32) / 255


def compose(variant):
    mono = variant == "tinted"
    canvas = radial_background(variant)
    n = int(S * TILE)
    ox = oy = (S - n) // 2
    sc = scene(n)
    ink_tile = (6, 14, 20)
    mos = mosaic(sc, CELLS, int(S * GAP), ink_tile)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    # diagonal from top-left to bottom-right: below/left of it = mosaic
    side = (yy - xx) / math.sqrt(2)                      # >0 means lower-left
    aa = np.clip(side / 3.0 + 0.5, 0, 1)[..., None]      # 3 px anti-aliased edge at 4x
    tile = sc * (1 - aa) + mos * aa
    if mono:
        g = tile @ np.array([0.30, 0.59, 0.11], np.float32)
        tile = np.repeat(g[..., None], 3, axis=2) * 1.05
    # the cut: a crisp core line plus a restrained glow
    dist = np.abs(side)
    core_w = S * 0.0042
    core = np.clip((core_w - dist) / 3.0 + 0.5, 0, 1)
    glow = np.exp(-(dist / (S * 0.020)) ** 2) * 0.33
    line_col = np.array((255, 255, 255) if mono else GLACIER, np.float32)
    # fade the line out just before the tile corners so it reads as light, not a rule
    along = (xx + yy) / (2 * n)
    fade = np.clip(np.minimum(along, 1 - along) / 0.08, 0, 1)
    tile = tile + (line_col - tile) * (glow * fade)[..., None]
    tile = tile + (np.array((255, 255, 255) if mono else FROST, np.float32) - tile) * (core * fade)[..., None]
    mask = rounded_mask(n, int(S * TILE_R))[..., None]
    # hairline rim on the tile so it separates from the ink at small sizes
    inner = rounded_mask(n - 2 * int(S * 0.003), int(S * TILE_R) - int(S * 0.003))
    rim = mask[..., 0].copy()
    pad = int(S * 0.003)
    rim[pad:n - pad, pad:n - pad] -= inner
    rim = np.clip(rim, 0, 1)[..., None] * 0.16
    region = canvas[oy:oy + n, ox:ox + n]
    region[:] = region * (1 - mask) + tile * mask
    region[:] = region + (255 - region) * rim
    canvas[oy:oy + n, ox:ox + n] = region

    img = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8), "RGB")
    # viewfinder corner mark at the clear (upper-right) corner, outside the tile
    d = ImageDraw.Draw(img)
    m = S * 0.052                      # distance from tile edge
    L = S * 0.105                      # arm length
    w = int(S * 0.016)                 # stroke
    cx, cy = ox + n + m, oy - m
    col = (255, 255, 255) if mono else GLACIER
    d.line([(cx - L, cy), (cx, cy)], fill=col, width=w)
    d.line([(cx, cy), (cx, cy + L)], fill=col, width=w)
    d.ellipse([cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2], fill=col)
    for (px, py) in ((cx - L, cy), (cx, cy + L)):
        d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=col)
    # the counterpart at the coarse corner, faint: the frame exists but has not snapped yet
    bx, by = ox - m, oy + n + m
    faint = (90, 90, 90) if mono else (52, 92, 104)
    d.line([(bx, by - L), (bx, by)], fill=faint, width=w)
    d.line([(bx, by), (bx + L, by)], fill=faint, width=w)
    for (px, py) in ((bx, by), (bx, by - L), (bx + L, by)):
        d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=faint)
    return img.resize((FINAL, FINAL), Image.LANCZOS)


def preview(icons):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    sizes = [180, 120, 80, 60, 40, 29]
    W = 1100
    sheet = Image.new("RGB", (W, 620), (22, 24, 30))
    x = 30
    for name, im in icons.items():
        big = im.resize((320, 320), Image.LANCZOS)
        mask = Image.new("L", (320, 320), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, 319, 319], 72, fill=255)
        sheet.paste(big, (x, 30), mask)
        sx, yy = x, 380
        for s in sizes:
            sm = im.resize((s, s), Image.LANCZOS)
            mk = Image.new("L", (s, s), 0)
            ImageDraw.Draw(mk).rounded_rectangle([0, 0, s - 1, s - 1], int(s * 0.2237), fill=255)
            if sx + s > x + 330:
                break
            sheet.paste(sm, (sx, yy), mk)
            sx += s + 14
        x += 360
    sheet.save(PREVIEW / "preview.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    icons = {}
    for variant, fname in (("light", "AppIcon-1024.png"), ("dark", "AppIcon-1024-dark.png"), ("tinted", "AppIcon-1024-tinted.png")):
        im = compose(variant)
        im.save(OUT / fname, optimize=True)
        icons[variant] = im
        print("wrote", OUT / fname)
    preview(icons)
    print("wrote", PREVIEW / "preview.png")


if __name__ == "__main__":
    main()
