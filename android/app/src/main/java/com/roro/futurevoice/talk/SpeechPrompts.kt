package com.roro.futurevoice.talk

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechGenre
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechMetrics
import com.roro.futurevoice.data.SpeechScript

/**
 * The Speech tab's three prompts (`Services/Speech/SpeechEngines.swift`):
 * the TEXT is lifted from iOS into [LiftedPrompts] by
 * scripts/android/gen-lifted-prompts.py; what is here is the code that fills
 * it.
 */
object SpeechPrompts {

    /** iOS `CoachingLanguage.contract(target:native:)`. Empty when the two
     *  languages are the same. */
    fun contract(target: String, native: String): String {
        val targetName = LanguageCatalog.englishName(target.substringBefore('-'))
        val nativeName = LanguageCatalog.englishName(native)
        if (targetName == nativeName) return ""
        return LiftedPrompts.contract(targetName, nativeName)
    }

    /** iOS `SpeechReader.prompt(language:)`. */
    fun reader(language: String): String =
        LiftedPrompts.speechReader(LanguageCatalog.englishName(language.substringBefore('-')),
            SpeechLibrary.fillers(language).joinToString(", "))

    private fun unitName(language: String) = when (SpeechLibrary.rateUnit(language)) {
        SpeechLibrary.RateUnit.WORDS -> "words"
        SpeechLibrary.RateUnit.SYLLABLES -> "syllables"
        SpeechLibrary.RateUnit.CHARACTERS -> "characters"
    }

    /** iOS `SpeechCoach.review` — system half. */
    fun coachSystem(script: SpeechScript, metrics: SpeechMetrics, native: String, level: CefrLevel): String {
        val lifted = LiftedPrompts.speechCoachSystem(level.code.uppercase(), LanguageCatalog.englishName(script.language),
            contract(script.language, native), LanguageCatalog.englishName(native),
            metrics.rateLow, metrics.rateHigh, unitName(script.language))
        if (metrics.reading == null) return lifted
        // A Season 2 take: iOS swaps only the rules for the five parts. The
        // lifted text is cut where its own rules start and end, so everything
        // around them stays the one lifted copy.
        return lifted.substringBefore("- Pace band:") + READING_RULES + "\n- Warm, direct," +
            lifted.substringAfter("- Warm, direct,")
    }

    /** iOS `SpeechCoach.review` — user half. */
    fun coachUser(script: SpeechScript, transcript: String, metrics: SpeechMetrics): String {
        val lifted = LiftedPrompts.speechCoachUser(
            body = script.body, transcript = transcript, accuracy = metrics.accuracy,
            missed = if (metrics.missed.isEmpty()) "none" else metrics.missed.joinToString(" | "),
            rate = metrics.rate, unit = unitName(script.language), paceScore = metrics.paceScore,
            pausesAtBreaks = metrics.pausesAtBreaks, breaks = metrics.breaks, hesitations = metrics.hesitations,
            hesitationSeconds = "%.1f".format(java.util.Locale.US, SpeechAnalyzer.HESITATION_SECONDS),
            pauseScore = metrics.pauseScore, fillers = metrics.fillers, fillerScore = metrics.fillerScore,
            steadiness = metrics.steadiness, overall = metrics.overall)
        val r = metrics.reading ?: return lifted
        return lifted.substringBefore("MEASURED:\n") + "MEASURED:\n" + readingMeasured(r, metrics.overall)
    }

    private val READING_RULES = """
        - The take was compared word by word with a native reading of the
          same script. Five parts, the score is their average; 100 only
          when every part is 100. Native speakers reading average
          ${SpeechReading.NATIVE_AVERAGE}. The headline and the first tip are
          about THE PART TO WORK ON NEXT, using its details (the words held
          too long, where the reader stopped, the numbers). Then the next
          weakest part. Skip parts at 95 or more. Intonation is not
          measured: say nothing about it.
    """.trimIndent()

    private fun readingMeasured(r: SpeechReadingScore, overall: Int): String {
        val slower = "%.0f".format(java.util.Locale.US, (1 / maxOf(r.speed, 0.01) - 1) * 100)
        val held = if (r.held.isEmpty()) "none" else r.held.joinToString(", ") { "\"${it.word}\" ${it.times}x" }
        val pauses = if (r.extraPauses.isEmpty()) "none" else r.extraPauses.joinToString(", ") { "\"${it.after}\" ${it.seconds}s" }
        val missed = if (r.missed.isEmpty()) "none" else r.missed.joinToString(" | ")
        val focus = r.focus?.raw ?: "none: every part is at a narrator's level"
        return listOf(
            "- overall $overall/100",
            "- speed ${r.parts.speed}/100: the reader took $slower% longer to say the words than the native reading",
            "- rhythm ${r.parts.rhythm}/100; words held far longer than the native reading holds them: $held",
            "- pauses ${r.parts.pauses}/100; stopped where the native reading doesn't, after: $pauses",
            "- accuracy ${r.parts.accuracy}/100; words read differently: ${r.slips}; first ones: $missed",
            "- pronunciation ${r.parts.pronunciation}/100 (only clearly wrong sounds count)",
            "- the part to work on next: $focus",
        ).joinToString("\n")
    }

    /** iOS `SpeechScriptEngine.write` — system. */
    fun writerSystem(genre: SpeechGenre, seconds: Int, language: String, native: String, level: CefrLevel): String {
        val unitName = when (SpeechLibrary.rateUnit(language)) {
            SpeechLibrary.RateUnit.WORDS -> "words"
            SpeechLibrary.RateUnit.SYLLABLES -> "Hangul syllables"
            SpeechLibrary.RateUnit.CHARACTERS -> "characters (kana + kanji, punctuation not counted)"
        }
        return LiftedPrompts.speechWriterSystem(
            target = LanguageCatalog.englishName(language.substringBefore('-')), nativeName = LanguageCatalog.englishName(native),
            contract = contract(language, native), genreBrief = genreBrief(genre),
            units = SpeechLibrary.plannedUnits(seconds, language), unitName = unitName, seconds = seconds,
            level = level.code.uppercase(), vocabulary = ConversationPrompt.speechVocabulary(level),
            structure = ConversationPrompt.speechStructure(level))
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

    private fun genreBrief(genre: SpeechGenre): String = LiftedPrompts.speechGenreBrief(genre.raw)
}
