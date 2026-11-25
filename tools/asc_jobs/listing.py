"""Fills the App Store Connect listing for Clarivo from docs/store/listing/*.txt.

Run from CI: python tools/asc.py job tools/asc_jobs/listing.py   (see .github/workflows/asc.yml, mode=job)
Each step prints what it did and keeps going if one step fails, so one run shows every problem at once.
Does NOT submit for review.
"""
import json
import os
from pathlib import Path

from asc import api, pages

APP_ID = os.environ.get("ASC_APP_ID", "")
ROOT = Path(".")
LIST = ROOT / "docs" / "store" / "listing"


def text(name):
    return (LIST / name).read_text(encoding="utf-8").strip()


def step(title):
    print("\n== " + title)


def first(path):
    status, data = api("GET", path)
    if status != 200 or not data or not data.get("data"):
        return None
    d = data["data"]
    return d[0] if isinstance(d, list) else d


# ---- content rights
step("content rights")
st, _ = api("PATCH", f"/v1/apps/{APP_ID}", {"data": {"type": "apps", "id": APP_ID, "attributes": {"contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}}})
print("status", st)

# ---- app info: categories, localisation
step("app info and categories")
infos = list(pages(f"/v1/apps/{APP_ID}/appInfos"))
info = infos[0] if infos else None
if info:
    info_id = info["id"]
    st, _ = api("PATCH", f"/v1/appInfos/{info_id}", {"data": {"type": "appInfos", "id": info_id, "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": "PHOTO_AND_VIDEO"}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": "GRAPHICS_AND_DESIGN"}},
    }}})
    print("categories status", st)
    locs = list(pages(f"/v1/appInfos/{info_id}/appInfoLocalizations"))
    loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), locs[0] if locs else None)
    if loc:
        st, _ = api("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": {
            "name": text("name.txt"),
            "subtitle": text("subtitle.txt"),
            "privacyPolicyUrl": "https://ecomswiftllc.github.io/clarivo/privacy/",
        }}})
        print("info localization status", st)

    step("age rating")
    status, data = api("GET", f"/v1/appInfos/{info_id}/ageRatingDeclaration")
    if status == 200 and data:
        rid = data["data"]["id"]
        none = "NONE"
        attrs = {
            "alcoholTobaccoOrDrugUseOrReferences": none, "contests": none, "gambling": False, "gamblingSimulated": none,
            "gunsOrOtherWeapons": none, "horrorOrFearThemes": none, "matureOrSuggestiveThemes": none,
            "medicalOrTreatmentInformation": none, "profanityOrCrudeHumor": none, "sexualContentGraphicAndNudity": none,
            "sexualContentOrNudity": none, "violenceCartoonOrFantasy": none, "violenceRealistic": none,
            "violenceRealisticProlongedGraphicOrSadistic": none, "unrestrictedWebAccess": False,
            "userGeneratedContent": False, "messagingAndChat": False, "advertising": True,
            "healthOrWellnessTopics": False, "socialMedia": False, "parentalControls": False, "ageAssurance": False, "lootBox": False,
        }
        st, _ = api("PATCH", f"/v1/ageRatingDeclarations/{rid}", {"data": {"type": "ageRatingDeclarations", "id": rid, "attributes": attrs}})
        print("age rating status", st)
else:
    print("no app info found")

# ---- version
step("version page")
versions = list(pages(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS"))
version = versions[0] if versions else None
if version:
    vid = version["id"]
    print("version", version["attributes"].get("versionString"), version["attributes"].get("appStoreState"))
    st, _ = api("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid, "attributes": {"copyright": "2026 Ecom Swift LLC"}}})
    print("copyright status", st)
    vlocs = list(pages(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations"))
    vloc = next((l for l in vlocs if l["attributes"]["locale"] == "en-US"), vlocs[0] if vlocs else None)
    if vloc:
        st, _ = api("PATCH", f"/v1/appStoreVersionLocalizations/{vloc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"], "attributes": {
            "description": text("description.txt"),
            "keywords": text("keywords.txt"),
            "promotionalText": text("promo.txt"),
            "marketingUrl": "https://ecomswiftllc.github.io/clarivo/",
            "supportUrl": "https://ecomswiftllc.github.io/clarivo/support/",
        }}})
        print("version localization status", st)

    step("app review details")
    status, data = api("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail", quiet=True)
    detail = {
        "contactFirstName": "Mubashir", "contactLastName": "Hassan", "contactPhone": "+1 631 251 1767",
        "contactEmail": "support@ecomswiftllc.com", "demoAccountRequired": False, "notes": text("review-notes.txt"),
    }
    if status == 200 and data and data.get("data"):
        did = data["data"]["id"]
        st, _ = api("PATCH", f"/v1/appStoreReviewDetails/{did}", {"data": {"type": "appStoreReviewDetails", "id": did, "attributes": detail}})
    else:
        st, _ = api("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": detail, "relationships": {
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    print("review details status", st)

# ---- price: free
step("price (free)")
status, data = api("GET", f"/v1/apps/{APP_ID}/appPricePoints?filter[territory]=USA&limit=200")
free_point = None
if status == 200 and data:
    for p in data["data"]:
        if p["attributes"].get("customerPrice") in ("0.0", "0", "0.00"):
            free_point = p["id"]
            break
print("free price point", free_point)
if free_point:
    body = {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": APP_ID}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${p1}"}]},
        }},
        "included": [{"type": "appPrices", "id": "${p1}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free_point}}}}],
    }
    st, _ = api("POST", "/v1/appPriceSchedules", body)
    print("price status", st)

# ---- availability: every region except China mainland (it needs AIGC and security assessment filings)
step("availability")
territories = [t["id"] for t in pages("/v1/territories?limit=200")]
print(len(territories), "territories")
included = []
rel = []
for i, t in enumerate(territories):
    key = "${t%d}" % i
    rel.append({"type": "territoryAvailabilities", "id": key})
    included.append({"type": "territoryAvailabilities", "id": key, "attributes": {"available": t != "CHN"},
                      "relationships": {"territory": {"data": {"type": "territories", "id": t}}}})
body = {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True}, "relationships": {
    "app": {"data": {"type": "apps", "id": APP_ID}}, "territoryAvailabilities": {"data": rel}}}, "included": included}
st, _ = api("POST", "/v2/appAvailabilities", body)
print("availability status", st)
print("\ndone")
