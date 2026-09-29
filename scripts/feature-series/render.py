#!/usr/bin/env python3
"""Render a feature-series episode as a 4:5 social carousel (1080×1350 PNGs).

Every slide is the REAL app: screenshots come from the DEBUG `-capture`
harness on a simulator (see `capture.sh`), dropped into a drawn iPhone and
captioned in the brand's look — ink ground, pixel headline (Galmuri14, the
app's own display face for Hangul), system Hangul body, the mosaic blue as
the one accent. An episode is data (`episodes/<name>.json`); this file only
knows how to draw the four slide kinds:

    zoom    a region of a screenshot, lifted out as a floating card (the hook)
    top     text above, phone rising from the bottom edge
    bottom  phone hanging from the top edge, text below
    outro   wordmark · tagline · URL

    python3 scripts/feature-series/render.py correction --lang ko
    python3 scripts/feature-series/render.py correction --lang ko --video   # + a 9:16-safe MP4 slideshow

Headline markup: `[word]` draws that word in the accent colour.
"""
import argparse, json, os, re, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

W, H = 1080, 1350
SS = 2                                    # supersample: draw at 2x, downsample once
BG = (18, 17, 16)
TX, DIM, FAINT = (237, 236, 232), (156, 154, 148), (96, 94, 90)
ACCENT = (64, 100, 245)
GLOW = (64, 100, 245, 0.28)      # colour + strength of the halo behind the phone
CARD_SHADOW = (64, 100, 245, 70) # the zoom card's shadow
HILITE = (33, 44, 92)            # the lit category tab on a cover

THEMES = {
    # The brand's ink ground — the feed carousels as first designed.
    "dark": dict(BG=(18, 17, 16), TX=(237, 236, 232), DIM=(156, 154, 148), FAINT=(96, 94, 90),
                 ACCENT=(64, 100, 245), GLOW=(64, 100, 245, 0.28), CARD_SHADOW=(64, 100, 245, 70),
                 HILITE=(33, 44, 92)),
    # Paper ground for the website, where dark cards on a light page read poorly.
    "light": dict(BG=(250, 249, 246), TX=(27, 26, 24), DIM=(92, 90, 84), FAINT=(146, 143, 136),
                  ACCENT=(53, 88, 240), GLOW=(27, 26, 24, 0.20), CARD_SHADOW=(27, 26, 24, 45),
                  HILITE=(226, 233, 255)),
}


def apply_theme(name):
    globals().update(THEMES[name])
MARGIN = 84

SDG = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
GALMURI = os.path.expanduser("~/Library/Fonts/Galmuri14.otf")
if not os.path.exists(GALMURI):
    GALMURI = os.path.join(ROOT, "FutureVoice/Resources/Fonts/Galmuri14.ttf")
GEIST = os.path.join(ROOT, "web/GeistPixel.ttf")
MENLO = "/System/Library/Fonts/Menlo.ttc"


# ── fonts: first face whose cmap has the glyph wins (same idea as render-voice-video) ──
class Face:
    def __init__(self, path, size, index=0):
        self.font = ImageFont.truetype(path, size * SS, index=index)
        tt = TTFont(path, fontNumber=index if path.endswith(".ttc") else -1, lazy=True)
        self.cmap = set(tt.getBestCmap().keys())


class Cascade:
    def __init__(self, faces, tracking=0.0):
        self.faces, self.tracking = faces, tracking * SS

    def runs(self, text):
        out, cur, curf = [], "", None
        for ch in text:
            f = next((f for f in self.faces if ord(ch) in f.cmap), self.faces[-1])
            if ch == " ":
                f = curf or f
            if f is not curf and cur:
                out.append((curf, cur)); cur = ""
            cur += ch; curf = f
        if cur:
            out.append((curf, cur))
        return out

    def width(self, text):
        return sum(f.font.getlength(r) + self.tracking * len(r) for f, r in self.runs(text))

    def draw(self, d, x, y, text, fill):          # x, y in SS space; y = baseline
        for f, r in self.runs(text):
            if self.tracking:
                for ch in r:
                    d.text((x, y), ch, font=f.font, fill=fill, anchor="ls")
                    x += f.font.getlength(ch) + self.tracking
            else:
                d.text((x, y), r, font=f.font, fill=fill, anchor="ls")
                x += f.font.getlength(r)
        return x


