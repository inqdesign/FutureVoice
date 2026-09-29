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
# A script-qualified code carries its OWN text: zh-Hant must never be
# handed the Simplified script, which is the same language in the wrong
# writing system to read aloud from.
for m in re.finditer(r'"([a-zA-Z-]{2,7})": \[(.*?)\n        \]', seg('byLanguage'), re.S):
    items = re.findall(r'"((?:\\.|[^"\\])*)"', m.group(2))
    paras[m.group(1)] = [t.replace('\\"', '"').replace('\\n', '\n') for t in items]
greet = {m.group(1): m.group(2).replace('\\"', '"')
         for m in re.finditer(r'"([a-zA-Z-]{2,7})": "((?:\\.|[^"\\])*)"', seg('greetings'))}
assert set(paras) == set(greet) and all(len(v) == 6 for v in paras.values())
# The line the onboarding speed pills speak (sized so the three rungs never
# overlap by ear — a short line made 0.9 measurably faster than 1.0).
pace = {m.group(1): m.group(2).replace('\\"', '"')
        for m in re.finditer(r'"([a-zA-Z-]{2,7})": "((?:\\.|[^"\\])*)"', seg('paceSamples'))}
assert "en" in pace
def k(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$') + '"'
out = ['package com.roro.futurevoice.talk', '', '/**',
       ' * The read-aloud script for voice cloning, per TARGET language —',
       ' * EXTRACTED from `VoiceCloneScript.swift` by scripts/android/gen-clone-script.py,',
       ' * never retyped. Edit the Swift file, then re-run the script.', ' */',
       'object VoiceCloneScript {', '',
       '    fun paragraphs(language: String): List<String> =',
       '        handAuthored(language) ?: byLanguage.getValue("en")', '',
       '    /**',
       "     * The script for a language, or null when there isn't one. The",
       '     * EXACT code is tried first so a script-qualified language can',
       '     * carry its own text — zh-Hant must not be handed the Simplified',
       '     * script, which is the same language and the wrong writing system',
       '     * to read aloud from.',
       '     */',
       '    fun handAuthored(language: String): List<String>? =',
       '        byLanguage[language] ?: byLanguage[language.take(2)]', '',
       "    /** The clone's first words, spoken the moment it exists. */",
       '    fun greeting(language: String): String =',
       '        greetings[language] ?: greetings[language.take(2)] ?: greetings.getValue("en")', '',
       '    /** What the onboarding speed pills say — long enough (~4.5 s) that', '     *  the three rungs are told apart by ear. */',
       '    fun paceSample(language: String): String =',
       '        paceSamples[language] ?: paceSamples[language.take(2)] ?: paceSamples.getValue("en")', '',
       '    private val byLanguage: Map<String, List<String>> = mapOf(']
for code in paras:
    out.append(f'        "{code}" to listOf(')
    out += [f'            {k(t)},' for t in paras[code]]
    out.append('        ),')
out += ['    )', '', '    private val greetings: Map<String, String> = mapOf(']
out += [f'        "{code}" to {k(greet[code])},' for code in paras]
out += ['    )', '', '    private val paceSamples: Map<String, String> = mapOf(']
out += [f'        "{code}" to {k(v)},' for code, v in pace.items()]
out += ['    )', '}']
(ROOT/'android/app/src/main/java/com/roro/futurevoice/talk/VoiceCloneScript.kt').write_text('\n'.join(out) + '\n')
print('VoiceCloneScript.kt regenerated', file=sys.stderr)
