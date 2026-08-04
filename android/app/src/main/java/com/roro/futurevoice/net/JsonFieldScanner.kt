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
}
