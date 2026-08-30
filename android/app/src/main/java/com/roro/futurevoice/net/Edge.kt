package com.roro.futurevoice.net

import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import okhttp3.Authenticator
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
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
        // A 401 means the bearer token the SDK handed us is already retired
        // on the server (slept-through refresh, clock jump). Refresh the
        // session and retry ONCE with the new token; a second 401 stands.
        .authenticator(SessionAuthenticator)
        .build()

    private object SessionAuthenticator : Authenticator {
        override fun authenticate(route: Route?, response: Response): Request? {
            if (response.priorResponse != null) return null   // already retried once
            val fresh = runBlocking { AuthRepository().refreshAfterUnauthorized() } ?: return null
            return response.request.newBuilder()
                .header("Authorization", "Bearer $fresh")
                .build()
        }
    }

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

    /** 402 `insufficient_credits` — a FREE account's pool is spent → paywall. */
    object InsufficientCredits :
        EdgeError("Your talk time is used up. Check your plan under Me → Account.")

    /**
     * 402 `daily_cap_reached` — a SUBSCRIBER's allowance is spent. Never a
     * paywall: they already paid, the pool refills on its own.
     */
    object DailyCapReached :
        EdgeError("Your talk time for this period is used up. This call is saved.")

    companion object {
        /**
         * The ONE place a 402 body is read. iOS learned this the hard way
         * (`ElevenLabsError.wall(body:)`): the streamed and buffered paths each
         * parsed the body separately, and the one that forgot told a paying
         * subscriber they were out of credits.
         */
        fun wall(body: String): EdgeError =
            if (body.contains("daily_cap_reached")) DailyCapReached else InsufficientCredits
    }

    /** `finishReason == MAX_TOKENS` AND the payload failed to parse. */
    object Truncated : EdgeError("Reply hit the token ceiling before it finished")
}
