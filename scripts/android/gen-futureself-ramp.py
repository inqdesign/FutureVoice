#!/usr/bin/env python3
"""Extract Futureself's 5-step palettes from Swift into Kotlin (never retyped).

The ramps live in `FutureselfPixels.swift` (`FutureselfRamp.table`), which is
itself lifted from `Shaders/Futureself.metal`'s kPalette. Re-run after
touching either; a palette that drifts between platforms is the same brand
wearing two faces.
"""
import re, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
src = (ROOT / 'FutureVoice/Shared/FutureselfPixels.swift').read_text()
seg = src[src.index('static let table'):src.index('static func rgb')]
themes = re.findall(r'\[ // (\d) (\w+)(.*?)\n        \],', seg, re.S)
assert len(themes) == 6, len(themes)
out = ['package com.roro.futurevoice.ui.brand', '',
       'import androidx.compose.ui.graphics.Color', '',
       '/**',
       " * Futureself's 5-step ramps — EXTRACTED from `FutureselfPixels.swift`",
       ' * by scripts/android/gen-futureself-ramp.py, which lifts them from',
       ' * `Shaders/Futureself.metal`. Indexed [theme][dark ? 0 : 1][step],',
       ' * base → hottest. Never retyped: one brand, one palette.',
       ' */',
       'object FutureselfRamp {', '',
       '    /** [theme][darkIndex][step] → rgb triple, 0…1. */',
       '    val table: Array<Array<Array<FloatArray>>> = arrayOf(']
for idx, name, body in themes:
    triples = re.findall(r'\(([\d.]+), ([\d.]+), ([\d.]+)\)', body)
    assert len(triples) == 10, (name, len(triples))
    out.append(f'        arrayOf( // {idx} {name}')
    for half in (0, 1):
        rows = triples[half * 5:(half + 1) * 5]
        out.append('            arrayOf(')
        for r, g, b in rows:
            out.append(f'                floatArrayOf({r}f, {g}f, {b}f),')
        out.append('            ),')
    out.append('        ),')
out += ['    )', '',
        '    fun rgb(theme: Int, dark: Boolean, step: Int): FloatArray =',
        '        table[theme.coerceIn(0, table.size - 1)][if (dark) 0 else 1][step.coerceIn(0, 4)]', '',
        '    fun color(theme: Int, dark: Boolean, step: Int): Color =',
        '        rgb(theme, dark, step).let { Color(it[0], it[1], it[2]) }', '}']
dest = ROOT / 'android/app/src/main/java/com/roro/futurevoice/ui/brand/FutureselfRamp.kt'
dest.write_text('\n'.join(out) + '\n')
print(f'FutureselfRamp.kt regenerated ({len(themes)} themes)', file=sys.stderr)
