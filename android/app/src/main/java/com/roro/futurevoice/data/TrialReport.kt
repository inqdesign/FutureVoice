package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.time.Instant
import java.time.ZoneId

/**
 * The free twenty minutes, read back as a report (iOS `TrialReport`,
 * 2026-10-19, founder: "when the free time runs out, don't just put the
 * paywall up — give them a report of what those minutes showed, a test, their
 * level, and a routine to keep going with").
 *
 * It is the weekly deck (`WeekRecapDeck` in trial mode) over the window from
 * the first talk to now, then three cards the week doesn't have: a test the
 * learner must take (built from the same window, [WeeklyTestEngine.Scope]),
 * the level — the FIRST formal assessment, run early ([assessTrialLevel])
 * because twenty minutes of call time is rarely fifteen of the learner's own
 * speech, which is the normal gate — and the routine, whose button is the way
 * to the plans. The plans are the last card, never the first thing.
 *
 * Who sees it: a free account that has NEVER had a subscription
 * (`subscriptionStatus == "inactive"`; a lapsed subscriber's empty pool is not
 * a trial ending) with the pool spent and at least one talk spoken in. It is
 * offered at the end of the call that spent the pool, and again on a later
 * launch if it was closed before the routine card — at most [TrialReportStore.MAX_OFFERS]
 * times: the deck is a moment, not a page.
 */
@Serializable
data class TrialReport(
    val recap: WeekRecap,
    val targetLanguage: String,
    /** The trial test, once built. Read back from [WeeklyTestStore] by id. */
    val testId: String? = null,
    /** True once the test could not be built from the window — too little
     *  material — so the deck moves on instead of asking for the impossible. */
    val testThin: Boolean = false,
    val level: String? = null,
    val levelRationale: String? = null,
    @Serializable(with = IsoDateMillisSerializer::class) val builtAt: Long,
    /** The fluent self's narration of the deck ([com.roro.futurevoice.net.ReportNarration]),
     *  written once and replayed from here. */
    val narration: com.roro.futurevoice.net.ReportNarration? = null,
    /** How the learner used the app, worded ([HabitAdvice]) — the routine
     *  card's evidence. */
    val habitAdvice: HabitAdvice? = null,
    /** The learner's OWN speaking time per language in the window, most first
     *  (iOS 2026-10-28). Twenty minutes of call is rarely ten of the learner's
     *  voice, and one learner in five splits it across languages, so the level
     *  card says what it was read from and names the language this report
     *  doesn't read. Empty on reports built before. */
    val spoken: List<Speech> = emptyList(),
) {
    @Serializable
    data class Speech(val language: String, val seconds: Int)

    val ownSpeechSeconds: Int?
        get() = spoken.firstOrNull { LanguageCatalog.sameLanguage(it.language, targetLanguage) }?.seconds
    val otherLanguages: List<Speech>
        get() = spoken.filter { !LanguageCatalog.sameLanguage(it.language, targetLanguage) && it.seconds > 0 }

    companion object {
        /** Under this much of their own speech, the level is a first read. */
        const val THIN_SPEECH_SECONDS = 300
    }
}

object TrialReportStore {
    const val MAX_OFFERS = 2
    /** Fewer than the weekly paper's five: twenty minutes is a small window,
     *  and a required test of two questions is still a test of the learner's
     *  own lines. Below this the test card says so and lets them past. */
    const val MIN_TEST_ITEMS = 3
    /** The deck is on screen, so nothing else raises a second one over it
     *  (iOS `isShowing`). */
    @Volatile var isShowing = false

    private const val PREFS = "futurevoice"
    private const val OFFERS_KEY = "futurevoice.trialReport.offers"
    private const val FINISHED_KEY = "futurevoice.trialReport.finished"
    private const val FILE_PREFIX = "trial_report"

