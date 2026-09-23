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

/** One word's span in the played line — what karaoke highlights. */
data class WordTiming(val word: String, val startMs: Int, val endMs: Int)

/**
 * Karaoke timings WITHOUT a second synthesis: spans are estimated from the
 * audio's own duration, split proportionally to how much text each word
 * carries (`ShadowDrillView.estimatedTimings`). Cached audio therefore
 * karaokes for free — the rule is cache first, timings from free
 * alignment/estimation, never a duplicate paid synthesis.
 */
object WordTimings {
    fun estimate(text: String, durationMs: Int, language: String = "en"): List<WordTiming> {
        // The timeline is cut into the language's OWN words: punctuation
        // rides along so the words joined back give the line itself.
        val words = com.roro.futurevoice.data.WordSplitter.timingWords(text, language)
        if (words.isEmpty() || durationMs <= 0) return emptyList()
        val totalChars = words.sumOf { maxOf(it.length, 1) }
        val msPerChar = durationMs.toDouble() / totalChars
        var cursor = 0.0
        return words.map { w ->
            val start = cursor
            cursor += msPerChar * maxOf(w.length, 1)
            // Small trailing gap so adjacent highlights read as distinct words.
            WordTiming(w, start.toInt(), maxOf(start.toInt() + 1, cursor.toInt() - 20))
        }
    }

    /** Which word index is being spoken at [positionMs], or -1. */
    fun indexAt(timings: List<WordTiming>, positionMs: Int): Int =
        timings.indexOfFirst { positionMs in it.startMs..it.endMs }
}
