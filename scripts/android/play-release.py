#!/usr/bin/env python3
"""Build the signed bundle and put it on a Google Play track — the Play twin of
`scripts/beta.sh`. Plan 7.5.

    scripts/android/play-release.py                     # build + plan (dry run)
    scripts/android/play-release.py --bump              # versionCode +1 first
    scripts/android/play-release.py --send              # upload to internal
    scripts/android/play-release.py --send --track alpha   # closed testing
    scripts/android/play-release.py --no-build --send   # upload the AAB already built
    scripts/android/play-release.py --match-ios         # versionName = the iOS marketing version
    scripts/android/play-release.py released            # the update sheet → what Play is serving
    scripts/android/play-release.py released 18 --force # same, without the proof below

THE UPDATE SHEET IS TWO STEPS, like iOS's (`beta.sh` / `beta.sh released`).
`--send` moves `app_release.latest_beta_build` (a sideloaded install). A
Play install compares against `latest_build`, and that may only move once
Play is actually SERVING the build — Play reviews every release, testing
tracks included, and a sheet that opens a Play page still offering the old
build is the iOS 2026-09-11 bug. The Publisher API has no review status, so
`released` takes its proof from the one place that can't lie: a learner who
is not on the team reporting that build. 2026-10-20: 1.2.0 (18) was served
to testers all afternoon while the row still said 17, so nobody on 17 was
told — `scripts/release-watch.sh` now runs `released --watch` every 30 min.

Release notes ride on the release, one per language, from
android/fastlane/metadata/android/<folder>/changelogs/<versionCode>.txt —
the same files fastlane `supply` reads. A version with no en-US notes is
refused: the notes are what a tester sees in the Play app, and "no notes" is
how a placeholder ships.

After the commit the same ko-KR / en-US changelogs, headings kept, go into
app_release.notes_sections_ko/en for the android row — what the in-app update
sheet draws as sections (warns, never fails, if that write doesn't land).

The release is written as a DRAFT while the app has never been published
(Play refuses any other status then); afterwards it is `completed` on the
track. Rolling a draft out is one click in Play Console → the track, which
is where the testers list lives anyway.

Auth and the shared plumbing are play-listing.py's (service account at
~/keys/play-service-account.json). Signing comes from android/local.properties
— the four RELEASE_* keys — and the build stops if the bundle comes out
unsigned rather than uploading something Play will reject.
"""

import importlib.util
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("pl", os.path.join(HERE, "play-listing.py"))
pl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pl)

ANDROID = os.path.join(pl.ROOT, "android")
GRADLE_FILE = os.path.join(ANDROID, "app/build.gradle.kts")
AAB = os.path.join(ANDROID, "app/build/outputs/bundle/release/app-release.aab")
def _java_home() -> str:
    """Android Studio's JBR, else $JAVA_HOME, else a JDK Gradle provisioned
    (Android Studio's JBR went missing on 2026-10-13 and the release build
    stopped at the first line)."""
    import glob
    for c in ["/Applications/Android Studio.app/Contents/jbr/Contents/Home",
              os.environ.get("JAVA_HOME", ""),
              *sorted(glob.glob(os.path.expanduser("~/.gradle/jdks/*/*/Contents/Home")), reverse=True)]:
        if c and os.path.exists(os.path.join(c, "bin/java")):
            return c
    return "/Applications/Android Studio.app/Contents/jbr/Contents/Home"


JAVA_HOME = _java_home()

# Play release-notes language → metadata folder (same map as the listing).
NOTE_LOCALES = pl.LOCALES


def version() -> tuple[int, str]:
    src = open(GRADLE_FILE).read()
    code = int(re.search(r"versionCode\s*=\s*(\d+)", src).group(1))
    name = re.search(r'versionName\s*=\s*"([^"]+)"', src).group(1)
    return code, name


def bump() -> int:
    src = open(GRADLE_FILE).read()
    code = int(re.search(r"versionCode\s*=\s*(\d+)", src).group(1)) + 1
    open(GRADLE_FILE, "w").write(re.sub(r"versionCode\s*=\s*\d+", f"versionCode = {code}", src, count=1))
    return code


