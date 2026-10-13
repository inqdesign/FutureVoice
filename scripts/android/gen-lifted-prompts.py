#!/usr/bin/env python3
"""Lift every remaining client-side prompt literal out of the iOS Swift source.

These prompts were hand-ported to Kotlin, one screen at a time, and a retype
loses exactly what a reader can't see: Swift's `\\` line continuation keeps
the next line's leftover indent ("…the way they'd   say it"), a blank line
between paragraphs, a trailing newline. Measured on 2026-10-13: the grammar
focus, weekly-test, public-intro and public-figure prompts all differed from
iOS by such bytes. So each literal is read here, with Swift's own semantics
(`iosref.literal_at`), at the pinned iOS ref, and written into
`talk/LiftedPrompts.kt`. The CODE around a prompt (which lines are listed,
in what order) stays hand-ported next to its caller.

    python3 scripts/android/gen-lifted-prompts.py [--check] [--ref <sha>]

Every interpolation must be mapped below, or the run fails.
"""
import pathlib, re, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "promptgen"))
from iosref import ROOT, REF, show, emit, literal_at, kotlin, kt, unescape  # noqa: E402

OUT = ROOT / "android/app/src/main/java/com/roro/futurevoice/talk/LiftedPrompts.kt"
IND = "            "


def lift(src, fn_anchor, lit_anchor, interp, nth=0):
    """The `nth` literal opening at `lit_anchor` after `fn_anchor`."""
    if fn_anchor not in src:
        sys.exit(f"anchor not found: {fn_anchor!r}")
    pos = src.index(fn_anchor)
    for _ in range(nth):
        pos = src.index(lit_anchor, pos) + len(lit_anchor)
    return kotlin(literal_at(src, lit_anchor, pos), interp, IND)


coaching = show("FutureVoice/Services/CoachingLanguage.swift")
speech = show("FutureVoice/Services/Speech/SpeechEngines.swift")
greeting = show("FutureVoice/Services/GreetingEngine.swift")
focus = show("FutureVoice/Services/GrammarFocus.swift")
weekly = show("FutureVoice/Services/WeeklyTestEngine.swift")
intro = show("FutureVoice/Services/PublicIntroComposer.swift")
recap = show("FutureVoice/Services/WeekRecap.swift")
brief = show("FutureVoice/Services/ScenarioBriefEngine.swift")

F = []  # (doc, signature, body)

F.append(("iOS `CoachingLanguage.contract` — the text; the caller returns \"\" when the two names match.",
          "contract(targetName: String, nativeName: String)",
          lift(coaching, "static func contract(target: String, native: String)", 'return """',
               {"targetName": "targetName", "nativeName": "nativeName"})))

# --- Speech (SpeechEngines.swift) -------------------------------------------
F.append(("iOS `SpeechReader.prompt(language:)`.",
          "speechReader(target: String, fillers: String)",
          lift(speech, "private static func prompt(language: String)", 'return """',
               {"target": "target", "fillers": "fillers"})))
F.append(("iOS `SpeechCoach.review`'s system prompt.",
          "speechCoachSystem(level: String, target: String, contract: String, nativeName: String, "
          "rateLow: Int, rateHigh: Int, unit: String)",
          lift(speech, "enum SpeechCoach {", 'let system = """', {
              "level.rawValue.uppercased()": "level", "target": "target", "nativeName": "nativeName",
              "CoachingLanguage.contract(target: script.language, native: native)": "contract",
              "metrics.rateLow": "rateLow", "metrics.rateHigh": "rateHigh", "unit": "unit"})))
F.append(("iOS `SpeechCoach.review`'s user message.",
          "speechCoachUser(body: String, transcript: String, accuracy: Int, missed: String, rate: Int, "
          "unit: String, paceScore: Int, pausesAtBreaks: Int, breaks: Int, hesitations: Int, "
          "hesitationSeconds: String, pauseScore: Int, fillers: Int, fillerScore: Int, steadiness: Int, "
          "overall: Int)",
          lift(speech, "enum SpeechCoach {", 'let user = """', {
              "script.body": "body", "transcript": "transcript", "metrics.accuracy": "accuracy",
              'metrics.missed.isEmpty ? "none" : metrics.missed.joined(separator: " | ")': "missed",
              "metrics.rate": "rate", "unit": "unit", "metrics.paceScore": "paceScore",
              "metrics.pausesAtBreaks": "pausesAtBreaks", "metrics.breaks": "breaks",
              "metrics.hesitations": "hesitations",
              'String(format: "%.1f", SpeechAnalyzer.hesitationSeconds)': "hesitationSeconds",
              "metrics.pauseScore": "pauseScore", "metrics.fillers": "fillers",
              "metrics.fillerScore": "fillerScore", "metrics.steadiness": "steadiness",
              "metrics.overall": "overall"})))
F.append(("iOS `SpeechScriptEngine.write`'s system prompt.",
          "speechWriterSystem(target: String, nativeName: String, contract: String, genreBrief: String, "
          "units: Int, unitName: String, seconds: Int, level: String, vocabulary: String, structure: String)",
          lift(speech, "enum SpeechScriptEngine {", 'let system = """', {
              "target": "target", "nativeName": "nativeName",
              "CoachingLanguage.contract(target: language, native: native)": "contract",
              "genreBrief(genre)": "genreBrief", "units": "units", "unitName": "unitName",
              "seconds": "seconds", "level.rawValue.uppercased()": "level",
              "scale.vocabulary": "vocabulary", "scale.structure": "structure"})))

