package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.Carryover
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionOrigin
import com.roro.futurevoice.talk.TurnRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.time.Instant
import java.time.ZoneId

/**
 * "Your week" — the week that just closed, told as a deck of cards
 * (iOS `WeekRecap.swift`, `633418f`).
 *
 * The week is the WEEKLY TEST's week ([WeeklyTestSchedule]): the deck opens at
 * the same moment the test does, recaps the seven days before it, and its
 * last card IS the test. So the learner meets one ritual a week — look back,
 * then prove it.
 *
 * Not the same thing as the weekly REPORT (the speaking assessment on
 * Progress). This is what the learner DID: every number here is counted in
 * code from the logs the app already keeps, and the one model call
 * ([WeekRecapCoach]) writes only the coach's note about those numbers.
 *
 * A recap is FROZEN once built: the week it describes is over, and the logs
 * it is drawn from are pruned (the talk meter keeps 45 days).
 */
@Serializable
data class WeekRecap(
    /** The week is [start, end); `end` is the opening that closed it. */
    @Serializable(with = IsoDateMillisSerializer::class) val start: Long,
    @Serializable(with = IsoDateMillisSerializer::class) val end: Long,
    /** One per day of the week, oldest first. */
    val activeDays: List<Boolean>,
    val streak: Int,
    val talkSeconds: Int,
    val previousTalkSeconds: Int,
    /** Every talk the learner spoke in, oldest first. */
    val talks: List<TalkLine>,
    /** Studied material the learner then SAID in a talk — the week's win. */
    val usedCount: Int,
    val used: List<Evidence>,
    val cardsCleared: Int,
    val wordsKnown: Int,
    val expressionsKnown: Int,
    val shadowTakes: Int,
    val shadowAverage: Int? = null,
    val previousShadowAverage: Int? = null,
    val scenes: Int,
    /** Words and expressions that became known or used this week — the
     *  review card's headline number IS this list's count. */
    val nowYours: List<String>,
    /** Sentence cards retired this week ("Got it", or said in a talk). */
    val sentencesGot: List<String>,
    /** Phrases the fluent self used that the learner hasn't, each with the
     *  fluent self's own sentence. */
    val newExpressionCount: Int,
    val newExpressions: List<Evidence>,
    /** Review cards minted from this week's corrections. */
    val newCards: Int,
    /** The same correction, twice or more. */
    val stumbles: List<Stumble>,
    /** Lines shadowed below the retry bar, lowest first. */
    val shakyLines: List<Stumble>,
    /** Last week's test, if one was finished inside this week. */
    val testScore: Int? = null,
    val testTotal: Int? = null,
    val coach: Coach? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val createdAt: Long = System.currentTimeMillis(),
) {
    @Serializable
    data class TalkLine(
        val title: String,
        @Serializable(with = IsoDateMillisSerializer::class) val day: Long,
        val minutes: Int,
        /** free · news · scenario · person */
        val kind: String,
    )

    @Serializable
    data class Evidence(val item: String, val quote: String)

    @Serializable
    data class Stumble(
        val was: String,
        val now: String,
        /** Times it came up (a fix), or the take's score (a shaky line). */
        val count: Int,
    )

    /** The coach's read — every quoted example checked in code against the
     *  learner's own lines before it is kept ([WeekRecapCoach.verified]). */
    @Serializable
    data class Coach(
        val headline: String,
        val insight: String = "",
        val insightQuote: String = "",
        val grammar: List<Pattern> = emptyList(),
        val upgrades: List<Upgrade> = emptyList(),
        val plan: List<String> = emptyList(),
    ) {
        @Serializable
        data class Pattern(val rule: String, val examples: List<Pair>, val tip: String)

        @Serializable
        data class Pair(val was: String, val now: String)

        @Serializable
        data class Upgrade(
            val instead: String,
            /** Counted in code across their lines. */
            val count: Int,
            val better: String,
            val original: String,
            val rewritten: String,
            val note: String,
        )
    }

    val talkMinutes: Int get() = talkSeconds / 60
    val daysActive: Int get() = activeDays.count { it }
    val reviewTotal: Int get() = cardsCleared + wordsKnown + expressionsKnown
    /** Anything at all happened — a recap of nothing is not shown unasked. */
    val hasActivity: Boolean get() = daysActive > 0 || talkSeconds > 0
}

// MARK: - Build

object WeekRecapBuilder {
    private const val DAY_MS = 86_400_000L
    private const val WEEK_MS = 7 * DAY_MS

