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
)

object TrialReportStore {
    const val MAX_OFFERS = 2
    /** Fewer than the weekly paper's five: twenty minutes is a small window,
     *  and a required test of two questions is still a test of the learner's
     *  own lines. Below this the test card says so and lets them past. */
    const val MIN_TEST_ITEMS = 3

    private const val PREFS = "futurevoice"
    private const val OFFERS_KEY = "futurevoice.trialReport.offers"
    private const val FINISHED_KEY = "futurevoice.trialReport.finished"
    private const val FILE_NAME = "trial_report.json"

    private fun p(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun file(c: Context) = File(c.filesDir, FILE_NAME)

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
        if (account.subscriptionStatus != "inactive" || account.unlimited || !account.needsSubscription) return false
        return spokenSessions(c).isNotEmpty()
    }

    suspend fun load(c: Context): TrialReport? = withContext(Dispatchers.IO) {
        val f = file(c)
        if (!f.exists()) null
        else runCatching { StoreJson.json.decodeFromString(TrialReport.serializer(), f.readText()) }.getOrNull()
    }

    suspend fun save(c: Context, report: TrialReport) = withContext(Dispatchers.IO) {
        val target = file(c)
        val tmp = File(target.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(StoreJson.json.encodeToString(TrialReport.serializer(), report))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }

    /**
     * The saved report, or a fresh one from the first talk to now. Built once:
     * the free minutes are over, so the window cannot grow, and a second build
     * would rewrite a coach the learner already read.
     */
    suspend fun current(c: Context, targetLanguage: String, now: Long = System.currentTimeMillis()): TrialReport {
        load(c)?.takeIf { it.targetLanguage == targetLanguage }?.let { return it }
        val first = spokenSessions(c).map { s -> s.turns.firstOrNull()?.timestamp ?: s.startedAt }.minOrNull() ?: now
        val zone = ZoneId.systemDefault()
        val start = Instant.ofEpochMilli(first).atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()
        var recap = WeekRecapBuilder.build(c, start, now + 1_000)
        // No week before a trial; the talk card's comparison line stays quiet.
        recap = recap.copy(previousTalkSeconds = 0, previousShadowAverage = null)
        // The meter's log is pruned at 45 days; a pool spent before that
        // still has its talks, so their own lengths stand in.
        if (recap.talkSeconds == 0) recap = recap.copy(talkSeconds = recap.talks.sumOf { it.minutes * 60 })
        val report = TrialReport(recap = recap, targetLanguage = targetLanguage, builtAt = now)
        save(c, report)
        return report
    }

    /** Re-read before writing: the test screen saves its id into the same file. */
    suspend fun update(c: Context, fallback: TrialReport?, change: (TrialReport) -> TrialReport): TrialReport? {
        val latest = load(c) ?: fallback ?: return null
        val next = change(latest)
        save(c, next)
        return next
    }

    /** Developer: start over. */
    fun reset(c: Context) {
        file(c).delete()
        p(c).edit().remove(OFFERS_KEY).remove(FINISHED_KEY).apply()
    }
}

/** Where the call that spent the free pool asks the root to raise the report
 *  (iOS raises it over the call screen; here the call screen leaves first, as
 *  it does for the plans). */
object TrialReportInbox {
    val pending = MutableStateFlow(false)
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
