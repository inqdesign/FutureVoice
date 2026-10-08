package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * One voice change per 30 days after the first voice (iOS
 * `VoiceChangeStatus`, 2026-10-09).
 *
 * Every voice the account adds costs one of ElevenLabs' monthly add/edits,
 * and deleting gives nothing back. So a re-record, a saved accent, "no
 * accent" or "regenerate from saved recording" is ONE change, and there is
 * one per rolling 30 days. Listening to takes is free. The server is the
 * judge (`voice_change_status`, `_shared/voice-changes.ts`); this is its
 * answer, read so every button that would make a voice can say so BEFORE
 * the learner spends a minute reading a script or half a minute on takes.
 */
data class VoiceChangeStatus(
    /** Changes still allowed now (0 or 1). */
    val left: Int,
    /** When one comes back (epoch ms); null while one is available. */
    val nextAt: Long?,
) {
    val canChange: Boolean get() = left > 0

    companion object {
        /** Said under a disabled control and as the server's refusal. The
         *  date is month + day in the APP language ([context]'s locale). */
        fun againLine(context: Context, nextAt: Long?): String {
            nextAt ?: return context.getString(R.string.voice_change_already)
            val locale = context.resources.configuration.locales[0]
            val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMMd")
            val day = java.text.SimpleDateFormat(pattern, locale).format(java.util.Date(nextAt))
            return context.getString(R.string.voice_change_again_from, day)
        }

        /** Added to every confirmation that would make a new voice. */
        fun usesItLine(context: Context): String = context.getString(R.string.voice_change_uses_it)

        /** ISO 8601 (any fraction) or Postgres' own text form
         *  ("2026-11-08 10:00:00.123+00"). */
        fun parse(s: String): Long? {
            var t = s.trim().replace(' ', 'T')
            if (Regex("[+-]\\d\\d$").containsMatchIn(t)) t += ":00"
            return runCatching { java.time.OffsetDateTime.parse(t).toInstant().toEpochMilli() }.getOrNull()
                ?: runCatching { java.time.Instant.parse(t).toEpochMilli() }.getOrNull()
        }
    }
}

/** The 403 `voice_change_limit` a clone or a remix save answers with once
 *  the month's change is used. Not a failure: a date. */
class VoiceChangeLimit(val nextAt: Long?) : Exception("voice_change_limit") {
    fun line(context: Context): String = VoiceChangeStatus.againLine(context, nextAt)

    companion object {
        /** The typed error for a response body, or null when it isn't one. */
        fun from(status: Int, body: String): VoiceChangeLimit? {
            if (status != 403 || !body.contains("voice_change_limit")) return null
            val next = runCatching {
                (StoreJson.json.parseToJsonElement(body).jsonObject["next_at"] as? JsonPrimitive)?.contentOrNull
            }.getOrNull()
            return VoiceChangeLimit(next?.let { VoiceChangeStatus.parse(it) })
        }
    }
}

/**
 * The learner's allowance as last read (iOS `AppState.voiceChangeStatus`),
 * null until first read. Every control that would make a new voice reads it.
 */
object VoiceChanges {
    private val _status = MutableStateFlow<VoiceChangeStatus?>(null)
    val status: StateFlow<VoiceChangeStatus?> = _status.asStateFlow()

    /** True unless the server said no change is left. */
    val canChange: Boolean get() = _status.value?.canChange ?: true

    /**
     * Read the allowance from the server. Called where a voice can be changed
     * (meet act, Me → Voice, the accent sheet, revival) and after any voice
     * is made. Silent on failure: the server still decides.
     */
    suspend fun refresh() {
        // Captures: draws every voice control locked (iOS `-voiceChangesLeft`).
        com.roro.futurevoice.capture.flags.MeCaptureFlags.voiceChangesLeft?.let { left ->
            _status.value = VoiceChangeStatus(left,
                if (left > 0) null else System.currentTimeMillis() + 23L * 86_400_000)
            return
        }
        val token = runCatching { AuthRepository().accessToken() }.getOrNull() ?: return
        runCatching {
            val raw = withContext(Dispatchers.IO) {
                val request = okhttp3.Request.Builder()
                    .url("${com.roro.futurevoice.core.Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/voice_change_status")
                    .header("Authorization", "Bearer $token")
                    .header("apikey", com.roro.futurevoice.core.Config.supabaseAnonKey)
                    .post("{}".toRequestBody("application/json".toMediaType()))
                    .build()
                com.roro.futurevoice.net.Edge.client.newCall(request).execute().use { resp ->
                    val body = resp.body.string()
                    if (resp.code !in 200..299) error("HTTP ${resp.code}: ${body.take(200)}")
                    body
                }
            }
            val obj = StoreJson.json.parseToJsonElement(raw).jsonObject
            val left = (obj["left"] as? JsonPrimitive)?.intOrNull ?: return
            val next = (obj["next_at"] as? JsonPrimitive)?.contentOrNull?.let { VoiceChangeStatus.parse(it) }
            _status.value = VoiceChangeStatus(left, next)
        }.onFailure { android.util.Log.w("VoiceChanges", "voice change status failed", it) }
    }
}
