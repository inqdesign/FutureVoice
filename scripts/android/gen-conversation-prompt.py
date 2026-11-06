#!/usr/bin/env python3
"""Lift the conversation prompt's TEXT out of the Swift source at an iOS ref.

Every multiline literal `ConversationEngine.conversationSystemPrompt` is
built from — the main body, the NEWS FACTS and FIRST CALL blocks, the level's
WORDS / SENTENCE SHAPES, the beginner question rules, TUTOR MODE, WHO YOU
BECAME with each `FutureGoal`'s line — plus
`turnOutputInstruction` and ConversationView's `realtimeStyleRules`, written
into `talk/ConversationPrompt.kt` byte for byte. Each Swift interpolation is
mapped to a Kotlin expression below; one this script doesn't know fails it,
so a new piece of the iOS prompt can't be silently dropped.

The pieces that are LOGIC rather than text (the persona and remembered-notes
blocks, the character blocks, the clock, the brief lines) are ported by hand
in ConversationEngine.kt / ConversationCharacter.kt / PromptClock.kt, and
`ConversationPromptVectorTest` compares the WHOLE prompt against the real
iOS output (scripts/android/gen-prompt-vectors.sh).

    python3 scripts/android/gen-conversation-prompt.py            # pinned ref
    python3 scripts/android/gen-conversation-prompt.py --check    # exit 1 if stale
    python3 scripts/android/gen-conversation-prompt.py --ref <sha>
"""
import pathlib, re, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "promptgen"))
from iosref import ROOT, REF, show, emit, unescape, literal_at, kt, LIT  # noqa: E402

OUT = ROOT / "android/app/src/main/java/com/roro/futurevoice/talk/ConversationPrompt.kt"


engine = show("FutureVoice/Services/ConversationEngine.swift")
view = show("FutureVoice/Views/ConversationView.swift")
character = show("FutureVoice/Services/ConversationEngine+Character.swift")
ground = show("FutureVoice/Services/CommonGround.swift")
clocksrc = show("FutureVoice/Services/PromptClock.swift")
goalsrc = show("FutureVoice/Services/FutureGoal.swift")


def kotlin_conv(segs, interp, indent="            "):
    parts = []
    for kind, v in segs:
        if kind == "t":
            parts.append(kt(v)); continue
        if v in interp:
            parts.append(interp[v]); continue
        # `x.isEmpty ? "lit" : y`
        m = re.fullmatch(rf'(\w+)\.isEmpty \? {LIT} : (\w+)', v)
        if m and m.group(1) in interp:
            a = interp[m.group(1)]
            parts.append(f'(if ({a}.isEmpty()) {kt(unescape(m.group(2)))} else {interp[m.group(3)]})'); continue
        # `flag ? "lit" : "lit"`
        m = re.fullmatch(rf'(\w+) \? {LIT} : {LIT}', v)
        if m and m.group(1) in interp:
            parts.append(f'(if ({interp[m.group(1)]}) {kt(unescape(m.group(2)))} else {kt(unescape(m.group(3)))})'); continue
        # `LanguageCatalog.base(targetLanguage) == "xx" ? "lit" : ""`
        m = re.fullmatch(rf'LanguageCatalog\.base\(targetLanguage\) == "(\w+)" \? {LIT} : ""', v)
        if m:
            base = "targetLanguage.substringBefore('-')"
            parts.append(f'(if ({base} == "{m.group(1)}") {kt(unescape(m.group(2)))} else "")'); continue
        sys.exit(f"unmapped interpolation: {v}")
    return f" +\n{indent}".join(parts) if parts else '""'


def func_from(name):
    return engine.index(name)


# The level's two halves, in band order.
fn = func_from("static func speechScale(for level: CEFRLevel)")
vocab, struct_ = [], []
pos = fn
for _ in range(3):
    vi = engine.index('vocabulary: """', pos)
    vocab.append(kotlin_conv(literal_at(engine, 'vocabulary: """', pos), {}))
    si = engine.index('structure: """', vi)
    struct_.append(kotlin_conv(literal_at(engine, 'structure: """', vi), {}))
    pos = si + 1

