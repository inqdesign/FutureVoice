#!/usr/bin/env python3
"""Copy rendered carousels into the website for nawana.app/community.

Reads episodes/series-<lang>.json (the board's export) and out/<lang>/<id>/NN.png
(render.py's output) and writes:

    web/community/series/<id>-NN.jpg   720×900, the feed size halved for the web
    web/community/series.json          what the page lists, in board order

Only episodes marked 완성 (status "done") go on the site. `--include-drafts`
adds 초안 ones too — for a preview, never for production: a draft can still
carry a screen with a sample-data glitch on it.

The site uses the LIGHT render (render.py --theme light): dark cards on the
light page read poorly.

    python3 scripts/feature-series/publish-web.py
    python3 scripts/feature-series/publish-web.py --include-drafts
"""
import argparse, glob, json, os, shutil
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WEB = os.path.join(ROOT, "web", "community")

# English labels for the page chrome around the (Korean) carousels.
EN = {
    "e01": ("nawana at a glance", "Call your fluent self, in your own voice"),
    "e02": ("One call", "One tap, then take turns like a phone call"),
    "e03": ("Call settings", "It talks at your pace and your level"),
    "e04": ("Corrections", "Mistakes are fine. Your fluent self says it right"),
    "e05": ("Every call, a book", "Each call becomes a study book"),
    "e06": ("The daily call", "Your fluent self calls at the time you pick"),
    "e07": ("Watch first", "See your fluent self handle it before you do"),
    "e08": ("Your own situation", "Rehearse what's actually coming up"),
    "e09": ("Practice with people", "Talk with friends and coworkers, in their own tone"),
    "e10": ("Today's review", "Everything to review today, in one place"),
    "e11": ("Say it again", "The same conversation, done right this time"),
    "e12": ("Shadowing", "Repeat after your own fluent voice"),
    "e13": ("Words", "Words from your calls collect themselves"),
    "e14": ("Expressions", "Make your future self's phrases your own"),
    "e15": ("Sentence cards", "The sentences you got wrong become cards"),
    "e16": ("Weekly test", "A test made only from what you learned this week"),
    "e17": ("Progress", "See your level from conversation alone"),
    "e18": ("Activity & day card", "Your study days add up, and each day becomes a card"),
    "e19": ("Home screen widget", "Today's words without opening the app"),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default="ko")
    ap.add_argument("--include-drafts", action="store_true")
    ap.add_argument("--theme", choices=["light", "dark"], default="light",
                    help="light (default) reads out/<lang>-light/, the paper-ground render made for the site")
    a = ap.parse_args()

    series = json.load(open(os.path.join(HERE, "episodes", f"series-{a.lang}.json"), encoding="utf-8"))
    series.sort(key=lambda e: e.get("order", 0))
    ok = {"done", "draft"} if a.include_drafts else {"done"}

    out_dir = os.path.join(WEB, "series")
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    listed = []
    for e in series:
        if e.get("status") not in ok:
            continue
        src = a.lang + ("-light" if a.theme == "light" else "")
        pngs = sorted(glob.glob(os.path.join(HERE, "out", src, e["id"], "[0-9][0-9].png")))
        if not pngs:
            print(f"skip {e['id']}: not rendered")
            continue
        slides = []
        for p in pngs:
            name = f"{e['id']}-{os.path.basename(p)[:-4]}.jpg"
            Image.open(p).convert("RGB").resize((720, 900), Image.LANCZOS).save(
                os.path.join(out_dir, name), quality=82, optimize=True, progressive=True)
            slides.append(f"/community/series/{name}")
        en = EN.get(e["id"], (e["short"], e.get("tagline", "")))
        listed.append({"id": e["id"], "cat": e["cat"], "slides": slides,
                       "ko": {"title": e["short"], "tagline": e.get("tagline", "")},
                       "en": {"title": en[0], "tagline": en[1]}})
    json.dump({"episodes": listed}, open(os.path.join(WEB, "series.json"), "w"), ensure_ascii=False, indent=1)
    size = sum(os.path.getsize(p) for p in glob.glob(os.path.join(out_dir, "*.jpg")))
    print(f"{len(listed)} episodes, {sum(len(x['slides']) for x in listed)} slides, {size/1e6:.1f} MB → {WEB}")


if __name__ == "__main__":
    main()
