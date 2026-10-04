package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.FluencyStats
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.StoreJson
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

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
    /**
     * A fluent-self line the learner talked over moments after it began (iOS
     * `Turn.talkedOver`, 2026-09-29): the gateway took a pause for the end of
     * their turn and cut in, and they carried on with the SAME sentence. Say
     * it again reads the learner's lines either side as one
     * (`SayItAgainScript.mergingCutIns`). Encoded only when true, so every
     * turn already on disk keeps its bytes.
     */
    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @kotlinx.serialization.EncodeDefault(kotlinx.serialization.EncodeDefault.Mode.NEVER)
    val talkedOver: Boolean = false,
)

@Serializable
data class TurnSuggestion(
    /** The learner's WHOLE turn, re-said as a fluent speaker would — never a
     *  fragment (it is read back in place of the turn). */
    val alternative: String,
    /** Why the rewrite reads better, in the learner's native language. */
    val reason: String,
    /**
     * The outright ERRORS inside the turn, one clause each (iOS `TurnFix`,
     * 2026-09-27). Empty is an ordinary answer. NULL dates the record: it was
     * saved before this contract, when `alternative` was one sentence at most.
     */
    val fixes: List<TurnFix>? = null,
)

/** One slip inside a turn: what they said, what it should be, and why. */
@Serializable
data class TurnFix(
    val id: String = StoreJson.newId(),
    /** Quoted from the learner's own line, verbatim. */
    val was: String,
    /** The same words corrected — nothing else restyled. */
    val now: String,
    /** The grammar point, in the learner's native language. */
    val why: String = "",
)

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
    /**
     * Coach mode's grammar focus for this call and how it went (iOS
     * `Session.grammarFocus`, `45b397e`). Null on old rows; also what the next
     * call reads to retire a focus the learner has stopped tripping on.
     */
    val grammarFocus: GrammarFocusRecord? = null,
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
        /** They said they knew it; this call is what CONFIRMED it. */
        @SerialName("knownWord") KNOWN_WORD,
        @SerialName("knownExpression") KNOWN_EXPRESSION,
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
    /** The band of the grammatical STRUCTURES the learner produced (a1…c2),
     *  written by the summary beside the score — range, where the score is
     *  accuracy (iOS `SessionScorecard.grammarRange`, 2026-09-24). */
    val grammarRange: String? = null,
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
    data class SuggestionDto(
        val alternative: String = "",
        val reason: String = "",
        val fixes: List<FixDto>? = null,
    )

    @Serializable
    data class FixDto(val was: String = "", val now: String = "", val why: String = "")

    /**
     * The gate every live correction passes (iOS `turnSuggestion(for:)`),
     * run PER PIECE because the two halves can disagree: a turn can be
     * grammatical and still worth re-saying, and a rewrite that only
     * re-spells what they said is a no-op however many fixes ride with it.
     *
     * [original] is the line the MODEL saw.
     */
    fun turnSuggestion(original: String, language: String): TurnSuggestion? {
        val s = suggestion ?: return null
        val alternative = s.alternative.trim()
        if (alternative.isEmpty() || com.roro.futurevoice.data.DrillIngest.looksLikeMetaRule(alternative)) return null
        val fixes = s.fixes.orEmpty().mapNotNull { f ->
            val was = f.was.trim(); val now = f.now.trim()
            // A fix accuses the learner of saying `was`; if they didn't, the
            // accusation is invented.
            if (was.isEmpty() || now.isEmpty() || !SpokenWords.quotes(was, original) ||
                SpokenWords.saysTheSameThing(was, now, language) ||
                SpokenWords.changesOnlyWordOrder(was, now, language) ||
                com.roro.futurevoice.data.DrillIngest.looksLikeMetaRule(now)) null
            else TurnFix(was = was, now = now, why = f.why.trim())
        }
        if (original.isNotBlank() && (SpokenWords.saysTheSameThing(original, alternative, language) ||
                SpokenWords.changesOnlyWordOrder(original, alternative, language))) {
            // The rewrite says nothing new — but it must not take surviving
            // fixes with it. The line is then THEIR turn with the fixes put
            // back where they were said, never a fix on its own: a lone
            // clause read in place of the turn is the fragment this ends.
            if (fixes.isEmpty()) return null
            var line = original
            for (fix in fixes) {
                val at = line.indexOf(fix.was, ignoreCase = true)
                if (at >= 0) line = line.replaceRange(at, at + fix.was.length, fix.now)
            }
            return TurnSuggestion(line, fixes.first().why, fixes)
        }
        // Always non-null, empty included: `fixes == null` marks a record
        // saved before this contract.
        return TurnSuggestion(alternative, s.reason.trim(), fixes)
    }
}

