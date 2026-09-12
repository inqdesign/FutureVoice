#!/usr/bin/env python3
"""Wire up Sign in with Apple for the web (nawana.app) in Supabase Auth.

Run from the repo root:  python3 scripts/apple-web-signin.py [path/to/AuthKey_XXXX.p8]

Reads the .p8 signing key from disk (never paste it anywhere), builds Apple's
client-secret JWT with openssl, and PATCHes the Supabase auth config via the
Management API (token from the keychain, same as scripts/stripe-web-billing.py):

  - external Apple provider: enabled, client ids = app bundle id + web
    Services ID, secret = the JWT
  - redirect allow-list: adds https://nawana.app/*

With no argument it picks the newest ~/Downloads/AuthKey_*.p8 and derives the
Key ID from the filename (AuthKey_<KEYID>.p8 is how Apple names the download).

⚠ Apple caps the client secret at 6 months. This script signs for 180 days
and prints the expiry date — put a reminder in the calendar; when it expires,
web sign-in dies silently until the script is re-run with the same .p8.
"""

import base64
import glob
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

TEAM_ID = "PXS8Q4NT67"                      # project.yml DEVELOPMENT_TEAM
WEB_CLIENT_ID = "com.roro.futurevoice.web"  # the Services ID
APP_CLIENT_ID = "com.roro.futurevoice"      # the app's bundle id (native flow)
SUPABASE_PROJECT_REF = "chhzjtigzdotacutwcyo"
REDIRECT_PATTERN = "https://nawana.app/*"
VALID_SECONDS = 180 * 24 * 3600             # Apple's max is ~6 months


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


SIWA_KEY_ID = "G5Q9Y57N22"  # the Sign in with Apple key registered 2026-09-03
KEY_DIR = Path.home() / "Documents" / "AuthKey collection"


def find_key() -> Path:
    if len(sys.argv) > 1:
        p = Path(sys.argv[1]).expanduser()
        if not p.exists():
            sys.exit(f"no such file: {p}")
        return p
    # The collection folder holds keys for SEVERAL projects — never pick by
    # "newest", name the exact key this integration was registered with.
    exact = KEY_DIR / f"AuthKey_{SIWA_KEY_ID}.p8"
    if exact.exists():
        return exact
    candidates = sorted(glob.glob(str(Path.home() / "Downloads" / "AuthKey_*.p8")),
                        key=lambda f: Path(f).stat().st_mtime, reverse=True)
    if not candidates:
        sys.exit(f"no {exact} and no AuthKey_*.p8 in ~/Downloads — pass the path as an argument")
    return Path(candidates[0])


def der_to_raw_es256(der: bytes) -> bytes:
    """openssl emits an ASN.1 DER ECDSA signature; JWTs need raw r||s (64 bytes)."""
    assert der[0] == 0x30, "not a DER sequence"
    idx = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)

    def read_int(i: int) -> tuple[bytes, int]:
        assert der[i] == 0x02, "expected DER integer"
        length = der[i + 1]
        val = der[i + 2 : i + 2 + length].lstrip(b"\x00")
        assert len(val) <= 32, "integer too long for P-256"
        return val.rjust(32, b"\x00"), i + 2 + length

    r, idx = read_int(idx)
    s, _ = read_int(idx)
    return r + s


def make_client_secret(p8: Path, key_id: str) -> tuple[str, int]:
    now = int(time.time())
    exp = now + VALID_SECONDS
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({
        "iss": TEAM_ID, "iat": now, "exp": exp,
        "aud": "https://appleid.apple.com", "sub": WEB_CLIENT_ID,
    }, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(p8)],
        input=signing_input, check=True, capture_output=True).stdout
    return f"{header}.{payload}.{b64url(der_to_raw_es256(der))}", exp


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
    p8 = find_key()
    m = re.match(r"AuthKey_([A-Z0-9]+)\.p8$", p8.name)
    key_id = m.group(1) if m else input("Key ID (10 chars, from the Keys page): ").strip()
    print(f"key file: {p8} · Key ID {key_id} · Team {TEAM_ID}")

    secret, exp = make_client_secret(p8, key_id)
    expires = datetime.fromtimestamp(exp, tz=timezone.utc).strftime("%Y-%m-%d")

    token = supabase_token()
    current = auth_config(token)

    # merge, never clobber: the native app flow may already list client ids,
    # and the allow-list holds whatever web auth already relies on.
    # ORDER MATTERS: GoTrue uses the FIRST id as the OAuth client_id for the
    # web flow, so the Services ID must lead — with the bundle id first,
    # Apple's authorize page received an App ID and rejected the login
    # (found live 2026-09-03). The rest only validate native id_tokens.
    ids = [c for c in (current.get("external_apple_client_id") or "").split(",") if c]
    ids = [WEB_CLIENT_ID] + [c for c in ids if c != WEB_CLIENT_ID]
    if APP_CLIENT_ID not in ids:
        ids.append(APP_CLIENT_ID)
    allow = [u for u in (current.get("uri_allow_list") or "").split(",") if u]
    if REDIRECT_PATTERN not in allow:
        allow.append(REDIRECT_PATTERN)

    try:
        auth_config(token, "PATCH", {
            "external_apple_enabled": True,
            "external_apple_client_id": ",".join(ids),
            "external_apple_secret": secret,
            "uri_allow_list": ",".join(allow),
        })
        print("supabase auth config updated:")
        print(f"  apple provider: enabled · client ids {','.join(ids)}")
        print(f"  redirect allow-list: {','.join(allow)}")
    except urllib.error.HTTPError as e:
        # Fallback: hand the values to paste into the dashboard by hand
        # (Authentication → Providers → Apple). The JWT is safe to print —
        # it is public-ish (sent on every OAuth exchange) and expires.
        print(f"⚠ Management API PATCH failed ({e.code}: {e.read().decode()[:200]})")
        print("paste by hand in Supabase → Authentication → Providers → Apple:")
        print(f"  Client IDs: {','.join(ids)}")
        print(f"  Secret Key:\n{secret}")

    print(f"\n⚠ secret expires {expires} — calendar it; re-run this script to renew")


if __name__ == "__main__":
    main()
