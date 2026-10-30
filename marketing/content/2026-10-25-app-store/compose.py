#!/usr/bin/env python3
"""Compose App Store screenshots: real simulator capture inside a phone, headline on top.

compose.py <copy.json> <rawdir-root> <outdir>
copy.json: {"<locale>": {"raw": "<rawdir name>", "font": "pixel|sans-tc|sans-sc",
            "shots": [{"id","capture","title","sub", "accent": "<substring of title>",
                       "focus": 0.0-1.0 (vertical crop anchor, optional), "zoom": 1.0}]}}
"""
import json, os, subprocess, sys, html, tempfile
from fontTools.ttLib import TTFont

ROOT = "/Users/eunggyuelee/FutureVoice"
GEIST = TTFont(f"{ROOT}/web/GeistPixel.ttf").getBestCmap()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1320, 2868

CSS = """
@font-face{font-family:GP;src:url(file://%(root)s/web/GeistPixel.ttf)}
@font-face{font-family:GM;src:url(file://%(root)s/web/Galmuri14.woff2)}
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:%(w)dpx;height:%(h)dpx;overflow:hidden}
html{background:#F7F8FA;
 background-image:linear-gradient(rgba(13,17,23,.045) 2px,transparent 2px),
 linear-gradient(90deg,rgba(13,17,23,.045) 2px,transparent 2px);
 background-size:66px 66px;background-position:-2px -2px}
body{font-family:-apple-system,'SF Pro Display','Helvetica Neue',sans-serif;color:#0D1117;position:relative}
.top{padding:190px 96px 0;text-align:center}
h1{font-weight:400;font-size:%(fs)dpx;line-height:1.22;letter-spacing:-1px;word-break:keep-all}
h1.sans{font-weight:700;letter-spacing:-2px;line-height:1.18}
h1 em{font-style:normal;color:#0A5CF5}
p{margin-top:40px;font-size:50px;line-height:1.36;color:#59606D;font-weight:500;word-break:keep-all}
.phone{margin:100px auto 0;width:1000px;height:2172px;
 border-radius:150px;background:#0D1117;padding:24px;box-shadow:0 50px 120px rgba(13,17,23,.18),0 0 0 3px #2a2f38 inset}
.screen{width:952px;height:2124px;border-radius:128px;overflow:hidden;background:#fff;position:relative}
.screen img{width:952px;display:block}
.call{position:absolute;left:50%%;transform:translateX(-50%%);overflow:hidden;border-radius:48px;background:#fff;
 box-shadow:0 40px 90px rgba(13,17,23,.22),0 0 0 2px rgba(13,17,23,.06)}
.call img{display:block}
"""


def font_for(title: str, mode: str) -> tuple[str, str]:
    if mode.startswith("sans"):
        fam = "'PingFang TC','Heiti TC'" if mode == "sans-tc" else "'PingFang SC','Heiti SC'"
        return f"font-family:{fam},sans-serif", "sans"
    latin_only = all(ord(c) in GEIST or c in " \n" for c in title)
    return ("font-family:GP" if latin_only else "font-family:GM,GP"), ""


def page(shot: dict, raw: str, mode: str) -> str:
    title = html.escape(shot["title"]).replace("\n", "<br>")
    if shot.get("accent"):
        a = html.escape(shot["accent"])
        title = title.replace(a, f"<em>{a}</em>", 1)
    style, cls = font_for(shot["title"], mode)
    lines = shot["title"].count("\n") + 1
    def em(line):
        tot = 0
        for c in line:
            if ord(c) > 0x2E80: tot += 1.0
            elif cls == "sans": tot += 0.6
            else: tot += 0.56 if style.endswith("GP") else 0.64
        return tot
    widest = max(em(l) for l in shot["title"].split("\n"))
    fs = shot.get("fs", int(min(116 if lines <= 2 else 100, 1110 / max(widest, 1))))
    sub_lines = shot.get("sub", "").count("\n") + 1 if shot.get("sub") else 0
    ptop = 190 + lines * int(fs * 1.22) + (44 + sub_lines * 71 if sub_lines else 0) + 110
    sub = f"<p>{html.escape(shot['sub']).replace(chr(10), '<br>')}</p>" if shot.get("sub") else ""
    css = CSS % {"root": ROOT, "w": W, "h": H, "fs": fs, "ptop": ptop}
    img = os.path.abspath(raw)
    shift = shot.get("shift", 0)  # px of the scaled screenshot to scroll up inside the screen
    co = ""
    if shot.get("callout"):
        x, y, w, h = shot["callout"]["crop"]
        cw = shot["callout"].get("width", 1180)
        k = cw / w
        co = (f'<div class="call" style="top:{shot["callout"]["top"]}px;width:{cw}px;height:{int(h*k)}px">'
              f'<img src="file://{img}" style="width:{int(1320*k)}px;margin:-{int(y*k)}px 0 0 -{int(x*k)}px"></div>')
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head><body>
<div class="top"><h1 class="{cls}" style="{style}">{title}</h1>{sub}</div>
<div class="phone"><div class="screen"><img src="file://{img}" style="margin-top:-{shift}px"></div></div>
{co}</body></html>"""


def render(html_text: str, out: str) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(html_text)
        path = f.name
    prof = tempfile.mkdtemp()
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    f"--user-data-dir={prof}", "--allow-file-access-from-files",
                    "--force-device-scale-factor=1", f"--window-size={W},{H}",
                    "--virtual-time-budget=1500", f"--screenshot={out}", f"file://{path}"],
                   check=True, capture_output=True)
    # store wants no alpha
    subprocess.run(["sips", "-s", "format", "png", out, "--out", out], capture_output=True)


def main():
    copy = json.load(open(sys.argv[1]))
    rawroot, outroot = sys.argv[2], sys.argv[3]
    only = sys.argv[4].split(",") if len(sys.argv) > 4 else None
    for loc, spec in copy.items():
        if only and loc not in only:
            continue
        od = os.path.join(outroot, loc)
        os.makedirs(od, exist_ok=True)
        for i, shot in enumerate(spec["shots"], 1):
            raw = os.path.join(rawroot, spec["raw"], shot["capture"] + ".png")
            if not os.path.exists(raw):
                print("MISSING", loc, raw)
                continue
            out = os.path.join(od, f"{i:02d}_{shot['id']}.png")
            render(page(shot, raw, spec.get("font", "pixel")), out)
            print(out)


if __name__ == "__main__":
    main()
