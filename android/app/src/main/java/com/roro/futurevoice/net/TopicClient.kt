package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.UUID

/** `topic-engine` — categorize a typed scenario (prompt server-side). */
class TopicClient(private val auth: AuthRepository) {

    @Serializable
    data class CategoryResult(
        val category: String = "",
        val icon: String = "sparkles",
        val isNew: Boolean = false,
        val summary: String = "",
    )

    @Serializable
    private data class Body(
        val action: String = "categorize",
        val text: String,
        val existing: List<String>,
        val icon_options: List<String>,
        val target_language: String,
    )

    @Serializable private data class PartR(val text: String? = null)
    @Serializable private data class ContentR(val parts: List<PartR>? = null)
    @Serializable private data class CandidateR(val content: ContentR? = null)
    @Serializable private data class ApiResponse(val candidates: List<CandidateR>? = null)

    suspend fun categorize(
        text: String, existing: List<String>, iconOptions: List<String>, targetLanguage: String,
    ): CategoryResult = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(Config.functionUrl("topic-engine"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("X-Idempotency-Key", UUID.randomUUID().toString())
            .post(Edge.json.encodeToString(Body.serializer(),
                Body(text = text, existing = existing, icon_options = iconOptions,
                    target_language = targetLanguage))
                .toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            val joined = Edge.json.decodeFromString(ApiResponse.serializer(), raw)
                .candidates?.firstOrNull()?.content?.parts?.mapNotNull { it.text }
                ?.joinToString("").orEmpty()
            val body = Edge.extractJson(joined) ?: throw EdgeError.JsonNotFound(joined)
            Edge.json.decodeFromString(CategoryResult.serializer(), body)
        }
    }

    companion object {
        /** The composer's icon palette (`ScenarioComposerSheet.iconPalette` subset). */
        val ICON_PALETTE = listOf(
            "cup.and.saucer", "fork.knife", "cart", "briefcase", "stethoscope",
            "airplane", "house", "graduationcap", "phone", "person.2",
            "car", "banknote", "heart", "sparkles",
        )
    }
}
