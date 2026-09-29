#!/usr/bin/env python3
"""Write the Google Play store page from android/fastlane/metadata/android/.

The Play twin of `scripts/asc-submit.py --metadata-only`: title, short and
full description per language, the contact details, and — with --images —
the icon, feature graphic and phone screenshots. The folder layout is
fastlane `supply`'s, so the same files work with `fastlane supply` on a
machine where fastlane runs (this one's Ruby 4.0 can't, see fastlane/Fastfile).

What this does NOT write, because the Publishing API can't: everything under
Play Console → App content (privacy policy URL, data safety, content rating,
target audience, ads, app access, permission declarations). Those answers
are in docs/play-console.md, ready to paste. Release notes ("what's new")
ride on a track release, not the listing — `changelogs/<versionCode>.txt`
is read by the release script (plan 7.5), not here.

Auth: a Google Cloud service account with access to the app in Play Console
(Users and permissions → invite the service account's email, "Manage store
presence"). Its JSON key goes at ~/keys/play-service-account.json, or set
PLAY_SERVICE_ACCOUNT to its path. The app must already exist in Play Console
— the API can edit an app, never create one.

Dry run by default. Without a key it validates the files (lengths, images)
and prints the plan; with a key it also diffs against the live listing.

    scripts/android/play-listing.py                 # validate + plan
    scripts/android/play-listing.py --images        # include graphics in the plan
    scripts/android/play-listing.py --send          # write text + details
    scripts/android/play-listing.py --send --images # and replace the graphics
"""

import base64
import json
import os
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

PACKAGE = "com.roro.futurevoice"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
META = os.path.join(ROOT, "android/fastlane/metadata/android")
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"
KEY = os.environ.get("PLAY_SERVICE_ACCOUNT", os.path.expanduser("~/keys/play-service-account.json"))

# Play listing language → metadata folder. en-GB shares the US copy and
# es-419 the neutral Spanish, exactly as the App Store pages do. No de-DE:
# the Android app has no German UI yet, and a German page would promise one.
LOCALES = {
    "en-US": "en-US", "en-GB": "en-US", "ko-KR": "ko-KR", "ja-JP": "ja-JP",
    "zh-TW": "zh-TW", "zh-CN": "zh-CN", "es-ES": "es-ES", "es-419": "es-ES",
    "fr-FR": "fr-FR",
}
FIELDS = {"title": "title.txt", "shortDescription": "short_description.txt",
          "fullDescription": "full_description.txt"}
LIMITS = {"title": 30, "shortDescription": 80, "fullDescription": 4000}
# imageType → (file or folder under images/, exact size or None, max count)
IMAGES = {
    "icon": ("icon.png", (512, 512), 1),
    "featureGraphic": ("featureGraphic.png", (1024, 500), 1),
    "phoneScreenshots": ("phoneScreenshots", None, 8),
}


def read(folder: str, name: str) -> str | None:
    p = os.path.join(META, folder, name)
    return open(p, encoding="utf-8").read().strip() if os.path.exists(p) else None


def png_size(path: str) -> tuple[int, int]:
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path}: not a PNG")
    return struct.unpack(">II", head[16:24])


def image_files(folder: str, kind: str) -> list[str]:
    name, _, _ = IMAGES[kind]
    base = os.path.join(META, folder, "images", name)
    if os.path.isdir(base):
        return sorted(os.path.join(base, f) for f in os.listdir(base)
                      if f.lower().endswith(".png"))
    # icon + feature graphic are the same in every language: fall back to en-US
    if not os.path.exists(base):
        base = os.path.join(META, "en-US", "images", name)
    return [base] if os.path.exists(base) else []


def validate(with_images: bool) -> list[str]:
    problems = []
    for loc, folder in LOCALES.items():
        for attr, f in FIELDS.items():
            v = read(folder, f)
            if not v:
                problems.append(f"{loc}: {f} missing")
            elif len(v) > LIMITS[attr]:
                problems.append(f"{loc}: {attr} {len(v)} > {LIMITS[attr]}")
        if not with_images:
            continue
        for kind, (_, exact, most) in IMAGES.items():
            files = image_files(folder, kind)
            if kind == "phoneScreenshots" and not 2 <= len(files) <= most:
                problems.append(f"{loc}: {len(files)} phone screenshots (Play needs 2–{most})")
            if kind != "phoneScreenshots" and not files:
                problems.append(f"{loc}: {kind} missing")
            for p in files:
                w, h = png_size(p)
                if exact and (w, h) != exact:
                    problems.append(f"{p}: {w}x{h}, needs {exact[0]}x{exact[1]}")
                if kind == "phoneScreenshots" and (
                        min(w, h) < 320 or max(w, h) > 3840 or max(w, h) > 2 * min(w, h)):
                    problems.append(f"{p}: {w}x{h} — sides 320–3840, long side ≤ 2× short")
    for f in ("contact_email.txt", "contact_website.txt", "default_language.txt"):
        if not read("", f):
            problems.append(f"{f} missing")
    return problems


