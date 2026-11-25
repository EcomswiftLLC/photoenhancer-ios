"""Shared layout code for the App Store screenshot scripts (make_store_shots.py, make_store_shots_ipad.py).

Every store slide is a REAL in-app capture (from the CI artifacts `screenshots` and `screenshots-ipad`) placed on the
dark "projection room" background under a short headline. Nothing in a slide is drawn UI: if a capture is missing,
the slide is skipped and reported, never invented.

Capture names are the `-lmScreen` names used by .github/workflows/ios.yml (onboarding, home, home-filled, settings,
editor-presets, editor-flow, editor-video, editor-camera, editor-depth, editor-effects, editor-overlays, editor-looks,
editor-text, editor-audio, editor-canvas, editor-timing, editor-layers, export).
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

INK = (10, 12, 19)
NAVY = (22, 26, 44)
PAPER = (237, 234, 227)
MIST = (200, 202, 209)
GLOW = (242, 196, 141)
VIOLET = (126, 132, 232)

# (capture name, headline lines, supporting line). Copy is limited to what the app does (docs/PRODUCT-SPEC.md).
SLIDES = [
    ("editor-flow", ["Paint the flow,", "draw the way."], "Brush an area, draw arrows, set the speed."),
    ("editor-video", ["Cinemagraphs", "from your video."], "Choose a loop, freeze a frame, paint the motion."),
    ("editor-depth", ["Depth that moves", "with the camera."], "3D parallax between subject and background."),
    ("editor-overlays", ["Twenty overlays,", "rain to fireworks."], "Stack rain, snow, fireflies, sparkles and more."),
    ("editor-presets", ["18 Magic presets,", "one tap each."], "Starting points you can change completely."),
    ("editor-effects", ["Bring the whole", "picture to life."], "Ripples, waves, wind sway, heat haze, shimmer."),
    ("editor-camera", ["Move the camera", "through the photo."], "Zoom, pan, drift, rotate and handheld shake."),
    ("editor-looks", ["24 looks and", "adjust dials."], "Plus film grain, text and stickers."),
    ("export", ["Export MP4,", "GIF or still."], "No watermark. Sizes up to what your device supports."),
    ("home-filled", ["Everything stays", "on your device."], "No account. Free, with ads."),
]


# Captures whose bottom edge carries pinned controls are shown whole instead of bleeding off the slide.
FIT_SLIDES = {"export"}


def font(names, size):
    for n in names:
        for base in ("C:/Windows/Fonts/", "/usr/share/fonts/truetype/dejavu/", "/System/Library/Fonts/Supplemental/"):
            p = Path(base) / n
            if p.exists():
                return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def serif(size):
    return font(["georgia.ttf", "DejaVuSerif.ttf"], size)


def sans(size):
    return font(["segoeui.ttf", "DejaVuSans.ttf"], size)


def background(W, H):
    """Ink-navy room with a soft apricot beam from the top (the projector) and a faint violet wash low on the right."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    base = np.zeros((H, W, 3), np.float32)
    t = (yy / H)[..., None]
    base += np.array(INK, np.float32) * (1 - t) + np.array((8, 9, 15), np.float32) * t
    # beam: a wide cone whose brightness falls off with distance from the top centre
    cx = W / 2
    spread = (0.20 + 0.55 * (yy / H)) * W * 0.62
    cone = np.exp(-(((xx - cx) / spread) ** 2) * 1.6) * np.exp(-(yy / (H * 0.42)) ** 1.5)
    base += cone[..., None] * (np.array(GLOW, np.float32) - base) * 0.20
    # source hot spot
    hot = np.exp(-(((xx - cx) / (W * 0.20)) ** 2 + (yy / (H * 0.07)) ** 2))
    base += hot[..., None] * (np.array(GLOW, np.float32) - base) * 0.30
    # violet counterweight
    vi = np.exp(-(((xx - W * 0.92) / (W * 0.5)) ** 2 + ((yy - H * 0.95) / (H * 0.30)) ** 2))
    base += vi[..., None] * (np.array(VIOLET, np.float32) - base) * 0.10
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")


