package com.roro.futurevoice.talk

import com.roro.futurevoice.data.LanguageCatalog
import kotlin.math.sqrt

/**
 * Deterministic shadow scoring — port of `ShadowEngine`'s scoring half
 * (`analyze` / `expandForDiff` / `tokenize` / `align`), verified against
 * golden vectors. The LLM never invents a number here; feedback prose is a
 * separate (server) call.
 *
 * Number spell-out is injectable: Android runtime uses ICU
 * (`RuleBasedNumberFormat`), the JVM tests a small English speller — both
 * must produce NumberFormatter-spellOut-shaped output ("twenty-one").
 */
object ShadowScore {

    enum class DiffOp { MATCH, SUB, INS, DEL }
    data class DiffStep(val op: DiffOp, val target: String?, val learner: String?)
    data class Analysis(
        val score: Int,
        val steps: List<DiffStep>,
        val targetTokenCount: Int,
        val learnerTokenCount: Int,
        val matchCount: Int,
    )

    /** en spell-out for the JVM tests; Android swaps in ICU at app start. */
    var spellOut: (Int, String) -> String? = { n, language ->
        if (language.startsWith("en")) englishSpellOut(n) else null
    }

    fun analyze(target: String, learner: String, language: String = "en"): Analysis {
        val style = LanguageCatalog.tokenStyle(language)
        val targetTokens = tokenize(expandForDiff(target, language), style)
        val learnerTokens = tokenize(expandForDiff(learner, language), style)
        // Japanese compares by SOUND: the transcriber picks the script
        // (ナワナ / なわな / nawana are the same three morae), so a token is
        // keyed in hiragana — the steps still carry what each side wrote.
        // Without this the app's own name scored as a miss on every take.
        val key: (String) -> String =
            if (language.startsWith("ja")) com.roro.futurevoice.data.JapaneseMorph::soundSpelling
            else { t -> t }
        val (matches, steps) = align(targetTokens, learnerTokens, key)
        val denom = maxOf(targetTokens.size, learnerTokens.size)
        val raw = if (denom > 0) matches.toDouble() / denom else 0.0
        // sqrt curve: single-word slips don't crater a good attempt.
        val score = (sqrt(raw) * 100).let { Math.round(it) }.toInt().coerceIn(0, 100)
        return Analysis(score, steps, targetTokens.size, learnerTokens.size, matches)
    }

    /** Ops in TARGET order (`ins` skipped) — indexes align with [tokenSpans]. */
    fun targetOps(steps: List<DiffStep>): List<DiffOp> =
        steps.filter { it.op != DiffOp.INS }.map { it.op }

    /** Which diff tokens each SPOKEN word occupies (see ShadowEngine.tokenSpans). */
    fun tokenSpans(words: List<String>, language: String = "en"): List<IntRange> {
        val style = LanguageCatalog.tokenStyle(language)
        var cursor = 0
        return words.map { word ->
            val count = tokenize(expandForDiff(word, language), style).size
            val range = cursor until (cursor + count)
            cursor += count
            range
        }
    }

    // ── Rhythm (deterministic) — port of `ShadowEngine.analyzeRhythm` ──

    /**
     * One target word the learner also said (diff `match` or `sub`), with its
     * onset in both timelines. [deviationMs] is how far off the beat the
     * learner's onset was AFTER pace normalization — positive = late.
     */
    data class RhythmWord(
        val word: String,
        /** Index of the word in the practiced target range (0-based). */
        val targetIndex: Int,
        val targetOnsetMs: Int,
        val learnerOnsetMs: Int,
        val targetDurationMs: Int,
        val learnerDurationMs: Int,
        /** Both onsets were observed. False = drawn nowhere, never graded. */
        val isMeasured: Boolean,
    ) {
        val deviationMs: Int get() = learnerOnsetMs - targetOnsetMs
    }

    data class RhythmAnalysis(val score: Int, val words: List<RhythmWord>, val targetSpanMs: Int)

    /** Words lead — a take with the wrong words is wrong however well timed —
     *  but not by so much that the beat is decoration. */
    const val MATCH_WEIGHT = 0.65
    const val RHYTHM_WEIGHT = 0.35

