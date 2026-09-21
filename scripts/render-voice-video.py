#!/usr/bin/env python3
"""Render the nawana.app voice note as a 9:16 social video (Threads / Reels).

What it draws, top to bottom on a 1080×1920 ink ground: the app mark, the
Futureself orb driven by the voice, the synced caption, and the brand block
(eyebrow · wordmark · tagline · URL). The orb is a faithful port of the page's
WebGL `mountFutureself` (itself a port of Shaders/Futureself.metal): 5-row
quantized mosaic, blue theme on the dark palette, mode 3 (speaking, centre-out),
level = RMS of the last 256 samples × 3.4 through the same fast-attack /
slow-release smoother the page runs at 60 Hz. Captions come from the VTT the
page uses, so what the video says is what the site says.

Audio is muxed from the mp3 itself — never re-recorded — with a short idle
lead-in and tail so the first caption doesn't pop on frame one.

    python3 scripts/render-voice-video.py --lang ko --out out.mp4
    python3 scripts/render-voice-video.py --lang ko --from 0 --to 250.6 --label "1 / 2" --out part1.mp4
    python3 scripts/render-voice-video.py --lang en --frames 5,40,120 --out frames/   # PNG stills, no video

Requires ffmpeg, numpy, Pillow, fontTools(+brotli). Runs in ~1× realtime.
"""
import argparse, io, math, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, "web")

W, H, FPS = 1080, 1920, 30
LEAD, TAIL = 0.8, 1.2                     # seconds of idle orb before / after the voice
BG = (18, 17, 16)                         # page --bg #121110
TX, DIM, FAINT = (237, 236, 232), (156, 154, 148), (110, 108, 102)
DOT = (64, 100, 245)                      # eyebrow pulse dot
ORB_D, ORB_CX, ORB_CY = 520, 540, 760
CAP_TOP, CAP_W, CAP_SIZE, CAP_LH = 1090, 900, 44, 1.45

AUDIO = {"ko": ("beta.mp3", "beta-ko.vtt"), "en": ("beta-en.mp3", "beta-en.vtt")}
COPY = {
    "en": dict(eyebrow="NOW ON THE APP STORE", tag=["Learn a language from", "your fluent self."]),
    "ko": dict(eyebrow="APP STORE 출시",        tag=["유창한 나에게", "언어를 배우세요."]),
}

# ── fonts: a browser-style cascade — first face whose cmap has the glyph wins ──
class Face:
    def __init__(self, path, size, index=0):
        self.font = ImageFont.truetype(path, size, index=index)
        tt = TTFont(path, fontNumber=index if path.endswith(".ttc") else -1, lazy=True)
        self.cmap = set(tt.getBestCmap().keys())
        self.ascent, self.descent = self.font.getmetrics()

class Cascade:
    def __init__(self, faces, tracking=0.0):
        self.faces, self.tracking = faces, tracking   # tracking: extra advance per char, px
    def _runs(self, text):
        runs, cur, curf = [], "", None
        for ch in text:
            f = next((f for f in self.faces if ord(ch) in f.cmap), self.faces[-1])
            if ch == " ": f = curf or f                # spaces stay in the run they follow
            if f is not curf and cur:
                runs.append((curf, cur)); cur = ""
            cur += ch; curf = f
        if cur: runs.append((curf, cur))
        return runs
    def width(self, text):
        if self.tracking:
            return sum(f.font.getlength(ch) + self.tracking for f, run in self._runs(text) for ch in run)
        return sum(f.font.getlength(run) for f, run in self._runs(text))
    def draw(self, d, x, y, text, fill):                # (x, y) = left, BASELINE
        for f, run in self._runs(text):
            if self.tracking:
                for ch in run:
                    d.text((x, y), ch, font=f.font, fill=fill, anchor="ls")
                    x += f.font.getlength(ch) + self.tracking
            else:
                d.text((x, y), run, font=f.font, fill=fill, anchor="ls")
                x += f.font.getlength(run)
    def draw_centered(self, d, cx, y, text, fill):
        self.draw(d, cx - self.width(text) / 2, y, text, fill)
    @property
    def line_h(self):
        return max(f.ascent + f.descent for f in self.faces)

