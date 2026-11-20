#!/usr/bin/env python3
"""Landing page in every app language.

index.html (English) and ko.html (Korean) are written by hand. The other
languages are built FROM index.html: web/i18n/<code>.json holds that
language's copy as {en, text} rows, keyed on the exact English line it
replaces. A row whose English line is no longer in index.html is reported
(the English changed and the copy has to be rewritten), never pasted.

Every page, the two hand-written ones included, gets the same language
picker in the nav, the same hreflang set and a CJK font stack per language.
The app screens inside the phone frames (web/kit) stay English on the new
pages on purpose: only the page's own copy is localized.

  python3 scripts/web-languages.py          # build every page, update sitemap
  python3 scripts/web-languages.py --check  # report stale copy, write nothing

Edit the English page (index.next.html → index.html as before), then run
this; rows it reports as stale need new copy in web/i18n/<code>.json.
"""
import html as _html
import json
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent / "web"
I18N = WEB / "i18n"
SITE = "https://nawana.app/"

# code, file, endonym, the word "Language", sans stack to put first
LANGS = [
    ("en", "index.html", "English", "Language", None),
    ("ko", "ko.html", "한국어", "언어", None),
    ("ja", "ja.html", "日本語", "言語", '"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", "Yu Gothic"'),
    ("zh-Hans", "zh-hans.html", "简体中文", "语言", '"PingFang SC", "Noto Sans SC", "Microsoft YaHei"'),
    ("zh-Hant", "zh-hant.html", "繁體中文", "語言", '"PingFang TC", "Noto Sans TC", "Microsoft JhengHei"'),
    ("es", "es.html", "Español", "Idioma", None),
    ("fr", "fr.html", "Français", "Langue", None),
    ("de", "de.html", "Deutsch", "Sprache", None),
]
CJK = {"ja", "zh-Hans", "zh-Hant"}

# The built pages do NOT sell on the web outside the eurozone. Stripe carries
# usd/krw/eur, and the English page's dollar price is dearer than the local App
# Store in Japan, Taiwan, Mexico… (Plus $22.49 vs ¥3,000 ≈ $19, measured
# 2026-10-28). So each page turns web checkout off, its buttons go to the App
# Store, and its cards print that page's own App Store price (`was` is the App
# Store figure the card shows when checkout is off). The exception, since
# 2026-11-10: the German, French and Spanish pages sell on the web, in euros, to
# a visitor in the eurozone (EURO in index.html, by time zone); anyone else on
# those pages still gets the App Store. Read from App Store Connect 2026-10-28:
# re-read them whenever a price changes there. Max re-read 2026-11-10 (it went to
# $34.99 on 11-03).
#   keys: the US `was` figure in index.html → this page's App Store price
#   a (eu, elsewhere) pair is picked by the visitor's time zone (Europe/*).
STORE_PRICES = {
    "ja": ({"$9.99": "¥1,500", "$99.99": "¥15,000", "$24.99": "¥3,000", "$249.99": "¥30,000", "$34.99": "¥6,000"},
           "日本のApp Storeでの価格です。Google Playやほかの国では、ストアにそれぞれの価格が表示されます。"),
    "zh-Hant": ({"$9.99": "NT$320", "$99.99": "NT$2,990", "$24.99": "NT$690", "$249.99": "NT$6,990", "$34.99": "NT$1,190"},
                "以上為台灣 App Store 的價格。Google Play 與其他地區請以商店顯示的價格為準。"),
    "zh-Hans": ({"$9.99": "US$9.99", "$99.99": "US$99.99", "$24.99": "US$24.99", "$249.99": "US$249.99", "$34.99": "US$34.99"},
                "以上为美国 App Store 的价格。Google Play 和其他地区请以商店显示的价格为准。"),
    "fr": ({"$9.99": "9,99 €", "$99.99": "99,99 €", "$24.99": "22,99 €", "$249.99": "229,99 €", "$34.99": "39,99 €"},
           "Prix de l’App Store en France. Sur Google Play et dans les autres pays, la boutique affiche son propre prix."),
    "de": ({"$9.99": "9,99 €", "$99.99": "99,99 €", "$24.99": "22,99 €", "$249.99": "229,99 €", "$34.99": "39,99 €"},
           "Preise im App Store in Deutschland. Bei Google Play und in anderen Ländern zeigt der Store den dortigen Preis."),
    "es": ({"$9.99": ("9,99 €", "$199 MXN"), "$99.99": ("99,99 €", "$1,999 MXN"), "$24.99": ("22,99 €", "$399 MXN"),
            "$249.99": ("229,99 €", "$3,999 MXN"), "$34.99": ("39,99 €", "$799 MXN")},
           ("Precios de la App Store en España. En Google Play y en otros países, la tienda muestra su propio precio.",
            "Precios de la App Store en México. En Google Play y en otros países, la tienda muestra su propio precio.")),
}
EURO_CHECKOUT = {"de", "fr", "es"}
EU_JS = 'const IN_EU = /^Europe\\//.test((Intl.DateTimeFormat().resolvedOptions().timeZone) || "")\n'