    /**
     * The ONE number a take is judged by — result card, history, mastery,
     * retry picks. Rhythm counts only when it was MEASURED: null is not zero,
     * and grading a learner on a measurement the app failed to take is worse
     * than not grading it.
     */
    fun overallScore(match: Int, rhythm: Int?): Int {
        if (rhythm == null) return match
        val blended = match * MATCH_WEIGHT + rhythm * RHYTHM_WEIGHT
        return Math.round(blended).toInt().coerceIn(0, 100)
    }

    private const val RHYTHM_GRACE_MS = 60.0
    private const val RHYTHM_RAMP_MS = 400.0

    /** Per-word grade shared with the dots: 2 on beat (≤120 ms), 1 slightly
     *  off (≤300 ms), 0 off. */
    fun rhythmGrade(deviationMs: Int): Int = when (kotlin.math.abs(deviationMs)) {
        in 0..120 -> 2
        in 121..300 -> 1
        else -> 0
    }

    /** Fewest measured pairs a rhythm score may stand on. The first and last
     *  pin the normalization and score 1.0 whatever happened. */
    const val MIN_MEASURED_PAIRS = 4

    /**
     * Pair the diff's matched slots with both timelines, folding tokens back
     * onto WORDS through [tokenSpans]; only a pair observed on BOTH sides
     * counts, and the normalization is pinned on the first and last measured
     * pairs. Null whenever the streams don't account for each other exactly,
     * or fewer than [MIN_MEASURED_PAIRS] measured pairs exist.
     */
    fun analyzeRhythm(
        steps: List<DiffStep>,
        targetTimings: List<WordTiming>,
        learnerTimings: List<WordTiming>,
        language: String = "en",
    ): RhythmAnalysis? {
        fun wordOfToken(words: List<String>): List<Int> =
            tokenSpans(words, language).flatMapIndexed { i, span -> List(span.count()) { i } }
        val targetWordOf = wordOfToken(targetTimings.map { it.word })
        val learnerWordOf = wordOfToken(learnerTimings.map { it.word })

        data class Pair3(val targetIndex: Int, val target: WordTiming, val learner: WordTiming)
        val pairs = mutableListOf<Pair3>()
        val pairedTargets = HashSet<Int>(); val pairedLearners = HashSet<Int>()
        var t = 0; var l = 0
        for (step in steps) {
            when (step.op) {
                DiffOp.MATCH, DiffOp.SUB -> {
                    if (t >= targetWordOf.size || l >= learnerWordOf.size) return null
                    val tw = targetWordOf[t]; val lw = learnerWordOf[l]
                    if (tw !in pairedTargets && lw !in pairedLearners) {
                        pairs += Pair3(tw, targetTimings[tw], learnerTimings[lw])
                        pairedTargets += tw; pairedLearners += lw
                    }
                    t += 1; l += 1
                }
                DiffOp.DEL -> { if (t >= targetWordOf.size) return null; t += 1 }
                DiffOp.INS -> { if (l >= learnerWordOf.size) return null; l += 1 }
            }
        }
        if (t != targetWordOf.size || l != learnerWordOf.size) return null

        val measured = pairs.filter { it.target.isMeasured && it.learner.isMeasured }
        if (measured.size < MIN_MEASURED_PAIRS) return null
        val first = measured.first(); val last = measured.last()
        val t0 = first.target.startMs; val l0 = first.learner.startMs
        val targetSpan = last.target.startMs - t0
        val learnerSpan = last.learner.startMs - l0
        if (targetSpan <= 0 || learnerSpan <= 0) return null
        val scale = targetSpan.toDouble() / learnerSpan

        val words = pairs.map { p ->
            RhythmWord(
                word = p.target.word,
                targetIndex = p.targetIndex,
                targetOnsetMs = p.target.startMs - t0,
                learnerOnsetMs = Math.round((p.learner.startMs - l0) * scale).toInt(),
                targetDurationMs = maxOf(0, p.target.endMs - p.target.startMs),
                learnerDurationMs = maxOf(0, Math.round((p.learner.endMs - p.learner.startMs) * scale).toInt()),
                isMeasured = p.target.isMeasured && p.learner.isMeasured,
            )
        }
        val credits = words.filter { it.isMeasured }.map { w ->
            val over = maxOf(0.0, kotlin.math.abs(w.deviationMs) - RHYTHM_GRACE_MS)
            maxOf(0.0, 1 - over / RHYTHM_RAMP_MS)
        }
        val mean = credits.sum() / credits.size
        val score = Math.round(mean * 100).toInt().coerceIn(0, 100)
        val spanEnd = pairs.maxOfOrNull { it.target.endMs - t0 } ?: targetSpan
        return RhythmAnalysis(score, words, maxOf(spanEnd, targetSpan))
    }

