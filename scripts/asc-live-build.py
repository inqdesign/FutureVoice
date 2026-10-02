#!/usr/bin/env python3
"""The build App Store installs are getting right now, straight from App Store
Connect: prints `<version> <build>` and writes the live version's "What's New"
(ko, en) to the two paths given, for scripts/release-watch.sh.

    python3 scripts/asc-live-build.py <ko_notes_out> <en_notes_out>

The iTunes lookup knows the VERSION but never the build number, and the update
sheet compares build numbers — this is the one place that knows both.
"""
import importlib.util
import os
import sys

out_ko, out_en = sys.argv[1], sys.argv[2]
_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("asc", os.path.join(_here, "asc-annual-prices.py"))
A = importlib.util.module_from_spec(_spec)
sys.argv = sys.argv[:1]
_spec.loader.exec_module(A)

APP_ID = "6792794655"
d = A.call("GET", f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS"
                  f"&filter[appStoreState]=READY_FOR_SALE&include=build&limit=1")
if not d.get("data"):
    sys.exit("no READY_FOR_SALE version")
ver = d["data"][0]
builds = [i for i in d.get("included", []) if i["type"] == "builds"]
if not builds:
    sys.exit("live version has no build attached")
version = ver["attributes"]["versionString"]
build = builds[0]["attributes"]["version"]

locs = A.call("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")["data"]
notes = {l["attributes"]["locale"]: (l["attributes"].get("whatsNew") or "") for l in locs}
en = notes.get("en-US") or notes.get("en-GB") or ""
open(out_ko, "w").write(notes.get("ko") or en)
open(out_en, "w").write(en)
print(version, build)
