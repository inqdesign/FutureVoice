# The G design (approved in Korean, 2026-11-14) for every other language.
#   python3 gen_lang.py <lang> [--android] [cap_dir]
# iOS:     raw captures from cap.sh (iPhone 17 Pro Max simulator, 1320 wide) → sets/ios/<lang>/01..10.png
# Android: raw emulator captures → sets/android/<lang>/01..10.png (no island, 1080x1920 Play frame)
# Copy is written per language in COPY below, not translated from the Korean.
import os, sys, shutil, subprocess
from PIL import Image
from copy_lang import COPY, LANGS_ROW, MEET
OUT = os.path.dirname(os.path.abspath(__file__))
SCR = "/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

lang = sys.argv[1]
android = "--android" in sys.argv
ipad = "--ipad" in sys.argv
args = [a for a in sys.argv[2:] if not a.startswith("--")]
CAP = args[0] if args else f"{SCR}/{'ipad' if ipad else 'cap'}/{lang}"
C = COPY[lang]
W, H = (2064, 2752) if ipad else (1320, 2347) if android else (1320, 2868)   # Play refuses taller than 2:1, so Android is 9:16
LIFT = 50 if android else 0           # Android: the headline sits a little higher
STAGE = 0.757                         # Android: everything under the headline, scaled about (660, 640)
FONTS = {"ja": "'Hiragino Sans','Hiragino Kaku Gothic ProN'", "zh-Hans": "'PingFang SC'",
         "zh-CN": "'PingFang SC'", "zh-Hant": "'PingFang TC'", "zh-TW": "'PingFang TC'",
         "ko": "'Apple SD Gothic Neo'"}
HTML_LANG = {"zh-CN": "zh-Hans", "zh-TW": "zh-Hant"}.get(lang, lang)
FONT = f"-apple-system,{FONTS.get(lang, 'system-ui')},'SF Pro Display',sans-serif"


def f(p): return f"file://{p}"


def src(n): return f(f"{CAP}/{n}.png")


def size(n):
    return Image.open(f"{CAP}/{n}.png").size


CSS = f"""*{{margin:0;padding:0;box-sizing:border-box}}html,body{{width:{W}px;height:{H}px;overflow:hidden}}
body{{font-family:{FONT};position:relative;word-break:keep-all;line-break:strict;background:linear-gradient(#F1F1F3,#E4E4E8);color:#111}}
h1{{position:absolute;left:60px;right:60px;text-align:center;font-weight:800;line-height:1.18;letter-spacing:{'-0.043em' if lang=='ko' else '-0.022em'};white-space:nowrap}}
h1 i{{font-style:normal;color:#A3A3A8}}
p{{position:absolute;left:90px;right:90px;text-align:center;font-size:54px;line-height:1.42;font-weight:500;letter-spacing:-0.02em;color:#6E6E73}}
.ph{{position:absolute;background:linear-gradient(120deg,#C9CBD0,#F4F4F6 40%,#B9BBC1);box-shadow:0 0 0 4px #A9ABB1 inset,0 50px 120px rgba(0,0,0,.14)}}
.ph .sc{{width:100%;height:100%;overflow:hidden;background:#fff;position:relative}}
.ph img{{width:100%;display:block}}
.crop{{position:absolute;overflow:hidden}} .crop img{{position:absolute;display:block}}
.card{{position:absolute;border-radius:64px;background:#F2F2F7;box-shadow:0 0 0 18px rgba(255,255,255,.6),0 30px 80px rgba(0,0,0,.08)}}
.face{{border-radius:50%;box-shadow:0 30px 80px rgba(0,0,0,.14)}}
.cut{{position:absolute;overflow:hidden;box-shadow:0 26px 70px rgba(0,0,0,.18)}}
.cut img{{position:absolute;display:block}}
.langrow{{position:absolute;left:0;right:0;top:580px;display:flex;justify-content:center;gap:14px}}
.lc{{padding:14px 26px;border-radius:999px;background:rgba(255,255,255,.7);color:#8E8E93;font-size:38px;font-weight:600;white-space:nowrap}}
.lc.on{{background:#0A5CF5;color:#fff}}
.script{{position:absolute;left:130px;width:1060px;top:640px;height:820px;overflow:hidden;font-family:-apple-system,'SF Pro Display',sans-serif;font-size:70px;line-height:1.5;font-weight:700;letter-spacing:.01em;word-spacing:.08em;color:#111;-webkit-mask-image:linear-gradient(#000 50%,rgba(0,0,0,.25) 85%,transparent 100%)}}
"""
# Headlines never wrap and never overflow: each shrinks until its widest line fits.
FIT = """<script>for(const h of document.querySelectorAll('h1')){let s=parseFloat(getComputedStyle(h).fontSize);
while(h.scrollWidth>h.clientWidth+1&&s>60){s-=2;h.style.fontSize=s+'px'}}
for(const b of document.querySelectorAll('.rc b')){let s=46;while(b.scrollWidth>b.clientWidth+1&&s>28){s-=1;b.style.fontSize=s+'px'}}</script>"""


