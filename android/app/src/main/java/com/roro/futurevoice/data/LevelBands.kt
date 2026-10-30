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

    /** The learner's own voiced seconds a fluency band needs (3 min). */
    const val MIN_FLUENCY_SPEAKING_SECONDS = 180.0

    /**
     * Pace → band, with iOS's two guards (2026-10-14: a B1 learner read ≈C2
     * after a few plain calls of short answers). Under three minutes of the
     * learner's own voice there is no band; and pace alone rewards short
     * answers, so turn length caps it at one band above the ≈Expression band
     * — the way range caps grammar. Returns the band and, when the cap
     * decided it, the cap.
     */
    fun fluencyRead(wpm: Double, fromVoicedSpeech: Boolean,
                    speakingSeconds: Double, wordsPerTurn: Double): Pair<CefrLevel, CefrLevel?>? {
        if (wpm <= 0 || speakingSeconds < MIN_FLUENCY_SPEAKING_SECONDS) return null
        val byPace = band(if (fromVoicedSpeech) wpm else wpm + 20, fluency)
        if (wordsPerTurn <= 0) return byPace to null
        val all = CefrLevel.entries
        val cap = all[minOf(all.indexOf(band(wordsPerTurn, expression)) + 1, all.size - 1)]
        return if (all.indexOf(cap) < all.indexOf(byPace)) cap to cap else byPace to null
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
     * Vocabulary as WHICH words, not how many (iOS `VocabSophistication`):
     * the share of graded word TOKENS at B2+ in the newest talks, cut at the
     * NICT JLE medians (1,277 learners of English in the same SST interview
     * + 20 natives). The old count below rose with talk alone — six pooled
     * ≈A2 interviews read B2. Above B2 the share stops separating levels, so
     * C1/C2 also need the assessment's precision read, else the band stops
     * at B2. English only; other languages keep [vocabularyLevel].
     */
    object VocabShare {
        const val MIN_GRADED_TOKENS = 400
        const val WINDOW_GRADED_TOKENS = 1500
        private val cuts = listOf(CefrLevel.C2 to 7.0, CefrLevel.C1 to 6.0, CefrLevel.B2 to 5.0,
            CefrLevel.B1 to 4.1, CefrLevel.A2 to 2.6, CefrLevel.A1 to 0.0)

        fun isCalibrated(language: String) = language == "en"

        data class Read(val graded: Int, val advanced: Int, val talks: Int) {
            val share: Double get() = if (graded > 0) advanced.toDouble() / graded * 100 else 0.0
        }

        /** What held the band: no precision read yet (null), or that read. */
        data class Ceiling(val precision: CefrLevel?)

        fun level(read: Read, precision: CefrLevel?): Pair<CefrLevel, Ceiling?>? {
            if (read.graded < MIN_GRADED_TOKENS) return null
            val all = CefrLevel.entries
            val byShare = cuts.first { read.share >= it.second }.first
            if (all.indexOf(byShare) <= all.indexOf(CefrLevel.B2)) return byShare to null
            if (precision == null) return CefrLevel.B2 to Ceiling(null)
            val capped = if (all.indexOf(precision) < all.indexOf(byShare))
                (if (all.indexOf(precision) > all.indexOf(CefrLevel.B2)) precision else CefrLevel.B2)
            else byShare
            return if (capped == byShare) byShare to null else capped to Ceiling(precision)
        }

        /** Talks NEWEST FIRST, each the learner's evidence lines, until
         *  [WINDOW_GRADED_TOKENS]. Repeats count — a token share is what was
         *  calibrated. */
        fun read(talksNewestFirst: List<List<String>>, gradeOf: (String) -> CefrLevel?): Read {
            var graded = 0; var advanced = 0; var talks = 0
            for (texts in talksNewestFirst) {
                if (graded >= WINDOW_GRADED_TOKENS) break
                val before = graded
                for (text in texts) for (token in text.split(Regex("[^\\p{L}\\p{N}]+"))) {
                    if (token.length <= 1) continue
                    val lv = gradeOf(token.lowercase()) ?: continue
                    graded++
                    if (lv.ordinal >= CefrLevel.B2.ordinal) advanced++
                }
                if (graded > before) talks++
            }
            return Read(graded, advanced, talks)
        }
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
