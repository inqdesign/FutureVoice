package com.roro.futurevoice.core

import android.content.Context
import androidx.core.content.edit
import com.roro.futurevoice.BuildConfig
import java.security.MessageDigest
import java.util.UUID

/**
 * Android mirror of iOS `Secrets.swift`.
 *
 * Only Supabase values live here. Every provider call goes through an Edge
 * Function, so the app never holds a Google or ElevenLabs key — see
 * `docs/contracts/edge-api.md`.
 */
object Config {
    val supabaseUrl: String = BuildConfig.SUPABASE_URL
    val supabaseAnonKey: String = BuildConfig.SUPABASE_ANON_KEY

    val isConfigured: Boolean
        get() = supabaseUrl.isNotBlank() && supabaseAnonKey.isNotBlank()

    fun functionUrl(name: String): String = "${supabaseUrl.trimEnd('/')}/functions/v1/$name"

    /**
     * The realtime Talk gateway (`gateway/` in this repo — a Cloudflare
     * Worker + Durable Object). ONE WebSocket per call; the gateway meters
     * the call itself through `talk-tick` with the caller's own JWT, so the
     * app never ticks on this path. Same URL iOS ships with.
     */
    const val gatewayUrl: String = "wss://futurevoice-gateway.futurevoice-gateway.workers.dev/call"
}

/**
 * Per-install salt for deterministic TTS idempotency keys.
 *
 * Same reasoning as iOS: the same (text, voice) from this install always sends
 * the same key, so a double-fired play or a retry dedupes to ONE charge
 * server-side. Salted per install so keys can never collide across users on
 * shared preset voices; a reinstall (which also loses the audio cache) simply
 * starts fresh.
 */
object InstallSalt {
    private const val PREFS = "futurevoice"
    private const val KEY = "futurevoice.ttsIdemSalt"

    @Volatile
    private var cached: String? = null

    fun init(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY, null)
        cached = existing ?: UUID.randomUUID().toString().also { prefs.edit { putString(KEY, it) } }
    }

    fun value(): String = cached ?: "unsalted"

    /**
     * `tts:<salt>:<sha256(voiceId|timestamps|text)[0..12] hex>`.
     *
     * The timestamps flag is inside the hash on purpose: plain and karaoke
     * syntheses are separate billable actions and must not dedupe against
     * each other.
     */
    fun ttsKey(text: String, voiceId: String, timestamps: Boolean): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$voiceId|$timestamps|$text".toByteArray())
        val hex = digest.take(12).joinToString("") { "%02x".format(it) }
        return "tts:${value()}:$hex"
    }
}
