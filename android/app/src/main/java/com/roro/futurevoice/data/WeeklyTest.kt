package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.net.WeekRecapCoach
import com.roro.futurevoice.talk.CarryoverDetector
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
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File
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
    /** The learner said their answer was right too, and it was counted so. */
    val appealed: Boolean? = null,
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
 * Builds and grades the weekly test (iOS `WeeklyTestEngine`).
 *
 * The test is ONE WEEK of the learner's own practice, the same week "Your
 * week" reports on: from one opening of the test to the next
 * ([WeekRecapBuilder.lastWeek]). Nothing older is dealt, and a thin week is
 * not padded with old material (iOS 2026-11-08, founder).
 *
 * "Studied" is a card the learner put off in the deck this week. The paper is
 * at most [MAX_PAPER] items, in this order:
 *
 *   translate ← this week's mistakes: the report's recurring grammar first,
 *               then sentence cards reviewed this week, each asked in a NEW
 *               sentence laid from tiles
 *   gap       ← expressions put off this week, in a line they were heard in
 *   meaning   ← words put off this week, and the report's better words
 *   listen    ← a line the fluent self said this week, rebuilt from tiles
 *   speak     ← another such line, said out loud
 *   retakes   ← last week's paper's misses only, once: a second miss leaves
 *               the test and stays with the deck
 *
 * `grammar`, `upgrade`, `build` and `rewrite` are no longer dealt; old papers
 * on disk still play them.
 *
 * **Nothing reaches the paper unchecked.** A reader that took no part in
 * writing an item passes it: [verifyTranslate] (a blind solver finds every
 * right sentence the tiles can build, and a reviewer asks whether the mistake
 * was a rule and this sentence tests it), the gap check and [onlyMeaningFits].
 * A failed check keeps nothing.
 *
 * **A right answer is code's to accept; a wrong one is not code's alone to
 * declare.** Tiles that match are right. Translate tiles that don't match get
 * a second read before they are called wrong ([laidStands]), a failed read
 * removes the question from the score, and every wrong answer can be appealed
 * on the spot.
 */
object WeeklyTestEngine {

    /** The whole paper, about five minutes. */
    const val MAX_PAPER = 12
    const val MAX_TRANSLATE = 4
    /** More are written than can be dealt: the gate drops about half. */
    const val TRANSLATE_DRAFTS = 6
    const val MAX_GAP = 3
    const val MAX_MEANING = 3
    const val MAX_LISTEN = 1
    const val MAX_SPEAK = 1
    /** Last week's misses dealt again this week. */
    const val MAX_RETAKE = 2
    /** How long a paper waits for its translate items to be written. */
    const val TRANSLATE_WAIT_MS = 30_000L
    /** How long the second read of a wrong answer waits. */
    const val SECOND_READ_WAIT_MS = 12_000L
    /** How long a paper waits for the week report's coach to be written when
     *  the deck hasn't been opened yet. The writing carries on past it (and
     *  lands in the report); the paper just goes without. */
    const val COACH_WAIT_MS = 25_000L
    /** Ceiling for a paper of one test's own misses ([retryPaper]). */
    const val MAX_RETRY = 20
    /** A spoken line passes at the shadow browser's own retry bar. */
    const val SPEAK_PASS_SCORE = ShadowPicks.RETRY_THRESHOLD
    /** Below this the week is too thin to be a test. */
    const val MIN_ITEMS = 5
    const val CHOICE_COUNT = 4
    /** Extra tiles for a build item, from the learner's OWN wording. */
    const val MAX_DECOY_TILES = 2
    /** The longest a card can be put off (the deck's "3 days"), with room
     *  for the day it was pressed. */
    const val LONGEST_PUT_OFF_MS = 3 * 86_400_000L + 3_600_000L
    const val BLANK_MARK = "______"

    // ── Week

    /** Whether something waiting to come back at [returnAt] was put off this
     *  week. The schedule keeps only the return date, and a put-off is at most
     *  [LONGEST_PUT_OFF_MS], so the date places it to within three days. */
    fun wasPutOff(returnAt: Long, start: Long, end: Long): Boolean =
        returnAt > start && returnAt <= end + LONGEST_PUT_OFF_MS

