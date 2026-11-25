"""Download real test photos from Wikimedia Commons (public domain / free licences) for quality checks.

Usage: python coreml/fetch_samples.py build/samples
Resolves each title through the Commons API (URL, licence, author), downloads a 1600 px rendition,
and writes build/samples/sources.json. Missing titles are skipped (logged); we need at least
4 colour photos and 2 historical black-and-white photos.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

UA = {"User-Agent": "model-quality-ci/1.0 (python-urllib)"}

COLOR = [
    "File:President Barack Obama.jpg",
    "File:Official portrait of Barack Obama.jpg",
    "File:Neil Armstrong pose.jpg",
    "File:Tunnel View, Yosemite Valley, Yosemite NP - Diliff.jpg",
    "File:Cat03.jpg",
    "File:Felis catus-cat on snow.jpg",
    "File:Fronalpstock big.jpg",
    "File:Times Square, New York City (HDR).jpg",
    "File:Golden Gate Bridge as seen from Battery East.jpg",
    "File:Sunflower from Silesia2.jpg",
]
BW = [
    "File:Lange-MigrantMother02.jpg",
    "File:First flight2.jpg",
    "File:Abraham Lincoln O-77 matte collodion print.jpg",
    "File:Albert Einstein Head.jpg",
]
MAX_COLOR = 6
MAX_BW = 3


def strip_html(s):
    return re.sub(r"<[^>]+>", "", s or "").strip()


def query(titles):
    params = {
        "action": "query", "format": "json", "prop": "imageinfo",
        "iiprop": "url|size|extmetadata", "iiurlwidth": "1600", "titles": "|".join(titles),
    }
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        data = json.load(r)
    out = {}
    norm = {n["from"]: n["to"] for n in data["query"].get("normalized", [])}
    for p in data["query"]["pages"].values():
        if "imageinfo" not in p:
            continue
        ii = p["imageinfo"][0]
        m = ii.get("extmetadata", {})
        out[p["title"]] = {
            "title": p["title"],
            "page": ii.get("descriptionurl"),
            "download": ii.get("thumburl") or ii.get("url"),
            "orig_size": [ii.get("width"), ii.get("height")],
            "license": strip_html(m.get("LicenseShortName", {}).get("value")),
            "license_url": m.get("LicenseUrl", {}).get("value"),
            "artist": strip_html(m.get("Artist", {}).get("value"))[:200],
            "credit": strip_html(m.get("Credit", {}).get("value"))[:200],
        }
    return out, norm


def slug(title):
    s = title.split(":", 1)[1].rsplit(".", 1)[0]
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_")[:40].lower()


def main(out):
    sources = []
    for group, titles, cap in (("color", COLOR, MAX_COLOR), ("bw", BW, MAX_BW)):
        os.makedirs(os.path.join(out, group), exist_ok=True)
        info, norm = query(titles)
        n = 0
        seen = set()
        for t in titles:
            t2 = norm.get(t, t)
            meta = info.get(t2)
            if not meta or meta["download"] in seen:
                print("skip (missing):", t)
                continue
            if n >= cap:
                break
            seen.add(meta["download"])
            name = slug(t2) + ".jpg"
            dst = os.path.join(out, group, name)
            for attempt in range(3):
                try:
                    with urllib.request.urlopen(urllib.request.Request(meta["download"], headers=UA), timeout=120) as r:
                        open(dst, "wb").write(r.read())
                    break
                except Exception as e:
                    print("retry", t, e)
                    time.sleep(3)
            else:
                continue
            meta.update({"group": group, "file": f"{group}/{name}"})
            sources.append(meta)
            n += 1
            print("got", group, name, meta["license"])
    with open(os.path.join(out, "sources.json"), "w") as f:
        json.dump(sources, f, indent=2)
    nc = sum(s["group"] == "color" for s in sources)
    nb = sum(s["group"] == "bw" for s in sources)
    if nc < 4 or nb < 2:
        raise SystemExit(f"not enough samples: color={nc} bw={nb}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/samples")
