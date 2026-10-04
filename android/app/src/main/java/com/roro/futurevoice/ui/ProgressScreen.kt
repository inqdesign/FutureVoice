package com.roro.futurevoice.ui

import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.AddComment
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import androidx.compose.material3.HorizontalDivider
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import com.roro.futurevoice.data.Recency
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.data.StudyCollections
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import com.roro.futurevoice.ui.brand.Symbols
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.WorkspacePremium
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.ShadowAttemptStore
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DeepLinkInbox
import com.roro.futurevoice.data.LanguageCatalog
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.data.WeeklyReport
import com.roro.futurevoice.data.WeeklyReportStore
import com.roro.futurevoice.net.WeeklyReportEngine
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.ui.text.font.FontWeight
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DailyStudyPick
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.GoalStore
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.ui.brand.BookCard
import com.roro.futurevoice.ui.brand.Books
import com.roro.futurevoice.ui.brand.EffortCharts
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import androidx.compose.material3.TextButton
import com.roro.futurevoice.data.AppUsageLog
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.DayCardData
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.Session

/**
 * Progress's dimensions. Shadowing is deliberately NOT one: shadow scores
 * measure practice EFFORT, not level, and presenting them as an assessed
 * skill made them read as part of the level estimate. They live in the
 * activity strip and in Practice.
 */
enum class Dim(val labelRes: Int) {
    OVERALL(R.string.overall),
    VOCABULARY(R.string.vocabulary),
    GRAMMAR(R.string.grammar),
    FLUENCY(R.string.fluency),
    EXPRESSIVENESS(R.string.expressiveness),
}

/** Two weeks: long enough to show a habit, short enough to read at a glance. */
private const val EFFORT_DAYS = 14

/** Day-of-month, the only part of a date a fourteen-bar strip has room for. */
private fun dayLabel(at: Long): String =
    java.text.SimpleDateFormat("d", java.util.Locale.US).format(java.util.Date(at))
/**
 * Progress — measured, never guessed. Every number here is computed in code
 * from the talks themselves (`ProgressMath`); the only thing an LLM writes on
 * this tab is the qualitative note beside a figure it did not invent.
 *
 * The overall level is ONE pooled judgment over everything said since the
 * last assessment — never a single talk's read, which is too small a sample
 * to publish. The per-skill pages behind the chips lean on the deterministic
 * measurements (CEFR-graded vocabulary, articulation pace, verified slip
 * density, words per turn). Shadowing and drill reps are PRACTICE, not
 * assessment: they appear as effort and never move the level.
 *
 * No share card here. The day card's home is the Activity page and only
 * there — that page's day summary already says what the day was, and the card
 * is that summary as a picture.
 */
