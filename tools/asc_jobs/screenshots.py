"""Uploads the store slides to App Store Connect (iPhone 6.9 inch and iPad 13 inch, 10 each).

Run from CI: python tools/asc.py job tools/asc_jobs/screenshots.py
Slides come from design/store/iphone69/*.png and design/store/ipad13/*.png (made by tools/make_store_shots*.py from CI captures).
Replaces whatever is in those two screenshot sets, so it is safe to re-run. Does NOT submit for review.
"""
import hashlib
from pathlib import Path

import requests

from asc import api, pages

APP_ID = "6839258428"
SETS = [
    ("APP_IPHONE_67", Path("design/store/iphone69")),
    ("APP_IPAD_PRO_3GEN_129", Path("design/store/ipad13")),
]

versions = list(pages(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS"))
vid = versions[0]["id"]
vlocs = list(pages(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations"))
loc = next(l for l in vlocs if l["attributes"]["locale"] == "en-US")
loc_id = loc["id"]
print("localization", loc_id)

existing = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in pages(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")}

for display_type, folder in SETS:
    files = sorted(folder.glob("*.png"))
    print("\n==", display_type, folder, len(files), "files")
    if not files:
        print("no slides, skipping")
        continue
    set_id = existing.get(display_type)
    if set_id:
        for shot in list(pages(f"/v1/appScreenshotSets/{set_id}/appScreenshots")):
            api("DELETE", f"/v1/appScreenshots/{shot['id']}")
        print("cleared existing set", set_id)
    else:
        status, data = api("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display_type},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
        if status not in (200, 201):
            print("could not create the set", status)
            continue
        set_id = data["data"]["id"]
        print("created set", set_id)

    shot_ids = []
    for f in files:
        blob = f.read_bytes()
        status, data = api("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(blob)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
        if status not in (200, 201):
            print("reserve failed", f.name, status)
            continue
        shot = data["data"]
        for op in shot["attributes"]["uploadOperations"]:
            chunk = blob[op["offset"]: op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
            r = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=300)
            if r.status_code >= 300:
                print("chunk upload failed", f.name, r.status_code, r.text[:200])
        st, _ = api("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {
            "type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
        print("uploaded", f.name, st)
        shot_ids.append(shot["id"])

    # Keep the file-name order (01..10) as the display order.
    if shot_ids:
        st, _ = api("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
                    {"data": [{"type": "appScreenshots", "id": i} for i in shot_ids]})
        print("order status", st)

    for shot in pages(f"/v1/appScreenshotSets/{set_id}/appScreenshots"):
        state = shot["attributes"].get("assetDeliveryState", {})
        print(shot["attributes"]["fileName"], state.get("state"), [e.get("description") for e in state.get("errors", [])])
print("\ndone")
