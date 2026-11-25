# Sample photo credits (Clarivo)

All sample photos in `Sources/Resources/Samples/` are real photographs. Retrieved 2026-11-25. Machine-readable copy for
the app's credits screen: `Sources/Resources/Samples/credits.json`. Gallery metadata: `samples.json`.

Sources and licences
- **Pexels** (https://www.pexels.com), Pexels License (https://www.pexels.com/license/): free to use, including
  commercially, no attribution required, modification allowed. Downloaded from images.pexels.com at 2400 px wide, long
  side then capped at 2400 px and recompressed as JPEG quality 85.
- **The Metropolitan Museum of Art Open Access** (https://www.metmuseum.org/policies/image-resources): images of
  public-domain works marked Open Access are released under Creative Commons Zero (CC0). The two historical prints
  were downloaded from images.metmuseum.org (original files) and recompressed as JPEG quality 88. They are genuine
  19th-century photographs with real fading, stains and foxing; nothing was added.

| File | What it is | Credit | Source page | Licence | Pixels | Bytes |
|---|---|---|---|---|---|---|
| historic-building-lowres.jpg | Degraded copy of historic-building.jpg (see below) | Dmitry Alexandrovich, Pexels (degraded copy made by Ecom Swift LLC) | https://www.pexels.com/photo/photo-of-a-historic-building-8327163/ | Pexels License | 474x600 | 44140 |
| street-sign-motion-blur.jpg | Degraded copy of street-sign.jpg (see below) | Diogo Miranda, Pexels (degraded copy made by Ecom Swift LLC) | https://www.pexels.com/photo/street-sign-pole-26974689/ | Pexels License | 1067x1600 | 98920 |
| tabby-cat-noisy.jpg | Degraded copy of tabby-cat.jpg (see below) | Samuel Sweet, Pexels (degraded copy made by Ecom Swift LLC) | https://www.pexels.com/photo/a-close-up-shot-of-a-cat-6145891/ | Pexels License | 1600x1417 | 859371 |
| portrait-woman-lowres.jpg | Degraded copy of portrait-woman.jpg (see below) | Pedro H. Novais, Pexels (degraded copy made by Ecom Swift LLC) | https://www.pexels.com/photo/portrait-of-woman-with-braided-hair-outdoors-38866875/ | Pexels License | 800x533 | 31681 |
| old-street-1864.jpg | Original | Andrew Joseph Russell (1864), via The Metropolitan Museum of Art, object 302354, The Met Open Access | https://www.metmuseum.org/art/collection/search/302354 | Public domain (CC0), The Metropolitan Museum of Art Open Access | 1841x1413 | 590904 |
| old-portrait-1859.jpg | Original | Horatio Ross (about 1859), via The Metropolitan Museum of Art, object 288085, The Met Open Access | https://www.metmuseum.org/art/collection/search/288085 | Public domain (CC0), The Metropolitan Museum of Art Open Access | 1636x2093 | 600595 |
| portrait-soft-focus.jpg | Original | Ali Ramazan Çiftçi, Pexels | https://www.pexels.com/photo/empty-swimming-pool-13127462/ | Pexels License | 1600x2400 | 521665 |
| portrait-man.jpg | Original | Noorain Saleem, Pexels | https://www.pexels.com/photo/an-elderly-bearded-man-smiling-11905784/ | Pexels License | 1600x2400 | 802054 |
| kingfisher.jpg | Original | Siegfried Poepperl, Pexels | https://www.pexels.com/photo/close-up-shot-of-a-kingfisher-14810091/ | Pexels License | 2400x1589 | 298749 |
| lake-autumn.jpg | Original | Gio Spigo, Pexels | https://www.pexels.com/photo/scenic-autumn-view-of-tovel-lake-in-trentino-41238366/ | Pexels License | 2400x1600 | 732187 |
| historic-building.jpg | Original | Dmitry Alexandrovich, Pexels | https://www.pexels.com/photo/photo-of-a-historic-building-8327163/ | Pexels License | 1898x2400 | 794697 |
| street-sign.jpg | Original | Diogo Miranda, Pexels | https://www.pexels.com/photo/street-sign-pole-26974689/ | Pexels License | 1600x2400 | 249271 |
| tabby-cat.jpg | Original | Samuel Sweet, Pexels | https://www.pexels.com/photo/a-close-up-shot-of-a-cat-6145891/ | Pexels License | 2400x2125 | 711558 |
| portrait-woman.jpg | Original | Pedro H. Novais, Pexels | https://www.pexels.com/photo/portrait-of-woman-with-braided-hair-outdoors-38866875/ | Pexels License | 2400x1600 | 373594 |

## Degraded copies (honest labelling)

These four files were made by Ecom Swift LLC from the sharp originals above with `design/samples/make_samples.py`,
so that before/after demonstrations have a known ground truth. Store slides and the website must call them
"a low-resolution copy", "a copy with added camera shake" or "a copy with added noise", never a real customer photo.

| File | Made from | Processing |
|---|---|---|
| historic-building-lowres.jpg | historic-building.jpg | Downscaled to 600 px long side (bilinear), JPEG quality 40 |
| street-sign-motion-blur.jpg | street-sign.jpg | Scaled to 1600 px, 25 px horizontal box motion blur, JPEG quality 88 |
| tabby-cat-noisy.jpg | tabby-cat.jpg | Scaled to 1600 px, exposure x0.8, Gaussian luminance noise (sigma 14) + colour noise (sigma 7) |
| portrait-woman-lowres.jpg | portrait-woman.jpg | Downscaled to 800 px, 1.2 px Gaussian blur, JPEG quality 55 |

Genuinely imperfect originals (not edited by us): `portrait-soft-focus.jpg` (photographer's own out-of-focus shot),
`old-street-1864.jpg` and `old-portrait-1859.jpg` (faded historical prints).

## Caveats
- People: `portrait-woman.jpg`, `portrait-man.jpg` and `portrait-soft-focus.jpg` show identifiable adults. The Pexels
  License allows commercial use but Pexels gives **no model-release information**. Use them in the app gallery and in
  neutral before/after demonstrations only; do not imply the person endorses Clarivo, and do not put them in paid ads.
  No minors appear in any sample.
- `portrait-man.jpg` has blurred passers-by in the background (not identifiable).
- `street-sign.jpg` shows generic street names ("Bank St", "West Main St"), no brand marks.
- The Met prints show historical people (a soldier, 1859; figures on a street, 1864); CC0, no restrictions.
- The old prints are sepia-toned rather than neutral grey.