    private fun p(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    /** One report per TARGET language: its test lives in that language's
     *  store and its level is that language's, so a switch must neither show
     *  the other one nor overwrite it. */
    private fun file(c: Context, language: String) = File(c.filesDir, "${FILE_PREFIX}_$language.json")

    fun finished(c: Context): Boolean = p(c).getBoolean(FINISHED_KEY, false)
    fun setFinished(c: Context) { p(c).edit().putBoolean(FINISHED_KEY, true).apply() }

    fun offers(c: Context): Int = p(c).getInt(OFFERS_KEY, 0)
    fun countOffer(c: Context) { p(c).edit().putInt(OFFERS_KEY, offers(c) + 1).apply() }

    /** Sessions the learner spoke in — the only ones a report can read. */
    private suspend fun spokenSessions(c: Context): List<Session> =
        WeekRecapBuilder.sessionsAcrossLanguages(c)
            .filter { s -> s.endedAt != null && s.turns.any { it.role == TurnRole.USER } }

    /** The account side of the gate. The device side (offers, finished, a
     *  spoken talk on file) is checked here too, so one call answers it. */
    suspend fun shouldOffer(c: Context, account: AccountStatus): Boolean {
        if (finished(c) || offers(c) >= MAX_OFFERS) return false
        // A fetch that failed reads as "never subscribed, nothing left";
        // only an answer the server actually gave may say so.
        if (!account.ownershipKnown || account.subscriptionStatus != "inactive" ||
            account.unlimited || !account.needsSubscription) return false
        return spokenSessions(c).isNotEmpty()
    }

    suspend fun load(c: Context, language: String): TrialReport? = withContext(Dispatchers.IO) {
        val f = file(c, language)
        if (!f.exists()) null
        else runCatching { StoreJson.json.decodeFromString(TrialReport.serializer(), f.readText()) }.getOrNull()
    }

    suspend fun save(c: Context, report: TrialReport) = withContext(Dispatchers.IO) {
        val target = file(c, report.targetLanguage)
        val tmp = File(target.parentFile, "${target.name}.tmp")
        tmp.writeText(StoreJson.json.encodeToString(TrialReport.serializer(), report))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }

    /**
     * The saved report, or a fresh one from the first talk to now. Built once:
     * the free minutes are over, so the window cannot grow, and a second build
     * would rewrite a coach the learner already read.
     */
    suspend fun current(c: Context, targetLanguage: String, now: Long = System.currentTimeMillis()): TrialReport {
        load(c, targetLanguage)?.let { return it }
        val sessions = spokenSessions(c)
        val first = sessions.map { s -> s.turns.firstOrNull()?.timestamp ?: s.startedAt }.minOrNull() ?: now
        return build(c, first, sessions, targetLanguage, now)
    }

    /** Me → Developer (debug builds): the report over the last [days] of this
     *  phone's own talks, built fresh every time, past every gate — so it can
     *  be LOOKED at before it reaches a learner (iOS `preview`). The
     *  end-of-report feedback ask is made showable again. */
    suspend fun preview(c: Context, targetLanguage: String, days: Int = 7,
                        now: Long = System.currentTimeMillis()): TrialReport {
        withContext(Dispatchers.IO) { file(c, targetLanguage).delete() }
        com.roro.futurevoice.ui.FeedbackPrompt.reset(c, com.roro.futurevoice.ui.FeedbackContext.TRIAL_REPORT)
        val start = now - days * 86_400_000L
        val sessions = spokenSessions(c).filter { s ->
            (s.turns.lastOrNull { it.role == TurnRole.USER }?.timestamp ?: s.startedAt) >= start
        }
        return build(c, start, sessions, targetLanguage, now)
    }

    private suspend fun build(c: Context, first: Long, sessions: List<Session>,
                              targetLanguage: String, now: Long): TrialReport {
        val zone = ZoneId.systemDefault()
        val start = Instant.ofEpochMilli(first).atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()
        val spoken = speech(sessions)
        // Two languages spoken: the report reads the one it is opened in, and
        // its minutes and talks are that language's, so the cover's number is
        // the number the level and the coach were read from. One language:
        // the meter's every-language total, as before.
        val several = spoken.count { it.seconds > 0 } > 1
        var recap = WeekRecapBuilder.build(c, start, now + 1_000, wholeWindow = true,
                                           onlyLanguage = if (several) targetLanguage else null)
        // No week before a trial; the talk card's comparison line stays quiet.
        recap = recap.copy(previousTalkSeconds = 0, previousShadowAverage = null)
        // The meter's log is pruned at 45 days; a pool spent before that
        // still has its talks, so their own lengths stand in.
        if (recap.talkSeconds == 0) recap = recap.copy(talkSeconds = recap.talks.sumOf { it.minutes * 60 })
        val report = TrialReport(recap = recap, targetLanguage = targetLanguage, builtAt = now, spoken = spoken)
        save(c, report)
        return report
    }

    /** The learner's own speech per language, read from their turns (the
     *  lines a level is judged on: no misheard or coach-read lines), most first. */
    private fun speech(sessions: List<Session>): List<TrialReport.Speech> {
        val byLanguage = linkedMapOf<String, Int>()
        for (s in sessions) {
            if (s.isPractice) continue
            val ms = s.turns.filter { it.isEvidence }.sumOf { it.durationMs }
            val key = byLanguage.keys.firstOrNull { LanguageCatalog.sameLanguage(it, s.targetLanguage) } ?: s.targetLanguage
            byLanguage[key] = (byLanguage[key] ?: 0) + ms / 1000
        }
        return byLanguage.map { TrialReport.Speech(it.key, it.value) }.sortedByDescending { it.seconds }
    }

    /** Load, change, save in one step — the deck and the test screen both
     *  write this file, and a copy read before a long wait is stale. Null
     *  when there is no report on file. */
    suspend fun update(c: Context, language: String, change: (TrialReport) -> TrialReport): TrialReport? {
        val latest = load(c, language) ?: return null
        val next = change(latest)
        save(c, next)
        return next
    }

    /** Developer: start over. */
    fun reset(c: Context) {
        c.filesDir.listFiles()?.filter { it.name.startsWith(FILE_PREFIX) }?.forEach { it.delete() }
        p(c).edit().remove(OFFERS_KEY).remove(FINISHED_KEY).apply()
    }
}

/** Where the call that spent the free pool asks the root to raise the report
 *  (iOS raises it over the call screen; here the call screen leaves first, as
 *  it does for the plans). */
object TrialReportInbox {
    val pending = MutableStateFlow(false)
    /** Me → Developer's preview ([TrialReportStore.preview]). */
    val preview = MutableStateFlow<TrialReport?>(null)
}

/**
 * The level for the trial report (iOS `AppState.assessTrialLevel`). An
 * assessment already on file wins. Otherwise the first one is run NOW, past
 * the 15-minute speech gate (founder's call, 2026-10-19): it is saved like any
 * report, so Progress shows the same level, and the next one waits on the
 * ordinary cadence. No level-up sheet — the report's own card is the
 * announcement ([onMeasured] sets the level quietly). When the talks can't
 * carry an assessment, the median of their per-talk reads stands in; null
 * only when there is nothing at all to read.
 */
suspend fun assessTrialLevel(
    c: Context,
    language: String,
    nativeLanguage: String,
    onMeasured: (String) -> Unit,
): Pair<CefrLevel, String?>? {
    fun strict(raw: String?): CefrLevel? = CefrLevel.entries.firstOrNull { it.code.equals(raw?.trim(), ignoreCase = true) }
    val reports = WeeklyReportStore.shared(c)
    reports.load(language).maxByOrNull { it.generatedAt }?.let { r ->
        strict(r.cefrLevel)?.let { return it to r.levelRationale }
    }
    val sessions = SessionStore.shared(c).load(language)
        .filter { it.endedAt != null && it.archivedAt == null && !it.isPractice }
    if (sessions.isNotEmpty()) {
        val from = LanguageScope.level(c, language, "")
        runCatching {
            com.roro.futurevoice.net.WeeklyReportEngine.generate(c, sessions, null, language, nativeLanguage)
        }.onFailure { e ->
            Analytics.capture("level_assess_failed", mapOf(
                "reason" to "trial_report", "error" to e.toString().take(200)))
        }.getOrNull()?.let { report ->
            reports.save(report, language)
            strict(report.cefrLevel)?.let { level ->
                Analytics.capture("level_assessed", mapOf(
                    "from" to from, "to" to level.code, "reason" to "trial_report",
                    "talks" to report.sessionCount, "first" to true))
                onMeasured(level.code)
                return level to report.levelRationale
            }
        }
    }
    val reads = sessions.mapNotNull { strict(it.summary?.scorecard?.cefrLevel) }.sortedBy { it.ordinal }
    if (reads.isEmpty()) return null
    return reads[reads.size / 2] to null
}
