"""Builds the static Clarivo site into website/clarivo/ (served at https://ecomswiftllc.github.io/clarivo/).

  python website/make_site_assets.py     # icons, og image, web copies of the sample photos
  python website/build_site.py           # pages

Pages: index.html, how-it-works/, privacy/, terms/, support/, sitemap.xml, robots.txt.
Privacy and terms are generated from website/legal/*.md (the DRAFT-NOTICE block is stripped).

Before/after examples: only real outputs of the app's own models may be shown. When they exist, put the pairs in
website/clarivo/assets/compare/ and describe them in website/compare/pairs.json:
  [{"before": "street-sign-before.jpg", "after": "street-sign-after.jpg", "title": "Unblur",
    "caption": "A copy of a street sign with added camera shake, after Unblur in Clarivo 1.0", "w": 1200, "h": 1600}]
Both images must have the same size and crop. With no pairs file the pages show the real sample inputs only.
Publishing: copy website/clarivo/ to /clarivo/ in the EcomswiftLLC/ecomswiftllc.github.io repo (see docs/store/website.md).
"""
import html
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "website" / "clarivo"
LEGAL = ROOT / "website" / "legal"
PAIRS = ROOT / "website" / "compare" / "pairs.json"

BASE = "https://ecomswiftllc.github.io/clarivo/"
UPDATED = "2026-11-25"
SITE_NAME = "Photo Enhancer HD: Clarivo"
SUPPORT_EMAIL = "support@ecomswiftllc.com"
FONTS = ('<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@500;600&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@500&display=swap">')

LOCK = ('<svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><rect x="2.5" y="7" width="11" height="7.5" rx="2" '
        'fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M5 7V5a3 3 0 0 1 6 0v2" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>')


def load_pairs():
    if PAIRS.exists():
        pairs = json.loads(PAIRS.read_text(encoding="utf-8"))
        return [p for p in pairs if (OUT / "assets" / "compare" / p["before"]).exists() and (OUT / "assets" / "compare" / p["after"]).exists()]
    return []


# ----------------------------------------------------------------------------- shell
def head(title, description, path, root="", extra=""):
    t, d = html.escape(title), html.escape(description)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{t}</title>
<meta name="description" content="{d}">
<link rel="canonical" href="{BASE + path}">
<meta name="theme-color" content="#081219">
<link rel="icon" href="{root}assets/favicon.svg" type="image/svg+xml">
<link rel="icon" href="{root}assets/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="{root}assets/apple-touch-icon.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="{html.escape(SITE_NAME)}">
<meta property="og:title" content="{t}">
<meta property="og:description" content="{d}">
<meta property="og:url" content="{BASE + path}">
<meta property="og:image" content="{BASE}assets/og-image.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="The Clarivo app icon and the name Clarivo, Photo Enhancer HD, next to three sample photos">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="{BASE}assets/og-image.png">
{FONTS}
<link rel="stylesheet" href="{root}assets/site.css">
{extra}</head>
<body>
<a class="skip" href="#main">Skip to content</a>
"""


def header(root, current=""):
    home = root or "./"

    def a(href, text, key):
        cur = ' aria-current="page"' if key == current else ""
        return f'<a href="{href}"{cur}>{text}</a>'
    return f"""<header class="site-header">
  <div class="wrap">
    <a class="brand" href="{home}"><img src="{root}assets/clarivo-mark.svg" alt="" width="32" height="32">Clarivo</a>
    <nav class="nav" aria-label="Main">
      {a(root + 'how-it-works/', 'How it works', 'how')}
      {a(home + '#private', 'Privacy', 'p')}
      {a(home + '#free', 'Free with ads', 'f')}
      {a(home + '#faq', 'Questions', 'q')}
      {a(root + 'support/', 'Support', 'support')}
    </nav>
  </div>
