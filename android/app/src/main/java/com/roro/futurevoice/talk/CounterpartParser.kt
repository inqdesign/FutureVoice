package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.Serializable

/**
 * The learner's free-spoken description of someone they know → a structured
 * [Counterpart] (iOS `CounterpartParser.parse`). Voice + a parse is far less
 * friction than four form fields, and people say more in their own language.
 * Every field comes back in the NATIVE language: it is their own note about
 * their own friend. Public figures go through [PublicFigureLookup] instead.
 */
object CounterpartParser {
    @Serializable
    private data class Payload(
        val name: String = "",
        val relationship: String = "",
        val location: String? = null,
        val how_we_met: String? = null,
        val background: String = "",
        val conversation_style: String = "",
        val common_topics: String? = null,
    )

    suspend fun parse(spokenDescription: String, languageHint: String, nativeLanguage: String): Counterpart {
        val user = "language_hint: $languageHint\nspoken_description:\n$spokenDescription"
        val p = GeminiClient(AuthRepository()).sendJson(
            system = CounterpartParsePrompt.system(LanguageCatalog.englishName(nativeLanguage)),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
            serializer = Payload.serializer(),
            model = GeminiClient.Model.FLASH_LITE_31,
            // Six free-text fields, all in the native language.
            maxTokens = 1500,
            purpose = "parse",
        )
        return Counterpart(
            name = p.name,
            relationship = p.relationship,
            location = p.location.orEmpty(),
            howWeMet = p.how_we_met.orEmpty(),
            background = p.background,
            conversationStyle = p.conversation_style,
            commonTopics = p.common_topics.orEmpty(),
        )
    }
}
