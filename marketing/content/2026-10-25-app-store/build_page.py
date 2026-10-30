#!/usr/bin/env python3
"""Build the review page: findings, screenshot sets per storefront, metadata proposals."""
import base64, glob, html, io, json, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
copy = json.load(open(f"{HERE}/copy.json"))
meta = json.load(open(f"{HERE}/meta.json"))
E = html.escape


def thumb(path, w=330):
    im = Image.open(path).convert("RGB")
    im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, "JPEG", quality=78, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(b.getvalue()).decode()


SETS = [  # (copy key, label, storefronts it serves, meta keys)
    ("ko", "한국어", "Korea", ["ko"]),
    ("ja", "日本語", "Japan", ["ja"]),
    ("de-DE", "Deutsch", "Germany, Austria, Switzerland", ["de-DE"]),
    ("fr-FR", "Français", "France, Belgium, Canada (fr)", ["fr-FR"]),
    ("es", "Español", "Spain + Mexico & Latin America (es-ES, es-MX)", ["es-ES", "es-MX"]),
    ("zh-Hant", "繁體中文", "Taiwan, Hong Kong", ["zh-Hant"]),
    ("zh-Hans", "简体中文", "Singapore, Malaysia, Chinese abroad", ["zh-Hans"]),
    ("en", "English", "US, UK and every storefront without its own set", ["en-US"]),
]

tabs, panels = [], []
for i, (key, label, where, metas) in enumerate(SETS):
    spec = copy.get(key)
    folder = f"{HERE}/out/{key}"
    files = sorted(glob.glob(f"{folder}/*.png"))
    if not spec or not files:
        continue
    sel = "true" if i == 0 else "false"
    tabs.append(f'<button role="tab" id="tab-{key}" aria-controls="p-{key}" aria-selected="{sel}" data-k="{key}">{E(label)}</button>')
    shots = "".join(
        f'<figure><img loading="lazy" src="{thumb(f)}" alt="{E(s["title"].replace(chr(10), " "))}"><figcaption>{n:02d} · {E(s["id"])}</figcaption></figure>'
        for n, (f, s) in enumerate(zip(files, spec["shots"]), 1))
    rows = []
    for mk in metas:
        m = meta[mk]
        cells = "".join(
            f'<tr><th>{E(name)}</th><td class="now">{E(m["fields"][f]["now"])}<span class="n">{m["fields"][f]["now_len"]}</span></td>'
            f'<td class="new">{E(m["fields"][f]["new"])}<span class="n">{m["fields"][f]["new_len"]}/{m["fields"][f]["limit"]}</span></td></tr>'
            for f, name in (("name", "Name"), ("subtitle", "Subtitle"), ("keywords", "Keywords"), ("promo", "Promotional text")))
        rows.append(f'<div class="meta"><h4>{E(mk)} metadata</h4><p class="why">{E(m["why"])}</p>'
                    f'<div class="tw"><table><thead><tr><th></th><th>Live now</th><th>Proposed</th></tr></thead><tbody>{cells}</tbody></table></div></div>')
    panels.append(f'''<section role="tabpanel" id="p-{key}" aria-labelledby="tab-{key}" {"" if i == 0 else "hidden"}>
<div class="who"><div><span class="lab">Storefronts</span>{E(where)}</div><div><span class="lab">Written for</span>{E(spec["audience"])}</div></div>
<div class="strip">{shots}</div>{"".join(rows)}</section>''')

live = "".join(f'<img src="{thumb(f, 150)}" alt="live screenshot">'
               for f in sorted(glob.glob(f"{HERE}/live/en-GB/APP_IPHONE_65/*.png")))
geist = base64.b64encode(open("/Users/eunggyuelee/FutureVoice/web/GeistPixel.ttf", "rb").read()).decode()

page = open(f"{HERE}/page_template.html").read()
page = (page.replace("{{GEIST}}", geist).replace("{{TABS}}", "".join(tabs))
        .replace("{{PANELS}}", "".join(panels)).replace("{{LIVE}}", live))
open(f"{HERE}/app-store-refresh.html", "w").write(page)
print(len(page) / 1e6, "MB")