</header>
"""


def footer(root):
    home = root or "./"
    return f"""<footer class="site-footer">
  <div class="wrap">
    <div>
      <h2>Photo Enhancer HD: Clarivo</h2>
      <p>A free photo enhancer for iPhone and iPad. Your photos are processed on your device and never uploaded. Not on the App Store yet.</p>
    </div>
    <nav aria-label="Footer">
      <h2>Pages</h2>
      <ul>
        <li><a href="{home}">Home</a></li>
        <li><a href="{root}how-it-works/">How it works</a></li>
        <li><a href="{root}support/">Support</a></li>
        <li><a href="{root}privacy/">Privacy policy</a></li>
        <li><a href="{root}terms/">Terms of use</a></li>
      </ul>
    </nav>
    <div>
      <h2>Ecom Swift LLC</h2>
      <p>30 N Gould St #37906<br>Sheridan, WY 82801<br>United States</p>
      <p class="email">{SUPPORT_EMAIL}</p>
    </div>
    <p class="legalline">&copy; 2026 Ecom Swift LLC. Apple, iPhone, iPad and the App Store are trademarks of Apple Inc. Clarivo is not affiliated with Apple or Google. Sample photos: Pexels photographers (Pexels License) and The Metropolitan Museum of Art (Open Access, CC0).</p>
  </div>
</footer>
{COMPARE_JS}
</body>
</html>
"""


COMPARE_JS = """<script>
document.querySelectorAll('.compare input[type=range]').forEach(function (r) {
  var box = r.closest('.compare');
  function set() { box.style.setProperty('--pos', r.value + '%'); }
  r.addEventListener('input', set); set();
});
</script>"""


def compare_html(p, root):
    t = html.escape(p["title"])
    c = html.escape(p["caption"])
    return f"""<figure class="specimen">
  <div class="compare" style="--pos:50%">
    <img src="{root}assets/compare/{p['before']}" alt="Before: {c}" width="{p.get('w', 1200)}" height="{p.get('h', 1600)}">
    <div class="after"><img src="{root}assets/compare/{p['after']}" alt="After {t}: {c}"></div>
    <div class="handle" aria-hidden="true"></div>
    <span class="tag b">Before</span><span class="tag a">After {t}</span>
    <input type="range" min="0" max="100" value="50" aria-label="Move the divider between before and after">
  </div>
  <figcaption><span>{c}</span><span class="small">Real output of the app, same crop on both sides</span></figcaption>