max_turn = re.search(r"static let maxTurnSentences = (\d+)", engine).group(1)

csp = func_from("static func conversationSystemPrompt(")
news = kotlin_conv(literal_at(engine, 'let newsBlock = newsFacts.isEmpty ? "" : """', csp), {
    'newsFacts.map { "- \\($0)" }.joined(separator: "\\n")': 'newsFacts.joinToString("\\n") { "- $it" }',
})
# Per-language lines (iOS 5a462332) are hand-ported in talk/LanguageLines.kt
# (logic + text), "" for every other language.
first = kotlin_conv(literal_at(engine, "let firstMeetingBlock = (firstMeeting && counterpart == nil) ?", csp),
               {"languageName": "languageName",
                "firstCallLanguageLine(targetLanguage)": "LanguageLines.firstCall(targetLanguage)"})
# A later call the same day (iOS 98d7ff2a): the opening line's two kinds.
_ok = re.search(rf'let openerKind = sameDay == nil\s*\? {LIT}\s*: {LIT}', engine[csp:])
if not _ok:
    sys.exit("openerKind's shape changed — `sameDay == nil ? \"…\" : \"…\"` expected")
they_called = kotlin_conv(literal_at(engine, "let theyCalledBlock = isFreeTalk ? ", csp), {
    "freeTalkCue.instruction": "freeTalkCue.instruction",
    "openerKind": f'(if (sameDay) {kt(unescape(_ok.group(2)))}\n             else {kt(unescape(_ok.group(1)))})',
})
# What you and they did earlier today (iOS 98d7ff2a), free talk only.
earlier = kotlin_conv(literal_at(engine, "let earlierBlock = sameDay.map { e in ", csp), {"e.record": "record"})
# "My own topic" (topics page, iOS deed6cf4).
own_topic = kotlin_conv(literal_at(
    engine, "let ownTopicBlock = (learnerPicksTopic && topic.isEmpty && counterpart == nil && !tutor) ?", csp), {})
cue_at = engine.index("enum FreeTalkCue: String, CaseIterable {")
cue = {case: kotlin_conv(literal_at(engine, 'return """', engine.index(f"case .{case}:", cue_at)), {},
                         indent="                ")
       for case in ("news", "plainQuestion", "ownThing")}
main_anchor = engine.index("        return \"\"\"\n        You're in a real-feeling SPOKEN", csp)
system = kotlin_conv(literal_at(engine, 'return """', main_anchor), {
    "languageName": "languageName",
    "counterpart.map { personaBlock(forCast: $0, persona: persona, languageName: languageName) } ?? personaBlock(persona, languageName: languageName)": "personaBlock",
    "counterpartBlock": "counterpartBlock",
    "firstMeetingBlock": "firstMeetingBlock",
    "theyCalledBlock": "theyCalledBlock",
    "earlierBlock": "earlierBlock",
    "ownTopicBlock": "ownTopicBlock",
    "clockBlock": "clockBlock",
    "LanguageCatalog.englishName(nativeLanguage)": "nativeName",
    "levelName": "levelName",
    "patterns": "patterns",
    "weak": "weak",
    "topic": "topic",
    "newsBlock": "newsBlock",
    "briefBlock": "briefBlock",
    "scale.vocabulary": "speechVocabulary(level)",
    "scale.structure": "speechStructure(level)",
    "maxTurnSentences": "MAX_TURN_SENTENCES",
    "CoachingLanguage.breathPunctuation": "CoachingLanguage.breathPunctuation",
    "varietyGuard(targetLanguage)": "LanguageVariety.guard(targetLanguage)",
    # Spanish (iOS 5a462332): the gender half only as the future self, the
    # variety half with no other variety picked; Japanese: how the future
    # self calls them. `asFutureSelf` = no cast person and no topic.
    "spanishGuard(targetLanguage, asFutureSelf: counterpart == nil && topic.isEmpty)":
        "LanguageLines.spanishGuard(targetLanguage, asFutureSelf)",
    "selfAddressLine(targetLanguage, asFutureSelf: counterpart == nil && topic.isEmpty)":
        "LanguageLines.selfAddress(targetLanguage, asFutureSelf)",
    "CoachingLanguage.selfWarmth": "CoachingLanguage.selfWarmth",
    "tutor": "tutor",
    # The learner's own goals (iOS 3d655c8b, WHO YOU BECAME): which calls
    # get it is ConversationEngine.kt's; "" = byte-identical, as iOS is with
    # no goals.
    "futureBlock": "futureBlock",
    "beginnerQuestions(level, targetLanguage: targetLanguage)": "beginnerQuestions(level, targetLanguage)",
    # The lesson-dependent block is assembled in ConversationEngine.kt
    # (`TutorPrompt`), from the pieces lifted below.
    'tutor ? tutorBlock(targetLanguage: targetLanguage, languageName: languageName, lesson: tutorLesson, justTicked: tutorJustTicked, lastFixes: tutorLastFixes, planning: tutorPlanning) : ""':
        '(if (tutor) tutorBlock else "")',
})
# WHO YOU BECAME (iOS 3d655c8b): the goals the learner picked in setup.
future = kotlin_conv(literal_at(
    engine, "let futureBlock = (!futureGoals.isEmpty && counterpart == nil && topic.isEmpty && !tutor) ?", csp),
    {'futureGoals.map { "- " + $0.promptText(languageName: languageName) }.joined(separator: "\\n")': "goalLines"})
