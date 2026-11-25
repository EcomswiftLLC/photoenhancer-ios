"""Download the upstream weights (never committed) and verify sha256.

Usage: python coreml/fetch_weights.py build/weights
Each weight lists sources in preference order; the sha256 is fixed, so a mirror can only be used
if it is byte-identical to the official file (the NAFNet HuggingFace mirror was checked against the
official Google Drive file on 2026-11-25: identical sha256).
"""
import hashlib
import json
import os
import subprocess
import sys
import urllib.request

WEIGHTS = {
    "realesr-general-x4v3.pth": {
        "sha256": "8dc7edb9ac80ccdc30c3a5dca6616509367f05fbc184ad95b731f05bece96292",
        "sources": [
            ("url", "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth"),
        ],
    },
    "NAFNet-GoPro-width32.pth": {
        "sha256": "19394e6155d12ef6371d1d57496f87f0ec88f92bdffa27c0792690722d5d1a5c",
        "sources": [
            # official link from megvii-research/NAFNet README (Google Drive)
            ("gdrive", "1Fr2QadtDCEXg6iwWX8OzeZLbHOx2t5Bj"),
            # byte-identical HuggingFace mirrors (same sha256 as the official file)
            ("url", "https://huggingface.co/nyanko7/nafnet-models/resolve/main/NAFNet-GoPro-width32.pth"),
            ("url", "https://huggingface.co/mikestealth/nafnet-models/resolve/main/NAFNet-GoPro-width32.pth"),
        ],
    },
    "ddcolor_paper_tiny.pth": {
        "sha256": "81dd643904f4664c3718513e3320ae3db0c567f0d3e18398606659adee7bfc17",
        "sources": [
            ("url", "https://huggingface.co/piddnad/DDColor-models/resolve/main/ddcolor_paper_tiny.pth"),
        ],
    },
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(kind, src, dst):
    if kind == "url":
        req = urllib.request.Request(src, headers={"User-Agent": "curl/8"})
        with urllib.request.urlopen(req, timeout=300) as r, open(dst, "wb") as f:
            while True:
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
    elif kind == "gdrive":
        subprocess.run([sys.executable, "-m", "gdown", "--quiet", src, "-O", dst], check=True, timeout=600)


def main(out):
    os.makedirs(out, exist_ok=True)
    used = {}
    for name, spec in WEIGHTS.items():
        dst = os.path.join(out, name)
        if os.path.exists(dst) and sha256(dst) == spec["sha256"]:
            used[name] = {"source": "cache", "sha256": spec["sha256"]}
            continue
        ok = False
        for kind, src in spec["sources"]:
            try:
                fetch(kind, src, dst)
                got = sha256(dst)
                if got == spec["sha256"]:
                    used[name] = {"source": f"{kind}:{src}", "sha256": got}
                    ok = True
                    print(f"OK {name} from {kind}:{src}")
                    break
                print(f"sha256 mismatch {name} from {src}: {got}")
            except Exception as e:  # try the next source
                print(f"failed {name} from {kind}:{src}: {e}")
        if not ok:
            raise SystemExit(f"could not fetch {name}")
    with open(os.path.join(out, "weights-sources.json"), "w") as f:
        json.dump(used, f, indent=2)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/weights")