@Composable
fun ProgressBody(language: String, nativeLanguage: String,
                 onOpenAssessment: () -> Unit, onOpenActivity: () -> Unit,
                 goalMinutes: Int = 10,
                 /** A measured CEFR level from a fresh assessment. */
                 onMeasuredLevel: (String) -> Unit = {},
                 /**
                  * Pace and turn length only move by speaking, so the way out
                  * of those pages is a call. Null hides the button rather
                  * than offering a door that opens nowhere — the words and
                  * slips pages route themselves through `DeepLinkInbox`.
                  */
                 onStartTalk: (() -> Unit)? = null,
                 /** Capture runs only: open on a skill page instead of Overall. */
                 initialDim: Dim = Dim.OVERALL) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var todaySeconds by remember { mutableStateOf(0) }
    var minutesByDay by remember { mutableStateOf<List<Pair<Long, Int>>>(emptyList()) }
    var effortByDay by remember { mutableStateOf<List<Pair<String, PracticeLog.Day>>>(emptyList()) }
    var report by remember { mutableStateOf<WeeklyReport?>(null) }
    /** The newest report that actually CARRIES a level — reports written
     *  before the pooled read existed have none, and the latest report is
     *  not always one of them. */
    var levelReport by remember { mutableStateOf<WeeklyReport?>(null) }
    var unlock by remember { mutableStateOf<WeeklyReportEngine.Unlock?>(null) }
    var generating by remember { mutableStateOf(false) }
    var dim by remember { mutableStateOf(initialDim) }
    var carryoverTotal by remember { mutableStateOf(0) }
    var carryoverWeek by remember { mutableStateOf(0) }
    var material by remember { mutableStateOf(0 to 0) }
    var streak by remember { mutableStateOf(0) }
    var avgShadowScore by remember { mutableStateOf(0) }
    // False until the first pass has landed. Every number below starts at
    // zero, and a zero is a CLAIM here ("nothing measured, 0/15 min") — so
    // the pages must not be drawn from it before the archive has been read.
    var loaded by remember { mutableStateOf(false) }
    var metrics by remember { mutableStateOf(ProgressMetrics()) }
    var showHowAssessed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(language, revision) {
        talks = SessionStore.shared(context).load(language)
        todaySeconds = TalkTimeLog.secondsToday(context)
        minutesByDay = TalkTimeLog.recentSeconds(context, EFFORT_DAYS)
        effortByDay = PracticeLog.recent(context, EFFORT_DAYS)
        val reports = WeeklyReportStore.shared(context).load(language)
        report = reports.firstOrNull()
        levelReport = reports.firstOrNull { it.cefrLevel != null }
        // Practice (coach mode) calls are out of the evidence pool: a
        // practice call must never move the learner's level (iOS `6e9eb92`).
        unlock = WeeklyReportEngine.unlockState(talks.filter { it.endedAt != null && !it.isPractice }, report)
        // Studied, then SAID — the loop closing, which is the one number that
        // proves the app worked. The detector already writes it onto every
        // summary; it had simply never been read back.
        val carries = talks.flatMap { it.summary?.carryovers.orEmpty() }
        carryoverTotal = carries.size
        val weekAgo = System.currentTimeMillis() - 7L * 86_400_000L
        carryoverWeek = carries.count { it.detectedAt >= weekAgo }
        // Whole-library mastery: "how far along am I" is THIS tab's question,
        // which is why it lives here rather than on Practice.
        val books = ScenarioStore.shared(context).load(language)
            .filter { it.archivedAt == null }
        material = books.sumOf { b ->
            b.curriculum?.masteredCount ?: 0
        } to books.sumOf { b ->
            b.curriculum?.totalCount ?: 0
        }
        streak = TalkTimeLog.streakDays(context)
        val bands = VocabStore.shared(context).usedWordsByLevel(language)
        val expressions = VocabStore.shared(context).expressionEntries(language).size
        val attempts = ShadowAttemptStore.shared(context).load(language)
        avgShadowScore = attempts.filterNot { it.isPartial }
            .sortedByDescending { it.createdAt }.take(10)
            .map { it.overallScore }.takeIf { it.isNotEmpty() }?.average()?.toInt() ?: 0
        // The walk is several passes over every ended talk plus a scorecard
        // recomputation each — off the main thread, or the tab opens on the
        // still-empty state and a learner with a year of talks reads zeroes.
        val loadedTalks = talks
        metrics = withContext(Dispatchers.Default) {
            ProgressMath.compute(loadedTalks, reports, bands, expressions)
        }
        loaded = true
    }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // The skill chips run FULL-BLEED, like iOS's tab bar under the title:
        // the row is widened past the page's 20 dp gutters and scrolls to the
        // very edge of the screen, with the gutter moved inside as content
        // padding so the first and last chips still line up with the cards.
        Row(
            Modifier.fullBleed(PAGE_GUTTER)
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = PAGE_GUTTER, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Dim.entries.forEach { d ->
                PillChip(label = stringResource(d.labelRes), selected = d == dim) { dim = d }
            }
        }

        // Deliberately NOT the empty state: it says nothing has been
        // measured, which is a lie for anyone with a history, and it is what
        // the tab showed on every entry while the archive was still being
        // read.
        if (!loaded) {
            Box(Modifier.fillMaxWidth().padding(top = 48.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            return@Column
        }

        val seeWords = { DeepLinkInbox.pending.value = DeepLinkInbox.Destination.VOCABULARY }
        val browseExpressions = { DeepLinkInbox.pending.value = DeepLinkInbox.Destination.EXPRESSIONS }
        val reviewSlips = { DeepLinkInbox.pending.value = DeepLinkInbox.Destination.REVIEW }

        if (dim != Dim.OVERALL) {
            // Each skill's own page: its measured number, the sentence saying
            // what was measured, the trend over its CEFR bands, and the way
            // to improve it — which always leaves this tab, because Progress
            // measures and the doing lives in Talk and Practice.
            ProgressSkillPage(dim, metrics,
                onSeeWords = seeWords,
                onReviewSlips = reviewSlips,
                onStartTalk = onStartTalk,
                onBrowseExpressions = browseExpressions)
            return@Column
        }

        // A level shows ONLY once a pooled read exists. No early guess from a
        // single talk: if the sample is not big enough yet, the honest
        // display is the recipe plus how far along the unlock is.
        val level = levelReport?.cefrLevel?.let { raw ->
            CefrLevel.entries.firstOrNull { it.code.equals(raw, true) }
        }
        val assessedAt = levelReport?.generatedAt
        val stale = assessedAt != null &&
            System.currentTimeMillis() - assessedAt > LEVEL_STALE_DAYS * 86_400_000L
        val secondary = MaterialTheme.colorScheme.onSurfaceVariant
        val tertiary = MaterialTheme.colorScheme.outline

        ProgressPanel {
            Text(stringResource(R.string.estimated_level),
                style = PT.caption.copy(fontWeight = FontWeight.SemiBold), color = secondary)
            if (level != null) {
                val code = level.code.uppercase()
                // A level assessed 4+ weeks ago dims instead of posing as
                // today's truth.
                Text(code,
                    style = com.roro.futurevoice.ui.brand.DisplayFace.style(code, PT.pixel(52)),
                    color = if (stale) secondary else MaterialTheme.colorScheme.primary)
                // Korean learners orient by TOPIK, Japanese by JLPT — the
                // official equivalence under the big number.
                LanguageCatalog.levelLabel(level, language).takeIf { it != code }?.let {
                    Text(it, style = PT.subheadline.copy(fontWeight = FontWeight.Medium),
                        color = secondary)
                }
                // What the level MEANS, before where it came from: a bare
                // letter is a grade, and this is a measurement.
                Text(canDoAt(code), style = PT.callout)
                assessedAt?.let { at ->
                    Text(
                        if (stale) stringResource(
                            R.string.assessed_a_while_back_your_next_talks_feed_a_fresh_assessmen_2febb6,
                            Recency.label(at))
                        else stringResource(
                            R.string.assessed_from_your_recent_talk_vocabulary_grammar_fluency_an_688dda,
                            Recency.label(at)),
                        style = PT.caption, color = secondary)
                }
                PanelDivider()
                NextAssessmentStatus(unlock, generating)
            } else {
                // The recipe made visible, equalizer-style: one bar per
                // measured ingredient, lit LED blocks = that axis's CEFR
                // band. A weak axis is a visibly shorter column.
                fun lit(l: CefrLevel?) = l?.let { CoreVocabulary.levelRank(it) + 1 } ?: 0
                fun label(l: CefrLevel?, approx: Boolean) =
                    l?.let { (if (approx) "≈" else "") + it.code.uppercase() } ?: "—"
                LevelEqualizer.View(listOf(
                    LevelEqualizer.Bar(stringResource(R.string.axis_vocab),
                        label(metrics.vocabLevel, false), lit(metrics.vocabLevel), Color(0xFF007AFF)),
                    LevelEqualizer.Bar(stringResource(R.string.fluency),
                        label(metrics.fluencyLevel, true), lit(metrics.fluencyLevel), Color(0xFF34C759)),
                    LevelEqualizer.Bar(stringResource(R.string.grammar),
                        label(metrics.grammarLevel, true), lit(metrics.grammarLevel), Color(0xFFFF9500)),
                    LevelEqualizer.Bar(stringResource(R.string.axis_express),
                        label(metrics.expressionLevel, true), lit(metrics.expressionLevel), Color(0xFFAF52DE)),
                ), Modifier.padding(top = 8.dp))
                Text(stringResource(R.string.vocabulary_is_graded_from_the_words_you_actually_use_levels_a3dc6c),
                    style = PT.caption2, color = tertiary)
                PanelDivider()
                BuildingStatus(unlock, generating)
            }
            // iOS: a small tinted Label, not a button — the measurement is the
            // panel's subject and this is a footnote-sized way into the recipe.
            TintLink(stringResource(R.string.how_this_is_assessed), Icons.Outlined.Info,
                modifier = Modifier.padding(top = 2.dp)) { showHowAssessed = true }
        }
        if (showHowAssessed) {
            HowAssessedSheet(
                level = level,
                rationale = levelReport?.levelRationale,
                firstReportMinutes = (WeeklyReportEngine.FIRST_REPORT_MIN_SECONDS / 60).toInt(),
                m = metrics,
                onDismiss = { showHowAssessed = false })
        }

        // THE growth graph: the level, one point per assessment. Present from
        // the first assessment on — with one point it says the curve starts
        // at the second, instead of hiding entirely.
        if (metrics.levelHistory.isNotEmpty()) {
            ProgressPanel {
                Text(stringResource(R.string.growth), style = PT.headline)
                if (metrics.levelHistory.size >= 2) {
                    LevelHistoryChart(metrics.levelHistory)
                    Text(stringResource(
                        R.string.your_level_one_point_per_assessment_this_line_is_what_growin_5b1e84),
                        style = PT.caption, color = secondary)
                } else {
                    Text(stringResource(
                        R.string.your_growth_curve_starts_at_your_second_assessment_every_ass_e7099b),
                        style = PT.callout, color = secondary)
                }
            }
        }

        // ONE unit on the level page: the CEFR band per skill, tappable for
        // the measured numbers behind it. Each row reads its OWN axis's band
        // — the raw figures (WPM, slips/100, words per turn) live on the
        // skill's own page, never beside a CEFR letter as a second scale.
        if (metrics.scoredCount > 0 || metrics.vocabLevel != null) {
            ProgressPanel {
                Text(stringResource(R.string.across_skills), style = PT.headline)
                SkillRow(stringResource(R.string.vocabulary),
                    metrics.vocabLevel?.code?.uppercase()) { dim = Dim.VOCABULARY }
                SkillRow(stringResource(R.string.fluency),
                    metrics.fluencyLevel?.let { "≈" + it.code.uppercase() }) { dim = Dim.FLUENCY }
                SkillRow(stringResource(R.string.grammar),
                    metrics.grammarLevel?.let { "≈" + it.code.uppercase() }) { dim = Dim.GRAMMAR }
                SkillRow(stringResource(R.string.expressiveness),
                    metrics.expressionLevel?.let { "≈" + it.code.uppercase() }) {
                    dim = Dim.EXPRESSIVENESS
                }
                Text(stringResource(R.string.same_bands_as_how_this_is_assessed_tap_a_skill_for_its_measu_19d33d),
                    style = PT.caption2, color = tertiary)
            }
        }

        // What to do next, from the SAME per-axis measurements the sheet
        // shows: only an axis measuring BELOW the target level appears, each
        // anchored to its live number. An unmeasured axis stays silent.
        level?.let { ProgressBands.next(it) }?.let { next ->
            ProgressPanel {
                Text(stringResource(R.string.to_reach, next.code.uppercase()), style = PT.headline)
                Text(canDoAt(next.code.uppercase()), style = PT.subheadline, color = secondary)
                FocusTips(metrics, next, seeWords, reviewSlips, onStartTalk)
            }
        }

        // What the last two weeks actually were. Both strips are drawn only
        // when there is something in them: an empty chart is a reproach, and
        // a new learner has done nothing wrong.
        if (minutesByDay.any { it.second > 0 }) {
            ProgressPanel {
                PanelHeader(stringResource(R.string.time_speaking)) {
                    Text(stringResource(R.string.lld_min_this_week,
                        minutesByDay.takeLast(7).sumOf { it.second } / 60),
                        style = PT.caption.copy(fontWeight = FontWeight.SemiBold), color = secondary)
                }
                EffortCharts.Bars(
                    days = minutesByDay.map { (at, secs) ->
                        EffortCharts.DayBar(dayLabel(at),
                            listOf(MaterialTheme.colorScheme.primary to secs / 60f))
                    },
                    goal = goalMinutes.toFloat(),
                )
                Text(stringResource(
                    R.string.minutes_you_actually_spoke_per_day_the_dashed_line_is_your_l_b779b3,
                    goalMinutes),
                    style = PT.caption, color = secondary)
            }
        }

        // Never drawn while zero: a headline "0" on the one number that
        // proves the loop closed reads as a verdict on the learner.
        if (carryoverTotal > 0) {
            BigStat(
                title = stringResource(R.string.studied_then_said),
                value = carryoverTotal,
                caption = stringResource(
                    if (carryoverTotal == 1)
                        R.string.thing_you_studied_has_come_out_of_your_mouth_in_a_real_conve_f4b959
                    else R.string.things_you_studied_have_come_out_of_your_mouth_in_a_real_con_3a0c5c),
                trailing = carryoverWeek.takeIf { it > 0 }
                    ?.let { stringResource(R.string.plus_lld_this_week, it) },
            )
        }

        if (material.second > 0) {
            BigStat(
                title = stringResource(R.string.your_material),
                value = material.first,
                caption = stringResource(
                    if (material.first == 1)
                        R.string.word_or_line_mastered_out_of_lld_your_talks_and_watches_have_8aaf23
                    else R.string.words_and_lines_mastered_out_of_lld_your_talks_and_watches_h_4f4924,
                    material.second),
                progress = material.first / material.second.toFloat(),
            )
        }

        if (effortByDay.any { it.second.total > 0 }) {
            val shadow = Color(0xFF34C759)
            val sentences = Color(0xFFFF9500)
            val notebook = Color(0xFF007AFF)
            ProgressPanel {
                Text(stringResource(R.string.activity), style = PT.headline)
                // Stacked by KIND, not just totals — a strip that is always one
                // colour is the "I only ever do the comfortable thing" signal,
                // and that is the whole reason to draw it by kind.
                EffortCharts.Bars(
                    days = effortByDay.map { (key, d) ->
                        EffortCharts.DayBar(key.takeLast(2), listOf(
                            shadow to d.shadowReps.toFloat(),
                            sentences to d.drillReps.toFloat(),
                            notebook to (d.wordReps + d.expressionReps).toFloat(),
                        ))
                    },
                    height = 130.dp,
                )
                EffortCharts.Legend(listOf(
                    stringResource(R.string.shadowing) to shadow,
                    stringResource(R.string.sentences) to sentences,
                    stringResource(R.string.notebook) to notebook,
                ))
                PanelDivider()
                // Reps stay what they have always meant here — REVIEW work.
                // Talk time is counted in minutes, in its own strip above.
                val week = effortByDay.takeLast(7)
                val reps = week.sumOf { it.second.total }
                val daysActive = week.count { it.second.total > 0 }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Stat(stringResource(R.string.reps_this_week), "$reps", Modifier.weight(1f))
                    Stat(stringResource(R.string.days_active), "$daysActive", Modifier.weight(1f))
                    if (avgShadowScore > 0) {
                        Stat(stringResource(R.string.avg_shadow_score), "$avgShadowScore",
                            Modifier.weight(1f))
                    }
                }
            }
        }

        // The ONLY way into the activity calendar from this tab. A streak is
        // a claim about a history, so it has to open the record — otherwise
        // it is a number asking to be trusted.
        ProgressPanel(onClick = onOpenActivity) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Filled.LocalFireDepartment, contentDescription = null,
                    tint = if (streak > 0) Color(0xFFFF9500) else secondary,
                    modifier = Modifier.width(24.dp).size(22.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        if (streak == 0) stringResource(R.string.no_streak_yet)
                        else stringResource(R.string.lld_day_streak, streak),
                        style = PT.subheadline.copy(fontWeight = FontWeight.Medium))
                    Text(stringResource(R.string.lld_talks_tap_for_calendar,
                        talks.count { it.endedAt != null }),
                        style = PT.caption, color = secondary)
                }
                Chevron()
            }
        }

        AssessmentPanel(
            report = report,
            onOpen = onOpenAssessment,
            unlock = unlock,
            working = generating,
            onGenerate = {
                generating = true
                scope.launch {
                    runCatching {
                        WeeklyReportEngine.generate(context, talks.filter { it.endedAt != null && !it.isPractice },
                            report, language, nativeLanguage)
                    }.getOrNull()?.let {
                        WeeklyReportStore.shared(context).save(it, language)
                        report = it
                        if (it.cefrLevel != null) levelReport = it
                        // The MEASURED level replaces the self-reported
                        // setting — from here scoring calibration, pickup-word
                        // difficulty and the talk-card label all track
                        // measurement rather than what someone guessed about
                        // themselves in onboarding. A manual change in Me
                        // still wins until the next assessment.
                        it.cefrLevel?.let { measured -> onMeasuredLevel(measured) }
                        unlock = WeeklyReportEngine.unlockState(
                            talks.filter { s -> s.endedAt != null && !s.isPractice }, it)
                        val fresh = WeeklyReportStore.shared(context).load(language)
                        val bands = VocabStore.shared(context).usedWordsByLevel(language)
                        val seen = talks
                        val expressions = metrics.expressionCount
                        metrics = withContext(Dispatchers.Default) {
                            ProgressMath.compute(seen, fresh, bands, expressions)
                        }
                    }
                    generating = false
                }
            },
        )
    }
}

