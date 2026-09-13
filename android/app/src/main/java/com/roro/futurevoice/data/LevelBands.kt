package com.roro.futurevoice.data

/**
 * Measured signals → CEFR bands, the four axes the level page draws as an
 * equalizer (iOS `ProgressTab`'s band tables). Deterministic: fixed
 * thresholds over real measurements, never an opinion — which is why the
 * labels carry "≈" and the AI verdict does not.
 */
object LevelBands {
    private class Band(val level: CefrLevel, val from: Double, val to: Double)

    /** Articulation pace. Native speakers run ~150+; wall-clock WPM reads
     *  ~20 lower (think-time and the turn wait included), so it is shifted up
     *  before banding rather than reading a level or two too low. */
    private val fluency = listOf(
        Band(CefrLevel.A1, 0.0, 60.0), Band(CefrLevel.A2, 60.0, 85.0), Band(CefrLevel.B1, 85.0, 105.0),
        Band(CefrLevel.B2, 105.0, 125.0), Band(CefrLevel.C1, 125.0, 145.0), Band(CefrLevel.C2, 145.0, 200.0))

    /** Words per turn — how far an idea gets developed. The WEAKEST proxy of
     *  the four (it measures length, not quality), so the thresholds sit
     *  deliberately high. */
    private val expression = listOf(
        Band(CefrLevel.A1, 0.0, 6.0), Band(CefrLevel.A2, 6.0, 10.0), Band(CefrLevel.B1, 10.0, 16.0),
        Band(CefrLevel.B2, 16.0, 24.0), Band(CefrLevel.C1, 24.0, 34.0), Band(CefrLevel.C2, 34.0, 60.0))

    /** Half-open lookup; a value past the table's end takes the LAST entry,
     *  so an off-scale measurement doesn't go unbanded. */
    private fun band(value: Double, specs: List<Band>): CefrLevel =
        specs.firstOrNull { value >= it.from && value < it.to }?.level ?: specs.last().level

    fun fluencyBand(wpm: Double, fromVoicedSpeech: Boolean): CefrLevel? {
        if (wpm <= 0) return null
        return band(if (fromVoicedSpeech) wpm else wpm + 20, fluency)
    }

    fun expressionBand(wordsPerTurn: Double): CefrLevel? =
        if (wordsPerTurn <= 0) null else band(wordsPerTurn, expression)

    /** The 0–100 grammar score as a band. Android has no verified-slip
     *  density yet, so this is iOS's fallback branch, not its primary one. */
    fun grammarBand(score: Int): CefrLevel? = when {
        score <= 0 -> null
        score < 40 -> CefrLevel.A1
        score < 55 -> CefrLevel.A2
        score < 70 -> CefrLevel.B1
        score < 82 -> CefrLevel.B2
        score < 92 -> CefrLevel.C1
        else -> CefrLevel.C2
    }

    /**
     * Vocabulary: the highest band where enough DISTINCT words have actually
     * been produced. The bar rises with the level — six A2 words are decent
     * evidence, six lucky C1 words (one song, one topic) are not — and a
     * baseline of 15 graded words is needed before any level is claimed.
     */
    fun vocabularyLevel(countsByLevel: Map<CefrLevel, Int>): CefrLevel? {
        val total = countsByLevel.values.sum()
        if (total < 15) return null
        var estimate: CefrLevel? = null
        for (lv in CefrLevel.entries) {
            val need = when (lv) {
                CefrLevel.A1, CefrLevel.A2 -> 6
                CefrLevel.B1 -> 8
                CefrLevel.B2 -> 10
                CefrLevel.C1 -> 12
                CefrLevel.C2 -> 15
            }
            if ((countsByLevel[lv] ?: 0) >= need) estimate = lv
        }
        return estimate ?: CefrLevel.A1
    }
}
