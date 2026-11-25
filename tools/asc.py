"""App Store Connect API helper for CI (the API key only exists in GitHub secrets).

Usage in a workflow (needs PyJWT, cryptography, requests; env ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH):
  python tools/asc.py call GET /v1/apps?filter[bundleId]=com.ecomswift.photoenhancer
  python tools/asc.py call POST /v1/bundleIds '{"data": {...}}'
  python tools/asc.py job tools/asc_jobs/some_job.py        (the job file may `from asc import api, ...`)
Prints JSON. Never prints the key or the token.
"""
import json
import os
import sys
import time
from pathlib import Path

import jwt
import requests

BASE = "https://api.appstoreconnect.apple.com"


def token():
    key = Path(os.environ["ASC_KEY_PATH"]).read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def api(method, path, body=None, ok=(200, 201, 202, 204), quiet=False):
    """Calls the API. Returns (status, json or None). Raises nothing for HTTP errors, prints them."""
    url = path if path.startswith("http") else BASE + path
    headers = {"Authorization": "Bearer " + token(), "Content-Type": "application/json"}
    r = requests.request(method, url, headers=headers, data=json.dumps(body) if body is not None else None, timeout=120)
    try:
        data = r.json() if r.text else None
    except ValueError:
        data = None
    if r.status_code not in ok and not quiet:
        print("HTTP", r.status_code, method, path)
        print(json.dumps(data, indent=2)[:4000] if data else r.text[:2000])
    return r.status_code, data


def pages(path):
    """Follows `links.next` and yields every item of a list endpoint."""
    url = path
    while url:
        status, data = api("GET", url)
        if status != 200 or not data:
            return
        for item in data.get("data", []):
            yield item
        url = (data.get("links") or {}).get("next")


def main(argv):
    if len(argv) >= 3 and argv[0] == "call":
        method, path = argv[1].upper(), argv[2]
        body = json.loads(argv[3]) if len(argv) > 3 and argv[3].strip() else None
        status, data = api(method, path, body, quiet=True)
        print("HTTP", status)
        print(json.dumps(data, indent=2)[:60000] if data else "")
        return 0 if status < 400 else 1
    if len(argv) >= 2 and argv[0] == "job":
        sys.path.insert(0, str(Path(__file__).parent))
        code = Path(argv[1]).read_text()
        exec(compile(code, argv[1], "exec"), {"__name__": "__job__"})
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
