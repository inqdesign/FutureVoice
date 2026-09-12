#!/usr/bin/env python3
"""Wire up Google sign-in for the web (nawana.app) in Supabase Auth.

Run from the repo root:  python3 scripts/google-web-signin.py [client_secret.json]

Takes the OAuth client JSON that Google Cloud console offers for download
(client_secret_*.json — with no argument, the newest one in ~/Downloads),
and PATCHes the Supabase auth config via the Management API:

  - Google provider: enabled, client id + secret from the JSON
  - the client id ALSO validates Android's native id_token flow — the app's
    Credential Manager uses this same web client id as serverClientId
    (GOOGLE_WEB_CLIENT_ID), so one OAuth client serves both surfaces and the
    same Google account resolves to the same Supabase user everywhere.

Prerequisite (Google Cloud console, console.cloud.google.com):
  1. OAuth consent screen: External, app name nawana, publish it
  2. Credentials → Create credentials → OAuth client ID → **Web application**
     - Authorized redirect URI:
       https://chhzjtigzdotacutwcyo.supabase.co/auth/v1/callback
  3. Download the JSON (⬇ button on the client row) → run this script

Unlike Apple's client secret, Google's does not expire — one run, done.
"""

import base64
import glob
import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

SUPABASE_PROJECT_REF = "chhzjtigzdotacutwcyo"
EXPECTED_REDIRECT = f"https://{SUPABASE_PROJECT_REF}.supabase.co/auth/v1/callback"


def find_client_json() -> Path:
    if len(sys.argv) > 1:
        p = Path(sys.argv[1]).expanduser()
        if not p.exists():
            sys.exit(f"no such file: {p}")
        return p
    candidates = sorted(glob.glob(str(Path.home() / "Downloads" / "client_secret*.json")),
                        key=lambda f: Path(f).stat().st_mtime, reverse=True)
    if not candidates:
        sys.exit("no client_secret*.json in ~/Downloads — pass the path as an argument")
    return Path(candidates[0])


def supabase_token() -> str:
    raw = subprocess.run(["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
                         check=True, capture_output=True, text=True).stdout.strip()
    if raw.startswith("go-keyring-base64:"):
        return base64.b64decode(raw.split(":", 1)[1]).decode().strip()
    return raw


def auth_config(token: str, method: str = "GET", body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{SUPABASE_PROJECT_REF}/config/auth",
        data=json.dumps(body).encode() if body else None, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Content-Type", "application/json")
    # api.supabase.com's WAF 403s the default Python-urllib user agent
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def main() -> None:
    path = find_client_json()
    data = json.loads(path.read_text())
    web = data.get("web")
    if not web:
        sys.exit(f"{path} is not a WEB oauth client (create the client as type 'Web application')")
    client_id, secret = web["client_id"], web["client_secret"]
    print(f"client json: {path}")
    print(f"client id:   {client_id}")

    redirects = web.get("redirect_uris") or []
    if EXPECTED_REDIRECT not in redirects:
        print(f"  ⚠ redirect URI {EXPECTED_REDIRECT} is not on the client — Google will refuse the")
        print(f"    callback. Add it in the console (current: {redirects or 'none'}); continuing anyway.")

    token = supabase_token()
    try:
        auth_config(token, "PATCH", {
            "external_google_enabled": True,
            "external_google_client_id": client_id,
            "external_google_secret": secret,
        })
        print("supabase auth config updated: google provider enabled")
    except urllib.error.HTTPError as e:
        print(f"⚠ Management API PATCH failed ({e.code}: {e.read().decode()[:200]})")
        print("paste by hand in Supabase → Authentication → Providers → Google:")
        print(f"  Client ID: {client_id}\n  Secret: (from {path})")
        return

    print("\nnext: put the same client id into the Android checkout as GOOGLE_WEB_CLIENT_ID")
    print("(FutureVoice-android android/local.properties) so the app's Google button lights up.")


if __name__ == "__main__":
    main()
