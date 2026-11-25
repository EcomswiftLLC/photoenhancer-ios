"""Shared layout code for the Clarivo App Store screenshot scripts (make_store_shots.py, make_store_shots_ipad.py).

Every store slide is a REAL in-app capture (CI artifacts `store-iphone` and `store-ipad`) placed on the deep-ink
background under a short headline. Nothing in a slide is drawn UI: if a capture is missing, the slide is skipped and
reported, never invented.

Capture names (produced by the APP agent's CI with the `-cvScreen <name>` launch argument):
home, enhance-result, compare, unblur, colorize, restore, portrait, batch, export, settings.

Copy rules (docs/DESIGN.md section 8): enhance, sharpen, upscale; no "recover lost detail"; colours are estimates;
no ratings, no competitor names. A before/after shown on a slide must come from the app's own models on the sample
photos (the captures are real app screens, so that holds by construction).
Typeface: Instrument Sans (design/fonts, SIL Open Font License).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
FONT = ROOT / "design/fonts/InstrumentSans-Variable.ttf"

INK = (8, 18, 25)          # #081219
DEEP = (15, 28, 38)        # #0F1C26
PEARL = (238, 245, 247)    # #EEF5F7
MIST = (157, 179, 191)     # #9DB3BF
GLACIER = (127, 230, 215)  # #7FE6D7
FROST = (207, 247, 241)

# (capture name, headline lines, supporting line). Copy is limited to what the app does (docs/ARCHITECTURE.md).
SLIDES = [
    ("enhance-result", ["Sharper, larger", "photos in a tap."], "AI upscale 2x, 4x or 8x, right on your device."),
    ("compare", ["See every", "detail change."], "Drag to compare. Pinch to zoom both sides."),
    ("unblur", ["Reduce blur", "and shake."], "Unblur and Sharpen for soft or shaky shots."),
    ("restore", ["Bring back", "faded prints."], "Reduce scratches, dust, fading and yellowing."),
    ("colorize", ["Add colour to", "black and white."], "Natural-looking colour, full resolution kept."),
    ("portrait", ["Clearer faces,", "never new ones."], "Sharpens the faces it finds and blends them back."),
    ("batch", ["Enhance many", "photos at once."], "Same settings for all, one ad for the batch."),
    ("export", ["JPG, PNG or HEIC,", "up to 8x."], "Keep or remove location data. No watermark."),
    ("home", ["Your photos never", "leave your device."], "Every model runs on your device. No account."),
    ("settings", ["Free, with no", "account to make."], "Clear privacy choices. Open-source credits inside."),
]

# Captures whose bottom edge carries pinned controls are shown whole instead of bleeding off the slide.
FIT_SLIDES = {"export", "settings"}
BRAND_SLIDES = {"home"}


def display(size, weight=600):
    try:
        f = ImageFont.truetype(str(FONT), size)
        f.set_variation_by_axes([100, weight])
        return f
    except Exception:
        for n in ("seguisb.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf"):
            for base in ("C:/Windows/Fonts/", "/usr/share/fonts/truetype/dejavu/"):
                if Path(base + n).exists():
                    return ImageFont.truetype(base + n, size)
        return ImageFont.load_default()


def text_font(size):
    return display(size, 450)


def background(W, H):
    """Deep blue ink, lit from the upper right by a cold, clear light; a faint glacier haze behind the capture."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    t = (yy / H)[..., None]
    base = np.array((14, 30, 42), np.float32) * (1 - t) + np.array(INK, np.float32) * t
    d = np.sqrt(((xx - W * 0.85) / W) ** 2 + ((yy - H * 0.02) / H) ** 2)
    light = np.exp(-(d / 0.55) ** 2)[..., None]
    base += light * (np.array((40, 86, 104), np.float32) - base) * 0.55
    haze = np.exp(-(((xx - W / 2) / (W * 0.45)) ** 2 + ((yy - H * 0.62) / (H * 0.32)) ** 2))[..., None]
    base += haze * (np.array(GLACIER, np.float32) - base) * 0.06
    # very fine grain so the gradient never bands
    rng = np.random.default_rng(3)
    base += rng.normal(0, 1.2, base.shape[:2])[..., None]
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")


