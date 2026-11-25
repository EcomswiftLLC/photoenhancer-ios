"""Builds the Clarivo App Store screenshots for the iPhone 6.9 inch display (1320 x 2868) from real CI captures.

Usage: python tools/make_store_shots.py <folder-with-CI-pngs> <output-folder>
  e.g. gh run download <run-id> --repo EcomswiftLLC/photoenhancer-ios -n store-iphone -D ci/store-iphone
       python tools/make_store_shots.py ci/store-iphone design/store/iphone69

Inputs: the PNGs of the `store-iphone` artifact (home.png, enhance-result.png, compare.png, ...).
Layout and copy live in tools/store_shots_common.py. Missing captures are skipped and listed, never invented.
Needs Pillow and numpy.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store_shots_common as common  # noqa: E402

W, H = 1320, 2868
OPTS = dict(head=124, sub=56, top=180, icon=150, gap=56, shot_w=1080, shot_gap=110, min_shot_top=760, radius=96, fit_margin=80, corner_off=34, corner_len=86, corner_w=10)

if __name__ == "__main__":
    common.run(sys.argv, W, H, OPTS, "iPhone 6.9 inch")
