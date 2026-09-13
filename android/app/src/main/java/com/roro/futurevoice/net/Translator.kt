package com.roro.futurevoice.net

import android.content.Context
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File

/**
 * Coaching text in the learner's own language, on demand: why a correction is
 * a correction. The server writes it (the `translate` edge function, the same
 * one iOS calls) and the answer is cached on disk — the same sentence pair
 * always explains the same way, and the learner who taps twice should not
 * wait twice.
 */
object Translator {
    @Serializable private data class Response(val text: String = "")

    private var memory: MutableMap<String, String>? = null

    private fun file(c: Context) = File(c.filesDir, "translations.json")

    private fun load(c: Context): MutableMap<String, String> = memory ?: runCatching {
        Edge.json.decodeFromString<Map<String, String>>(file(c).readText()).toMutableMap()
    }.getOrDefault(mutableMapOf()).also { memory = it }

    private fun key(original: String, alternative: String, lang: String) =
        lang + "" + original + "" + alternative

    /** What is already on disk, with no network — so a tap can answer at once. */
    fun cachedExplanation(c: Context, original: String, alternative: String, lang: String): String? =
        load(c)[key(original, alternative, lang)]

    suspend fun explainCorrection(
        c: Context, original: String, alternative: String, lang: String,
    ): String? = withContext(Dispatchers.IO) {
        val k = key(original, alternative, lang)
        load(c)[k]?.let { return@withContext it }
        val body = buildJsonObject {
            put("kind", "explain"); put("original", original)
            put("alternative", alternative); put("to_lang", lang)
        }
        val text = runCatching {
            val req = Request.Builder().url(Config.functionUrl("translate"))
                .header("Authorization", "Bearer ${AuthRepository().accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(req).execute().use { r ->
                if (r.code !in 200..299) null
                else Edge.json.decodeFromString(Response.serializer(), r.body.string())
                    .text.trim().takeIf { it.isNotEmpty() }
            }
        }.getOrNull() ?: return@withContext null
        val map = load(c)
        map[k] = text
        runCatching { file(c).writeText(Edge.json.encodeToString(map.toMap())) }
        text
    }
}
