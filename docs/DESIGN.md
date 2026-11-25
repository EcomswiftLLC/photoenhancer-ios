# Clarivo - brand and design system

Hand-over for the APP agent (Swift theme in `Sources/Theme`, namespace `CV`), the website and the store slides.
Owner: BRAND agent. Every value below is final for v1; if the app needs a new token, add it here first.

## 1. Brand in one line

**Clarivo** (store name "Photo Enhancer HD: Clarivo", subtitle "Unblur, Upscale & Sharpen") makes photos look sharper,
cleaner and larger, on the device, in a few taps. The brand idea is **focus snapping in**: the moment a soft, blocky image
resolves into a crisp one. Everything visual is cool, clean and precise, like looking through cold, clear water.

Distinct from the siblings: Aperta = brass on graphite, Lumotion = champagne glow on ink. Clarivo = **glacier aqua on deep
blue ink**. No gold, no warm glow, no serif display.

## 2. Colour (dark first; the app is dark only)

A cool, blue-tinted ink (never neutral black) keeps photos honest and makes the aqua feel like light through glass.

| Token (Swift `CV.Palette.*`) | Hex | Use |
|---|---|---|
| `ink` | `#081219` | App background, launch background |
| `deep` | `#0F1C26` | First surface: cards, sheets, tab/tool bars |
| `raised` | `#172836` | Raised surface: pressed rows, chips, slider tracks |
| `line` | `#FFFFFF` at 9% | Hairlines and outlines |
| `lineStrong` | `#FFFFFF` at 16% | Focused field outline, secondary button border |
| `pearl` | `#EEF5F7` | Primary text (17.1:1 on ink) |
| `mist` | `#9DB3BF` | Secondary text (8.7:1 on ink, 6.9:1 on raised) |
| `faint` | `#6B8494` | Tertiary/disabled text, large text or icons only (4.8:1 on ink; never body text on `raised`) |
| `glacier` | `#7FE6D7` | THE accent: primary button fill, selected state, slider thumb ring, progress, links (12.8:1 on ink) |
| `glacierDeep` | `#47C9BA` | Lower stop of the primary button gradient, pressed accent, chart/progress track end |
| `frost` | `#CFF7F1` | Highlight only: the compare-slider handle line, focus "snap" flash (1 frame, 160 ms) |
| `onGlacier` | `#04201D` | Text/icons on glacier (11.6:1) |
| `success` | `#6FD39A` | Saved/finished confirmation icon |
| `warning` | `#F4C56A` | Cap applied, colour photo detected, low memory |
| `danger` | `#FF8A80` | Errors, destructive actions |

Rules
- One accent. `glacier` appears at most once per screen as a filled element (the primary action). Everything else is
  pearl/mist on ink surfaces.
- Gradients: only the primary button (`glacier` -> `glacierDeep`, top to bottom) and the icon. No decorative gradient
  washes behind content.
- Photos sit on `ink` with no tint, no glow, no vignette: the result must be judged honestly.
- Status colours are always paired with an icon and words (never colour alone).
- Accent colour asset `AccentColor` = `#7FE6D7`; `LaunchBackground` = `#081219`.

Light palette (website and documents only; the app has no light mode):
paper `#F4F8F9`, text `#0B1A24`, secondary `#4A5F6C` (6.3:1), accent-for-text `#0A6E65` (5.7:1), accent fill stays
`#7FE6D7` with `#04201D` text.

## 3. Type

App: the system families, chosen deliberately.
- Display and titles: **SF Pro Display, semibold, tracking -0.4 (titles) / -0.8 (display)**. A crisp grotesk, not a serif:
  sharpness is the product.
- Body and controls: SF Pro Text (`.body`, `.callout`), regular; buttons `.headline` semibold.
- Numbers that are data (scale 2x/4x/8x, megapixels, pixel sizes, percent, file size): **SF Mono, medium,
  monospaced digits**. This is the one place mono is used, because these are real readouts.

| Swift `CV.Font.*` | Spec | Use |
|---|---|---|
| `display(34)` | SF Pro, 34 pt, semibold, tracking -0.8, Dynamic Type scaled, max 1.5x | Home title, result headline |
| `title(22)` | SF Pro, 22 pt, semibold, tracking -0.4, scaled, max 1.6x | Section titles, sheet titles |
| `headline` | `.headline` semibold | Buttons, row titles |
| `body` | `.body` | Paragraphs |
| `callout` | `.callout` | Tool descriptions |
| `label` | `.footnote` medium | Chips, small labels (sentence case, never all caps) |
| `caption` | `.caption` | Footnotes, credits |
| `readout` | `.callout`, `design: .monospaced`, medium, monospacedDigit | 4x, 3024 x 4032, 12.2 MP, 84% |

All text supports Dynamic Type; layouts must not truncate at AX1. Never all caps. Sentence case everywhere.

Website: **Instrument Sans** (Google Fonts, 500/600 headings, tracking -0.02em) for headings and **Inter** fallback
to system-ui for body; readouts in **JetBrains Mono** 500. Body 17 px / 1.6, max line 68 ch.

## 4. Space, radius, elevation, motion

Spacing (`CV.Space`): `xs 4`, `s 8`, `m 16`, `l 24`, `xl 32`, `xxl 48`. Screen side margin 20 (iPhone) / 32 (iPad
regular width); iPad content max width 760 for forms and settings, the compare view uses the full width.

Radius (`CV.Radius`, all `.continuous`): `chip 10`, `control 14` (buttons, fields, segmented), `tile 18` (photo
thumbnails, tool tiles), `panel 24` (sheets, the compare canvas frame). Radius follows hierarchy: a tile inside a panel
uses the smaller radius.

