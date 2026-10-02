package com.roro.futurevoice.talk

import com.roro.futurevoice.data.WordSplitter

/**
 * ElevenLabs' character alignment (`with-timestamps`) → one timed window per
 * word of the line — port of iOS `ElevenLabsClient.wordTimings(from:…)`,
 * `groupedIntoWords` and `alignmentMatches`. These are the MEASURED onsets a
 * shadow take is graded against: the synthesizer reports where each
 * character of the audio it made actually falls.
 */
object TtsAlignment {

    /**
     * Group consecutive non-space characters into words; for a language
     * written without spaces, gather them into the line's own timing words
     * (`WordSplitter.timingWords`) instead, or a Japanese line comes back as
     * one timed run.
     */
    fun wordTimings(
        chars: List<String>, starts: List<Double>, ends: List<Double>, language: String,
    ): List<WordTiming> {
        if (chars.size != starts.size || chars.size != ends.size) return emptyList()
        if (!WordSplitter.spaced(language)) {
            groupedIntoWords(chars, starts, ends, language)?.let { return it }
        }
        val out = ArrayList<WordTiming>()
        val current = StringBuilder()
        var s = 0.0; var e = 0.0
        fun flush() {
            if (current.isNotEmpty()) {
                out += WordTiming(current.toString(), Math.round(s * 1000).toInt(), Math.round(e * 1000).toInt())
                current.clear()
            }
        }
        for (i in chars.indices) {
            if (chars[i].isBlank()) { flush(); continue }
            if (current.isEmpty()) s = starts[i]
            current.append(chars[i]); e = ends[i]
        }
        flush()
        return out
    }

    private fun groupedIntoWords(
        chars: List<String>, starts: List<Double>, ends: List<Double>, language: String,
    ): List<WordTiming>? {
        val words = WordSplitter.timingWords(chars.joinToString(""), language)
        if (words.isEmpty()) return null
        val out = ArrayList<WordTiming>()
        var i = 0
        for (word in words) {
            val spelled = StringBuilder()
            var first = -1; var last = 0
            while (spelled.length < word.length && i < chars.size) {
                val c = chars[i]
                if (c.isNotBlank()) {
                    if (first < 0) first = i
                    spelled.append(c); last = i
                }
                i += 1
            }
            if (spelled.toString() != word || first < 0) return null
            out += WordTiming(word, Math.round(starts[first] * 1000).toInt(), Math.round(ends[last] * 1000).toInt())
        }
        return out
    }

    /**
     * True when a timing set really spells out [text] — same characters,
     * ignoring spaces, case and punctuation. What this must catch is a
     * normalized (romanized) alignment being shown as the target sentence.
     */
    fun alignmentMatches(text: String, timings: List<WordTiming>): Boolean {
        if (timings.isEmpty()) return false
        return LocalAlignment.normalized(timings.joinToString("") { it.word }) == LocalAlignment.normalized(text)
    }
}