</figure>"""


# ----------------------------------------------------------------------------- home
FAQ = [
    ("Is Clarivo really free?",
     "<p>Yes. There is no subscription, no in-app purchase and no watermark. Ads from Google AdMob pay for the app: a banner on the Home screen, and a short rewarded video before you save or share a result. You always see the finished photo first.</p>"),
    ("Are my photos uploaded anywhere?",
     "<p>No. Your photos are processed on your device and never uploaded. The AI models are built into the app and run on your iPhone or iPad, so Clarivo also works offline. Your photos are never shared with the ad network.</p>"),
    ("Can it fix any blurry photo?",
     "<p>It can make most photos look sharper and cleaner. Unblur reduces motion blur and camera shake, and Sharpen helps photos that are only a little soft. Heavy blur can improve, but detail that the camera never captured cannot be brought back, and no app can do that honestly.</p>"),
    ("How large can a photo get?",
     "<p>Upscale offers 2x, 4x and 8x. The result can be up to 8192 pixels on its long side. If a photo is too big for 8x, Clarivo reduces it first and tells you.</p>"),
    ("Are the colours of a colorized photo accurate?",
     "<p>They are an estimate. The colorize model adds natural-looking colour, but it cannot know the real colour of a coat or a car in a photo from 1900. Treat it as an interpretation, not a historical record.</p>"),
    ("Does Portrait change faces?",
     "<p>No. It finds faces and sharpens them with the same upscaling model used for the rest of the photo, then blends them back. It does not generate a new face.</p>"),
    ("Why am I asked to watch an ad?",
     "<p>Ads pay for the app. Before you save or share, the app offers a short video. A whole batch needs one ad, and saves in the 2 minutes after an ad need no other. If no ad is available, for example offline, the save goes ahead for free.</p>"),
    ("Does it need access to my photo library?",
     "<p>Not to open photos. You pick photos with the iOS photo picker or from Files, and Clarivo sees only what you choose. To save a result to Photos, it asks for add-only permission, which cannot read your library.</p>"),
    ("Which devices does it run on?",
     "<p>iPhone and iPad with iOS 17 or iPadOS 17 or later.</p>"),
    ("When can I download it?",
     "<p>Clarivo is not on the App Store yet, so there is no download link. This page will link to the App Store once the app is available.</p>"),
]


def jsonld():
    app = {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": SITE_NAME, "alternateName": "Clarivo",
           "url": BASE, "applicationCategory": "PhotographyApplication", "operatingSystem": "iOS 17.0 or later",
           "description": "A free photo enhancer for iPhone and iPad: AI upscale 2x, 4x and 8x, unblur, noise reduction, portrait sharpening, colorize and old-photo restore, processed on the device.",
           "image": BASE + "assets/icon-512.png", "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
           "publisher": {"@type": "Organization", "name": "Ecom Swift LLC"}}
    plain = lambda s: html.unescape(re.sub(r"<[^>]+>", "", s))
    faq = {"@context": "https://schema.org", "@type": "FAQPage",
           "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": plain(a)}} for q, a in FAQ]}
    return "".join(f'<script type="application/ld+json">{json.dumps(x)}</script>\n' for x in (app, faq))


TOOLS = [
    ("Upscale", "2x 4x 8x", "Enlarge a small or cropped photo with an AI model that adds fine, natural-looking texture as it scales."),
    ("Unblur", "", "Reduce motion blur and camera shake. Sharpen, with a strength slider, handles photos that are only a little soft."),
    ("Remove noise", "", "Clean up the grain of low light and high ISO, blended with the original to the strength you choose."),
    ("Portrait", "", "Find the faces in a photo and make them sharper, without inventing or changing them."),
    ("Colorize", "", "Add natural-looking colour to a black-and-white photo while keeping the full resolution of the original."),
    ("Restore", "", "Reduce scratches and dust, lift fading and remove the yellow cast of an old print."),
    ("Auto fix", "", "Balance light and colour in one tap, with a strength slider."),
    ("Batch", "", "Apply the same settings to many photos, with progress for each one and a cancel button."),
]

STRIP = [
    ("historic-building-lowres", "Small building photo", "600 px copy, for Upscale"),
    ("street-sign-motion-blur", "Shaken street sign", "copy with added shake, for Unblur"),
    ("tabby-cat-noisy", "Grainy cat", "copy with added noise, for Remove noise"),
    ("old-street-1864", "Street scene, 1864", "faded albumen print, for Restore"),
    ("old-portrait-1859", "Portrait, about 1859", "salted paper print, for Colorize"),
]


def build_index(pairs):
    title = "Photo Enhancer HD: Clarivo | Sharper, larger photos on iPhone"
    desc = ("Free photo enhancer for iPhone and iPad. AI upscale 2x, 4x and 8x, unblur, remove noise, sharpen portraits, "
            "colorize black-and-white photos and restore old prints. Your photos are processed on your device and never uploaded.")
    if pairs:
        visual = compare_html(pairs[0], "")
    else:
        visual = """<figure class="specimen">
          <div class="frame"><img src="assets/photos/hero-detail-nearest.png" width="640" height="800" alt="Ornate windows of a building facade from a 474 by 600 pixel photo, enlarged about six times without enhancement, so its square pixels and compression blocks show"></div>
          <span class="corner" aria-hidden="true"></span>
          <figcaption><span>A detail of a real <span class="chip readout">474 &times; 600 px</span> sample, enlarged with no enhancement</span><span>Clarivo can upscale the whole photo to <span class="readout">3792 &times; 4800</span></span></figcaption>
        </figure>"""
    tools = "\n".join(
        f'          <div><dt>{html.escape(n)}{f" <span class=readout>{r}</span>" if r else ""}</dt><dd>{html.escape(d)}</dd></div>'
        for n, r, d in TOOLS)
    strip = "\n".join(
        f'        <li><figure><img src="assets/photos/{f}.jpg" alt="{html.escape(t)}: {html.escape(c)}" decoding="async">'
        f'<figcaption><strong>{html.escape(t)}</strong>{html.escape(c)}</figcaption></figure></li>' for f, t, c in STRIP)
    faq = "\n".join(f'        <details><summary>{html.escape(q)}</summary><div class="answer">{a}</div></details>' for q, a in FAQ)
    body = head(title, desc, "", "", jsonld()) + header("", "") + f"""
