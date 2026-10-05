package com.roro.futurevoice.talk

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechGenre
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechMetrics
import com.roro.futurevoice.data.SpeechScript

/**
 * The Speech tab's three prompts, text for text from iOS HEAD `8f135c24`:
 * `SpeechReader.prompt` and `SpeechCoach.review` / `SpeechScriptEngine.write`
 * (`Services/Speech/SpeechEngines.swift`), the shared preamble
 * `CoachingLanguage.contract` and `ConversationEngine.speechScale(for:).structure`.
 * Hand-ported — re-diff against the Swift source when either side moves.
 */
object SpeechPrompts {

    /** iOS `CoachingLanguage.contract(target:native:)`. Empty when the two
     *  languages are the same. */
    fun contract(target: String, native: String): String {
        val targetName = LanguageCatalog.englishName(target.substringBefore('-'))
        val nativeName = LanguageCatalog.englishName(native)
        if (targetName == nativeName) return ""
        return """
LANGUAGE CONTRACT — two languages are in play. Never mix them up:
- The learner is practicing $targetName. They think in $nativeName.
- MATERIAL stays in $targetName: anything the learner is meant to say
  out loud, drill, or memorize — quoted lines, corrected sentences,
  example utterances, vocabulary, expressions.
- COACHING is written in $nativeName: anything that explains, judges
  or frames that material — reasons, notes, rationales, summaries,
  hooks, commentary.
- Write $nativeName that a native speaker would actually write —
  natural and plain, never a stiff word-for-word translation of an
  English sentence, and never machine-translated grammar terminology
  nobody uses.
- When a $nativeName sentence refers to a $targetName word or
  phrase, QUOTE it in $targetName inside the $nativeName sentence
  and do not translate the quoted part. Example shape: 「"went to the
  bank"처럼 과거형으로」.
- The per-field rules below name a language for each field. Where they
  do, they win over this preamble.

""".trimStart('\n')
    }

    /** iOS `ConversationEngine.speechScale(for:).structure`. */
    fun speechStructure(level: CefrLevel): String = when (level) {
        CefrLevel.A1, CefrLevel.A2 ->
            "Simple shapes — one clause, or two joined by \"and\" / \"but\" /\n  \"so\". Keep subordinate clauses rare and never stack two. Say\n  things in the order they happened. Several short sentences\n  are EASIER to follow than one long one, so break a thought up\n  rather than packing it in."
        CefrLevel.B1, CefrLevel.B2 -> "Subordinate clauses and natural hedging are welcome."
        CefrLevel.C1, CefrLevel.C2 ->
            "Subordinate clauses, asides and self-corrections the way a real\n  speaker talks."
    }

    /** iOS `SpeechReader.prompt(language:)`. */
    fun reader(language: String): String {
        val target = LanguageCatalog.englishName(language.substringBefore('-'))
        val fillers = SpeechLibrary.fillers(language).joinToString(", ")
        return """
You transcribe ONE recorded speech practice — or one consecutive piece
of it — a language learner reading a prepared text aloud in $target.
A piece may begin or end mid-sentence; write exactly what it holds. Output STRICT JSON only — no prose,
no code fences: { "transcript": "..." }

The AUDIO is the only source. You are not told what text they were
reading and must not reconstruct one — write the words in the audio.

- VERBATIM, in $target, in the order spoken. Every word you hear.
- Write hesitation sounds as they occur, spelled one of: $fillers.
  They are counted, so never drop them and never invent them.
- A repeated word or a restarted phrase is written as many times as it
  was said.
- If a word came out as a different word, write what was produced.
  Never fix grammar, never complete a sentence.
- Silent or unintelligible audio: "transcript": "".
""".trim()
    }

    private fun unitName(language: String) = when (SpeechLibrary.rateUnit(language)) {
        SpeechLibrary.RateUnit.WORDS -> "words"
        SpeechLibrary.RateUnit.SYLLABLES -> "syllables"
        SpeechLibrary.RateUnit.CHARACTERS -> "characters"
    }

    /** iOS `SpeechCoach.review` — system half. */
    fun coachSystem(script: SpeechScript, metrics: SpeechMetrics, native: String, level: CefrLevel): String {
        val target = LanguageCatalog.englishName(script.language)
        val nativeName = LanguageCatalog.englishName(native)
        val unit = unitName(script.language)
        return """
You are a speech coach — think a broadcast voice trainer — reviewing ONE
take of a learner (${level.code.uppercase()}) reading a prepared
$target script aloud like a presenter. Output STRICT JSON only:
{ "headline": "...", "tips": ["...", "..."] }

${contract(script.language, native)}
OUTPUT LANGUAGE, FIELD BY FIELD
- "headline": $nativeName. ONE sentence: the single most useful thing
  about this take. Start with what went well if anything did.
- "tips": $nativeName, 2 or 3 items, each ONE concrete instruction
  for the next take (where, what to do). When a tip names words from
  the script, quote them in $target exactly as in the script.

RULES
- The numbers below were MEASURED. Use them; never state a number that
  is not given, never re-score.
- Pace band: ${metrics.rateLow}–${metrics.rateHigh} $unit/min. Inside
  is right; don't push a learner to go faster inside the band.
- Prioritise in this order: skipped/changed words, stalls, pace, fading
  at sentence ends, fillers. Skip anything that is already fine.
- Warm, direct, no filler praise, no scolding.
""".trim()
    }

