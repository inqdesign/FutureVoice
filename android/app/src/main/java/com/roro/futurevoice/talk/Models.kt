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

/**
 * The user's persona — `UserPersona` in Models.swift, same on-disk shape
 * (`persona.json`; `situations` keeps its legacy `englishSituations` key).
 * The top half is the user writing about themselves; `learnedNotes` is the
 * fluent self remembering what it was told in calls. One file, one profile.
 */
@Serializable
data class UserPersona(
    val displayName: String = "",
    val city: String = "",
    val country: String = "",
    val lengthOfStay: String = "",
    val occupation: String = "",
    val household: String = "",
    val interests: List<String> = emptyList(),
    @SerialName("englishSituations")
    val situations: List<String> = emptyList(),
    val freeNotes: String = "",
    @Serializable(with = IsoDateMillisSerializer::class)
    val updatedAt: Long = System.currentTimeMillis(),
    val learnedNotes: List<PersonaNote> = emptyList(),
    @Serializable(with = IsoDateMillisSerializer::class)
    val metAt: Long? = null,
) {
    val isMinimallyComplete: Boolean
        get() = displayName.isNotBlank() && city.isNotBlank() &&
            (occupation.isNotBlank() || household.isNotBlank() ||
                interests.isNotEmpty() || situations.isNotEmpty())
}

/** One thing the fluent self learned about the user during a talk. NATIVE language. */
@Serializable
data class PersonaNote(
    val id: String = StoreJson.newId(),
    val text: String,
    val sessionId: String? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val learnedAt: Long = System.currentTimeMillis(),
)

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

// MARK: - Drill cards & learner profile (`Models.swift` parity)

@Serializable
data class DrillCard(
    val id: String = StoreJson.newId(),
    val sourcePhrase: String,
    val targetPhrase: String,
    val reason: String,
    @Serializable(with = IsoDateMillisSerializer::class)
    val createdAt: Long,
    @Serializable(with = IsoDateMillisSerializer::class)
    val lastReviewedAt: Long? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val nextReviewAt: Long,
    val box: Int,
    val timesSeen: Int = 0,
    val timesCorrect: Int = 0,
    val sourceSessionId: String? = null,
    val sourceTurnId: String? = null,
    /**
     * iOS's `DrillCardEnrichment`, carried OPAQUELY: Android doesn't render
     * it yet, but a rewrite of the file must not drop what iOS wrote.
     */
    val enrichment: kotlinx.serialization.json.JsonElement? = null,
)

@Serializable
data class LearnerProfile(
    val id: String = StoreJson.newId(),
    val userId: String,
    val targetLanguage: String,
    /** iOS `CEFRLevel` rawValue — "a1"…"c2". */
    var proficiencyLevel: String = "b1",
    var recurringMistakes: List<LearnerPattern> = emptyList(),
    var weakVocabAreas: List<String> = emptyList(),
    var strongPatterns: List<String> = emptyList(),
    var totalSessions: Int = 0,
    var totalSpeakingSeconds: Int = 0,
    @Serializable(with = IsoDateMillisSerializer::class)
    var lastSessionAt: Long? = null,
    var summaryEmbedding: List<Float>? = null,
) {
    /**
     * `LearnerProfile.absorb` — fold one finished session in. New patterns
     * merge on normalized mistake+correction (bumping frequency, keeping the
     * freshest phrasing), re-ranked by frequency then recency, capped at
     * [MAX_RECURRING]; weak areas merge newest-first case-insensitively,
     * capped at [MAX_WEAK_AREAS].
     */
    fun absorb(summary: SessionSummary, speakingSeconds: Double, now: Long = System.currentTimeMillis()) {
        fun norm(s: String) = s.lowercase().trim()
        fun key(p: LearnerPattern) = norm(p.mistake) + "→" + norm(p.correction)
        val mistakes = recurringMistakes.toMutableList()
        for (incoming in summary.newPatternsDetected) {
            val idx = mistakes.indexOfFirst { key(it) == key(incoming) }
            if (idx >= 0) {
                val old = mistakes[idx]
                mistakes[idx] = old.copy(
                    frequency = old.frequency + incoming.frequency,
                    lastSeenAt = now,
                    correction = incoming.correction,
                    context = incoming.context.ifEmpty { old.context },
                )
            } else {
                mistakes.add(incoming.copy(lastSeenAt = now))
            }
        }
        mistakes.sortWith(compareByDescending<LearnerPattern> { it.frequency }.thenByDescending { it.lastSeenAt })
        recurringMistakes = mistakes.take(MAX_RECURRING)

        val weak = weakVocabAreas.toMutableList()
        for (area in summary.weakVocabAreas) {
            val trimmed = area.trim()
            if (trimmed.isEmpty()) continue
            weak.removeAll { it.lowercase() == trimmed.lowercase() }
            weak.add(0, trimmed)
        }
        weakVocabAreas = weak.take(MAX_WEAK_AREAS)

        totalSessions += 1
        totalSpeakingSeconds += Math.round(speakingSeconds).toInt()
        lastSessionAt = now
    }

    companion object {
        const val MAX_RECURRING = 10
        const val MAX_WEAK_AREAS = 5
    }
}

