package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.Serializable
import java.io.File

/**
 * Rotating pool of free-talk greeting lines (`freetalk_openers.json`, the iOS
 * shape). One Gemini call writes six openers; sessions rotate through them,
 * so the first line of a free talk never waits on the model. Topic, scenario
 * and news openers stay dynamic — this pool is only for the no-topic talk.
 *
 * Keyed to language + persona name and regenerated when either changes.
 * Until a pool exists, [fallbackOpener] speaks; on the very first free talk,
 * before the fluent self has met the learner, [introOpener] outranks both —
 * a rotating "good to hear you" is a greeting between people who already
 * know each other.
 */
class FreeTalkOpeners(private val context: Context) {

    @Serializable
    private data class Pool(
        val key: String,
        val lines: List<String>,
        val cursor: Int = 0,
        @Serializable(with = com.roro.futurevoice.data.IsoDateMillisSerializer::class)
        val generatedAt: Long = System.currentTimeMillis(),
    )

    @Serializable
    private data class Payload(val openers: List<String> = emptyList())

    companion object {
        private fun key(language: String, personaName: String?) =
            language.take(2) + "|" + personaName.orEmpty().trim()

        fun introOpener(language: String): String =
            FreeTalkOpenerContent.intro[language.take(2)] ?: FreeTalkOpenerContent.intro.getValue("en")

        fun fallbackOpener(language: String): String =
            FreeTalkOpenerContent.fallback[language.take(2)] ?: FreeTalkOpenerContent.fallback.getValue("en")
    }

    private val file = File(context.filesDir, "freetalk_openers.json")

    fun hasPool(language: String, personaName: String?): Boolean =
        load()?.let { it.key == key(language, personaName) && it.lines.isNotEmpty() } == true

    /** The next line in rotation, advancing the cursor; null without a pool. */
    fun next(language: String, personaName: String?): String? {
        val pool = load() ?: return null
        if (pool.key != key(language, personaName) || pool.lines.isEmpty()) return null
        val line = pool.lines[pool.cursor % pool.lines.size]
        save(pool.copy(cursor = (pool.cursor + 1) % pool.lines.size))
        return line
    }

    suspend fun generatePool(language: String, personaName: String?, level: CefrLevel): List<String> {
        val name = personaName?.takeIf { it.isNotBlank() } ?: "the learner"
        val payload = GeminiClient(AuthRepository()).sendJson(
            system = FreeTalkOpenerContent.poolPrompt(
                LanguageCatalog.englishName(language), level.code.uppercase(), name),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, "Write the greetings.")),
            serializer = Payload.serializer(),
            model = GeminiClient.Model.FLASH_LITE_31,
            maxTokens = 512,
            purpose = "freetalk-openers",
            idempotencyKey = "freetalk-openers:" + key(language, personaName),
        )
        val lines = payload.openers.map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.isNotEmpty()) save(Pool(key(language, personaName), lines, cursor = 0))
        return lines
    }

    private fun load(): Pool? = runCatching {
        if (!file.exists()) null else StoreJson.json.decodeFromString(Pool.serializer(), file.readText())
    }.getOrNull()

    private fun save(pool: Pool) {
        runCatching { file.writeText(StoreJson.json.encodeToString(Pool.serializer(), pool)) }
    }
}