    /** The week that the most recent opening closed. */
    fun lastWeek(context: Context, now: Long = System.currentTimeMillis(),
                 zone: ZoneId = ZoneId.systemDefault()): Pair<Long, Long> {
        val end = WeeklyTestSettings.schedule(context).currentOpening(now, zone)
        return (end - WEEK_MS) to end
    }

    /** Local midnights of the seven days the week starts on. */
    fun days(start: Long, zone: ZoneId = ZoneId.systemDefault()): List<Long> {
        val first = Instant.ofEpochMilli(start).atZone(zone).toLocalDate()
        return (0L until 7L).map { first.plusDays(it).atStartOfDay(zone).toInstant().toEpochMilli() }
    }

    /** Metered talk, all languages, from the day [from] falls on until [to]. */
    fun talkSeconds(context: Context, from: Long, to: Long, zone: ZoneId = ZoneId.systemDefault()): Int {
        var day = Instant.ofEpochMilli(from).atZone(zone).toLocalDate()
        var seconds = 0
        while (true) {
            val at = day.atStartOfDay(zone).toInstant().toEpochMilli()
            if (at >= to) break
            seconds += TalkTimeLog.recentSeconds(context, 1, at).firstOrNull()?.second ?: 0
            day = day.plusDays(1)
        }
        return seconds
    }

    /** Every talk on the phone, in every enrolled language — a week is the
     *  learner's, not a language's (iOS `loadAcrossLanguages`). */
    suspend fun sessionsAcrossLanguages(context: Context): List<Session> {
        val store = SessionStore.shared(context)
        val active = LanguageScope.active(context)
        val languages = (LanguageScope.enrolled(context) + active).distinct()
        val all = languages.flatMap { store.load(it) }
        store.load(active)   // leave the store's cache on the active language
        return all
    }

    suspend fun build(context: Context, start: Long, end: Long,
                      zone: ZoneId = ZoneId.systemDefault()): WeekRecap {
        val language = LanguageScope.active(context)
        val days = days(start, zone)
        val sessions = sessionsAcrossLanguages(context)
        val spokenDays = sessions.mapNotNull { s -> lastUserLine(s) }
            .map { Instant.ofEpochMilli(it).atZone(zone).toLocalDate() }.toSet()
        val active = days.map { day ->
            TalkTimeLog.studied(context, day) ||
                Instant.ofEpochMilli(day).atZone(zone).toLocalDate() in spokenDays
        }
        val log = days.mapNotNull { PracticeLog.day(context, it) }
        val vocab = VocabStore.shared(context)
        val words = vocab.wordEntries(language)
        val expressions = vocab.expressionEntries(language).associate { it.text to it.firstAt }
        val cards = DrillStore.shared(context).load(language)
        val attempts = ShadowAttemptStore.shared(context).load(language)
        val test = WeeklyTestStore.shared(context).load(language)
            .firstOrNull { t -> !t.isMonthly && t.finishedAt.let { it != null && it >= start && it < end } }
        return assemble(
            start = start, end = end,
            activeDays = active,
            streak = TalkTimeLog.streakDays(context, end - 1),
            talkSeconds = talkSeconds(context, start, end, zone),
            previousTalkSeconds = talkSeconds(context, start - WEEK_MS, start, zone),
            sessions = sessions,
            firstSeen = words + expressions,
            cards = cards,
            attempts = attempts,
            log = log,
            testScore = test?.score,
            testTotal = test?.total,
        )
    }

    private fun lastUserLine(s: Session): Long? = s.turns.lastOrNull { it.role == TurnRole.USER }?.timestamp