/** A level assessed longer ago than this reads as stale — dimmed, with a
 *  "talk again and it refreshes" line, rather than posing as today's truth. */
private const val LEVEL_STALE_DAYS = 28L

/** The page gutter the host column puts around every tab (RootScreen). */
private val PAGE_GUTTER = 20.dp

/**
 * Widen a child past its parent's horizontal padding by [bleed] on each side,
 * so a horizontally scrolling row reaches the screen edges. The row's content
 * padding puts the gutter back inside the scroll.
 */
private fun Modifier.fullBleed(bleed: androidx.compose.ui.unit.Dp): Modifier =
    this.layout { measurable, constraints ->
        val extra = bleed.roundToPx() * 2
        val placeable = measurable.measure(constraints.copy(
            minWidth = (constraints.minWidth + extra),
            maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + extra
            else constraints.maxWidth))
        val width = if (constraints.hasBoundedWidth) constraints.maxWidth else placeable.width
        layout(width, placeable.height) { placeable.place(-extra / 2, 0) }
    }

/**
 * iOS's text styles by their iOS names, for this tab and its skill pages —
 * the Material slots only carry some of them (callout, caption2 and a 12 pt
 * caption have no slot), and matching the iOS page element by element needs
 * all of them. Sizes are iOS's default Dynamic Type sizes, in sp.
 */
