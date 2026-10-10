#!/usr/bin/env python3
"""One carousel, one feature per slide — the app-store "tour" look.

Cream ground with a soft sky halo, the phone hanging from the top and fading
into the ground mid-screen, one big title and a two-line caption under it,
and a floating card (a crop of a screen, or the app icon) lifted off the
phone's right edge. Every screen is the REAL app (the same shots render.py
uses: shots/<lang>/ first, then out/<lang>/raw/).

    python3 scripts/feature-series/tour.py --lang ko     # → out/ko-tour/01.png …
"""
import argparse, json, os
from PIL import Image, ImageDraw, ImageFilter

import render as R   # phone frame + font cascade

HERE = R.HERE
W, H, SS = 1080, 1350, R.SS
s = R.s

BG = (253, 251, 242)
HALO = (196, 228, 246)
TX = (36, 24, 20)
DIM = (112, 100, 94)

PHONE_W = 780
PHONE_TOP = 170
FADE_FROM, FADE_TO = 800, 965      # 1080 space: the phone dissolves into the ground here


def shot_path(lang, name):
    p = os.path.join(HERE, "shots", lang, name + ".png")
    return p if os.path.exists(p) else os.path.join(HERE, "out", lang, "raw", name + ".png")


def halo(canvas):
    lay = Image.new("RGBA", canvas.size, HALO + (0,))
    a = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(a).ellipse([s(40), s(260), s(W - 40), s(980)], fill=230)
    lay.putalpha(a.filter(ImageFilter.GaussianBlur(s(150))))
    canvas.alpha_composite(lay)


def phone(canvas, path):
    ph = R.build_phone(path)
    ph = ph.resize((s(PHONE_W), int(ph.height * s(PHONE_W) / ph.width)), Image.LANCZOS)
    x, y = s(W / 2) - ph.width // 2, s(PHONE_TOP)
    # vertical fade: full until FADE_FROM, gone by FADE_TO
    fade = Image.new("L", ph.size, 255)
    fd = ImageDraw.Draw(fade)
    for yy in range(ph.height):
        gy = (y + yy) / SS
        v = 255 if gy < FADE_FROM else max(0, int(255 * (1 - (gy - FADE_FROM) / (FADE_TO - FADE_FROM))) )
        if v < 255:
            fd.line([(0, yy), (ph.width, yy)], fill=v)
    alpha = Image.composite(ph.split()[3], Image.new("L", ph.size, 0), fade)
    from PIL import ImageChops
    ph.putalpha(ImageChops.multiply(ph.split()[3], fade))
    # soft drop shadow
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sa = Image.new("L", canvas.size, 0)
    sa.paste(alpha.point(lambda v: v * 40 // 255), (x, y + s(24)))
    sh.putalpha(sa.filter(ImageFilter.GaussianBlur(s(40))))
    canvas.alpha_composite(sh)
    canvas.alpha_composite(ph, (x, y))


def float_card(canvas, img, width, cx, cy, angle=-5, radius=40, pad=0):
    img = img.convert("RGB")
    if pad:
        bgc = img.getpixel((2, 2))
        big = Image.new("RGB", (img.width + 2 * pad, img.height + 2 * pad), bgc)
        big.paste(img, (pad, pad)); img = big
    img = img.resize((s(width), int(img.height * s(width) / img.width)), Image.LANCZOS)
    card = Image.new("RGBA", (img.width + s(8), img.height + s(8)), (0, 0, 0, 0))
    m = Image.new("L", card.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, card.width - 1, card.height - 1], radius=s(radius + 4), fill=255)
    rim = Image.new("RGBA", card.size, (255, 255, 255, 255)); rim.putalpha(m)
    card.alpha_composite(rim)
    im = Image.new("L", img.size, 0)
    ImageDraw.Draw(im).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=s(radius), fill=255)
    ic = img.convert("RGBA"); ic.putalpha(im)
    card.alpha_composite(ic, (s(4), s(4)))
    card = card.rotate(angle, resample=Image.BICUBIC, expand=True)
    x, y = s(cx) - card.width // 2, s(cy) - card.height // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sa = Image.new("L", canvas.size, 0)
    sa.paste(card.split()[3].point(lambda v: v * 70 // 255), (x, y + s(22)))
    shadow.putalpha(sa.filter(ImageFilter.GaussianBlur(s(34))))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(card, (x, y))


def fonts():
    F = R.Face
    return dict(title=R.Cascade([F(R.SDG, 100, 4)]),
                cap=R.Cascade([F(R.SDG, 37, 2)]),
                word=R.Cascade([F(R.GEIST, 150)]),
                url=R.Cascade([F(R.MENLO, 32)], tracking=1.5))


def centered(d, casc, y, text, fill):
    casc.draw(d, s(W / 2) - casc.width(text) / 2, s(y), text, fill)


def render(slide, lang, F):
    canvas = Image.new("RGBA", (s(W), s(H)), BG + (255,))
    halo(canvas)
    d = ImageDraw.Draw(canvas)
    if slide.get("kind") == "outro":
        centered(d, F["word"], 640, "nawana", TX)
        y = 760
        for line in slide["caption"].split("\n"):
            centered(d, F["cap"], y, line, DIM); y += 54
        centered(d, F["url"], y + 70, "nawana.app", (53, 88, 240))
        return canvas
    phone(canvas, shot_path(lang, slide["shot"]))
    fl = slide.get("float")
    if fl:
        if fl.get("icon"):
            img = Image.open(os.path.join(R.ROOT, "FutureVoice/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"))
            float_card(canvas, img, fl.get("width", 230), fl.get("x", 900), fl.get("y", 640), fl.get("angle", -6), radius=52)
        else:
            src = Image.open(shot_path(lang, fl.get("shot", slide["shot"])))
            float_card(canvas, src.crop(tuple(fl["crop"])), fl.get("width", 440),
                       fl.get("x", 820), fl.get("y", 690), fl.get("angle", -4), pad=fl.get("pad", 24))
    d = ImageDraw.Draw(canvas)
    centered(d, F["title"], 1072, slide["title"], TX)
    y = 1150
    for line in slide["caption"].split("\n"):
        centered(d, F["cap"], y, line, DIM); y += 54
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default="ko")
    ap.add_argument("--only", type=int, default=0, help="render only slide N (1-based)")
    a = ap.parse_args()
    slides = json.load(open(os.path.join(HERE, "episodes", f"tour-{a.lang}.json"), encoding="utf-8"))
    out = os.path.join(HERE, "out", f"{a.lang}-tour")
    os.makedirs(out, exist_ok=True)
    F = fonts()
    for i, sl in enumerate(slides, 1):
        if a.only and i != a.only:
            continue
        img = render(sl, a.lang, F).convert("RGB")   # 2160×2700, full supersampled size
        img.save(os.path.join(out, f"{i:02d}.png"), optimize=True)
    print(len(slides), "slides →", out)


if __name__ == "__main__":
    main()
