package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.FluencyStats
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.StoreJson
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Domain types for the Talk loop. Shapes come from
 * `docs/contracts/data-model.md` — keep them in step with `Models.swift`.
 */

@Serializable
enum class TurnRole {
    @SerialName("user") USER,
    @SerialName("fluentSelf") FLUENT_SELF,
}

/**
 * One line of a conversation. Persisted in the iOS on-disk shape
 * (`StoreJson`): a turn saved here reads on an iPhone and vice versa.
 */
@Serializable
data class Turn(
    val id: String = StoreJson.newId(),
    val role: TurnRole,
    val transcript: String,
    val durationMs: Int = 0,
    @Serializable(with = IsoDateMillisSerializer::class)
    val timestamp: Long = System.currentTimeMillis(),
    val suggestion: TurnSuggestion? = null,
    val fluency: FluencyStats? = null,
    /** Local file ref; never synced. */
    val audioURL: String? = null,
    /** The learner flagged this turn as misheard — out of every metric. */
    val excludedFromScoring: Boolean = false,
)

@Serializable
data class TurnSuggestion(val alternative: String, val reason: String)

@Serializable
enum class SessionMode {
    @SerialName("pronunciation") PRONUNCIATION,
    @SerialName("conversation") CONVERSATION,
}

/** Where a talk was launched from — the SOURCE, distinct from the activity. */
@Serializable
enum class SessionOrigin {
    @SerialName("free") FREE,
    @SerialName("news") NEWS,
    @SerialName("scenario") SCENARIO,
}

/**
 * A finished (or in-progress) talk — `docs/contracts/data-model.md`. Language-
 * scoped: lives under `LanguageScope.directory(targetLanguage)`.
 */
@Serializable
data class Session(
    val id: String = StoreJson.newId(),
    val userId: String,
    val targetLanguage: String,
    val mode: SessionMode = SessionMode.CONVERSATION,
    val topic: String? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val startedAt: Long,
    @Serializable(with = IsoDateMillisSerializer::class)
    val endedAt: Long? = null,
    val turns: List<Turn> = emptyList(),
    val summary: SessionSummary? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val archivedAt: Long? = null,
    val origin: SessionOrigin? = null,
    val originScenarioId: String? = null,
    val counterpartId: String? = null,
) {
    /** Newest-ended-first ordering key, as `SessionStore.swift` ranks. */
    val rank: Long get() = endedAt ?: startedAt

    /**
     * What this talk is called in lists: the topic, else the learner's own
     * first words, else null (the caller shows the generic "Conversation").
     */
    val displayTitle: String?
        get() {
            topic?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            val first = turns.firstOrNull { it.role == TurnRole.USER }?.transcript?.trim()
                ?.takeIf { it.isNotEmpty() } ?: return null
            val words = first.split(' ')
            return "\u201C" + words.take(6).joinToString(" ") + (if (words.size > 6) "…" else "") + "\u201D"
        }
}

// ── Summary types: the SHAPE is the contract; the values arrive with the
// session-summary work. Every field defaults so a summary written by a newer
// build still decodes (the same lenient decode `SessionSummary.swift` does).

@Serializable
data class SessionSummary(
    val phrasesUsed: List<PhraseFeedback> = emptyList(),
    val newPatternsDetected: List<LearnerPattern> = emptyList(),
    val suggestedDrills: List<String> = emptyList(),
    val overallNote: String = "",
    val scorecard: SessionScorecard? = null,
    val newWordsUsed: List<String> = emptyList(),
    val expressionsUsed: List<String> = emptyList(),
    val expressionsOffered: List<String> = emptyList(),
    val weakVocabAreas: List<String> = emptyList(),
    val grammarIssues: List<GrammarIssue> = emptyList(),
    val carryovers: List<Carryover> = emptyList(),
)

@Serializable
data class PhraseFeedback(
    val id: String = StoreJson.newId(),
    val userSaid: String,
    val fluentAlternative: String,
    val reason: String,
)

@Serializable
data class GrammarIssue(
    val id: String = StoreJson.newId(),
    val quote: String,
    val correction: String,
    val note: String,
)

@Serializable
data class Carryover(
    val id: String = StoreJson.newId(),
    val sessionId: String,
    val source: Source,
    val item: String,
    val quote: String,
    val turnId: String,
    val sourceId: String? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val detectedAt: Long,
) {
    @Serializable
    enum class Source {
        @SerialName("drillCard") DRILL_CARD,
        @SerialName("curriculumItem") CURRICULUM_ITEM,
        @SerialName("studyingExpression") STUDYING_EXPRESSION,
        @SerialName("suggestion") SUGGESTION,
        @SerialName("studyingWord") STUDYING_WORD,
    }
}

@Serializable
data class SessionScorecard(
    val vocabulary: AxisScore,
    val grammar: AxisScore,
    val expressiveness: AxisScore,
    val fluency: AxisScore,
    val pronunciation: AxisScore? = null,
    val topLine: String = "",
    val cefrLevel: String? = null,
) {
    /** Mean of the axes (+ pronunciation when present) — the headline number. */
    val overall: Int
        get() {
            val s = listOfNotNull(vocabulary.score, grammar.score, expressiveness.score, fluency.score, pronunciation?.score)
            return if (s.isEmpty()) 0 else s.sum() / s.size
        }
}

@Serializable
data class AxisScore(val score: Int, val note: String = "")

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

@Serializable
data class LearnerPattern(
    val id: String = StoreJson.newId(),
    val mistake: String,
    val correction: String,
    val context: String,
    val frequency: Int = 1,
    @Serializable(with = IsoDateMillisSerializer::class)
    val lastSeenAt: Long = System.currentTimeMillis(),
)
