#!/usr/bin/env python3
"""Submit a version that `beta.sh` already uploaded to App Review.

What `beta.sh` stops short of: it uploads to TestFlight, and App Store
Connect then wants the version made, the build attached, the notes pasted
and the submission sent — four screens by hand. This does the four:

  1. waits for build <build> of <version> to finish processing (VALID),
  2. creates the App Store version (or reuses one still being prepared),
  3. attaches the build and writes the WHOLE store page for every locale on
     file (see LOCALES): the version's description, keywords, promotional
     text, what's new, support and marketing URLs, and — when App Store
     Connect lets the app info be edited — its name, subtitle and privacy
     URL. A locale the store doesn't have yet is created,
  4. opens a review submission with that version and submits it.

Every field comes from fastlane/metadata/<folder>/<field>.txt. The dry run
prints, per locale and field, whether it would be CREATED, CHANGED (with the
old and new length) or left alone — read it before --send, because a field
that differs from the live page is about to replace it.

The app info (name · subtitle · privacy URL) can only be written while an
app info is being prepared — i.e. not while another version is in review or
between approval and release. When none is editable the script says so and
writes the rest; run it again later with --metadata-only to fill them in.

Release type is AFTER_APPROVAL: the version goes live when Apple approves it.
The update sheet still waits on `./scripts/beta.sh released` after that.

Dry run by default; `--send` does it.

    scripts/asc-submit.py 1.0.10 61                  # plan only
    scripts/asc-submit.py 1.0.10 61 --send           # do it
    scripts/asc-submit.py 1.0.10 61 --send --prepare # everything but the submission
    scripts/asc-submit.py 1.0.10 61 --metadata-only  # plan the page, no build/submit
    scripts/asc-submit.py 1.0.10 61 --metadata-only --send
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
# App Store locale → fastlane/metadata folder. The store's primary English is
# en-GB and shares the en-US copy; Spanish is one neutral text in two storefronts.
LOCALES = {
    "en-GB": "en-US", "en-US": "en-US", "ko": "ko", "ja": "ja",
    "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
    "es-ES": "es-ES", "es-MX": "es-MX", "fr-FR": "fr-FR", "de-DE": "de-DE",
}
# field on appStoreVersionLocalizations → file
VERSION_FIELDS = {
    "description": "description.txt", "keywords": "keywords.txt",
    "promotionalText": "promotional_text.txt", "whatsNew": "release_notes.txt",
    "supportUrl": "support_url.txt", "marketingUrl": "marketing_url.txt",
}
# field on appInfoLocalizations → file
INFO_FIELDS = {"name": "name.txt", "subtitle": "subtitle.txt",
               "privacyPolicyUrl": "privacy_url.txt"}
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170,
          "description": 4000, "whatsNew": 4000}
# An app info in one of these can't be edited.
LOCKED_INFO = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "WAITING_FOR_REVIEW",
               "IN_REVIEW", "PENDING_RELEASE", "ACCEPTED", "PENDING_DEVELOPER_RELEASE"}


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


def field(folder: str, filename: str) -> str | None:
    path = os.path.join(ROOT, "fastlane/metadata", folder, filename)
    return open(path).read().strip() if os.path.exists(path) else None


def wanted(fields: dict) -> dict:
    """{locale: {attribute: text}} for every locale whose folder exists."""
    out = {}
    for loc, folder in LOCALES.items():
        if not os.path.isdir(os.path.join(ROOT, "fastlane/metadata", folder)):
            continue
        vals = {attr: field(folder, f) for attr, f in fields.items()}
        out[loc] = {k: v for k, v in vals.items() if v}
    return out


def check_limits(*pages: dict) -> None:
    bad = [f"{loc}.{attr}: {len(v)} > {LIMITS[attr]}"
           for page in pages for loc, vals in page.items()
           for attr, v in vals.items() if attr in LIMITS and len(v) > LIMITS[attr]]
    if bad:
        sys.exit("over App Store limits:\n  " + "\n  ".join(bad))


def sync_localizations(kind: str, parent_rel: str, parent_type: str, parent_id: str,
                       live: list, page: dict, send: bool) -> None:
    """Create or update one set of localizations (version or app info).
    Prints a line per locale; writes only with `send`."""
    by_locale = {l["attributes"]["locale"]: l for l in live}
    for loc, vals in page.items():
        cur = by_locale.get(loc)
        if cur is None:
            print(f"  {kind} {loc}: CREATE ({', '.join(vals)})")
            if send:
                call("POST", f"/{kind}", {"data": {
                    "type": kind, "attributes": {"locale": loc, **vals},
                    "relationships": {parent_rel: {"data": {"type": parent_type, "id": parent_id}}}}})
            continue
        changed = {k: v for k, v in vals.items() if (cur["attributes"].get(k) or "").strip() != v}
        if not changed:
            print(f"  {kind} {loc}: unchanged")
            continue
        desc = ", ".join(f"{k} {len(cur['attributes'].get(k) or '')}→{len(v)}" for k, v in changed.items())
        print(f"  {kind} {loc}: CHANGE {desc}")
        if send:
            call("PATCH", f"/{kind}/{cur['id']}", {"data": {
                "type": kind, "id": cur["id"], "attributes": changed}})


def sync_page(ver: dict | None, send: bool) -> None:
    version_page, info_page = wanted(VERSION_FIELDS), wanted(INFO_FIELDS)
    check_limits(version_page, info_page)
    print(f"locales on file: {', '.join(version_page)}")

    if ver is None:
        print("  (version not created yet — every version localization would be CREATED)")
    else:
        live = call("GET", f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")["data"]
        sync_localizations("appStoreVersionLocalizations", "appStoreVersion", "appStoreVersions",
                           ver["id"], live, version_page, send)

    infos = call("GET", f"/apps/{APP_ID}/appInfos")["data"]
    editable = [i for i in infos if i["attributes"].get("appStoreState") not in LOCKED_INFO]
    if not editable:
        states = ", ".join(i["attributes"].get("appStoreState", "?") for i in infos)
        print(f"  app info (name · subtitle · privacy URL): locked ({states}) — "
              f"re-run with --metadata-only once a version is being prepared")
        return
    info = editable[0]
    live = call("GET", f"/appInfos/{info['id']}/appInfoLocalizations?limit=50")["data"]
    sync_localizations("appInfoLocalizations", "appInfo", "appInfos", info["id"], live, info_page, send)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    version, build_no = args
    send = "--send" in sys.argv

    if "--metadata-only" in sys.argv:
        d = call("GET", f"/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=10")
        ver = next((v for v in d["data"] if v["attributes"]["versionString"] == version), None)
        print(f"version {version}: {ver['attributes']['appStoreState'] if ver else 'not created'}")
        sync_page(ver, send)
        if not send:
            print("dry run — re-run with --send")
        return

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

    if not send:
        sync_page(ver, send=False)
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

    sync_page(ver, send=True)

    # `--prepare`: a draft a person can read in App Store Connect before it
    # goes anywhere. Re-run with --send (no --prepare) to submit it.
    if "--prepare" in sys.argv:
        print(f"prepared {version} ({build_no}) — not submitted. Check it in App Store Connect,"
              f" then: scripts/asc-submit.py {version} {build_no} --send")
        return

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
