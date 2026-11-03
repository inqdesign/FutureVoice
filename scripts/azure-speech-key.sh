#!/usr/bin/env bash
# Store the Azure Speech key for the pronunciation assessment, without it ever
# appearing on screen, in shell history, or in a chat.
#
#   scripts/azure-speech-key.sh
#
# Writes ~/keys/azure-speech.env (mode 600), which scripts/pronunciation-probe.sh
# reads and from which `supabase secrets set` is fed. The key is typed hidden.

set -euo pipefail

DEST="$HOME/keys/azure-speech.env"
mkdir -p "$HOME/keys"

echo "Azure portal → nawana-speech → Keys and Endpoint"
echo
echo "Copy KEY 1 with the portal's copy icon (⧉) next to it, then press Enter here."
printf "(or paste it first — nothing will show) "
IFS= read -rs KEY
echo
KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
# Just Enter: take it from the clipboard, and clear the clipboard after.
if [ -z "$KEY" ]; then
  KEY="$(pbpaste | tr -d '[:space:]')"
  [ -n "$KEY" ] && { printf '' | pbcopy; echo "(read from the clipboard, clipboard cleared)"; }
fi
if [ ${#KEY} -lt 20 ]; then
  echo "That doesn't look like a key (too short). Nothing was saved." >&2
  exit 1
fi

printf "Location/Region [koreacentral]: "
IFS= read -r REGION
REGION="$(printf '%s' "${REGION:-koreacentral}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
# "Korea Central" pasted as shown in the portal → koreacentral
REGION="${REGION// /}"

umask 077
printf 'AZURE_SPEECH_KEY=%s\nAZURE_SPEECH_REGION=%s\n' "$KEY" "$REGION" > "$DEST"
chmod 600 "$DEST"

# Check the key works before saying so: ask Azure for a short-lived token.
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "https://${REGION}.api.cognitive.microsoft.com/sts/v1.0/issueToken" \
  -H "Ocp-Apim-Subscription-Key: ${KEY}" -H "Content-Length: 0" || true)

echo
if [ "$CODE" = "200" ]; then
  echo "✓ Saved to $DEST and Azure accepted the key (region: $REGION)."
  echo "  You can close this window and tell Claude it's in."
else
  echo "Saved to $DEST, but Azure answered HTTP $CODE."
  echo "  401 = wrong key · 404/000 = wrong region name. Run this again to replace it."
fi
