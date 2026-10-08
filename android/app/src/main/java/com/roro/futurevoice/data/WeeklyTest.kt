package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.net.WeekRecapCoach
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.GrammarFocus
import com.roro.futurevoice.talk.LearnerPattern
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.ShadowScore
import com.roro.futurevoice.talk.SessionMode
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File
import java.text.Normalizer
import kotlin.random.Random

/**
 * One week's test (or the month's paper of misses) — iOS `WeeklyTest`, the
 * same on-disk shape (`lang/<code>/weekly-tests.json`).
 */
@Serializable
data class WeeklyTest(
    val id: String = StoreJson.newId(),
    val targetLanguage: String,
    /** null decodes as weekly (tests written before the monthly existed). */
    val kind: Kind? = null,
    /** The window the material was drawn from. */
    @Serializable(with = IsoDateMillisSerializer::class) val periodStart: Long,
    @Serializable(with = IsoDateMillisSerializer::class) val periodEnd: Long,
    @Serializable(with = IsoDateMillisSerializer::class) val createdAt: Long,
    @Serializable(with = IsoDateMillisSerializer::class) val startedAt: Long? = null,
    @Serializable(with = IsoDateMillisSerializer::class) val finishedAt: Long? = null,
    val items: List<WeeklyTestItem>,
    val answers: List<WeeklyTestAnswer> = emptyList(),
    /** Longest run of correct answers in a row while playing. */
    val bestStreak: Int = 0,
    /** When the result was written into the review loop; nil until then, so a
     *  finished test is applied exactly once. */
    @Serializable(with = IsoDateMillisSerializer::class) val appliedAt: Long? = null,
) {
    /** `MONTHLY` survives only so papers saved before iOS 70dd26a9
     *  (2026-10-05) still decode — there is one test now, and every reader
     *  skips a monthly one. */
    @Serializable
    enum class Kind { @SerialName("weekly") WEEKLY, @SerialName("monthly") MONTHLY }

    val isMonthly: Boolean get() = kind == Kind.MONTHLY
    val isFinished: Boolean get() = finishedAt != null
    val score: Int get() = answers.count { it.correct }
    val total: Int get() = items.size

    /** The next item to play, null once every one is answered. */
    val nextItem: WeeklyTestItem?
        get() {
            val done = answers.map { it.itemId }.toSet()
            return items.firstOrNull { it.id !in done }
        }
}

@Serializable
data class WeeklyTestItem(
    val id: String = StoreJson.newId(),
    val kind: Kind,
    /** meaning: the sense in the learner's language · gap: the line with the
     *  blank · build: what the learner originally said · listen/speak: empty. */
    val prompt: String,
    /** The correct answer, as the material spells it. */
    val answer: String,
    /** meaning/gap: the choices, answer included, in display order ·
     *  build/listen: the word tiles, in display order · rewrite: empty. */
    val options: List<String> = emptyList(),
    val sessionId: String? = null,
    val turnId: String? = null,
    val cardId: String? = null,
    /** build/rewrite: the correction's one-line reason (coaching, native language). */
    val note: String? = null,
    /** True when the item came back from an earlier test's wrong answers. */
    val isRetake: Boolean? = null,
    /** grammar: the rule in the learner's language. */
    val rule: String? = null,
    /** grammar: the span that was wrong · upgrade: the leaned-on word —
     *  marked inside [prompt] · rewrite: what was said (the fix's "was"). */
    val focus: String? = null,
    /** upgrade: the learner's line with the better word in it · rewrite:
     *  what it should be (the fix's "now"). */
    val example: String? = null,
    /** translate: other orders of the answer's own words that are just as
     *  right ("Yesterday I…" / "I … yesterday"). */
    val orders: List<String>? = null,
) {
    @Serializable
    enum class Kind {
        /** A word the talks taught: its meaning is shown, pick the word. */
        @SerialName("meaning") MEANING,
        /** A fluent-self line with its phrase blanked out: pick the phrase. */
        @SerialName("gap") GAP,
        /** A corrected sentence: rebuild the fluent version from tiles. No
         *  longer dealt (iOS 2026-10-08) — stored papers still hold it; a
         *  missed one comes back as [REWRITE]. */
        @SerialName("build") BUILD,
        /** A fluent-self line HEARD and rebuilt from its own tiles (dictation). */
        @SerialName("listen") LISTEN,
        /** A fluent-self line said out loud, scored like a shadow take. */
        @SerialName("speak") SPEAK,
        /** A grammar point the week's report found going wrong in more than
         *  one sentence: its rule with one of the learner's lines, rebuilt
         *  the right way from tiles. */
        @SerialName("grammar") GRAMMAR,
        /** A word the learner leans on (the report's "upgrades"): their line
         *  with it marked, pick the better word. */
        @SerialName("upgrade") UPGRADE,
        /** A sentence the learner said and was corrected, shown whole with
         *  the mistake marked: say or type it again the right way. Dealt for
         *  one day (2026-10-08) and replaced by [TRANSLATE]; stored papers
         *  may still hold it. */
        @SerialName("rewrite") REWRITE,
        /** A grammar point the learner got wrong, asked in a NEW sentence:
         *  `prompt` is a native-language sentence, laid in the target
         *  language from `options` (the answer's words + trap words from the
         *  learner's mistake). Right in `answer`'s order or one of `orders`.
         *  `rule` names the point, `note` is its tip, `focus` → `example` the
         *  learner's own slip and its fix. */
        @SerialName("translate") TRANSLATE,
    }
}

@Serializable
data class WeeklyTestAnswer(
    val itemId: String,
    val given: String,
    val correct: Boolean,
    @Serializable(with = IsoDateMillisSerializer::class) val at: Long,
    /** speak: the shadow match score the verdict was made from. */
    val score: Int? = null,
)

/**
 * SplitMix64 seeded from a test id, so a paper shuffles the same way on every
 * open (iOS `WeeklyTestRandom`). The bit stream is the same as iOS's; the
 * shuffle algorithm on top is Kotlin's, so the two platforms don't deal the
 * same order from one id — they never have to, nothing is synced.
 */
class WeeklyTestRandom(seed: String) : Random() {
    private var state: Long

    init {
        val hex = seed.replace("-", "")
        val hi = hex.take(16).toULongOrNull(16)?.toLong() ?: seed.hashCode().toLong()
        state = hi + GOLDEN
    }

    fun nextLong64(): Long {
        state += GOLDEN
        var z = state
        z = (z xor (z ushr 30)) * M1
        z = (z xor (z ushr 27)) * M2
        return z xor (z ushr 31)
    }

    override fun nextBits(bitCount: Int): Int =
        if (bitCount == 0) 0 else (nextLong64() ushr (64 - bitCount)).toInt()

    private companion object {
        val GOLDEN = 0x9E3779B97F4A7C15UL.toLong()
        val M1 = 0xBF58476D1CE4E5B9UL.toLong()
        val M2 = 0x94D049BB133111EBUL.toLong()
    }
}

/**
 * Builds and grades the weekly test (iOS `WeeklyTestEngine`, 1.1.1 with its
 * follow-ups). The test is the learner's own week turned into questions —
 * nothing is drawn from a generic bank:
 *
 *   meaning  ← the week's talk BOOKS' Words chapter (iOS `36342dd`)
 *   gap      ← the Expressions page's "To study" list, in the line it was heard in
 *   translate← the corrections (drill cards) and the profile's recurring
 *              mistakes, asked in a NEW sentence: a native-language line to say
 *              in the target language, graded in code against the pattern's
 *              required spans and the learner's own wrong forms (replaced
 *              `build`, iOS 2026-10-08 — founder: "a mistake is learned by
 *              using its pattern again, not by re-reading the sentence it was in")
 *   listen   ← the fluent self's saved lines, heard and rebuilt from tiles
 *   speak    ← the fluent self's lines, said out loud and scored like a shadow take
 *
 * listen and speak take only lines that carry a "To study" expression, and
 * never a call's opening line. A learner reported (2026-10-08) that the test
 * "felt random": the opener's greeting came up to be repeated, and a
 * correction card — one clause since 2026-09-27 — was shuffled into four
 * tiles that rebuilt nothing worth knowing. Every item now has a reason the
 * learner can see: a phrase they are studying, or a sentence they got wrong.
 *   grammar  ← the week report's recurring grammar points (`WeekRecap.Coach`),
 *              else the profile's recurring mistakes — rule + one of the
 *              learner's own lines, rebuilt right from tiles (iOS `9617756`)
 *   upgrade  ← the week report's leaned-on words — the learner's line with
 *              the word marked, pick the better one
 *
 * Every grade is computed in code. The only model calls are the free, cached
 * dictionary gloss (meaning) and the audio read of a take (speak).
 */
object WeeklyTestEngine {