<main id="main">
  <section class="hero" aria-labelledby="h1">
    <div class="wrap">
      <div>
        <h1 id="h1">Sharper, cleaner, larger photos.</h1>
        <p class="lede">Clarivo upscales photos 2x, 4x or 8x, reduces blur and noise, sharpens portraits, colorizes black-and-white photos and restores faded prints. All of it runs on your iPhone or iPad.</p>
        <p class="privacy-line">{LOCK}<span>Your photos are processed on your device and never uploaded.</span></p>
        <p class="status">Not on the App Store yet</p>
        <p class="small hero-note">There is no download link yet. See <a href="how-it-works/">how it works</a>, or ask a question on the <a href="support/">support page</a>.</p>
      </div>
      {visual}
    </div>
  </section>

  <section class="section" id="tools" aria-labelledby="h-tools">
    <div class="wrap">
      <h2 id="h-tools">Eight tools for sharper photos</h2>
      <div class="section-body">
        <dl class="tools">
{tools}
        </dl>
        <p>Every result opens in a before and after view: drag the divider, pinch to zoom both sides at once, or touch and hold to see the original. Export as JPG, PNG or HEIC at the original size, 2x, 4x, 8x or a size you set, and keep or remove the photo's metadata and location. No watermark.</p>
      </div>
    </div>
  </section>

  <section class="section band" aria-labelledby="h-samples">
    <div class="wrap">
      <h2 id="h-samples">Try it before you pick your own</h2>
      <div class="section-body">
        <p>Clarivo comes with sample photos. Some are genuinely old or soft; others are copies of sharp photos that we deliberately degraded, so you can see what each tool does. They are labelled as such.</p>
      </div>
    </div>
    <div class="wrap" style="padding-block: 0 64px; display: block;">
      <ul class="samples">
{strip}
      </ul>
      <p class="small" style="margin-top:16px">Photos from Pexels (Pexels License) and The Metropolitan Museum of Art (Open Access, CC0). <a href="how-it-works/">See every tool with its sample</a>.</p>
    </div>
  </section>

  <section class="section" id="private" aria-labelledby="h-private">
    <div class="wrap">
      <h2 id="h-private">Your photos stay on your device</h2>
      <div class="section-body">
        <p>Every model runs on your iPhone or iPad with Apple's Core ML. There is no account and no server that receives your pictures, and Clarivo runs no analytics of its own.</p>
        <ul class="checks">
          <li>You pick photos with the iOS photo picker or Files, so Clarivo sees only what you choose</li>
          <li>Saving to Photos uses add-only permission</li>
          <li>Works offline: the AI models are inside the app</li>
          <li>Remove location and other metadata when you export, if you want</li>
          <li>Recent results stay on your device and are cleared after 7 days</li>
        </ul>
        <p>The only outside service is the ad network, and it never receives your photos. The <a href="privacy/">privacy policy</a> explains what it collects.</p>
      </div>
    </div>
  </section>

  <section class="section band" id="free" aria-labelledby="h-free">
    <div class="wrap">
      <h2 id="h-free">Free, and paid for by ads</h2>
      <div class="section-body">
        <p>Clarivo has no subscription and no in-app purchase. Ads from Google AdMob pay for it.</p>
        <div class="split">
          <div>
            <h3>Where you see ads</h3>
            <ul>
              <li>A banner on the Home screen, never over your photo.</li>
              <li>A short video before you save or share. You see the finished result first, a batch needs one ad, and saves in the next 2 minutes need none.</li>
            </ul>
          </div>
          <div>
            <h3>When no ad is available</h3>
            <ul>
              <li>Saving goes ahead for free.</li>
              <li>This happens, for example, when you are offline.</li>
            </ul>
          </div>
        </div>
        <p>Where the law requires it, the app shows Google's consent form, and iOS asks whether the app may track you. You can say no and still use everything.</p>
      </div>
    </div>
  </section>

  <section class="section" id="faq" aria-labelledby="h-faq">
    <div class="wrap">
      <h2 id="h-faq">Questions</h2>
      <div class="section-body">
{faq}
      </div>
    </div>
  </section>