internal object PT {
    private fun s(size: Int, leading: Int, weight: FontWeight = FontWeight.Normal) = TextStyle(
        fontSize = size.sp, lineHeight = leading.sp, fontWeight = weight, letterSpacing = 0.sp)

    val caption2 = s(11, 13)
    val caption = s(12, 16)
    val footnote = s(13, 18)
    val subheadline = s(15, 20)
    val callout = s(16, 21)
    val body = s(17, 22)
    val headline = s(17, 22, FontWeight.SemiBold)
    val title3 = s(20, 25)

    /** `.geistPixel(n)` — the display face at a fixed size, tight leading. */
    fun pixel(size: Int) = TextStyle(fontSize = size.sp, lineHeight = (size * 1.1f).sp,
        letterSpacing = 0.sp)
}

/** iOS `CardDivider(inset: 0)` inside a panel. */
@Composable
internal fun PanelDivider() {
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, thickness = 0.5.dp)
}

/** A headline with a trailing accessory on its first baseline (iOS
 *  `HStack(alignment: .firstTextBaseline) { title; Spacer(); … }`). */
@Composable
internal fun PanelHeader(title: String, trailing: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = PT.headline, modifier = Modifier.weight(1f))
        trailing()
    }
}

/** iOS's list chevron: small, tertiary. */
@Composable
internal fun Chevron() {
    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
        tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
}