    /** The paper in its fixed order, inside [MAX_PAPER]: last week's misses
     *  and the two heard lines keep their seats, then mistakes, then
     *  expressions and words share what is left. */
    fun paper(translate: List<WeeklyTestItem>, gap: List<WeeklyTestItem>, meaning: List<WeeklyTestItem>,
              listen: List<WeeklyTestItem>, speak: List<WeeklyTestItem>,
              retakes: List<WeeklyTestItem>): List<WeeklyTestItem> {
        val heard = listen.take(MAX_LISTEN) + speak.take(MAX_SPEAK)
        val again = retakes.take(MAX_RETAKE)
        var room = MAX_PAPER - heard.size - again.size
        val mistakes = translate.take(minOf(MAX_TRANSLATE, room))
        room -= mistakes.size
        val gaps = gap.take(MAX_GAP)
        val words = meaning.take(MAX_MEANING)
        val keptGaps = ArrayList<WeeklyTestItem>()
        val keptWords = ArrayList<WeeklyTestItem>()
        var g = 0
        var w = 0
        while (room > 0 && (g < gaps.size || w < words.size)) {
            if (g < gaps.size) { keptGaps += gaps[g]; g++; room-- }
            if (room > 0 && w < words.size) { keptWords += words[w]; w++; room-- }
        }
        return mistakes + keptGaps + keptWords + heard + again
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
        /** The words put off in the deck, still in the notebook, at the
         *  learner's level or above — the ONLY source of meaning items (iOS
         *  `studiedMaterial`, 2026-10-21: the test is what was studied). */
        val putOffWords: List<String> = emptyList(),
        /** The closed week's report coach, written at gather time if missing. */
        val coach: WeekRecap.Coach? = null,
        /** The expressions put off in the deck, never used, rated at the
         *  learner's level or above ([QuickQuizStock.rateMissing]). */
        val putOffExpressions: List<String> = emptyList(),
        /** The sentence cards put off in the deck ([DrillStore.putOffCards]) —
         *  what translate items are built on. */
        val putOffCards: List<DrillCard> = emptyList(),
        /** Keeps the gap items whose answer alone fits ([QuickQuizStock.keepOnlyAnswer]);
         *  null = no check (a JVM test has no model). */
        val checkGaps: (suspend (List<WeeklyTestItem>, String) -> List<WeeklyTestItem>)? = null,
        /** A scene's own example line for an expression, by its normalized
         *  key (trimmed, lowercased). */
        val sceneExamples: Map<String, String> = emptyMap(),
        /** The learner's own language — translate items need it. */
        val nativeLanguage: String = "",
        /** Writes the translate items (one model call); null = no network,
         *  so no translate items (a JVM test). Args: system, user, test id. */
        val writeTranslate: (suspend (String, String, String) -> TranslatePayload?)? = null,
        /** The trial report's fill: a talk's book words and phrases (iOS
         *  2026-10-28). Null = no fill (the weekly paper, a JVM test). */
        val bookOf: (suspend (Session) -> Pair<List<String>, List<String>>)? = null,
        /** The week this paper is about ([WeekRecapBuilder.lastWeek]); null =
         *  the seven days before now (a JVM test has no schedule). */
        val week: Pair<Long, Long>? = null,
        /** Keeps the meaning items whose gloss fits only the answer
         *  ([onlyMeaningFits]); null = no check (a JVM test has no model). */
        val checkMeanings: (suspend (List<WeeklyTestItem>, String) -> List<WeeklyTestItem>)? = null,
        /** The translate gate ([verifyTranslate]); null = no check. */
        val checkTranslate: (suspend (List<WeeklyTestItem>, String) -> List<WeeklyTestItem>)? = null,
        /** Told what each paper came to (`weekly_test_built`). */
        val onBuilt: ((Map<String, Any?>) -> Unit)? = null,
    )

    @Serializable
    data class TranslatePayload(val items: List<Item> = emptyList()) {
        @Serializable
        data class Item(
            val source: Int,
            val point: String,
            val answer: String,
            val native: String,
            val wrong: String? = null,
            val orders: List<String>? = null,
            val decoys: List<String>? = null,
            val tip: String? = null,
        )
    }

    /**
     * A paper over a window of the caller's choosing instead of the week's
     * (iOS `WeeklyTestEngine.Scope`) — the trial report's test
     * ([TrialReport]): from the first talk to now, its own coach, and a lower
     * floor, since twenty minutes is a small week.
     */
    data class Scope(val start: Long, val minimum: Int, val coach: WeekRecap.Coach?)