def notes(code: int) -> list[dict]:
    out = []
    for lang, folder in NOTE_LOCALES.items():
        path = os.path.join(pl.META, folder, "changelogs", f"{code}.txt")
        if os.path.exists(path):
            text = open(path).read().strip()
            if len(text) > 500:
                sys.exit(f"{folder}/changelogs/{code}.txt is {len(text)} chars — Play allows 500.")
            out.append({"language": lang, "text": text})
    if not any(n["language"] == "en-US" for n in out):
        sys.exit(f"No en-US release notes at en-US/changelogs/{code}.txt — write them first.")
    return out


SUPABASE_REF = "chhzjtigzdotacutwcyo"


def supabase_sql(query: str):
    """One statement through the Management API; the parsed rows, or None."""
    import base64
    import json
    raw = subprocess.run(["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
                         capture_output=True, text=True).stdout.strip()
    if not raw:
        return None
    token = base64.b64decode(raw.removeprefix("go-keyring-base64:")).decode()
    r = subprocess.run(
        ["curl", "-sf", "-X", "POST",
         f"https://api.supabase.com/v1/projects/{SUPABASE_REF}/database/query",
         "-H", f"Authorization: Bearer {token}", "-H", "Content-Type: application/json",
         "-d", json.dumps({"query": query})],
        capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout or "[]")
    except ValueError:
        return None


def sql_text(t: str | None) -> str:
    """Dollar-quoted literal — release notes carry apostrophes."""
    if t is None:
        return "null"
    tag = "n"
    while f"${tag}$" in t:
        tag += "n"
    return f"${tag}${t}${tag}$"


def changelog(code: int, folder: str) -> str | None:
    path = os.path.join(pl.META, folder, "changelogs", f"{code}.txt")
    return open(path).read().strip() if os.path.exists(path) else None


def flat_notes(text: str | None) -> str | None:
    """The bullets alone, for a sheet that draws one list (beta.sh's
    `sheet_notes`). The headed copy goes to notes_sections_*."""
    if not text:
        return text
    marks = ("- ", "• ", "· ", "* ")
    lines = text.splitlines()
    if any(l.strip().startswith(marks) for l in lines):
        lines = [l for l in lines if l.strip().startswith(marks)]
    return "\n".join(lines).strip()


def test_user_ids() -> set[str]:
    """The team's own accounts — the admin console's TEST_IDS, read from the
    iOS worktree so there is one list. Their phones carry sideloaded builds,
    which prove nothing about what Play serves."""
    first = subprocess.run(["git", "-C", pl.ROOT, "worktree", "list", "--porcelain"],
                           text=True, capture_output=True).stdout.splitlines()
    ios = next((l.split(" ", 1)[1] for l in first if l.startswith("worktree ")), "")
    path = os.path.join(ios, "admin/src/assemble.ts")
    if not os.path.exists(path):
        return set()
    src = open(path).read()
    block = re.search(r"const TEST_IDS = new Set\(\[(.*?)\]\)", src, re.S)
    return set(re.findall(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
                          block.group(1) if block else ""))


def released(args: list[str]) -> None:
    """Move the update sheet for Play installs to the build Play is serving."""
    watch, force = "--watch", "--force"
    positional = [a for a in args if not a.startswith("--")]
    rows = supabase_sql("select latest_build, latest_beta_build from public.app_release "
                        "where platform = 'android'")
    if not rows:
        sys.exit("app_release (android) could not be read.")
    current = rows[0]["latest_build"] or 0

    # What Play has: production once it has a release, else the newest
    # completed release on any testing track (every tester installs from Play).
    pl.TOKEN = pl.token()
    edit = pl.call("POST", "/edits", {})["id"]
    try:
        tracks = pl.call("GET", f"/edits/{edit}/tracks").get("tracks", [])
    finally:
        pl.call("DELETE", f"/edits/{edit}")
    def completed(t):
        return [(int(c), r.get("name") or "") for r in t.get("releases", [])
                if r.get("status") == "completed" for c in r.get("versionCodes", [])]
    prod = next((completed(t) for t in tracks if t["track"] == "production"), [])
    served = prod or [x for t in tracks for x in completed(t)]
    if not served:
        sys.exit("Nothing completed on any Play track.")
    on_play, rel_name = max(served)
    code = int(positional[0]) if positional else on_play
    if code > on_play:
        sys.exit(f"Play has no completed release of {code} (newest is {on_play}).")
    if code <= current:
        if watch not in args:
            print(f"Update sheet already on {current} — nothing to do.")
        return

    if force not in args:
        team = test_user_ids()
        seen = supabase_sql(
            "select user_id::text as id, min(created_at)::text as at from client_events "
            f"where properties->>'platform' = 'android' and properties->>'build' = '{code}' "
            # The admin flag marks the founder's own accounts too.
            "and user_id not in (select user_id from user_credits where unlimited) "
            "group by user_id") or []
        proof = [r for r in seen if r["id"] not in team]
        if not proof:
            msg = (f"Play has {code} committed, but no learner outside the team has run it yet — "
                   "review may still be going. Re-run later, or --force once Play Console shows it.")
            if watch in args:
                return
            sys.exit(msg)
        print(f"Proof: {len(proof)} learner(s) on {code}, first at {min(r['at'] for r in proof)} UTC")

    m = re.match(r"\s*([0-9][0-9.]*)", rel_name)
    name = m.group(1) if (m and code == on_play) else version()[1]
    ko, en = changelog(code, "ko-KR"), changelog(code, "en-US")
    ok = supabase_sql(
        f"update public.app_release set latest_build = {code}, "
        f"latest_beta_build = greatest(coalesce(latest_beta_build, 0), {code}), "
        f"latest_version = {sql_text(name)}, "
        f"notes_ko = coalesce({sql_text(flat_notes(ko))}, notes_ko), "
        f"notes_en = coalesce({sql_text(flat_notes(en))}, notes_en), updated_at = now() "
        "where platform = 'android';")
    if ok is None:
        sys.exit("app_release update failed.")
    print(f"✓ app_release (android).latest_build → {code} ({name}). Play installs now see the update sheet.")
    publish_note_sections(code)


def publish_note_sections(code: int) -> None:
    """The same changelogs WITH their headings, for the update sheet's
    sections (New / Fixed / Improved) — beta.sh's `publish_note_sections`,
    for the `android` row of app_release. Korean from ko-KR, English from
    en-US. Its own statement, and a failure only warns: a database without
    the columns (20261018150000), or no token in the keychain, costs the
    sections, never the release."""
    ko, en = changelog(code, "ko-KR"), changelog(code, "en-US")
    ok = supabase_sql(f"update public.app_release set notes_sections_ko = {sql_text(ko)}, "
                      f"notes_sections_en = {sql_text(en)} where platform = 'android';")
    if ok is not None:
        print("▸ app_release (android).notes_sections → this version's changelogs")
    else:
        print("  ! notes_sections update failed (migration 20261018150000 not applied?) — "
              "the sheet shows one flat list.", file=sys.stderr)


def build() -> None:
    env = dict(os.environ, JAVA_HOME=JAVA_HOME)
    r = subprocess.run(["./gradlew", "bundleRelease", "--console=plain"], cwd=ANDROID, env=env,
                       capture_output=True, text=True)
    if "BUILD SUCCESSFUL" not in r.stdout:
        print(r.stdout[-3000:], r.stderr[-2000:])
        sys.exit("bundleRelease failed.")
    v = subprocess.run([os.path.join(JAVA_HOME, "bin/jarsigner"), "-verify", AAB],
                       capture_output=True, text=True).stdout
    if "jar verified" not in v:
        sys.exit("The bundle is not signed — check RELEASE_* in android/local.properties.")


def ios_version(ios: str) -> str:
    """The iOS marketing version in the main worktree — the version whose
    features Android carries once the ledger is clear."""
    r = subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString",
                        os.path.join(ios, "FutureVoice/Resources/Info.plist")], text=True, capture_output=True)
    return r.stdout.strip()


