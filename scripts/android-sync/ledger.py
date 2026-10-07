#!/usr/bin/env python3
"""What Android owes iOS — the one list both platforms are kept in step by.

    scripts/android-sync/ledger.py                  # the report
    scripts/android-sync/ledger.py --gate testflight   # exit 1 on an unclassified commit
    scripts/android-sync/ledger.py --gate store        # exit 1 on anything still owed

Since 2026-10-07 every iOS commit that touches the app, the widget, the server
or the gateway says what it means for Android, in a trailer the commit-msg hook
(`scripts/hooks/commit-msg`) insists on:

    Android: 3fb869e6           ported in the same session — the Android commit
    Android: todo <what>        owed; closed when an Android commit names this sha
    Android: n/a <why>          nothing to port (iOS-only platform, server-only…)

An Android commit closes a `todo` by naming the iOS commit — `iOS: <sha>` as a
trailer, or "(iOS <sha>)" in the subject, the way feat/android has always
written it. Commits made before the hook (or with --no-verify) are classified
in `overrides.tsv`; history before `start` was the master plan's catch-up and
is not this ledger's.

The gates: a TestFlight build may carry owed work (iteration must not wait on
Android), but not an UNCLASSIFIED commit — someone has to have decided. An App
Store submission may carry neither: what reaches iOS learners reaches Android's
next build. `ANDROID_GATE=skip` passes either gate and says so out loud.
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = subprocess.check_output(["git", "-C", HERE, "rev-parse", "--show-toplevel"], text=True).strip()
PATHS = ["FutureVoice", "FutureVoiceWidget", "supabase", "gateway"]
ANDROID_BRANCH = os.environ.get("ANDROID_BRANCH", "feat/android")
# Release bumps, catalog merges and the admin console never carry Android work.
SKIP_SUBJECT = re.compile(r"^(chore\((release|i18n)\)|[a-z]+\(admin\)|fixup!|squash!)")
# The Swift sources scripts/android/gen-vectors.sh compiles into the golden
# vectors Android's tests read. A commit that changes one changed a rule both
# platforms must compute identically, so it can never be `n/a`.
CONTRACT_FILES = {f"FutureVoice/{p}.swift" for p in (
    "Models/Models", "Services/CarryoverDetector", "Services/DrillStore", "Services/ScorecardMetrics",
    "Services/ShadowEngine", "Services/LanguageCatalog", "Services/WordSplitter",
    "Services/JapaneseMorph", "Services/TextScript")}
HEX = re.compile(r"\b[0-9a-f]{7,40}\b")


def git(*args, check=True):
    r = subprocess.run(["git", "-C", ROOT, *args], text=True, capture_output=True)
    if check and r.returncode:
        sys.exit(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def classify(value):
    """(kind, detail) for a trailer value; kind is done / todo / na / bad."""
    v = value.strip()
    low = v.lower()
    if low.startswith("n/a"):
        return "na", v[3:].lstrip(" —-:")
    if low.startswith("todo"):
        return "todo", v[4:].lstrip(" —-:")
    m = re.match(r"(?:done\s+)?([0-9a-f]{7,40})\b", low)
    if m:
        return "done", m.group(1)
    # The free-text form the 2026-09-21 rule used ("Android: Speech 패리티 때
    # 같이") — a decision that something is owed, so it is owed.
    return "todo", v


def android_closures():
    """iOS sha prefixes named by any commit on the Android branch."""
    if not git("rev-parse", "--verify", "-q", ANDROID_BRANCH, check=False).strip():
        return set(), False
    named = set()
    for line in git("log", ANDROID_BRANCH, "--format=%B").splitlines():
        if re.search(r"\biOS\b", line):
            named.update(HEX.findall(line.lower()))
    return named, True


def on_android(sha):
    return subprocess.run(["git", "-C", ROOT, "merge-base", "--is-ancestor", sha, ANDROID_BRANCH],
                          capture_output=True).returncode == 0


def main():
    gate = None
    if "--gate" in sys.argv:
        gate = sys.argv[sys.argv.index("--gate") + 1]
        if gate not in ("testflight", "store"):
            sys.exit("--gate testflight | store")

    start = os.environ.get("ANDROID_LEDGER_START") or open(os.path.join(HERE, "start")).read().strip()
    overrides = {}
    for line in open(os.path.join(HERE, "overrides.tsv"), encoding="utf-8"):
        if line.strip() and not line.startswith("#"):
            sha, value = line.rstrip("\n").split("\t", 1)
            overrides[sha.lower()] = value

    closures, have_android = android_closures()
    rows = {"owed": [], "unclassified": [], "done": [], "na": []}
    log = git("log", "--no-merges", "--reverse", "--format=%H%x1f%s%x1f%b%x1d",
              f"{start}..HEAD", "--", *PATHS)
    for entry in filter(None, (e.strip("\n") for e in log.split("\x1d"))):
        sha, subject, body = (entry.split("\x1f") + ["", ""])[:3]
        short = sha[:8]
        if SKIP_SUBJECT.match(subject):
            continue
        # Read off the body, not git's trailer parser: the line has often been
        # written as its own paragraph above Co-Authored-By, which the parser
        # (last paragraph only) never sees.
        found = re.findall(r"^Android:[ \t]*(.*\S)", body, re.M | re.I)
        value = found[-1] if found else ""
        value = value or next((v for k, v in overrides.items() if sha.startswith(k)), "")
        line = f"{short} {subject}"
        if not value:
            rows["unclassified"].append(line)
            continue
        kind, detail = classify(value)
        closed = any(sha.startswith(c) for c in closures if len(c) >= 7)
        touched = set(git("show", "--name-only", "--format=", sha).split()) & CONTRACT_FILES
        if touched and kind == "na" and not closed:
            kind, detail = "todo", (f"marked n/a, but it changes {', '.join(sorted(os.path.basename(t) for t in touched))} — "
                                    "port the rule and re-run scripts/android/gen-vectors.sh on feat/android")
        if kind == "na":
            rows["na"].append(f"{line}\n      → {detail or 'n/a'}")
        elif kind == "done":
            if closed or (have_android and on_android(detail)):
                rows["done"].append(f"{line}\n      → Android {detail}")
            else:
                rows["owed"].append(f"{line}\n      → claims Android {detail}, which is not on {ANDROID_BRANCH}")
        elif closed:
            rows["done"].append(f"{line}\n      → {detail} (closed on {ANDROID_BRANCH})")
        else:
            rows["owed"].append(f"{line}\n      → {detail}")

    print(f"# Android ledger — iOS {start[:8]}..HEAD against {ANDROID_BRANCH}\n")
    for key, title in (("owed", "안드로이드가 갚을 것"), ("unclassified", "분류 안 됨 — Android: 줄이 없음"),
                       ("done", "옮김"), ("na", "해당 없음")):
        items = rows[key]
        print(f"## {title} ({len(items)})")
        for l in items if key in ("owed", "unclassified") else items[-10:]:
            print(f"- {l}")
        if key not in ("owed", "unclassified") and len(items) > 10:
            print(f"  … and {len(items) - 10} earlier")
        print()

    if not gate:
        return
    blocking = rows["unclassified"] + (rows["owed"] if gate == "store" else [])
    if not blocking:
        print(f"✓ Android gate ({gate}): clear")
        return
    if os.environ.get("ANDROID_GATE") == "skip":
        print(f"! Android gate ({gate}): {len(blocking)} open — SKIPPED by ANDROID_GATE=skip", file=sys.stderr)
        return
    what = "unclassified commits" if gate == "testflight" else "commits Android still owes or that are unclassified"
    print(f"✗ Android gate ({gate}): {len(blocking)} {what}.", file=sys.stderr)
    print("  Classify one: add a line to scripts/android-sync/overrides.tsv (<sha><TAB>n/a …|todo …).", file=sys.stderr)
    print("  Close one: port it on feat/android with `iOS: <sha>` in the commit.", file=sys.stderr)
    print("  Ship anyway (say why to the founder): ANDROID_GATE=skip", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