def load_fonts():
    geist = os.path.join(WEB, "GeistPixel.ttf")
    sdg = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
    # Pixelify Sans is the page's wordmark face; it ships as woff2, which Pillow can't open.
    pix_ttf = os.path.join(tempfile.gettempdir(), "PixelifySans.render.ttf")
    if not os.path.exists(pix_ttf):
        f = TTFont(os.path.join(WEB, "PixelifySans.woff2")); f.flavor = None; f.save(pix_ttf)
    return dict(
        caption=Cascade([Face(geist, CAP_SIZE), Face(sdg, CAP_SIZE, 0)]),           # .caption: Geist Pixel → system Hangul
        eyebrow=Cascade([Face("/System/Library/Fonts/Menlo.ttc", 24, 0), Face(sdg, 24, 2)], tracking=24 * 0.18),
        wordmark=Cascade([Face(pix_ttf, 100)]),
        tag=Cascade([Face("/System/Library/Fonts/HelveticaNeue.ttc", 38, 0), Face(sdg, 38, 0)]),
        url=Cascade([Face("/System/Library/Fonts/Menlo.ttc", 26, 0)], tracking=26 * 0.05),
    )

# ── captions (WebVTT) — same pick rule as the page: first cue with s <= t < e ──
def parse_vtt(path):
    txt = open(path, encoding="utf-8").read().replace("\r", "")
    cues = []
    for blk in txt.split("\n\n"):
        if "-->" not in blk: continue
        ls = blk.strip().split("\n")
        i = next(j for j, l in enumerate(ls) if "-->" in l)
        def tc(x):
            q = x.strip().split(" ")[0].split(":")
            return float(q[0]) * 60 + float(q[1]) if len(q) == 2 else float(q[0]) * 3600 + float(q[1]) * 60 + float(q[2])
        a, b = ls[i].split("-->")
        body = "\n".join(ls[i + 1:]).strip()
        if body: cues.append((tc(a), tc(b), body))
    return cues

def cue_at(cues, t):
    for s, e, body in cues:
        if s <= t < e: return body
    return ""

def wrap(cascade, text, max_w):
    lines = []
    for para in text.split("\n"):
        words, cur = para.split(" "), ""
        for w in words:
            cand = (cur + " " + w).strip()
            if cascade.width(cand) <= max_w or not cur:
                if cascade.width(cand) > max_w and not cur:      # one over-long word: break by char
                    piece = ""
                    for ch in w:
                        if cascade.width(piece + ch) > max_w and piece:
                            lines.append(piece); piece = ""
                        piece += ch
                    cur = piece
                else:
                    cur = cand
            else:
                lines.append(cur); cur = w
        if cur: lines.append(cur)
    return lines