    /** The counting, kept off the stores so a test can hand it a week. */
    fun assemble(
        start: Long, end: Long,
        activeDays: List<Boolean>,
        streak: Int,
        talkSeconds: Int,
        previousTalkSeconds: Int,
        sessions: List<Session>,
        /** Word / expression → when it was first known or said. */
        firstSeen: Map<String, Long>,
        cards: List<DrillCard>,
        attempts: List<ShadowAttempt>,
        log: List<PracticeLog.Day>,
        testScore: Int?,
        testTotal: Int?,
    ): WeekRecap {
        fun inWeek(at: Long?) = at != null && at >= start && at < end

        // Talks the learner actually spoke in, dated by their last line.
        val week = sessions.filter { inWeek(lastUserLine(it)) }
            .sortedBy { it.turns.firstOrNull()?.timestamp ?: Long.MIN_VALUE }
        val talkLines = week.map(::talkLine)

        // Used: deduped by item, strongest source first.
        val usedByItem = HashMap<String, kotlin.Pair<Carryover, Int>>()
        for (session in week) {
            for (c in session.summary?.carryovers.orEmpty()) {
                if (!inWeek(c.detectedAt)) continue
                val key = CarryoverDetector.normalized(c.item)
                val rank = sourceRank(c.source)
                val existing = usedByItem[key]
                if (existing != null && existing.second <= rank) continue
                usedByItem[key] = c to rank
            }
        }
        val used = usedByItem.values
            .sortedWith(compareBy<kotlin.Pair<Carryover, Int>> { it.second }.thenByDescending { it.first.detectedAt })
            .map { WeekRecap.Evidence(it.first.item, it.first.quote) }

        // Became yours: first known or used this week, newest first.
        val nowYours = firstSeen.entries.filter { inWeek(it.value) }
            .sortedByDescending { it.value }.map { it.key }
        val sentencesGot = cards
            .filter { inWeek(it.usedInTalkAt) || (it.box >= 5 && inWeek(it.lastReviewedAt)) }
            .sortedByDescending { it.lastReviewedAt ?: it.createdAt }
            .map { it.targetPhrase }
        val newCards = cards.count { inWeek(it.createdAt) }

        // New material from the fluent self, with the line it was said in.
        val offered = ArrayList<WeekRecap.Evidence>()
        val seenOffered = HashSet<String>()
        for (session in week) {
            for (phrase in session.summary?.expressionsOffered.orEmpty()) {
                val key = CarryoverDetector.normalized(phrase)
                if (key.isEmpty() || !seenOffered.add(key)) continue
                offered.add(WeekRecap.Evidence(phrase, sentence(phrase, session) ?: ""))
            }
        }

        // Stumbles: the same fix, more than once.
        val fixes = LinkedHashMap<String, WeekRecap.Stumble>()
        for (session in week) {
            for (turn in session.turns) {
                if (turn.role != TurnRole.USER || turn.excludedFromScoring) continue
                for (fix in turn.suggestion?.fixes.orEmpty()) {
                    val key = CarryoverDetector.normalized(fix.now)
                    if (key.isEmpty()) continue
                    val prev = fixes[key] ?: WeekRecap.Stumble(fix.was, fix.now, 0)
                    fixes[key] = prev.copy(count = prev.count + 1)
                }
            }
        }
        val stumbles = fixes.values.filter { it.count >= 2 }.sortedByDescending { it.count }

        // Shadowing.
        val thisWeek = attempts.filter { inWeek(it.createdAt) }
        val previous = attempts.filter { it.createdAt >= start - WEEK_MS && it.createdAt < start }
        fun average(list: List<ShadowAttempt>): Int? =
            if (list.isEmpty()) null
            else Math.round(list.sumOf { it.overallScore }.toDouble() / list.size).toInt()
        // A line's BEST take this week is its verdict.
        val bestByLine = HashMap<String, ShadowAttempt>()
        for (attempt in thisWeek) {
            if (attempt.isPartial) continue
            val kept = bestByLine[attempt.turnId]
            if (kept != null && kept.overallScore >= attempt.overallScore) continue
            bestByLine[attempt.turnId] = attempt
        }
        val shaky = bestByLine.values
            .filter { it.overallScore < ShadowPicks.RETRY_THRESHOLD }
            .sortedBy { it.overallScore }
            .map { WeekRecap.Stumble(it.learnerTranscript, it.targetText, it.overallScore) }

        return WeekRecap(
            start = start, end = end,
            activeDays = activeDays,
            streak = streak,
            talkSeconds = talkSeconds,
            previousTalkSeconds = previousTalkSeconds,
            talks = talkLines,
            usedCount = used.size,
            used = used.take(4),
            cardsCleared = log.sumOf { it.drillDone },
            wordsKnown = log.sumOf { it.wordDone },
            expressionsKnown = log.sumOf { it.expressionDone },
            shadowTakes = log.sumOf { it.shadowReps },
            shadowAverage = average(thisWeek),
            previousShadowAverage = average(previous),
            scenes = log.sumOf { it.sceneReps },
            nowYours = nowYours.take(60),
            sentencesGot = sentencesGot.take(30),
            newExpressionCount = offered.size,
            newExpressions = offered.take(4),
            newCards = newCards,
            stumbles = stumbles.take(2),
            shakyLines = shaky.take(2),
            testScore = testScore,
            testTotal = testTotal,
            coach = null,
        )
    }

