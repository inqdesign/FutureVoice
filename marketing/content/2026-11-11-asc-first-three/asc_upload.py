#!/usr/bin/env python3
"""Put the new iPhone screenshots on an App Store version, every language.

    python3 asc_upload.py <version>            # dry run: what would change
    python3 asc_upload.py <version> --send     # replace the iPhone 6.9" and 6.5" sets

The version must be editable (PREPARE_FOR_SUBMISSION, or rejected): Apple locks
screenshots while a version is waiting for or in review. Korean comes from
G-set/ (the founder's own call screenshots), every other language from
sets/ios/<lang>/. The 6.5" files are the same pictures at 1242x2688.
The iPad 13" set (2064x2752) comes from sets/ipad/<lang>/.
"""
import hashlib, importlib.util, os, sys, tempfile, time, urllib.request
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("a", "/Users/eunggyuelee/FutureVoice/scripts/asc-submit.py")
a = importlib.util.module_from_spec(spec); sys.argv, argv = ["x"], sys.argv; spec.loader.exec_module(a); sys.argv = argv

# App Store locale → folder of ten 1320x2868 PNGs
FOLDERS = {
    "ko": f"{HERE}/G-set",
    "en-GB": f"{HERE}/sets/ios/en", "en-US": f"{HERE}/sets/ios/en",
    "ja": f"{HERE}/sets/ios/ja",
    "zh-Hans": f"{HERE}/sets/ios/zh-Hans", "zh-Hant": f"{HERE}/sets/ios/zh-Hant",
    "es-ES": f"{HERE}/sets/ios/es", "es-MX": f"{HERE}/sets/ios/es",
    "fr-FR": f"{HERE}/sets/ios/fr", "de-DE": f"{HERE}/sets/ios/de",
}


# App Store locale → our language folder, for the iPad set
IPAD = {"ko": "ko", "en-GB": "en", "en-US": "en", "ja": "ja", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
        "es-ES": "es", "es-MX": "es", "fr-FR": "fr", "de-DE": "de"}


def files(folder, kind):
    names = sorted(n for n in os.listdir(folder) if n.endswith(".png"))
    assert len(names) == 10, f"{folder}: {len(names)} files"
    if kind in ("APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129"):
        return [(n, open(f"{folder}/{n}", "rb").read()) for n in names]
    out = []
    for n in names:
        im = Image.open(f"{folder}/{n}").convert("RGB")
        im = im.resize((1242, round(im.height * 1242 / im.width)), Image.LANCZOS)
        top = (im.height - 2688) // 2
        im = im.crop((0, top, 1242, top + 2688))
        p = tempfile.mktemp(suffix=".png"); im.save(p)
        out.append((n, open(p, "rb").read())); os.remove(p)
    return out


def retry(fn, tries=6):
    for i in range(tries):
        try:
            return fn()
        except Exception as e:          # the upload host resets connections now and then
            if i == tries - 1:
                raise
            print("    retry:", str(e)[:80]); time.sleep(5 * (i + 1))


def upload(set_id, shots):
    """Resumable: a screenshot already COMPLETE under the same file name stays; the rest is
    replaced. RESUME=1 keeps finished ones (a re-run after a dropped connection)."""
    keep = set()
    for s in retry(lambda: a.call("GET", f"/appScreenshotSets/{set_id}/appScreenshots?limit=50")["data"]):
        done = s["attributes"]["assetDeliveryState"]["state"] == "COMPLETE"
        if os.environ.get("RESUME") and done:
            keep.add(s["attributes"]["fileName"]); continue
        retry(lambda: a.call("DELETE", f"/appScreenshots/{s['id']}"))
    for name, raw in shots:
        if name in keep:
            continue
        def one():
            shot = a.call("POST", "/appScreenshots", {"data": {"type": "appScreenshots",
                "attributes": {"fileName": name, "fileSize": len(raw)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
            try:
                for op in shot["attributes"]["uploadOperations"]:
                    req = urllib.request.Request(op["url"], data=raw[op["offset"]:op["offset"] + op["length"]], method=op["method"])
                    for h in op.get("requestHeaders") or []: req.add_header(h["name"], h["value"])
                    urllib.request.urlopen(req, timeout=120).read()
                a.call("PATCH", f"/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
                    "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(raw).hexdigest()}}})
            except Exception:
                try: a.call("DELETE", f"/appScreenshots/{shot['id']}")
                except Exception: pass
                raise
        retry(one)
        print("    up", name)


def main():
    version, send = sys.argv[1], "--send" in sys.argv
    vs = a.call("GET", f"/apps/{a.APP_ID}/appStoreVersions?filter[platform]=IOS&limit=10")["data"]
    v = next(x for x in vs if x["attributes"]["versionString"] == version)
    print(version, v["attributes"]["appStoreState"])
    locs = a.call("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50")["data"]
    for loc in locs:
        code = loc["attributes"]["locale"]
        folder = FOLDERS.get(code)
        only = os.environ.get("LOCALES")
        if only and code not in only.split(","):
            continue
        if not folder:
            print(f"  {code}: no set, left alone"); continue
        sets = a.call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50")["data"]
        for kind in ("APP_IPHONE_67", "APP_IPHONE_65", "APP_IPAD_PRO_3GEN_129"):
            src = f"{HERE}/sets/ipad/{IPAD[code]}" if kind.startswith("APP_IPAD") else folder
            s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == kind), None)
            print(f"  {code} {kind}: {'replace' if s else 'create'} with {src}")
            if not send: continue
            if s is None:
                s = a.call("POST", "/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": kind},
                    "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
            upload(s["id"], files(src, kind))
    if send:
        time.sleep(20)
        print("uploaded; check states in App Store Connect")
    else:
        print("Dry run. Add --send.")


main()
