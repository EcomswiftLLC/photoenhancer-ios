# Clarivo website

Live at https://ecomswiftllc.github.io/clarivo/ (home, how-it-works/, support/, privacy/, terms/, sitemap.xml, robots.txt).

- Sources: `website/build_site.py` (pages), `website/make_site_assets.py` (icons, og image, web copies of the samples),
  `website/site.css`, `website/legal/*.md` (privacy policy and terms; DRAFT notice stripped on build; lawyer review open).
- Build: `python tools/make_icon.py && python website/make_site_assets.py && python website/build_site.py` -> `website/clarivo/`.
- Publish: clone `EcomswiftLLC/ecomswiftllc.github.io` to a temp folder OUTSIDE this repo, replace its `/clarivo/`
  folder with `website/clarivo/`, commit, push. GitHub Pages serves it within a minute or two. Touch nothing else there
  (`app-ads.txt` at the root is shared by all apps).
- Before/after: only real outputs of the app's models. Put pairs in `website/clarivo/assets/compare/` and list them in
  `website/compare/pairs.json` (format in the build script docstring); the home hero and how-it-works page switch to a
  compare slider automatically. Until then the hero shows a real low-resolution sample detail enlarged with no
  enhancement, honestly labelled.
- App Store URLs: support https://ecomswiftllc.github.io/clarivo/support/, privacy https://ecomswiftllc.github.io/clarivo/privacy/,
  marketing https://ecomswiftllc.github.io/clarivo/
- When the App Store id exists, replace the "Not on the App Store yet" status and FAQ answer with the store link.
