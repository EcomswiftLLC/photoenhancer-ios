"""Builds the Clarivo website image assets into website/clarivo/assets/.

Writes: favicon.svg, clarivo-mark.svg (vector version of the app icon's "Cold Resolve" mark), favicon-32.png,
apple-touch-icon.png (180), icon-512.png, og-image.png (1200x630) and photos/<name>.jpg (web copies of the bundled
sample photos, long side 1400 px, plus 2x-nearest "as is" crops of the low-resolution samples).
Usage: python website/make_site_assets.py   (run tools/make_icon.py first; needs Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "website" / "clarivo" / "assets"
ICON = ROOT / "Sources" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
SAMPLES = ROOT / "Sources" / "Resources" / "Samples"

SITE_PHOTOS = ["historic-building-lowres", "street-sign-motion-blur", "tabby-cat-noisy", "portrait-woman-lowres",
               "old-street-1864", "old-portrait-1859", "kingfisher", "lake-autumn", "portrait-man", "portrait-soft-focus"]

INK, GLACIER, FROST, PEARL, MIST = "#081219", "#7FE6D7", "#CFF7F1", "#EEF5F7", "#9DB3BF"


def mark_svg(bg=True, label="Clarivo"):
    """100-unit SVG of the mark: tile with a mosaic lower-left half, smooth upper-right half, glacier cut, corner."""
    t0, t1, r = 19.0, 81.0, 11.5
    n = 6
    step = (t1 - t0) / n
    cells = []
    # cell colours sampled from the icon's scene (top to bottom), mosaic only below the diagonal
    rows = ["#1E4A60", "#2A6878", "#2E6E7C", "#24505E", "#163442", "#2A5F6C"]
    for j in range(n):
        for i in range(n):
            if i <= j:   # lower-left triangle incl. diagonal cells (they are clipped by the cut below)
                x, y = t0 + i * step, t0 + j * step
                cells.append(f'<rect x="{x + 0.35:.2f}" y="{y + 0.35:.2f}" width="{step - 0.7:.2f}" height="{step - 0.7:.2f}" fill="{rows[j]}"/>')
    lower = "".join(cells)
    title = f'role="img" aria-label="{label}"><title>{label}</title>' if label else 'aria-hidden="true">'
    bgrect = f'<rect width="100" height="100" rx="22.4" fill="{INK}"/>' if bg else ""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" {title}
<defs>
<clipPath id="cvT"><rect x="{t0}" y="{t0}" width="{t1 - t0}" height="{t1 - t0}" rx="{r}"/></clipPath>
<clipPath id="cvLo"><path d="M{t0} {t0} L{t1} {t1} L{t0} {t1} Z"/></clipPath>
<linearGradient id="cvSky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#122E46"/><stop offset=".55" stop-color="#287484"/><stop offset="1" stop-color="#8FDCD0"/></linearGradient>
</defs>
{bgrect}
<g clip-path="url(#cvT)">
<rect x="{t0}" y="{t0}" width="{t1 - t0}" height="{t1 - t0}" fill="url(#cvSky)"/>
<circle cx="62.4" cy="39.5" r="5.3" fill="{FROST}"/>
<path d="M{t0} 60 C30 52 36 50 44 54 S58 46 64 49 S76 54 {t1} 52 L{t1} {t1} L{t0} {t1} Z" fill="#224E60"/>
<path d="M{t0} 66 C34 64 44 58 54 60 S70 66 {t1} 63 L{t1} {t1} L{t0} {t1} Z" fill="#0C2230"/>
<rect x="{t0}" y="{t0}" width="{t1 - t0}" height="{t1 - t0}" fill="{INK}" clip-path="url(#cvLo)"/>
<g clip-path="url(#cvLo)">{lower}</g>
<path d="M{t0 + 2} {t0 + 2} L{t1 - 2} {t1 - 2}" stroke="{GLACIER}" stroke-opacity=".35" stroke-width="3.2" stroke-linecap="round"/>
<path d="M{t0 + 2} {t0 + 2} L{t1 - 2} {t1 - 2}" stroke="{FROST}" stroke-width="1.1" stroke-linecap="round"/>
</g>
<rect x="{t0 + .3}" y="{t0 + .3}" width="{t1 - t0 - .6}" height="{t1 - t0 - .6}" rx="{r}" fill="none" stroke="#fff" stroke-opacity=".16" stroke-width=".6"/>
<path d="M76 13 H87 V24" fill="none" stroke="{GLACIER}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M13 76 V87 H24" fill="none" stroke="#345C68" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
"""