    private fun talkLine(session: Session): WeekRecap.TalkLine {
        val first = session.turns.firstOrNull()?.timestamp ?: session.startedAt
        val last = session.turns.lastOrNull()?.timestamp ?: first
        val kind = when {
            session.counterpartId != null -> "person"
            session.origin == SessionOrigin.SCENARIO -> "scenario"
            session.origin == SessionOrigin.NEWS -> "news"
            else -> "free"
        }
        // A talk with no title yet is drawn as "Conversation" by the deck.
        return WeekRecap.TalkLine(session.displayTitle.orEmpty(), first,
            maxOf(1, Math.round((last - first) / 60_000.0).toInt()), kind)
    }

    /** The fluent self's sentence that carried [phrase], if one can be found. */
    private fun sentence(phrase: String, session: Session): String? {
        val needle = phrase.lowercase()
        for (turn in session.turns) {
            if (turn.role != TurnRole.FLUENT_SELF) continue
            TalkCurriculum.sentences(turn.transcript)
                .firstOrNull { it.lowercase().contains(needle) }
                ?.let { return it.trim() }
        }
        return null
    }

    /** A card from a past talk took more to produce than a suggestion still
     *  on screen — the same order `Carryover.Source` is declared in on iOS. */
    private fun sourceRank(source: Carryover.Source): Int = when (source) {
        Carryover.Source.DRILL_CARD -> 0
        Carryover.Source.CURRICULUM_ITEM -> 1
        Carryover.Source.STUDYING_EXPRESSION -> 2
        Carryover.Source.STUDYING_WORD -> 3
        Carryover.Source.KNOWN_EXPRESSION -> 4
        Carryover.Source.KNOWN_WORD -> 5
        Carryover.Source.SUGGESTION -> 6
    }
}

// MARK: - Store

/**
 * Frozen recaps, one per week, plus which weeks have been shown. Device-local
 * and across languages: a week is the learner's, not a language's
 * (`week-recaps-v3.json`, iOS's file name).
 */
object WeekRecapStore {
    private const val FILE_NAME = "week-recaps-v3.json"
    private const val PREFS = "futurevoice"
    private const val SEEN_KEY = "futurevoice.weekRecap.seenEnd"

    private fun file(c: Context) = File(c.filesDir, FILE_NAME)
    private val serializer = ListSerializer(WeekRecap.serializer())

    suspend fun load(c: Context): List<WeekRecap> = withContext(Dispatchers.IO) {
        val f = file(c)
        if (!f.exists()) emptyList()
        else runCatching { StoreJson.json.decodeFromString(serializer, f.readText()) }
            .getOrElse { emptyList() }.sortedByDescending { it.end }
    }

    suspend fun recap(c: Context, endingAt: Long): WeekRecap? =
        load(c).firstOrNull { kotlin.math.abs(it.end - endingAt) < 1000 }

    suspend fun save(c: Context, recap: WeekRecap) {
        val all = load(c).filterNot { kotlin.math.abs(it.end - recap.end) < 1000 } + recap
        write(c, all)
    }

    /** The last week's recap — frozen on first ask, since the week is over. */
    suspend fun lastWeek(c: Context, now: Long = System.currentTimeMillis()): WeekRecap {
        val (start, end) = WeekRecapBuilder.lastWeek(c, now)
        recap(c, end)?.let { return it }
        return WeekRecapBuilder.build(c, start, end).also { save(c, it) }
    }

    fun wasShown(c: Context, recap: WeekRecap): Boolean =
        p(c).getLong(SEEN_KEY, Long.MIN_VALUE) >= recap.end

    fun markShown(c: Context, recap: WeekRecap) {
        p(c).edit().putLong(SEEN_KEY, maxOf(p(c).getLong(SEEN_KEY, Long.MIN_VALUE), recap.end)).apply()
    }

    fun resetShown(c: Context) { p(c).edit().remove(SEEN_KEY).apply() }

    /** Developer: forget the frozen copy so the next ask rebuilds it. */
    suspend fun remove(c: Context, endingAt: Long) {
        write(c, load(c).filter { kotlin.math.abs(it.end - endingAt) >= 1000 })
    }

    private suspend fun write(c: Context, list: List<WeekRecap>) = withContext(Dispatchers.IO) {
        val target = file(c)
        val tmp = File(target.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(StoreJson.json.encodeToString(serializer, list))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }

    private fun p(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/** Where a request to show "Your week" waits for the root to raise it
 *  (iOS `DailyCallInbox.pendingWeekRecap` / `debugWeekRecap`). */
object WeekRecapInbox {
    /** The week-turn notification was tapped: show it, seen or not. */
    val asked = MutableStateFlow(false)
    /** Developer: a recap built on demand (any window), raised as is. */
    val debug = MutableStateFlow<WeekRecap?>(null)
    /** Developer: run the unasked offer again ("slide up again"). */
    val reoffer = MutableStateFlow(0)
}