Elevation: no drop shadows on dark. Separate layers with surface colour (`ink` -> `deep` -> `raised`) and hairlines.
Floating controls over a photo use `.ultraThinMaterial` with `ink` at 55% plus a `line` hairline.

Touch targets >= 44 x 44 pt (buttons 48 high). Focus ring (iPad keyboard): 2 pt `glacier`.

Motion: one signature moment, the **focus snap**: when a preview result arrives, the result crossfades in over 220 ms
while a single `frost` hairline sweeps once along the compare divider. Everything else uses `.easeOut(0.12-0.2 s)` and
responds to touch only. Respect Reduce Motion (crossfade only, no sweep). Progress uses a determinate bar where tiles
are counted ("Tile 12 of 48"), never an endless spinner when progress is known.

## 5. Iconography and imagery

- SF Symbols, `.regular` weight, `hierarchical` rendering in `pearl`, selected = `glacier`. Suggested: upscale
  `arrow.up.left.and.arrow.down.right`, unblur `camera.metering.spot`, denoise `circle.dotted`, portrait
  `person.crop.square`, colorize `paintpalette`, restore `photo.badge.checkmark`, auto fix `wand.and.stars`, sharpen
  `triangle.lefthalf.filled`, batch `square.stack.3d.up`, export `square.and.arrow.up`.
- App icon: a photo tile whose lower-left half is a coarse pixel mosaic and upper-right half is smooth and crisp,
  split by a bright glacier diagonal, with a viewfinder corner mark. Generated by `tools/make_icon.py`.
- Sample photos are real, licensed photographs (see `docs/store/photo-credits.md`). Never placeholder art, never AI art.

## 6. Components (map to the Lumotion shell, renamed LM -> CV)

- Primary button: glacier gradient fill, `onGlacier` text, radius `control`, 48 high. One per screen.
- Secondary button: clear fill, `lineStrong` 1 pt border, pearl text. Quiet button: glacier text, no fill.
- Tool tile (Home grid): `deep` fill, radius `tile`, SF Symbol 24 pt + title (`headline`) + one-line callout in mist.
  Selected: 1.5 pt glacier border, no fill change.
- Scale chooser (2x/4x/8x): segmented, `raised` track, selected segment glacier fill + `onGlacier` readout text.
- Compare canvas: photo edge to edge in a `panel` frame; divider 2 pt pearl with a 28 pt round handle (`ink` 70% +
  `frost` ring); labels "Before" / "After" as small material chips at the top corners.
- Banner ad (Home only) sits at the bottom inside a `deep` strip with a `line` hairline above, never overlapping content.

## 7. Voice and tone

Calm, precise, plain. Short sentences, active verbs, sentence case, no exclamation marks, no hype words
("magic", "revolutionary", "insane", "perfect").

- Name actions by outcome: "Enhance", "Unblur", "Remove noise", "Colorize", "Restore", "Save to Photos".
  The same verb carries through: button "Save to Photos" -> toast "Saved to Photos".
- Progress says what is happening: "Enhancing tile 12 of 48", "Colorizing".
- Errors say what happened and what to do: "This photo is too large to upscale 8x. Try 4x, or we can reduce it
  first." No apologies, no vague "Something went wrong".
- Empty state is an invitation: "Pick a photo to enhance" + "Try a sample".

## 8. Honest-copy rules (mandatory in app, store, website, ads)

1. Say **enhance, sharpen, upscale, reduce blur, reduce noise, colorize, restore** (restore = fix fading, scratches
   and dust). Never say "recover lost detail", "restore details that were never there", "reconstruct faces",
   "4K from any photo" or "perfect".
2. Upscaling makes a photo larger and cleaner-looking; the AI predicts plausible fine texture. Copy may say
   "sharper, larger photos"; it may not say the result is the true original detail.
3. Unblur "reduces motion blur and camera shake"; heavy blur may only improve a little. Say so in help text.
4. Colorize "adds natural-looking colour"; colours are an estimate, not the historical truth.
5. Portrait enhance "sharpens faces"; it does not invent or change faces. Never "face restoration" / "reconstruction".
6. Privacy line, use verbatim: **"Your photos are processed on your device and never uploaded."**
   (Ads: "Ads are shown by Google AdMob; your photos are never shared with them.")
7. Before/after images in the store and on the website must be real outputs of the app's own models on the real
   sample photos, with the same crop and zoom for both halves. Degraded inputs must be labelled as such in the credits.
8. No fake ratings, download counts or "No. 1" claims. No competitor names.

## 9. Swift skeleton for the APP agent

```swift
enum CV {
    enum Palette {
        static let ink = Color(hex: 0x081219), deep = Color(hex: 0x0F1C26), raised = Color(hex: 0x172836)
        static let line = Color.white.opacity(0.09), lineStrong = Color.white.opacity(0.16)
        static let pearl = Color(hex: 0xEEF5F7), mist = Color(hex: 0x9DB3BF), faint = Color(hex: 0x6B8494)
        static let glacier = Color(hex: 0x7FE6D7), glacierDeep = Color(hex: 0x47C9BA), frost = Color(hex: 0xCFF7F1)
        static let onGlacier = Color(hex: 0x04201D)
        static let success = Color(hex: 0x6FD39A), warning = Color(hex: 0xF4C56A), danger = Color(hex: 0xFF8A80)
    }
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 32, xxl: CGFloat = 48 }
    enum Radius { static let chip: CGFloat = 10, control: CGFloat = 14, tile: CGFloat = 18, panel: CGFloat = 24 }
}
```
Nav bar title colour `#EEF5F7`, tint `#7FE6D7`. Status bar light content.
