#!/usr/bin/env bash
# Deliver a CloudKit silent push to a booted SIMULATOR, by hand.
#
# Testing `SyncPush` has three layers, and only the first one is ours:
#
#   1. THE HANDLER — does a content-available push wake this app, and does
#      `SyncPush.isOurs` recognise our account's zone? That is this script,
#      plus `SyncPushTests`, which pins the payload shape the script sends.
#   2. THE SUBSCRIPTION — does the zone subscription get created, and does
#      APNs accept this install? One real device. Look for no
#      `sync_push_subscribe_failed` and no `push_register_failed`.
#   3. THE DELIVERY — does CloudKit actually push when the other device
#      writes? TWO real devices, one iCloud account, one app account, sync on
#      in both. Nothing on a Mac can stand in for this: a simulator has no
#      APNs connection at all, which is exactly why layer 1 is hand-delivered.
#
# So a green run here means the wiring is right and the payload is understood.
# It does NOT mean Apple will deliver — that is layer 3, and it is the only
# one that can tell you the feature works.
#
# ONE PRECONDITION, measured the hard way: the app only calls
# `registerForRemoteNotifications()` once an account has sync switched ON
# (`SyncPush.activate`, from `SyncEngine.setUser`/`enable`) — a device that
# isn't syncing is deliberately never woken. An app that has never registered
# does not get the delegate callback, so a probe against a signed-out
# simulator sends a perfectly good push into silence and looks like a bug.
# Sign in and turn sync on in Me → Devices first, or this proves nothing.
#
# The subscription id is derived from the app's own `futurevoice.sync.lastUserId`,
# so the push claims to be for the account the simulator last ran as. Pass a
# user id to override.
#
#   ./scripts/sync-push-probe.sh                  # booted sim, dev build
#   ./scripts/sync-push-probe.sh <user-id>
#   UDID=<udid> BUNDLE=com.roro.futurevoice ./scripts/sync-push-probe.sh
#
set -euo pipefail

UDID="${UDID:-booted}"
BUNDLE="${BUNDLE:-com.roro.futurevoice.dev}"
CONTAINER="${CONTAINER:-iCloud.${BUNDLE}}"

if [ "$UDID" = "booted" ]; then
  booted=$(xcrun simctl list devices | grep "(Booted)" || true)
  count=$(printf '%s' "$booted" | grep -c . || true)
  # Never guess between booted simulators: the push goes to one of them and
  # the log stream is usually pointed at another, which reads as "the app
  # didn't wake" when it woke somewhere else.
  if [ "$count" -gt 1 ]; then
    echo "more than one simulator is booted — name one with UDID=:"; echo "$booted"; exit 1
  fi
  resolved=$(printf '%s' "$booted" | grep -oE '[0-9A-F-]{36}' | head -1)
else
  resolved=$(xcrun simctl list devices | grep -F "$UDID" | grep -oE '[0-9A-F-]{36}' | head -1)
  [ -n "$resolved" ] || resolved="$UDID"
fi
[ -n "$resolved" ] || { echo "no booted simulator (boot one, or pass UDID=)"; exit 1; }

data=$(xcrun simctl get_app_container "$resolved" "$BUNDLE" data 2>/dev/null) || {
  echo "$BUNDLE is not installed on $resolved — build and install it first"; exit 1; }

user="${1:-}"
if [ -z "$user" ]; then
  user=$(/usr/libexec/PlistBuddy -c "Print :futurevoice.sync.lastUserId" \
    "$data/Library/Preferences/$BUNDLE.plist" 2>/dev/null || true)
fi
[ -n "$user" ] || { echo "no account on this simulator — sign in once, or pass a user id"; exit 1; }

zone="nawana-$user"
sid="changes-$zone"
payload=$(mktemp -t syncpush).json
# The subscription id sits INSIDE `fet`, beside the zone. At the top of `ck`
# it parses into a CKRecordZoneNotification with a nil subscriptionID, which
# reads as "this push is somebody else's" — see SyncPushTests.
cat > "$payload" <<JSON
{
  "aps": { "content-available": 1 },
  "ck": {
    "ce": 2,
    "cid": "$CONTAINER",
    "nid": "$(uuidgen)",
    "fet": { "zid": "$zone", "zoid": "_defaultOwner", "dbs": 2, "sid": "$sid" }
  }
}
JSON

echo "device    $resolved"
echo "app       $BUNDLE"
echo "zone      $zone"
echo "subscription  $sid"
echo
xcrun simctl push "$resolved" "$BUNDLE" "$payload"
rm -f "$payload"
echo
echo "The app should have been woken. What it does next depends on its state:"
echo "  • sync OFF for this account  → handled and dropped, by design"
echo "  • sync ON                    → one .items pass, and a sync_woken event"
echo
echo "Watch it happen — the handler says which of the three it did:"
echo "  xcrun simctl spawn $resolved log stream --level debug \\"
echo "    --predicate 'subsystem == \"com.roro.futurevoice\" AND category == \"sync-push\"'"
echo
echo "On a real DEVICE (layers 2 and 3) the same notices read with:"
echo "  idevicesyslog | grep sync-push        # brew install libimobiledevice"
echo "or Console.app with the phone selected. NOT \`log stream --device\`: macOS 26"
echo "dropped that option, and zsh's own \`log\` builtin shadows /usr/bin/log anyway."
