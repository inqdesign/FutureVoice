#!/usr/bin/env python3
"""Build the gallery page from a gallery.sh run.

    gallery_page.py <out-dir> <lang> <appearance> <mode> ...

Reads <out>/ios/<mode>.png and <out>/android-raw/<mode>.png (+ result.tsv),
writes small JPEGs beside them, <out>/verdicts.tsv and <out>/index.html.

Verdicts are what a machine can tell from the picture and the run alone:
  crash        the capture app logged a FATAL exception
  not-wired    the harness has no route for the mode (red placeholder)
  not-ported   the app lacks the screen (orange placeholder, reason on it)
  blank        the frame is one flat colour (still loading, or nothing drawn)
  ok           a real screen was drawn
Master plan 1.3 adds the finer checks (leaked English, covered controls).
"""
import html, os, sys
from PIL import Image

out, lang, look, *modes = sys.argv[1:]
W = 360


def thumb(src, dst):
    if not os.path.exists(src):
        return False
    im = Image.open(src).convert("RGB")
    im = im.resize((W, int(im.height * W / im.width)))
    im.save(dst, "JPEG", quality=72)
    return True


def near(c, t):
    return all(abs(a - b) < 30 for a, b in zip(c, t))


def android_verdict(png, crashed):
    if crashed:
        return "crash"
    if not os.path.exists(png):
        return "missing"
    im = Image.open(png).convert("RGB")
    w, h = im.size
    # Sample a grid inside the content area (skip status and nav bars).
    pts = [im.getpixel((w * x // 10, h * y // 20)) for x in range(1, 10) for y in range(3, 18)]
    n = len(pts)
    if sum(near(p, (0xB0, 0x00, 0x20)) for p in pts) > n * 0.8:
        return "not-wired"
    if sum(near(p, (0xE6, 0x51, 0x00)) for p in pts) > n * 0.8:
        return "not-ported"
    # Nothing drawn outside the middle: the splash (a lone icon), a centred
    # spinner, or an empty frame. A sparse but real screen still has ink —
    # a title, a back arrow, a line of text — somewhere outside the centre.
    import numpy as np
    a = np.asarray(im.convert("L"))[::4, ::4]            # every 4th pixel keeps thin text
    hh, ww = a.shape
    body = a[int(hh * 0.06):int(hh * 0.9), :]            # skip status and navigation bars
    dark = body < 110
    bh, bw = body.shape
    dark[int(bh * 0.35):int(bh * 0.65), int(bw * 0.3):int(bw * 0.7)] = False  # splash icon zone
    ink = int(dark.sum())
    if ink < 40:
        return "blank"
    return "ok"


crashed = set()
res = os.path.join(out, "android-raw", "result.tsv")
if os.path.exists(res):
    for line in open(res):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2 and parts[1] == "crash":
            crashed.add(parts[0])

rows, counts = [], {}
for m in modes:
    has_ios = thumb(f"{out}/ios/{m}.png", f"{out}/ios/{m}.jpg")
    thumb(f"{out}/android-raw/{m}.png", f"{out}/android/{m}.jpg")
    v = android_verdict(f"{out}/android-raw/{m}.png", m in crashed)
    counts[v] = counts.get(v, 0) + 1
    rows.append((m, v, has_ios))

with open(f"{out}/verdicts.tsv", "w") as f:
    for m, v, _ in rows:
        f.write(f"{m}\t{v}\n")

colour = {"ok": "ok", "not-ported": "port", "not-wired": "bad",
          "crash": "bad", "blank": "blank", "missing": "blank"}
label = {"ok": "화면", "not-ported": "앱에 없음", "not-wired": "못 이음",
         "crash": "크래시", "blank": "빈 화면", "missing": "없음"}
order = ["crash", "not-wired", "blank", "missing", "not-ported", "ok"]
rows.sort(key=lambda r: (order.index(r[1]) if r[1] in order else 9, r[0]))

cards = []
for m, v, has_ios in rows:
    ios = (f'<img loading="lazy" src="ios/{m}.jpg" alt="iOS {m}">' if has_ios
           else '<div class="none">iOS 샷 없음</div>')
    cards.append(f'''<article class="row" data-v="{v}">
  <header><code>{html.escape(m)}</code><span class="chip {colour.get(v, "blank")}">{label.get(v, v)}</span></header>
  <div class="pair"><figure>{ios}<figcaption>iOS 1.0.7 (54)</figcaption></figure>
  <figure><img loading="lazy" src="android/{m}.jpg" alt="Android {m}"><figcaption>Android</figcaption></figure></div>
</article>''')

present = [k for k in order if k in counts]
filters = "".join(
    f'<button type="button" id="f-{k}" data-f="{k}"><span class="dot {colour[k]}"></span>{label[k]} {counts[k]}</button>'
    for k in present)
tally = " · ".join(f"{label[k]} {counts[k]}" for k in present)
look_ko = "라이트" if look == "light" else "다크"
page = f'''<title>화면 대조판</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;600;700&display=swap">
<style>
:root{{--bg:#eef0f4;--surface:#fff;--fg:#14161b;--muted:#5d6472;--line:#d9dde5;--accent:#0a5cf5;
--ok:#1b7f45;--port:#b35300;--bad:#c0162c;--blank:#6b3fd1;
font-family:"Noto Sans KR",-apple-system,system-ui,sans-serif}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--bg:#0f1115;--surface:#181b21;--fg:#e8eaef;--muted:#9aa2b1;--line:#2a2f38;--accent:#6c9dff;--ok:#4cc27d;--port:#ff9a3d;--bad:#ff5d6e;--blank:#a98bff}}}}
:root[data-theme="dark"]{{--bg:#0f1115;--surface:#181b21;--fg:#e8eaef;--muted:#9aa2b1;--line:#2a2f38;--accent:#6c9dff;--ok:#4cc27d;--port:#ff9a3d;--bad:#ff5d6e;--blank:#a98bff}}
body{{background:var(--bg);color:var(--fg);padding-inline:16px;padding-block:0 32px}}
.top{{position:sticky;top:env(safe-area-inset-top,0px);background:var(--bg);padding-block:16px 12px;z-index:1;display:grid;gap:6px}}
h1{{font-size:20px;margin:0;text-wrap:balance}}
.meta{{color:var(--muted);font-size:13px}}
.filters{{display:flex;flex-wrap:wrap;gap:6px}}
.filters button{{display:inline-flex;align-items:center;gap:6px;padding:5px 11px;border-radius:999px;border:1px solid var(--line);background:var(--surface);color:var(--fg);font:inherit;font-size:13px;cursor:pointer}}
.filters button[aria-pressed="true"]{{border-color:var(--accent);box-shadow:inset 0 0 0 1px var(--accent)}}
.filters button:focus-visible{{outline:2px solid var(--accent);outline-offset:2px}}
.dot{{width:8px;height:8px;border-radius:50%;background:currentColor}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,340px),1fr));gap:14px}}
.row[hidden]{{display:none}}
.row{{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:10px;display:grid;gap:8px}}
.row header{{display:flex;justify-content:space-between;align-items:center;gap:8px}}
code{{font:13px ui-monospace,"SF Mono",Menlo,monospace}}
.chip{{font-size:11px;font-weight:600;padding:2px 8px;border-radius:999px;border:1px solid currentColor}}
.ok{{color:var(--ok)}} .port{{color:var(--port)}} .bad{{color:var(--bad)}} .blank{{color:var(--blank)}}
.pair{{display:grid;grid-template-columns:1fr 1fr;gap:8px}}
figure{{margin:0;display:grid;gap:4px}}
img{{width:100%;max-width:100%;border-radius:8px;display:block;border:1px solid var(--line)}}
figcaption{{color:var(--muted);font-size:11px;text-align:center}}
.none{{aspect-ratio:9/19.5;max-width:100%;border:1px dashed var(--line);border-radius:8px;display:grid;place-items:center;color:var(--muted);font-size:12px}}
@media (prefers-reduced-motion:reduce){{*{{transition:none!important}}}}
</style>
<div class="top">
  <h1>iOS · Android 화면 대조 — 캡처 모드 {len(rows)}개</h1>
  <div class="meta">언어 {html.escape(lang)} · {look_ko} 모드 · {tally}. 문제 있는 모드가 위로 옵니다. 왼쪽이 기준인 iOS, 오른쪽이 안드로이드.</div>
  <div class="filters"><button type="button" id="f-all" data-f="" aria-pressed="true">전부 {len(rows)}</button>{filters}</div>
</div>
<main class="grid">{"".join(cards)}</main>
<script>
const bs=[...document.querySelectorAll('.filters button')];
bs.forEach(b=>b.addEventListener('click',()=>{{const v=b.dataset.f;
  bs.forEach(x=>x.setAttribute('aria-pressed',x===b?'true':'false'));
  document.querySelectorAll('.row').forEach(r=>r.hidden=!!v&&r.dataset.v!==v);}}));
</script>
'''
open(f"{out}/index.html", "w").write(page)
print(tally)