    const val MAX_MEANING = 4
    const val MAX_GAP = 3
    const val MAX_REWRITE = 3
    const val MAX_TRANSLATE = 3
    /** How long a paper waits for its translate items to be written. */
    const val TRANSLATE_WAIT_MS = 30_000L
    /** How long an unlisted tile order waits to be read. */
    const val ORDER_WAIT_MS = 10_000L
    const val MAX_LISTEN = 2
    const val MAX_SPEAK = 2
    const val MAX_GRAMMAR = 2
    const val MAX_UPGRADE = 2
    /** How long a paper waits for the week report's coach to be written when
     *  the deck hasn't been opened yet. The writing carries on past it (and
     *  lands in the report); the paper just goes without. */
    const val COACH_WAIT_MS = 25_000L
    /** Wrong answers of recent tests dealt again this week (iOS 70dd26a9:
     *  the weekly paper absorbed the monthly one). */
    const val MAX_RETAKE = 5
    /** How many finished weekly papers the retakes are drawn from — about a
     *  month, which is what the monthly paper used to gather. */
    const val RETAKE_WEEKS = 4
    /** Ceiling for a paper of one test's own misses ([retryPaper]). */
    const val MAX_RETRY = 20
    /** A spoken line passes at the shadow browser's own retry bar. */
    const val SPEAK_PASS_SCORE = ShadowPicks.RETRY_THRESHOLD
    /** Below this the week is too thin to be a test. */
    const val MIN_ITEMS = 5
    const val CHOICE_COUNT = 4
    /** Extra tiles for a build item, from the learner's OWN wording. */
    const val MAX_DECOY_TILES = 2
    /** How far back the window reaches with no previous test. */
    const val DEFAULT_WINDOW_MS = 7 * 86_400_000L
    const val BLANK_MARK = "______"

    // ── Window

    /** Since the last WEEKLY test was built, else one week. A monthly paper
     *  is never the anchor (iOS `07170af`). */
    fun window(lastTest: WeeklyTest?, now: Long): Pair<Long, Long> {
        val anchor = lastTest?.takeIf { !it.isMonthly }
        val start = anchor?.periodEnd ?: (now - DEFAULT_WINDOW_MS)
        return minOf(start, now) to now
    }

    // ── What a build reads

    /** Everything the week's build reads, gathered once — so the build itself
     *  is a pure function a JVM test can run. */
    class Material(
        /** Unarchived conversation talks, every one on file. */
        val sessions: List<Session>,
        val studying: List<String>,
        val usedRecently: List<String>,
        val recorded: List<String>,
        val cards: List<DrillCard>,
        val libraryExpressions: List<String>,
        /** Whether a fluent-self turn's own recording is on disk. */
        val hasAudio: (Turn) -> Boolean,
        /** Graded headwords by band (empty for a language with no list). */
        val graded: (CefrLevel) -> List<String> = { emptyList() },
        /** A talk's book Words chapter: each word and whether it is mastered
         *  (`TalkCurriculum.build(...).words`). The ONLY source of meaning
         *  items (iOS `36342dd`). */
        val bookWords: suspend (Session) -> List<Pair<String, Boolean>> = { emptyList() },
        /** The closed week's report coach, written at gather time if missing. */
        val coach: WeekRecap.Coach? = null,
        /** The profile's recurring mistakes, fresh and frequent enough to be a
         *  focus (`GrammarFocus` rules) — the grammar fallback. */
        val mistakes: List<LearnerPattern> = emptyList(),
        /** Names a mistake for the learner: (label, tip) in their language. */
        val describeMistake: suspend (LearnerPattern) -> Pair<String, String>? = { null },
        /** What the Expressions page lists under "To study"
         *  (iOS `ExpressionCatalog.toStudy`), newest first. */
        val toStudy: List<String> = emptyList(),
        /** A scene's own example line for an expression, by its normalized
         *  key (trimmed, lowercased). */
        val sceneExamples: Map<String, String> = emptyMap(),
        /** The learner's own language — translate items need it. */
        val nativeLanguage: String = "",
        /** Every recurring mistake on the profile, unfiltered — [slips]
         *  judges them by what was really said ([GrammarFocus.evidence]). */
        val profileMistakes: List<LearnerPattern> = emptyList(),
        /** Writes the translate items (one model call); null = no network,
         *  so no translate items (a JVM test). Args: system, user, test id. */
        val writeTranslate: (suspend (String, String, String) -> TranslatePayload?)? = null,
    )

    @Serializable
    data class TranslatePayload(val items: List<Item> = emptyList()) {
        @Serializable
        data class Item(
            val source: Int,
            val point: String,
            val native: String,
            val answer: String,
            val orders: List<String>? = null,
            val decoys: List<String>? = null,
            val tip: String? = null,
        )
    }

    suspend fun gather(context: Context, language: String, level: CefrLevel,
                       native: String): Material {
        val vocab = VocabStore.shared(context)
        val app = context.applicationContext
        val now = System.currentTimeMillis()
        val fresh = now - GrammarFocus.FRESH_DAYS * 86_400_000L
        val profileMistakes = runCatching {
            ProfileStore.shared(context).load(language, level.code).recurringMistakes
        }.getOrDefault(emptyList())
        val mistakes = profileMistakes
            .filter { it.frequency >= GrammarFocus.MIN_FREQUENCY && it.lastSeenAt >= fresh }
        return Material(
            sessions = SessionStore.shared(context).load(language)
                .filter { it.archivedAt == null && it.mode == SessionMode.CONVERSATION },
            studying = vocab.studying(language),
            usedRecently = vocab.usedWords(7, language),
            recorded = vocab.recordedWords(language),
            cards = DrillStore.shared(context).load(language),
            libraryExpressions = runCatching { ExpressionCatalog.all(context, language).map { it.text } }
                .getOrDefault(emptyList()),
            hasAudio = { turn -> turnAudio(app, turn) != null },
            graded = { band -> CoreVocabulary.headwords(band, language) },
            bookWords = { session ->
                TalkCurriculum.build(session, level, language, vocab, emptyList(), emptyList())
                    .words.map { it.text to (it.masteredAt != null) }
            },
            coach = weekCoach(app, language, level, native),
            mistakes = mistakes,
            describeMistake = { p ->
                GrammarFocus.describe(app, p, language, native)?.let { it.label to it.tip }
            },
            toStudy = runCatching {
                ExpressionCatalog.library(context, language).filter { !it.known }.map { it.text }
            }.getOrDefault(emptyList()),
            sceneExamples = runCatching {
                val out = LinkedHashMap<String, String>()
                for (sc in ScenarioStore.shared(context).load(language)) {
                    for (e in sc.curriculum?.expressions.orEmpty()) {
                        val example = e.example ?: continue
                        out.putIfAbsent(e.text.trim().lowercase(), example)
                    }
                }
                out.toMap()
            }.getOrDefault(emptyMap()),
            nativeLanguage = native,
            profileMistakes = profileMistakes,
            writeTranslate = { system, user, testId ->
                val job = coachScope.async {
                    runCatching {
                        GeminiClient(AuthRepository()).sendJson(
                            system = system,
                            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                            serializer = TranslatePayload.serializer(),
                            maxTokens = 3000, purpose = "weekly-test",
                            idempotencyKey = "weekly-test-translate:$testId")
                    }.getOrNull()
                }
                withTimeoutOrNull(TRANSLATE_WAIT_MS) { job.await() }
            },
        )
    }

    /** Turns a stored tile item into the rewrite that replaced it, reading
     *  the language's cards and talks once (iOS `asRewrite`). */
    suspend fun rewriteLookup(context: Context, language: String): (WeeklyTestItem) -> WeeklyTestItem? {
        val cards = runCatching { DrillStore.shared(context).load(language) }.getOrDefault(emptyList())
        val sessions = runCatching { SessionStore.shared(context).load(language) }.getOrDefault(emptyList())
        return { asRewrite(it, cards, sessions, language) }
    }

    /** Outlives the screen: a coach still being written when the paper stops
     *  waiting lands in the report anyway, so the deck doesn't pay twice. */
    private val coachScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * The closed week's report coach (iOS `weekCoach`). Written here when the
     * deck hasn't been opened yet — saved into the report, so the deck shows
     * the same read and it is paid for once — but the paper waits at most
     * [COACH_WAIT_MS] for it.
     */
    private suspend fun weekCoach(context: Context, language: String, level: CefrLevel,
                                  native: String): WeekRecap.Coach? {
        val recap = runCatching { WeekRecapStore.lastWeek(context) }.getOrNull() ?: return null
        recap.coach?.let { return it }
        if (!recap.hasActivity) return null
        val job = coachScope.async {
            val written = runCatching { WeekRecapCoach.write(context, recap, language, level, native) }
                .getOrNull() ?: return@async null
            // The deck may have written it meanwhile; keep the first.
            val latest = WeekRecapStore.recap(context, recap.end) ?: recap
            if (latest.coach != null) return@async latest.coach
            WeekRecapStore.save(context, latest.copy(coach = written))
            written
        }
        return withTimeoutOrNull(COACH_WAIT_MS) { job.await() }
    }

    /** A turn's own recording: `Turn.audioURL`, else `turn-audio/<id>.wav`. */
    fun turnAudio(context: Context, turn: Turn): File? =
        listOfNotNull(turn.audioURL?.let(::File),
            File(File(context.filesDir, "turn-audio"), "${turn.id}.wav"))
            .firstOrNull { it.isFile && it.length() > 44 }