def rounded(im, radius, top_only=False):
    mask = Image.new("L", im.size, 0)
    box = [0, 0, im.width - 1, (im.height + radius) if top_only else (im.height - 1)]
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def wrap_text(draw, text, fnt, max_w):
    """Greedy wrap, then rebalance two-line results so no line is a lone word."""
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    if len(lines) == 2:
        best = None
        for i in range(1, len(words)):
            a, b = " ".join(words[:i]), " ".join(words[i:])
            w = max(draw.textlength(a, font=fnt), draw.textlength(b, font=fnt))
            if w <= max_w and (best is None or w < best[0]):
                best = (w, [a, b])
        if best:
            lines = best[1]
    return lines


def corner_mark(d, x, y, L, w, col):
    """The brand's viewfinder corner (top-right form)."""
    d.line([(x - L, y), (x, y)], fill=col, width=w)
    d.line([(x, y), (x, y + L)], fill=col, width=w)
    for px, py in ((x - L, y), (x, y), (x, y + L)):
        d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=col)


def make_slide(W, H, shot_path, lines, caption, opts, brand=False, fit=False):
    canvas = background(W, H)
    d = ImageDraw.Draw(canvas)
    head_f, sub_f = display(opts["head"]), text_font(opts["sub"])
    y = opts["top"]
    if brand:
        ic = Image.open(ICON).convert("RGB").resize((opts["icon"], opts["icon"]), Image.LANCZOS)
        r = rounded(ic, int(ic.width * 0.2237))
        canvas.paste(r, ((W - ic.width) // 2, y), r)
        y += ic.height + opts["gap"]
    for line in lines:
        d.text((W / 2, y), line, font=head_f, fill=PEARL, anchor="ma")
        y += int(opts["head"] * 1.10)
    y += int(opts["head"] * 0.16)
    for sl in wrap_text(d, caption, sub_f, W * 0.84):
        d.text((W / 2, y), sl, font=sub_f, fill=MIST, anchor="ma")
        y += int(opts["sub"] * 1.36)

    shot = Image.open(shot_path).convert("RGB")
    top = max(y + opts["shot_gap"], opts["min_shot_top"])
    if fit:
        sh = H - top - opts["fit_margin"]
        sw = int(sh * shot.width / shot.height)
        if sw > opts["shot_w"]:
            sw = opts["shot_w"]
            sh = int(sw * shot.height / shot.width)
        shot = shot.resize((sw, sh), Image.LANCZOS)
        framed = rounded(shot, opts["radius"])
        bottom = top + sh
    else:
        sw = opts["shot_w"]
        shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
        shot = shot.crop((0, 0, sw, min(shot.height, H - top)))
        framed = rounded(shot, opts["radius"], top_only=True)
        bottom = H + 40
    x = (W - sw) // 2
    # soft drop shadow and a hairline pearl rim (no glow: light is cold and edged)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, top + 24, x + sw, bottom + 40], opts["radius"], fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(opts["radius"] * 0.45))
    canvas.paste(shadow, (0, 0), shadow)
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([x - 3, top - 3, x + sw + 2, bottom + (opts["radius"] if not fit else 2)],
                                          opts["radius"] + 3, outline=PEARL + (60,), width=3)
    canvas.paste(rim, (0, 0), rim)
    canvas.paste(framed, (x, top), framed)
    # the brand corner, glacier, at the capture's upper-right
    corner_mark(ImageDraw.Draw(canvas), x + sw + opts["corner_off"], top - opts["corner_off"], opts["corner_len"],
                opts["corner_w"], GLACIER)
    return canvas


def run(argv, W, H, opts, ratio_name):
    if len(argv) < 3:
        sys.exit(f"Usage: python {Path(argv[0]).name} <folder-with-CI-pngs> <output-folder>\n"
                 f"Writes {W}x{H} {ratio_name} slides. Missing captures are skipped, never invented.")
    src, dst = Path(argv[1]), Path(argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    wrote, missing, n = [], [], 0
    for name, lines, caption in SLIDES:
        shot_path = src / f"{name}.png"
        if not shot_path.exists():
            missing.append(name)
            continue
        n += 1
        slide = make_slide(W, H, shot_path, lines, caption, opts, brand=name in BRAND_SLIDES, fit=name in FIT_SLIDES)
        out = dst / f"{n:02d}-{name}.png"
        slide.save(out, optimize=True)
        wrote.append(out.name)
        print("wrote", out)
    for name in missing:
        print("missing capture, slide skipped:", name)
    print(f"{len(wrote)} slides written, {len(missing)} skipped")