/**
 * The user's persona — `UserPersona` in Models.swift, same on-disk shape
 * (`persona.json`; `situations` keeps its legacy `englishSituations` key).
 * The top half is the user writing about themselves; `learnedNotes` is the
 * fluent self remembering what it was told in calls. One file, one profile.
 *
 * Decoded LENIENTLY: a persona that fails to load walks an existing user
 * back into onboarding, so both lists skip what they can't read instead of
 * throwing ([LenientListSerializer]).
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
    @Serializable(with = PersonaNoteListSerializer::class)
    val learnedNotes: List<PersonaNote> = emptyList(),
    @Serializable(with = IsoDateMillisSerializer::class)
    val metAt: Long? = null,
    /**
     * The learner's own hand moves on the share level, newest last — fed
     * back into the summary call so it sorts the way THIS person draws the
     * line. Capped at [MAX_SHARE_CORRECTIONS].
     */
    @Serializable(with = ShareCorrectionListSerializer::class)
    val shareCorrections: List<ShareCorrection> = emptyList(),
) {
    val isMinimallyComplete: Boolean
        get() = displayName.isNotBlank() && city.isNotBlank() &&
            (occupation.isNotBlank() || household.isNotBlank() ||
                interests.isNotEmpty() || situations.isNotEmpty())

    /** One time the learner moved a line's share level by hand. */
    @Serializable
    data class ShareCorrection(
        val text: String,
        val from: PersonaNote.Share,
        val to: PersonaNote.Share,
        @Serializable(with = IsoDateMillisSerializer::class)
        val at: Long,
    )

    /** A remembered line the summary call says has CHANGED; [note] replaces [replacing]. */
    data class NoteUpdate(val replacing: String, val note: PersonaNote)

    /**
     * The remembered lines still believed: everything on file minus the
     * `now` lines whose month has passed. Every reader of the notebook goes
     * through this, so an expired line is gone from all of them at once.
     */
    fun currentNotes(now: Long = System.currentTimeMillis()): List<PersonaNote> =
        learnedNotes.filterNot { it.isExpired(now) }

    /**
     * What a STRANGER gets from the notebook — the ONLY lines any
     * stranger-facing surface (the Find-people intro, a cast counterpart's
     * prompt) may read: the text of an `ALL` line, the gist of a `GIST`
     * line, nothing of a `NOTHING` one.
     */
    val strangerLines: List<String> get() = currentNotes().mapNotNull { it.strangerLine }

    /** Everything the learner TYPED about themselves, as plain lines (iOS `knownFacts`). */
    val knownFacts: List<String>
        get() {
            val out = ArrayList<String>()
            val place = listOf(city, country).filter { it.isNotEmpty() }.joinToString(", ")
            if (place.isNotEmpty()) out += "Lives in $place"
            if (occupation.isNotEmpty()) out += occupation
            if (household.isNotEmpty()) out += household
            if (interests.isNotEmpty()) out += "Interested in ${interests.joinToString(", ")}"
            if (freeNotes.isNotEmpty()) out += freeNotes
            return out
        }

    /**
     * Record the learner's hand moves between what was on file and this
     * draft. Only a CHANGED level counts; a line saved as it was says nothing.
     */
    fun recordingShareCorrections(previous: List<PersonaNote>, now: Long = System.currentTimeMillis()): UserPersona {
        val before = previous.associateBy { it.id }
        val added = learnedNotes.mapNotNull { n ->
            val old = before[n.id] ?: return@mapNotNull null
            if (old.share == n.share) null else ShareCorrection(n.text, old.share, n.share, now)
        }
        if (added.isEmpty()) return this
        return copy(shareCorrections = (shareCorrections + added).takeLast(MAX_SHARE_CORRECTIONS))
    }

    /**
     * Fold what a talk taught into the notebook (iOS `absorb(notes:updates:)`).
     * Updates first — the outdated line goes and its successor is appended as
     * the newest — then expired `now` lines are pruned, then additions not
     * already on file. The oldest fall off past [limit].
     */
    fun absorbing(
        notes: List<PersonaNote>,
        updates: List<NoteUpdate> = emptyList(),
        limit: Int = 40,
        now: Long = System.currentTimeMillis(),
    ): UserPersona {
        val kept = learnedNotes.toMutableList()
        for (u in updates) {
            val idx = kept.indexOfFirst { it.id == u.replacing }
            if (idx < 0) continue
            kept.removeAt(idx)
            kept.add(u.note)
        }
        kept.removeAll { it.isExpired(now) }
        val seen = kept.map { it.dedupeKey }.toMutableSet()
        for (n in notes) {
            val k = n.dedupeKey
            if (k.isEmpty() || !seen.add(k)) continue
            kept.add(n)
        }
        return copy(learnedNotes = if (kept.size > limit) kept.takeLast(limit) else kept)
    }

    companion object {
        const val MAX_SHARE_CORRECTIONS = 8
    }
}

