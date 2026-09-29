package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionMode
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
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
     *  build/listen: the word tiles, in display order. */
    val options: List<String> = emptyList(),
    val sessionId: String? = null,
    val turnId: String? = null,
    val cardId: String? = null,
    /** build: the correction's one-line reason (coaching, native language). */
    val note: String? = null,
    /** True when the item came back from an earlier test's wrong answers. */
    val isRetake: Boolean? = null,
) {
    @Serializable
    enum class Kind {
        /** A word the talks taught: its meaning is shown, pick the word. */
        @SerialName("meaning") MEANING,
        /** A fluent-self line with its phrase blanked out: pick the phrase. */
        @SerialName("gap") GAP,
        /** A corrected sentence: rebuild the fluent version from tiles. */
        @SerialName("build") BUILD,
        /** A fluent-self line HEARD and rebuilt from its own tiles (dictation). */
        @SerialName("listen") LISTEN,
        /** A fluent-self line said out loud, scored like a shadow take. */
        @SerialName("speak") SPEAK,
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
 *   meaning  ← the notebook (words the talks taught)
 *   gap      ← the fluent self's phrases (`expressionsOffered` / `expressionsUsed`)
 *   build    ← the corrections (drill cards with what the learner said)
 *   listen   ← the fluent self's saved lines, heard and rebuilt from tiles
 *   speak    ← the fluent self's lines, said out loud and scored like a shadow take
 *
 * Every grade is computed in code. The only model calls are the free, cached
 * dictionary gloss (meaning) and the audio read of a take (speak).
 */
object WeeklyTestEngine {

    const val MAX_MEANING = 4
    const val MAX_GAP = 3
    const val MAX_BUILD = 3
    const val MAX_LISTEN = 2
    const val MAX_SPEAK = 2
    /** Wrong answers of the previous test dealt again this week. */
    const val MAX_RETAKE = 3
    /** The monthly paper's ceiling. */
    const val MAX_MONTHLY = 20
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
    )

    suspend fun gather(context: Context, language: String): Material {
        val vocab = VocabStore.shared(context)
        val app = context.applicationContext
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
        )
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
        items += meaningItems(fluentTurns.map { it.second.transcript }, material, language, level, rng, gloss)
        items += gapItems(windowSessions, fluentTurns, userTurns, material.libraryExpressions, language, rng)
        items += buildItems(material.cards, start, end, now, language, rng)
        val listens = listenItems(fluentTurns, material.hasAudio, language, rng)
        items += listens
        items += speakItems(fluentTurns, windowSessions,
            listens.map { CarryoverDetector.normalized(it.answer) }.toSet(), language, rng)
        // What last week got wrong is asked again first.
        if (lastTest != null && lastTest.isFinished && !lastTest.isMonthly) {
            val fresh = items.map(::itemKey).toSet()
            items += retakes(listOf(lastTest), MAX_RETAKE, fresh, language, rng)
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

    // ── Monthly

    /** Every item the given weekly tests got wrong, each asked once; null
     *  under [MIN_ITEMS]. */
    fun buildMonthly(tests: List<WeeklyTest>, targetLanguage: String,
                     now: Long = System.currentTimeMillis(), id: String = StoreJson.newId()): WeeklyTest? {
        val rng = WeeklyTestRandom(id)
        val items = retakes(tests, MAX_MONTHLY, emptySet(), targetLanguage, rng).toMutableList()
        if (items.size < MIN_ITEMS) return null
        items.shuffle(rng)
        fun audible(i: WeeklyTestItem) = i.kind == WeeklyTestItem.Kind.LISTEN || i.kind == WeeklyTestItem.Kind.SPEAK
        if (audible(items.first())) {
            val swap = items.indexOfFirst { !audible(it) }
            if (swap > 0) java.util.Collections.swap(items, 0, swap)
        }
        val start = tests.mapNotNull { it.finishedAt }.minOrNull() ?: now
        return WeeklyTest(id = id, targetLanguage = targetLanguage, kind = WeeklyTest.Kind.MONTHLY,
            periodStart = start, periodEnd = now, createdAt = now, items = items)
    }

    /** Wrong answers of [tests], newest test first, one per distinct answer,
     *  as fresh items with their choices reshuffled. */
    private fun retakes(tests: List<WeeklyTest>, limit: Int, excluding: Set<String>,
                        language: String, rng: Random): List<WeeklyTestItem> {
        val out = ArrayList<WeeklyTestItem>()
        val seen = excluding.toHashSet()
        for (test in tests.sortedByDescending { it.createdAt }) {
            val wrong = test.answers.filter { !it.correct }.map { it.itemId }.toSet()
            for (item in test.items) {
                if (item.id !in wrong || !isValid(item, language)) continue
                if (out.size >= limit) return out
                if (!seen.add(itemKey(item))) continue
                // Build tiles are dealt afresh, so a stored item picks up
                // today's decoy rule instead of its old tiles.
                val options = when (item.kind) {
                    WeeklyTestItem.Kind.BUILD -> buildTiles(item.answer, item.prompt, language, rng)
                    WeeklyTestItem.Kind.LISTEN -> dictationTiles(item.answer, language, rng)
                    else -> item.options.shuffled(rng)
                }
                out += item.copy(id = StoreJson.newId(), options = options, isRetake = true)
            }
        }
        return out
    }

    /** This test's misses dealt again as a paper of their own — played in
     *  place, never saved. Null when nothing was missed. */
    fun retryPaper(test: WeeklyTest, now: Long = System.currentTimeMillis()): WeeklyTest? {
        val items = retakes(listOf(test), MAX_MONTHLY, emptySet(), test.targetLanguage,
            WeeklyTestRandom(StoreJson.newId()))
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
            WeeklyTestItem.Kind.BUILD -> ok(item.prompt) && item.options.all(::ok)
            WeeklyTestItem.Kind.GAP -> ok(item.prompt.replace(BLANK_MARK, "")) && item.options.all(::ok)
            WeeklyTestItem.Kind.MEANING, WeeklyTestItem.Kind.LISTEN -> item.options.all(::ok)
            WeeklyTestItem.Kind.SPEAK -> true
        }
    }

    /** A test in progress with its not-yet-answered invalid items removed and
     *  stale tiles re-dealt. Null when nothing changed. */
    fun pruned(test: WeeklyTest): WeeklyTest? {
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
            if (item.kind == WeeklyTestItem.Kind.BUILD) {
                val fresh = buildTiles(item.answer, item.prompt, test.targetLanguage, rng)
                if (fresh.map(::tileKey).toSet() != item.options.map(::tileKey).toSet()) {
                    kept += item.copy(options = fresh); changed = true; continue
                }
            }
            kept += item
        }
        return if (changed) test.copy(items = kept) else null
    }

    /** One identity per thing asked, whatever the prompt's wording. */
    fun itemKey(item: WeeklyTestItem): String =
        "${item.kind.name.lowercase()}|${CarryoverDetector.normalized(item.answer)}"

    // ── speak

    /** Fluent-self sentences of 4–16 words, the ones carrying an offered
     *  phrase first, never a line the listen items already used. */
    private fun speakItems(fluentTurns: List<Pair<Session, Turn>>, sessions: List<Session>,
                           excluding: Set<String>, language: String, rng: Random): List<WeeklyTestItem> {
        val offered = sessions.flatMap { it.summary?.expressionsOffered.orEmpty() }.map { it.lowercase() }.toSet()
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
                // The line's identity is the talk book's: a one-sentence turn
                // keeps its turn id, a cut sentence the book's sentence id —
                // the turn's audio must never play for a sentence.
                val lineId = if (parts.size == 1) turn.id else TalkCurriculum.sentenceLineId(turn.id, index)
                lines += Line(sentence, session, lineId, offered.count { lower.contains(it) })
            }
        }
        return lines.shuffled(rng).sortedByDescending { it.weight }.take(MAX_SPEAK).map {
            WeeklyTestItem(kind = WeeklyTestItem.Kind.SPEAK, prompt = "", answer = it.text,
                sessionId = it.session.id, turnId = it.lineId)
        }
    }

    // ── meaning

    private suspend fun meaningItems(fluentTexts: List<String>, material: Material, language: String,
                                     level: CefrLevel, rng: Random,
                                     gloss: suspend (String) -> String?): List<WeeklyTestItem> {
        val weekLemmas = VocabLemmas.lemmas(fluentTexts, language)
        // Notebook words the week's talks used lead; the rest of the notebook
        // follows; words the learner produced this week close the list.
        val candidates = ArrayList<String>()
        val seen = HashSet<String>()
        fun add(w: String) {
            val k = w.lowercase()
            if (k.isEmpty() || k in seen || !TextScript.isInTargetScript(w, language)) return
            seen += k; candidates += w
        }
        material.studying.filter { it.lowercase() in weekLemmas }.forEach(::add)
        material.studying.forEach(::add)
        material.usedRecently.forEach(::add)

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

    private fun gapItems(sessions: List<Session>, fluentTurns: List<Pair<Session, Turn>>,
                         userTurns: List<Pair<Session, Turn>>, library: List<String>,
                         language: String, rng: Random): List<WeeklyTestItem> {
        data class Candidate(val phrase: String, val sentence: String, val session: Session, val turn: Turn)
        val candidates = ArrayList<Candidate>()
        val seen = HashSet<String>()
        fun collect(phrases: List<String>, turns: List<Pair<Session, Turn>>) {
            for (phrase in phrases) {
                val key = exprKey(phrase)
                if (key.isEmpty() || key in seen || !TextScript.isInTargetScript(phrase, language)) continue
                val hit = firstSentence(phrase, turns, language) ?: continue
                seen += key
                candidates += Candidate(phrase, hit.first, hit.second, hit.third)
            }
        }
        // The fluent self's phrases first, then the ones the learner used.
        for (s in sessions) collect(s.summary?.expressionsOffered.orEmpty(), fluentTurns)
        for (s in sessions) collect(s.summary?.expressionsUsed.orEmpty(), userTurns)

        var weekPool = candidates.map { it.phrase }
        for (s in sessions) {
            weekPool = weekPool + s.summary?.expressionsOffered.orEmpty() + s.summary?.expressionsUsed.orEmpty()
        }
        weekPool = dedupe(weekPool, ::exprKey)
        val libraryPool = dedupe(library, ::exprKey)

        val out = ArrayList<WeeklyTestItem>()
        for (c in candidates.shuffled(rng)) {
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
                sessionId = c.session.id, turnId = c.turn.id)
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

    private fun buildItems(cards: List<DrillCard>, start: Long, end: Long, now: Long,
                           language: String, rng: Random): List<WeeklyTestItem> {
        val spaced = WordSplitter.spaced(language)
        val pool = cards.filter { card ->
            if (card.box >= DrillIngest.MAX_BOX || card.sourcePhrase.isBlank()) return@filter false
            if (!TextScript.isInTargetScript(card.targetPhrase, language) ||
                !TextScript.isInTargetScript(card.sourcePhrase, language)) return@filter false
            val touched = listOfNotNull(card.createdAt, card.lastReviewedAt)
            if (touched.none { it > start && it <= end }) return@filter false
            // An unspaced language's "words" are segments, so a plain
            // sentence runs longer in tiles.
            val n = WordSplitter.count(card.targetPhrase, language)
            n >= 3 && n <= (if (spaced) 12 else 18)
        }
        // Due cards first (the test is a review), then the newest.
        val ordered = pool.sortedWith(compareBy<DrillCard> { if (it.nextReviewAt <= now) 0 else 1 }
            .thenByDescending { it.createdAt })
        val out = ArrayList<WeeklyTestItem>()
        val seen = HashSet<String>()
        for (card in ordered) {
            if (out.size >= MAX_BUILD) break
            if (!seen.add(DrillIngest.normalizedForMatch(card.targetPhrase))) continue
            out += WeeklyTestItem(kind = WeeklyTestItem.Kind.BUILD,
                prompt = DrillIngest.relevantFragment(card.sourcePhrase, card.targetPhrase, maxChars = 120),
                answer = card.targetPhrase,
                options = buildTiles(card.targetPhrase, card.sourcePhrase, language, rng),
                sessionId = card.sourceSessionId, turnId = card.sourceTurnId,
                cardId = card.id, note = card.reason)
        }
        return out
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

    // ── listen

    private fun listenItems(fluentTurns: List<Pair<Session, Turn>>, hasAudio: (Turn) -> Boolean,
                            language: String, rng: Random): List<WeeklyTestItem> {
        // Heard and rebuilt from its own word tiles with the text hidden —
        // dictation (iOS `985694e`). Whole turns only: the saved audio is the turn.
        val max = if (WordSplitter.spaced(language)) 14 else 18
        fun fits(text: String): Boolean {
            val n = WordSplitter.count(text, language)
            return n in 4..max && TextScript.isInTargetScript(text, language)
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

    /** A build/listen item: the tiles in the order the learner laid them. */
    fun isCorrect(item: WeeklyTestItem, tiles: List<String>, language: String): Boolean =
        tiles.map(::tileKey) == WordSplitter.words(item.answer, language).map(::tileKey)

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
     *   build    right → one Leitner rung up · wrong → one rung down
     *   listen / speak → nothing (a spoken take is already a shadow attempt)
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
                WeeklyTestItem.Kind.BUILD -> {
                    val card = item.cardId?.let { cards[it] } ?: continue
                    // Both log the drill rep themselves.
                    if (answer.correct) drills.markCorrect(card, language, now)
                    else drills.markIncorrect(card, language, now)
                }
                WeeklyTestItem.Kind.LISTEN, WeeklyTestItem.Kind.SPEAK -> Unit
            }
        }
        StoreEvents.bump()
    }

    private fun dedupe(list: List<String>, key: (String) -> String): List<String> {
        val seen = HashSet<String>()
        return list.filter { seen.add(key(it)) }
    }
}