</main>
""" + footer("")
    (OUT / "index.html").write_text(body, encoding="utf-8")


# ----------------------------------------------------------------------------- how it works
HOW = [
    ("Upscale 2x, 4x or 8x", "historic-building-lowres", True,
     "A copy of a building photo reduced to 474 &times; 600 pixels.",
     "Choose 2x, 4x or 8x. The AI model works through the photo in small tiles, so even large photos stay smooth, and adds fine texture as it enlarges. 8x runs two passes and stops at 8192 pixels on the long side.",
     "Upscaling predicts plausible texture. It makes a photo larger and cleaner, but it is not the original detail of the scene."),
    ("Unblur and Sharpen", "street-sign-motion-blur", False,
     "A copy of a street sign photo with sideways camera shake added by us.",
     "Unblur reduces mild blur and camera shake with an on-device AI pass plus sharpening. Sharpen is a lighter tool with a strength slider for photos that are only a little soft.",
     "Heavy blur can improve, but detail the camera never captured cannot be brought back."),
    ("Remove noise", "tabby-cat-noisy", False,
     "A darker copy of a cat photo with sensor-style noise added by us.",
     "Clarivo cleans up grain and colour speckles, then blends the result with the original to the strength you choose, so fur and skin keep their texture.", ""),
    ("Portrait", "portrait-woman-lowres", True,
     "A small, slightly soft 800 px copy of a portrait.",
     "Clarivo finds the faces, enhances each one with the upscaling model and blends it back with a soft edge.",
     "It sharpens what is there. It does not generate a new face or change how someone looks."),
    ("Restore an old photo", "old-street-1864", False,
     "Street scene, Culpeper, Virginia, March 1864, by Andrew Joseph Russell. A genuinely faded albumen print.",
     "Restore reduces scratches and dust, lifts fading and removes the yellow cast of old prints. It is classical image processing, so it never invents content.", ""),
    ("Colorize black and white", "old-portrait-1859", False,
     "Portrait of a man in military regalia, about 1859, by Horatio Ross. A salted paper print with stains and fading.",
     "The colorize model estimates natural colours for the scene, and Clarivo applies them to the full-resolution original so no sharpness is lost.",
     "Colours are an estimate, not a historical record."),
]


def build_how(pairs):
    title = "How it works | Photo Enhancer HD: Clarivo"
    desc = "How Clarivo enhances photos on your iPhone or iPad: upscale, unblur, remove noise, portrait, restore and colorize, with the real sample photos and the honest limits of each tool."
    rows = []
    for name, img, pix, src, what, limit in HOW:
        lim = f'<p class="limit">{limit}</p>' if limit else ""
        rows.append(f"""        <div class="tool-row">
          <img class="{'pix' if pix else ''}" src="../assets/photos/{img}.jpg" alt="Sample input for {html.escape(name)}: {html.escape(re.sub('&times;', 'x', src))}" loading="lazy" decoding="async">
          <div>
            <h3>{name}</h3>
            <p>{what}</p>
            {lim}
            <p class="source">Sample input: {src}</p>
          </div>
        </div>""")
    if pairs:
        examples = "\n".join(compare_html(p, "../") for p in pairs)
        ex_section = f"""  <section class="section band" aria-labelledby="h-ex">
    <div class="wrap">
      <h2 id="h-ex">Before and after</h2>
      <div class="section-body" style="max-width:none">
        <p>These are real results from Clarivo's models on the sample photos, with the same crop on both sides. Drag the divider.</p>
{examples}
      </div>
    </div>
  </section>"""
    else:
        ex_section = ""
    body = head(title, desc, "how-it-works/", "../") + header("../", "how") + f"""
<main id="main">
  <section class="section" style="border-top:0" aria-labelledby="h1">
    <div class="wrap">
      <h1 id="h1" style="font-size:clamp(2rem,4.6vw,3rem)">How Clarivo works</h1>
      <div class="section-body">
        <p>Everything happens on your iPhone or iPad. Your photos are processed on your device and never uploaded.</p>
        <ol class="steps">
          <li><div><h3>Pick a photo</h3><p>Choose one or many from Photos or Files, or try a built-in sample.</p></div></li>
          <li><div><h3>Choose a tool</h3><p>Upscale, Unblur, Remove noise, Portrait, Colorize, Restore or Auto fix. A preview appears in seconds.</p></div></li>
          <li><div><h3>Compare</h3><p>Drag the divider, pinch to zoom both sides together, or touch and hold for the original.</p></div></li>
          <li><div><h3>Save or share</h3><p>Pick JPG, PNG or HEIC and a size. The full-resolution result is made, then saved to Photos or Files, or shared.</p></div></li>
        </ol>
      </div>
    </div>
  </section>

