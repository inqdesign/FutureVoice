#!/usr/bin/env bash
# Put a signed-in session on the emulator.
#
# Uninstalling the app (or an expired token) drops the session, and Android
# has no UI route back to a sign-in screen: Welcome's "Get started" opens an
# ANONYMOUS session and walks straight into the clone flow, which costs real
# money. So the session goes in directly.
#
# Credentials live outside the repo in ~/keys/nawana-dev-account.txt
# (line 1 email, line 2 password).
set -euo pipefail

DEV=${1:-emulator-5554}
CREDS="$HOME/keys/nawana-dev-account.txt"
PROPS="$(dirname "$0")/../../android/local.properties"

[ -f "$CREDS" ] || { echo "no $CREDS"; exit 1; }
EMAIL=$(sed -n '1p' "$CREDS"); PASSWORD=$(sed -n '2p' "$CREDS")
URL=$(grep '^SUPABASE_URL=' "$PROPS" | cut -d= -f2-)
ANON=$(grep '^SUPABASE_ANON_KEY=' "$PROPS" | cut -d= -f2-)
REF=$(echo "$URL" | sed 's|https://||; s|\.supabase\.co.*||')

curl -s -X POST "$URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" > /tmp/dev-session.json

adb -s "$DEV" shell am force-stop com.roro.futurevoice >/dev/null 2>&1 || true

python3 - "$DEV" "$REF" <<'PY'
import html, json, os, subprocess, sys, tempfile
dev, ref = sys.argv[1], sys.argv[2]
s = json.load(open('/tmp/dev-session.json'))
if 'access_token' not in s:
    sys.exit(f"sign-in failed: {s}")
# supabase-kt fails the WHOLE load on any key its model doesn't know.
s.pop('expires_at', None); s.pop('weak_password', None)
# Keep `identities` — AuthRepository.isAnonymous reads its emptiness, so
# dropping it makes the app treat a real account as anonymous.
for ident in (s.get('user') or {}).get('identities') or []:
    ident.pop('email', None)
payload = html.escape(json.dumps(s, separators=(',', ':')), quote=True)
xml = ("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n"
       f'    <string name="sb-{ref}-supabase-co-session">{payload}</string>\n</map>\n')
p = os.path.join(tempfile.mkdtemp(), 'p.xml')
open(p, 'w').write(xml)
subprocess.run(f'adb -s {dev} push {p} /data/local/tmp/sess.xml', shell=True, capture_output=True)
subprocess.run(
    f'adb -s {dev} shell "run-as com.roro.futurevoice cp /data/local/tmp/sess.xml '
    'shared_prefs/com.roro.futurevoice_preferences.xml"', shell=True)
print('session injected')
PY

adb -s "$DEV" shell am start -n com.roro.futurevoice/.MainActivity >/dev/null 2>&1
