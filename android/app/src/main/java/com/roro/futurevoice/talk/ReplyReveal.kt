package com.roro.futurevoice.talk

/**
 * The fluent self's line is SHOWN as it is HEARD (iOS `ReplyReveal`, 2026-10-10).
 *
 * The gateway announces a line at its first written token and streams the
 * text from there — but most turns adopt a speculative reply, whose text is
 * already complete, so the whole line landed on screen at once and the voice
 * followed ~1 s later (synthesis only starts once the turn is committed).
 * Read as "it writes everything, then thinks again, then talks". So the text
 * is held until the voice is audible and then revealed a SENTENCE at a time,
 * each one when its audio should be starting.
 *
 * Sentence timing is an estimate: the PCM stream carries no alignment. The
 * rate is the line's own once all of its audio is in (letters ÷ seconds of
 * audio received), a per-script default before that.
 */
object ReplyReveal {
    /** A sentence is shown this much before its estimated start, so the eye
     *  is never behind the ear. */
    const val LEAD_SECONDS = 0.2

    /** The prefix of [text] to show [elapsed] seconds into the voice. Only
     *  complete sentences are shown while the line is still being written;
     *  the unterminated tail joins once [isFinal]. */
    fun visible(text: String, isFinal: Boolean, elapsed: Double, charactersPerSecond: Double): String {
        val ends = sentenceEnds(text).toMutableList()
        if (isFinal && ends.lastOrNull() != text.length &&
            text.substring(ends.lastOrNull() ?: 0).isNotBlank()) {
            ends.add(text.length)
        }
        if (ends.isEmpty() || charactersPerSecond <= 0) return ""
        var shownEnd = ends[0]
        for (end in ends.drop(1)) {
            // This sentence starts where the previous one ended.
            val before = weight(text.substring(0, shownEnd))
            if (before / charactersPerSecond > elapsed + LEAD_SECONDS) break
            shownEnd = end
        }
        return text.substring(0, shownEnd).trim()
    }

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
