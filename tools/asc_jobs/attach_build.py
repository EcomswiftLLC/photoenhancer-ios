"""Attaches the newest processed build to the 1.0 version. Does NOT submit for review."""
from asc import api, pages

APP_ID = "6839258428"
versions = list(pages(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS"))
vid = versions[0]["id"]
status, data = api("GET", f"/v1/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=5")
for b in (data or {}).get("data", []):
    a = b["attributes"]
    print("build", a.get("version"), a.get("processingState"), a.get("uploadedDate"), "expired" if a.get("expired") else "", "nonExemptEncryption=", a.get("usesNonExemptEncryption"))
valid = [b for b in (data or {}).get("data", []) if b["attributes"].get("processingState") == "VALID" and not b["attributes"].get("expired")]
if not valid:
    print("no processed build yet")
else:
    b = valid[0]
    st, _ = api("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
    print("attached build", b["attributes"]["version"], "status", st)
