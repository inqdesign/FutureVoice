#!/usr/bin/env python3
"""Submit a version that `beta.sh` already uploaded to App Review.

What `beta.sh` stops short of: it uploads to TestFlight, and App Store
Connect then wants the version made, the build attached, the notes pasted
and the submission sent — four screens by hand. This does the four:

  1. waits for build <build> of <version> to finish processing (VALID),
  2. creates the App Store version (or reuses one still being prepared),
  3. attaches the build and writes `whatsNew` from
     fastlane/metadata/<locale>/release_notes.txt for every locale on file,
  4. opens a review submission with that version and submits it.

Release type is AFTER_APPROVAL: the version goes live when Apple approves it.
The update sheet still waits on `./scripts/beta.sh released` after that.

Dry run by default; `--send` does it.

    scripts/asc-submit.py 1.0.10 61           # plan only
    scripts/asc-submit.py 1.0.10 61 --send    # do it
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6792794655"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALES = {"en-US": "en-US", "en-GB": "en-US", "ko": "ko"}  # the store's English is en-GB


def token() -> str:
    key_dir = os.path.expanduser("~/.appstoreconnect/private_keys")
    keys = [f for f in os.listdir(key_dir) if f.startswith("AuthKey_") and f.endswith(".p8")]
    if not keys:
        sys.exit(f"no App Store Connect key in {key_dir}")
    key_path = os.path.join(key_dir, keys[0])
    kid = keys[0][len("AuthKey_"):-len(".p8")]
    iss = open(os.path.expanduser("~/.appstoreconnect/issuer_id")).read().strip()

    def b64(raw: bytes) -> str:
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64(json.dumps({"iss": iss, "iat": now, "exp": now + 1200,
                              "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing = f"{header}.{payload}".encode()
    # openssl signs to DER; JOSE wants raw r||s, each left-padded to 32 bytes.
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                         input=signing, capture_output=True, check=True).stdout
    parsed = subprocess.run(["openssl", "asn1parse", "-inform", "DER"],
                            input=der, capture_output=True, check=True).stdout.decode()
    ints = [ln.split(":")[-1].strip() for ln in parsed.splitlines() if "INTEGER" in ln]
    sig = b"".join(bytes.fromhex(i.rjust(64, "0")) for i in ints)
    return f"{header}.{payload}.{b64(sig)}"


TOKEN = token()


def call(method: str, path: str, body=None):
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:600]
        raise RuntimeError(f"{method} {url.split('?')[0]} → {e.code} {detail}") from None


def notes(locale_dir: str) -> str:
    return open(os.path.join(ROOT, "fastlane/metadata", locale_dir, "release_notes.txt")).read().strip()


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    version, build_no = args
    send = "--send" in sys.argv

    # 1. The build, processed.
    build = None
    for _ in range(90):
        d = call("GET", f"/builds?filter[app]={APP_ID}&filter[version]={build_no}"
                        f"&filter[preReleaseVersion.version]={version}&limit=1")
        if d["data"]:
            build = d["data"][0]
            state = build["attributes"]["processingState"]
            print(f"build {version} ({build_no}): {state}")
            if state == "VALID":
                break
            if state in ("FAILED", "INVALID"):
                sys.exit("build failed processing")
        else:
            print(f"build {version} ({build_no}): not visible yet")
        time.sleep(30)
    else:
        sys.exit("gave up waiting for the build")

    # 2. The version.
    d = call("GET", f"/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=10")
    ver = next((v for v in d["data"] if v["attributes"]["versionString"] == version), None)
    if ver:
        print(f"version {version}: exists, {ver['attributes']['appStoreState']}")
    elif not send:
        print(f"version {version}: would create")
    else:
        ver = call("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version,
                           "releaseType": "AFTER_APPROVAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
        print(f"version {version}: created {ver['id']}")

    for loc, folder in LOCALES.items():
        print(f"whatsNew[{loc}]: {notes(folder)!r}")
    if not send:
        print("dry run — re-run with --send")
        return

    vid = ver["id"]
    call("PATCH", f"/appStoreVersions/{vid}", {"data": {
        "type": "appStoreVersions", "id": vid,
        "attributes": {"releaseType": "AFTER_APPROVAL"}}})
    call("PATCH", f"/appStoreVersions/{vid}/relationships/build",
         {"data": {"type": "builds", "id": build["id"]}})
    if build["attributes"].get("usesNonExemptEncryption") is None:
        call("PATCH", f"/builds/{build['id']}", {"data": {
            "type": "builds", "id": build["id"],
            "attributes": {"usesNonExemptEncryption": False}}})
    print("build attached")

    locs = call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    for l in locs:
        folder = LOCALES.get(l["attributes"]["locale"])
        if not folder:
            continue
        call("PATCH", f"/appStoreVersionLocalizations/{l['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": l["id"],
            "attributes": {"whatsNew": notes(folder)}}})
        print(f"whatsNew written: {l['attributes']['locale']}")

    # 4. Submit. Reuse a submission still being assembled, else open one.
    subs = call("GET", f"/reviewSubmissions?filter[app]={APP_ID}&filter[platform]=IOS"
                       f"&filter[state]=READY_FOR_REVIEW&limit=5")["data"]
    sub = subs[0] if subs else call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
    try:
        call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    except RuntimeError as e:
        if "409" not in str(e):
            raise
        print(f"item already on the submission ({e})")
    call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {
        "type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print(f"submitted for review: {version} ({build_no})")


if __name__ == "__main__":
    main()
