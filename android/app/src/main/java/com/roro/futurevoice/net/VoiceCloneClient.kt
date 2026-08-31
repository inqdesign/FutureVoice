package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.util.UUID

/**
 * `elevenlabs-voice-clone` — multipart upload, contract in `edge-api.md`.
 * The first clone (and 24 h of onboarding retakes) is free server-side;
 * `remove_background_noise` is decided by the CALLER from the measured SNR,
 * never hardcoded (denoising a clean take shaves the cues that make a clone
 * recognizable).
 */
class VoiceCloneClient(private val auth: AuthRepository) {

    @Serializable
    private data class CloneResponse(val voice_id: String)

    class VoiceLimitReached : Exception("voice_limit_reached")

    suspend fun cloneVoice(
        name: String,
        sample: File,
        removeBackgroundNoise: Boolean,
        description: String? = null,
    ): String = withContext(Dispatchers.IO) {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("name", name)
            .apply { description?.let { addFormDataPart("description", it) } }
            .addFormDataPart("remove_background_noise", if (removeBackgroundNoise) "true" else "false")
            .addFormDataPart("files", sample.name, sample.asRequestBody("audio/wav".toMediaType()))
            .build()
        val request = Request.Builder()
            .url(Config.functionUrl("elevenlabs-voice-clone"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("X-Idempotency-Key", UUID.randomUUID().toString())
            .post(body)
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val text = resp.body.string()
            if (resp.code !in 200..299) {
                // Upstream 400 carrying voice_limit_reached is OUR capacity
                // problem — callers show a human message, not the JSON.
                if (text.contains("voice_limit_reached")) throw VoiceLimitReached()
                if (resp.code == 402) throw EdgeError.wall(text)
                throw EdgeError.Http(resp.code, text.take(512))
            }
            Edge.json.decodeFromString(CloneResponse.serializer(), text).voice_id
        }
    }
}