/**
 * One thing the fluent self learned about the user during a talk. NATIVE
 * language: the learner reads these in their own profile.
 *
 * Every line is a STANDING TRUTH ([text]) with its evidence under it
 * ([heard], the sentence it was distilled from), and a three-way lock
 * ([share]) on how much of it a stranger gets. Serialized by hand
 * ([PersonaNoteSerializer]) because the decode has to be lenient in ways the
 * generated one can't be, and `isPrivate` must be READ but never WRITTEN.
 */
@Serializable(with = PersonaNoteSerializer::class)
data class PersonaNote(
    val id: String = StoreJson.newId(),
    val text: String,
    val sessionId: String? = null,
    val learnedAt: Long = System.currentTimeMillis(),
    /** How much of this a STRANGER gets. Defaults to NOTHING — a line nobody judged is hidden. */
    val share: Share = Share.NOTHING,
    /** How long this is expected to stay true — a `NOW` line fades after [NOW_HORIZON_MS]. */
    val kind: Kind = Kind.FACT,
    /** The sentence the line was distilled from, in the learner's own words. */
    val heard: String? = null,
    /** The outline a stranger may hear when [share] is `GIST`; null when there's no honest one. */
    val gist: String? = null,
    /** The model's one-clause reason for its [share] pick, in the app language. */
    val why: String? = null,
) {
    enum class Kind(val wire: String) { FACT("fact"), NOW("now");
        companion object { fun from(raw: String?): Kind? = entries.firstOrNull { it.wire == raw } }
    }

    /** What a stranger gets. Ordered least to most. */
    @Serializable
    enum class Share(val wire: String) {
        @SerialName("nothing") NOTHING("nothing"),
        @SerialName("gist") GIST("gist"),
        @SerialName("all") ALL("all");
        companion object { fun from(raw: String?): Share? = entries.firstOrNull { it.wire == raw } }
    }

    /** Nothing at all leaves the notebook. A `GIST` line is NOT private in this sense. */
    val isPrivate: Boolean get() = share == Share.NOTHING

    /**
     * The line as a stranger-facing surface may read it, or null. `GIST` with
     * no gist on file yields null rather than falling back to the text: the
     * learner chose "the outline", and the outline is missing.
     */
    val strangerLine: String?
        get() = when (share) {
            Share.NOTHING -> null
            Share.ALL -> text
            Share.GIST -> gist?.trim()?.takeIf { it.isNotEmpty() }
        }

    fun isExpired(now: Long = System.currentTimeMillis()): Boolean =
        kind == Kind.NOW && now - learnedAt > NOW_HORIZON_MS

    /** Comparison form for "do we already know this?" (iOS `dedupeKey`). */
    val dedupeKey: String
        get() = text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.joinToString(" ")

    companion object {
        const val NOW_HORIZON_MS: Long = 30L * 86_400_000L
    }
}

/**
 * `PersonaNote.init(from:)` / `encode(to:)` on iOS. Lenient on everything
 * but the text: every note written before a field existed has no key for it.
 * `share` falls back to the old two-way lock (`isPrivate` true → nothing,
 * false → all), and with neither key — or a value it can't read — to
 * nothing. `isPrivate` is never written: a build from before the three rungs
 * reading a `gist` line with `isPrivate: false` on it would put the WHOLE
 * line in the intro.
 */