def fonts():
    return dict(
        # 56 = 4× Galmuri14's grid, so the pixels stay square after the 2x downsample.
        head=Cascade([Face(GALMURI, 56), Face(SDG, 54, 6)]),
        body=Cascade([Face(SDG, 33, 2)]),
        eyebrow=Cascade([Face(SDG, 25, 4)], tracking=1.5),
        count=Cascade([Face(MENLO, 23)], tracking=1),
        wordmark=Cascade([Face(GEIST, 132)]),
        tag=Cascade([Face(SDG, 40, 4)]),
        url=Cascade([Face(MENLO, 30)], tracking=1.5),
        # cover: 112 = 8× Galmuri14's grid
        cover=Cascade([Face(GALMURI, 112), Face(SDG, 104, 6)]),
        toc=Cascade([Face(SDG, 29, 2)]),
        toc_on=Cascade([Face(SDG, 29, 6)]),
        toc_head=Cascade([Face(SDG, 21, 4)], tracking=2),
        toc_num=Cascade([Face(MENLO, 21)]),
        tagline=Cascade([Face(SDG, 40, 2)]),
    )


def s(v):
    return int(round(v * SS))


# ── the phone ──────────────────────────────────────────────────────────────
# Built at the screenshot's own resolution (1206×2622, iPhone 17 Pro @3x),
# then scaled once. Screen corner radius ≈ 62 pt → 186 px.
SCREEN_R = 186
BEZEL = 30          # black glass border around the screen
RIM = 9             # titanium band outside it
TITANIUM = (58, 57, 60)
TITANIUM_HI = (104, 103, 108)


def build_phone(shot_path):
    shot = Image.open(shot_path).convert("RGB")
    sw, sh = shot.size
    pad = BEZEL + RIM
    btn = 7                                    # side buttons stand this far proud
    pw, ph = sw + 2 * pad + 2 * btn, sh + 2 * pad
    ph_img = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    d = ImageDraw.Draw(ph_img)
    ox = btn
    # side buttons (action + volume left, power right)
    for (y0, y1) in [(500, 640), (760, 990), (1060, 1290)]:
        d.rounded_rectangle([0, y0, ox + 10, y1], radius=6, fill=TITANIUM)
    d.rounded_rectangle([pw - ox - 10, 860, pw, 1210], radius=6, fill=TITANIUM)
    # rim, highlight edge, glass
    R = SCREEN_R + pad
    d.rounded_rectangle([ox, 0, ox + sw + 2 * pad - 1, ph - 1], radius=R, fill=TITANIUM)
    d.rounded_rectangle([ox + 2, 2, ox + sw + 2 * pad - 3, ph - 3], radius=R - 2,
                        outline=TITANIUM_HI, width=2)
    d.rounded_rectangle([ox + RIM, RIM, ox + sw + 2 * pad - RIM - 1, ph - RIM - 1],
                        radius=SCREEN_R + BEZEL, fill=(6, 6, 7))
    # screen
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=SCREEN_R, fill=255)
    ph_img.paste(shot, (ox + pad, pad), mask)
    return ph_img


