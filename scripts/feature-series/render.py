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
    glow = Image.new("RGBA", (ph.width + 2 * pad, ph.height + 2 * pad), ACCENT + (0,))
    glow.putalpha(Image.new("L", glow.size, 0))
    a = Image.new("L", glow.size, 0)
    a.paste(ph.split()[3].point(lambda v: int(v * 0.28)), (pad, pad))
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
            radius=s(44), fill=ACCENT + (70,))
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(s(50))))
        canvas.alpha_composite(card, (s(56), s(ty)))
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

    raise SystemExit(f"unknown slide kind: {kind}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("episode")
    ap.add_argument("--lang", default="ko")
    ap.add_argument("--raw", default=None, help="screenshot dir (default: out/<lang>/raw)")
    ap.add_argument("--out", default=None)
    ap.add_argument("--video", action="store_true", help="also write a slideshow MP4")
    a = ap.parse_args()

    ep_all = json.load(open(os.path.join(HERE, "episodes", a.episode + ".json"), encoding="utf-8"))
    ep = ep_all[a.lang]
    out = a.out or os.path.join(HERE, "out", a.lang, a.episode)
    raw = a.raw or os.path.join(HERE, "out", a.lang, "raw")
    os.makedirs(out, exist_ok=True)
    F = fonts()
    slides = ep["slides"]
    paths = []
    for i, sl in enumerate(slides, 1):
        img = render_slide(sl, ep, i, len(slides), raw, F)
        img = img.convert("RGB").resize((W, H), Image.LANCZOS)
        p = os.path.join(out, f"{i:02d}.png")
        img.save(p, optimize=True)
        paths.append(p)
        print(p)

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
        mp4 = os.path.join(out, f"{a.episode}-{a.lang}.mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs,
                        "-filter_complex", ";".join(filt), "-map", chain,
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", mp4], check=True)
        print(mp4)


if __name__ == "__main__":
    main()
