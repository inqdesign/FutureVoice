#!/usr/bin/env python3
"""
Generate Android string resources from the iOS string catalog.

    scripts/android/gen-strings.py            # write res/values*/strings_catalog.xml
    scripts/android/gen-strings.py --check    # exit 1 if the files on disk are stale

`FutureVoice/Resources/Localizable.xcstrings` is the ONE catalog
(`android-launch-roadmap.md` §0.4: no string is authored twice). Its keys are
the English text, exactly as iOS's `Text("literal")` / `explain("literal")`
use them; here each key becomes an `R.string.<slug>` — `resourceName("Free
talk")` == `free_talk` — so a Kotlin call site can be derived from the English
text by eye. A string Android needs that iOS doesn't is added to the catalog
by hand (`extractionState: "manual"`), never to a `strings.xml`.

Skipped, deliberately:
  - `shouldTranslate: false` entries — punctuation, format shells, dev samples;
  - `extractionState: "stale"` — no longer in the iOS code, so not in the product;
  - blank keys.

Format specifiers are rewritten from Foundation to Java (`%@` → `%s`,
`%lld` → `%d`) and given positions when a string has more than one, which
Android lint requires and translators reorder by. Values are emitted quoted,
so leading/trailing spaces and apostrophes survive untouched.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "FutureVoice/Resources/Localizable.xcstrings"
RES = ROOT / "android/app/src/main/res"
FILE_NAME = "strings_catalog.xml"
DEFAULT_LANGUAGES = ["en", "ko"]   # ko/en are the launch languages; de UI is not

JAVA_KEYWORDS = {
    "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
    "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
    "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int",
    "interface", "long", "native", "new", "package", "private", "protected", "public",
    "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this",
    "throw", "throws", "transient", "try", "void", "volatile", "while", "true", "false",
    "null", "in", "is", "as", "fun", "val", "var", "when", "object", "typealias",
}

SPEC = re.compile(r"%(\d+\$)?([-+ 0#]*\d*(?:\.\d+)?)(lld|llu|ld|lu|d|i|u|@|f|s|c)")


def resource_name(key: str) -> str:
    """Stable, readable slug for a catalog key (before collision handling)."""
    slug = re.sub(r"[^a-z0-9]+", "_", key.lower()).strip("_")
    if not slug or slug[0].isdigit():
        slug = "s_" + slug if slug else "s_" + hashlib.sha1(key.encode()).hexdigest()[:8]
    if len(slug) > 60:
        slug = slug[:60].rstrip("_") + "_" + hashlib.sha1(key.encode()).hexdigest()[:6]
    if slug in JAVA_KEYWORDS:
        slug += "_"
    return slug


def java_format(value: str) -> str:
    """Foundation → Java format specifiers, positional when there are several."""
    parts = value.split("%%")
    out = []
    for part in parts:
        specs = list(SPEC.finditer(part))
        # Foundation positions only appear when the en override wrote them;
        # otherwise a string with >1 spec gets 1$, 2$, … in order.
        needs_positions = len(specs) > 1

        def repl(m, counter=[0]):
            counter[0] += 1
            pos, flags, conv = m.group(1), m.group(2), m.group(3)
            conv = {"@": "s", "lld": "d", "llu": "d", "ld": "d", "lu": "d", "i": "d", "u": "d"}.get(conv, conv)
            if not pos and needs_positions:
                pos = f"{counter[0]}$"
            return f"%{pos or ''}{flags}{conv}"

        out.append(SPEC.sub(repl, part))
    return "%%".join(out)


def xml_value(value: str) -> str:
    v = java_format(value)
    v = v.replace("\\", "\\\\").replace('"', '\\"')
    v = v.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    v = v.replace("\n", "\\n").replace("\t", "\\t")
    if v[:1] in ("@", "?"):
        v = "\\" + v
    return f'"{v}"'


def load_entries():
    catalog = json.loads(CATALOG.read_text())
    source = catalog["sourceLanguage"]
    entries = {}
    skipped = {"blank": 0, "no_translate": 0, "stale": 0}
    for key, meta in catalog["strings"].items():
        if not key.strip():
            skipped["blank"] += 1
            continue
        if meta.get("shouldTranslate") is False:
            skipped["no_translate"] += 1
            continue
        if meta.get("extractionState") == "stale":
            skipped["stale"] += 1
            continue
        values = {}
        for lang, loc in meta.get("localizations", {}).items():
            unit = loc.get("stringUnit")
            if unit and unit.get("value") is not None:
                values[lang] = unit["value"]
        values.setdefault(source, key)   # the key IS the source-language text
        entries[key] = values

    # Collisions: every member of a colliding group gets a hash suffix, so a
    # name never silently changes meaning when a sibling key appears.
    by_name = {}
    for key in entries:
        by_name.setdefault(resource_name(key), []).append(key)
    names = {}
    for name, keys in by_name.items():
        if len(keys) == 1:
            names[keys[0]] = name
        else:
            for key in keys:
                names[key] = f"{name}_{hashlib.sha1(key.encode()).hexdigest()[:6]}"
    return source, entries, names, skipped


def render(lang: str, source: str, entries, names) -> str:
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        "<!-- GENERATED by scripts/android/gen-strings.py from",
        "     FutureVoice/Resources/Localizable.xcstrings — do not edit; edit the",
        "     catalog and re-run. Names are resource_name(<English key>). -->",
        "<resources>",
    ]
    count = 0
    for key in sorted(entries, key=lambda k: names[k]):
        value = entries[key].get(lang)
        if value is None:
            continue   # Android falls back to values/ (en) on its own
        name = names[key]
        if name != resource_name(key) or len(key) > 60:
            lines.append(f"    <!-- {key!r} -->")
        lines.append(f"    <string name=\"{name}\">{xml_value(value)}</string>")
        count += 1
    lines.append("</resources>")
    lines.append("")
    return "\n".join(lines), count


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify the generated files are current")
    ap.add_argument("--languages", default=",".join(DEFAULT_LANGUAGES))
    args = ap.parse_args()

    source, entries, names, skipped = load_entries()
    stale = []
    for lang in args.languages.split(","):
        folder = RES / ("values" if lang == source else f"values-{lang}")
        text, count = render(lang, source, entries, names)
        path = folder / FILE_NAME
        if args.check:
            if not path.exists() or path.read_text() != text:
                stale.append(path)
        else:
            folder.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        print(f"{lang}: {count} strings → {path.relative_to(ROOT)}", file=sys.stderr)
    print(f"catalog: {len(entries)} usable keys, skipped {skipped}", file=sys.stderr)
    if stale:
        print("STALE — re-run scripts/android/gen-strings.py:", *[p.relative_to(ROOT) for p in stale], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
