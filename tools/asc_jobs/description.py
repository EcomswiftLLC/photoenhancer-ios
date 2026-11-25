"""Updates only the en-US version texts (description, keywords, promo text) from docs/store/listing/*.txt."""
from pathlib import Path

from asc import api, pages

APP_ID = "6839258428"
L = Path("docs/store/listing")
t = lambda n: (L / n).read_text(encoding="utf-8").strip()
vid = list(pages(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS"))[0]["id"]
loc = next(l for l in pages(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations") if l["attributes"]["locale"] == "en-US")
st, _ = api("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {
    "description": t("description.txt"), "keywords": t("keywords.txt"), "promotionalText": t("promo.txt")}}})
print("version texts status", st)