/**
 * iOS `Label(title, systemImage:)` in `.footnote.weight(.medium)`, tinted, as a
 * plain button — a small blue line of text with its icon, not a Material
 * TextButton (which pads it out to 48 dp and sets it in the button face).
 */
@Composable
internal fun TintLink(
    text: String,
    icon: ImageVector?,
    modifier: Modifier = Modifier,
    style: TextStyle = PT.footnote.copy(fontWeight = FontWeight.Medium),
    onClick: () -> Unit,
) {
    val tint = MaterialTheme.colorScheme.primary
    Row(
        modifier.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        icon?.let { Icon(it, contentDescription = null, tint = tint,
            modifier = Modifier.size(with(LocalDensity.current) { (style.fontSize * 1.1f).toDp() })) }
        Text(text, style = style, color = tint)
    }
}

/**
 * iOS `ProgressView(value:total:)`, linear: a 4 pt capsule, the fill in the
 * accent colour over the system fill grey — no gap, no stop dot (Material 3's
 * LinearProgressIndicator draws both).
 */
@Composable
internal fun IosProgressBar(
    fraction: Float,
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
) {
    val track = if (MaterialTheme.colorScheme.background.luminance() < 0.5f)
        Color(0xFF787880).copy(alpha = 0.36f) else Color(0xFF787880).copy(alpha = 0.2f)
    Box(modifier.height(4.dp).clip(CircleShape).background(track)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(fraction.coerceIn(0f, 1f))
            .clip(CircleShape).background(color))
    }
}

