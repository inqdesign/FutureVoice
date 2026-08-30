package com.roro.futurevoice.talk

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.Locale

/**
 * Deterministic metrics computed from a session's turns — port of
 * `ScorecardMetrics.swift`, field for field. Passed as evidence into the
 * summary prompt so the model grounds its 0–100 scores in real numbers.
 * Side-effect-free; a number that differs from iOS on the same turns is a
 * bug on whichever side is newer (`android-launch-roadmap.md` §0.3).
 *
 * Known gap: `distinct_words_by_cefr_level` is EMPTY until the core word list
 * (`cefr_words*.tsv`) is bundled — the prompt then leans on the other
 * evidence, exactly as iOS does for a language with no list.
 */
data class ScorecardMetrics(
    val userTurnCount: Int,
    val userWordCount: Int,
    val uniqueWordCount: Int,
    val typeTokenRatio: Double,
    val avgWordsPerUserTurn: Double,
    val totalUserSpeakingSeconds: Double,
    val wordsPerMinute: Double,
    val suggestionCount: Int,
    val suggestionRate: Double,
    val selfCorrectionHits: Int,
    val pausesPerMinute: Double,
    val pauseRatio: Double,
    val articulationRate: Double,
    val vocabLevelCounts: Map<String, Int>,
) {
    /** Compact JSON for the prompt — same keys and rounding as `promptJSON()`. */
    fun promptJson(): JsonObject = buildJsonObject {
        put("user_turn_count", userTurnCount)
        put("user_word_count", userWordCount)
        put("unique_word_count", uniqueWordCount)
        put("type_token_ratio", fmt(typeTokenRatio, 2))
        put("avg_words_per_turn", fmt(avgWordsPerUserTurn, 1))
        put("total_user_speaking_seconds", Math.round(totalUserSpeakingSeconds).toInt())
        put("words_per_minute", Math.round(wordsPerMinute).toInt())
        put("suggestion_count", suggestionCount)
        put("suggestion_rate", fmt(suggestionRate, 2))
        put("self_correction_hits", selfCorrectionHits)
        put("articulation_rate_wpm", Math.round(articulationRate).toInt())
        put("pauses_per_minute", fmt(pausesPerMinute, 1))
        put("pause_ratio", fmt(pauseRatio, 2))
        put("distinct_words_by_cefr_level", JsonObject(vocabLevelCounts.mapValues { JsonPrimitive(it.value) }))
    }

    companion object {
        fun compute(turns: List<Turn>): ScorecardMetrics {
            val userTurns = turns.filter { it.role == TurnRole.USER && !it.excludedFromScoring }
            val allWords = userTurns.flatMap { tokens(it.transcript) }
            val userWordCount = allWords.size
            val uniqueWords = allWords.map { it.lowercase() }.toSet()
            val ttr = if (userWordCount > 0) uniqueWords.size.toDouble() / userWordCount else 0.0
            val avgWords = if (userTurns.isEmpty()) 0.0 else userWordCount.toDouble() / userTurns.size
            val secondsSpoken = userTurns.sumOf { it.durationMs / 1000.0 }
            val wpm = if (secondsSpoken > 0) (userWordCount / secondsSpoken) * 60.0 else 0.0
            val suggestionCount = userTurns.count { it.suggestion != null }
            val suggestionRate = if (userTurns.isEmpty()) 0.0 else suggestionCount.toDouble() / userTurns.size
            val selfCorrections = userTurns.sumOf { selfCorrectionMatches(it.transcript) }

            val fl = userTurns.mapNotNull { it.fluency }
            val voiced = fl.sumOf { it.speakingSeconds }
            val span = fl.sumOf { it.totalSeconds }
            val pauses = fl.sumOf { it.pauseCount }
            val pauseSecs = fl.sumOf { it.pauseSeconds }
            val pausesPerMin = if (voiced > 0) pauses / (voiced / 60.0) else 0.0
            val pauseRatio = if (span > 0) pauseSecs / span else 0.0
            val articulation = if (voiced > 0) userWordCount / (voiced / 60.0) else 0.0

            return ScorecardMetrics(
                userTurnCount = userTurns.size,
                userWordCount = userWordCount,
                uniqueWordCount = uniqueWords.size,
                typeTokenRatio = ttr,
                avgWordsPerUserTurn = avgWords,
                totalUserSpeakingSeconds = secondsSpoken,
                wordsPerMinute = wpm,
                suggestionCount = suggestionCount,
                suggestionRate = suggestionRate,
                selfCorrectionHits = selfCorrections,
                pausesPerMinute = pausesPerMin,
                pauseRatio = pauseRatio,
                articulationRate = articulation,
                vocabLevelCounts = emptyMap(),
            )
        }

        /** Swift: split on `CharacterSet.alphanumerics.inverted`. */
        private fun tokens(text: String): List<String> =
            text.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }

        private val selfCorrectionPatterns = listOf(
            "I mean", "i mean", "uh ", " uh,", " um ", " um,", "you know,", "like,", "wait,",
        )

        private fun selfCorrectionMatches(text: String): Int =
            selfCorrectionPatterns.sumOf { needle -> text.split(needle).size - 1 }

        private fun fmt(v: Double, places: Int) = String.format(Locale.US, "%.${places}f", v)
    }
}