def set_version_name(name: str) -> None:
    src = open(GRADLE_FILE).read()
    open(GRADLE_FILE, "w").write(re.sub(r'versionName\s*=\s*"[^"]+"', f'versionName = "{name}"', src, count=1))


def android_gate(track: str, send: bool) -> None:
    """The same ledger the iOS release reads (2026-10-07), run in the main iOS
    worktree so HEAD is the iOS tip: every iOS commit Android still owes is
    listed. A production release refuses while any is open; a testing track
    only prints them. ANDROID_GATE=skip passes it and says so."""
    first = subprocess.run(["git", "-C", pl.ROOT, "worktree", "list", "--porcelain"],
                           text=True, capture_output=True).stdout.splitlines()
    ios = next((l.split(" ", 1)[1] for l in first if l.startswith("worktree ")), "")
    ledger = os.path.join(ios, "scripts/android-sync/ledger.py")
    if not os.path.exists(ledger):
        print("! Android ledger not found in the iOS worktree — not checked.")
        return
    strict = track == "production"
    r = subprocess.run([sys.executable, ledger] + (["--gate", "store"] if strict else []),
                       text=True, capture_output=True)
    out = r.stdout.split("## 옮김")[0].strip()
    print(out + ("\n" + r.stderr.strip() if r.stderr.strip() else ""))
    if strict and r.returncode and send:
        sys.exit("Android owes iOS work — a production release waits for it.")

    # One version number for one feature set (2026-10-07): Android's
    # versionName is the iOS marketing version it matches, so "1.1.4" means
    # the same app on both stores and in analytics' app_version. versionCode
    # stays Play's own counter. --match-ios writes it.
    want = ios_version(ios)
    _, have = version()
    if "--match-ios" in sys.argv and want and want != have:
        set_version_name(want)
        print(f"versionName {have} → {want} (iOS)")
        have = want
    if want and have != want:
        print(f"! versionName {have} ≠ iOS {want} — run with --match-ios once the ledger is clear.")
        if strict and send:
            sys.exit("A production release carries the iOS version it matches.")