# `FutureGoal` ids (in `allCases` order) and what the fluent self is told
# for each (`promptText(languageName:)`).
goal_ids = re.findall(r'^\s*case (\w+) = "([\w.]+)"$', goalsrc[:goalsrc.index("var id: String")], re.M)
pt_at = goalsrc.index("func promptText(languageName: String) -> String {")
pt_body = goalsrc[pt_at:goalsrc.index("\n    }\n", pt_at)]
goal_text = dict(re.findall(rf'case \.(\w+):\s+return {LIT}', pt_body))
if set(goal_text) != {c for c, _ in goal_ids}:
    sys.exit("FutureGoal.promptText doesn't cover every case")


def goal_line(swift):
    parts = [unescape(x) for x in swift.split("\\(languageName)")]
    segs = []
    for n, part in enumerate(parts):
        if n: segs.append(("i", "languageName"))
        if part: segs.append(("t", part))
    return kotlin_conv(segs, {"languageName": "languageName"}, indent="            ")


goal_when = "\n        ".join(f'"{raw}" -> {goal_line(goal_text[case])}' for case, raw in goal_ids)
goal_list = ", ".join(f'"{raw}"' for _, raw in goal_ids)
beginner = kotlin_conv(literal_at(engine, "static func beginnerQuestions(_ level: CEFRLevel"),
                  {"level.rawValue.uppercased()": "level.code.uppercase()",
                   "beginnerQuestionLanguageLine(targetLanguage)": "LanguageLines.beginnerQuestion(targetLanguage)"})