/**
 * When and how the level actually gets assessed — the weekly read's REAL
 * unlock rules, never a vague progress bar. Shown INSTEAD of a level, while
 * there isn't one.
 */
@Composable
private fun BuildingStatus(unlock: WeeklyReportEngine.Unlock?, working: Boolean) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    if (working) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Text(stringResource(R.string.assessing_your_level_from_everything_you_ve_said),
                style = PT.callout, color = secondary)
        }
        return
    }
    when (unlock) {
        is WeeklyReportEngine.Unlock.First -> {
            Text(stringResource(
                R.string.your_level_is_graded_at_your_first_assessment_one_pooled_jud_873e14),
                style = PT.callout, color = secondary)
            UnlockBar(unlock.accumulated, unlock.required)
        }
        is WeeklyReportEngine.Unlock.Next -> {
            Text(stringResource(
                R.string.your_level_is_re_assessed_regularly_the_next_assessment_need_a344c5),
                style = PT.callout, color = secondary)
            UnlockConditionRow(Icons.Outlined.CalendarToday, unlock.daysRemaining == 0,
                daysRemainingText(unlock.daysRemaining))
            UnlockConditionRow(Icons.Filled.Mic, unlock.secondsRemaining == 0.0,
                newTalkRemainingText(unlock.secondsRemaining))
        }
        WeeklyReportEngine.Unlock.Ready -> Text(
            stringResource(R.string.ready_assessing_your_level_now),
            style = PT.callout, color = secondary)
        null -> Unit
    }
}

/**
 * Shown UNDER an existing level: when the next re-assessment happens and
 * exactly how much more talk gets you there — the part the learner can go and
 * do right now.
 */
@Composable
private fun NextAssessmentStatus(unlock: WeeklyReportEngine.Unlock?, working: Boolean) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    if (working) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Text(stringResource(R.string.re_assessing_your_level_now),
                style = PT.callout, color = secondary)
        }
        return
    }
    when (unlock) {
        is WeeklyReportEngine.Unlock.Next -> {
            Text(stringResource(R.string.next_assessment),
                style = PT.caption.copy(fontWeight = FontWeight.SemiBold), color = secondary)
            val required = WeeklyReportEngine.RECURRING_MIN_SECONDS
            val done = (required - unlock.secondsRemaining).coerceIn(0.0, required)
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                IosProgressBar((done / required).toFloat(), Modifier.weight(1f))
                Text(stringResource(R.string.lld_lld_min_new_talk,
                    (done / 60).toInt(), (required / 60).toInt()),
                    style = PT.caption, color = secondary)
            }
            UnlockConditionRow(Icons.Outlined.CalendarToday, unlock.daysRemaining == 0,
                daysRemainingText(unlock.daysRemaining))
            if (unlock.secondsRemaining > 0) {
                Text(stringResource(
                    R.string.talk_lld_more_minutes_and_this_level_gets_re_read_from_every_b72704,
                    minutesUp(unlock.secondsRemaining)),
                    style = PT.caption, color = secondary)
            }
        }
        WeeklyReportEngine.Unlock.Ready -> Text(
            stringResource(R.string.ready_re_assessing_your_level_now),
            style = PT.callout, color = secondary)
        // Can't happen once a level exists; nothing to show.
        else -> Unit
    }
}