    /**
     * This week's test, or null under [MIN_ITEMS]. [gloss] is the dictionary
     * lookup (a word → its first sense in the learner's language, or null).
     */
    suspend fun build(
        material: Material,
        lastTest: WeeklyTest?,
        language: String,
        level: CefrLevel,
        now: Long = System.currentTimeMillis(),
        id: String = StoreJson.newId(),
        /** The finished weekly papers the retakes come from (with [lastTest]). */
        recentTests: List<WeeklyTest> = emptyList(),
        gloss: suspend (String) -> String?,
    ): WeeklyTest? {
        val (start, end) = window(lastTest, now)
        val rng = WeeklyTestRandom(id)
        val windowSessions = material.sessions.filter { s ->
            val ended = s.endedAt ?: return@filter false
            ended > start && ended <= end
        }
        val fluentTurns = windowSessions.flatMap { s ->
            s.turns.filter { it.role == TurnRole.FLUENT_SELF && !it.excludedFromScoring }.map { s to it }
        }
        val userTurns = windowSessions.flatMap { s ->
            s.turns.filter { it.role == TurnRole.USER && !it.excludedFromScoring }.map { s to it }
        }

        val items = ArrayList<WeeklyTestItem>()
        items += meaningItems(windowSessions, material, language, level, rng, gloss)
        // What the Expressions page lists under "To study" — the learner's
        // own study list, and the reason a fluent-self line is worth a
        // question at all.
        val toStudy = material.toStudy.filter { TextScript.isInTargetScript(it, language) }
        val studyPhrases = toStudy.map { it.lowercase() }
        // A call's first fluent-self line is its greeting — the same few
        // words every call, never the material.
        val openers = material.sessions.mapNotNull { s ->
            s.turns.firstOrNull { it.role == TurnRole.FLUENT_SELF }?.id
        }.toSet()
        val teachingTurns = fluentTurns.filter { it.second.id !in openers }
        items += gapItems(toStudy, windowSessions, teachingTurns, material.sessions, openers,
            material.sceneExamples, material.libraryExpressions, language, rng)
        items += translateItems(material, start, end, now, windowSessions, language, level, id)
        val listens = listenItems(teachingTurns, studyPhrases, material.hasAudio, language, rng)
        items += listens
        items += speakItems(teachingTurns, studyPhrases,
            listens.map { CarryoverDetector.normalized(it.answer) }.toSet(), language, rng)
        // What the week's report found: grammar that keeps going wrong and
        // words leaned on too often (iOS `9617756`).
        items += grammarItems(material, userTurns, language, rng)
        items += upgradeItems(material, userTurns, language, level, rng)
        // What recent weeks got wrong is asked again — the test is a review,
        // and a miss is the most certain material there is.
        val recent = (recentTests + listOfNotNull(lastTest))
            .filter { it.isFinished && !it.isMonthly }
            .associateBy { it.id }.values
            .sortedByDescending { it.createdAt }
            .take(RETAKE_WEEKS)
        if (recent.isNotEmpty()) {
            val fresh = items.map(::itemKey).toSet()
            items += retakes(recent, MAX_RETAKE, fresh, language, rng) {
                asRewrite(it, material.cards, material.sessions, language)
            }
        }
        if (items.size < MIN_ITEMS) return null
        items.shuffle(rng)
        // A test opens on something you can answer by reading.
        if (items.first().kind == WeeklyTestItem.Kind.LISTEN) {
            val swap = items.indexOfFirst { it.kind != WeeklyTestItem.Kind.LISTEN }
            if (swap > 0) java.util.Collections.swap(items, 0, swap)
        }
        return WeeklyTest(id = id, targetLanguage = language, periodStart = start, periodEnd = end,
            createdAt = now, items = items)
    }

    /** Wrong answers of [tests], newest test first, one per distinct answer,
     *  as fresh items with their choices reshuffled. A miss that a NEWER test
     *  asked again is that test's to report: answered right there, it is done
     *  and never comes back; wrong again, the newer miss is the one dealt. */
    fun retakes(tests: List<WeeklyTest>, limit: Int, excluding: Set<String>,
                        language: String, rng: Random,
                        /** A stored tile item as its rewrite ([asRewrite]); null drops it. */
                        rewrite: (WeeklyTestItem) -> WeeklyTestItem?): List<WeeklyTestItem> {
        val out = ArrayList<WeeklyTestItem>()
        val seen = excluding.toHashSet()
        for (test in tests.sortedByDescending { it.createdAt }) {
            val wrong = test.answers.filter { !it.correct }.map { it.itemId }.toSet()
            val asked = test.items.map(::itemKey)
            for (stored in test.items) {
                if (stored.id !in wrong || !isValid(stored, language)) continue
                if (out.size >= limit) return out
                // A missed tile item comes back as the rewrite it is now.
                val item = (if (stored.kind == WeeklyTestItem.Kind.BUILD) rewrite(stored) else stored)
                    ?: continue
                if (itemKey(item) in seen) continue
                // Build tiles are dealt afresh, so a stored item picks up
                // today's decoy rule instead of its old tiles.
                val options = when (item.kind) {
                    WeeklyTestItem.Kind.BUILD, WeeklyTestItem.Kind.GRAMMAR ->
                        buildTiles(item.answer, item.prompt, language, rng)
                    WeeklyTestItem.Kind.LISTEN -> dictationTiles(item.answer, language, rng)
                    else -> item.options.shuffled(rng)
                }
                out += item.copy(id = StoreJson.newId(), options = options, isRetake = true)
                seen += itemKey(item)
            }
            seen += asked
        }
        return out
    }

    /** This test's misses dealt again as a paper of their own — played in
     *  place, never saved. Null when nothing was missed. */
    fun retryPaper(test: WeeklyTest, now: Long = System.currentTimeMillis(),
                   rewrite: (WeeklyTestItem) -> WeeklyTestItem?): WeeklyTest? {
        val items = retakes(listOf(test), MAX_RETRY, emptySet(), test.targetLanguage,
            WeeklyTestRandom(StoreJson.newId()), rewrite)
        if (items.isEmpty()) return null
        return WeeklyTest(targetLanguage = test.targetLanguage, kind = test.kind,
            periodStart = test.periodStart, periodEnd = test.periodEnd, createdAt = now,
            startedAt = now, items = items)
    }

    /** An item that still passes today's rules, judged in the TEST's own
     *  language — never the active pointer (iOS `2bbe007`). */
    fun isValid(item: WeeklyTestItem, language: String): Boolean {
        fun ok(t: String) = TextScript.isInTargetScript(t, language)
        if (!ok(item.answer)) return false
        return when (item.kind) {
            WeeklyTestItem.Kind.BUILD, WeeklyTestItem.Kind.GRAMMAR, WeeklyTestItem.Kind.UPGRADE ->
                ok(item.prompt) && item.options.all(::ok)
            WeeklyTestItem.Kind.REWRITE -> ok(item.prompt)
            WeeklyTestItem.Kind.TRANSLATE -> true
            WeeklyTestItem.Kind.GAP -> ok(item.prompt.replace(BLANK_MARK, "")) && item.options.all(::ok)
            WeeklyTestItem.Kind.MEANING, WeeklyTestItem.Kind.LISTEN -> item.options.all(::ok)
            WeeklyTestItem.Kind.SPEAK -> true
        }
    }

    /** A test in progress with its not-yet-answered invalid items removed,
     *  stale tiles re-dealt and tile items turned into rewrites. Null when
     *  nothing changed. */
    fun pruned(test: WeeklyTest, rewrite: (WeeklyTestItem) -> WeeklyTestItem?): WeeklyTest? {
        val answered = test.answers.map { it.itemId }.toSet()
        var changed = false
        val rng = WeeklyTestRandom(test.id)
        val kept = ArrayList<WeeklyTestItem>()
        for (item in test.items) {
            if (item.id in answered) { kept += item; continue }
            if (!isValid(item, test.targetLanguage)) { changed = true; continue }
            // A listen item minted as pick-one-of-three becomes dictation.
            if (item.kind == WeeklyTestItem.Kind.LISTEN &&
                item.options.any { WordSplitter.count(it, test.targetLanguage) > 1 }) {
                kept += item.copy(prompt = "", options = dictationTiles(item.answer, test.targetLanguage, rng))
                changed = true; continue
            }
            // An unanswered tile item becomes the rewrite that replaced it;
            // one whose card is gone leaves the paper.
            if (item.kind == WeeklyTestItem.Kind.BUILD) {
                changed = true
                rewrite(item)?.let { kept += it.copy(id = item.id, options = emptyList(), isRetake = item.isRetake) }
                continue
            }
            kept += item
        }
        return if (changed) test.copy(items = kept) else null
    }

    /** One identity per thing asked, whatever the prompt's wording. */
    fun itemKey(item: WeeklyTestItem): String =
        "${item.kind.name.lowercase()}|${CarryoverDetector.normalized(item.answer)}"

    // ── speak

