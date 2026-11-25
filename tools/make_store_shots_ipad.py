"""Builds the Clarivo App Store screenshots for the iPad 13 inch display (2064 x 2752) from real CI captures.

Usage: python tools/make_store_shots_ipad.py <folder-with-CI-pngs> <output-folder>
  e.g. gh run download <run-id> --repo EcomswiftLLC/photoenhancer-ios -n store-ipad -D ci/store-ipad
       python tools/make_store_shots_ipad.py ci/store-ipad design/store/ipad13

Inputs: the PNGs of the `store-ipad` artifact (home.png, enhance-result.png, compare.png, ...).
Layout and copy live in tools/store_shots_common.py. Missing captures are skipped and listed, never invented.
Needs Pillow and numpy.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store_shots_common as common  # noqa: E402

W, H = 2064, 2752
OPTS = dict(head=156, sub=70, top=170, icon=190, gap=64, shot_w=1600, shot_gap=120, min_shot_top=800, radius=64, fit_margin=80, corner_off=40, corner_len=110, corner_w=12)

if __name__ == "__main__":
    common.run(sys.argv, W, H, OPTS, "iPad 13 inch")
