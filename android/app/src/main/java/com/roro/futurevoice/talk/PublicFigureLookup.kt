package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.Serializable

/**
 * WHO a public figure is — and nothing else (iOS
 * `CounterpartParser.identifyPublicFigure`, `ede039e`).
 *
 * A search-written 3–4 sentence profile was the old design (`59c6481`), and it
 * became the whole person: every call with RM opened on the one fact in it
 * that stood out (the museums). The model already knows the person's work,
 * manner and interests; the only thing it can't know is WHICH person the
 * learner means, so that is the only thing asked — one line ("BTS RM ·
 * rapper") for the learner to confirm.
 */
object PublicFigureLookup {
    @Serializable
    private data class Identity(val found: Boolean = false, val identity: String? = null)

    /** The identity line in the learner's native language, or null when no
     *  public figure goes by [name]. */
    suspend fun identify(name: String, nativeLanguage: String): String? {
        val nativeName = LanguageCatalog.englishName(nativeLanguage)
        val result = GeminiClient(AuthRepository()).sendJson(
            system = CounterpartParsePrompt.publicFigure(nativeName),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, "name: $name")),
            serializer = Identity.serializer(),
            // Grounding needs the full model: a name is ambiguous, and a
            // person who became public last month isn't in the weights.
            model = GeminiClient.Model.FLASH_36,
            maxTokens = 800,
            searchGrounding = true,
            purpose = "parse",
        )
        val identity = result.identity?.trim().orEmpty()
        return if (result.found && identity.isNotEmpty()) identity else null
    }
}