def rounded(im, radius):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def font(size, bold=False):
    for f in (["C:/Windows/Fonts/seguisb.ttf", "C:/Windows/Fonts/segoeuib.ttf"] if bold else ["C:/Windows/Fonts/segoeui.ttf"]) + \
             ["/System/Library/Fonts/SFNS.ttf", "DejaVuSans.ttf"]:
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()


def og_image(icon):
    W, H = 1200, 630
    im = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(im)
    # right: three real sample photos as a strip
    photos = ["old-street-1864", "kingfisher", "historic-building"]
    x = 640
    for i, p in enumerate(photos):
        ph = Image.open(SAMPLES / f"{p}.jpg").convert("RGB")
        w, h = 170, 470
        s = max(w / ph.width, h / ph.height)
        ph = ph.resize((int(ph.width * s) + 1, int(ph.height * s) + 1), Image.LANCZOS)
        ph = ph.crop(((ph.width - w) // 2, (ph.height - h) // 2, (ph.width - w) // 2 + w, (ph.height - h) // 2 + h))
        r = rounded(ph, 18)
        im.paste(r, (x + i * 182, 80), r)
    ic = rounded(icon.resize((132, 132), Image.LANCZOS), 30)
    im.paste(ic, (72, 80), ic)
    d.text((72, 250), "Clarivo", font=font(76, True), fill=PEARL)
    d.text((72, 352), "Photo Enhancer HD", font=font(36), fill=GLACIER)
    d.text((72, 410), "Upscale, unblur, colorize and restore,", font=font(28), fill=MIST)
    d.text((72, 448), "on your iPhone and iPad.", font=font(28), fill=MIST)
    d.text((72, 520), "Your photos never leave your device.", font=font(24), fill=PEARL)
    im.save(OUT / "og-image.png", optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "photos").mkdir(exist_ok=True)
    (OUT / "favicon.svg").write_text(mark_svg(True), encoding="utf-8")
    (OUT / "clarivo-mark.svg").write_text(mark_svg(True), encoding="utf-8")
    icon = Image.open(ICON).convert("RGB")
    icon.resize((32, 32), Image.LANCZOS).save(OUT / "favicon-32.png")
    icon.resize((180, 180), Image.LANCZOS).save(OUT / "apple-touch-icon.png")
    icon.resize((512, 512), Image.LANCZOS).save(OUT / "icon-512.png", optimize=True)
    og_image(icon)
    # hero detail: a 100 x 125 px region of the real 474 x 600 sample, enlarged 6.4x with nearest neighbour (no enhancement)
    lo = Image.open(SAMPLES / "historic-building-lowres.jpg").convert("RGB")
    det = lo.crop((150, 250, 250, 375)).resize((640, 800), Image.NEAREST)
    det.save(OUT / "photos" / "hero-detail-nearest.png", optimize=True)
    for p in SITE_PHOTOS:
        ph = Image.open(SAMPLES / f"{p}.jpg").convert("RGB")
        if max(ph.size) > 1400:
            s = 1400 / max(ph.size)
            ph = ph.resize((round(ph.width * s), round(ph.height * s)), Image.LANCZOS)
        ph.save(OUT / "photos" / f"{p}.jpg", quality=82, optimize=True, progressive=True)
    print("assets written to", OUT)


if __name__ == "__main__":
    main()
