package com.roro.futurevoice.net

/**
 * Pulls a top-level string field out of a JSON body that is STILL BEING
 * STREAMED, returning it only once its closing quote has arrived.
 *
 * This is why the fluent self starts speaking fast: the turn schema puts
 * `reply` first, so TTS fires the moment that field completes while the model
 * is still writing the suggestion and the transcript.
 *
 * Port of `GeminiClient.completedStringField`. See `docs/contracts/behavior.md` §3
 * — the rules here (nil for a non-string value, bail on a surrogate half) are
 * part of the contract, not implementation detail.
 */
object JsonFieldScanner {

    fun completedStringField(name: String, partial: String): String? {
        val keyIndex = partial.indexOf("\"$name\"")
        if (keyIndex < 0) return null
        var i = keyIndex + name.length + 2

        fun skipSpace() {
            while (i < partial.length && partial[i].isWhitespace()) i++
        }

        skipSpace()
        if (i >= partial.length || partial[i] != ':') return null
        i++
        skipSpace()
        // A non-string value (`null`, an object) must never read as a finished
        // string — that's how `"suggestion": null` used to fire early.
        if (i >= partial.length || partial[i] != '"') return null
        i++

        val out = StringBuilder()
        var escaped = false
        while (i < partial.length) {
            val c = partial[i]
            if (escaped) {
                when (c) {
                    'n' -> out.append('\n')
                    't' -> out.append('\t')
                    'r' -> out.append('\r')
                    '"' -> out.append('"')
                    '\\' -> out.append('\\')
                    '/' -> out.append('/')
                    'u' -> {
                        // \uXXXX. Surrogate halves can't be resolved one escape
                        // at a time — bail and let the fully decoded payload win.
                        val start = i + 1
                        val end = start + 4
                        if (end > partial.length) return null
                        val value = partial.substring(start, end).toIntOrNull(16) ?: return null
                        if (value in 0xD800..0xDFFF) return null
                        out.append(value.toChar())
                        i = end - 1
                    }
                    else -> out.append(c)
                }
                escaped = false
            } else when (c) {
                '\\' -> escaped = true
                '"' -> return out.toString()   // closing quote → field complete
                else -> out.append(c)
            }
            i++
        }
        return null      // still streaming
    }

    /**
     * Same scan as [completedStringField], but also reports a value still being
     * written (iOS `streamingStringField`): `second` says whether the closing
     * quote has arrived. Null until the field's opening quote is on the wire,
     * and for a non-string value; a value that opens a nested body is skipped.
     */
    fun streamingStringField(name: String, partial: String): Pair<String, Boolean>? {
        var searchFrom = 0
        scan@ while (true) {
            val keyIndex = partial.indexOf("\"$name\"", searchFrom)
            if (keyIndex < 0) return null
            var i = keyIndex + name.length + 2
            searchFrom = i
            while (i < partial.length && partial[i].isWhitespace()) i++
            if (i >= partial.length || partial[i] != ':') return null
            i++
            while (i < partial.length && partial[i].isWhitespace()) i++
            if (i >= partial.length || partial[i] != '"') return null
            i++
            val out = StringBuilder()
            var escaped = false
            while (i < partial.length) {
                val c = partial[i]
                if (escaped) {
                    when (c) {
                        'n' -> out.append('\n')
                        't' -> out.append('\t')
                        'r' -> out.append('\r')
                        '"' -> out.append('"')
                        '\\' -> out.append('\\')
                        '/' -> out.append('/')
                        'u' -> {
                            val start = i + 1
                            val end = start + 4
                            if (end > partial.length) return null
                            val value = partial.substring(start, end).toIntOrNull(16) ?: return null
                            if (value in 0xD800..0xDFFF) return null
                            out.append(value.toChar())
                            i = end - 1
                        }
                        else -> out.append(c)
                    }
                    escaped = false
                } else if (c == '\\') {
                    escaped = true
                } else if (c == '"') {
                    if (out.toString().trim().startsWith("{")) continue@scan
                    return out.toString() to true
                } else {
                    out.append(c)
                }
                i++
            }
            if (out.toString().trim().startsWith("{")) return null
            return out.toString() to false
        }
    }

    /** Below this (in [speakableWeight]) a value is not split: cutting "Sure."
     *  off the front of a short line buys nothing (iOS `minSpeakableSentence`). */
    private const val MIN_SPEAKABLE_SENTENCE = 25

    /** The first sentence of a still-streaming value, once it is unambiguously
     *  finished — a terminator FOLLOWED BY whitespace (iOS
     *  `firstSpeakableSentence`). */
    fun firstSpeakableSentence(partial: String): String? {
        val terminators = setOf('.', '!', '?', '。', '！', '？')
        var weight = 0
        for (i in partial.indices) {
            weight += speakableWeight(partial[i])
            if (partial[i] in terminators && weight >= MIN_SPEAKABLE_SENTENCE &&
                i + 1 < partial.length && partial[i + 1].isWhitespace()) {
                val sentence = partial.substring(0, i + 1).trim()
                return sentence.ifEmpty { null }
            }
        }
        return null
    }

    /** Hangul syllables, CJK ideographs and kana are whole syllables or words;
     *  Latin letters are a fraction of one. */
    private fun speakableWeight(c: Char): Int = when (c.code) {
        in 0xAC00..0xD7A3, in 0x1100..0x11FF, in 0x3130..0x318F, in 0x3040..0x30FF,
        in 0x3400..0x4DBF, in 0x4E00..0x9FFF -> 2
        else -> 1
    }
}