    /** Fluent-self sentences of 4–16 words that carry a phrase on the "To
     *  study" list — saying it is studying it — and never a line the listen
     *  items already used. No such line, no item: a sentence picked for its
     *  length alone is what read as random. */
    private fun speakItems(fluentTurns: List<Pair<Session, Turn>>, studyPhrases: List<String>,
                           excluding: Set<String>, language: String, rng: Random): List<WeeklyTestItem> {
        data class Line(val text: String, val session: Session, val lineId: String, val weight: Int)
        val lines = ArrayList<Line>()
        val seen = excluding.toHashSet()
        for ((session, turn) in fluentTurns) {
            val parts = TalkCurriculum.sentences(turn.transcript)
            parts.forEachIndexed { index, sentence ->
                val n = WordSplitter.count(sentence, language)
                if (n < 4 || n > 16 || !TextScript.isInTargetScript(sentence, language)) return@forEachIndexed
                if (!seen.add(CarryoverDetector.normalized(sentence))) return@forEachIndexed
                val lower = sentence.lowercase()
                val weight = studyPhrases.count { lower.contains(it) }
                if (weight == 0) return@forEachIndexed
                // The line's identity is the talk book's: a one-sentence turn
                // keeps its turn id, a cut sentence the book's sentence id —
                // the turn's audio must never play for a sentence.
                val lineId = if (parts.size == 1) turn.id else TalkCurriculum.sentenceLineId(turn.id, index)
                lines += Line(sentence, session, lineId, weight)
            }
        }
        return lines.shuffled(rng).sortedByDescending { it.weight }.take(MAX_SPEAK).map {
            WeeklyTestItem(kind = WeeklyTestItem.Kind.SPEAK, prompt = "", answer = it.text,
                sessionId = it.session.id, turnId = it.lineId)
        }
    }

    // ── meaning

    private suspend fun meaningItems(sessions: List<Session>, material: Material, language: String,
                                     level: CefrLevel, rng: Random,
                                     gloss: suspend (String) -> String?): List<WeeklyTestItem> {
        // The words come from the week's talk BOOKS and nowhere else (iOS
        // `36342dd`): a book's Words chapter is already the fluent self's
        // words at or above the learner's level, minus every word the learner
        // said in that talk. The old sources (the whole notebook, then words
        // the learner had USED this week) could hand a B2 learner "house".
        // Not yet mastered first; a thin week asks fewer word questions
        // rather than reaching outside.
        val unmastered = ArrayList<String>()
        val mastered = ArrayList<String>()
        val seen = HashSet<String>()
        for (session in sessions.sortedByDescending { it.endedAt ?: it.startedAt }) {
            for ((w, done) in material.bookWords(session)) {
                val k = w.lowercase()
                if (k.isEmpty() || k in seen || !TextScript.isInTargetScript(w, language)) continue
                seen += k
                if (done) mastered += w else unmastered += w
            }
        }
        val candidates = unmastered.shuffled(rng) + mastered.shuffled(rng)

        // Decoys: the graded list at the learner's level, then the two
        // neighbouring bands; the learner's own words where there's no list.
        val graded = ArrayList<String>()
        for (band in decoyBands(level)) {
            graded += material.graded(band).filter { it.lowercase() !in seen }.shuffled(rng)
        }
        if (graded.size < CHOICE_COUNT) {
            graded += material.recorded.filter { it.lowercase() !in seen &&
                TextScript.isInTargetScript(it, language) }.shuffled(rng)
        }

        val out = ArrayList<WeeklyTestItem>()
        for (word in candidates) {
            if (out.size >= MAX_MEANING) break
            val sense = gloss(word)?.trim().orEmpty()
            // A gloss that repeats the word teaches nothing and gives it away.
            if (sense.isEmpty() || sense.lowercase().contains(word.lowercase())) continue
            val decoys = meaningDecoys(word, candidates, graded, language, rng)
            if (decoys.size != CHOICE_COUNT - 1) continue
            out += WeeklyTestItem(kind = WeeklyTestItem.Kind.MEANING, prompt = sense, answer = word,
                options = (listOf(word) + decoys).shuffled(rng))
        }
        return out
    }

    /** The learner's level and its two neighbours, nearest first. */
    fun decoyBands(level: CefrLevel): List<CefrLevel> {
        val all = CefrLevel.entries
        val i = all.indexOf(level)
        val bands = mutableListOf(level)
        if (i > 0) bands += all[i - 1]
        if (i + 1 < all.size) bands += all[i + 1]
        return bands
    }

    /**
     * The wrong choices for a meaning item. Same word class FIRST
     * ([WordClass]): a verb's gloss must not be answerable by ruling out three
     * nouns. Inside a class the learner's own pool comes before the graded
     * list; only when the class runs dry do other-class words fill the row.
     */
    fun meaningDecoys(word: String, own: List<String>, graded: List<String>,
                      language: String, rng: Random): List<String> {
        fun same(w: String) = WordClass.sameClass(word, w, language)
        val others = own.filter { !it.equals(word, ignoreCase = true) }
        val ownSame = others.filter(::same)
        val ownRest = others.filterNot(::same)
        val gradedSame = graded.asSequence().filter(::same).take(30).toList()
        val ordered = ownSame.shuffled(rng) + gradedSame.shuffled(rng) + ownRest.shuffled(rng) + graded
        return dedupe(ordered.filter { !it.equals(word, ignoreCase = true) }) { it.lowercase() }
            .take(CHOICE_COUNT - 1)
    }

    // ── gap

    private fun exprKey(p: String) = CarryoverDetector.normalized(p)

    /** A "To study" expression with its line blanked out, newest first —
     *  the list the learner keeps on the Expressions page, in the sentence
     *  they met it in: this week's talks first, then any talk, then the
     *  scene that taught it. A phrase with no such line is skipped. */
    private fun gapItems(toStudy: List<String>, sessions: List<Session>,
                         fluentTurns: List<Pair<Session, Turn>>, allSessions: List<Session>,
                         openers: Set<String>, sceneExamples: Map<String, String>,
                         library: List<String>, language: String, rng: Random): List<WeeklyTestItem> {
        data class Candidate(val phrase: String, val sentence: String, val session: Session?, val turn: Turn?)
        val anyFluent = allSessions.flatMap { s ->
            s.turns.filter { it.role == TurnRole.FLUENT_SELF && !it.excludedFromScoring && it.id !in openers }
                .map { s to it }
        }
        val candidates = ArrayList<Candidate>()
        for (phrase in toStudy) {
            if (candidates.size >= MAX_GAP * 3) break
            val hit = firstSentence(phrase, fluentTurns, language) ?: firstSentence(phrase, anyFluent, language)
            if (hit != null) {
                candidates += Candidate(phrase, hit.first, hit.second, hit.third)
                continue
            }
            val example = sceneExamples[phrase.trim().lowercase()] ?: continue
            if (example.contains(phrase, ignoreCase = true) && TextScript.isInTargetScript(example, language)) {
                candidates += Candidate(phrase, example, null, null)
            }
        }

        // Decoys: every other phrase of the week first — they are the ones
        // that could plausibly fit — then the rest of the study list, and the
        // library only to fill the row.
        var weekPool = emptyList<String>()
        for (s in sessions) {
            weekPool = weekPool + s.summary?.expressionsOffered.orEmpty() + s.summary?.expressionsUsed.orEmpty()
        }
        weekPool = dedupe(weekPool + toStudy, ::exprKey)
        val libraryPool = dedupe(library, ::exprKey)

        val out = ArrayList<WeeklyTestItem>()
        // Newest first, as the list shows them — the top of it is what the
        // learner is studying now.
        for (c in candidates) {
            if (out.size >= MAX_GAP) break
            val key = exprKey(c.phrase)
            fun fits(p: String) = exprKey(p) != key && !c.sentence.lowercase().contains(p.lowercase()) &&
                TextScript.isInTargetScript(p, language)
            val decoys = dedupe(weekPool.filter(::fits).shuffled(rng) + libraryPool.filter(::fits).shuffled(rng),
                ::exprKey).take(CHOICE_COUNT - 1)
            val prompt = blank(c.phrase, c.sentence)
            if (decoys.size != CHOICE_COUNT - 1 || prompt == null) continue
            out += WeeklyTestItem(kind = WeeklyTestItem.Kind.GAP, prompt = prompt, answer = c.phrase,
                options = (listOf(c.phrase) + decoys).shuffled(rng),
                sessionId = c.session?.id, turnId = c.turn?.id)
        }
        return out
    }

    /** The first sentence in [turns] containing [phrase], short enough to
     *  read as one line — a gap item never shows a whole turn. */
    private fun firstSentence(phrase: String, turns: List<Pair<Session, Turn>>,
                              language: String): Triple<String, Session, Turn>? {
        val needle = phrase.lowercase()
        for ((session, turn) in turns) {
            for (sentence in TalkCurriculum.sentences(turn.transcript)) {
                if (!sentence.lowercase().contains(needle)) continue
                val n = WordSplitter.count(sentence, language)
                if (n < 4 || n > 30 || !TextScript.isInTargetScript(sentence, language)) continue
                return Triple(sentence, session, turn)
            }
        }
        return null
    }

