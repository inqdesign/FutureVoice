#!/usr/bin/env python3
"""Build the signed bundle and put it on a Google Play track — the Play twin of
`scripts/beta.sh`. Plan 7.5.

    scripts/android/play-release.py                     # build + plan (dry run)
    scripts/android/play-release.py --bump              # versionCode +1 first
    scripts/android/play-release.py --send              # upload to internal
    scripts/android/play-release.py --send --track alpha   # closed testing
    scripts/android/play-release.py --no-build --send   # upload the AAB already built

Release notes ride on the release, one per language, from
android/fastlane/metadata/android/<folder>/changelogs/<versionCode>.txt —
the same files fastlane `supply` reads. A version with no en-US notes is
refused: the notes are what a tester sees in the Play app, and "no notes" is
how a placeholder ships.

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
JAVA_HOME = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"

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


def main() -> None:
    args = sys.argv[1:]
    send = "--send" in args
    track = args[args.index("--track") + 1] if "--track" in args else "internal"
    if "--bump" in args:
        print(f"versionCode → {bump()}")
    code, name = version()
    rel_notes = notes(code)

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
    finally:
        if edit:
            try:
                pl.call("DELETE", f"/edits/{edit}")
            except RuntimeError:
                pass


if __name__ == "__main__":
    main()
