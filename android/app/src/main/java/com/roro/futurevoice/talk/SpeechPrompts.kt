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
    fun coachSystem(script: SpeechScript, metrics: SpeechMetrics, native: String, level: CefrLevel): String =
        LiftedPrompts.speechCoachSystem(level.code.uppercase(), LanguageCatalog.englishName(script.language),
            contract(script.language, native), LanguageCatalog.englishName(native),
            metrics.rateLow, metrics.rateHigh, unitName(script.language))

    /** iOS `SpeechCoach.review` — user half. */
    fun coachUser(script: SpeechScript, transcript: String, metrics: SpeechMetrics): String =
        LiftedPrompts.speechCoachUser(
            body = script.body, transcript = transcript, accuracy = metrics.accuracy,
            missed = if (metrics.missed.isEmpty()) "none" else metrics.missed.joinToString(" | "),
            rate = metrics.rate, unit = unitName(script.language), paceScore = metrics.paceScore,
            pausesAtBreaks = metrics.pausesAtBreaks, breaks = metrics.breaks, hesitations = metrics.hesitations,
            hesitationSeconds = "%.1f".format(java.util.Locale.US, SpeechAnalyzer.HESITATION_SECONDS),
            pauseScore = metrics.pauseScore, fillers = metrics.fillers, fillerScore = metrics.fillerScore,
            steadiness = metrics.steadiness, overall = metrics.overall)

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