    /** [sentence] with the first case- and diacritic-insensitive occurrence
     *  of [phrase] replaced by the blank mark. */
    fun blank(phrase: String, sentence: String): String? {
        if (phrase.isEmpty()) return null
        val at = fold(sentence).indexOf(fold(phrase))
        if (at < 0) return null
        return sentence.substring(0, at) + BLANK_MARK + sentence.substring(at + phrase.length)
    }

    /** Lowercased with diacritics dropped, one char per char — so an index
     *  into the fold is an index into the original. */
    private fun fold(s: String): String = buildString(s.length) {
        for (c in s) {
            val stripped = Normalizer.normalize(c.toString(), Normalizer.Form.NFD)
                .filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }
            append((if (stripped.length == 1) stripped[0] else c).lowercaseChar())
        }
    }

    // ── build

    /** The corrections touched this window, due first then newest, each as
     *  the learner's WHOLE sentence to say or type again the right way. */
    private fun rewriteItems(cards: List<DrillCard>, start: Long, end: Long, now: Long,
                             sessions: List<Session>, language: String): List<WeeklyTestItem> {
        val pool = cards.filter { card ->
            if (card.box >= DrillIngest.MAX_BOX || card.sourcePhrase.isBlank()) return@filter false
            if (!TextScript.isInTargetScript(card.targetPhrase, language) ||
                !TextScript.isInTargetScript(card.sourcePhrase, language)) return@filter false
            val touched = listOfNotNull(card.createdAt, card.lastReviewedAt)
            touched.any { it > start && it <= end }
        }
        val ordered = pool.sortedWith(compareBy<DrillCard> { if (it.nextReviewAt <= now) 0 else 1 }
            .thenByDescending { it.createdAt })
        val byId = sessions.associateBy { it.id }
        val out = ArrayList<WeeklyTestItem>()
        val seen = HashSet<String>()
        for (card in ordered) {
            if (out.size >= MAX_REWRITE) break
            val item = rewriteItem(card, byId, language) ?: continue
            if (!seen.add(itemKey(item))) continue
            out += item
        }
        return out
    }

    /**
     * One correction card as a rewrite item. What the learner reads is what
     * they said around the slip: the sentence it sits in, or — when that
     * sentence runs past [rewriteClauseFrom] words, which a spoken turn
     * usually does, since the recognizer joins it with commas — just the
     * comma-bounded clause holding it. The answer is that same span with the
     * card's fix applied. Hesitation sounds ([SpeechLibrary.fillers]) are
     * taken out of both: they are not the mistake, and "consistent uh issue"
     * is hard to read back. `focus` / `example` carry the fix itself (what was
     * said → what it should be), which is what the grade and the hint read.
     * Null when the span is still too short or long to write out, or the fix
     * changes nothing.
     *
     * Until the clause cut (iOS 2026-10-08, same day as the item) the whole
     * sentence had to fit 25 words, and real spoken turns run 29–34 words —
     * so almost no real correction ever became an item.
     */
    fun rewriteItem(card: DrillCard, sessions: Map<String, Session>, language: String): WeeklyTestItem? {
        val was = card.sourcePhrase.trim()
        val now = card.targetPhrase.trim()
        var said = was
        var answer = now
        val turn = card.sourceSessionId?.let { sessions[it] }?.turns
            ?.firstOrNull { it.id == card.sourceTurnId }
        if (turn != null) {
            for (sentence in TalkCurriculum.sentences(turn.transcript)) {
                val range = foldedRange(sentence, was) ?: continue
                val span = if (WordSplitter.count(sentence, language) > rewriteClauseFrom(language))
                    clauseRange(range, sentence) else sentence.indices
                val clause = sentence.substring(span.first, span.last + 1)
                val local = foldedRange(clause, was) ?: continue
                said = clause
                answer = clause.replaceRange(local, now)
                break
            }
        }
        said = withoutFillers(said, language)
        answer = withoutFillers(answer, language)
        val n = WordSplitter.count(said, language)
        if (n < 3 || n > (if (WordSplitter.spaced(language)) 25 else 40) ||
            CarryoverDetector.normalized(said) == CarryoverDetector.normalized(answer)) return null
        return WeeklyTestItem(kind = WeeklyTestItem.Kind.REWRITE, prompt = said, answer = answer,
            sessionId = card.sourceSessionId, turnId = card.sourceTurnId,
            cardId = card.id, note = card.reason, focus = was, example = now)
    }

    // ── translate

    /** One mistake a translate item can be built on: what was said, what it
     *  should be, why, and the card it came from (for write-back). */
    data class Slip(val was: String, val now: String, val why: String, val cardId: String?)

    /** The mistakes to build on: this window's correction cards, due first
     *  then newest, then the profile's recurring mistakes — deduped. */
    fun slips(cards: List<DrillCard>, mistakes: List<LearnerPattern>, start: Long, end: Long, now: Long,
              language: String, sessions: List<Session> = emptyList()): List<Slip> {
        val window = cards.filter { card ->
            if (card.box >= DrillIngest.MAX_BOX || card.sourcePhrase.isBlank()) return@filter false
            if (!TextScript.isInTargetScript(card.targetPhrase, language) ||
                !TextScript.isInTargetScript(card.sourcePhrase, language)) return@filter false
            listOfNotNull(card.createdAt, card.lastReviewedAt).any { it > start && it <= end }
        }.sortedWith(compareBy<DrillCard> { if (it.nextReviewAt <= now) 0 else 1 }
            .thenByDescending { it.createdAt })
        val out = ArrayList<Slip>()
        val seen = HashSet<String>()
        fun add(s: Slip) { if (seen.add(CarryoverDetector.normalized(s.was))) out += s }
        for (c in window) add(Slip(c.sourcePhrase, c.targetPhrase, c.reason, c.id))
        val fresh = now - GrammarFocus.FRESH_DAYS * 86_400_000L
        // A profile pattern only when the learner really said it in a talk
        // (`GrammarFocus.evidence`) — its frequency was inflated for weeks.
        for (p in mistakes) {
            if (p.lastSeenAt < fresh) continue
            if (!TextScript.isInTargetScript(p.mistake, language) ||
                !TextScript.isInTargetScript(p.correction, language)) continue
            if (GrammarFocus.evidence(p, sessions, now) < 1) continue
            add(Slip(p.mistake, p.correction, p.context, null))
        }
        return out.take(10)
    }

    /** New sentences that need the grammar the learner got wrong, laid from
     *  word tiles. One model call writes each sentence, the other word orders
     *  that are just as right, and trap words built from the learner's own
     *  mistake; code grades the laid tiles against that closed set. A free
     *  answer (typed or said) was tried first and could not be graded
     *  exactly: a slip elsewhere passed and a synonym failed (founder,
     *  2026-10-08: "that limit can't be there"). Nothing when the target IS
     *  the native language (there is nothing to translate from) or the call
     *  fails. */
    private suspend fun translateItems(material: Material, start: Long, end: Long, now: Long,
                                       windowSessions: List<Session>, target: String, level: CefrLevel,
                                       testId: String): List<WeeklyTestItem> {
        val write = material.writeTranslate ?: return emptyList()
        val native = material.nativeLanguage
        if (native.isEmpty() || LanguageCatalog.sameLanguage(target, native)) return emptyList()
        val list = slips(material.cards, material.profileMistakes, start, end, now, target, material.sessions)
        if (list.isEmpty()) return emptyList()
        val topics = windowSessions.mapNotNull { it.topic }.filter { it.isNotEmpty() }.take(6)
        val targetName = LanguageCatalog.englishName(target)
        val nativeName = LanguageCatalog.englishName(native)
        val system = "You write a short translation quiz for a $targetName learner whose own " +
            "language is $nativeName, level ${level.code.uppercase()}. " +
            "They answer by laying word tiles in order. You get mistakes they really " +
            "made. Pick up to $MAX_TRANSLATE of them, each a DIFFERENT grammar point " +
            "(skip pure word choice or a slip with no rule behind it), and for each " +
            "write ONE new everyday sentence that cannot be said right without that " +
            "grammar point.\n" +
            "\n" +
            "Return {\"items\":[{\"source\":n,\"point\":\"...\",\"native\":\"...\",\"answer\":\"...\"," +
            "\"orders\":[\"...\"],\"decoys\":[\"...\"],\"tip\":\"...\"}]}\n" +
            "- source: the number of the mistake it is built on.\n" +
            "- native: the sentence in $nativeName, casual and spoken, the way they'd " +
            "say it to a friend, 6–12 words, about ordinary life (these were their " +
            "topics: ${topics.joinToString("; ")}). NOT their original sentence.\n" +
            "- answer: the most natural $targetName way to say it, at their level, " +
            "5–12 words. Its words are the tiles, so there must be ONE wording: no " +
            "optional words, nothing a learner could naturally say differently " +
            "with other words.\n" +
            "- orders: every OTHER order of exactly the same words that is just as " +
            "correct. Go through each time, place and duration phrase (\"for two " +
            "years\", \"yesterday\", \"at midnight\") and each adverb, and list the " +
            "sentence with it at the front too wherever that is natural — a " +
            "learner who lays a right order and is marked wrong stops trusting " +
            "the test. [] only if the order is truly fixed.\n" +
            "- decoys: 2–3 single words built from their mistake (e.g. \"since\", \"am\" " +
            "for \"I am working here since 2020\") that make the sentence WRONG " +
            "wherever they go, and are not in answer.\n" +
            "- point: the grammar point in $nativeName, 2–5 words. tip: one line in " +
            "$nativeName on when it applies, at most 14 words.\n" +
            "JSON only."
        val user = list.mapIndexed { i, s ->
            "${i + 1}. said \"${s.was}\" → should be \"${s.now}\"" + (if (s.why.isEmpty()) "" else " (${s.why})")
        }.joinToString("\n")
        val payload = runCatching { write(system, user, testId) }.getOrNull() ?: return emptyList()
        val rng = WeeklyTestRandom(testId)
        val out = ArrayList<WeeklyTestItem>()
        val points = HashSet<String>()
        for (it in payload.items) {
            if (out.size >= MAX_TRANSLATE || it.source - 1 !in list.indices) continue
            val slip = list[it.source - 1]
            val item = translateItem(it.native, it.answer, it.orders.orEmpty(), it.decoys.orEmpty(), it.point,
                it.tip, slip, target, rng) ?: continue
            if (!points.add(it.point.lowercase())) continue
            out += item
        }
        return out
    }

    /** A model-written translate item, or null. Kept only when the answer is
     *  a tileable sentence in the target script; `orders` keep only the ones
     *  made of exactly the answer's words; a decoy must be one target-script
     *  word the answer doesn't use. Tiles = the answer's words + decoys. */
    fun translateItem(native: String, answer: String, orders: List<String>, decoys: List<String>,
                      point: String, tip: String?, slip: Slip, target: String, rng: Random): WeeklyTestItem? {
        val words = WordSplitter.words(answer, target)
        val keys = words.map(::tileKey)
        if (words.size < 3 || words.size > (if (WordSplitter.spaced(target)) 14 else 20) ||
            !TextScript.isInTargetScript(answer, target) || native.isEmpty() ||
            CarryoverDetector.normalized(native) == CarryoverDetector.normalized(answer)) return null
        val sameWords = keys.sorted()
        val kept = dedupe(orders.filter {
            val k = WordSplitter.words(it, target).map(::tileKey)
            k.sorted() == sameWords && k != keys
        }) { WordSplitter.words(it, target).map(::tileKey).joinToString(" ") }
        val answerKeys = keys.toSet()
        val traps = dedupe(decoys.map { it.trim() }.filter {
            it.isNotEmpty() && WordSplitter.count(it, target) == 1 && tileKey(it) !in answerKeys &&
                TextScript.isInTargetScript(it, target)
        }, ::tileKey).take(3)
        val tiles = (words + traps).shuffled(rng).toMutableList()
        if (tiles.size > 2 && tiles.map(::tileKey) == keys) java.util.Collections.swap(tiles, 0, tiles.lastIndex)
        return WeeklyTestItem(kind = WeeklyTestItem.Kind.TRANSLATE, prompt = native, answer = answer,
            options = tiles, cardId = slip.cardId, note = tip, rule = point,
            focus = slip.was, example = slip.now, orders = kept)
    }

    /** Past this many words a sentence is cut to the clause holding the slip. */
    fun rewriteClauseFrom(language: String): Int = if (WordSplitter.spaced(language)) 16 else 30

    private val CLAUSE_MARKS = setOf(',', ';', '、', '，', '；')

    /** The comma/semicolon-bounded stretch of [sentence] holding [range],
     *  trimmed. The slip's own span is never cut, even when it crosses a
     *  comma. */
    fun clauseRange(range: IntRange, sentence: String): IntRange {
        var lower = range.first
        while (lower > 0 && sentence[lower - 1] !in CLAUSE_MARKS) lower--
        var upper = range.last + 1
        while (upper < sentence.length && sentence[upper] !in CLAUSE_MARKS) upper++
        while (lower < upper && sentence[lower].isWhitespace()) lower++
        while (upper > lower && sentence[upper - 1].isWhitespace()) upper--
        return lower until upper
    }

    private fun isPunctuation(c: Char): Boolean = when (Character.getType(c).toByte()) {
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION -> true
        else -> false
    }

    /** [text] with the language's hesitation sounds taken out, and the
     *  commas they leave behind tidied. Spaced languages drop whole words
     *  only; Japanese drops the sound wherever it stands, with its 、. */
    fun withoutFillers(text: String, language: String): String {
        val fillers = SpeechLibrary.fillers(language).map { it.lowercase() }.toSet() -
            "este"   // Spanish "this" as often as a filler
        if (fillers.isEmpty()) return text
        var out: String
        if (WordSplitter.spaced(language)) {
            out = text.split(' ').filter { it.isNotEmpty() }.filter { word ->
                word.lowercase().trim(::isPunctuation) !in fillers
            }.joinToString(" ")
        } else {
            out = text
            for (f in fillers.sortedByDescending { it.length }) {
                out = out.replace(f + "、", "")
                out = out.replace(f, "")
            }
        }
        // ", ," and a leading comma are what a removed "um," leaves behind.
        while (out.contains(", ,")) out = out.replace(", ,", ",")
        return out.trim { it == ',' || it == '、' || it.isWhitespace() }
    }

    /** A stored tile item ([WeeklyTestItem.Kind.BUILD]) as the rewrite that
     *  replaced it, read from its card. Null when the card is gone. */
    fun asRewrite(item: WeeklyTestItem, cards: List<DrillCard>, sessions: List<Session>,
                  language: String): WeeklyTestItem? {
        val id = item.cardId ?: return null
        val card = cards.firstOrNull { it.id == id } ?: return null
        val out = rewriteItem(card, sessions.associateBy { it.id }, language) ?: return null
        return out.copy(isRetake = item.isRetake)
    }

    /** A line's own words, shuffled and never in order — the listen item's
     *  tiles. No decoys: the ear supplies the difficulty. */
    fun dictationTiles(text: String, language: String, rng: Random): List<String> {
        val words = WordSplitter.words(text, language)
        val tiles = words.shuffled(rng).toMutableList()
        if (tiles.size > 2 && tiles.map(::tileKey) == words.map(::tileKey)) {
            java.util.Collections.swap(tiles, 0, tiles.lastIndex)
        }
        return tiles
    }

    /**
     * The target's words plus up to [MAX_DECOY_TILES] decoys — words the
     * correction REPLACED, never ones it merely left out (iOS `3f5a082`).
     * A tile set that spells the answer in order is not a test.
     */
    fun buildTiles(target: String, source: String, language: String, rng: Random): List<String> {
        val targetWords = WordSplitter.words(target, language)
        val decoys = dedupe(replacedWords(WordSplitter.words(source, language), targetWords)
            .filter { TextScript.isInTargetScript(it, language) }, ::tileKey)
            .shuffled(rng).take(MAX_DECOY_TILES)
        val tiles = (targetWords + decoys).shuffled(rng).toMutableList()
        if (tiles.size > 2 && tiles.map(::tileKey) == targetWords.map(::tileKey)) {
            java.util.Collections.swap(tiles, 0, tiles.lastIndex)
        }
        return tiles
    }

    /** The tiles the answer doesn't use — a build item's decoys, i.e. the
     *  learner's own words the correction replaced (iOS `cf5b08d`). Read off
     *  the item (tiles minus the answer's words, as a multiset) so items
     *  already on disk need nothing new. Empty for dictation. */
    fun decoyTiles(item: WeeklyTestItem, language: String): List<String> {
        val needed = HashMap<String, Int>()
        for (w in WordSplitter.words(item.answer, language)) needed.merge(tileKey(w), 1, Int::plus)
        return item.options.filter { tile ->
            val key = tileKey(tile)
            val n = needed[key] ?: 0
            if (n > 0) { needed[key] = n - 1; false } else true
        }
    }

    // ── report (grammar · upgrade)

    /** Where [needle] sits in [text], case- and diacritic-insensitively. */
    fun foldedRange(text: String, needle: String): IntRange? {
        val n = needle.trim()
        if (n.isEmpty()) return null
        val at = fold(text).indexOf(fold(n))
        return if (at < 0) null else at until at + n.length
    }

    private data class LearnerHit(val sentence: String, val range: IntRange, val session: Session, val turn: Turn)

    /** The first sentence of the window's learner lines that QUOTES [span]
     *  (the report's quotes were checked against every language's lines;
     *  this keeps them to the active one), with the span's range in it. */
    private fun learnerSentence(span: String, userTurns: List<Pair<Session, Turn>>, maxWords: Int,
                                language: String): LearnerHit? {
        for ((session, turn) in userTurns) {
            for (sentence in TalkCurriculum.sentences(turn.transcript)) {
                val range = foldedRange(sentence, span) ?: continue
                val n = WordSplitter.count(sentence, language)
                if (n < 3 || n > maxWords || !TextScript.isInTargetScript(sentence, language)) continue
                return LearnerHit(sentence, range, session, turn)
            }
        }
        return null
    }

    /**
     * One item per recurring grammar point: the rule, one of the learner's
     * own lines with the mistake in it, rebuilt right from tiles (the wrong
     * words ride along as decoys — [buildTiles]). The report's points come
     * first; when it has none (or none found in this week's lines) the
     * profile's recurring mistakes stand in, named by `GrammarFocus`.
     */
    private suspend fun grammarItems(material: Material, userTurns: List<Pair<Session, Turn>>,
                                     language: String, rng: Random): List<WeeklyTestItem> {
        val maxWords = if (WordSplitter.spaced(language)) 12 else 18
        val out = ArrayList<WeeklyTestItem>()
        val seen = HashSet<String>()
        fun make(rule: String, tip: String, was: String, fixed: String): WeeklyTestItem? {
            val hit = learnerSentence(was, userTurns, maxWords, language) ?: return null
            val answer = hit.sentence.replaceRange(hit.range, fixed)
            val key = CarryoverDetector.normalized(answer)
            if (!TextScript.isInTargetScript(answer, language) ||
                key == CarryoverDetector.normalized(hit.sentence) || !seen.add(key)) return null
            return WeeklyTestItem(kind = WeeklyTestItem.Kind.GRAMMAR, prompt = hit.sentence, answer = answer,
                options = buildTiles(answer, hit.sentence, language, rng),
                sessionId = hit.session.id, turnId = hit.turn.id,
                note = tip.ifEmpty { null }, rule = rule, focus = was)
        }
        for (pattern in material.coach?.grammar.orEmpty()) {
            if (out.size >= MAX_GRAMMAR) break
            for (example in pattern.examples.shuffled(rng)) {
                val item = make(pattern.rule, pattern.tip, example.was, example.now) ?: continue
                out += item; break
            }
        }
        for (pattern in material.mistakes) {
            if (out.size >= MAX_GRAMMAR) break
            if (learnerSentence(pattern.mistake, userTurns, maxWords, language) == null) continue
            val (label, tip) = material.describeMistake(pattern) ?: continue
            out += make(label, tip, pattern.mistake, pattern.correction) ?: continue
        }
        return out
    }

    /**
     * One item per leaned-on word: the learner's line with it marked, and the
     * report's better word among three that don't belong — the week's other
     * better words first, then graded words of the same class one band above
     * the learner (the band the report reaches for).
     */
    private fun upgradeItems(material: Material, userTurns: List<Pair<Session, Turn>>,
                             language: String, level: CefrLevel, rng: Random): List<WeeklyTestItem> {
        val upgrades = material.coach?.upgrades.orEmpty()
        if (upgrades.isEmpty()) return emptyList()
        val all = CefrLevel.entries
        val oneUp = all[minOf(all.indexOf(level) + 1, all.lastIndex)]
        val graded = ArrayList<String>()
        for (band in decoyBands(oneUp)) graded += material.graded(band).shuffled(rng)
        val maxWords = if (WordSplitter.spaced(language)) 25 else 35
        val out = ArrayList<WeeklyTestItem>()
        for (u in upgrades.shuffled(rng)) {
            if (out.size >= MAX_UPGRADE) break
            if (!TextScript.isInTargetScript(u.better, language) ||
                !TextScript.isInTargetScript(u.instead, language)) continue
            val hit = learnerSentence(u.instead, userTurns, maxWords, language) ?: continue
            val taken = (listOf(u.better, u.instead) + WordSplitter.words(hit.sentence, language))
                .map { it.lowercase() }.toSet()
            fun fits(w: String) = w.lowercase() !in taken && TextScript.isInTargetScript(w, language)
            val week = upgrades.map { it.better }.filter(::fits).shuffled(rng)
            val sameClass = graded.asSequence().filter(::fits)
                .filter { WordClass.sameClass(u.better, it, language) }.take(30).toList()
            val decoys = dedupe(week + sameClass.shuffled(rng) + graded.filter(::fits)) { it.lowercase() }
                .take(CHOICE_COUNT - 1)
            if (decoys.size != CHOICE_COUNT - 1) continue
            out += WeeklyTestItem(kind = WeeklyTestItem.Kind.UPGRADE, prompt = hit.sentence, answer = u.better,
                options = (listOf(u.better) + decoys).shuffled(rng),
                sessionId = hit.session.id, turnId = hit.turn.id,
                note = u.note.ifEmpty { null }, focus = u.instead, example = u.rewritten.ifEmpty { null })
        }
        return out
    }

    // ── listen

    private fun listenItems(fluentTurns: List<Pair<Session, Turn>>, studyPhrases: List<String>,
                            hasAudio: (Turn) -> Boolean,
                            language: String, rng: Random): List<WeeklyTestItem> {
        // Heard and rebuilt from its own word tiles with the text hidden —
        // dictation (iOS `985694e`). Whole turns only: the saved audio is the turn.
        // Only a line carrying a "To study" phrase: hearing it is the point.
        val max = if (WordSplitter.spaced(language)) 14 else 18
        fun fits(text: String): Boolean {
            val n = WordSplitter.count(text, language)
            val lower = text.lowercase()
            return n in 4..max && TextScript.isInTargetScript(text, language) &&
                studyPhrases.any { lower.contains(it) }
        }
        val withAudio = fluentTurns.filter { fits(it.second.transcript) && hasAudio(it.second) }
        val out = ArrayList<WeeklyTestItem>()
        val seen = HashSet<String>()
        for ((session, turn) in withAudio.shuffled(rng)) {
            if (out.size >= MAX_LISTEN) break
            if (!seen.add(CarryoverDetector.normalized(turn.transcript))) continue
            out += WeeklyTestItem(kind = WeeklyTestItem.Kind.LISTEN, prompt = "", answer = turn.transcript,
                options = dictationTiles(turn.transcript, language, rng),
                sessionId = session.id, turnId = turn.id)
        }
        return out
    }

    // ── Grading

    /** A choice item: the picked option against the answer. */
    fun isCorrect(item: WeeklyTestItem, chosen: String): Boolean =
        CarryoverDetector.normalized(chosen) == CarryoverDetector.normalized(item.answer)

    /** A tile item: the tiles in the order the learner laid them — the
     *  answer's order, or (translate) another order the item lists as just
     *  as right. */
    fun isCorrect(item: WeeklyTestItem, tiles: List<String>, language: String): Boolean {
        val laid = tiles.map(::tileKey)
        return (listOf(item.answer) + item.orders.orEmpty())
            .any { WordSplitter.words(it, language).map(::tileKey) == laid }
    }

    /** Laid tiles that are exactly the answer's words — no trap, none left
     *  out — in an order the item doesn't list. The one case code can't
     *  settle: the grammar point is already proved (every word of the right
     *  form, no wrong one), and only whether the ORDER is natural is open. */
    fun isReorder(item: WeeklyTestItem, tiles: List<String>, language: String): Boolean =
        tiles.map(::tileKey).sorted() == WordSplitter.words(item.answer, language).map(::tileKey).sorted() &&
            !isCorrect(item, tiles, language)

    @Serializable
    private data class OrderVerdict(val natural: Boolean)

    /**
     * Is [laid] a natural order of the answer's words, meaning the same? The
     * model generating the item lists the orders it can think of and
     * measurably misses one in about twelve ("For two years I have worked
     * here" unlisted beside "I have worked here for two years", probe
     * 2026-10-08). Asked only for [isReorder] answers, so it judges word order
     * and nothing else; a failed call is the old verdict, wrong.
     */
    suspend fun orderIsNatural(item: WeeklyTestItem, laid: String, language: String): Boolean {
        val name = LanguageCatalog.englishName(language)
        // Told the point and the learner's slip, or it accepts the slip itself
        // as "understandable" (probe 2026-10-08).
        val system = "A learner laid word tiles to say a $name sentence. They used exactly " +
            "the words of the model answer, in a different order. Judge only the " +
            "order: is it grammatical and natural, meaning the same — something a " +
            "careful teacher would accept? Unusual but correct emphasis (a time " +
            "phrase moved to the front) is fine. The quiz tests one grammar point, " +
            "given below with the learner's earlier mistake; an order that repeats " +
            "that mistake is NOT acceptable, even if a listener would understand it.\n" +
            "Return {\"natural\": true} or {\"natural\": false}."
        var user = ""
        item.rule?.let { user += "Grammar point: $it\n" }
        if (item.focus != null && item.example != null) user += "Their earlier mistake: ${item.focus} → ${item.example}\n"
        user += "Model answer: ${item.answer}\nTheir order: $laid"
        val job = coachScope.async {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = system,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                    serializer = OrderVerdict.serializer(),
                    model = GeminiClient.Model.FLASH_LITE_31, maxTokens = 400, purpose = "weekly-test",
                    idempotencyKey = "weekly-test-order:${item.id}:${CarryoverDetector.normalized(laid)}",
                    fastThinking = true)
            }.getOrNull()
        }
        return withTimeoutOrNull(ORDER_WAIT_MS) { job.await() }?.natural ?: false
    }

    private fun lcs(a: List<String>, b: List<String>): Array<IntArray> {
        val dp = Array(a.size + 1) { IntArray(b.size + 1) }
        for (i in a.indices.reversed()) for (j in b.indices.reversed()) {
            dp[i][j] = if (a[i] == b[j]) dp[i + 1][j + 1] + 1 else maxOf(dp[i + 1][j], dp[i][j + 1])
        }
        return dp
    }

    /** Source words sitting in a substitution gap of the source↔target
     *  alignment: the words the correction swapped for others. */
    fun replacedWords(source: List<String>, target: List<String>): List<String> {
        val a = source.map(::tileKey); val b = target.map(::tileKey)
        if (a.isEmpty() || b.isEmpty()) return emptyList()
        val dp = lcs(a, b)
        val out = ArrayList<String>()
        val gapSource = ArrayList<String>(); var gapTargetCount = 0
        fun closeGap() {
            if (gapTargetCount > 0) out += gapSource
            gapSource.clear(); gapTargetCount = 0
        }
        var i = 0; var j = 0
        while (i < a.size && j < b.size) {
            when {
                a[i] == b[j] -> { closeGap(); i++; j++ }
                dp[i + 1][j] >= dp[i][j + 1] -> { gapSource += source[i]; i++ }
                else -> { gapTargetCount++; j++ }
            }
        }
        gapSource += source.subList(i, source.size)
        gapTargetCount += b.size - j
        closeGap()
        return out
    }

    /**
     * A rewrite item: what the learner said or typed. Right when it is the
     * answer sentence, or when it carries the fix (every word the fix added,
     * none it removed — [CarryoverDetector.showsTheFix], the rule that credits
     * a correction in a talk) inside most of the sentence, so a reply of the
     * fixed word alone is not a rewrite. Nothing else counts against it: how
     * the rest is worded is the learner's. (iOS `isCorrect(_:rewritten:)` —
     * renamed here because Kotlin can't overload on the label.)
     *
     * Everything is compared through [ShadowScore.expandForDiff] first:
     * dictation writes "I've" as "I have" and digits for numbers, and an
     * answer said right must not fail on how the recognizer spelled it.
     * Spaces are compared away too (Korean spacing is the recognizer's).
     */
    fun isCorrectRewrite(item: WeeklyTestItem, rewrittenRaw: String, language: String): Boolean {
        // Hesitation is never the mistake, in the slip or in the answer.
        fun expand(t: String) = ShadowScore.expandForDiff(withoutFillers(t, language), language)
        fun squeezed(t: String) = CarryoverDetector.normalized(expand(t)).replace(" ", "")
        val given = CarryoverDetector.normalized(expand(rewrittenRaw))
        if (given.isEmpty()) return false
        if (given.contains(CarryoverDetector.normalized(expand(item.answer))) ||
            squeezed(rewrittenRaw).contains(squeezed(item.answer))) return true
        val was = expand(item.focus ?: return false)
        val now = expand(item.example ?: return false)
        val rewritten = expand(rewrittenRaw)
        // A pure reorder adds and drops nothing; only the fix itself shows it.
        val fixKey = CarryoverDetector.normalized(now)
        if (!CarryoverDetector.fixChangesWords(was, now)) return fixKey.isNotEmpty() && given.contains(fixKey)
        return CarryoverDetector.showsTheFixInText(was, now, rewritten) &&
            CarryoverDetector.sharedWordRatio(expand(item.answer), rewritten) >= 0.6
    }

    /** The words the fix put in — the hint a rewrite item offers. */
    fun hintWords(item: WeeklyTestItem): String? {
        val was = item.focus ?: return null
        val now = item.example ?: return null
        val added = CarryoverDetector.addedWords(was, now)
        return if (added.isEmpty()) now else added.joinToString(" · ")
    }

    /** Which laid tiles sit where the answer wants them, and which of the
     *  answer's words never arrived (iOS `ce2fe49`). */
    data class TileCheck(val correct: List<Boolean>, val answerMatched: List<Boolean>)

    fun tileCheck(tiles: List<String>, answer: String, language: String): TileCheck {
        val a = tiles.map(::tileKey)
        val b = WordSplitter.words(answer, language).map(::tileKey)
        if (a.isEmpty() || b.isEmpty()) return TileCheck(List(a.size) { false }, List(b.size) { false })
        val dp = lcs(a, b)
        val correct = BooleanArray(a.size); val matched = BooleanArray(b.size)
        var i = 0; var j = 0
        while (i < a.size && j < b.size) {
            when {
                a[i] == b[j] -> { correct[i] = true; matched[j] = true; i++; j++ }
                dp[i + 1][j] >= dp[i][j + 1] -> i++
                else -> j++
            }
        }
        return TileCheck(correct.toList(), matched.toList())
    }

    /** Tiles joined back into the sentence the learner built. */
    fun sentence(tiles: List<String>, language: String): String =
        tiles.joinToString(if (WordSplitter.spaced(language)) " " else "")

    fun tileKey(word: String): String = CarryoverDetector.normalized(word)

    // ── Writing back

    /**
     * What a finished test does to the review loop. Runs once per test (the
     * caller stamps `appliedAt`); an answer is a CLAIM, so nothing retires:
     *
     *   meaning  right → the word waits 3 days · wrong → back in the notebook, due now
     *   gap      right → the phrase waits 3 days · wrong → bookmarked, due now
     *   rewrite  right → one Leitner rung up · wrong → one rung down (build alike)
     *   listen / speak → nothing (a spoken take is already a shadow attempt)
     *   grammar  nothing (its corrections already carry cards)
     *   upgrade  wrong → the better word in the notebook, due now
     */
    suspend fun apply(context: Context, test: WeeklyTest, now: Long = System.currentTimeMillis()) {
        val language = test.targetLanguage
        val vocab = VocabStore.shared(context)
        val drills = DrillStore.shared(context)
        val cards = drills.load(language).associateBy { it.id }
        val threeDays = 3 * 86_400_000L
        val byId = test.items.associateBy { it.id }
        for (answer in test.answers) {
            val item = byId[answer.itemId] ?: continue
            when (item.kind) {
                WeeklyTestItem.Kind.MEANING -> {
                    val word = item.answer
                    if (answer.correct) {
                        PracticeLog.record(context, PracticeLog.Kind.WORD)
                        if (vocab.isStudying(word, language)) {
                            ReviewQueue.snooze(context, StudyScheduleStore.Kind.WORD, word, language, threeDays)
                        }
                    } else {
                        vocab.addStudying(word, language)          // records the rep itself
                        ReviewQueue.retire(context, StudyScheduleStore.Kind.WORD, word, language)
                    }
                }
                WeeklyTestItem.Kind.GAP -> {
                    val phrase = item.answer
                    if (answer.correct) {
                        PracticeLog.record(context, PracticeLog.Kind.EXPRESSION)
                        if (vocab.isStudyingExpression(phrase, language)) {
                            ReviewQueue.snooze(context, StudyScheduleStore.Kind.EXPRESSION, phrase, language, threeDays)
                        }
                    } else {
                        if (!vocab.isStudyingExpression(phrase, language)) {
                            vocab.setStudyingExpression(phrase, true, language)
                        } else PracticeLog.record(context, PracticeLog.Kind.EXPRESSION)
                        ReviewQueue.retire(context, StudyScheduleStore.Kind.EXPRESSION, phrase, language)
                    }
                }
                WeeklyTestItem.Kind.BUILD, WeeklyTestItem.Kind.REWRITE, WeeklyTestItem.Kind.TRANSLATE -> {
                    val card = item.cardId?.let { cards[it] } ?: continue
                    // Both log the drill rep themselves.
                    if (answer.correct) drills.markCorrect(card, language, now)
                    else drills.markIncorrect(card, language, now)
                }
                WeeklyTestItem.Kind.UPGRADE -> {
                    // Missed: the better word goes in the notebook, due now.
                    // Right is a recognition, not a use — nothing to claim.
                    if (answer.correct) continue
                    val better = item.answer
                    if (WordSplitter.count(better, language) > 1) {
                        if (!vocab.isStudyingExpression(better, language)) {
                            vocab.setStudyingExpression(better, true, language)
                        }
                        ReviewQueue.retire(context, StudyScheduleStore.Kind.EXPRESSION, better, language)
                    } else {
                        vocab.addStudying(better, language)
                        ReviewQueue.retire(context, StudyScheduleStore.Kind.WORD, better, language)
                    }
                }
                // Recognition writes nothing; a spoken line is already a
                // shadow attempt. A grammar point has no card of its own —
                // the corrections it was found in already have theirs.
                WeeklyTestItem.Kind.LISTEN, WeeklyTestItem.Kind.SPEAK, WeeklyTestItem.Kind.GRAMMAR -> Unit
            }
        }
        StoreEvents.bump()
    }

    private fun dedupe(list: List<String>, key: (String) -> String): List<String> {
        val seen = HashSet<String>()
        return list.filter { seen.add(key(it)) }
    }
}
