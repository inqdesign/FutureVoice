#!/usr/bin/env python3
"""Lift the upcoming goal's preparation prompts out of the Swift source.

Byte for byte, from FutureVoice/Services/GoalPrep.swift (iOS 70bb10f4 …
67cae6a9):
  - `GoalPrep.system(goal:appState:earlier:now:)` — the day's reading and
    model answer, with its per-level lengths (`words`) and Korean line;
  - `GoalPrep.phase(_:now:)` — where the preparation is, by days left;
  - `GoalPrep.questions(for:appState:)`'s system prompt — the likely
    questions on the day, with its Korean line.
The loops that build the learner's facts and the days already done are
ported by hand in GoalPrep.kt and PINNED here: the run fails the day their
Swift changes.

    python3 scripts/android/gen-goal-prep-prompts.py [--check] [--ref <sha>]
"""
import pathlib, re, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "promptgen"))
from iosref import ROOT, REF, show, emit, literal_at, kotlin, kt, unescape, func_body, pin  # noqa: E402

OUT = ROOT / "android/app/src/main/java/com/roro/futurevoice/talk/GoalPrepPrompts.kt"
src = show("FutureVoice/Services/GoalPrep.swift")

LIT = r'"((?:[^"\\]|\\.)*)"'


def one_line(swift: str, interp=None) -> str:
    """A single-line Swift literal's body as a Kotlin expression; `\\(x)` is
    mapped through `interp`."""
    interp = interp or {}
    parts, buf, k = [], "", 0
    while k < len(swift):
        if swift.startswith("\\(", k):
            j = swift.index(")", k)
            expr = swift[k + 2:j]
            if expr not in interp:
                sys.exit(f"unmapped interpolation: {expr}")
            if buf:
                parts.append(kt(unescape(buf))); buf = ""
            parts.append(interp[expr])
            k = j + 1
            continue
        if swift[k] == "\\":
            buf += swift[k:k + 2]; k += 2; continue
        buf += swift[k]; k += 1
    if buf:
        parts.append(kt(unescape(buf)))
    return " + ".join(parts) if parts else '""'


def ternary_tail(expr: str, head: str) -> str:
    """`X.isEmpty ? "" : X + "<tail>"` → the tail literal, as Kotlin."""
    m = re.fullmatch(re.escape(head) + r'\.isEmpty \? "" : ' + re.escape(head) + r' \+ ' + LIT, expr)
    if not m:
        sys.exit(f"unexpected shape: {expr}")
    return one_line(m.group(1))


# --- the day's preparation -------------------------------------------------
sy = src.index("private static func system(goal: UpcomingGoal")
segs = literal_at(src, 'return """', sy)
interp = {
    "target": "target", "native": "native", "level": "level",
    "goal.promptLine(now: now)": "promptLine",
    "phase(goal, now: now)": "phase",
    'about.isEmpty ? "Nothing yet." : about.joined(separator: "\\n")':
        '(if (about.isEmpty()) "Nothing yet." else about.joinToString("\\n"))',
    'done.isEmpty ? "Nothing yet — this is day 1." : done.joined(separator: "\\n")':
        '(if (done.isEmpty()) "Nothing yet — this is day 1." else done.joinToString("\\n"))',
    "words": "words", "korean": "korean",
}
for kind, v in segs:
    if kind == "i" and v.startswith("goal.materialLines.isEmpty"):
        interp[v] = f'(if (materialLines.isEmpty()) "" else materialLines + {ternary_tail(v, "goal.materialLines")})'
day_system = kotlin(segs, interp)

words = {}
for case, key in ((".a1", "A1"), (".a2", "A2"), (".b1", "B1"), (".b2", "B2")):
    m = re.search(r"case " + re.escape(case) + r": words = " + LIT, src[sy:])
    words[key] = one_line(m.group(1))