    suspend fun gather(context: Context, language: String, level: CefrLevel,
                       native: String, scope: Scope? = null): Material {
        val vocab = VocabStore.shared(context)
        val app = context.applicationContext
        val now = System.currentTimeMillis()
        val thisWeek = scope?.let { minOf(it.start, now) to now } ?: WeekRecapBuilder.lastWeek(context, now)
        // What was studied this week (iOS `studiedMaterial`): put off in the
        // deck between the openings, still on the learner's lists, at their
        // level or above. A word the graded list can't place keeps its seat.
        val schedule = StudyScheduleStore.shared(context).snapshot(language)
        val put = (schedule.dueItems(now) + schedule.upcoming(now))
            .filter { wasPutOff(it.at, thisWeek.first, thisWeek.second) }
        val seenPut = HashSet<String>()
        val putOffWords = put.filter { it.kind == StudyScheduleStore.Kind.WORD }.map { it.text }.filter { w ->
            seenPut.add("w|" + w.lowercase()) && vocab.isStudying(w, language) &&
                TextScript.isInTargetScript(w, language) &&
                (CoreVocabulary.level(w, language)?.let { it.ordinal >= level.ordinal } ?: true)
        }
        val putPhrases = put.filter { it.kind == StudyScheduleStore.Kind.EXPRESSION }.map { it.text }.filter { p ->
            seenPut.add("e|" + p.trim().lowercase()) && !vocab.hasUsedExpression(p, language) &&
                TextScript.isInTargetScript(p, language)
        }
        runCatching { QuickQuizStock.rateMissing(context, putPhrases, LanguageCatalog.englishName(language)) }
        val rated = QuickQuizStock.levels(context)
        val putOffExpressions = putPhrases.filter { QuickQuizStock.atLevel(rated[it.trim().lowercase()], level) }
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
            putOffWords = putOffWords,
            coach = if (scope != null) scope.coach else weekCoach(app, language, level, native),
            putOffExpressions = putOffExpressions,
            putOffCards = runCatching { DrillStore.shared(context).putOffCards(language) }.getOrDefault(emptyList()),
            checkGaps = { items, testId ->
                val stored = items.map { i ->
                    QuickQuizStock.Stored(kind = QuickQuizStock.Kind.expression, point = "", tip = "",
                        sentence = i.prompt, answer = i.answer, wrong = i.options.filter { it != i.answer },
                        createdAt = System.currentTimeMillis())
                }
                val kept = QuickQuizStock.keepOnlyAnswer(stored, LanguageCatalog.englishName(language),
                    "weekly-gap-$testId").map { CarryoverDetector.normalized(it.sentence) }.toSet()
                items.filter { CarryoverDetector.normalized(it.prompt) in kept }
            },
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
            week = thisWeek,
            checkMeanings = { items, testId -> onlyMeaningFits(items, language, native, testId) },
            checkTranslate = { items, testId -> verifyTranslate(items, language, native, testId) },
            onBuilt = { props -> com.roro.futurevoice.core.Analytics.capture("weekly_test_built", props) },
            bookOf = if (scope == null) null else { session ->
                val book = TalkCurriculum.build(session, level, language, vocab, emptyList(), emptyList())
                book.words.map { it.text } to book.expressions.map { it.text }
            },
            writeTranslate = { system, user, testId ->
                val job = coachScope.async {
                    runCatching {
                        GeminiClient(AuthRepository()).sendJson(
                            system = system,
                            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                            serializer = TranslatePayload.serializer(),
                            maxTokens = 5000, purpose = "weekly-test",
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
        /** The trial report's own window and floor; its coach rides on the
         *  [Material] ([gather] with the same scope). */
        scope: Scope? = null,
        gloss: suspend (String) -> String?,
    ): WeeklyTest? {
        val (start, end) = scope?.let { minOf(it.start, now) to now }
            ?: material.week ?: ((now - 7 * 86_400_000L) to now)
        val rng = WeeklyTestRandom(id)
        val windowSessions = material.sessions.filter { s ->
            val ended = s.endedAt ?: return@filter false
            ended in start..end
        }
        val fluentTurns = windowSessions.flatMap { s ->
            s.turns.filter { it.role == TurnRole.FLUENT_SELF && !it.excludedFromScoring }.map { s to it }
        }
        // A call's first fluent-self line is its greeting — the same few
        // words every call, never the material.
        val openers = material.sessions.mapNotNull { s ->
            s.turns.firstOrNull { it.role == TurnRole.FLUENT_SELF }?.id
        }.toSet()
        val teachingTurns = fluentTurns.filter { it.second.id !in openers }

        val studied = material.putOffExpressions.filter { TextScript.isInTargetScript(it, language) }
        val betterWords = material.coach?.upgrades.orEmpty().map { it.better }
            .filter { WordSplitter.count(it, language) == 1 && TextScript.isInTargetScript(it, language) }
        val seenWords = HashSet<String>()
        val words = (material.putOffWords + betterWords).filter { seenWords.add(it.lowercase()) }
        val meaningDrafts = meaningItems(material, language, level, rng, gloss, words = words, limit = MAX_MEANING * 2)
        val gapDrafts = gapItems(studied, windowSessions, teachingTurns, material.sessions, openers,
            material.sceneExamples, material.libraryExpressions, language, rng, limit = MAX_GAP * 2)

        // A heard line is about what the week taught: a phrase put off this
        // week, or one the fluent self offered in this week's talks.
        val offered = windowSessions.flatMap { it.summary?.expressionsOffered.orEmpty() }
        val heardPhrases = (studied + offered).map { it.lowercase() }.distinct().filter { it.isNotEmpty() }
        val listens = listenItems(teachingTurns, heardPhrases, material.hasAudio, language, rng)
        val speaks = speakItems(teachingTurns, heardPhrases,
            listens.map { CarryoverDetector.normalized(it.answer) }.toSet(), language, rng)

        // Last week's misses, once. A retake is checked like anything else:
        // it was written before the gate or before today's rules.
        var retakeDrafts: List<WeeklyTestItem> = emptyList()
        if (lastTest != null && lastTest.isFinished && !lastTest.isMonthly && lastTest.createdAt >= start) {
            val fresh = (meaningDrafts + gapDrafts + listens + speaks).map(::itemKey).toSet()
            retakeDrafts = retakes(listOf(lastTest), MAX_RETAKE * 2, fresh, language, rng, firstMissOnly = true) {
                asRewrite(it, material.cards, material.sessions, language)
            }
        }
        fun again(kind: WeeklyTestItem.Kind) = retakeDrafts.filter { it.kind == kind }
        val askedLastWeek = lastTest?.items.orEmpty().mapNotNull { it.cardId }.toSet()

        suspend fun meaningCheck(list: List<WeeklyTestItem>): List<WeeklyTestItem> =
            material.checkMeanings?.let { check -> runCatching { check(list, id) }.getOrDefault(emptyList()) } ?: list
        suspend fun gapCheck(list: List<WeeklyTestItem>): List<WeeklyTestItem> =
            material.checkGaps?.let { check -> runCatching { check(list, id) }.getOrDefault(emptyList()) } ?: list

        val (meaningKept, gapKept, translateKept) = coroutineScope {
            val m = async { meaningCheck(meaningDrafts + again(WeeklyTestItem.Kind.MEANING)) }
            val g = async { gapCheck(gapDrafts + again(WeeklyTestItem.Kind.GAP)) }
            val t = async {
                translateItems(material, start, end, windowSessions, askedLastWeek,
                    again(WeeklyTestItem.Kind.TRANSLATE), language, level, id)
            }
            Triple(m.await(), g.await(), t.await())
        }

        fun fresh(list: List<WeeklyTestItem>) = list.filter { it.isRetake != true }
        // Heard lines need no check: the answer is the line itself.
        val keptAgain = (translateKept + gapKept + meaningKept).filter { it.isRetake == true } +
            again(WeeklyTestItem.Kind.LISTEN) + again(WeeklyTestItem.Kind.SPEAK)
        val items = paper(fresh(translateKept), fresh(gapKept), fresh(meaningKept), listens, speaks, keptAgain)
            .toMutableList()

        // The trial report's test is never refused for being small (iOS
        // 2026-10-28, founder: "make the test even if the amount is small,
        // even from related things"). Twenty minutes rarely leave anything
        // put off in the deck, so it is filled from the window's own talks:
        // the words and phrases their books teach, then their lines to hear
        // and say. Any count is a test.
        val bookOf = material.bookOf
        if (scope != null && items.size < scope.minimum && bookOf != null) {
            val books = windowSessions.map { bookOf(it) }
            val seenWord = words.map { it.lowercase() }.toHashSet()
            val bookWords = books.flatMap { it.first }.filter { seenWord.add(it.lowercase()) }
            val seenPhrase = studied.map { it.lowercase() }.toHashSet()
            val bookPhrases = books.flatMap { it.second }
                .filter { TextScript.isInTargetScript(it, language) && seenPhrase.add(it.lowercase()) }
            val have = items.map(::itemKey).toSet()
            val more = ArrayList<WeeklyTestItem>()
            more += meaningCheck(meaningItems(material, language, level, rng, gloss, words = bookWords,
                limit = MAX_MEANING * 2)).take(MAX_MEANING)
            val moreGaps = gapItems(bookPhrases, windowSessions, teachingTurns, material.sessions, openers,
                material.sceneExamples, material.libraryExpressions, language, rng, limit = MAX_GAP * 2)
            more += gapCheck(moreGaps).take(MAX_GAP)
            // Lines carrying one of those phrases first; with still too few,
            // any of their own talk's lines (every line contains "").
            val phrases = if (items.size + more.size < scope.minimum) listOf("") else bookPhrases.map { it.lowercase() }
            val heard = listenItems(teachingTurns, phrases, material.hasAudio, language, rng)
            more += heard
            more += speakItems(teachingTurns, phrases,
                (listens + heard).map { CarryoverDetector.normalized(it.answer) }.toSet(), language, rng)
            items += more.filter { itemKey(it) !in have }
        }
        val enough = items.size >= (if (scope == null) MIN_ITEMS else 1)
        val counts = HashMap<String, Any?>()
        items.groupBy { it.kind }.forEach { (kind, list) -> counts["n_" + kind.name.lowercase()] = list.size }
        counts["items"] = items.size
        counts["retakes"] = items.count { it.isRetake == true }
        counts["talks"] = windowSessions.size
        counts["enough"] = enough
        material.onBuilt?.invoke(counts)
        if (!enough) return null
        // A test opens on something you can answer by reading.
        if (items.first().kind == WeeklyTestItem.Kind.LISTEN) {
            val swap = items.indexOfFirst { it.kind != WeeklyTestItem.Kind.LISTEN }
            if (swap > 0) java.util.Collections.swap(items, 0, swap)
        }
        return WeeklyTest(id = id, targetLanguage = language, periodStart = start, periodEnd = end,
            createdAt = now, items = items)
    }

    /** Wrong answers of [tests], newest test first, one per distinct answer,
     *  as fresh items with their choices reshuffled. [firstMissOnly] is the
     *  weekly paper's rule: a miss comes back once, in a kind still dealt, so
     *  a question can't chase the learner week after week. */
    fun retakes(tests: List<WeeklyTest>, limit: Int, excluding: Set<String>,
                        language: String, rng: Random, firstMissOnly: Boolean = false,
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
                if (firstMissOnly && (stored.isRetake == true || stored.kind !in DEALT)) continue
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

    private val DEALT = setOf(WeeklyTestItem.Kind.MEANING, WeeklyTestItem.Kind.GAP, WeeklyTestItem.Kind.TRANSLATE,
        WeeklyTestItem.Kind.LISTEN, WeeklyTestItem.Kind.SPEAK)

    /** This test's misses dealt again as a paper of their own — played in
     *  place, never saved. Null when nothing was missed. */
    fun retryPaper(test: WeeklyTest, now: Long = System.currentTimeMillis(),
                   rewrite: (WeeklyTestItem) -> WeeklyTestItem?): WeeklyTest? {
        val items = retakes(listOf(test), MAX_RETRY, emptySet(), test.targetLanguage,
            WeeklyTestRandom(StoreJson.newId()), rewrite = rewrite)
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

    private suspend fun meaningItems(material: Material, language: String,
                                     level: CefrLevel, rng: Random,
                                     gloss: suspend (String) -> String?,
                                     words: List<String>, limit: Int): List<WeeklyTestItem> {
        val seen = words.map { it.lowercase() }.toHashSet()
        val candidates = words.shuffled(rng)

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
            if (out.size >= limit) break
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

    @Serializable
    private data class MeaningVerdicts(val results: List<Result> = emptyList()) {
        @Serializable
        data class Result(val n: Int, val fit: List<String> = emptyList())
    }

    /** The meaning items whose gloss fits only the answer, as read by a call
     *  that is never told which word was meant. Decoys share a word class, so
     *  a near-synonym can be one of them and two choices would be right.
     *  Nothing when the check can't run. */
    suspend fun onlyMeaningFits(items: List<WeeklyTestItem>, target: String, native: String,
                                testId: String): List<WeeklyTestItem> {
        if (items.isEmpty()) return emptyList()
        val system = WeeklyTestPrompts.meaningSystem(LanguageCatalog.englishName(target), LanguageCatalog.englishName(native))
        val user = items.mapIndexed { i, item ->
            "${i + 1}. ${item.prompt}\n   words: ${item.options.sorted().joinToString(" | ")}"
        }.joinToString("\n")
        val v = askModel(system, user, MeaningVerdicts.serializer(), 3000,
            "weekly-test-meaning:$testId", 30_000L) ?: return emptyList()
        return v.results.mapNotNull { r ->
            val item = items.getOrNull(r.n - 1) ?: return@mapNotNull null
            if (r.fit.map(CarryoverDetector::normalized) == listOf(CarryoverDetector.normalized(item.answer))) item else null
        }
    }

    /** One buffered `weekly-test` call, null when it failed or ran out of time. */
    private suspend fun <T> askModel(system: String, user: String,
                                     serializer: kotlinx.serialization.DeserializationStrategy<T>,
                                     maxTokens: Int, key: String, waitMs: Long): T? {
        val job = coachScope.async {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = system,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                    serializer = serializer, maxTokens = maxTokens, purpose = "weekly-test",
                    idempotencyKey = key)
            }.getOrNull()
        }
        return withTimeoutOrNull(waitMs) { job.await() }
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

    /** A studied expression with its line blanked out, in the sentence the
     *  learner met it in: this week's talks first, then any talk, then the
     *  scene that taught it. A phrase with no such line is skipped. The
     *  caller still runs the check ([Material.checkGaps]): the decoys are
     *  other phrases, and nothing here can tell whether one fits too. */
    fun gapItems(toStudy: List<String>, sessions: List<Session>,
                         fluentTurns: List<Pair<Session, Turn>>, allSessions: List<Session>,
                         openers: Set<String>, sceneExamples: Map<String, String>,
                         library: List<String>, language: String, rng: Random,
                         limit: Int = MAX_GAP): List<WeeklyTestItem> {
        data class Candidate(val phrase: String, val sentence: String, val session: Session?, val turn: Turn?)
        val anyFluent = allSessions.flatMap { s ->
            s.turns.filter { it.role == TurnRole.FLUENT_SELF && !it.excludedFromScoring && it.id !in openers }
                .map { s to it }
        }
        val candidates = ArrayList<Candidate>()
        for (phrase in toStudy) {
            if (candidates.size >= limit * 3) break
            val hit = firstSentence(phrase, fluentTurns, language) ?: firstSentence(phrase, anyFluent, language)
            if (hit != null) {
                candidates += Candidate(phrase, hit.first, hit.second, hit.third)
                continue
            }
            val example = sceneExamples[phrase.trim().lowercase()] ?: continue
            if (foldedRange(example, phrase, language) != null && leavesContext(phrase, example, language) &&
                TextScript.isInTargetScript(example, language)) {
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
            if (out.size >= limit) break
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

    /** The sentence in [turns] containing [phrase] that leaves the most
     *  context around the blank, short enough to read as one line — a gap
     *  item never shows a whole turn. It took the FIRST hit until iOS
     *  2026-10-21, and "So what's on your mind?" left "So ______?". */
    private fun firstSentence(phrase: String, turns: List<Pair<Session, Turn>>,
                              language: String): Triple<String, Session, Turn>? {
        var best: Triple<String, Session, Turn>? = null
        var bestLeft = -1
        for ((session, turn) in turns) {
            for (sentence in TalkCurriculum.sentences(turn.transcript)) {
                if (foldedRange(sentence, phrase, language) == null) continue
                val n = WordSplitter.count(sentence, language)
                if (n > 30 || !leavesContext(phrase, sentence, language) ||
                    !TextScript.isInTargetScript(sentence, language)) continue
                val left = n - WordSplitter.count(phrase, language)
                if (left > bestLeft) { best = Triple(sentence, session, turn); bestLeft = left }
            }
        }
        return best
    }

    /** Words left around the blank, at least: under this the line can't say
     *  which phrase it wants. */
    const val MIN_GAP_CONTEXT = 4

    fun leavesContext(phrase: String, sentence: String, language: String): Boolean =
        WordSplitter.count(sentence, language) - WordSplitter.count(phrase, language) >= MIN_GAP_CONTEXT

    /** [sentence] with the first case- and diacritic-insensitive occurrence
     *  of [phrase] replaced by the blank mark. */
    fun blank(phrase: String, sentence: String,
              language: String? = CoreVocabulary.activeLanguage()): String? {
        if (phrase.isEmpty()) return null
        val range = foldedRange(sentence, phrase, language) ?: return null
        return sentence.replaceRange(range, BLANK_MARK)
    }

    // ── build

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
                val range = foldedRange(sentence, was, language) ?: continue
                val span = if (WordSplitter.count(sentence, language) > rewriteClauseFrom(language))
                    clauseRange(range, sentence) else sentence.indices
                val clause = sentence.substring(span.first, span.last + 1)
                val local = foldedRange(clause, was, language) ?: continue
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

    /** A "fix" that only takes the last words off a sentence: the speaker
     *  stopped mid-thought ("I'm very excited about." → "I'm very excited.").
     *  No rule was broken, and a question built on it has nothing to test. */
    fun isBrokenOff(was: String, now: String): Boolean {
        val before = was.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val after = now.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (before.isEmpty() || after.size >= before.size) return false
        var i = 0
        var j = 0
        var last: String? = null
        while (i < before.size) {
            if (j < after.size && tileKey(before[i]) == tileKey(after[j])) { i++; j++ }
            else { last = before[i]; i++ }
        }
        if (j != after.size || last == null) return false
        return before.last() == last || (last.lastOrNull() ?: ' ') in ".!?。！？"
    }

    /** The week's mistakes to build on: the report's recurring grammar first,
     *  then the sentence cards reviewed this week and still put off, newest
     *  first. A card last week's paper asked about stays out: a miss returns
     *  as last week's retake, not again in a new sentence. */
    fun slips(putOff: List<DrillCard>, language: String, start: Long, end: Long,
              coach: WeekRecap.Coach?, excludingCards: Set<String>): List<Slip> {
        val cards = putOff.filter { c ->
            c.id !in excludingCards && c.sourcePhrase.isNotBlank() &&
                TextScript.isInTargetScript(c.targetPhrase, language) &&
                TextScript.isInTargetScript(c.sourcePhrase, language)
        }
        val out = ArrayList<Slip>()
        val seen = HashSet<String>()
        for (pattern in coach?.grammar.orEmpty()) {
            for (example in pattern.examples) {
                if (!TextScript.isInTargetScript(example.was, language) ||
                    !TextScript.isInTargetScript(example.now, language) ||
                    isBrokenOff(example.was, example.now)) continue
                val key = CarryoverDetector.normalized(example.was)
                if (!seen.add(key)) continue
                val card = cards.firstOrNull { CarryoverDetector.normalized(it.sourcePhrase).contains(key) }
                if (card != null) seen += CarryoverDetector.normalized(card.sourcePhrase)
                out += Slip(example.was, example.now, pattern.rule, card?.id)
            }
        }
        val reviewed = cards.filter { c ->
            val at = c.lastReviewedAt ?: return@filter false
            at >= start && at < end
        }.sortedByDescending { it.lastReviewedAt ?: 0L }
        for (c in reviewed) {
            if (isBrokenOff(c.sourcePhrase, c.targetPhrase)) continue
            if (seen.add(CarryoverDetector.normalized(c.sourcePhrase))) out += Slip(c.sourcePhrase, c.targetPhrase, c.reason, c.id)
        }
        return out.take(10)
    }

    /** New sentences that need the grammar the learner got wrong, laid from
     *  word tiles, then passed through [verifyTranslate] beside last week's
     *  translate misses. The writer has to produce the sentence with the
     *  mistake made again (`wrong`): a sentence where it can't write that
     *  doesn't test the mistake. Nothing when the target IS the native
     *  language, or a call fails. */
    private suspend fun translateItems(material: Material, start: Long, end: Long,
                                       windowSessions: List<Session>, excludingCards: Set<String>,
                                       retakes: List<WeeklyTestItem>, target: String, level: CefrLevel,
                                       testId: String): List<WeeklyTestItem> {
        val native = material.nativeLanguage
        if (native.isEmpty() || LanguageCatalog.sameLanguage(target, native)) return emptyList()
        val list = slips(material.putOffCards, target, start, end, material.coach, excludingCards)
        val drafts = ArrayList<WeeklyTestItem>()
        val write = material.writeTranslate
        if (write != null && list.isNotEmpty()) {
            val topics = windowSessions.mapNotNull { it.topic }.filter { it.isNotEmpty() }.take(6)
            val system = WeeklyTestPrompts.translateSystem(LanguageCatalog.englishName(target),
                LanguageCatalog.englishName(native), level.code.uppercase(), TRANSLATE_DRAFTS, topics.joinToString("; "), target)
            val user = list.mapIndexed { i, s ->
                "${i + 1}. said \"${s.was}\" → should be \"${s.now}\"" + (if (s.why.isEmpty()) "" else " (${s.why})")
            }.joinToString("\n")
            val payload = runCatching { write(system, user, testId) }.getOrNull()
            val rng = WeeklyTestRandom(testId)
            val points = HashSet<String>()
            for (it in payload?.items.orEmpty()) {
                if (it.source - 1 !in list.indices) continue
                val wrong = it.wrong ?: continue
                if (CarryoverDetector.normalized(wrong) == CarryoverDetector.normalized(it.answer)) continue
                val item = translateItem(it.native, it.answer, it.orders.orEmpty(), it.decoys.orEmpty(), it.point,
                    it.tip, list[it.source - 1], target, rng) ?: continue
                if (!points.add(it.point.lowercase())) continue
                drafts += item
            }
        }
        val check = material.checkTranslate ?: return drafts + retakes
        return runCatching { check(drafts + retakes, testId) }.getOrDefault(emptyList())
    }

    @Serializable
    data class TranslateReview(
        val n: Int,
        val rule: Boolean? = null,
        val repeats: Boolean? = null,
        @SerialName("same_meaning") val sameMeaning: Boolean? = null,
        val correct: Boolean? = null,
        @SerialName("tip_true") val tipTrue: Boolean? = null,
    ) {
        val passes: Boolean get() =
            rule == true && repeats == true && sameMeaning == true && correct == true && tipTrue == true
    }

    @Serializable
    private data class ReviewVerdicts(val results: List<TranslateReview> = emptyList())

    @Serializable
    private data class SolveVerdicts(val results: List<Result> = emptyList()) {
        @Serializable
        data class Result(val n: Int, val sentences: List<String>? = null)
    }

    /** The gate every translate item passes before it reaches a paper. Two
     *  readers that did not write it: one is never told the answer and lists
     *  every right sentence the tiles can build, the other reviews the item. */
    suspend fun verifyTranslate(items: List<WeeklyTestItem>, target: String, native: String,
                                testId: String): List<WeeklyTestItem> {
        if (items.isEmpty()) return emptyList()
        val t = LanguageCatalog.englishName(target)
        val n = LanguageCatalog.englishName(native)
        val blind = items.mapIndexed { i, item ->
            "${i + 1}. Sentence: ${item.prompt}\n   Tiles: ${item.options.joinToString(" | ")}"
        }.joinToString("\n")
        val open = items.mapIndexed { i, item ->
            val traps = decoyTiles(item, target).joinToString(", ")
            "${i + 1}. Sentence: ${item.prompt}\n   Answer: ${item.answer}\n   Traps: ${traps.ifEmpty { "none" }}\n" +
                "   Earlier mistake: \"${item.focus ?: ""}\" → \"${item.example ?: ""}\"\n" +
                "   Point: ${item.rule ?: ""}\n   Tip: ${item.note ?: "none"}"
        }.joinToString("\n")
        val (solved, reviewed) = coroutineScope {
            val s = async { askModel(WeeklyTestPrompts.solveSystem(t, n), blind, SolveVerdicts.serializer(), 6000,
                "weekly-test-solve:$testId", TRANSLATE_WAIT_MS) }
            val r = async { askModel(WeeklyTestPrompts.reviewSystem(t, n, target), open, ReviewVerdicts.serializer(), 4000,
                "weekly-test-review:$testId", TRANSLATE_WAIT_MS) }
            s.await() to r.await()
        }
        if (solved == null || reviewed == null) return emptyList()
        val sentences = solved.results.associate { it.n to (it.sentences ?: emptyList()) }
        val reviews = reviewed.results.associateBy { it.n }
        return items.mapIndexedNotNull { i, item ->
            val review = reviews[i + 1] ?: return@mapIndexedNotNull null
            passing(item, sentences[i + 1] ?: emptyList(), review, target)
        }
    }

    /** Code's half of the gate. Out when the review failed or the blind reader
     *  could not reach the answer from the tiles. A trap that built a right
     *  sentence leaves the table; with no trap left, nothing tests the mistake
     *  and the item goes. Other orders it found join `orders`. */
    fun passing(item: WeeklyTestItem, solved: List<String>, review: TranslateReview, language: String): WeeklyTestItem? {
        if (!review.passes) return null
        val answer = tileBag(item.answer, language)
        val said = solved.filter { it.isNotBlank() }
        if (said.none { tileBag(it, language) == answer }) return null
        val traps = decoyTiles(item, language)
        val others = said.filter { tileBag(it, language) != answer }
        fun builtWith(trap: String): Boolean {
            val key = tileKey(trap)
            return others.any { sentence ->
                if (WordSplitter.spaced(language)) WordSplitter.words(sentence, language).map(::tileKey).contains(key)
                else CarryoverDetector.normalized(sentence).contains(key)
            }
        }
        val working = traps.filter(::builtWith).map(::tileKey).toSet()
        if (working.size >= traps.map(::tileKey).toSet().size) return null
        val keys = WordSplitter.words(item.answer, language).map(::tileKey)
        val moreOrders = said.filter {
            tileBag(it, language) == answer && WordSplitter.words(it, language).map(::tileKey) != keys
        }
        val known = item.orders.orEmpty().map { WordSplitter.words(it, language).map(::tileKey) }.toHashSet()
        val orders = item.orders.orEmpty().toMutableList()
        for (order in moreOrders) if (known.add(WordSplitter.words(order, language).map(::tileKey))) orders += order
        return item.copy(options = item.options.filter { tileKey(it) !in working }, orders = orders)
    }

    /** A sentence as the things it is made of, order aside. Words where spaces
     *  mark them; letters where they don't, because a tokenizer can cut the
     *  same Japanese sentence differently once it is reordered. */
    fun tileBag(text: String, language: String): String =
        if (WordSplitter.spaced(language)) WordSplitter.words(text, language).map(::tileKey).sorted().joinToString(" ")
        else CarryoverDetector.normalized(text).filter { !it.isWhitespace() }.toList().sorted().joinToString("")

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
    fun foldedRange(text: String, needle: String,
                    language: String? = CoreVocabulary.activeLanguage()): IntRange? =
        com.roro.futurevoice.talk.SpokenWords.wholeWordRange(text, needle, language)

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

    @Serializable
    private data class SecondRead(val right: Boolean)

    /** Tiles the code did not accept, read once more before they are called
     *  wrong: an answer can be right in words the item never listed. Null when
     *  the read failed, and the question then doesn't count at all. */
    suspend fun laidStands(item: WeeklyTestItem, laid: String, language: String): Boolean? {
        val system = WeeklyTestPrompts.secondReadSystem(LanguageCatalog.englishName(language))
        var user = ""
        item.rule?.let { user += "Grammar point: $it\n" }
        if (item.focus != null && item.example != null) user += "Their earlier mistake: ${item.focus} → ${item.example}\n"
        user += "The sentence asked for: ${item.prompt}\nModel answer: ${item.answer}\nWhat they laid: $laid"
        return askModel(system, user, SecondRead.serializer(), 1500,
            "weekly-test-second:${item.id}:${CarryoverDetector.normalized(laid)}", SECOND_READ_WAIT_MS)?.right
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
     * a correction in a talk) inside most of the sentence, or as the whole
     * fixed clause on its own; a reply of the fixed word alone is not a rewrite. Nothing else counts against it: how
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
        if (!CarryoverDetector.showsTheFixInText(was, now, rewritten)) return false
        // The screen underlines only the part that was wrong, so the fixed
        // clause on its own is an answer (2026-10-25, "whoever limits AI's"
        // for a 22-word line). A lone word is still not: the clause has to
        // be the fix whole, at least two words of it.
        if (WordSplitter.count(now, language) >= 2 && given.contains(fixKey)) return true
        return CarryoverDetector.sharedWordRatio(expand(item.answer), rewritten) >= 0.6
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
     * caller stamps `appliedAt`). A right answer is the deck's own "Got it"
     * (iOS, 2026-11-08): the item is KNOWN, leaves the deck and ticks off in
     * every book that teaches it (the books read the same stores). A right
     * answer used to push it 3 days on, so it stayed put off and came back
     * in every week's test.
     *
     *   meaning  right → known, out of the deck · wrong → back in the notebook, due now
     *   gap      right → known, out of the deck · wrong → bookmarked, due now
     *   rewrite  right → the card retires (Got it) · wrong → one rung down (build, translate alike)
     *   listen / speak → nothing (a spoken take is already a shadow attempt)
     *   grammar  nothing (its corrections already carry cards)
     *   upgrade  wrong → the better word in the notebook, due now
     */
    suspend fun apply(context: Context, test: WeeklyTest, now: Long = System.currentTimeMillis()) {
        val language = test.targetLanguage
        val vocab = VocabStore.shared(context)
        val drills = DrillStore.shared(context)
        val cards = drills.load(language).associateBy { it.id }
        val byId = test.items.associateBy { it.id }
        for (answer in test.answers) {
            val item = byId[answer.itemId] ?: continue
            when (item.kind) {
                WeeklyTestItem.Kind.MEANING -> {
                    val word = item.answer
                    if (answer.correct) {
                        vocab.markKnown(word, language, now)       // logs the rep, leaves the notebook
                        ReviewQueue.retire(context, StudyScheduleStore.Kind.WORD, word, language)
                    } else {
                        vocab.addStudying(word, language)          // records the rep itself
                        ReviewQueue.retire(context, StudyScheduleStore.Kind.WORD, word, language)
                    }
                }
                WeeklyTestItem.Kind.GAP -> {
                    val phrase = item.answer
                    if (answer.correct) {
                        // Already known, or said in a talk (which outranks
                        // known): nothing to claim, never step it down.
                        if (vocab.hasUsedExpression(phrase, language)) {
                            PracticeLog.record(context, PracticeLog.Kind.EXPRESSION)
                        } else vocab.setKnownExpression(phrase, true, language, now)   // logs the rep
                        ReviewQueue.retire(context, StudyScheduleStore.Kind.EXPRESSION, phrase, language)
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
                    if (answer.correct) drills.markKnown(card, language, now)
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
