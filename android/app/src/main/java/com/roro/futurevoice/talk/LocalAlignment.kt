package com.roro.futurevoice.talk

import com.roro.futurevoice.data.JapaneseMorph

/**
 * Timeline arithmetic shared by every word-timing source — port of the pure
 * half of iOS `LocalAlignment` (`align` / `fill` / `alignByCharacters` /
 * `normalized`). The recognizer half of iOS's file has no Android
 * counterpart that returns times (see [TakeAligner] for what measures the
 * learner here); this half is what turns a set of anchored spans into one
 * window per expected word, and marks which of them were really observed.
 *
 * Displayed words are ALWAYS the expected ones (punctuation intact) — an
 * anchor only ever contributes a time.
 */
object LocalAlignment {

    /** Below this share of anchored words a pass is discarded. */
    const val MIN_MATCH_RATIO = 0.5

    /** A recognized/anchored span, seconds from the file's start. */
    data class Span(val start: Double, val end: Double)

    /**
     * Turn an expected→anchor pairing into a gapless, monotonic timeline.
     * Unmatched words share the span between their anchored neighbours,
     * split by how much text each carries — and are marked UNMEASURED.
     */
    fun fill(
        expected: List<String>,
        pairing: List<Int?>,
        heardSpans: List<Span>,
        durationMs: Int,
    ): List<WordTiming> {
        val n = expected.size
        val starts = arrayOfNulls<Double>(n)
        val ends = arrayOfNulls<Double>(n)
        val anchored = BooleanArray(n)
        pairing.forEachIndexed { i, seg ->
            if (seg != null && seg < heardSpans.size) {
                starts[i] = heardSpans[seg].start
                ends[i] = heardSpans[seg].end
                anchored[i] = true
            }
        }
        val audioEnd = if (durationMs > 0) durationMs / 1000.0
        else ends.filterNotNull().maxOrNull() ?: 0.0

        var i = 0
        while (i < n) {
            if (starts[i] != null) { i += 1; continue }
            var j = i
            while (j < n && starts[j] == null) j += 1
            val spanStart = if (i > 0) ends[i - 1] ?: 0.0 else 0.0
            val spanEnd = if (j < n) starts[j] ?: audioEnd else audioEnd
            val span = maxOf(0.0, spanEnd - spanStart)
            val weights = (i until j).map { maxOf(expected[it].length, 1).toDouble() }
            val total = weights.sum()
            var cursor = spanStart
            weights.forEachIndexed { k, w ->
                val slice = if (total > 0) span * (w / total) else 0.0
                starts[i + k] = cursor
                cursor += slice
                ends[i + k] = cursor
            }
            i = j
        }

        val out = ArrayList<WordTiming>(n)
        var previousEnd = 0.0
        for (k in 0 until n) {
            val s = maxOf(starts[k] ?: previousEnd, previousEnd)
            val e = maxOf(ends[k] ?: s, s + 0.01)
            previousEnd = e
            out += WordTiming(expected[k], (s * 1000).toInt(), (e * 1000).toInt(), isMeasured = anchored[k])
        }
        return out
    }

    /**
     * [fill] for a language written without spaces: both sides down to
     * CHARACTERS (each heard segment's span shared evenly across its
     * letters), aligned, gathered back into the expected words. A word is
     * MEASURED only when its first letter anchored to the first letter of a
     * heard segment — a real timestamp, not an even share.
     */
    fun alignByCharacters(
        expected: List<String>,
        heard: List<Triple<String, Double, Double>>,
        durationMs: Int,
        minRatio: Double = MIN_MATCH_RATIO,
    ): List<WordTiming> {
        val expectedChars = ArrayList<String>()
        val charRange = ArrayList<IntRange>()
        for (word in expected) {
            val start = expectedChars.size
            expectedChars += letters(word)
            charRange += start until expectedChars.size
        }
        val heardChars = ArrayList<String>()
        val spans = ArrayList<Span>()
        val opensSegment = ArrayList<Boolean>()
        for ((text, start, end) in heard) {
            val sounds = letters(text)
            if (sounds.isEmpty()) continue
            val share = maxOf(0.0, end - start) / sounds.size
            sounds.forEachIndexed { k, letter ->
                heardChars += letter
                spans += Span(start + share * k, start + share * (k + 1))
                opensSegment += k == 0
            }
        }
        if (expectedChars.isEmpty() || heardChars.isEmpty()) return emptyList()
        val pairing = align(expectedChars, heardChars)
        val anchored = pairing.count { it != null }
        if (anchored.toDouble() / expectedChars.size < minRatio) return emptyList()
        val chars = fill(expectedChars, pairing, spans, durationMs)

        val out = ArrayList<WordTiming>()
        var previousEnd = 0
        expected.forEachIndexed { w, word ->
            val range = charRange[w]
            if (range.isEmpty()) {
                out += WordTiming(word, previousEnd, previousEnd + 10, isMeasured = false)
                previousEnd += 10
                return@forEachIndexed
            }
            val first = range.first; val last = range.last
            val measured = pairing[first]?.let { opensSegment[it] } ?: false
            val s = maxOf(chars[first].startMs, previousEnd)
            val e = maxOf(chars[last].endMs, s + 10)
            out += WordTiming(word, s, e, isMeasured = measured)
            previousEnd = e
        }
        return out
    }

    /** Letters compared by SOUND (nawana / ナワナ / なわな are one word). */
    private fun letters(text: String): List<String> =
        JapaneseMorph.soundSpelling(normalized(text)).map { it.toString() }

    /**
     * Edit-distance alignment: for each expected item, the index of the heard
     * item it corresponds to, or null when dropped or mangled. Only an EXACT
     * hit anchors — a substitution's timestamp belongs to something else.
     */
    fun align(expected: List<String>, heard: List<String>): List<Int?> {
        val n = expected.size; val m = heard.size
        if (n == 0 || m == 0) return List(n) { null }
        val cost = Array(n + 1) { IntArray(m + 1) }
        for (i in n - 1 downTo 0) cost[i][m] = cost[i + 1][m] + 1
        for (j in m - 1 downTo 0) cost[n][j] = cost[n][j + 1] + 1
        for (i in n - 1 downTo 0) for (j in m - 1 downTo 0) {
            val sub = cost[i + 1][j + 1] + if (expected[i] == heard[j]) 0 else 1
            cost[i][j] = minOf(sub, cost[i + 1][j] + 1, cost[i][j + 1] + 1)
        }
        val pairing = arrayOfNulls<Int>(n)
        var i = 0; var j = 0
        while (i < n && j < m) {
            val sub = cost[i + 1][j + 1] + if (expected[i] == heard[j]) 0 else 1
            when {
                cost[i][j] == sub -> { if (expected[i] == heard[j]) pairing[i] = j; i += 1; j += 1 }
                cost[i][j] == cost[i + 1][j] + 1 -> i += 1
                else -> j += 1
            }
        }
        return pairing.toList()
    }

    /** Match key: case- and punctuation-insensitive ("Sure," ≡ "sure"). */
    fun normalized(s: String): String = buildString {
        for (ch in s.lowercase()) {
            val type = Character.getType(ch)
            if (ch.isLetterOrDigit() || type == Character.NON_SPACING_MARK.toInt() ||
                type == Character.COMBINING_SPACING_MARK.toInt() ||
                type == Character.LETTER_NUMBER.toInt() || type == Character.OTHER_NUMBER.toInt()) append(ch)
        }
    }
}