    /**
     * The (target word, learner word) pairs the diff matched or substituted,
     * folded from tokens onto words the way [analyzeRhythm] folds them —
     * each word paired at most once. Null when the streams don't account for
     * each other.
     */
    fun wordPairs(
        steps: List<DiffStep>, targetWords: List<String>, learnerWords: List<String>, language: String,
    ): List<Pair<Int, Int>>? {
        fun wordOfToken(words: List<String>): List<Int> =
            tokenSpans(words, language).flatMapIndexed { i, span -> List(span.count()) { i } }
        val tOf = wordOfToken(targetWords); val lOf = wordOfToken(learnerWords)
        val out = mutableListOf<Pair<Int, Int>>()
        val seenT = HashSet<Int>(); val seenL = HashSet<Int>()
        var t = 0; var l = 0
        for (step in steps) {
            when (step.op) {
                DiffOp.MATCH, DiffOp.SUB -> {
                    if (t >= tOf.size || l >= lOf.size) return null
                    if (tOf[t] !in seenT && lOf[l] !in seenL) {
                        out += tOf[t] to lOf[l]; seenT += tOf[t]; seenL += lOf[l]
                    }
                    t += 1; l += 1
                }
                DiffOp.DEL -> { if (t >= tOf.size) return null; t += 1 }
                DiffOp.INS -> { if (l >= lOf.size) return null; l += 1 }
            }
        }
        if (t != tOf.size || l != lOf.size) return null
        return out
    }

    /** Off-beat measured words for the coach prompt, `[weather +180ms]`. */
    fun renderRhythmForPrompt(rhythm: RhythmAnalysis?): String {
        if (rhythm == null) return "n/a"
        val off = rhythm.words.filter { it.isMeasured && rhythmGrade(it.deviationMs) < 2 }
        if (off.isEmpty()) return "all words on beat"
        return off.joinToString(" ") { w ->
            "[${w.word} ${if (w.deviationMs >= 0) "+" else ""}${w.deviationMs}ms]"
        }
    }

    /** `[= the] [~ today/to-day] [- is] [+ uh]`. */
    fun renderDiffForPrompt(steps: List<DiffStep>): String = steps.joinToString(" ") { s ->
        when (s.op) {
            DiffOp.MATCH -> "[= ${s.target.orEmpty()}]"
            DiffOp.SUB -> "[~ ${s.target.orEmpty()}/${s.learner.orEmpty()}]"
            DiffOp.DEL -> "[- ${s.target.orEmpty()}]"
            DiffOp.INS -> "[+ ${s.learner.orEmpty()}]"
        }
    }

    private val IRREGULAR = listOf(
        "won't" to "will not", "can't" to "can not", "cannot" to "can not",
        "shan't" to "shall not", "let's" to "let us", "y'all" to "you all",
        "wanna" to "want to", "gonna" to "going to", "gotta" to "got to",
        "lemme" to "let me", "gimme" to "give me", "kinda" to "kind of",
        "sorta" to "sort of", "outta" to "out of", "dunno" to "do not know",
        "'cause" to "because", "cuz" to "because",
    )
    private val SUFFIXES = listOf(
        "n't" to " not", "'re" to " are", "'m" to " am", "'ve" to " have",
        "'ll" to " will", "'d" to " would", "'s" to " is",
    )

