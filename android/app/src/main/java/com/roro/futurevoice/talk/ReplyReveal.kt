package com.roro.futurevoice.talk

/**
 * The fluent self's line is SHOWN as it is HEARD (iOS `ReplyReveal`, 2026-10-10).
 *
 * The gateway announces a line at its first written token and streams the
 * text from there — but most turns adopt a speculative reply, whose text is
 * already complete, so the whole line landed on screen at once and the voice
 * followed ~1 s later (synthesis only starts once the turn is committed).
 * Read as "it writes everything, then thinks again, then talks". So the text
 * is held until the voice is audible and then revealed a WORD at a time, each
 * one when its audio should be starting (2026-10-13, founder: a sentence
 * dropping in whole read as stiff beside other voice chats). Unspaced
 * scripts (ja, zh) go a character at a time.
 *
 * Word timing is an estimate: the PCM stream carries no alignment. The rate
 * is the line's own once all of its audio is in (letters ÷ seconds of voice,
 * the gaps between sentences taken out), a per-script default before that;
 * each sentence boundary costs [SENTENCE_PAUSE_SECONDS]. Only complete
 * sentences are ever revealed into while the line is still being written.
 */
object ReplyReveal {
    /** A word is shown this much before its estimated start, so the eye is
     *  never behind the ear. */
    const val LEAD_SECONDS = 0.15

    /** The silence between two sentences of one line. */
    const val SENTENCE_PAUSE_SECONDS = 0.4

    /** The prefix of [text] to show [elapsed] seconds into the voice. Only
     *  complete sentences are revealed into while the line is still being
     *  written; the unterminated tail joins once [isFinal]. */
    fun visible(text: String, isFinal: Boolean, elapsed: Double, charactersPerSecond: Double): String {
        val ends = sentenceEnds(text).toMutableList()
        if (isFinal && ends.lastOrNull() != text.length &&
            text.substring(ends.lastOrNull() ?: 0).isNotBlank()) {
            ends.add(text.length)
        }
        val limit = ends.lastOrNull() ?: return ""
        if (charactersPerSecond <= 0) return ""
        var shownEnd = 0
        var sentence = 0
        for ((start, end) in units(text.substring(0, limit))) {
            while (sentence < ends.size && ends[sentence] <= start) sentence++
            val startsAt = weight(text.substring(0, start)) / charactersPerSecond +
                sentence * SENTENCE_PAUSE_SECONDS
            if (startsAt > elapsed + LEAD_SECONDS) break
            shownEnd = end
        }
        return text.substring(0, shownEnd).trim()
    }

    /** The line's own letters per second once all of its audio is in: the
     *  sentence gaps are silence, not speech. */
    fun charactersPerSecond(text: String, seconds: Double): Double? {
        val ends = sentenceEnds(text)
        // The last sentence has no space after it, so it isn't in `ends`.
        val tail = text.substring(ends.lastOrNull() ?: 0)
        val sentences = ends.size + (if (weight(tail) > 0) 1 else 0)
        val speaking = seconds - maxOf(0, sentences - 1) * SENTENCE_PAUSE_SECONDS
        val w = weight(text)
        if (speaking <= 0.5 || w <= 0) return null
        return w / speaking
    }

    /** The pieces revealed one at a time: a word with whatever punctuation
     *  and space trail it, or — in an unspaced script — one character. */
    fun units(text: String): List<Pair<Int, Int>> {
        val out = mutableListOf<Pair<Int, Int>>()
        var i = 0
        while (i < text.length) {
            while (i < text.length && text[i].isWhitespace()) i++
            if (i >= text.length) break
            val start = i
            if (isUnspaced(text[i])) {
                i++
            } else {
                while (i < text.length && !text[i].isWhitespace() && !isUnspaced(text[i])) i++
            }
            // Punctuation that closes the piece rides with it.
            while (i < text.length && !text[i].isWhitespace() && !text[i].isLetterOrDigit()) i++
            out.add(start to i)
        }
        return out
    }

    /** Kana and Han: no spaces between words, so each character is a piece. */
    private fun isUnspaced(c: Char): Boolean = c.code in 0x3040..0x30FF || c.code in 0x4E00..0x9FFF

    /** End index of every COMPLETE sentence: a Latin terminator followed by
     *  whitespace, or a CJK one (which needs no space after it). Closing
     *  quotes and brackets ride with the sentence they close. */
    fun sentenceEnds(text: String): List<Int> {
        val closers = setOf(')', '"', '\'', '”', '’', '」', '』')
        val ends = mutableListOf<Int>()
        var i = 0
        while (i < text.length) {
            val c = text[i]
            val cjk = c in "。！？"
            if (!cjk && c !in ".!?…") { i++; continue }
            var j = i + 1
            while (j < text.length && (text[j] in ".!?…。！？" || text[j] in closers)) j++
            if (cjk || (j < text.length && text[j].isWhitespace())) ends.add(j)
            i = j
        }
        return ends
    }

    /** What takes time to say: letters and digits, not spaces or punctuation. */
    fun weight(s: CharSequence): Int = s.count { it.isLetterOrDigit() }

    /** Letters per second before the line's own audio has said. Hangul and
     *  kana/kanji carry a syllable each; Latin letters are a fraction of one.
     *  Scaled by the learner's speech speed (0.85–1.0). */
    fun defaultCharactersPerSecond(text: String, speed: Double): Double {
        val syllabic = text.any { c ->
            c.code in 0xAC00..0xD7A3 ||    // Hangul
                c.code in 0x3040..0x30FF || // kana
                c.code in 0x4E00..0x9FFF    // CJK ideographs
        }
        return (if (syllabic) 7.0 else 14.0) * speed
    }
}