def place_phone(canvas, shot_path, width, x_center, top):
    """Paste a phone `width` px wide (1080 space) with its top at `top` (may be negative)."""
    ph = build_phone(shot_path)
    scale = s(width) / ph.width
    ph = ph.resize((s(width), int(ph.height * scale)), Image.LANCZOS)
    x = s(x_center) - ph.width // 2
    y = s(top)
    # soft shadow + faint accent glow so the phone lifts off the ink
    # (padded, or the blur is clipped to the phone's box and reads as a rectangle)
    pad = s(160)
    glow = Image.new("RGBA", (ph.width + 2 * pad, ph.height + 2 * pad), GLOW[:3] + (0,))
    glow.putalpha(Image.new("L", glow.size, 0))
    a = Image.new("L", glow.size, 0)
    a.paste(ph.split()[3].point(lambda v: int(v * GLOW[3])), (pad, pad))
    glow.putalpha(a.filter(ImageFilter.GaussianBlur(s(60))))
    _paste_clipped(canvas, glow, x - pad, y + s(30) - pad)
    _paste_clipped(canvas, ph, x, y)
    return ph.height / SS


def _paste_clipped(canvas, img, x, y):
    # alpha_composite refuses negative offsets; crop what hangs off the top/left
    cx, cy = max(0, -x), max(0, -y)
    img = img.crop((cx, cy, img.width, img.height))
    canvas.alpha_composite(img, (x + cx, y + cy))


# ── text ───────────────────────────────────────────────────────────────────
def draw_marked(d, casc, x, y, line, fill, accent):
    """Draw `line`, colouring [bracketed] spans with `accent`."""
    for part in re.split(r"(\[[^\]]+\])", line):
        if not part:
            continue
        if part.startswith("["):
            x = casc.draw(d, x, y, part[1:-1], accent)
        else:
            x = casc.draw(d, x, y, part, fill)


def text_block(d, F, slide, series, idx, total, top):
    """Eyebrow + counter, headline, body. Returns the y where it ended (1080 space)."""
    y = top
    # eyebrow: ● SERIES   ·····   2 / 6
    d.ellipse([s(MARGIN), s(y - 15), s(MARGIN + 12), s(y - 3)], fill=ACCENT)
    F["eyebrow"].draw(d, s(MARGIN + 24), s(y), series, DIM)
    cnt = f"{idx} / {total}"
    F["count"].draw(d, s(W - MARGIN) - F["count"].width(cnt), s(y), cnt, FAINT)
    y += 92
    for line in slide["title"].split("\n"):
        draw_marked(d, F["head"], s(MARGIN), s(y), line, TX, ACCENT)
        y += 74
    if slide.get("body"):
        y += 10
        for line in slide["body"].split("\n"):
            F["body"].draw(d, s(MARGIN), s(y), line, DIM)
            y += 48
    return y


def text_height(slide):
    h = 92 + 74 * len(slide["title"].split("\n"))
    if slide.get("body"):
        h += 10 + 48 * len(slide["body"].split("\n"))
    return h


