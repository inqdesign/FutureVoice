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
        /** The share matched before the sqrt curve, 0…1 (iOS `ratio`). */
        val ratio: Double = 0.0,
    )

    /** en spell-out for the JVM tests; Android swaps in ICU at app start. */
    var spellOut: (Int, String) -> String? = { n, language ->
        if (language.startsWith("en")) englishSpellOut(n) else null
    }

    fun analyze(target: String, learner: String, language: String = "en"): Analysis {
        val style = LanguageCatalog.tokenStyle(language)
        val targetTokens = tokenize(expandForDiff(target, language), style)
        val learnerTokens = heardTokens(learner, target, targetTokens, language, style)
        // Japanese compares by SOUND: the transcriber picks the script
        // (ナワナ / なわな / nawana are the same three morae), so a token is
        // keyed in hiragana — the steps still carry what each side wrote.
        // Without this the app's own name scored as a miss on every take.
        val key: (String) -> String = soundKey(language)
        val (matches, steps) = align(targetTokens, learnerTokens, key)
        val denom = maxOf(targetTokens.size, learnerTokens.size)
        val raw = if (style == LanguageCatalog.TokenStyle.SYLLABLE)
            wordCreditRatio(target, language, steps, targetTokens.size, learnerTokens.size)
        else if (denom > 0) matches.toDouble() / denom else 0.0
        // sqrt curve: single-word slips don't crater a good attempt.
        val score = (sqrt(raw) * 100).let { Math.round(it) }.toInt().coerceIn(0, 100)
        return Analysis(score, steps, targetTokens.size, learnerTokens.size, matches, raw)
    }

    /**
     * True when what the live recognizer heard ENDS with the line's last
     * words — the learner reached the end of the line (iOS `a4fa2dc6`). Ends
     * an attempt on content rather than on a silence a noisy room may never
     * give. Words for spaced languages (the last two, in order, inside the
     * last five heard), characters for ko/ja/zh (the last three, inside the
     * last eight heard). Digits spelled out first, as the diff does. False
     * for a line too short to tell its end from its middle.
     */
    fun heardLineEnd(target: String, heard: String, language: String): Boolean {
        val style = LanguageCatalog.tokenStyle(language)
        val t = tokenize(expandForDiff(target, language), LanguageCatalog.TokenStyle.WORD)
        val h = heardTokens(heard, target, t, language, LanguageCatalog.TokenStyle.WORD)
        val key: (String) -> String = soundKey(language)
        return when (style) {
            LanguageCatalog.TokenStyle.WORD -> {
                if (t.size < 2 || h.size < 2) return false
                val end = t.takeLast(2).map(key)
                val tail = h.takeLast(5).map(key)
                (0 until tail.size - 1).any { tail[it] == end[0] && tail[it + 1] == end[1] }
            }
            LanguageCatalog.TokenStyle.SYLLABLE -> {
                val tc = t.joinToString("").map { key(it.toString()) }.joinToString("")
                val hc = h.joinToString("").map { key(it.toString()) }.joinToString("")
                if (tc.length < 4) return false
                hc.takeLast(8).contains(tc.takeLast(3))
            }
        }
    }

    /**
     * Which words of a script a PIECE of a reading holds: the piece's own
     * transcript laid against the whole script, free to begin and end
     * anywhere in it (iOS `scriptRange`, 2026-11-17). A piece's span used to
     * be where the prompter's cursor stood when it was cut; a cursor behind
     * the voice had "fifty-one to ninety" judged against the sentence before
     * it. Null when the piece is too short to place or under half its words
     * are the script's. [near] (a word index) only settles a tie.
     */
    fun scriptRange(heard: String, words: List<String>, language: String, near: Int? = null): IntRange? {
        val style = LanguageCatalog.tokenStyle(language)
        val key = soundKey(language)
        val script = ArrayList<String>()
        val owner = ArrayList<Int>()
        for ((index, word) in words.withIndex()) {
            for (token in tokenize(expandForDiff(word, language), style)) {
                script.add(key(token)); owner.add(index)
            }
        }
        val piece = tokenize(expandForDiff(heard, language), style).map(key)
        val m = piece.size
        val n = script.size
        if (m < (if (style == LanguageCatalog.TokenStyle.WORD) 3 else 5) || n == 0) return null
        // Edit distance of the whole piece against ANY stretch of the script:
        // row 0 is free, so the stretch may start anywhere.
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in 1..m) {
            dp[i][0] = i
            for (j in 1..n) {
                dp[i][j] = minOf(dp[i - 1][j - 1] + (if (piece[i - 1] == script[j - 1]) 0 else 1),
                    dp[i - 1][j] + 1, dp[i][j - 1] + 1)
            }
        }
        val hintToken = near?.let { h -> owner.indexOfFirst { it >= h }.takeIf { it >= 0 } } ?: 0
        var end = 1
        for (j in 1..n) {
            if (dp[m][j] < dp[m][end] ||
                (dp[m][j] == dp[m][end] && near != null && kotlin.math.abs(j - hintToken) < kotlin.math.abs(end - hintToken))) end = j
        }
        // From the first script token the piece matched to the last: a word
        // at either edge that matched nothing is not kept (a piece cut after
        // "eighty-six" opens on "1000", and "one" is not "six").
        var i = m
        var j = end
        var matched = 0
        var first = -1
        var last = -1
        while (i > 0) {
            if (j > 0 && dp[i][j] == dp[i - 1][j - 1] + (if (piece[i - 1] == script[j - 1]) 0 else 1)) {
                if (piece[i - 1] == script[j - 1]) {
                    matched++
                    first = j - 1
                    if (last < 0) last = j - 1
                }
                i--; j--
            } else if (dp[i][j] == dp[i - 1][j] + 1) {
                i--
            } else {
                j--
            }
        }
        if (matched * 2 < m || first < 0) return null
        return owner[first]..owner[last]
    }

    /**
     * A piece's read-back with the script's words put back where Azure heard
     * them clearly (iOS `restoringClearWords`, 2026-11-17). The read-back is
     * never shown the script, so a word it can't know comes back as something
     * else: "this nawana Air flight" read as "to this fly" while Azure scored
     * all four words 94–97 with no error. A stretch where the two disagree is
     * restored only when EVERY script word in it came back from Azure as
     * `None` at [minAccuracy] or more; omitted, inserted or mispronounced
     * words keep the read-back's version. Spaced languages only.
     * Returns the text and how many words were put back.
     */
    fun restoringClearWords(heard: String, reference: String, words: List<PronunciationResult.Word>,
                            language: String, minAccuracy: Int = 85): Pair<String, Int> {
        val style = LanguageCatalog.tokenStyle(language)
        if (style != LanguageCatalog.TokenStyle.WORD || heard.isEmpty() || reference.isEmpty() || words.isEmpty()) return heard to 0
        val key = soundKey(language)
        fun toks(s: String) = tokenize(expandForDiff(s, language), style)

        val heardWords = heard.split(Regex("\\s+")).filter { it.isNotEmpty() }.toMutableList()
        val hTok = ArrayList<String>(); val hOwner = ArrayList<Int>()
        for ((i, w) in heardWords.withIndex()) for (t in toks(w)) { hTok.add(t); hOwner.add(i) }
        val refTok = toks(reference)
        val aTok = ArrayList<String>(); val aClear = ArrayList<Boolean>()
        for (w in words) {
            if (w.isInsertion) continue
            val clear = w.error == "None" && (w.accuracy ?: 0) >= minAccuracy
            for (t in toks(w.word)) { aTok.add(t); aClear.add(clear) }
        }
        if (refTok.isEmpty() || hTok.isEmpty() || aTok.isEmpty()) return heard to 0

        // Which script tokens Azure heard clearly.
        val refClear = BooleanArray(refTok.size)
        var i = 0; var j = 0
        for (step in align(refTok, aTok, key).second) when (step.op) {
            DiffOp.MATCH -> { refClear[i] = aClear[j]; i++; j++ }
            DiffOp.SUB -> { i++; j++ }
            DiffOp.DEL -> i++
            DiffOp.INS -> j++
        }

        // Stretches where the read-back and the script disagree: [refFrom, refTo) × [hFrom, hTo).
        val hunks = ArrayList<IntArray>()
        var open: IntArray? = null
        i = 0; j = 0
        for (step in align(refTok, hTok, key).second) {
            if (step.op == DiffOp.MATCH) {
                open?.let { hunks.add(it) }; open = null
                i++; j++
                continue
            }
            val h = open ?: intArrayOf(i, i, j, j).also { open = it }
            when (step.op) {
                DiffOp.SUB -> { i++; j++ }
                DiffOp.DEL -> i++
                DiffOp.INS -> j++
                DiffOp.MATCH -> {}
            }
            h[1] = i; h[3] = j
        }
        open?.let { hunks.add(it) }

        fun boundary(t: Int) = t == 0 || t == hTok.size || hOwner[t - 1] != hOwner[t]
        var restored = 0
        for (h in hunks.asReversed()) {
            val (rFrom, rTo, hFrom, hTo) = h
            if (rFrom == rTo || (rFrom until rTo).any { !refClear[it] } || !boundary(hFrom) || !boundary(hTo)) continue
            val put = refTok.subList(rFrom, rTo).toMutableList()
            if (hFrom == hTo) {
                val at = if (hFrom == 0) 0 else hOwner[hFrom - 1] + 1
                heardWords.addAll(at, put)
            } else {
                val first = hOwner[hFrom]; val last = hOwner[hTo - 1]
                // The sentence's own punctuation stays with it.
                val tail = heardWords[last].takeLastWhile { !it.isLetterOrDigit() && !it.isWhitespace() }
                put[put.size - 1] = put.last() + tail
                for (k in last downTo first) heardWords.removeAt(k)
                heardWords.addAll(first, put)
            }
            restored += put.size
        }
        return (if (restored > 0) heardWords.joinToString(" ") else heard) to restored
    }

    /** How two tokens are compared: Japanese by sound (the transcriber picks
     *  the script, ナワナ / なわな, so kana is keyed in hiragana), Chinese by
     *  Simplified character, everything else as written (iOS `soundKey`). */
    private fun soundKey(language: String): (String) -> String = when {
        language.startsWith("ja") -> com.roro.futurevoice.data.JapaneseMorph::soundSpelling
        language.startsWith("zh") -> com.roro.futurevoice.data.ChineseMorph::simplified
        language.startsWith("en") -> ::englishSpelling
        else -> { t -> t }
    }

    /**
     * British and American spellings of one word are one word: a script says
     * "ageing", the transcriber writes "aging", and the reader said it right
     * (iOS `englishSpelling`, 2026-11-17). Both sides go through this; the
     * steps still carry what each side wrote. Families with one sound only.
     */
    fun englishSpelling(token: String): String {
        if (token.length < 4) return token
        SPELLING_PAIRS[token]?.let { return it }
        var t = token
        for ((pattern, template) in SPELLING_RULES) t = pattern.replace(t, template)
        return t
    }

    private val SPELLING_PAIRS = mapOf(
        "ageing" to "aging", "grey" to "gray", "greys" to "grays", "programme" to "program", "programmes" to "programs",
        "tyre" to "tire", "tyres" to "tires", "jewellery" to "jewelry", "judgement" to "judgment",
        "catalogue" to "catalog", "dialogue" to "dialog", "analogue" to "analog", "cosy" to "cozy",
        "pyjamas" to "pajamas", "plough" to "plow", "sceptical" to "skeptical", "mould" to "mold",
        "moustache" to "mustache", "doughnut" to "donut", "yoghurt" to "yogurt", "storey" to "story",
        "kerb" to "curb", "draught" to "draft", "enrol" to "enroll", "fulfil" to "fulfill", "skilful" to "skillful",
        "wilful" to "willful", "instalment" to "installment", "practise" to "practice", "practised" to "practiced",
        "practising" to "practicing",
    )
    private val SPELLING_RULES = listOf(
        Regex("^(colo|favo|hono|neighbo|behavio|labo|flavo|humo|rumo|harbo|endeavo|savo|vigo|armo|odo|tumo|vapo|rigo|splendo|parlo|glamo)u(r.*)$") to "$1$2",
        Regex("^(.{3,})is(e|ed|es|ing|er|ers|ation|ations)$") to "$1iz$2",
        Regex("^(.{3,})ys(e|ed|es|ing)$") to "$1yz$2",
        Regex("^(cent|theat|met|lit|fib|calib|somb|spect|lust|meag)re(s?)$") to "$1er$2",
        Regex("^(travel|cancel|model|label|level|signal|counsel|fuel|quarrel|marvel|jewel|dial|equal|total|channel|tunnel|shovel|panel)l(ed|ing|er|ers)$") to "$1$2",
        Regex("^(defen|offen|licen|preten)ce(s?)$") to "$1se$2",
    )

    /** Ops in TARGET order (`ins` skipped) — indexes align with [tokenSpans]. */
    fun targetOps(steps: List<DiffStep>): List<DiffOp> =
        steps.filter { it.op != DiffOp.INS }.map { it.op }

    /**
     * Korean and Japanese are ALIGNED by character but SCORED by the target's
     * words (Korean eojeol, Japanese segmenter words): a word counts only when
     * every character in it matched — by character a wrong particle read 96
     * (iOS ShadowEngine.wordCreditRatio). Extra speech converts to words at the
     * line's own characters per word, so the denominator is max(target,
     * learner). Chinese words come from [com.roro.futurevoice.data.ChineseMorph].
     */
    private fun wordCreditRatio(target: String, language: String, steps: List<DiffStep>,
                                targetSyllables: Int, learnerSyllables: Int): Double {
        val words = when {
            language.startsWith("ko") -> target.split(Regex("\\s+")).filter { it.isNotEmpty() }
            language.startsWith("ja") -> com.roro.futurevoice.data.JapaneseMorph.segments(target)
            language.startsWith("zh") -> com.roro.futurevoice.data.ChineseMorph.segments(target)
            else -> emptyList()
        }
        val spans = tokenSpans(words, language).filter { !it.isEmpty() }
        val ops = targetOps(steps)
        if (spans.isEmpty() || targetSyllables == 0 || ops.size != targetSyllables) {
            val denom = maxOf(targetSyllables, learnerSyllables)
            return if (denom > 0) steps.count { it.op == DiffOp.MATCH }.toDouble() / denom else 0.0
        }
        val matched = spans.count { span -> span.all { ops[it] == DiffOp.MATCH } }
        val perWord = targetSyllables.toDouble() / spans.size
        val denom = maxOf(spans.size.toDouble(), learnerSyllables / perWord)
        return matched / denom
    }

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

    /**
     * The measured assessment for the coach, or "n/a" (iOS
     * `renderPronunciationForPrompt`, 0971c05d). Score and parts, then each
     * faulted word with its weakest sounds — the model is told to name those
     * and nothing it did not measure.
     */
    fun renderPronunciationForPrompt(p: PronunciationResult?): String {
        if (p == null) return "n/a"
        val parts = mutableListOf("overall ${p.score}", "accuracy ${p.accuracy}", "fluency ${p.fluency}")
        p.prosody?.let { parts += "prosody $it" }
        val weak = p.weakWords.take(6).map { w ->
            val sounds = w.weakPhonemes.take(3).map { "${it.phoneme} ${it.accuracy ?: 0}" }
            val tag = if (w.error == "None" || w.error == "Mispronunciation") "" else " ${w.error}"
            "[${w.word} ${w.accuracy ?: 0}$tag${if (sounds.isEmpty()) "" else ": " + sounds.joinToString(", ")}]"
        }
        val monotone = if (p.words.any { it.error == "Monotone" }) " Monotone" else ""
        return parts.joinToString(" · ") + monotone +
            (if (weak.isEmpty()) " — every word scored well" else " — low words: " + weak.joinToString(" "))
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
        // One word or two is the transcriber's: "All right, everyone" came
        // back "Alright" and was marked (iOS 2026-11-17).
        "alright" to "all right", "okay" to "ok",
    )
    private val SUFFIXES = listOf(
        "n't" to " not", "'re" to " are", "'m" to " am", "'ve" to " have",
        "'ll" to " will", "'d" to " would", "'s" to " is",
    )

    /**
     * Lowercased, apostrophes folded, and the WRITTEN shapes of numbers put
     * back into words and bare digits (iOS `written`): "1,500" → "1500",
     * "$5" → "5 dollars", "50%" → "50 percent", "3.5" → "3 point 5", and in
     * English "21st" → "twenty first", "1960s" → "nineteen sixties", "Dr." →
     * "doctor". A transcriber picks these; the reader said the words. Every
     * change stays inside one whitespace-delimited word, and running it
     * twice changes nothing.
     */
    fun written(text: String, language: String): String {
        // A model-written target says "I’m" and the recognizer writes "I'm";
        // that is a choice no mouth makes (iOS `17d0b56`).
        var out = text.lowercase()
            .replace('’', '\'').replace('‘', '\'').replace('ʼ', '\'')
        val code = language.take(2)
        val hasDigit = out.any { it.isDigit() }
        val commaDecimal = code == "de" || code == "es" || code == "fr"
        if (hasDigit) {
            out = (if (commaDecimal) GROUP_DOT else GROUP_COMMA).replace(out, "")
        }
        val units = CURRENCY_WORDS[code]
        if (units != null && out.any { it in "$€£₩¥" }) {
            out = MONEY.replace(out) { m ->
                val unit = units[m.groupValues[1]] ?: return@replace m.value
                "${m.groupValues[2]} ${if (m.groupValues[2] == "1") unit.first else unit.second}"
            }
            out = MONEY_SIGN.replace(out) { m -> units[m.value]?.let { " ${it.second} " } ?: m.value }
        }
        PERCENT_WORD[code]?.let { if ('%' in out) out = out.replace("%", " $it ") }
        // "nine degrees" comes back "9°" (or "9°C"): the reader said the word.
        DEGREE_WORD[code]?.let { degrees -> if ('°' in out) out = DEGREE.replace(out) { " $degrees " } }
        DECIMAL_WORD[code]?.let { point ->
            if (hasDigit) out = (if (commaDecimal) DECIMAL_COMMA else DECIMAL_DOT).replace(out) { m ->
                "${m.groupValues[1]} $point " + m.groupValues[2].map { it.toString() }.joinToString(" ")
            }
        }
        if (code == "zh" && hasDigit) {
            // Mandarin readers and recognizers write numbers either way (3年 /
            // 三年); spell both sides out so the character diff lines up.
            out = ZH_DIGITS.replace(out) { m ->
                m.value.toIntOrNull()?.let { com.roro.futurevoice.data.ChineseMorph.spellOut(it) } ?: m.value
            }
        }
        if (code != "en") return out

        if (hasDigit) {
            fun spell(v: Int): List<String> =
                (spellOut(v, "en") ?: "").lowercase().replace("-", " ").split(" ").filter { it.isNotEmpty() }
            fun ending(words: List<String>, change: (String) -> String): String =
                if (words.isEmpty()) "" else (words.dropLast(1) + change(words.last())).joinToString(" ")
            out = ORDINAL.replace(out) { m ->
                val n = m.groupValues[1].toIntOrNull() ?: return@replace m.value
                " " + ending(spell(n)) { ORDINAL_WORD[it] ?: if (it.endsWith("y")) it.dropLast(1) + "ieth" else it + "th" } + " "
            }
            // Decades: the 1960s are "the nineteen sixties", the 80s "the eighties".
            out = DECADE.replace(out) { m ->
                val n = m.groupValues[1].toIntOrNull() ?: return@replace m.value
                val plural: (String) -> String = { if (it.endsWith("y")) it.dropLast(1) + "ies" else it + "s" }
                if (m.groupValues[1].length == 4 && n in 1100..2099 && (n / 100) % 10 != 0) {
                    val hi = spell(n / 100)
                    val lo = n % 100
                    " " + (if (lo == 0) ending(hi + "hundred", plural) else ending(hi + spell(lo), plural)) + " "
                } else " " + ending(spell(n), plural) + " "
            }
        }
        if ("dr" in out || "mr" in out) {
            for ((re, long) in TITLES) out = re.replace(out, long)
        }
        return out
    }

    private val ZH_DIGITS = Regex("\\d{1,9}")
    private val GROUP_COMMA = Regex("(?<=\\d),(?=\\d{3}(?!\\d))")
    private val GROUP_DOT = Regex("(?<=\\d)\\.(?=\\d{3}(?!\\d))")
    private val MONEY = Regex("([$€£₩¥])(\\d+(?:[.,]\\d+)?)")
    private val MONEY_SIGN = Regex("[$€£₩¥]")
    private val DECIMAL_DOT = Regex("(\\d+)\\.(\\d+)")
    private val DECIMAL_COMMA = Regex("(\\d+),(\\d+)")
    private val ORDINAL = Regex("(?<![\\d.,])(\\d{1,9})(st|nd|rd|th)(?![a-z])")
    private val DECADE = Regex("(?<![\\d.,])(\\d{2,4})'?s(?![a-z])")
    private val TITLES = listOf("dr" to "doctor", "mrs" to "missus", "mr" to "mister")
        .map { (short, long) -> Regex("(?<![a-z0-9'])$short\\.?(?![a-z0-9'])") to long }
    private val CURRENCY_WORDS: Map<String, Map<String, Pair<String, String>>> = mapOf(
        "en" to mapOf("$" to ("dollar" to "dollars"), "€" to ("euro" to "euros"), "£" to ("pound" to "pounds"),
            "₩" to ("won" to "won"), "¥" to ("yen" to "yen")),
        "de" to mapOf("$" to ("dollar" to "dollar"), "€" to ("euro" to "euro"), "£" to ("pfund" to "pfund"),
            "₩" to ("won" to "won"), "¥" to ("yen" to "yen")),
        "es" to mapOf("$" to ("dólar" to "dólares"), "€" to ("euro" to "euros"), "£" to ("libra" to "libras"),
            "₩" to ("won" to "wones"), "¥" to ("yen" to "yenes")),
        "fr" to mapOf("$" to ("dollar" to "dollars"), "€" to ("euro" to "euros"), "£" to ("livre" to "livres"),
            "₩" to ("won" to "wons"), "¥" to ("yen" to "yens")),
        "ko" to mapOf("$" to ("달러" to "달러"), "€" to ("유로" to "유로"), "£" to ("파운드" to "파운드"),
            "₩" to ("원" to "원"), "¥" to ("엔" to "엔")),
        "ja" to mapOf("$" to ("ドル" to "ドル"), "€" to ("ユーロ" to "ユーロ"), "£" to ("ポンド" to "ポンド"),
            "₩" to ("ウォン" to "ウォン"), "¥" to ("円" to "円")),
        "zh" to mapOf("$" to ("美元" to "美元"), "€" to ("欧元" to "欧元"), "£" to ("英镑" to "英镑"),
            "₩" to ("韩元" to "韩元"), "¥" to ("元" to "元")),
    )
    private val DEGREE = Regex("°[cf]?(?![a-z])")
    private val DEGREE_WORD = mapOf("en" to "degrees", "de" to "grad", "es" to "grados", "fr" to "degrés")
    private val PERCENT_WORD = mapOf("en" to "percent", "de" to "prozent", "es" to "por ciento", "fr" to "pour cent",
        "ko" to "퍼센트", "ja" to "パーセント")
    private val DECIMAL_WORD = mapOf("en" to "point", "de" to "komma", "es" to "coma", "fr" to "virgule",
        "ko" to "점", "ja" to "点", "zh" to "点")
    private val ORDINAL_WORD = mapOf("one" to "first", "two" to "second", "three" to "third", "five" to "fifth",
        "eight" to "eighth", "nine" to "ninth", "twelve" to "twelfth")

    fun expandForDiff(text: String, language: String): String {
        var out = written(text, language).replace("-", " ")
        out = Regex("\\d+").replace(out) { m ->
            val n = m.value.toIntOrNull() ?: return@replace m.value
            val spelled = spellOut(n, language) ?: return@replace m.value
            // German comes back with soft hyphens between its parts, which
            // split "21" into three tokens against the one word a
            // transcriber writes.
            " " + spelled.lowercase().replace("\u00AD", "").replace("-", " ") + " "
        }
        // A romaji word in a Japanese line (nawana) is six letters on one side
        // and three kana on the other — the recognizer writes it ナワナ. Cut
        // into kana on both sides so the morae line up.
        if (language.startsWith("ja")) {
            return com.roro.futurevoice.data.JapaneseMorph.katakanaFromLatinIn(out)
        }
        // Chinese: one script on both sides — the recognizer may write 說
        // where the line has 说, which is not a word the learner got wrong.
        if (language.startsWith("zh")) return com.roro.futurevoice.data.ChineseMorph.simplified(out)
        if (!language.startsWith("en")) return out
        for ((from, to) in IRREGULAR) {
            out = Regex("(?<![a-z])${Regex.escape(from)}(?![a-z])").replace(out, to)
        }
        for ((suffix, expansion) in SUFFIXES) {
            out = Regex("(?<=[a-z])${Regex.escape(suffix)}\\b").replace(out, expansion)
        }
        return out
    }

    /**
     * The heard side's tokens, with every number brought to the reading the
     * TARGET uses (iOS `heardTokens`). A transcriber writes digits for every
     * spoken form of a number: a script saying "nineteen eleven" read exactly
     * came back "1911", was spelled "one thousand nine hundred eleven", and
     * the take showed three added words and a wrong one. German years
     * (neunzehnhundertelf), Spanish un/una and Korean native numbers (3시 is
     * 세 시) are the same problem. Digits HEARD take whichever reading is
     * closest to the target; words heard for digits in the TARGET become the
     * target's own spelling. The plain spell-out wins a tie, and the
     * target's tokens never change. Japanese spells out in kanji, which
     * carries no reading.
     */
    private fun heardTokens(
        heard: String, target: String, targetTokens: List<String>,
        language: String, style: LanguageCatalog.TokenStyle,
    ): List<String> {
        val tokens = numberedTokens(heard, target, targetTokens, language, style)
        if (style != LanguageCatalog.TokenStyle.WORD) return tokens
        val units = if (language.startsWith("en")) spellingOutUnits(tokens, targetTokens, language) else tokens
        return joiningCompounds(units, targetTokens, language)
    }

    /** A transcriber writes "mph" for "miles an hour": a heard abbreviation
     *  is written out the way that brings it closest to the target, and left
     *  alone when no way does (iOS, 2026-11-18). */
    private val UNIT_WORDS: Map<String, List<List<String>>> = run {
        val kmh = listOf(
            listOf("kilometers", "an", "hour"), listOf("kilometers", "per", "hour"),
            listOf("kilometres", "an", "hour"), listOf("kilometres", "per", "hour"),
        )
        mapOf(
            "mph" to listOf(listOf("miles", "an", "hour"), listOf("miles", "per", "hour")),
            "kph" to kmh, "kmh" to kmh,
            "km" to listOf(listOf("kilometers"), listOf("kilometres"), listOf("kilometer"), listOf("kilometre")),
            "kg" to listOf(listOf("kilograms"), listOf("kilos"), listOf("kilogram"), listOf("kilo")),
            "lbs" to listOf(listOf("pounds")), "lb" to listOf(listOf("pounds"), listOf("pound")),
            "ft" to listOf(listOf("feet"), listOf("foot")),
            "mins" to listOf(listOf("minutes")), "hrs" to listOf(listOf("hours")),
        )
    }

    private fun spellingOutUnits(heard: List<String>, targetTokens: List<String>, language: String): List<String> {
        if (heard.none { it in UNIT_WORDS }) return heard
        val key = soundKey(language)
        fun cost(t: List<String>): Int { val (matched, steps) = align(targetTokens, t, key); return steps.size - matched }
        var tokens = heard
        var i = 0
        while (i < tokens.size) {
            val options = UNIT_WORDS[tokens[i]]
            if (options == null) { i++; continue }
            var best = cost(tokens)
            var pick: List<String>? = null
            for (words in options) {
                val trial = tokens.subList(0, i) + words + tokens.subList(i + 1, tokens.size)
                val c = cost(trial)
                if (c < best) { best = c; pick = words }
            }
            if (pick != null) {
                tokens = tokens.subList(0, i) + pick + tokens.subList(i + 1, tokens.size)
                i += pick.size
            } else i++
        }
        return tokens
    }

    /**
     * One word or two is the transcriber's choice, not the mouth's: a script's
     * "shortcut" came back "short cut" and showed a wrong word and an added
     * one, "every day" came back "everyday" (iOS `joiningCompounds`,
     * 2026-11-17). Two heard words that make one of the target's, or one heard
     * word that is two of the target's in a row, are written the target's way,
     * wherever that brings the two closer.
     */
    private fun joiningCompounds(heard: List<String>, targetTokens: List<String>, language: String): List<String> {
        if (heard.isEmpty() || targetTokens.size < 2) return heard
        val key = soundKey(language)
        val single = targetTokens.map(key).toSet()
        val pairs = HashMap<String, Pair<String, String>>()
        for (i in 0 until targetTokens.size - 1) pairs[key(targetTokens[i] + targetTokens[i + 1])] = targetTokens[i] to targetTokens[i + 1]
        var tokens = heard
        fun cost(t: List<String>): Int { val (matched, steps) = align(targetTokens, t, key); return steps.size - matched }
        var best: Int? = null
        var i = 0
        while (i < tokens.size) {
            var trial: List<String>? = null
            val pair = pairs[key(tokens[i])]
            if (i + 1 < tokens.size && key(tokens[i] + tokens[i + 1]) in single &&
                !(key(tokens[i]) in single && key(tokens[i + 1]) in single)) {
                trial = tokens.subList(0, i) + (tokens[i] + tokens[i + 1]) + tokens.subList(i + 2, tokens.size)
            } else if (pair != null && key(tokens[i]) !in single) {
                trial = tokens.subList(0, i) + pair.first + pair.second + tokens.subList(i + 1, tokens.size)
            }
            if (trial != null) {
                val before = best ?: cost(tokens)
                val after = cost(trial)
                if (after < before) { tokens = trial; best = after } else best = before
            }
            i++
        }
        return tokens
    }

    private fun numberedTokens(
        heard: String, target: String, targetTokens: List<String>,
        language: String, style: LanguageCatalog.TokenStyle,
    ): List<String> {
        // Written shapes first ("1,500" is one number, "21st" no number at
        // all), so a run below is always a whole spoken number.
        @Suppress("NAME_SHADOWING") val heard = written(heard, language)
        @Suppress("NAME_SHADOWING") val target = written(target, language)
        var tokens = tokenize(expandForDiff(heard, language), style)
        val digits = Regex("\\d+")
        val known = listOf("en", "de", "es", "fr", "ko").any { language.startsWith(it) }
        if (!known || (!digits.containsMatchIn(heard) && !digits.containsMatchIn(target))) return tokens
        // Edit distance, not matches: "one hundred and five" for "105"
        // matches every target word and still leaves an added "and".
        fun cost(t: List<String>): Int { val (m, steps) = align(targetTokens, t); return steps.size - m }

        val runs = digits.findAll(heard).toList()
        if (runs.isNotEmpty() && runs.size <= MAX_NUMBER_RUNS) {
            val options = runs.map { readings(it.value, language) }
            var picked = IntArray(runs.size)
            fun build(p: IntArray): List<String> {
                val sb = StringBuilder(heard)
                for (i in runs.indices.reversed()) if (p[i] > 0) {
                    sb.replace(runs[i].range.first, runs[i].range.last + 1, " " + options[i][p[i]] + " ")
                }
                return tokenize(expandForDiff(sb.toString(), language), style)
            }
            var best = cost(tokens)
            for (i in runs.indices) for (c in 1 until options[i].size) {
                val trial = picked.copyOf().also { it[i] = c }
                val built = build(trial)
                val score = cost(built)
                if (score < best) { best = score; picked = trial; tokens = built }
            }
        }

        val targetRuns = digits.findAll(target).toList()
        if (targetRuns.isEmpty() || targetRuns.size > MAX_NUMBER_RUNS) return tokens
        var best = cost(tokens)
        for (run in targetRuns) {
            val all = readings(run.value, language).map { tokenize(expandForDiff(it, language), style) }
            val plain = all.firstOrNull() ?: continue
            var winner: List<String>? = null
            for (other in all.drop(1)) {
                if (other.isEmpty() || other == plain || other.size > tokens.size) continue
                for (at in 0..tokens.size - other.size) {
                    if (tokens.subList(at, at + other.size) != other) continue
                    val trial = tokens.subList(0, at) + plain + tokens.subList(at + other.size, tokens.size)
                    val score = cost(trial)
                    if (score < best) { best = score; winner = trial }
                }
            }
            winner?.let { tokens = it }
        }
        return tokens
    }

    private const val MAX_NUMBER_RUNS = 24

    /**
     * The ways a digit run is read aloud in [language], the plain spell-out
     * (what [expandForDiff] writes) first. iOS `readings(of:language:)`.
     */
    fun readings(digits: String, language: String): List<String> {
        if (digits.length > 9) return emptyList()
        val n = digits.toIntOrNull() ?: return emptyList()
        val code = language.take(2)
        fun spell(v: Int): String =
            (spellOut(v, code) ?: "").lowercase().replace("­", "").replace("-", " ")
        val plain = spell(n)
        if (plain.isEmpty()) return emptyList()
        val each = digits.map { it - '0' }
        val out = mutableListOf(plain)
        when (code) {
            "en" -> {
                val words = plain.split(" ")
                val withAnd = mutableListOf<String>()
                for ((i, word) in words.withIndex()) {
                    withAnd.add(word)
                    if (i + 1 >= words.size || words[i + 1] == "thousand" || words[i + 1] == "million") continue
                    if (word == "hundred" || (word == "thousand" && n % 1000 < 100)) withAnd.add("and")
                }
                out.add(withAnd.joinToString(" "))
                // "a thousand" and a bare "thousand" are written "1000" too: a take
                // cut between "eighty-six" and "thousand" came back "86" + "1000
                // people" and showed an added "one" (iOS, 2026-11-17).
                for (base in listOf(words, withAnd)) {
                    if (base.size >= 2 && base[0] == "one" &&
                        base[1] in setOf("hundred", "thousand", "million", "billion")) {
                        val rest = base.drop(1).joinToString(" ")
                        out.add("a $rest")
                        out.add(rest)
                    }
                }
                if (digits.length == 4 && n >= 1000) {
                    val hi = n / 100
                    val lo = n % 100
                    if (lo == 0) {
                        if (hi % 10 != 0) out.add("${spell(hi)} hundred")
                    } else {
                        out.add(if (lo < 10) "${spell(hi)} oh ${spell(lo)}" else "${spell(hi)} ${spell(lo)}")
                        if (hi % 10 != 0) {
                            out.add("${spell(hi)} hundred and ${spell(lo)}")
                            out.add("${spell(hi)} hundred ${spell(lo)}")
                        }
                    }
                }
                if (digits.length >= 2) {
                    out.add(each.joinToString(" ") { if (it == 0) "oh" else spell(it) })
                    out.add(each.joinToString(" ") { spell(it) })
                }
            }
            "de" -> {
                if (digits.length == 4 && n in 1100..1999) {
                    val lo = n % 100
                    out.add(spell(n / 100) + "hundert" + (if (lo > 0) spell(lo) else ""))
                }
                val stems = mutableListOf(plain)
                if (plain.startsWith("einhundert") || plain.startsWith("eintausend")) stems.add(plain.drop(3))
                out.addAll(stems.drop(1))
                for (stem in stems) if (stem.endsWith("eins")) {
                    val base = stem.dropLast(1)
                    out.addAll(listOf(base, base + "e", base + "en", base + "em", base + "er"))
                }
                if (digits.length >= 2) out.add(each.joinToString(" ") { spell(it) })
            }
            "es" -> {
                val stems = mutableListOf(plain)
                if ("cientos" in plain || "quinientos" in plain) {
                    stems.add(plain.replace("cientos", "cientas").replace("quinientos", "quinientas"))
                    out.add(stems[1])
                }
                for (stem in stems) {
                    if (stem.endsWith("veintiuno")) {
                        val base = stem.dropLast(3)
                        out.addAll(listOf(base + "ún", base + "una"))
                    } else if (stem == "uno" || stem.endsWith(" uno")) {
                        val base = stem.dropLast(1)
                        out.addAll(listOf(base, base + "a"))
                    }
                }
                if (digits.length >= 2) out.add(each.joinToString(" ") { spell(it) })
            }
            // une for a final "un" (vingt et une), the Belgian and Swiss tens
            // (septante, huitante, nonante), the old year reading of four
            // digits (dix neuf cent quatre vingt dix), digit by digit.
            "fr" -> {
                val stems = mutableListOf(plain)
                if (digits.length == 4 && n in 1100..1999) {
                    val lo = n % 100
                    stems.add(spell(n / 100) + " cent" + (if (lo > 0) " " + spell(lo) else ""))
                }
                // Belgium and Switzerland: 70 septante, 80 huitante, 90 nonante.
                for (stem in stems) if ("soixante" in stem || "quatre vingt" in stem) {
                    val swiss = stem
                        .replace("soixante et onze", "septante et un")
                        .replace("soixante dix", "septante")
                        .replace("soixante onze", "septante et un")
                        .replace("soixante douze", "septante deux")
                        .replace("soixante treize", "septante trois")
                        .replace("soixante quatorze", "septante quatre")
                        .replace("soixante quinze", "septante cinq")
                        .replace("soixante seize", "septante six")
                        .replace("quatre vingt dix", "nonante")
                        .replace("quatre vingt onze", "nonante et un")
                        .replace("quatre vingt douze", "nonante deux")
                        .replace("quatre vingt treize", "nonante trois")
                        .replace("quatre vingt quatorze", "nonante quatre")
                        .replace("quatre vingt quinze", "nonante cinq")
                        .replace("quatre vingt seize", "nonante six")
                    if (swiss != stem) out.add(swiss)
                    val huit = stem.replace("quatre vingts", "huitante")
                        .replace("quatre vingt ", "huitante ")
                    if (huit != stem) out.add(huit)
                }
                out.addAll(stems.drop(1))
                for (stem in stems) if (stem == "un" || stem.endsWith(" un")) out.add(stem + "e")
                if (digits.length >= 2) out.add(each.joinToString(" ") { spell(it) })
            }
            "ko" -> {
                if (n in 1..99) {
                    val ones = listOf("", "하나", "둘", "셋", "넷", "다섯", "여섯", "일곱", "여덟", "아홉")
                    val counting = listOf("", "한", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉")
                    val tens = listOf("", "열", "스물", "서른", "마흔", "쉰", "예순", "일흔", "여든", "아흔")
                    out.add(if (n == 20) "스무" else tens[n / 10] + counting[n % 10])
                    out.add(tens[n / 10] + ones[n % 10])
                }
                if (digits.length >= 2) {
                    val sino = listOf("영", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구")
                    out.add(each.joinToString("") { if (it == 0) "공" else sino[it] })
                    out.add(each.joinToString("") { sino[it] })
                }
            }
        }
        return out.filter { it.isNotEmpty() }.distinct()
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

    /** The publisher's silence between one host's sentences (news-show-probe.py SENTENCE_GAP). */
    const val PODCAST_SENTENCE_GAP_MS = 420

    /**
     * A podcast line has no measured timings, and its file is the line's
     * sentences with a fixed 0.42 s between them. The plain estimate spread
     * that silence over the characters, so the highlight ran ahead from the
     * second sentence on (iOS `PlaylistPlayer.podcastTimings`, 2026-11-15).
     */
    fun podcast(text: String, durationMs: Int, language: String): List<WordTiming> {
        val words = com.roro.futurevoice.data.WordSplitter.timingWords(text, language)
        if (words.isEmpty() || durationMs <= 0) return emptyList()
        val enders = setOf('。', '！', '？', '.', '!', '?', '…')
        val closers = setOf('”', '"', '\'', '’', '」', '』', '）', ')')
        val sentences = mutableListOf(mutableListOf<String>())
        words.forEachIndexed { i, w ->
            sentences.last().add(w)
            val last = w.trimEnd { it in closers }.lastOrNull()
            if (last != null && last in enders && i < words.size - 1) sentences.add(mutableListOf())
        }
        val spaced = com.roro.futurevoice.data.WordSplitter.spaced(language)
        fun weight(w: String) = if (spaced) maxOf(w.length, 1) else maxOf(LocalAlignment.normalized(w).length, 1)
        val speech = durationMs - PODCAST_SENTENCE_GAP_MS * (sentences.size - 1)
        if (speech <= durationMs / 3) return estimate(text, durationMs, language)
        val msPerChar = speech.toDouble() / sentences.sumOf { s -> s.sumOf { weight(it) } }
        var cursor = 0.0
        val out = mutableListOf<WordTiming>()
        sentences.forEachIndexed { si, sentence ->
            if (si > 0) cursor += PODCAST_SENTENCE_GAP_MS
            for (w in sentence) {
                val start = cursor
                cursor += msPerChar * weight(w)
                out.add(WordTiming(w, start.toInt(), maxOf(start.toInt() + 1, cursor.toInt() - 20), isMeasured = false))
            }
        }
        return out
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