guards = {
    "scriptGuard(targetLanguage)": "CorrectionOnlyPrompt.scriptGuard(targetLanguage)",
    "spacingGuard(targetLanguage)": "CorrectionOnlyPrompt.spacingGuard(targetLanguage)",
    "registerGuard(targetLanguage)": "CorrectionOnlyPrompt.registerGuard(targetLanguage)",
    "varietyGuard(targetLanguage)": "LanguageVariety.guard(targetLanguage)",
    "spokenGrammarGuard(targetLanguage)": "LanguageLines.spokenGrammarGuard(targetLanguage)",
}
# Tutor mode's lesson block (iOS af3c7ffe…bd242766): the text of each branch;
# which branch, and the checklist rows, are TutorPrompt's (hand-ported).
tb = engine.index("static func tutorBlock(targetLanguage: String, languageName: String,")
# Branch order (iOS 23ce515f): planning, final check, done, on (after the
# fixes), none.
tb_plan_at = engine.index('lessonPart = """', tb)
tutor_planning = kotlin_conv(literal_at(engine, 'lessonPart = """', tb), {"round": "round"})
tb_check_at = engine.index('lessonPart = """', tb_plan_at + 10)
tutor_check = kotlin_conv(literal_at(engine, 'lessonPart = """', tb_plan_at + 10), {
    "lesson.titleTarget": "titleTarget", "parts": "parts",
})
tb_done_at = engine.index('lessonPart = """', tb_check_at + 10)
tutor_done = kotlin_conv(literal_at(engine, 'lessonPart = """', tb_check_at + 10), {
    "lesson.titleTarget": "titleTarget",
})
tb_fix_at = engine.index('let fixes = lastFixes.isEmpty ? "" : """', tb)
tutor_fixes = kotlin_conv(literal_at(engine, 'let fixes = lastFixes.isEmpty ? "" : """', tb), {
    'lastFixes.joined(separator: "; ")': 'lastFixes.joinToString("; ")',
})
tb_now_at = engine.index('lessonPart = """', tb_fix_at)
tutor_now_part = kotlin_conv(literal_at(engine, 'lessonPart = """', tb_fix_at), {
    "lesson.titleTarget": "titleTarget", "rows": "rows", "now + 1": "(now + 1)", "fixes": "fixes",
})
tutor_none = kotlin_conv(literal_at(engine, 'lessonPart = """', tb_now_at + 10), {})
tutor = kotlin_conv(literal_at(engine, 'return """', tb),
               {"languageName": "languageName", "lessonPart": "lessonPart", **guards,
                "tutorRegisterLine(targetLanguage)": "LanguageLines.tutorRegisterLine(targetLanguage)",
                "tutorNow(lesson: lesson, justTicked: justTicked && !planning)": "tutorNow"})
tn = engine.index("private static func tutorNow(lesson: TutorLesson?, justTicked: Bool)")
tn_check_at = engine.index('return """', tn)
tutor_now_check = kotlin_conv(literal_at(engine, 'return """', tn), {})
tn_done_at = engine.index('return """', tn_check_at + 10)
tutor_now_done = kotlin_conv(literal_at(engine, 'return """', tn_check_at + 10), {})
tutor_now_next = kotlin_conv(literal_at(engine, 'return """', tn_done_at + 10), {
    "now": "now", "now + 1": "(now + 1)", "next.task": "nextTask", "next.example": "nextExample",
})
output = kotlin_conv(literal_at(engine, "static func turnOutputInstruction("), {
    "LanguageCatalog.englishName(targetLanguage)": "targetName",
    "nativeName": "nativeName",
    **guards,
    "relationshipRegisterLine(targetLanguage, counterpart: counterpart)":
        "ConversationCharacter.relationshipRegisterLine(targetLanguage, counterpart)",
    "politeSettingLine(targetLanguage, counterpart: counterpart, inScene: inScene)":
        "ConversationCharacter.politeSettingLine(targetLanguage, counterpart, inScene)",
    "rewriteRules(level)": "CorrectionOnlyPrompt.rewriteRules(level)",
    "notesLanguageGuard(targetLanguage, nativeLanguage: nativeLanguage)":
        "LanguageLines.notesLanguageGuard(targetLanguage, nativeLanguage)",
})
realtime = kotlin_conv(literal_at(view, "private static let realtimeStyleRules = "), {})

# --- the text inside the hand-ported LOGIC blocks ---------------------------
LN = {"languageName": "languageName"}
pos = engine.index("private static func strangerPersonaBlock(")
stranger_guard = kotlin_conv(literal_at(engine, 'lines.append("""', pos), LN)
pos = engine.index("static func rememberedBlock(")
remembered_lead = kotlin_conv(literal_at(engine, 'var out = lead ?? """', pos), {})
p2 = engine.index("if !recent.isEmpty {", pos)
remembered_recent = kotlin_conv(literal_at(engine, 'out += """', p2),
                           {'recent.map(line).joined(separator: "\\n")': "recentLines"})