def rounded_top(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height + radius], radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def wrap_text(draw, text, fnt, max_w):
    """Greedy wrap, then rebalance two-line results so no line is a lone word (no orphans)."""
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


def make_slide(W, H, shot_path, lines, caption, opts, brand=False, fit=False):
    canvas = background(W, H)
    d = ImageDraw.Draw(canvas)
    head_f, sub_f = serif(opts["head"]), sans(opts["sub"])
    y = opts["top"]
    if brand:
        ic = Image.open(ICON).convert("RGB").resize((opts["icon"], opts["icon"]), Image.LANCZOS)
        m = Image.new("L", ic.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, ic.width - 1, ic.height - 1], int(ic.width * 0.2237), fill=255)
        canvas.paste(ic, ((W - ic.width) // 2, y), m)
        y += ic.height + opts["gap"]
    for line in lines:
        d.text((W / 2, y), line, font=head_f, fill=PAPER, anchor="ma")
        y += int(opts["head"] * 1.14)
    y += int(opts["head"] * 0.10)
    for sl in wrap_text(d, caption, sub_f, W * 0.86):
        d.text((W / 2, y), sl, font=sub_f, fill=MIST, anchor="ma")
        y += int(opts["sub"] * 1.38)
    # the capture: by default a rounded top bleeding off the bottom edge (a phone rising into frame). With fit=True the
    # whole capture is shown, scaled to the free height, for screens whose bottom edge carries controls (Export).
    shot = Image.open(shot_path).convert("RGB")
    top = max(y + opts["shot_gap"], opts["min_shot_top"])
    if fit:
        margin = opts["fit_margin"]
        sw = int((H - top - margin) * shot.width / shot.height)
        sh = H - top - margin
        shot = shot.resize((sw, sh), Image.LANCZOS)
        mask = Image.new("L", shot.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], opts["radius"], fill=255)
        framed = shot.convert("RGBA")
        framed.putalpha(mask)
        bottom = top + sh
    else:
        sw = opts["shot_w"]
        shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
        shot = shot.crop((0, 0, sw, min(shot.height, H - top)))
        framed = rounded_top(shot, opts["radius"])
        bottom = H + 40
    x = (W - sw) // 2
    halo = Image.new("L", (W, H), 0)
    ImageDraw.Draw(halo).rounded_rectangle([x - 6, top - 6, x + sw + 6, bottom + 6], opts["radius"] + 6, fill=255)
    halo_g = halo.filter(ImageFilter.GaussianBlur(opts["radius"] * 0.9)).point(lambda v: int(v * 0.30))
    canvas.paste(Image.new("RGB", (W, H), GLOW), (0, 0), halo_g)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, top + 30, x + sw, bottom + 40], opts["radius"], fill=(0, 0, 0, 190))
    shadow = shadow.filter(ImageFilter.GaussianBlur(opts["radius"] * 0.5))
    canvas.paste(shadow, (0, 0), shadow)
    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([x - 4, top - 4, x + sw + 3, bottom + (opts["radius"] if not fit else 3)],
                                           opts["radius"] + 4, outline=GLOW + (150,), width=4)
    canvas.paste(edge, (0, 0), edge)
    canvas.paste(framed, (x, top), framed)
    return canvas.convert("RGB")


def run(argv, W, H, opts, ratio_name):
    if len(argv) < 3:
        sys.exit(f"Usage: python {Path(argv[0]).name} <folder-with-CI-pngs> <output-folder>\n"
                 f"Writes {W}x{H} {ratio_name} slides. Missing captures are skipped, never invented.")
    src, dst = Path(argv[1]), Path(argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    wrote, missing = [], []
    n = 0
    for name, lines, caption in SLIDES:
        shot_path = src / f"{name}.png"
        if not shot_path.exists():
            missing.append(name)
            continue
        n += 1
        slide = make_slide(W, H, shot_path, lines, caption, opts, brand=(name == "home-filled"), fit=(name in FIT_SLIDES))
        out = dst / f"{n:02d}-{name}.png"
        slide.save(out, optimize=True)
        wrote.append(out.name)
        print("wrote", out)
    for name in missing:
        print("missing capture, slide skipped:", name)
    print(f"{len(wrote)} slides written, {len(missing)} skipped")
