"""Re-checks readiness, sets manual release and submits version 1.0 for App Review (reviewSubmissions flow)."""
import sys
from asc import api, pages

APP_ID = "6839258428"
vers = list(pages(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&include=build"))
v = vers[0]
vid = v["id"]
print("version", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
st, bd = api("GET", f"/v1/appStoreVersions/{vid}/build")
b = (bd or {}).get("data")
print("build", b and (b["attributes"]["version"], b["attributes"]["processingState"], b["attributes"]["expired"]))
ok = bool(b) and b["attributes"]["processingState"] == "VALID" and not b["attributes"]["expired"]

loc = next(l for l in pages(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations") if l["attributes"]["locale"] == "en-US")
a = loc["attributes"]
for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl"):
    print(k, "set" if a.get(k) else "MISSING")
    ok = ok and bool(a.get(k))
for s in pages(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets"):
    shots = list(pages(f"/v1/appScreenshotSets/{s['id']}/appScreenshots"))
    states = [x["attributes"].get("assetDeliveryState", {}).get("state") for x in shots]
    print("screenshots", s["attributes"]["screenshotDisplayType"], len(shots), sorted(set(states)))
    ok = ok and len(shots) == 10 and all(x in ("COMPLETE", "UPLOAD_COMPLETE") for x in states)

subs = list(pages(f"/v1/apps/{APP_ID}/reviewSubmissions"))
print("existing review submissions", [(x["id"], x["attributes"]["state"]) for x in subs])
ok = ok and not subs
if not ok:
    print("NOT READY, nothing submitted")
    sys.exit(0)

st, _ = api("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid, "attributes": {"releaseType": "MANUAL"}}})
print("release type MANUAL status", st)
st, d = api("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"}, "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
print("create submission", st)
sid = d["data"]["id"]
st, _ = api("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}}, "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
print("add item", st)
st, d = api("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
print("submit", st, "submission id", sid, "state", d and d["data"]["attributes"]["state"])
vs = list(pages(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS"))[0]
print("version state now", vs["attributes"]["appStoreState"], "release", vs["attributes"].get("releaseType"))