p3 = engine.index('out += """', p2) + 10
remembered_close = kotlin_conv(literal_at(engine, 'out += """', p3), LN)

pos = character.index("static func personaBlock(forCast")
cast_lead = kotlin_conv(literal_at(character, 'lead: """', pos), {})
pos = character.index("static func addressBlock(")
address = kotlin_conv(literal_at(character, 'return """', pos), {'lines.joined(separator: "\\n")': "lines"})
ADDR = {"addressBlock(c, targetLanguage: targetLanguage, languageName: languageName)": "addressBlock",
        "c.name": "name", **LN}
pos = character.index("private static func ownPersonBlock(")
tone_close = kotlin_conv(literal_at(character, '? """', pos), {})
tone_distant = kotlin_conv(literal_at(character, ': """', character.index('? """', pos) + 5), {})
own = kotlin_conv(literal_at(character, 'return """', pos),
             {**ADDR, "tone": "tone", 'facts.isEmpty ? "" : facts + "\\n"': '(if (facts.isEmpty()) "" else facts + "\\n")'})
pos = character.index("private static func strangerBlock(")
strangerb = kotlin_conv(literal_at(character, 'return """', pos), {
    **ADDR, 'facets.isEmpty ? "" : facets + "\\n"': '(if (facets.isEmpty()) "" else facets + "\\n")',
    "c.intro.isEmpty ? c.background : c.intro": "intro",
    "CommonGround.block(learner: persona, counterpart: c)": "commonGround",
    "metBefore": "metBefore"})
pos = character.index("private static func publicFigureBlock(")
public = kotlin_conv(literal_at(character, 'return """', pos), {**ADDR, "identity": "identity",
                                                                 "metBefore": "metBefore"})

pos = ground.index("static func block(")
ground_none = kotlin_conv(literal_at(ground, 'return """', pos), {})
ground_some = kotlin_conv(literal_at(ground, 'return """', ground.index('return """', pos) + 10),
                     {'shared.map { "- \\($0)" }.joined(separator: "\\n")': 'shared.joinToString("\\n") { "- $it" }'})
clock_block = kotlin_conv(literal_at(clocksrc, 'return """', clocksrc.index("func promptBlock(")),
                     {'lines.joined(separator: "\\n")': "lines"})


def band(xs):
    return (f"CefrLevel.A1, CefrLevel.A2 ->\n            {xs[0]}\n"
            f"        CefrLevel.B1, CefrLevel.B2 ->\n            {xs[1]}\n"
            f"        CefrLevel.C1, CefrLevel.C2 ->\n            {xs[2]}")


