package com.roro.futurevoice.net

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/**
 * Reading the JSON a MODEL wrote (iOS `GeminiClient.decodeRepairing`,
 * `55aa93a`, 2026-09-28).
 *
 * Every summary failure with an excerpt in the week of 2026-09-25 was the
 * same thing: a native-language coaching field quoting target-language words
 * as `「"had"」` with the inner quotes unescaped — the shape
 * `CoachingLanguage.contract`'s own example shows. A retry sends the same
 * prompt and often gets the same slip (one talk failed five times running),
 * so the fix has to be on the reading side.
 *
 * A body that decodes is never touched, and a repair that still doesn't
 * decode throws the ORIGINAL error, so telemetry keeps describing what the
 * model actually wrote. Every place that decodes model-written JSON goes
 * through here — never `Edge.json.decodeFromString` on model text directly.
 */
object GeminiJson {

    fun <T> decode(serializer: DeserializationStrategy<T>, text: String, json: Json = Edge.json): T =
        try {
            json.decodeFromString(serializer, text)
        } catch (original: Exception) {
            val fixed = repairingInteriorQuotes(text) ?: throw original
            try {
                json.decodeFromString(serializer, fixed)
            } catch (_: Exception) {
                throw original
            }
        }

    /** The same rule for a caller that walks the tree itself (the summary). */
    fun parseObject(text: String): JsonObject =
        try {
            Json.parseToJsonElement(text).jsonObject
        } catch (original: Exception) {
            val fixed = repairingInteriorQuotes(text) ?: throw original
            try {
                Json.parseToJsonElement(fixed).jsonObject
            } catch (_: Exception) {
                throw original
            }
        }

    /**
     * Escapes `"` characters that sit INSIDE a JSON string value. Inside a
     * string, a quote is taken as the string's real end only when the next
     * non-space character is one JSON allows after a string (`,` `}` `]`
     * `:`) — and never when it touches a corner bracket (`「"had"」`), which
     * is the reported shape. Anything else is escaped. Returns null when
     * nothing needed escaping.
     */
    fun repairingInteriorQuotes(text: String): String? {
        val out = StringBuilder(text.length + 16)
        var inString = false
        var escaped = false
        var changed = false
        for (i in text.indices) {
            val c = text[i]
            if (!inString) {
                if (c == '"') inString = true
                out.append(c)
                continue
            }
            if (escaped) { escaped = false; out.append(c); continue }
            if (c == '\\') { escaped = true; out.append(c); continue }
            if (c != '"') { out.append(c); continue }
            val prev = if (i > 0) text[i - 1] else null
            var j = i + 1
            while (j < text.length && text[j].isWhitespace()) j++
            val next = if (j < text.length) text[j] else null
            val touchesBracket = prev == '「' || prev == '『' ||
                (i + 1 < text.length && (text[i + 1] == '」' || text[i + 1] == '』'))
            val endsString = next == null || next in ",}]:"
            if (endsString && !touchesBracket) {
                inString = false
                out.append(c)
            } else {
                out.append("\\\"")
                changed = true
            }
        }
        return if (changed) out.toString() else null
    }
}

/**
 * A header value OkHttp will actually SEND (iOS `GeminiClient.headerSafeKey`,
 * `6a9e866`). A key built from a learner's own text (the openers key carries
 * the persona name, e.g. "메이") is not ASCII, and OkHttp THROWS on such a
 * header value — the request never leaves the phone (on iOS URLSession dropped
 * it silently and the edge function answered 400 "missing X-Idempotency-Key";
 * no opener pool, ever, for a learner whose name isn't Latin). A non-ASCII key
 * goes out as its SHA-256, so the same logical request still maps to the same
 * key and the ledger's charge dedupe is unchanged.
 */
object IdempotencyKey {
    fun headerSafe(key: String): String {
        if (key.all { it in ' '..'~' }) return key
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest(key.toByteArray(Charsets.UTF_8))
        return "h:" + digest.joinToString("") { "%02x".format(it) }
    }
}
