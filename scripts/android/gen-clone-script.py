#!/usr/bin/env python3
"""Re-extract VoiceCloneScript.kt from VoiceCloneScript.swift (verbatim —
never retype the scripts; the six-beat text IS the phonetic contract)."""
import re, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
sw = (ROOT/'FutureVoice/Services/VoiceCloneScript.swift').read_text()
def seg(name):
    i = sw.index(f'private static let {name}')
    return sw[i:sw.index('\n    ]', i)]
paras = {}
for m in re.finditer(r'"([a-z]{2})": \[(.*?)\n        \]', seg('byLanguage'), re.S):
    items = re.findall(r'"((?:\\.|[^"\\])*)"', m.group(2))
    paras[m.group(1)] = [t.replace('\\"', '"').replace('\\n', '\n') for t in items]
greet = {m.group(1): m.group(2).replace('\\"', '"')
         for m in re.finditer(r'"([a-z]{2})": "((?:\\.|[^"\\])*)"', seg('greetings'))}
assert set(paras) == set(greet) and all(len(v) == 6 for v in paras.values())
def k(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$') + '"'
out = ['package com.roro.futurevoice.talk', '', '/**',
       ' * The read-aloud script for voice cloning, per TARGET language —',
       ' * EXTRACTED from `VoiceCloneScript.swift` by scripts/android/gen-clone-script.py,',
       ' * never retyped. Edit the Swift file, then re-run the script.', ' */',
       'object VoiceCloneScript {', '',
       '    fun paragraphs(language: String): List<String> =',
       '        byLanguage[language] ?: byLanguage.getValue("en")', '',
       "    /** The clone's first words, spoken the moment it exists. */",
       '    fun greeting(language: String): String =',
       '        greetings[language] ?: greetings.getValue("en")', '',
       '    private val byLanguage: Map<String, List<String>> = mapOf(']
for code in paras:
    out.append(f'        "{code}" to listOf(')
    out += [f'            {k(t)},' for t in paras[code]]
    out.append('        ),')
out += ['    )', '', '    private val greetings: Map<String, String> = mapOf(']
out += [f'        "{code}" to {k(greet[code])},' for code in paras]
out += ['    )', '}']
(ROOT/'android/app/src/main/java/com/roro/futurevoice/talk/VoiceCloneScript.kt').write_text('\n'.join(out) + '\n')
print('VoiceCloneScript.kt regenerated', file=sys.stderr)