def phone(img, x, y, w, extra=""):
    iw, ih = size(img)
    p = w * .026
    h = (w - 2 * p) * ih / iw + 2 * p
    r = w * (.15 if not android else .11)
    return (f'<div class="ph" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;padding:{p}px;border-radius:{r}px;{extra}">'
            f'<div class="sc" style="border-radius:{r - p}px"><img src="{src(img)}"></div></div>')


def title(t, top=200, size=140):
    a, b = t
    return f'<h1 style="top:{top - LIFT}px;font-size:{size}px">{a}<br><i>{b}</i></h1>'


def sub(t, top):
    return f'<p style="top:{top - LIFT}px">{t}</p>'


def stage(body):
    if not android:
        return body
    return (f'<div style="position:absolute;left:0;top:0;width:{W}px;height:2868px;'
            f'transform:translateY(-{LIFT}px) scale({STAGE});transform-origin:660px 640px">{body}</div>')


def full(img, t):
    return title(t) + stage(phone(img, 170, 700, 980))


def cut_px(imgpath, x, y, w, h, X, Y, Wd, rad, extra="", sw=None):
    """A pixel region of a screenshot, cut on its own edge."""
    sw = sw or Image.open(imgpath).size[0]
    k = Wd / w
    return (f'<div class="cut" style="left:{X}px;top:{Y}px;width:{Wd}px;height:{h * k}px;border-radius:{rad * k}px;{extra}">'
            f'<img src="{f(imgpath)}" style="width:{sw * k}px;left:{-x * k}px;top:{-y * k}px"></div>')


def card_px(img, box, X, Y, Wd, pad=46):
    x0, y0, x1, y1 = box
    k = (Wd - 2 * pad) / (x1 - x0)
    iw, _ = size(img)
    return (f'<div class="card" style="left:{X}px;top:{Y}px;width:{Wd}px;height:{(y1 - y0) * k + 2 * pad}px">'
            f'<div class="crop" style="left:{pad}px;top:{pad}px;width:{Wd - 2 * pad}px;height:{(y1 - y0) * k}px;border-radius:{30 * k}px">'
            f'<img src="{src(img)}" style="width:{iw * k}px;left:{-x0 * k}px;top:{-y0 * k}px"></div></div>')


def grey_cards(img, x_probe=None, min_h=None):
    """The tutor sheet's grey cards on its white page: [(x0,y0,x1,y1), …] top to bottom."""
    im = Image.open(f"{CAP}/{img}.png").convert("RGB")
    w, h = im.size
    x_probe = x_probe or int(w * .045)
    min_h = min_h or int(w * .09)
    card = lambda p: abs(p[0] - 242) <= 3 and abs(p[1] - 242) <= 3 and abs(p[2] - 247) <= 3
    runs, start = [], None
    for y in range(int(h * .08), h):
        if card(im.getpixel((x_probe, y))):
            start = y if start is None else start
        elif start is not None:
            if y - start >= min_h: runs.append((start, y))
            start = None
    out = []
    for y0, y1 in runs:
        ym = y0 + 12
        x0 = x_probe
        while x0 > 0 and card(im.getpixel((x0 - 1, ym))): x0 -= 1
        x1 = x_probe
        while x1 < w - 1 and card(im.getpixel((x1 + 1, ym))): x1 += 1
        out.append((x0, y0, x1 + 1, y1))
    return out


def face_crop(img):
    """The tutor's face button on the Talk tab (bottom right), as a circle."""
    if android:
        return (889, 1999, 134)         # measured on the Pixel 9 capture (1080x2424)
    iw, ih = size(img)
    s = iw / 402
    return (328 * s, 728 * s, 55 * s)