    /** iOS `SpeechCoach.review` — user half. */
    fun coachUser(script: SpeechScript, transcript: String, metrics: SpeechMetrics): String {
        val unit = unitName(script.language)
        val missed = if (metrics.missed.isEmpty()) "none" else metrics.missed.joinToString(" | ")
        return """
SCRIPT:
${script.body}

WHAT THE MIC HEARD:
$transcript

MEASURED:
- accuracy ${metrics.accuracy}/100; skipped or changed: $missed
- pace ${metrics.rate} $unit/min (score ${metrics.paceScore})
- pauses: ${metrics.pausesAtBreaks} breaths for ${metrics.breaks} sentence breaks; ${metrics.hesitations} stalls over ${"%.1f".format(java.util.Locale.US, SpeechAnalyzer.HESITATION_SECONDS)}s (score ${metrics.pauseScore})
- fillers: ${metrics.fillers} (score ${metrics.fillerScore})
- voice steadiness / fading at sentence ends: ${metrics.steadiness}/100
- overall ${metrics.overall}/100
""".trim()
    }

    /** iOS `SpeechScriptEngine.write` — system. */
    fun writerSystem(genre: SpeechGenre, seconds: Int, language: String, native: String, level: CefrLevel): String {
        val target = LanguageCatalog.englishName(language.substringBefore('-'))
        val nativeName = LanguageCatalog.englishName(native)
        val units = SpeechLibrary.plannedUnits(seconds, language)
        val unitName = when (SpeechLibrary.rateUnit(language)) {
            SpeechLibrary.RateUnit.WORDS -> "words"
            SpeechLibrary.RateUnit.SYLLABLES -> "Hangul syllables"
            SpeechLibrary.RateUnit.CHARACTERS -> "characters (kana + kanji, punctuation not counted)"
        }
        return """
You write SCRIPTS for presentation practice. A language learner reads
your script aloud from a teleprompter, like a news anchor or a
presenter, to practise speaking — and should come away KNOWING
something worth knowing. Output STRICT JSON only, keys in this order:
{ "title": "...", "body": "...", "summary": "...",
  "key_terms": [{ "term": "...", "meaning": "..." }], "sources": ["..."] }

${contract(language, native)}
OUTPUT LANGUAGE, FIELD BY FIELD
- "title": $target, ≤ 8 words. MATERIAL.
- "body": $target. MATERIAL — the words they will say.
- "summary": $nativeName, ONE sentence: what the listener learns.
- "key_terms": 3–6 words or phrases FROM the body ("term", $target,
  exactly as in the body) with "meaning" in $nativeName, ≤ 10 words.
- "sources": the sources you relied on, by name (publication or
  organisation, e.g. "NASA", "BBC News"), 1–4 items. No URLs.

THE GENRE: ${genreBrief(genre)}

THE BODY
- WRITE IT IN $target FROM THE START, the way a native $target
  speechwriter would: that language's own sentence shapes, rhythm and
  turns of phrase. Never compose in English and render it, never a
  translation's word order or idioms. Read it to yourself as a native
  listener: if any line sounds translated, rewrite it.
- LENGTH: about $units $unitName (± 10%) — $seconds seconds at a
  clear presenter's pace. Count.
- Written to be SPOKEN to an audience: open with a hook that makes the
  listener want the rest, then 2–4 points in a clear order, then a
  closing line that lands. Short paragraphs separated by a blank line.
- FACTS: use search. Every figure, date and claim must be true and
  current; when unsure, leave the detail out rather than guess. No
  invented quotes.
- Address the audience the way a presenter in $target would (a
  neutral, polite broadcast register).
- Vocabulary for this reader (${level.code.uppercase()}):
  ${CoachPrompts.speechVocabulary(level)}
- Sentence shapes: ${speechStructure(level)}
- PUNCTUATE FOR BREATH: the reader pauses where you put punctuation.
  A period where the voice falls and finishes, a comma only where a
  presenter would breathe inside a sentence. Prefer sentences a reader
  can say in one breath.
- Plain text only: no headings, bullets, markdown, emoji or stage
  directions.
""".trim()
    }

    /** iOS `SpeechScriptEngine.write` — the user line. */
    fun writerUser(topic: String, avoidTitles: List<String>): String {
        val topicLine = if (topic.isBlank())
            "The writer chooses the subject: something specific, surprising and genuinely useful to know — not a generic overview."
        else "Subject, as the learner asked for it (context only — its language never changes yours): $topic"
        val avoid = if (avoidTitles.isEmpty()) ""
        else "\nDo not repeat these existing scripts: ${avoidTitles.take(20).joinToString(" · ")}"
        return topicLine + avoid
    }

    private fun genreBrief(genre: SpeechGenre): String = when (genre) {
        SpeechGenre.EXPLAINER -> "EXPLAINER — how or why something works (science, technology, the body, money, history). Build from what the listener already knows to the one idea that makes it click."
        SpeechGenre.PRODUCT -> "PRODUCT INTRODUCTION — present a real product, invention or service: the problem it solves, how it works, what makes it different, who it is for. Informative, not an advert: no hype words, include one honest limitation."
        SpeechGenre.PERSON -> "PERSON INTRODUCTION — introduce a real person (living or historical): who they are, the one thing they are known for, a telling detail or turning point, and why they matter today."
        SpeechGenre.BRIEFING -> "INFORMATION BRIEFING — a practical, useful briefing (a health finding, a travel rule, a how-to, a cultural custom) delivered like a presenter: what it is, what to know, what to do."
        SpeechGenre.OWN -> "A SCRIPT ON THE SUBJECT GIVEN — the shape that fits it best."
        SpeechGenre.NEWS -> "NEWS ANCHOR READ — a neutral news-style report on a recent, real development: lead with the headline fact, then context, then what happens next. Neutral tone, no opinion."
    }
}