text = f'''package com.roro.futurevoice.talk

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.LanguageCatalog

// GENERATED by scripts/android/gen-conversation-prompt.py --ref {REF} — do not edit.
// Source: FutureVoice/Services/ConversationEngine.swift (conversationSystemPrompt's
// literals, speechScale, beginnerQuestions, tutorBlock, turnOutputInstruction) and
// FutureVoice/Views/ConversationView.swift (realtimeStyleRules), FutureVoice/Services/
// FutureGoal.swift (promptText).

/** The conversation prompt's text, byte for byte iOS's. Assembled by [ConversationEngine]. */
object ConversationPrompt {{
    /** iOS `ConversationEngine.maxTurnSentences`. */
    const val MAX_TURN_SENTENCES = {max_turn}

    /** iOS `speechScale(for:).vocabulary`. */
    fun speechVocabulary(level: CefrLevel): String = when (level) {{
        {band(vocab)}
    }}

    /** iOS `speechScale(for:).structure`. */
    fun speechStructure(level: CefrLevel): String = when (level) {{
        {band(struct_)}
    }}

    /** iOS `newsBlock` — "" when there are no facts. */
    fun newsBlock(newsFacts: List<String>): String =
        if (newsFacts.isEmpty()) "" else
            {news}

    /** iOS `firstMeetingBlock`, when it applies. */
    fun firstCallBlock(languageName: String, targetLanguage: String): String =
        {first}

    /**
     * iOS `ConversationEngine.FreeTalkCue`: what the fluent self brings when the
     * learner answers the free talk's hello with no subject of their own. Drawn
     * ONCE per call ([random]), never left to the model.
     */
    enum class FreeTalkCue {{
        NEWS, PLAIN_QUESTION, OWN_THING;

        val instruction: String get() = when (this) {{
            NEWS ->
                {cue["news"]}
            PLAIN_QUESTION ->
                {cue["plainQuestion"]}
            OWN_THING ->
                {cue["ownThing"]}
        }}

        companion object {{
            /** Half the calls ask about the news when there is some; the rest,
             *  and every call without news, split between the other two. */
            fun random(hasRecentNews: Boolean, rng: kotlin.random.Random = kotlin.random.Random.Default): FreeTalkCue {{
                if (hasRecentNews && rng.nextBoolean()) return NEWS
                return if (rng.nextBoolean()) PLAIN_QUESTION else OWN_THING
            }}
        }}
    }}

    /** iOS `futureBlock` (WHO YOU BECAME); [goalLines] are "- " + each
     *  goal's [futureGoalText], one per line. */
    fun futureBlock(goalLines: String): String =
        {future}

    /** iOS `FutureGoal.allCases`' ids, in order. */
    val FUTURE_GOAL_IDS: List<String> = listOf({goal_list})

    /** iOS `FutureGoal.promptText(languageName:)` by id — "" for an id this
     *  build doesn't know. */
    fun futureGoalText(id: String, languageName: String): String = when (id) {{
        {goal_when}
        else -> ""
    }}

    /** iOS `theyCalledBlock` — a plain free talk the LEARNER placed. */
    fun theyCalledBlock(freeTalkCue: FreeTalkCue, sameDay: Boolean = false): String =
        {they_called}

    /** iOS `earlierBlock` (98d7ff2a): what you and they did earlier today —
     *  a talk, a tutor lesson, a scene or a pronunciation drill. Free talk
     *  only; absent, every prompt from before is byte-identical. */
    fun earlierTodayBlock(record: String): String =
        {earlier}

    /** iOS `ownTopicBlock` — a "my own topic" call (topics page): the
     *  subject the learner names is the call. */
    val ownTopicBlock: String =
        {own_topic}

    /** iOS `beginnerQuestions` — empty at B1 and above. */
    fun beginnerQuestions(level: CefrLevel, targetLanguage: String = ""): String {{
        if (level != CefrLevel.A1 && level != CefrLevel.A2) return ""
        return {beginner}
    }}

    /** iOS `tutorBlock` (TutorMode): appended last when the call has it on.
     *  [lessonPart] and [tutorNow] are chosen by [TutorPrompt]. */
    fun tutorBlock(targetLanguage: String, languageName: String, lessonPart: String, tutorNow: String): String =
        {tutor}

    /** iOS `tutorBlock`'s lesson part while a lesson is being planned;
     *  [round] names the finished lesson for a next round, else "". */
    fun tutorLessonPlanning(round: String): String =
        {tutor_planning}

    /** iOS `tutorBlock`'s lesson part for the final check; [parts] are the
     *  numbered challenge tasks, one per line. */
    fun tutorLessonFinalCheck(titleTarget: String, parts: String): String =
        {tutor_check}

    /** iOS `tutorBlock`'s lesson part once the final check is passed. */
    fun tutorLessonDone(titleTarget: String): String =
        {tutor_done}

    /** iOS `tutorBlock`'s note on the last try's fixes — "" when none. */
    fun tutorLastFixes(lastFixes: List<String>): String =
        if (lastFixes.isEmpty()) "" else
            {tutor_fixes}

    /** iOS `tutorBlock`'s lesson part while a challenge is on. */
    fun tutorLessonOn(titleTarget: String, rows: String, now: Int, fixes: String): String =
        {tutor_now_part}

    /** iOS `tutorBlock`'s lesson part with no lesson yet. */
    const val TUTOR_NO_TOPIC =
        {tutor_none}

    /** iOS `tutorNow` when the last challenge was just ticked: the final check. */
    const val TUTOR_NOW_FINAL_CHECK =
        {tutor_now_check}

    /** iOS `tutorNow` when the lesson is finished. */
    const val TUTOR_NOW_FINISHED =
        {tutor_now_done}

    /** iOS `tutorNow` when challenge [now] (1-based) was just ticked. */
    fun tutorNowNext(now: Int, nextTask: String, nextExample: String): String =
        {tutor_now_next}

    /** iOS `conversationSystemPrompt`'s body, every computed piece passed in. */
    fun systemPrompt(
        languageName: String, nativeName: String, levelName: String, level: CefrLevel,
        personaBlock: String, counterpartBlock: String, firstMeetingBlock: String,
        theyCalledBlock: String, ownTopicBlock: String, clockBlock: String,
        earlierBlock: String = "",
        patterns: String, weak: String, topic: String, newsBlock: String, briefBlock: String,
        targetLanguage: String, tutor: Boolean, tutorBlock: String = "", futureBlock: String = "",
        /** The model IS the learner's future self (iOS `counterpart == nil && topic.isEmpty`). */
        asFutureSelf: Boolean,
    ): String =
        {system}

    /** iOS `turnOutputInstruction` — the JSON packaging for a buffered turn call. */
    fun turnOutputInstruction(targetLanguage: String, nativeLanguage: String,
                              counterpart: Counterpart?, inScene: Boolean,
                              level: CefrLevel = CefrLevel.B1): String {{
        val nativeName = LanguageCatalog.englishName(nativeLanguage)
        val targetName = LanguageCatalog.englishName(targetLanguage)
        return {output}
    }}

    // ---- Text inside the hand-ported logic blocks (ConversationEngine,
    // ConversationCharacter, CommonGround, PromptClock). Each takes the
    // pieces that logic computed.

    /** iOS `strangerPersonaBlock`: the guard under a stranger's shared lines. */
    fun strangerLinesGuard(languageName: String): String =
        {stranger_guard}

    /** iOS `rememberedBlock`'s default first line. */
    const val REMEMBERED_LEAD =
        {remembered_lead}

    /** iOS `rememberedBlock`'s recent-news part. */
    fun rememberedRecent(recentLines: String): String =
        {remembered_recent}

    /** iOS `rememberedBlock`'s closing rule + guard. */
    fun rememberedClose(languageName: String): String =
        {remembered_close}

    /** iOS `personaBlock(forCast:)`'s first line for someone close. */
    const val CLOSE_REMEMBERED_LEAD =
        {cast_lead}

    /** iOS `addressBlock`. */
    fun addressBlock(lines: String): String =
        {address}

    /** iOS `ownPersonBlock`'s two tones. */
    const val TONE_CLOSE =
        {tone_close}
    const val TONE_DISTANT =
        {tone_distant}

    /** iOS `ownPersonBlock`. */
    fun ownPersonBlock(name: String, facts: String, addressBlock: String, tone: String, languageName: String): String =
        {own}

    /** iOS `strangerBlock`. */
    fun strangerBlock(name: String, facets: String, intro: String, addressBlock: String,
                      commonGround: String, languageName: String,
                      metBefore: Boolean = false): String =
        {strangerb}

    /** iOS `publicFigureBlock`. */
    fun publicFigureBlock(identity: String, addressBlock: String, languageName: String,
                          metBefore: Boolean = false): String =
        {public}

    /** iOS `CommonGround.block` with nothing shared. */
    const val COMMON_GROUND_NONE =
        {ground_none}

    /** iOS `CommonGround.block` with something shared. */
    fun commonGround(shared: List<String>): String =
        {ground_some}

    /** iOS `PromptClock.promptBlock`'s text around its lines. */
    fun clockBlock(lines: String): String =
        {clock_block}

    /** iOS ConversationView `realtimeStyleRules`: what the realtime call appends. */
    const val REALTIME_STYLE_RULES =
        {realtime}
}}
'''
emit(OUT, text)