{ex_section}
  <section class="section" aria-labelledby="h-tools">
    <div class="wrap" style="display:block">
      <h2 id="h-tools" style="margin-bottom:32px">The tools and their samples</h2>
      <div class="tool-rows">
{chr(10).join(rows)}
      </div>
      <p class="small" style="margin-top:32px">Sample photos: Pexels photographers (Pexels License); the two historical prints from The Metropolitan Museum of Art (Open Access, CC0). Copies marked as degraded were made by Ecom Swift LLC from sharp originals.</p>
    </div>
  </section>
</main>
""" + footer("../")
    (OUT / "how-it-works").mkdir(exist_ok=True)
    (OUT / "how-it-works" / "index.html").write_text(body, encoding="utf-8")


# ----------------------------------------------------------------------------- support
SUPPORT = [
    ("How do I enhance a photo?",
     "<ol><li>On Home, tap a tool, then choose a photo from Photos or Files, or try a sample.</li><li>Pick the settings, such as 4x for Upscale, and wait for the preview.</li><li>Compare with the before and after view.</li><li>Tap Save to Photos, Save to Files or Share.</li></ol>"),
    ("The result still looks soft",
     "<p>Try Unblur for shake, then Sharpen with a higher strength. Very heavy blur, or a photo that was out of focus, can only improve a little: detail the camera never captured cannot be brought back. Starting from the original file, not a screenshot or a message attachment, gives the best result.</p>"),
    ("8x says the photo was reduced first",
     "<p>To keep your device responsive, results are limited to 8192 pixels on the long side and 48 megapixels. A large photo is reduced before the 8x pass so the result fits. Use 4x if you want to keep the original size as the starting point.</p>"),
    ("Processing is slow or stops",
     "<p>AI upscaling is heavy work, especially at 8x on older devices. Keep the app open until it finishes. If the device runs low on memory, Clarivo stops safely and tells you; try a smaller size or close other apps.</p>"),
    ("Why am I asked to watch an ad?",
     "<p>Ads pay for Clarivo. Before you save or share, the app offers a short video; a batch needs one ad, and saves in the next 2 minutes need none. If no ad is available, saving goes ahead for free.</p>"),
    ("I want to change my ad or tracking choice",
     "<p>Open Settings in the app and use Privacy choices where it appears. You can also change tracking in iOS Settings under Privacy and Security, then Tracking.</p>"),
    ("I saw an ad that seems wrong",
     "<p>Write to us with roughly when you saw it and what it showed. A screenshot helps. We block ad categories and advertisers through Google AdMob where we can.</p>"),
]


def build_support():
    title = "Support | Photo Enhancer HD: Clarivo"
    desc = "Get help with Clarivo: contact details and answers about enhancing photos, upscaling limits, ads and privacy."
    faq = "\n".join(f'          <details><summary>{html.escape(q)}</summary><div class="answer">{a}</div></details>' for q, a in SUPPORT)
    body = head(title, desc, "support/", "../") + header("../", "support") + f"""
<main id="main">
  <div class="page">
    <div class="wrap">
      <div class="doc">
        <h1>Support</h1>
        <p>Write to us and a person will read it. We reply by email.</p>
        <p class="contact-line">{SUPPORT_EMAIL}</p>
        <p class="small">Select the address to copy it into your mail app.</p>
        <p>A message gets answered faster when it includes your iPhone or iPad model and iOS version, the tool you used, and what happened. Please do not attach private photos unless we ask for one.</p>
        <p>Clarivo is not on the App Store yet, so support right now covers questions about the app before it is available.</p>
        <h2>Common questions</h2>
        <div>
{faq}
        </div>
        <h2>Company</h2>
        <p>Ecom Swift LLC<br>30 N Gould St #37906<br>Sheridan, WY 82801<br>United States</p>
        <p>Read the <a href="../privacy/">privacy policy</a> and the <a href="../terms/">terms of use</a>.</p>
      </div>
    </div>
  </div>