def store_prices(page, code):
    prices, note = STORE_PRICES[code]
    on = "EURO" if code in EURO_CHECKOUT else "false"
    page, n = re.subn(r"(const BILLING = \{.*?)enabled: true,", r"\1enabled: " + on + ",", page, count=1, flags=re.S)
    assert n == 1, f"{code}: BILLING.enabled not found"

    def js(v):
        return json.dumps(v, ensure_ascii=False) if isinstance(v, str) else \
            f"(IN_EU ? {json.dumps(v[0], ensure_ascii=False)} : {json.dumps(v[1], ensure_ascii=False)})"

    def sub(m):
        usd = m.group(1)
        assert usd in prices, f"{code}: no App Store price for {usd}"
        return "was: " + js(prices[usd])
    block = re.search(r"\nconst PLANS = \{.*?\n\}", page, flags=re.S)
    plans = re.sub(r'was: "(\$[\d.]+)"', sub, block.group(0))
    if "IN_EU" in plans:
        plans = "\n" + EU_JS + plans[1:]
    page = page[:block.start()] + plans + page[block.end():]

    if isinstance(note, str):
        p = f'    <p class="p-fine">{note}</p>\n'
    else:
        p = (f'    <p class="p-fine" id="store-note">{note[1]}</p>\n'
             f'    <script>if (/^Europe\\//.test(Intl.DateTimeFormat().resolvedOptions().timeZone || "")) '
             f'document.getElementById("store-note").textContent = {json.dumps(note[0], ensure_ascii=False)}</script>\n')
    i = page.index('    <p class="p-fine" id="manage-sub"')
    return page[:i] + p + page[i:]


def url(file):
    return SITE if file == "index.html" else SITE + file


GLOBE = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">'
         '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18"/></svg>')

CSS = """.langpick { position: relative; }
.langpick summary { list-style: none; cursor: pointer; display: flex; align-items: center; gap: 6px; }
.langpick summary::-webkit-details-marker { display: none; }
.langpick summary svg { width: 15px; height: 15px; display: block; }
.langpick .lp-menu { position: absolute; right: 0; top: calc(100% + 12px); z-index: 60; min-width: 168px;
  display: flex; flex-direction: column; padding: 6px; border-radius: 12px;
  background: rgba(255,253,242,0.98); border: 1px solid rgba(28,33,51,0.10); box-shadow: 0 12px 32px rgba(4,8,26,0.14); }
.langpick .lp-menu a { display: block; padding: 9px 12px; border-radius: 8px; color: #1C2133; text-decoration: none; }
.langpick .lp-menu a:hover { background: rgba(28,33,51,0.06); }
.langpick .lp-menu a[aria-current] { font-weight: 600; }
.nav-menu .lp-row { display: flex; flex-wrap: wrap; padding: 4px calc(var(--pad) - 10px) 0; }
.nav-menu .lp-row a { padding: 10px; }
.nav-menu .lp-row a[aria-current] { color: var(--ink); font-weight: 600; }
@media (max-width: 860px) { .navlinks .langpick { display: none; } }
"""

SCRIPT = """<script>
document.addEventListener("click", function (e) {
  document.querySelectorAll("details.langpick[open]").forEach(function (d) { if (!d.contains(e.target)) d.removeAttribute("open"); });
});
</script>"""

# Every injected block sits between markers, so a rebuild replaces it.
FENCES = {"hreflang": ("<!-- lang:hreflang -->", "<!-- /lang:hreflang -->"),
          "css": ("/* lang:css */", "/* /lang:css */"),
          "pick": ("<!-- lang:pick -->", "<!-- /lang:pick -->"),
          "pickm": ("<!-- lang:pickm -->", "<!-- /lang:pickm -->"),
          "js": ("<!-- lang:js -->", "<!-- /lang:js -->")}


def fence(name, body):
    a, b = FENCES[name]
    return a + body + b


def strip_fences(page):
    for a, b in FENCES.values():
        page = re.sub(r"\n[ \t]*" + re.escape(a) + ".*?" + re.escape(b), "", page, flags=re.S)
        page = re.sub(re.escape(a) + ".*?" + re.escape(b), "", page, flags=re.S)
    return page


