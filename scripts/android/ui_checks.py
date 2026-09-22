"""Automatic checks over one captured screen (master plan 1.3).

Reads the uiautomator dump the sweep saves beside each screenshot and reports
what a machine can be sure of — nothing here is a judgement about looks:

  english      a UI string shown in English while the app is in another
               language: the on-screen text is EXACTLY a catalog string's
               English value and that string has a different translation in
               the shot's language. Learning material is English on purpose
               and never matches a catalog string, so it is not flagged.
  placeholder  a format hole reached the screen (%s, %1$d, %lld, {name}).
  covered      a tappable control overlaps the status bar or the navigation
               bar (the app draws edge to edge; see ui/BottomInsets.kt).
  offscreen    text laid out past the right edge of the screen.

What it can't see: text clipped INSIDE its box (the dump reports the whole
string, not what fit) — that stays a human's call in the gallery.
"""
import html
import os
import re
import xml.etree.ElementTree as ET

RES = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "res")
LANG_DIR = {"ko": "values-ko", "ja": "values-ja", "zh-Hant": "values-zh-rTW", "en": "values"}
FILES = ("strings_catalog.xml", "strings_android.xml")
PLACEHOLDER = re.compile(r"%(\d+\$)?(l{0,2}[sdf@]|l{0,2}d)|\{[a-zA-Z_]+\}")
BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def _clean(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        v = v[1:-1]
    return html.unescape(v.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n")).strip()


def _strings(folder):
    out = {}
    for f in FILES:
        p = os.path.join(RES, folder, f)
        if not os.path.exists(p):
            continue
        for el in ET.parse(p).getroot().iter("string"):
            name = el.get("name")
            text = "".join(el.itertext())
            if name:
                out[name] = _clean(text)
    return out


_cache = {}


def english_leaks_table(lang):
    """English values that should NOT appear when the app runs in [lang]."""
    if lang in _cache:
        return _cache[lang]
    en = _strings("values")
    loc = _strings(LANG_DIR.get(lang, "values"))
    table = {}
    for name, e in en.items():
        t = loc.get(name)
        if t and t != e and len(e) >= 3 and re.search(r"[A-Za-z]{2}", e):
            table[e] = name
    _cache[lang] = table
    return table


def parse_bars(path):
    bars = []
    if os.path.exists(path):
        for line in open(path):
            m = BOUNDS.search(line)
            if m:
                bars.append(tuple(map(int, m.groups())))
    return bars or [(0, 0, 1080, 142), (0, 2298, 1080, 2424)]


def check(xml_path, lang, bars):
    if not os.path.exists(xml_path) or os.path.getsize(xml_path) == 0:
        return [("nodump", "no view tree was captured")]
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError:
        return [("nodump", "view tree unreadable")]
    leaks = english_leaks_table(lang) if lang != "en" else {}
    width = max((int(b[2]) for b in bars), default=1080)
    issues, seen = [], set()

    def add(kind, detail):
        if (kind, detail) not in seen:
            seen.add((kind, detail))
            issues.append((kind, detail))

    for n in root.iter("node"):
        if not n.get("package", "").startswith("com.roro.futurevoice"):
            continue
        text = (n.get("text") or "").strip()
        desc = (n.get("content-desc") or "").strip()
        m = BOUNDS.match(n.get("bounds", ""))
        x1, y1, x2, y2 = map(int, m.groups()) if m else (0, 0, 0, 0)
        for s in (text, desc):
            if not s:
                continue
            if s in leaks:
                add("english", s)
            if PLACEHOLDER.search(s):
                add("placeholder", s)
        if text and x2 > width + 4 and x1 < width:
            add("offscreen", text[:60])
        clickable = n.get("clickable") == "true"
        small = (y2 - y1) < 400 and (x2 - x1) > 0
        if clickable and small:
            for bx1, by1, bx2, by2 in bars:
                overlap = min(y2, by2) - max(y1, by1)
                if overlap > 8 and min(x2, bx2) > max(x1, bx1):
                    label = text or desc or n.get("class", "control").split(".")[-1]
                    add("covered", f"{label[:40]} at y {y1}–{y2}")
    return issues


# --- Static: English written straight into the UI code --------------------
# The runtime check only knows catalog strings. A literal typed into a
# composable never reaches the catalog, so it is English in every language —
# the sign-in screen's "Sign in with the same Apple ID…" was found this way.
SRC = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "java")
LITERAL = re.compile(r'\b(?:Text|label|title|placeholder|contentDescription)\s*[=(]\s*(?:\{\s*Text\(\s*)?"((?:[^"\\]|\\.)*)"', re.S)
# English on purpose: the day card is pinned to English (it is for a feed);
# SituationTree.kt is generated from iOS, which shows these labels in English
# too; debug-only controls never ship.
ALLOW_FILES = {"DayCard.kt", "SituationTree.kt"}
ALLOW_TEXT = re.compile(r"^(Dev |Clone flow \(debug\)|Welcome \(debug\)|Ring now \(debug\))")


def hardcoded_english():
    found = []
    for dirpath, _, files in os.walk(SRC):
        for f in files:
            if not f.endswith(".kt") or f in ALLOW_FILES:
                continue
            src = open(os.path.join(dirpath, f), encoding="utf-8").read()
            for m in LITERAL.finditer(src):
                s = m.group(1)
                if "$" in s and not re.search(r"[A-Za-z]{3,} [A-Za-z]{2,}", s.replace("$", "")):
                    continue
                if re.search(r"[A-Za-z]{2,} [A-Za-z]{2,}", s) and not ALLOW_TEXT.match(s):
                    line = src.count("\n", 0, m.start()) + 1
                    found.append((f, line, s))
    return found