def render_caption(fonts, text):
    """RGBA layer of the caption, or None. Cached per cue by the caller."""
    if not text: return None
    cas = fonts["caption"]
    lines = wrap(cas, text, CAP_W)
    lh = int(CAP_SIZE * CAP_LH)
    img = Image.new("RGBA", (W, lh * len(lines) + 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = cas.faces[0].ascent
    for i, line in enumerate(lines):
        cas.draw_centered(d, W / 2, base + i * lh, line, TX + (255,))
    return np.asarray(img)

# ── the Futureself orb: numpy port of the page's fragment shader (theme 0 blue, dark) ──
PAL = np.array([[.020, .028, .060], [.080, .095, .130], [.020, .130, .400],
                [.040, .360, .960], [.480, .720, 1.000]], np.float32)
BASE = PAL[0]

def frac(x): return x - np.floor(x)
def hash21(p):
    p = frac(p * np.array([123.34, 456.21], np.float32))
    p = p + np.sum(p * (p + 45.32), axis=-1, keepdims=True)
    return frac(p[..., 0] * p[..., 1])
def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

class Orb:
    def __init__(self, size):
        self.size = size
        s = np.float32(size)
        ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
        pos = np.stack([xs + 0.5, ys + 0.5], -1)               # position (y already top-down)
        cell_pt = s / 5.0
        cell = np.floor(pos / cell_pt)
        self.ci = cell[..., 1].astype(np.int64); self.cj = cell[..., 0].astype(np.int64)
        # per-cell constants (5×5)
        cy, cx = np.mgrid[0:5, 0:5].astype(np.float32)
        c = np.stack([cx, cy], -1)
        self.r1, self.r2, self.r3 = hash21(c + 0.13), hash21(c + 7.77), hash21(c + 23.19)
        cuv = (c + 0.5) * cell_pt / s
        bias = np.abs(cuv[..., 0] - 0.5) * 2.0                 # mode 3: speaking, centre-out
        self.order = np.clip(self.r1 * 0.55 + bias * 0.45, 0, 1)
        # per-pixel statics: hairline gap, rim shading, circle clip
        f = pos - cell * cell_pt
        gap = np.minimum(np.minimum(f[..., 0], f[..., 1]), np.minimum(cell_pt - f[..., 0], cell_pt - f[..., 1]))
        self.w = smoothstep(0.35, 1.1, gap)[..., None]
        rad = s * 0.5
        pc = pos - s * 0.5
        inset = rad - np.sqrt(np.sum(pc * pc, -1))
        rim = np.exp(-np.maximum(inset, 0) / 7.0)
        topw = np.clip(0.5 - pc[..., 1] / s, 0, 1)
        shade = rim * (0.14 + 0.34 * topw)
        self.mul = (1.0 - shade * 0.85)[..., None]
        self.add = (rim * (1.0 - topw) * 0.06)[..., None]
        self.alpha = np.clip(inset + 0.5, 0, 1)[..., None]      # 1 px anti-aliased circle
        self.pos17 = pos * 1.7
        self.grain = {}

    def frame(self, t, level):
        r1, r2, r3 = self.r1, self.r2, self.r3
        v = 0.16 + 0.14 * np.sin(t * (0.35 + 0.55 * r2) + r3 * 6.2831)
        drive = min(max(level, 0.0), 1.0) * 1.15
        ignite = smoothstep(self.order, self.order + 0.22, drive)
        v += ignite * (0.55 + 0.30 * r2)
        v += ignite * 0.08 * np.sin(t * (2.0 + 3.0 * r1) + r2 * 6.2831)
        step5 = np.clip(np.floor(v * 4.0 + (r3 - 0.5) * 0.9 + 0.5), 0, 4).astype(np.int64)
        cc = PAL[step5]                                         # (5,5,3)
        col = BASE * (1 - self.w) + cc[self.ci, self.cj] * self.w
        col = col * self.mul + self.add
        tq = int(math.floor(t * 18.0)) % 64
        g = self.grain.get(tq)
        if g is None:
            g = self.grain[tq] = ((hash21(self.pos17 + tq * np.array([13.7, 91.3], np.float32)) - 0.5) * 0.06)[..., None]
        return np.clip(col + g, 0, 1)


# ── the letter-pattern flower: numpy port of the page's halftone-flower shader ──
# ASCII/jamo glyph atlas (light→heavy by ink coverage), one 8-petal polar flower
# with a top-right sun, a stem, grain — on the dark palette, then the page's veil
# (a radial darkening at the centre so the foreground reads).
FLOWER_CH = ' .......ㄱㅏrㄴcㅗtㅓoㄷaㄹeㅋxㅂsㅍwㅁmㅇㅎ'
PAPER, INK, GRAIN = np.array([.071, .067, .063], np.float32), np.array([.58, .55, .5], np.float32), 0.022

def hsh(p):                                     # h(): fract(sin(dot(p,(127.1,311.7)))*43758.5453)
    return frac(np.sin(p[..., 0] * 127.1 + p[..., 1] * 311.7) * 43758.5453)
def vnoise(p):
    i, f = np.floor(p), frac(p); f = f * f * (3 - 2 * f)
    a = hsh(i); b = hsh(i + [1, 0]); c = hsh(i + [0, 1]); d = hsh(i + [1, 1])
    return (a + (b - a) * f[..., 0]) * (1 - f[..., 1]) + (c + (d - c) * f[..., 0]) * f[..., 1]
def fbm(p):
    v, a = 0.0, 0.5
    for _ in range(3):
        v = v + a * vnoise(p); p = p * 2.1; a *= 0.5
    return v

class Flower:
    def __init__(self, w, h):
        self.w, self.h = w, h
        cell = max(10.0, h / 85.0)
        self.cols, self.rows = int(math.ceil(w / cell)), int(math.ceil(h / cell))
        # cell centres in the shader's space: y UP, x scaled by aspect
        ys, xs = np.mgrid[0:self.rows, 0:self.cols].astype(np.float32)
        cc = np.stack([(xs + 0.5) * cell, (ys + 0.5) * cell], -1)         # y up → row 0 is the BOTTOM
        cuv = cc / np.array([w, h], np.float32)
        self.asp = w / h
        self.p = np.stack([cuv[..., 0] * self.asp, cuv[..., 1]], -1)
        # glyph atlas at 64 px, then resampled to the cell (GL LINEAR ≈ bilinear)
        G, S = 64, int(math.ceil(cell))
        self.S = S
        font = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", int(G * .74), index=6)   # Bold
        atlas = np.zeros((len(FLOWER_CH), S, S), np.float32)
        for i, ch in enumerate(FLOWER_CH):
            im = Image.new("L", (G, G), 0); ImageDraw.Draw(im).text((G / 2, G / 2 + 2), ch, font=font, fill=255, anchor="mm")
            atlas[i] = np.asarray(im.resize((S, S), Image.BILINEAR), np.float32) / 255.0
        self.atlas_flat = atlas.reshape(-1)
        # per-pixel gather tables: which cell, which atlas texel (rows here are TOP-down image rows)
        py, px = np.mgrid[0:h, 0:w].astype(np.float32)
        gy = (h - py - 0.5) / cell; gx = (px + 0.5) / cell                 # gl_FragCoord (y up)
        cr, ccol = np.minimum(np.floor(gy), self.rows - 1).astype(np.int64), np.minimum(np.floor(gx), self.cols - 1).astype(np.int64)
        iu, iv = frac(gx), frac(gy)
        ai = np.minimum((iu * S).astype(np.int64), S - 1); aj = np.minimum(((1 - iv) * S).astype(np.int64), S - 1)
        self.pix_cell = (cr * self.cols + ccol).reshape(-1)
        self.pix_sub = (aj * S + ai).reshape(-1)
        self.grain = ((hsh(np.stack([px + 0.5, h - py - 0.5], -1)) - 0.5) * GRAIN)[..., None]
        # the page's .veil: radial-gradient(72% 56% at 50% 50%, bg .74, bg .22 64%, bg 0 100%)
        d = np.sqrt(((px + 0.5 - w / 2) / (0.72 * w)) ** 2 + ((py + 0.5 - h / 2) / (0.56 * h)) ** 2)
        a = np.where(d < 0.64, 0.74 + (0.22 - 0.74) * (d / 0.64), np.clip(0.22 * (1 - (d - 0.64) / 0.36), 0, 1))
        self.veil = a.astype(np.float32)[..., None]
        self.bg = np.array(BG, np.float32) / 255.0

    def frame(self, t, center=(0.70, 0.55), R=0.32, N=8.0, q=0.0):
        p = self.p
        c = np.array([self.asp * center[0] + 0.02 * math.sin(t * 0.5 + q), center[1]], np.float32)
        d = p - c
        rad = np.sqrt(np.sum(d * d, -1))
        ang = np.arctan2(d[..., 1], d[..., 0]) + 0.07 * math.sin(t * 0.55 + q)
        w = fbm(np.stack([ang * 2.3 + q * 3.0, rad * 5.0], -1) + q)
        lobe = np.abs(np.cos(N * 0.5 * ang + q)) ** 0.40
        pet = R * (0.55 + 0.45 * lobe) * (0.55 + 0.9 * w)
        g = smoothstep(pet, pet * 0.20, rad)
        ridge = np.abs(np.cos(N * 0.5 * ang + q))
        rr = np.clip(rad / np.maximum(pet, 1e-4), 0, 1)
        form = 0.40 + 0.60 * ridge * (1.0 + (0.55 - 1.0) * rr)
        u = d / np.maximum(rad, 1e-4)[..., None]
        sun = 0.55 + 0.55 * (u[..., 0] * 0.55 + u[..., 1] * 0.83)
        g = g * np.clip(form * sun, 0, 1)
        g = np.maximum(g, 0.14 * smoothstep(pet * 1.6, pet * 0.9, rad))
        # stem, below the flower centre only
        dy = c[1] - p[..., 1]
        sx = c[0] + 0.05 * np.sin(dy * 4.0 + q) + dy * dy * 0.14 * math.sin(t * 0.5 + q)
        stem = np.where(p[..., 1] > c[1], 0.0, 0.30 * smoothstep(0.006, 0.002, np.abs(p[..., 0] - sx)))
        L = np.maximum(np.maximum(0.05, g), stem)
        lvl = np.sqrt(np.clip(L, 0, 1))
        gi = np.floor(lvl * (len(FLOWER_CH) - 1) + 0.5).astype(np.int64)
        strength = 0.20 + 0.80 * smoothstep(0.05, 0.32, L)
        k = self.atlas_flat[gi.reshape(-1)[self.pix_cell] * (self.S * self.S) + self.pix_sub].reshape(self.h, self.w)
        ks = (k * strength.reshape(-1)[self.pix_cell].reshape(self.h, self.w))[..., None]
        col = PAPER + (INK - PAPER) * ks + self.grain
        return col * (1 - self.veil) + self.bg * self.veil

# ── level from the audio, exactly as the page's pump() + smoother ──
def levels(samples, sr, n_frames, fps=FPS):
    """Smoothed drive per video frame, simulating the page's 60 Hz rAF loop."""
    sim_hz = 60
    n_ticks = int(math.ceil(n_frames / fps * sim_hz)) + 2
    out = np.zeros(n_ticks, np.float32)
    v = 0.0
    for k in range(n_ticks):
        t = k / sim_hz
        idx = int(t * sr)
        win = samples[max(0, idx - 256):idx]
        target = 0.0 if len(win) == 0 else min(1.0, float(np.sqrt(np.mean(win * win))) * 3.4)
        tau = 0.06 if target > v else 0.35
        v += (target - v) * (1 - math.exp(-(1 / sim_hz) / tau))
        out[k] = v
    # sample the 60 Hz state at each 30 fps frame time
    return np.array([out[min(n_ticks - 1, int(round(i / fps * sim_hz)))] for i in range(n_frames)], np.float32)

# ── static layer: mark, eyebrow, wordmark, tagline, URL ──
def static_layer(fonts, lang, label):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # the app mark (pixel O-ring + detached cell), geometry from the page's <svg viewBox="0 0 1024 1024">
    rects = [(291, 238, 410, 100), (701, 338, 104, 347), (187, 338, 104, 347), (291, 685, 410, 100), (805, 685, 98, 100)]
    gw = 903 - 187; scale = 64 / gw; ox = W / 2 - (187 + gw / 2) * scale; oy = 150 - 238 * scale
    for x, y, w, h in rects:
        d.rectangle([ox + x * scale, oy + y * scale, ox + (x + w) * scale, oy + (y + h) * scale], fill=TX + (255,))
    c = COPY[lang]
    eyebrow = (label + "  ·  " if label else "") + c["eyebrow"]
    ey = 1478
    ew = fonts["eyebrow"].width(eyebrow) + 22
    ex = W / 2 - ew / 2
    d.ellipse([ex, ey - 12, ex + 12, ey], fill=DOT + (255,))
    fonts["eyebrow"].draw(d, ex + 22, ey, eyebrow, DIM + (255,))
    fonts["wordmark"].draw_centered(d, W / 2, 1610, "nawana", TX + (255,))
    fonts["tag"].draw_centered(d, W / 2, 1680, c["tag"][0], DIM + (255,))
    fonts["tag"].draw_centered(d, W / 2, 1730, c["tag"][1], DIM + (255,))
    fonts["url"].draw_centered(d, W / 2, 1800, "nawana.app", FAINT + (255,))
    return np.asarray(img).copy()

def alpha_over(dst, layer, y0):
    h = layer.shape[0]
    a = layer[..., 3:4].astype(np.float32) / 255.0
    region = dst[y0:y0 + h]
    region[:] = (layer[..., :3] * a + region * (1 - a)).astype(np.uint8)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", choices=["ko", "en"], required=True)
    ap.add_argument("--from", dest="t_from", type=float, default=0.0)
    ap.add_argument("--to", dest="t_to", type=float, default=None)
    ap.add_argument("--label", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-flower", action="store_true", help="flat ink ground instead of the letter-pattern flower")
    ap.add_argument("--frames", default=None, help="comma-separated audio times → PNG stills into --out dir")
    args = ap.parse_args()

    mp3, vtt = (os.path.join(WEB, p) for p in AUDIO[args.lang])
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", mp3, "-f", "f32le", "-ac", "1", "-ar", "44100", "-"],
                         capture_output=True, check=True).stdout
    samples = np.frombuffer(raw, np.float32); sr = 44100
    t_to = args.t_to if args.t_to is not None else len(samples) / sr
    seg = samples[int(args.t_from * sr):int(t_to * sr)]
    dur = len(seg) / sr
    total = LEAD + dur + TAIL
    n_frames = int(round(total * FPS))
    cues = [(s - args.t_from, e - args.t_from, b) for s, e, b in parse_vtt(vtt)]

    fonts = load_fonts()
    overlay = static_layer(fonts, args.lang, args.label)
    ov_a = overlay[..., 3:4].astype(np.float32) / 255.0
    ov_rgb = overlay[..., :3].astype(np.float32)
    flower = None if args.no_flower else Flower(W, H)
    flat_bg = np.full((H, W, 3), BG, np.uint8)
    orb = Orb(ORB_D)
    lv = levels(seg, sr, n_frames)
    lead_frames = int(round(LEAD * FPS))
    cap_cache = {}
    x0, y0 = ORB_CX - ORB_D // 2, ORB_CY - ORB_D // 2

    def compose(i):
        t = i / FPS                       # video time
        ta = t - LEAD                     # audio time
        level = lv[max(0, i - lead_frames)] if ta >= 0 else 0.0
        if flower is not None:
            bgf = flower.frame(t) * 255.0
            frame = (bgf * (1 - ov_a) + ov_rgb * ov_a + 0.5).astype(np.uint8)
        else:
            frame = flat_bg.copy(); alpha_over(frame, overlay, 0)
        o = orb.frame(t, level)
        region = frame[y0:y0 + ORB_D, x0:x0 + ORB_D].astype(np.float32) / 255.0
        frame[y0:y0 + ORB_D, x0:x0 + ORB_D] = ((o * orb.alpha + region * (1 - orb.alpha)) * 255 + 0.5).astype(np.uint8)
        text = cue_at(cues, ta) if 0 <= ta < dur else ""
        if text:
            layer = cap_cache.get(text)
            if layer is None: layer = cap_cache[text] = render_caption(fonts, text)
            alpha_over(frame, layer, CAP_TOP)
        return frame

    if args.frames:
        os.makedirs(args.out, exist_ok=True)
        for ta in (float(x) for x in args.frames.split(",")):
            i = int(round((ta + LEAD) * FPS))
            Image.fromarray(compose(i)).save(os.path.join(args.out, f"{args.lang}-{ta:07.2f}.png"))
        print("stills →", args.out); return

    fade_out = max(0.0, total - 0.6)
    cmd = ["ffmpeg", "-v", "error", "-y",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-i", mp3,
           "-filter_complex",
           f"[0:v]fade=t=in:st=0:d=0.4,fade=t=out:st={fade_out:.3f}:d=0.6,format=yuv420p[v];"
           f"[1:a]atrim=start={args.t_from}:end={t_to},asetpts=N/SR/TB,adelay={int(LEAD*1000)},apad=pad_dur={TAIL}[a]",
           "-map", "[v]", "-map", "[a]", "-t", f"{total:.3f}",
           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-profile:v", "high", "-level", "4.1",
           "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", args.out]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(n_frames):
        p.stdin.write(compose(i).tobytes())
        if i % 300 == 0: print(f"\r  {i}/{n_frames} frames", end="", file=sys.stderr, flush=True)
    p.stdin.close(); p.wait()
    print(f"\r  {n_frames}/{n_frames} frames → {args.out} ({total:.1f}s)", file=sys.stderr)
    if p.returncode: sys.exit(p.returncode)

if __name__ == "__main__":
    main()
