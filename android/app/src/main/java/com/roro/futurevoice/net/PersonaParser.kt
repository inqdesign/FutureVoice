package com.roro.futurevoice.net

import kotlinx.serialization.Serializable

/**
 * Turns spoken profile answers into compact profile text.
 *
 * Onboarding already asks one thing per screen, so this is a polish pass —
 * same field in, same field out: drop restarts and filler, keep every
 * concrete detail, land on English the conversation prompt can use as ground
 * truth. The prompt itself is generated from the Swift source
 * ([PersonaPolishPrompt]) so the two platforms cannot drift.
 */
object PersonaParser {

    @Serializable
    data class Polished(
        val occupation: String = "",
        val household: String = "",
        val free_notes: String = "",
    )

    /**
     * Pass "" for any field the user TYPED (or skipped) — it comes back "" and
     * the caller keeps what it had. Typed text is already deliberate, and
     * rewriting it would surprise the person who wrote it.
     */
    suspend fun polish(
        occupation: String,
        household: String,
        freeNotes: String,
        languageHint: String,
    ): Polished {
        val user = buildString {
            append("language_hint: ").append(languageHint).append('\n')
            append("occupation_answer:\n").append(occupation).append("\n\n")
            append("household_answer:\n").append(household).append("\n\n")
            append("free_notes_answer:\n").append(freeNotes)
        }
        return GeminiClient(com.roro.futurevoice.data.AuthRepository()).sendJson(
            system = PersonaPolishPrompt.SYSTEM,
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
            serializer = Polished.serializer(),
            // Pure transcript cleanup — utility tier.
            model = GeminiClient.Model.FLASH_LITE_31,
            // Three polished answers out of three rambling spoken ones: the
            // input is unbounded, so the output can be long even though the
            // schema looks small.
            maxTokens = 1500,
            purpose = "parse",
        )
    }
}
