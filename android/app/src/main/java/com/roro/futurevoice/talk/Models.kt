package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.FluencyStats
import kotlinx.serialization.Serializable
import java.util.UUID

/**
 * Domain types for the Talk loop. Shapes come from
 * `docs/contracts/data-model.md` — keep them in step with `Models.swift`.
 */

enum class TurnRole { USER, FLUENT_SELF }

data class Turn(
    val id: String = UUID.randomUUID().toString(),
    val role: TurnRole,
    val transcript: String,
    val durationMs: Int = 0,
    val timestamp: Long = System.currentTimeMillis(),
    val suggestion: TurnSuggestion? = null,
    val fluency: FluencyStats? = null,
)

data class TurnSuggestion(val alternative: String, val reason: String)

/**
 * The wire shape of one in-call turn.
 *
 * FIELD ORDER IS LOAD-BEARING — `reply` first, because TTS fires the instant
 * that field's closing quote arrives while the tail is still streaming.
 */
@Serializable
data class ConversationTurnPayload(
    val reply: String = "",
    val suggestion: SuggestionDto? = null,
    val transcript: String? = null,
) {
    @Serializable
    data class SuggestionDto(val alternative: String = "", val reason: String = "")

    /** Drops junk — empty alternatives and rule-like "suggestions". */
    fun turnSuggestion(): TurnSuggestion? {
        val s = suggestion ?: return null
        if (s.alternative.isBlank()) return null
        return TurnSuggestion(s.alternative.trim(), s.reason.trim())
    }
}

/** Minimal persona block for the system prompt. */
data class UserPersona(
    val displayName: String = "",
    val city: String = "",
    val country: String = "",
    val lengthOfStay: String = "",
    val occupation: String = "",
    val household: String = "",
    val interests: List<String> = emptyList(),
    val situations: List<String> = emptyList(),
    val freeNotes: String = "",
) {
    val isMinimallyComplete: Boolean
        get() = displayName.isNotBlank() || city.isNotBlank() || occupation.isNotBlank()
}

data class LearnerPattern(
    val mistake: String,
    val correction: String,
    val context: String,
)