# ── slides ─────────────────────────────────────────────────────────────────
def render_slide(slide, ep, idx, total, raw_dir, F):
    canvas = Image.new("RGBA", (s(W), s(H)), BG + (255,))
    kind = slide["kind"]
    series = ep["series"]

    if kind == "outro":
        d = ImageDraw.Draw(canvas)
        cy = H * 0.42
        wm = "nawana"
        F["wordmark"].draw(d, s(W / 2) - F["wordmark"].width(wm) / 2, s(cy), wm, TX)
        y = cy + 110
        for line in slide.get("tag", []):
            F["tag"].draw(d, s(W / 2) - F["tag"].width(line) / 2, s(y), line, TX)
            y += 58
        y += 60
        url = "nawana.app"
        F["url"].draw(d, s(W / 2) - F["url"].width(url) / 2, s(y), url, ACCENT)
        if slide.get("foot"):
            F["body"].draw(d, s(W / 2) - F["body"].width(slide["foot"]) / 2, s(H - 110), slide["foot"], FAINT)
        return canvas

    shot = os.path.join(raw_dir, slide["shot"] + ".png")

    if kind == "zoom":
        d = ImageDraw.Draw(canvas)
        end = text_block(d, F, slide, series, idx, total, 110)
        img = Image.open(shot).convert("RGB")
        x0, y0, x1, y1 = slide["crop"]
        crop = img.crop((x0, y0, x1, y1))
        cw = W - 2 * 56
        crop = crop.resize((s(cw), int(crop.height * s(cw) / crop.width)), Image.LANCZOS)
        # the card, with a rounded mask and a shadow
        mask = Image.new("L", crop.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, crop.width - 1, crop.height - 1], radius=s(44), fill=255)
        card = crop.convert("RGBA"); card.putalpha(mask)
        avail_top = end + 40
        ty = int(avail_top + max(0, (H - 70 - avail_top) - crop.height / SS) / 2)
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            [s(56), s(ty) + s(24), s(56) + crop.width, s(ty) + crop.height + s(24)],
            radius=s(44), fill=CARD_SHADOW)
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(s(50))))
        canvas.alpha_composite(card, (s(56), s(ty)))
        if BG[0] > 128:
            ImageDraw.Draw(canvas).rounded_rectangle([s(56), s(ty), s(56) + crop.width - 1, s(ty) + crop.height - 1],
                                                     radius=s(44), outline=(222, 219, 212), width=s(2))
        return canvas

    pw = slide.get("phone_width", 660)
    if kind == "top":
        d = ImageDraw.Draw(canvas)
        end = text_block(d, F, slide, series, idx, total, 110)
        place_phone(canvas, shot, pw, W / 2, end + slide.get("gap", 44))
        return canvas

    if kind == "bottom":
        th = text_height(slide)
        text_top = H - 70 - th + 16
        phone_bottom = text_top - 64
        ph_h = pw * (2622 + 2 * (BEZEL + RIM)) / (1206 + 2 * (BEZEL + RIM) + 14)
        place_phone(canvas, shot, pw, W / 2, phone_bottom - ph_h)
        d = ImageDraw.Draw(canvas)
        text_block(d, F, slide, series, idx, total, text_top + 16)
        return canvas

    if kind == "full":
        # The whole phone, uncropped: for screens whose top AND bottom both
        # carry the feature (a question above, its answer buttons below).
        d = ImageDraw.Draw(canvas)
        end = text_block(d, F, slide, series, idx, total, 110)
        top = end + 40
        full_w = 1206 + 2 * (BEZEL + RIM) + 14
        full_h = 2622 + 2 * (BEZEL + RIM)
        pw = min(660, (H - 56 - top) * full_w / full_h)
        place_phone(canvas, shot, pw, W / 2, top)
        return canvas

    raise SystemExit(f"unknown slide kind: {kind}")


CATS = [("start", "시작하기"), ("talk", "Talk"), ("watch", "Watch"),
        ("practice", "복습"), ("progress", "진행")]


def wrap_lines(casc, text, max_w):
    """Greedy word wrap in 1080 space (Korean breaks at spaces, like the app)."""
    out = []
    for para in text.split("\n"):
        cur = ""
        for w in para.split(" "):
            cand = (cur + " " + w).strip()
            if cur and casc.width(cand) / SS > max_w:
                out.append(cur); cur = w
            else:
                cur = cand
        out.append(cur)
    return out