    fun expandForDiff(text: String, language: String): String {
        // A model-written target says "I’m" and the recognizer writes "I'm";
        // that is a choice no mouth makes, so folding the typographic forms
        // keeps a perfectly-said word from scoring as a substitution
        // (iOS `17d0b56`).
        var out = text.lowercase()
            .replace('\u2019', '\'').replace('\u2018', '\'').replace('\u02BC', '\'')
            .replace("-", " ")
        out = Regex("\\d+").replace(out) { m ->
            val n = m.value.toIntOrNull() ?: return@replace m.value
            val spelled = spellOut(n, language) ?: return@replace m.value
            " " + spelled.lowercase().replace("-", " ") + " "
        }
        // A romaji word in a Japanese line (nawana) is six letters on one side
        // and three kana on the other — the recognizer writes it ナワナ. Cut
        // into kana on both sides so the morae line up.
        if (language.startsWith("ja")) {
            return com.roro.futurevoice.data.JapaneseMorph.katakanaFromLatinIn(out)
        }
        if (!language.startsWith("en")) return out
        for ((from, to) in IRREGULAR) {
            out = Regex("(?<![a-z])${Regex.escape(from)}(?![a-z])").replace(out, to)
        }
        for ((suffix, expansion) in SUFFIXES) {
            out = Regex("(?<=[a-z])${Regex.escape(suffix)}\\b").replace(out, expansion)
        }
        return out
    }

    private fun tokenize(text: String, style: LanguageCatalog.TokenStyle): List<String> {
        val words = text.lowercase()
            .split(Regex("[^\\p{L}\\p{N}'-]+"))
            .filter { it.isNotEmpty() }
        return when (style) {
            LanguageCatalog.TokenStyle.WORD -> words
            LanguageCatalog.TokenStyle.SYLLABLE -> words.flatMap { w -> w.map { it.toString() } }
        }
    }

    private fun align(a: List<String>, b: List<String>,
                      key: (String) -> String = { it }): Pair<Int, List<DiffStep>> {
        val n = a.size; val m = b.size
        if (n == 0 && m == 0) return 0 to emptyList()
        val ka = a.map(key); val kb = b.map(key)
        fun same(i: Int, j: Int) = ka[i - 1] == kb[j - 1]
        val dp = Array(n + 1) { IntArray(m + 1) }
        for (i in 0..n) dp[i][0] = i
        for (j in 0..m) dp[0][j] = j
        for (i in 1..n) for (j in 1..m) {
            dp[i][j] = if (same(i, j)) dp[i - 1][j - 1]
            else 1 + minOf(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1])
        }
        val steps = mutableListOf<DiffStep>()
        var matches = 0
        var i = n; var j = m
        while (i > 0 || j > 0) {
            when {
                i > 0 && j > 0 && same(i, j) -> {
                    steps.add(DiffStep(DiffOp.MATCH, a[i - 1], b[j - 1])); matches += 1; i -= 1; j -= 1
                }
                i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + 1 -> {
                    steps.add(DiffStep(DiffOp.SUB, a[i - 1], b[j - 1])); i -= 1; j -= 1
                }
                i > 0 && (j == 0 || dp[i][j] == dp[i - 1][j] + 1) -> {
                    steps.add(DiffStep(DiffOp.DEL, a[i - 1], null)); i -= 1
                }
                else -> { steps.add(DiffStep(DiffOp.INS, null, b[j - 1])); j -= 1 }
            }
        }
        steps.reverse()
        return matches to steps
    }

    /** NumberFormatter-spellOut shape for en ("twenty-one"), 0…999_999. */
    fun englishSpellOut(n: Int): String? {
        if (n < 0 || n > 999_999) return null
        val ones = listOf("zero","one","two","three","four","five","six","seven","eight","nine",
            "ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen")
        val tens = listOf("","","twenty","thirty","forty","fifty","sixty","seventy","eighty","ninety")
        fun underHundred(x: Int): String = when {
            x < 20 -> ones[x]
            x % 10 == 0 -> tens[x / 10]
            else -> "${tens[x / 10]}-${ones[x % 10]}"
        }
        fun underThousand(x: Int): String = when {
            x < 100 -> underHundred(x)
            x % 100 == 0 -> "${ones[x / 100]} hundred"
            else -> "${ones[x / 100]} hundred ${underHundred(x % 100)}"
        }
        return when {
            n < 1000 -> underThousand(n)
            n % 1000 == 0 -> "${underThousand(n / 1000)} thousand"
            else -> "${underThousand(n / 1000)} thousand ${underThousand(n % 1000)}"
        }
    }
}