words["else"] = one_line(re.search(r"default: words = " + LIT, src[sy:]).group(1))
day_korean = one_line(re.search(r'let korean = appState\.nativeLanguage == "ko" \? ' + LIT + ' : ""', src[sy:]).group(1))

# --- the phase ---------------------------------------------------------------
ph = src.index("static func phase(_ goal: UpcomingGoal")
ph_body = func_body(src, "phase", ph)
no_date = one_line(re.search(r"guard let left = goal\.daysLeft\(now: now\) else \{\s*return " + LIT, ph_body).group(1))
phase_cases = {}
for case in ("...0", "1...3", "4...14"):
    phase_cases[case] = one_line(re.search(r"case " + re.escape(case) + r": return " + LIT, ph_body).group(1),
                                 {"left": "left"})
phase_default = one_line(re.search(r"default: return " + LIT, ph_body).group(1), {"left": "left"})
assert re.search(r"switch left \{", ph_body), "phase's switch changed"

# --- the likely questions ----------------------------------------------------
qs = src.index("static func questions(for goal: UpcomingGoal")
q_korean = one_line(re.search(r'let korean = appState\.nativeLanguage == "ko" \? ' + LIT + ' : ""', src[qs:]).group(1))
q_segs = literal_at(src, 'system: """', qs)
q_interp = {
    "target": "target", "native": "native", "korean": "korean",
    "appState.proficiency.rawValue.uppercased()": "level",
    "goal.promptLine()": "promptLine",
}
for kind, v in q_segs:
    if kind == "i" and v.startswith("goal.materialLines.isEmpty"):
        q_interp[v] = f'(if (materialLines.isEmpty()) "" else materialLines + {ternary_tail(v, "goal.materialLines")})'
questions_system = kotlin(q_segs, q_interp)

# --- hand-ported pieces, pinned ----------------------------------------------
pin({
    # The learner's facts and the days already done (GoalPrep.kt `system`).
    "GoalPrep.system": (func_body(src, "system", sy), "dc4168e24a50"),
})

emit(OUT, f'''package com.roro.futurevoice.talk

import com.roro.futurevoice.data.CefrLevel

// GENERATED by scripts/android/gen-goal-prep-prompts.py --ref {REF} — do not edit.
// Source: FutureVoice/Services/GoalPrep.swift (GoalPrep.system, phase,
// questions).

object GoalPrepPrompts {{
    /** iOS `GoalPrep.system`'s `words`: the reading and answer lengths. */
    fun words(level: CefrLevel): String = when (level) {{
        CefrLevel.A1 -> {words["A1"]}
        CefrLevel.A2 -> {words["A2"]}
        CefrLevel.B1 -> {words["B1"]}
        CefrLevel.B2 -> {words["B2"]}
        else -> {words["else"]}
    }}

    /** iOS `GoalPrep.system`'s Korean line. */
    fun dayKorean(native: String): String = if (native == "ko") {day_korean} else ""

    /** iOS `GoalPrep.phase`: where the preparation is; null = no date. */
    fun phase(left: Int?): String {{
        if (left == null) return {no_date}
        return when (left) {{
            in Int.MIN_VALUE..0 -> {phase_cases["...0"]}
            in 1..3 -> {phase_cases["1...3"]}
            in 4..14 -> {phase_cases["4...14"]}
            else -> {phase_default}
        }}
    }}

    /** iOS `GoalPrep.system`. [about] and [done] are built by the caller. */
    fun daySystem(target: String, native: String, level: String, promptLine: String, phase: String,
                  materialLines: String, about: List<String>, done: List<String>, words: String,
                  korean: String): String =
        {day_system}

    /** iOS `GoalPrep.questions`'s Korean line. */
    fun questionsKorean(native: String): String = if (native == "ko") {q_korean} else ""

    /** iOS `GoalPrep.questions`'s system prompt. */
    fun questionsSystem(target: String, native: String, level: String, promptLine: String,
                        materialLines: String, korean: String): String =
        {questions_system}
}}
''')