def token() -> str:
    sa = json.load(open(KEY))

    def b64(raw: bytes) -> str:
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    now = int(time.time())
    header = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64(json.dumps({
        "iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
        "aud": sa["token_uri"], "iat": now, "exp": now + 3000}).encode())
    signing = f"{header}.{claims}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=True) as pem:
        pem.write(sa["private_key"])
        pem.flush()
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", pem.name],
                             input=signing, capture_output=True, check=True).stdout
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": f"{header}.{claims}.{b64(sig)}"}).encode()
    with urllib.request.urlopen(sa["token_uri"], data=body, timeout=30) as r:
        return json.load(r)["access_token"]


TOKEN = None


def call(method: str, url: str, body=None, raw: bytes | None = None, ctype=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url if url.startswith("http") else API + url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if data is not None:
        req.add_header("Content-Type", ctype or "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            out = r.read()
            return json.loads(out) if out else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {url.split('?')[0]} → {e.code} {e.read().decode()[:600]}") from None


def main() -> None:
    global TOKEN
    send = "--send" in sys.argv
    with_images = "--images" in sys.argv

    problems = validate(with_images)
    if problems:
        print("Not ready:")
        for p in problems:
            print("  ·", p)
        sys.exit(1)
    print(f"Files OK — {len(LOCALES)} languages" + (", graphics included" if with_images else ""))

    if not os.path.exists(KEY):
        print(f"\nNo service-account key at {KEY} — stopping at the file check.")
        print("Plan: " + ", ".join(LOCALES) + " · title / short / full description · contact details"
              + (" · icon, feature graphic, phone screenshots" if with_images else ""))
        return

    TOKEN = token()
    edit = call("POST", "/edits", {})["id"]
    try:
        live = {l["language"]: l for l in call("GET", f"/edits/{edit}/listings").get("listings", [])}
        for loc, folder in LOCALES.items():
            want = {attr: read(folder, f) for attr, f in FIELDS.items()}
            have = live.get(loc, {})
            changed = [a for a in FIELDS if (have.get(a) or "").strip() != want[a]]
            state = "CREATE" if loc not in live else ("CHANGE " + ", ".join(changed) if changed else "unchanged")
            print(f"  {loc:7} {state}")
            if send and changed:
                call("PUT", f"/edits/{edit}/listings/{loc}", {"language": loc, **want})

        details = {"contactEmail": read("", "contact_email.txt"),
                   "contactWebsite": read("", "contact_website.txt"),
                   "defaultLanguage": read("", "default_language.txt")}
        have = call("GET", f"/edits/{edit}/details")
        diff = {k: v for k, v in details.items() if have.get(k) != v}
        print("  details " + (", ".join(f"{k}={v}" for k, v in diff.items()) if diff else "unchanged"))
        if send and diff:
            call("PATCH", f"/edits/{edit}/details", diff)

        if with_images:
            for loc, folder in LOCALES.items():
                for kind in IMAGES:
                    files = image_files(folder, kind)
                    print(f"  {loc:7} {kind}: replace with {len(files)} file(s)")
                    if not send:
                        continue
                    call("DELETE", f"/edits/{edit}/listings/{loc}/{kind}")
                    for p in files:
                        call("POST", f"{UPLOAD}/edits/{edit}/listings/{loc}/{kind}?uploadType=media",
                             raw=open(p, "rb").read(), ctype="image/png")

        if send:
            # A draft app (never released) refuses a plain commit's review
            # step; changesNotSentForReview keeps the edit and lets the
            # listing ride along with the first release's review.
            q = "?changesNotSentForReview=true" if "--not-for-review" in sys.argv else ""
            call("POST", f"/edits/{edit}:commit{q}")
            print("Committed.")
        else:
            call("DELETE", f"/edits/{edit}")
            print("\nDry run — nothing written. Run again with --send.")
    except Exception:
        try:
            call("DELETE", f"/edits/{edit}")
        finally:
            raise


if __name__ == "__main__":
    main()