def render_cover_category(ep, series_list, total, F, with_list):
    """A cover that stays true after the series grows: it names the CATEGORY
    (the app's own tabs, which don't change) and this episode — no episode
    numbers, no full index, so adding or reordering episodes never makes an
    already-posted cover wrong. `with_list` adds this category's episodes."""
    canvas = Image.new("RGBA", (s(W), s(H)), BG + (255,))
    d = ImageDraw.Draw(canvas)
    y = 110
    d.ellipse([s(MARGIN), s(y - 15), s(MARGIN + 12), s(y - 3)], fill=ACCENT)
    F["eyebrow"].draw(d, s(MARGIN + 24), s(y), "나와나 기능 소개", DIM)
    cat_name = dict(CATS)[ep["cat"]]
    # the five categories as a row of tabs, this one lit
    y = 250
    x = MARGIN
    for cid, name in CATS:
        on = cid == ep["cat"]
        wdt = F["toc_on"].width(name) / SS
        if on:
            d.rounded_rectangle([s(x - 18), s(y - 36), s(x + wdt + 18), s(y + 14)], radius=s(25), fill=HILITE)
        (F["toc_on"] if on else F["toc"]).draw(d, s(x), s(y), name, TX if on else FAINT)
        x += wdt + 52
    # title, then the one line that says what the feature is
    lines = ep.get("coverTitle", ep["short"]).split("\n")
    y = 660 - 65 * (len(lines) - 1)
    for line in lines:
        F["cover"].draw(d, s(MARGIN), s(y), line, TX)
        y += 130
    if ep.get("tagline"):
        y += 10
        for line in wrap_lines(F["tagline"], ep["tagline"], W - 2 * MARGIN):
            F["tagline"].draw(d, s(MARGIN), s(y), line, DIM)
            y += 58
    if with_list:
        mates = [e for e in series_list if e["cat"] == ep["cat"]]
        yy = max(y + 110, 860)
        F["toc_head"].draw(d, s(MARGIN), s(yy), f"{cat_name} 시리즈".upper(), FAINT)
        yy += 56
        for e in mates:
            on = e is ep
            if on:
                d.ellipse([s(MARGIN), s(yy - 20), s(MARGIN + 12), s(yy - 8)], fill=ACCENT)
            (F["toc_on"] if on else F["toc"]).draw(d, s(MARGIN + 32), s(yy), e["short"], TX if on else DIM)
            yy += 48
    F["body"].draw(d, s(MARGIN), s(H - 70), "옆으로 넘겨보세요  →", FAINT)
    url = "nawana.app"
    F["url"].draw(d, s(W - MARGIN) - F["url"].width(url), s(H - 70), url, ACCENT)
    return canvas


def render_cover(ep, series_list, total, F):
    """Slide 1 of every episode: its title over the whole series' contents,
    this episode lit. No screenshot — a clean ground, so the feed shows a
    series at a glance and each post says where it sits in it."""
    canvas = Image.new("RGBA", (s(W), s(H)), BG + (255,))
    d = ImageDraw.Draw(canvas)
    num = series_list.index(ep) + 1
    # eyebrow row
    y = 110
    d.ellipse([s(MARGIN), s(y - 15), s(MARGIN + 12), s(y - 3)], fill=ACCENT)
    F["eyebrow"].draw(d, s(MARGIN + 24), s(y), "나와나 기능 소개", DIM)
    cnt = f"1 / {total}"
    F["count"].draw(d, s(W - MARGIN) - F["count"].width(cnt), s(y), cnt, FAINT)
    # episode number + title
    y = 250
    no = f"{num:02d}"
    F["toc_num"].draw(d, s(MARGIN), s(y), f"EP. {no} / {len(series_list):02d}", ACCENT)
    y += 138
    for line in ep.get("coverTitle", ep["short"]).split("\n"):
        F["cover"].draw(d, s(MARGIN), s(y), line, TX)
        y += 130
    # contents, two columns
    top = max(y + 30, 600)
    col_x = [MARGIN, W / 2 + 20]
    cols = [["start", "talk", "watch"], ["practice", "progress"]]
    d.line([s(MARGIN), s(top - 40), s(W - MARGIN), s(top - 40)], fill=(44, 43, 41), width=s(1))
    for ci, cats in enumerate(cols):
        yy = top
        x = col_x[ci]
        for cat_id in cats:
            name = dict(CATS)[cat_id]
            F["toc_head"].draw(d, s(x), s(yy), name.upper(), FAINT)
            yy += 50
            for e in [e for e in series_list if e["cat"] == cat_id]:
                n = series_list.index(e) + 1
                on = e is ep
                if on:
                    d.rounded_rectangle([s(x - 14), s(yy - 33), s(x + W / 2 - MARGIN - 34), s(yy + 12)],
                                        radius=s(10), fill=HILITE)
                F["toc_num"].draw(d, s(x), s(yy - 2), f"{n:02d}", ACCENT if on else FAINT)
                (F["toc_on"] if on else F["toc"]).draw(d, s(x + 48), s(yy), e["short"], TX if on else DIM)
                yy += 46
            yy += 24
    F["body"].draw(d, s(MARGIN), s(H - 70), "옆으로 넘겨보세요  →", FAINT)
    url = "nawana.app"
    F["url"].draw(d, s(W - MARGIN) - F["url"].width(url), s(H - 70), url, ACCENT)
    return canvas


