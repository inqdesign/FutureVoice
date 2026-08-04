package com.roro.futurevoice.net

import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/**
 * Shared transport for the Supabase Edge Functions.
 *
 * Contract: `docs/contracts/edge-api.md`. Every request carries the caller's
 * Supabase access token plus an `X-Idempotency-Key`; the ledger dedupes CHARGES
 * on that key, so retrying the same logical request is free.
 */
object Edge {

    val json: Json = Json {
        ignoreUnknownKeys = true
        // Mirrors Swift's encodeIfPresent: a null field is omitted entirely,
        // which is what Gemini's part union expects (a text part must carry no
        // "inlineData" key, and vice versa).
        explicitNulls = false
        encodeDefaults = true
    }

    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(40, TimeUnit.SECONDS)
        .writeTimeout(40, TimeUnit.SECONDS)
        // Streamed responses (SSE turns, PCM audio) outlive any single call
        // budget — the per-read timeout above is the real guard.
        .callTimeout(0, TimeUnit.MILLISECONDS)
        .retryOnConnectionFailure(true)
        .build()

    /** First `{` … last `}`. Same tolerant extraction iOS uses. */
    fun extractJson(text: String): String? {
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start < 0 || end < 0 || start > end) return null
        return text.substring(start, end + 1)
    }
}

sealed class EdgeError(message: String) : Exception(message) {
    object InvalidResponse : EdgeError("Invalid response")
    class Http(val status: Int, val body: String) : EdgeError("HTTP $status: $body")
    class JsonNotFound(val raw: String) : EdgeError("No JSON found in reply: ${raw.take(200)}")

    /** 402 — surface the credit copy, never a raw error. */
    object InsufficientCredits :
        EdgeError("You're out of credits. Check your plan under Me → Account.")

    /** `finishReason == MAX_TOKENS` AND the payload failed to parse. */
    object Truncated : EdgeError("Reply hit the token ceiling before it finished")
}