@Serializable
data class SuggestedTopic(
    val id: String = StoreJson.newId(),
    val title: String,
    val blurb: String,
    val category: String? = null,
    /** Grounded facts collected at pool generation — seeds `newsFacts`. */
    val facts: List<String>? = null,
)

/**
 * A reusable practice scenario — `Scenario` in Models.swift, same
 * `scenarios.json` shape (every optional lenient). Android v1 writes the
 * composer subset (environment/summary/category); the Watch fields ride
 * along untouched so an iOS-written file survives a round trip.
 */
@Serializable
data class Scenario(
    val id: String = StoreJson.newId(),
    val environment: String,
    val role: String = "",
    val notes: String = "",
    @Serializable(with = IsoDateMillisSerializer::class)
    val createdAt: Long = System.currentTimeMillis(),
    @Serializable(with = IsoDateMillisSerializer::class)
    val lastUsedAt: Long? = null,
    val counterpartId: String? = null,
    val voicePresetId: String? = null,
    val curriculum: ScenarioCurriculum? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val archivedAt: Long? = null,
    val openers: List<String>? = null,
    val openerCursor: Int? = null,
    val isTopic: Boolean? = null,
    val category: String? = null,
    val categoryIcon: String? = null,
    val summary: String? = null,
    val isMeeting: Boolean? = null,
) {
    val cardTitle: String
        get() = summary?.trim()?.takeIf { it.isNotEmpty() } ?: environment

    /** `environment=… | role=… | notes=…` — what the conversation prompt parses. */
    val promptBlurb: String
        get() = buildList {
            add("environment=$environment")
            role.trim().takeIf { it.isNotEmpty() }?.let { add("role=$it") }
            notes.trim().takeIf { it.isNotEmpty() }?.let { add("notes=$it") }
        }.joinToString(" | ")
}

@Serializable
data class DialogueEngineTurn(
    val id: String = StoreJson.newId(),
    val speaker: String,   // "user" | "counterpart"
    val text: String,
)

/**
 * The scenario's course content — `ScenarioCurriculum` in Models.swift, same
 * shape on disk. The scene (dialogue) is what plays; words/expressions/shadow
 * lines are what the book asks to master.
 */
@Serializable
data class ScenarioCurriculum(
    val words: List<Item> = emptyList(),
    val expressions: List<Item> = emptyList(),
    val shadowLines: List<Item> = emptyList(),
    val dialogueTitle: String? = null,
    val dialogue: List<DialogueEngineTurn>? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val generatedAt: Long = System.currentTimeMillis(),
) {
    @Serializable
    data class Item(
        val id: String = StoreJson.newId(),
        val text: String,
        val note: String = "",
        val example: String? = null,
        @Serializable(with = IsoDateMillisSerializer::class)
        val masteredAt: Long? = null,
    )

    /** Fold a fresh take in: scene replaces, study items accumulate (iOS `absorb`). */
    fun absorb(fresh: ScenarioCurriculum): ScenarioCurriculum {
        fun merged(old: List<Item>, new: List<Item>): List<Item> {
            val seen = old.map { it.text.lowercase() }.toMutableSet()
            return old + new.filter { seen.add(it.text.lowercase()) }
        }
        return copy(
            words = merged(words, fresh.words),
            expressions = merged(expressions, fresh.expressions),
            shadowLines = merged(shadowLines, fresh.shadowLines),
            dialogueTitle = fresh.dialogueTitle,
            dialogue = fresh.dialogue,
            generatedAt = fresh.generatedAt,
        )
    }
}

/** The four preset scene voices (`VoicePreset.catalog` + `StockPerson`). */
data class StockPerson(val voiceId: String, val name: String, val identity: String) {
    companion object {
        val catalog = listOf(
            StockPerson("NDTYOmYEjbDIVCKB35i3", "Paige",
                "Paige — American, twenties; bright and upbeat, quick to encourage, keeps the conversation moving"),
            StockPerson("UgBBYS2sOqTuMpoF3BR0", "Mark",
                "Mark — American, thirties; easygoing and direct, with a dry sense of humor"),
            StockPerson("FF59babHL8N8gfTgtBMT", "Emma",
                "Emma — British, twenties; warm and chatty, asks friendly follow-up questions"),
            StockPerson("L0Dsvb3SLTyegXwtm47J", "James",
                "James — British, forties; calm and courteous, unhurried, gently witty"),
        )
        fun by(voiceId: String?): StockPerson =
            catalog.firstOrNull { it.voiceId == voiceId } ?: catalog[0]
    }
}