</main>
""" + footer("../")
    (OUT / "support").mkdir(exist_ok=True)
    (OUT / "support" / "index.html").write_text(body, encoding="utf-8")


# ----------------------------------------------------------------------------- legal (markdown -> html)
URL_RE = re.compile(r"(https?://[^\s<)]+)")
MAIL_RE = re.compile(r"([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})")


def inline(text):
    t = html.escape(text, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)

    def url(m):
        u, trail = m.group(1), ""
        while u and u[-1] in ".,;":
            trail, u = u[-1] + trail, u[:-1]
        return f'<a href="{u}" rel="noopener">{u}</a>{trail}'
    t = URL_RE.sub(url, t)
    parts = re.split(r"(<a .*?</a>)", t)
    return "".join(p if p.startswith("<a ") else MAIL_RE.sub(r'<span class="email">\1</span>', p) for p in parts)


def md_to_html(md):
    md = re.sub(r"<!-- DRAFT-NOTICE-START -->.*?<!-- DRAFT-NOTICE-END -->", "", md, flags=re.S)
    out, para, items = [], [], []
    title, meta_open, seen_h2 = "", False, False

    def flush():
        nonlocal para, items
        if para:
            out.append("<p>" + "<br>".join(inline(p) for p in para) + "</p>")
            para = []
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items = []
    for raw in md.splitlines():
        line = raw.rstrip()
        if line.startswith("# "):
            flush()
            title = line[2:].strip()
            out.append(f"<h1>{html.escape(title)}</h1>")
        elif line.startswith("## "):
            flush()
            if meta_open:
                out.append("</div>"); meta_open = False
            seen_h2 = True
            out.append(f"<h2>{inline(line[3:].strip())}</h2>")
        elif line.startswith("- "):
            if para:
                out.append("<p>" + "<br>".join(inline(p) for p in para) + "</p>"); para = []
            items.append(line[2:].strip())
        elif not line.strip():
            flush()
        elif line.startswith("**") and title and not seen_h2:
            if not meta_open:
                out.append('<div class="meta">'); meta_open = True
            out.append("<p>" + inline(line) + "</p>")
        else:
            if meta_open:
                out.append("</div>"); meta_open = False
            para.append(line.strip())
    flush()
    if meta_open:
        out.append("</div>")
    return title, "\n".join(out)


def build_legal(src, folder, page, desc):
    _, content = md_to_html((LEGAL / src).read_text(encoding="utf-8"))
    body = head(f"{page} | {SITE_NAME}", desc, folder + "/", "../") + header("../") + f"""
<main id="main">
  <div class="page">
    <div class="wrap">
      <article class="doc">
{content}
      </article>
    </div>
  </div>
</main>
""" + footer("../")
    (OUT / folder).mkdir(exist_ok=True)
    (OUT / folder / "index.html").write_text(body, encoding="utf-8")


def build_misc():
    urls = ["", "how-it-works/", "support/", "privacy/", "terms/"]
    xml = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    xml += [f"  <url><loc>{BASE}{u}</loc><lastmod>{UPDATED}</lastmod></url>" for u in urls]
    xml.append("</urlset>")
    (OUT / "sitemap.xml").write_text("\n".join(xml) + "\n", encoding="utf-8")
    (OUT / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {BASE}sitemap.xml\n", encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "assets").mkdir(exist_ok=True)
    shutil.copy(ROOT / "website" / "site.css", OUT / "assets" / "site.css")
    pairs = load_pairs()
    build_index(pairs)
    build_how(pairs)
    build_support()
    build_legal("privacy-policy.md", "privacy", "Privacy Policy",
                "How Clarivo handles information: photos are processed on your device and never uploaded, there is no account, and ads come from Google AdMob with your consent where required.")
    build_legal("terms-of-use.md", "terms", "Terms of Use",
                "The terms for using Photo Enhancer HD: Clarivo, a free photo enhancer supported by ads.")
    build_misc()
    print("site built in", OUT, "| before/after pairs:", len(pairs))


if __name__ == "__main__":
    main()