ZOOM_CROPS = {"transcript": [20, 935, 1186, 1675]}   # the learner's line + its correction card


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("episode", help="episode id (e04) or 'all'")
    ap.add_argument("--lang", default="ko")
    ap.add_argument("--raw", default=None, help="screenshot dir (default: out/<lang>/raw)")
    ap.add_argument("--out", default=None)
    ap.add_argument("--video", action="store_true", help="also write a slideshow MP4")
    ap.add_argument("--theme", choices=list(THEMES), default="dark",
                    help="dark = the feed carousels; light = the website (out/<lang>-light/)")
    a = ap.parse_args()
    apply_theme(a.theme)

    # The series as the board holds it (episodes/series-<lang>.json, exported from the board's db).
    series = json.load(open(os.path.join(HERE, "episodes", f"series-{a.lang}.json"), encoding="utf-8"))
    series.sort(key=lambda e: e.get("order", 0))
    targets = series if a.episode == "all" else [e for e in series if e["id"] == a.episode]
    if not targets:
        raise SystemExit(f"no episode {a.episode}")
    raw = a.raw or os.path.join(HERE, "out", a.lang, "raw")
    F = fonts()
    for ep in targets:
        out = a.out or os.path.join(HERE, "out", a.lang + ("-light" if a.theme == "light" else ""), ep["id"])
        os.makedirs(out, exist_ok=True)
        ep = dict(ep, series=f"나와나 기능 소개 · {ep['short']}")
        slides = [dict(sl) for sl in ep["slides"]]
        for sl in slides:
            if sl.get("kind") == "zoom" and "crop" not in sl:
                sl["crop"] = ZOOM_CROPS.get(sl["shot"], [0, 700, 1206, 1500])
        slides.append({"kind": "outro", "tag": ["유창한 나에게", "언어를 배우세요."],
                       "foot": f"기능 소개 · {ep['short']} 편"})
        total = len(slides) + 1
        paths = []
        imgs = [render_cover_category(next(e for e in series if e["id"] == ep["id"]), series, total, F, False)]
        imgs += [render_slide(sl, ep, i, total, raw, F) for i, sl in enumerate(slides, 2)]
        for i, img in enumerate(imgs, 1):
            img = img.convert("RGB").resize((W, H), Image.LANCZOS)
            p = os.path.join(out, f"{i:02d}.png")
            img.save(p, optimize=True)
            paths.append(p)
        print(ep["id"], len(paths), "slides →", out)

        if a.video:
            # 3.2 s a slide with a short crossfade; 1080×1350 fits a Reels/Threads feed post.
            dur, fade = 3.2, 0.4
            inputs, filt = [], []
            for i, p in enumerate(paths):
                inputs += ["-loop", "1", "-t", str(dur), "-i", p]
            chain, off = "[0:v]", 0.0
            for i in range(1, len(paths)):
                off += dur - fade
                filt.append(f"{chain}[{i}:v]xfade=transition=fade:duration={fade}:offset={off:.2f}[v{i}]")
                chain = f"[v{i}]"
            mp4 = os.path.join(out, f"{ep['id']}-{a.lang}.mp4")
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs,
                            "-filter_complex", ";".join(filt), "-map", chain,
                            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", mp4], check=True)
            print(mp4)


if __name__ == "__main__":
    main()