def render(body, out):
    html = (f'<!doctype html><html lang="{HTML_LANG}"><meta charset="utf-8"><style>{CSS}</style>'
            f'<body>{body}{FIT}</body></html>')
    p = f"{OUT}/_t_{lang}.html"
    open(p, "w").write(html)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={OUT}/prof",
                    "--allow-file-access-from-files", "--force-device-scale-factor=1", f"--window-size={W},{H}",
                    "--virtual-time-budget=2000", f"--screenshot={out}", f"file://{p}"], check=True, capture_output=True)
    os.remove(p)


# ── the ten
def s01():
    if not android and C.get("hand"):
        return None
    row = "".join(f'<span class="lc{" on" if on else ""}">{t}</span>' for t, on in LANGS_ROW)
    return title(C["s01"], size=124) + f'<div class="langrow" style="top:{580 - LIFT}px">{row}</div>' + stage(phone("tabs", 170, 760, 980))


ILL = OUT + "/ill"
MEET_CSS = """<style>
.rc{position:absolute;width:560px;height:250px;border-radius:48px;background:#fff;box-shadow:0 24px 70px rgba(0,0,0,.13)}
.rc img{position:absolute;bottom:22px}
.rc .tx{position:absolute;top:44px;right:30px;width:310px}
.rc small{display:block;font-size:32px;font-weight:700;color:#8E8E93;margin-bottom:8px;white-space:nowrap}
.rc b{display:block;font-size:46px;font-weight:800;line-height:1.22;color:#111;letter-spacing:-0.02em;white-space:nowrap}
</style>"""


def meet_card(i, x, y, scale=1.0):
    """One of the four reasons, with its drawing (gpt-image-2, the speech challenge pictures' style)."""
    pic = ["shadow", "fix", "calm", "goal"][i]
    tag, text = MEET[lang][1][i]
    w, hh = Image.open(f"{ILL}/{pic}_a.png").size
    k = min((300 if pic == "calm" else 330) / hh, 180 / w)
    iw, ih = w * k, hh * k
    return (f'<div class="rc" style="left:{x}px;top:{y}px;transform:scale({scale});transform-origin:0 0">'
            f'<img src="file://{ILL}/{pic}_a.png" style="left:{24 + (180 - iw) / 2}px;height:{ih}px">'
            f'<div class="tx"><small>{tag}</small><b>{text}</b></div></div>')


def s02():
    """Meet the fluent you (founder, 11-15): the real meet screen and four reasons around it."""
    return (title(MEET[lang][0]) + MEET_CSS
            + stage(phone("voice-meet", 170, 700, 980)
                    + meet_card(0, 30, 1180) + meet_card(1, 730, 1560)
                    + meet_card(2, 30, 1990) + meet_card(3, 730, 2380)))


def s03():
    cards = grey_cards("tutor")
    goals, today = cards[0], cards[1]
    fx, fy, fw = face_crop("tabs")
    iw, _ = size("tabs")
    k = 200 / fw
    face = (f'<div class="crop face" style="left:560px;top:820px;width:200px;height:200px">'
            f'<img src="{src("tabs")}" style="width:{iw * k}px;left:{-fx * k}px;top:{-fy * k}px"></div>')
    g = card_px("tutor", goals, 90, 1100, 1140)
    gh = (goals[3] - goals[1]) * (1140 - 92) / (goals[2] - goals[0]) + 92
    t = card_px("tutor", today, 90, 1100 + gh + 60, 1140)
    return title(C["s03"]) + sub(C["s03sub"], 580) + stage(face + g + t)


SCRIPT = ("<div class='script'>Have you ever had the perfect sentence in your head, only to watch it fall apart "
          "the moment you said it? Speaking is a skill, not just knowledge. You can know the words and the grammar, "
          "but if your mouth has never actually built the sentence, it tends to fall apart.</div>")


def s04():
    live = f"{SCR}/live/ko_07.png"          # the camera card: no words on it, the same in every language
    cam_w = 1060
    cam_h = cam_w * 890 / 863
    cam_y = 2760 - cam_h
    sp = f"{CAP}/speech.png"
    sw, _ = Image.open(sp).size
    k = sw / 1320                          # card rects measured on a 1320-wide capture
    c1 = [v * k for v in (48, 610, 594, 900)]
    c2 = [v * k for v in (678, 1546, 594, 900)]
    if android:                         # Pixel 9: the movie-scene card and the podcast card
        c1, c2 = (53, 568, 471, 722), (556, 1314, 471, 716)
        k = 0.82
    return (title(C["s04"]) + stage(SCRIPT
            + cut_px(live, 190, 1652, 863, 890, 130, cam_y, cam_w, 62, "box-shadow:0 40px 100px rgba(0,0,0,.20)", sw=1242)
            + cut_px(sp, *c1, 40, cam_y - 150, 290, 86 * k, "transform:rotate(-5deg)", sw=sw)
            + cut_px(sp, *c2, 990, cam_y - 150, 290, 86 * k, "transform:rotate(5deg)", sw=sw)))