# `SpeechScriptEngine.genreBrief`: one plain literal per case.
gb = speech[speech.index("private static func genreBrief(_ genre: SpeechGenre)"):]
gb = gb[:gb.index("\n    }\n")]
briefs = re.findall(r'case \.(\w+):\s*return "((?:[^"\\]|\\.)*)"', gb)
if len(briefs) < 6:
    sys.exit(f"genreBrief: {len(briefs)} cases parsed")
F.append(("iOS `SpeechScriptEngine.genreBrief`, by the genre's raw value; \"\" for an unknown one.",
          "speechGenreBrief(genre: String)",
          "when (genre) {\n" + "".join(f'                "{c}" -> {kt(unescape(t))}\n' for c, t in briefs)
          + '                else -> ""\n            }'))

# --- People ------------------------------------------------------------------
F.append(("iOS `GreetingEngine.write`'s system prompt.",
          "greetingSystem(language: String)",
          lift(greeting, "static func write(for c: Counterpart", 'let system = """', {"language": "language"})))
F.append(("iOS `PublicIntroComposer.prompt`; [about] is its `about` lines joined.",
          "publicIntro(languageName: String, about: String)",
          lift(intro, "static func prompt(_ s: Sources)", 'return """', {
              "languageName": "languageName", 'about.joined(separator: "\\n")': "about",
              "CoachingLanguage.breathPunctuation": "CoachingLanguage.breathPunctuation"})))

# --- Grammar focus (GrammarFocus.swift) --------------------------------------
PAT = {"pattern.mistake": "mistake", "pattern.correction": "correction", "pattern.context": "context"}
F.append(("iOS `GrammarFocus.describe`'s system prompt.",
          "focusDescribeSystem(targetName: String, nativeName: String)",
          lift(focus, "static func describe(", 'let system = """',
               {"targetName": "targetName", "nativeName": "nativeName"})))
F.append(("iOS `GrammarFocus.describe`'s user message.",
          "focusDescribeContent(mistake: String, correction: String, context: String)",
          lift(focus, "static func describe(", 'let content = """', PAT)))
F.append(("iOS `GrammarFocus.isRepeat`'s system prompt.",
          "focusRepeatSystem()",
          lift(focus, "func isRepeat(", 'let system = """', {})))
F.append(("iOS `GrammarFocus.isRepeat`'s user message; [list] is the fixes, one per line.",
          "focusRepeatContent(mistake: String, correction: String, context: String, list: String)",
          lift(focus, "func isRepeat(", 'let content = """', {**PAT, "list": "list"})))

# --- Weekly test (WeeklyTestEngine.swift) ------------------------------------
F.append(("iOS `WeeklyTestEngine.translateItems`'s system prompt.",
          "weeklyTranslateSystem(targetName: String, nativeName: String, level: String, maxTranslate: Int, "
          "topics: String)",
          lift(weekly, "private static func translateItems(", 'let system = """', {
              "targetName": "targetName", "nativeName": "nativeName",
              "appState.proficiency.rawValue.uppercased()": "level", "maxTranslate": "maxTranslate",
              'topics.joined(separator: "; ")': "topics"})))
F.append(("iOS `WeeklyTestEngine.orderIsNatural`'s system prompt.",
          "weeklyOrderSystem(name: String)",
          lift(weekly, "static func orderIsNatural(", 'let system = """', {"name": "name"})))

# --- Week recap coach (WeekRecap.swift) --------------------------------------
F.append(("iOS `WeekRecapCoach.write`'s system prompt.",
          "weekRecapSystem(targetName: String, nativeName: String, level: String)",
          lift(recap, "enum WeekRecapCoach {", 'let system = """', {
              "targetName": "targetName", "nativeName": "nativeName", "evidence.level": "level"})))
F.append(("iOS `WeekRecapCoach.Evidence.gather`'s evidence block. Each list arrives already "
          "joined, with iOS's \"(none)\" / \"(nothing)\" stand-ins applied by the caller.",
          "weekRecapEvidence(level: String, lines: String, corrections: String, frequent: String, shown: String)",
          lift(recap, "static func gather(recap: WeekRecap", 'let prompt = """', {
              "level": "level", 'lines.prefix(220).joined(separator: "\\n")': "lines",
              'corrections.isEmpty ? "(none)" : corrections.prefix(90).joined(separator: "\\n")': "corrections",
              'frequent.isEmpty ? "(none)" : frequent.joined(separator: ", ")': "frequent",
              'shown.isEmpty ? "(nothing)" : shown.joined(separator: "\\n")': "shown"})))

# --- Scenario brief (ScenarioBriefEngine.swift) ------------------------------
F.append(("iOS `ScenarioBriefEngine.systemPrompt`.",
          "briefSystem(target: String, native: String, sourceCount: Int)",
          lift(brief, "private static func systemPrompt(targetLanguage: String, nativeLanguage: String, sourceCount: Int)",
               'return """', {"target": "target", "native": "native", "sourceCount": "sourceCount"})))

funcs = "\n\n".join(f"    /** {doc} */\n    fun {sig}: String =\n            {body}" for doc, sig, body in F)
emit(OUT, f'''package com.roro.futurevoice.talk

// GENERATED by scripts/android/gen-lifted-prompts.py --ref {REF} — do not edit.
// Source: the iOS prompt literals named on each function, read with Swift's
// own literal semantics at that ref.

/** Prompt TEXT lifted byte for byte from iOS; the code around each stays with its caller. */
object LiftedPrompts {{
{funcs}
}}
''')