object PersonaNoteSerializer : KSerializer<PersonaNote> {
    override val descriptor: SerialDescriptor = JsonObject.serializer().descriptor

    private fun JsonObject.str(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    override fun deserialize(decoder: Decoder): PersonaNote {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        val text = obj.str("text") ?: throw SerializationException("PersonaNote without text")
        val share = Share.from(obj.str("share"))
            ?: (obj["isPrivate"] as? JsonPrimitive)?.booleanOrNull?.let { if (it) Share.NOTHING else Share.ALL }
            ?: Share.NOTHING
        val learnedAt = obj.str("learnedAt")?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
            ?: System.currentTimeMillis()
        return PersonaNote(
            id = obj.str("id") ?: StoreJson.newId(),
            text = text,
            sessionId = obj.str("sessionId"),
            learnedAt = learnedAt,
            share = share,
            kind = PersonaNote.Kind.from(obj.str("kind")) ?: PersonaNote.Kind.FACT,
            heard = obj.str("heard"),
            gist = obj.str("gist"),
            why = obj.str("why"),
        )
    }

    override fun serialize(encoder: Encoder, value: PersonaNote) {
        val obj = buildJsonObject {
            put("id", value.id)
            put("text", value.text)
            value.sessionId?.let { put("sessionId", it) }
            put("learnedAt", DateTimeFormatter.ISO_INSTANT.format(
                Instant.ofEpochMilli(value.learnedAt).truncatedTo(ChronoUnit.SECONDS)))
            put("kind", value.kind.wire)
            put("share", value.share.wire)
            value.heard?.let { put("heard", it) }
            value.gist?.let { put("gist", it) }
            value.why?.let { put("why", it) }
        }
        (encoder as JsonEncoder).encodeJsonElement(obj)
    }
}

private typealias Share = PersonaNote.Share

/**
 * A list that skips the elements it can't read instead of failing the whole
 * record — and reads as empty when the key holds something that isn't a
 * list at all. What `UserPersona`'s lenient `init(from:)` buys on iOS.
 */
open class LenientListSerializer<T>(private val element: KSerializer<T>) : KSerializer<List<T>> {
    private val list = ListSerializer(element)
    override val descriptor: SerialDescriptor = list.descriptor
    override fun deserialize(decoder: Decoder): List<T> {
        val json = decoder as JsonDecoder
        val arr = json.decodeJsonElement() as? JsonArray ?: return emptyList()
        return arr.mapNotNull { runCatching { json.json.decodeFromJsonElement(element, it) }.getOrNull() }
    }
    override fun serialize(encoder: Encoder, value: List<T>) = list.serialize(encoder, value)
}

object PersonaNoteListSerializer : LenientListSerializer<PersonaNote>(PersonaNoteSerializer)
object ShareCorrectionListSerializer :
    LenientListSerializer<UserPersona.ShareCorrection>(UserPersona.ShareCorrection.serializer())

/**
 * One call's grammar focus, as it was shown and as it went (iOS
 * `GrammarFocusRecord`). `label` is coaching (native language); `mistake` /
 * `correction` are the learner's own slip and its fix (target language).
 */
@Serializable
data class GrammarFocusRecord(
    /** [LearnerProfile.patternKey] — normalized mistake→correction. */
    val patternKey: String,
    val label: String,
    val mistake: String,
    val correction: String,
    /** Times the same slip came back in this call, judged per correction. */
    val repeats: Int = 0,
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
    /** When the learner PRODUCED this sentence in a real conversation — the
     *  strongest state there is, and the one a claim can never outrank. */
    @Serializable(with = IsoDateMillisSerializer::class)
    val usedInTalkAt: Long? = null,
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
        /** iOS `LearnerProfile.patternKey`: normalized mistake→correction. */
        fun patternKey(p: LearnerPattern): String =
            p.mistake.lowercase().trim() + "→" + p.correction.lowercase().trim()

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
    /** Material the learner attached, and what ONE reading of it produced
     *  (iOS `Scenario.brief`). Optional so old rows decode unchanged. */
    val brief: ScenarioBrief? = null,
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
