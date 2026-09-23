package com.roro.futurevoice.data

/**
 * Where a transcript's words begin and end, for the TARGET language — port of
 * `WordSplitter.swift`.
 *
 * Every split on a space used to assume the language writes them. Japanese
 * doesn't, so a whole sentence was one "word": nothing could be highlighted,
 * no phrase could be matched and a talk counted as one word a minute. This is
 * the one place that knows which languages need a segmenter and which just
 * split.
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
        else JapaneseMorph.segments(text)

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
        for (piece in JapaneseMorph.displayPieces(text)) {
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
        if (spaced(language)) !text.contains(" ") else JapaneseMorph.segments(text).size <= 1

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
