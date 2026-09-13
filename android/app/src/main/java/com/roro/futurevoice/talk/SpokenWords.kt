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
    fun saysTheSameThing(a: String, b: String): Boolean = of(a) == of(b)

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
