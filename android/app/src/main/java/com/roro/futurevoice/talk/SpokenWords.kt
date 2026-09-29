package com.roro.futurevoice.talk

/**
 * A line as MOUTHS produced it, not as a transcriber wrote it down.
 *
 * Punctuation, capitalization, spelling and contraction choice all come from
 * the recognizer, never from the speaker — so a correction built on any of
 * them tells someone they made a mistake they did not make, in their own
 * voice, mid-call. Both the drop filter and the highlight compare through
 * here.
 */
object SpokenWords {
    fun of(text: String): List<String> {
        var s = text.lowercase().replace('’', '\'')
        for ((contracted, expanded) in SpokenWordsContent.contractions) {
            s = s.replace(contracted, expanded)
        }
        // Everything that isn't a letter, digit or space is the transcriber's.
        val kept = buildString { for (c in s) append(if (c.isLetterOrDigit()) c else ' ') }
        return kept.split(' ').filter { it.isNotEmpty() }
    }

    /**
     * True when the suggestion's only change is one no mouth can produce.
     * Deliberately narrow: a mixed suggestion that fixes something real AND
     * happens to contract still survives.
     */
    fun saysTheSameThing(a: String, b: String, language: String = "en"): Boolean {
        if (language.startsWith("ja")) {
            // The SCRIPT is the transcriber's choice, like punctuation. This
            // folds what it can — katakana against hiragana, a romaji name
            // against its kana — but not kanji against kana (分かった /
            // わかった), which needs a reading Android has no way to produce.
            // The prompt's own ASR SCRIPT GUARD carries that half.
            val ja = com.roro.futurevoice.data.JapaneseMorph::soundSpelling
            return ja(a.filter { it.isLetterOrDigit() }) == ja(b.filter { it.isLetterOrDigit() })
        }
        // Digits spelled out (the recognizer writes "3" for "three") and, in
        // Korean, word spacing folded away: 띄어쓰기 is the transcriber's
        // (한번 / 한 번), so a rewrite that only re-spaces changes nothing.
        return comparable(a, language).let { it.isNotEmpty() && it == comparable(b, language) }
    }

    private fun comparable(text: String, language: String): String {
        val words = of(ShadowScore.expandForDiff(text, language))
        return words.joinToString(if (language.substringBefore('-') == "ko") "" else " ")
    }

    /**
     * Korean only: the "fix" puts the SAME words in another order. Spoken
     * Korean orders freely ("먹었어, 아까 라면") — an afterthought, not a slip.
     * In English a reorder can be a real correction, so no other language.
     */
    fun changesOnlyWordOrder(a: String, b: String, language: String): Boolean {
        if (language.substringBefore('-') != "ko") return false
        val left = of(ShadowScore.expandForDiff(a, "ko"))
        val right = of(ShadowScore.expandForDiff(b, "ko"))
        if (left.size < 2 || left == right) return false
        return left.sorted() == right.sorted()
    }

    /**
     * Is [quote] something the learner actually said in [line]? The model
     * quotes loosely, so: contained after normalizing, contained with spaces
     * compared away (Korean spacing is the recognizer's; Japanese has none),
     * or three words in four shared (iOS `ConversationEngine.quotes`).
     */
    fun quotes(quote: String, line: String): Boolean {
        val needle = CarryoverDetector.normalized(quote)
        val hay = CarryoverDetector.normalized(line)
        if (needle.isEmpty()) return false
        if (hay.contains(needle)) return true
        val squeezed = needle.replace(" ", "")
        if (squeezed.isNotEmpty() && hay.replace(" ", "").contains(squeezed)) return true
        val words = needle.split(' ').filter { it.isNotEmpty() }.toSet()
        if (words.size < 3) return false
        val have = hay.split(' ').filter { it.isNotEmpty() }.toSet()
        return words.intersect(have).size.toDouble() / words.size >= 0.75
    }

    /**
     * Which display tokens of [alternative] actually changed against
     * [original]. A token is marked only when EVERY comparison word inside it
     * went unmatched, so "I'm" against "I am" lights up nothing.
     */
    fun changedTokens(alternative: String, original: String): List<Boolean> {
        val tokens = alternative.split(" ").filter { it.isNotEmpty() }
        val a = ArrayList<String>()
        val owner = ArrayList<Int>()
        tokens.forEachIndexed { idx, token -> of(token).forEach { a.add(it); owner.add(idx) } }
        val o = of(original)
        val m = a.size; val n = o.size
        // Longest common subsequence: what survived the rewrite.
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in m - 1 downTo 0) for (j in n - 1 downTo 0) {
            dp[i][j] = if (a[i] == o[j]) dp[i + 1][j + 1] + 1 else maxOf(dp[i + 1][j], dp[i][j + 1])
        }
        val kept = BooleanArray(m)
        var i = 0; var j = 0
        while (i < m && j < n) {
            when {
                a[i] == o[j] -> { kept[i] = true; i++; j++ }
                dp[i + 1][j] >= dp[i][j + 1] -> i++
                else -> j++
            }
        }
        val hasWord = BooleanArray(tokens.size)
        val changed = BooleanArray(tokens.size)
        owner.forEachIndexed { position, tokenIndex ->
            hasWord[tokenIndex] = true
            if (!kept[position]) changed[tokenIndex] = true
        }
        // A token with no words in it is punctuation — never highlighted.
        return tokens.indices.map { changed[it] && hasWord[it] }
    }
}
