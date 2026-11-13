package com.roro.futurevoice.data

/**
 * Where a transcript's words begin and end, for the TARGET language — port of
 * `WordSplitter.swift`.
 *
 * Every split on a space used to assume the language writes them. Japanese
 * doesn't, so a whole sentence was one "word": nothing could be highlighted,
 * no phrase could be matched and a talk counted as one word a minute. This is
 * the one place that knows which languages need a segmenter ([JapaneseMorph],
 * [ChineseMorph]) and which just split — and, for an unspaced one, WHICH
 * segmenter: every caller that cuts unspaced text asks here rather than
 * naming one.
 *
 * Only for text in the TARGET language — never for chrome or coaching.
 */
object WordSplitter {

    /** True when words are separated by spaces, so joining them needs one. */
    fun spaced(language: String): Boolean = LanguageCatalog.writesSpaces(language)

    /** The words of [text], punctuation dropped for an unspaced language (a
     *  spaced one keeps it attached, as it always has). */
    fun words(text: String, language: String): List<String> =
        if (spaced(language)) text.split(Regex("\\s+")).filter { it.isNotEmpty() }
        else segments(text, language)

    // ── Unspaced languages ──

    /** Chinese rather than Japanese — the two unspaced targets. */
    fun isChinese(language: String): Boolean = language.substringBefore('-') == "zh"

    /** The segmenter's words of unspaced text, punctuation dropped. */
    fun segments(text: String, language: String): List<String> =
        if (isChinese(language)) ChineseMorph.segments(text) else JapaneseMorph.segments(text)

    /** Each segment with where it sits in [text]: (surface, start, end). */
    fun segmentRanges(text: String, language: String): List<Triple<String, Int, Int>> =
        if (isChinese(language)) ChineseMorph.words(text).map { Triple(it.surface, it.start, it.end) }
        else JapaneseMorph.words(text).map { Triple(it.surface, it.start, it.end) }

    /** Words and the punctuation between them; concatenated, the text back. */
    fun displayPieces(text: String, language: String): List<JapaneseMorph.Piece> =
        if (isChinese(language)) ChineseMorph.displayPieces(text) else JapaneseMorph.displayPieces(text)

    /** Every wordlist headword said in [text], with its span. */
    fun headwords(text: String, language: String): List<Triple<String, Int, Int>> =
        if (isChinese(language)) ChineseMorph.headwords(text, CoreVocabulary.set(language))
        else JapaneseMorph.headwords(text, CoreVocabulary.set(language), CoreVocabulary.forms(language))

    /** The notebook key of every [displayPieces] piece ("" for none). */
    fun pieceKeys(text: String, language: String): List<String> =
        if (isChinese(language)) ChineseMorph.pieceKeys(text, CoreVocabulary.set(language))
        else JapaneseMorph.pieceKeys(text, CoreVocabulary.set(language), CoreVocabulary.forms(language))

    /** A particle or filler — grammar, never a word to hint, study or credit. */
    fun isFunctionToken(token: String, language: String): Boolean =
        if (isChinese(language)) ChineseMorph.isFunctionToken(token) else JapaneseMorph.isFunctionToken(token)

    fun count(text: String, language: String): Int = words(text, language).size

    /**
     * The words a TIMELINE is cut into — what karaoke lights, a tap selects
     * and a rhythm mark sits under. Unlike [words], nothing is dropped:
     * punctuation rides on the word before it (an opening bracket on the word
     * after), so the words joined back give the line itself, which is what
     * the shadow screen draws from them.
     */
    fun timingWords(text: String, language: String): List<String> {
        if (spaced(language)) {
            return text.split(Regex("\\s+")).filter { it.isNotEmpty() }
        }
        val out = ArrayList<String>()
        var leading = ""
        for (piece in displayPieces(text, language)) {
            val t = piece.text.filterNot { it.isWhitespace() }
            if (t.isEmpty()) continue
            if (piece.isWord) {
                out.add(leading + t)
                leading = ""
                continue
            }
            for (ch in t) {
                if (ch in OPENING || out.isEmpty()) leading += ch
                else out[out.size - 1] = out[out.size - 1] + ch
            }
        }
        if (leading.isNotEmpty()) {
            if (out.isEmpty()) out.add(leading) else out[out.size - 1] = out[out.size - 1] + leading
        }
        return out
    }

    /** Brackets that belong to the word AFTER them. */
    private val OPENING = setOf('「', '『', '（', '(', '【', '〈', '《', '［', '[', '“', '‘')

    /** One notebook entry or several? A spaced language can hold a two-word
     *  chunk the learner tapped; an unspaced one keys by segment. */
    fun isSingleWord(text: String, language: String): Boolean =
        if (spaced(language)) !text.contains(" ") else segments(text, language).size <= 1

    /** Leading snippet for a title — the first few words, or the first few
     *  characters where words aren't delimited. */
    fun snippet(text: String, language: String, maxWords: Int, maxChars: Int): String {
        if (spaced(language)) {
            val ws = text.split(" ").filter { it.isNotEmpty() }
            val head = ws.take(maxWords).joinToString(" ")
            return if (ws.size > maxWords) "$head…" else head
        }
        return if (text.length > maxChars) text.take(maxChars) + "…" else text
    }
}
