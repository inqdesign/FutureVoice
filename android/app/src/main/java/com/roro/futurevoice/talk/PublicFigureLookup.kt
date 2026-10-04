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
            system = """
                The user wants to practise a conversation with a PUBLIC FIGURE — a singer, an actor, an athlete, an author, a politician. They typed a name. Find out exactly who they mean.

                Return STRICT JSON only — no prose, no code fences:
                { "found": true, "identity": "..." }

                - identity: 3–6 words the user can confirm at a glance — the name as the person is publicly known, then the group or field and the role ("BTS RM · rapper", "Son Heung-min · footballer"). Written in $nativeName; names stay in their usual script.
                - If the name could mean several public figures, pick the most famous reading.
                - If no public figure goes by that name, return { "found": false }.
            """.trimIndent(),
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