def main() -> None:
    args = sys.argv[1:]
    if args[:1] == ["released"]:
        released(args[1:])
        return
    send = "--send" in args
    track = args[args.index("--track") + 1] if "--track" in args else "internal"
    if "--bump" in args:
        print(f"versionCode → {bump()}")
    code, name = version()
    rel_notes = notes(code)
    android_gate(track, send)
    code, name = version()

    if "--no-build" not in args:
        print(f"Building {name} ({code})…")
        build()
    if not os.path.exists(AAB):
        sys.exit(f"No bundle at {AAB}.")
    size = os.path.getsize(AAB) / 1e6
    print(f"Bundle {name} ({code}), {size:.1f} MB, signed")
    print(f"Track {track} · notes in {', '.join(n['language'] for n in rel_notes)}")

    pl.TOKEN = pl.token()
    edit = pl.call("POST", "/edits", {})["id"]
    try:
        have = {b["versionCode"] for b in pl.call("GET", f"/edits/{edit}/bundles").get("bundles", [])}
        if code in have:
            sys.exit(f"versionCode {code} is already on Play — run with --bump.")
        current = pl.call("GET", f"/edits/{edit}/tracks/{track}")
        live = [r for r in current.get("releases", []) if r.get("status") != "draft"]
        status = "completed" if any(
            r.get("status") == "completed"
            for t in pl.call("GET", f"/edits/{edit}/tracks").get("tracks", [])
            for r in t.get("releases", [])) else "draft"
        print(f"Release status: {status}" + ("" if live else " (track has nothing live yet)"))
        if not send:
            print("\nDry run — nothing uploaded. Run again with --send.")
            return

        print("Uploading bundle…")
        raw = open(AAB, "rb").read()
        up = pl.call("POST", f"{pl.UPLOAD}/edits/{edit}/bundles?uploadType=media", raw=raw,
                     ctype="application/octet-stream")
        print(f"  uploaded versionCode {up['versionCode']}")
        pl.call("PUT", f"/edits/{edit}/tracks/{track}", {
            "track": track,
            "releases": [{"name": f"{name} ({code})", "versionCodes": [str(code)],
                          "status": status, "releaseNotes": rel_notes}],
        })
        pl.call("POST", f"/edits/{edit}:commit")
        edit = None
        print(f"Committed to {track} as {status}.")
        # A sideloaded install can be told now; a Play install waits for
        # review — `released` (release-watch runs it) moves latest_build.
        if supabase_sql("update public.app_release set latest_beta_build = "
                        f"greatest(coalesce(latest_beta_build, 0), {code}) "
                        "where platform = 'android';") is not None:
            print(f"▸ app_release (android).latest_beta_build → {code}")
        publish_note_sections(code)
        print("Play installs are told once review is done: release-watch runs "
              "`play-release.py released --watch` every 30 min.")
    finally:
        if edit:
            try:
                pl.call("DELETE", f"/edits/{edit}")
            except RuntimeError:
                pass


if __name__ == "__main__":
    main()