@Composable
private fun UnlockBar(accumulated: Double, required: Double) {
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        IosProgressBar((accumulated / required).toFloat(), Modifier.weight(1f))
        Text(stringResource(R.string.lld_lld_min_7abd2a,
            (accumulated / 60).toInt(), (required / 60).toInt()),
            style = PT.caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** iOS `unlockConditionRow`: the condition's own glyph in a 22 pt column
 *  (a check once it's met), the text at subheadline. */
@Composable
private fun UnlockConditionRow(icon: ImageVector, met: Boolean, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) {
            Icon(if (met) Icons.Filled.CheckCircle else icon,
                contentDescription = null,
                tint = if (met) Color(0xFF34C759) else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(16.dp))
        }
        Text(text, style = PT.subheadline,
            color = if (met) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun daysRemainingText(days: Int): String = when {
    days == 0 -> stringResource(R.string.a_week_since_the_last_assessment)
    days == 1 -> stringResource(R.string.one_more_day)
    else -> stringResource(R.string.lld_more_days, days)
}

@Composable
private fun newTalkRemainingText(secondsRemaining: Double): String =
    if (secondsRemaining <= 0.0) stringResource(R.string.enough_new_conversation)
    else stringResource(R.string.lld_more_min_of_new_talk, minutesUp(secondsRemaining))

/** Minutes, rounded UP and never zero — "0 more min" is not a condition. */
private fun minutesUp(seconds: Double): Int =
    kotlin.math.ceil(seconds / 60.0).toInt().coerceAtLeast(1)

/**
 * The lagging axes, each with its live number and the one place that axis is
 * actually worked on. Capped at three so it reads as focus, not a checklist;
 * two axes that want the same door keep their line and drop the duplicate
 * button rather than showing it twice.
 */
@Composable
private fun FocusTips(
    m: ProgressMetrics,
    next: CefrLevel,
    onSeeWords: () -> Unit,
    onReviewSlips: () -> Unit,
    onStartTalk: (() -> Unit)?,
) {
    class Tip(val icon: ImageVector, val text: String, val action: ProgressAction?)
    val targetRank = CoreVocabulary.levelRank(next)
    fun lags(l: CefrLevel?) = l != null && CoreVocabulary.levelRank(l) < targetRank
    val talk = onStartTalk?.let {
        ProgressAction(stringResource(R.string.start_a_talk), it, Icons.Filled.GraphicEq)
    }
    val tips = mutableListOf<Tip>()
    if (lags(m.vocabLevel)) {
        tips += Tip(Icons.AutoMirrored.Outlined.MenuBook,
            stringResource(R.string.use_more_level_words_in_your_talks, next.code.uppercase()),
            ProgressAction(stringResource(R.string.see_words, next.code.uppercase()), onSeeWords,
                Icons.AutoMirrored.Outlined.MenuBook))
    }
    if (lags(m.grammarLevel)) {
        val hint = m.grammarNextThreshold?.let { t ->
            m.grammarLevel?.let { ProgressBands.next(it) }?.let { up ->
                stringResource(R.string.get_under_1f_and_this_reads, t, up.code.uppercase())
            }
        }.orEmpty()
        tips += Tip(Icons.Outlined.Verified,
            stringResource(R.string.you_re_at_1f_verified_slips_per_100_words,
                m.slipsPer100Words, hint),
            ProgressAction(stringResource(R.string.review_your_slips), onReviewSlips,
                Icons.Outlined.Verified))
    }
    if (lags(m.fluencyLevel)) {
        tips += Tip(Icons.Outlined.Speed,
            stringResource(R.string.your_pace_is_lld_words_min_talk_more_often_and_a_little_long_608384,
                m.effectivePace), talk)
    }
    if (lags(m.expressionLevel)) {
        tips += Tip(Icons.AutoMirrored.Outlined.Chat,
            stringResource(R.string.your_turns_average_lld_words_add_detail_how_things_felt_not_b4c918,
                m.wordsPerTurn), talk)
    }
    if (tips.isEmpty()) {
        tips += Tip(Icons.Outlined.CheckCircle,
            stringResource(R.string.every_measured_skill_already_reads_at_or_above_keep_talking_24170a,
                next.code.uppercase()), null)
    }
    val offered = mutableSetOf<String>()
    tips.take(3).forEach { tip ->
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.width(22.dp).padding(top = 2.dp), contentAlignment = Alignment.TopCenter) {
                Icon(tip.icon, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(17.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(tip.text, style = PT.callout)
                val action = tip.action
                if (action != null && offered.add(action.title)) ProgressActionLink(action)
            }
        }
    }
}

/** iOS `activityStat`: the figure in headline-bold, its label in caption2. */
@Composable
private fun Stat(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(value, style = PT.headline.copy(fontWeight = FontWeight.Bold))
        Text(label, style = PT.caption2, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * The latest assessment, readable at a glance (iOS `weeklyReadPanel`).
 *
 * Locked, it shows what it is WAITING for and how far along that is — the
 * same number the gate opens on, so the bar can't fill at a different rate
 * than the door opens. Unlocked, it offers the button; generated, it shows
 * the digest and the way into the full report.
 *
 * The full item lists live on the report's own page: a wall of text at the
 * bottom of Progress was getting skipped, not read.
 */
@Composable
private fun AssessmentPanel(
    report: WeeklyReport?,
    onOpen: () -> Unit,
    unlock: WeeklyReportEngine.Unlock?,
    working: Boolean,
    onGenerate: () -> Unit,
) {
    if (unlock == null) return
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    ProgressPanel {
        PanelHeader(stringResource(R.string.latest_assessment)) {
            if (working) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            else report?.let {
                Text(readDateRange(it), style = PT.caption, color = secondary)
            }
        }

        val summary = report?.summary?.takeIf { it.isNotBlank() }
        if (report != null && summary != null) {
            Text(summary, style = PT.callout)
            DigestRow(Icons.Filled.AutoAwesome, report.newExpressions.size,
                stringResource(R.string.new_expressions))
            DigestRow(Icons.Filled.Autorenew, report.repeatedMistakes.size,
                stringResource(R.string.to_drill))
            DigestRow(Icons.Outlined.AddComment, report.suggestedExpressions.size,
                stringResource(R.string.to_try))
            Row(Modifier.fillMaxWidth().padding(top = 2.dp)
                .clickable(interactionSource = remember { MutableInteractionSource() },
                    indication = null, onClick = onOpen),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.read_the_full_report),
                    style = PT.subheadline.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(1f))
                Chevron()
            }
        }

        when (unlock) {
            is WeeklyReportEngine.Unlock.First -> {
                Text(stringResource(R.string.your_first_assessment_unlocks_after_lld_minutes_of_talk,
                    (unlock.required / 60).toInt()),
                    style = PT.subheadline, color = secondary)
                UnlockBar(unlock.accumulated, unlock.required)
            }
            is WeeklyReportEngine.Unlock.Next -> if (report == null || summary == null) {
                Text(
                    if (unlock.daysRemaining > 0)
                        stringResource(R.string.next_read_in_lld_days, unlock.daysRemaining)
                    else stringResource(R.string.lld_more_min_of_talking,
                        (unlock.secondsRemaining / 60).toInt() + 1),
                    style = PT.subheadline, color = secondary)
            }
            WeeklyReportEngine.Unlock.Ready -> {
                Button(onClick = onGenerate, enabled = !working,
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) {
                    if (working) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        Text(stringResource(
                            if (report == null) R.string.read_my_level
                            else R.string.new_assessment))
                    }
                }
            }
        }
    }
}

/** "Sep 23 – Sep 30": the window the read covers, in the phone's locale. */
private fun readDateRange(r: WeeklyReport): String {
    val fmt = java.text.SimpleDateFormat(
        android.text.format.DateFormat.getBestDateTimePattern(java.util.Locale.getDefault(), "MMMd"),
        java.util.Locale.getDefault())
    return "${fmt.format(java.util.Date(r.periodStart))} – ${fmt.format(java.util.Date(r.periodEnd))}"
}

/** iOS `digestRow`: tinted glyph, the count in semibold, its noun secondary.
 *  A zero count draws nothing. */
@Composable
private fun DigestRow(icon: ImageVector, count: Int, text: String) {
    if (count <= 0) return
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(17.dp))
        }
        Text("$count", style = PT.subheadline.copy(fontWeight = FontWeight.SemiBold))
        Text(text, style = PT.subheadline, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * One skill's line on the level page: what it is, and the band it measures
 * at. Tappable, because the numbers behind it are on its own page.
 *
 * It is handed the band its OWN axis measured — vocabulary is graded from
 * the word list, the other three from their own deterministic proxies. A row
 * that ran every axis's 0-100 score through the grammar table said something
 * different about the same skill than the equalizer directly above it.
 */
@Composable
private fun SkillRow(title: String, band: String?, onOpen: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .clickable(interactionSource = remember { MutableInteractionSource() },
                indication = null, onClick = onOpen)
            .padding(vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title, style = PT.subheadline, modifier = Modifier.weight(1f))
        // The band, not the 0-100 score: the number is calibrated to the
        // learner's own level setting, so beside a CEFR letter it reads as a
        // second, contradicting scale. The score lives on the skill's page.
        Text(band ?: "—", style = PT.subheadline.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Chevron()
    }
}

/**
 * One big measured number with the sentence that says what it counts.
 *
 * The figure carries the weight and the sentence does the explaining — a
 * label above a number makes the reader assemble the fact from two places.
 */
@Composable
private fun BigStat(
    title: String,
    value: Int,
    caption: String,
    trailing: String? = null,
    progress: Float? = null,
) {
    ProgressPanel {
        PanelHeader(title) {
            trailing?.let {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.NorthEast, contentDescription = null,
                        tint = Color(0xFF34C759), modifier = Modifier.size(13.dp))
                    Text(it, style = PT.caption.copy(fontWeight = FontWeight.SemiBold),
                        color = Color(0xFF34C759))
                }
            }
        }
        // First-baseline aligned, as iOS: the caption's FIRST line sits on
        // the figure's baseline and any further lines run below it.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("$value", style = TextStyle(fontSize = 44.sp, lineHeight = 48.sp,
                fontWeight = FontWeight.Bold, letterSpacing = 0.sp),
                modifier = Modifier.alignByBaseline())
            Text(caption, style = PT.callout,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.alignByBaseline())
        }
        progress?.let {
            IosProgressBar(it, Modifier.fillMaxWidth(),
                color = if (it >= 1f) Color(0xFF34C759) else MaterialTheme.colorScheme.primary)
        }
    }
}

/** What a level can actually DO, in one line (iOS `canDo`). */
@Composable
private fun canDoAt(level: String): String = stringResource(
    when (level.uppercase()) {
        "A1" -> R.string.simple_words_and_phrases_about_immediate_familiar_things
        "A2" -> R.string.everyday_topics_in_simple_terms_routines_plans_basic_needs
        "B1" -> R.string.familiar_topics_fluently_enough_to_get_by_and_tell_a_simple_fa6cea
        "B2" -> R.string.clear_detailed_talk_on_many_topics_including_some_abstract_o_933630
        "C1" -> R.string.fluent_flexible_and_precise_even_on_complex_topics
        else -> R.string.effortless_and_nuanced_close_to_native
    })