def s08():
    iw, _ = size("composer-box")
    k = iw / 402                       # the box, in points on a 402-pt screen
    box = (32, 1982, 1048, 2318) if android else (8 * k, 655 * k, 396 * k, 815 * k)
    return (title(C["s08"], size=130) + stage(phone("watchtab-sky", 170, 700, 980)
            + card_px("composer-box", box, 50, 2240, 1220, pad=10)))


def tablet(img, t, subline=None):
    iw, ih = size(img)
    y = 800 if subline else 700
    p = 26
    w = int((H - 70 - y) * iw / ih)          # the whole iPad fits, bottom bar included
    x = (W - w) // 2
    h = (w - 2 * p) * ih / iw + 2 * p
    head = (f'<h1 style="top:170px;font-size:190px">{t[0]}<br><i>{t[1]}</i></h1>'
            + (f'<p style="top:640px;font-size:72px">{subline}</p>' if subline else ''))
    return (head + f'<div class="ph" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;padding:{p}px;border-radius:90px">'
            f'<div class="sc" style="border-radius:{90 - p}px"><img src="{src(img)}"></div></div>')


IPAD_SHOTS = [("01", lambda: tablet("tabs", C["s01"])), ("02", lambda: tablet("voice-meet", MEET[lang][0]) + MEET_CSS
                     + meet_card(0, 40, 1150, 1.25) + meet_card(1, 1320, 1550, 1.25)
                     + meet_card(2, 40, 1950, 1.25) + meet_card(3, 1320, 2350, 1.25)),
              ("03", lambda: tablet("tutor", C["s03"], C["s03sub"])), ("04", lambda: tablet("speech", C["s04"])),
              ("05", lambda: tablet("fix", C["s05"])), ("06", lambda: tablet("coach", C["s06"])),
              ("07", lambda: tablet("shadow", C["s07"])), ("08", lambda: tablet("watchtab-sky", C["s08"])),
              ("09", lambda: tablet("talkdetail", C["s09"])), ("10", lambda: tablet("activity-week", C["s10"]))]

SHOTS = [("01", s01), ("02", s02), ("03", s03), ("04", s04),
         ("05", lambda: full("fix", C["s05"])), ("06", lambda: full("coach", C["s06"])),
         ("07", lambda: full("shadow", C["s07"])), ("08", s08),
         ("09", lambda: full("talkdetail", C["s09"])), ("10", lambda: full("activity-week", C["s10"]))]

if __name__ == "__main__":
    kind = "ipad" if ipad else "android" if android else "ios"
    if ipad: SHOTS = IPAD_SHOTS
    dest = f"{OUT}/sets/{kind}/{lang}"
    os.makedirs(dest, exist_ok=True)
    only = os.environ.get("ONLY", "").split(",") if os.environ.get("ONLY") else None
    for n, fn in SHOTS:
        if only and n not in only: continue
        body = fn()
        out = f"{dest}/{n}.png"
        if body is None and not ipad:
            Image.open(C["hand"]).convert("RGB").save(out)
        else:
            render(body, out)
        if android:   # Play's phone size: 1080x1920
            Image.open(out).convert("RGB").resize((1080, 1920), Image.LANCZOS).save(out)
    ims = [Image.open(f"{dest}/{n}.png").convert("RGB").resize((330, 717 if not android else 587) if not ipad else (330, 440)) for n, _ in SHOTS if os.path.exists(f"{dest}/{n}.png")]
    rh = ims[0].height + 10
    sheet = Image.new("RGB", (5 * 340 + 10, 2 * rh + 10), "#fff")
    for i, im in enumerate(ims): sheet.paste(im, (10 + (i % 5) * 340, 10 + (i // 5) * rh))
    sheet.save(f"{OUT}/sets/{kind}_{lang}_sheet.jpg", quality=85)
    print(dest)