def decorate(page, code):
    page = strip_fences(page)
    # the old one-way toggle (en ↔ 한국어) and the old two-language hreflang
    page = re.sub(r'\n[ \t]*<a href="(?:ko|index)\.html">(?:한국어|English)</a>', "", page)
    page = re.sub(r'\n<link rel="alternate" hreflang="[^"]+" href="[^"]+" />', "", page)

    alts = "".join(f'\n<link rel="alternate" hreflang="{c}" href="{url(f)}" />' for c, f, *_ in LANGS)
    alts += f'\n<link rel="alternate" hreflang="x-default" href="{SITE}" />'
    page = page.replace("\n<style>", "\n" + fence("hreflang", alts) + "\n<style>", 1)

    font = next(l[4] for l in LANGS if l[0] == code)
    css = CSS
    if font:
        css += (f'html[lang="{code}"] {{ --sans: {font}, -apple-system, "Helvetica Neue", sans-serif;\n'
                f'  --pixel: "Geist Pixel", {font}, -apple-system, sans-serif; }}\n')
    head_end = page.index("</head>")
    i = page.rindex("</style>", 0, head_end)
    page = page[:i] + fence("css", "\n" + css) + "\n" + page[i:]

    me = next(l for l in LANGS if l[0] == code)
    links = "".join(
        f'<a href="{"/" if f == "index.html" else f}" hreflang="{c}" lang="{c}"'
        + (' aria-current="page"' if c == code else "") + f">{n}</a>"
        for c, f, n, *_ in LANGS)
    desk = (f'<details class="langpick"><summary aria-label="{me[3]}">{GLOBE}<span>{me[2]}</span></summary>'
            f'<div class="lp-menu">{links}</div></details>')
    page, n1 = re.subn(r'(\n([ \t]*)<a class="btn-store" href="#" data-appstore>)',
                       lambda m: "\n" + m.group(2) + fence("pick", desk) + m.group(1), page, count=1)
    page, n2 = re.subn(r'(<div class="nav-menu" id="nav-menu">.*?)(\n  </div>)',
                       lambda m: m.group(1) + "\n    " + fence("pickm", f'<div class="lp-row">{links}</div>') + m.group(2),
                       page, count=1, flags=re.S)
    assert n1 == 1 and n2 == 1, f"{code}: nav not found"
    page = page.replace("</body>", fence("js", "\n" + SCRIPT + "\n") + "\n</body>", 1)
    return page


def localize(english, code, file):
    rows = json.loads((I18N / f"{code}.json").read_text())
    table = {r["en"]: r["text"] for r in rows}
    lines = english.split("\n")
    present = set(lines)
    stale = [r["en"].strip()[:70] for r in rows if r["en"] not in present]
    lines = [table.get(l, l) for l in lines]
    page = "\n".join(lines)
    page = page.replace('<html lang="en">', f'<html lang="{code}">', 1)
    page = page.replace(f'<meta property="og:url" content="{SITE}" />', f'<meta property="og:url" content="{url(file)}" />')
    page = page.replace(f'<link rel="canonical" href="{SITE}" />', f'<link rel="canonical" href="{url(file)}" />')
    # Geist Pixel is ASCII only: a pixel word with any other letter goes to the sans
    page = re.sub(r'<span class="px-k">([^<]*)</span>',
                  lambda m: m.group(1) if (code in CJK or re.search(r"[^\x00-\x7F]", _html.unescape(m.group(1)))) else m.group(0),
                  page)
    return store_prices(page, code), stale


def sitemap():
    sm = WEB / "sitemap.xml"
    text = sm.read_text()
    text = re.sub(r"\n  <url><loc>https://nawana\.app/(?:[a-z-]+\.html)?</loc><xhtml:link.*?</url>", "", text, flags=re.S)
    alts = "".join(f'<xhtml:link rel="alternate" hreflang="{c}" href="{url(f)}"/>' for c, f, *_ in LANGS)
    alts += f'<xhtml:link rel="alternate" hreflang="x-default" href="{SITE}"/>'
    entries = "".join(f"\n  <url><loc>{url(f)}</loc>{alts}</url>" for c, f, *_ in LANGS)
    text = re.sub(r"<urlset[^>]*>",
                  '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">'
                  + entries.replace("\\", "\\\\"), text, count=1)
    return text


def main():
    check = "--check" in sys.argv
    english = (WEB / "index.html").read_text()
    built, bad = {}, False
    for code, file, *_ in LANGS[2:]:
        if not (I18N / f"{code}.json").exists():
            print(f"{code}: no web/i18n/{code}.json, skipped")
            continue
        page, stale = localize(english, code, file)
        if stale:
            bad = True
            print(f"{code}: {len(stale)} rows match no line of index.html:")
            for s in stale[:10]:
                print("   ", s)
        built[file] = decorate(page, code)
    if check:
        sys.exit(1 if bad else 0)
    for code, file, *_ in LANGS[:2]:
        for f in (file, file.replace(".html", ".next.html")):
            p = WEB / f
            if p.exists():
                p.write_text(decorate(p.read_text(), code))
    for f, page in built.items():
        (WEB / f).write_text(page)
        print("wrote", f)
    (WEB / "sitemap.xml").write_text(sitemap())
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