/**
 * One word's span in a timeline — the target line's (karaoke, the beat it is
 * judged against) or the learner's take (`TakeAligner`). iOS `WordTiming`,
 * same JSON keys, so a timings file cached on either platform reads on the
 * other.
 */
@kotlinx.serialization.Serializable
data class WordTiming(
    val word: String,
    val startMs: Int,
    val endMs: Int,
    /**
     * False when the span was never OBSERVED — a character-count estimate or
     * a word shared out across a gap between two anchored neighbours. Karaoke
     * may light on either; the rhythm grade may only judge a measured one.
     * Defaults true so every timing already on disk keeps working.
     */
    val isMeasured: Boolean = true,
)

/**
 * Karaoke timings WITHOUT a second synthesis: spans are estimated from the
 * audio's own duration, split proportionally to how much text each word
 * carries (`ShadowDrillView.estimatedTimings`). Cached audio therefore
 * karaokes for free — the rule is cache first, timings from free
 * alignment/estimation, never a duplicate paid synthesis. Every span is an
 * estimate, so none of them is ever graded.
 */
object WordTimings {
    fun estimate(text: String, durationMs: Int, language: String = "en"): List<WordTiming> {
        // The timeline is cut into the language's OWN words: punctuation
        // rides along so the words joined back give the line itself.
        val words = com.roro.futurevoice.data.WordSplitter.timingWords(text, language)
        if (words.isEmpty() || durationMs <= 0) return emptyList()
        // Weighted by what is SAID — a 。 or 「 on a Japanese word takes no time.
        val spaced = com.roro.futurevoice.data.WordSplitter.spaced(language)
        fun weight(w: String) = if (spaced) maxOf(w.length, 1) else maxOf(LocalAlignment.normalized(w).length, 1)
        val totalChars = words.sumOf { weight(it) }
        val msPerChar = durationMs.toDouble() / totalChars
        var cursor = 0.0
        return words.map { w ->
            val start = cursor
            cursor += msPerChar * weight(w)
            // Small trailing gap so adjacent highlights read as distinct words.
            WordTiming(w, start.toInt(), maxOf(start.toInt() + 1, cursor.toInt() - 20), isMeasured = false)
        }
    }

    /** Which word index is being spoken at [positionMs], or -1. */
    fun indexAt(timings: List<WordTiming>, positionMs: Int): Int =
        timings.indexOfFirst { positionMs in it.startMs..it.endMs }

    /**
     * Does a timeline belong to THIS recording? Overshoot is the tell: words
     * cannot end after the audio does. Undershoot is bounded by coverage —
     * every alignment ends at the last WORD, not the last sample
     * (`ShadowDrillView.fits`).
     */
    fun fits(timings: List<WordTiming>, durationMs: Int): Boolean {
        if (timings.isEmpty()) return false
        val last = timings.last().endMs
        if (durationMs <= 0) return true
        val tolerance = maxOf(300, (durationMs * 0.12).toInt())
        if (last > durationMs + tolerance) return false
        return last >= durationMs * MIN_COVERAGE
    }

    /** iOS `minTimingCoverage`. */
    const val MIN_COVERAGE = 0.6

    /** A stored timeline is cut into the words this line is cut into now —
     *  always true for a spaced language (`ShadowDrillView.cutMatches`). */
    fun cutMatches(timings: List<WordTiming>, text: String, language: String): Boolean =
        com.roro.futurevoice.data.WordSplitter.spaced(language) ||
            timings.map { it.word } == com.roro.futurevoice.data.WordSplitter.timingWords(text, language)
}
