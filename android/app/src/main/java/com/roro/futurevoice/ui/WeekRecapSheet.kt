package com.roro.futurevoice.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircleOutline
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Spellcheck
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.ViewAgenda
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import com.roro.futurevoice.ui.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.UILanguage
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DeepLinkInbox
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.WeekInProgress
import com.roro.futurevoice.data.WeekRecap
import com.roro.futurevoice.data.WeekRecapBuilder
import com.roro.futurevoice.data.WeekRecapInbox
import com.roro.futurevoice.data.WeekRecapStore
import com.roro.futurevoice.data.WeeklyTestInbox
import com.roro.futurevoice.data.WeeklyTestSchedule
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.data.WeeklyTestStore
import com.roro.futurevoice.data.WeeklyTest
import com.roro.futurevoice.data.WeeklyTestEngine
import com.roro.futurevoice.data.TrialReport
import com.roro.futurevoice.data.TrialReportStore
import com.roro.futurevoice.data.assessTrialLevel
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LearningPurposeStore
import com.roro.futurevoice.data.RoutineRecipe
import com.roro.futurevoice.data.RoutineText
import com.roro.futurevoice.data.StudyPlanStore
import com.roro.futurevoice.net.WeekRecapCoach
import com.roro.futurevoice.net.ReportNarration
import com.roro.futurevoice.net.ReportNarrationPlayer
import com.roro.futurevoice.net.ReportNarrator
import com.roro.futurevoice.data.HabitAdvice
import com.roro.futurevoice.data.HabitAdvisor
import com.roro.futurevoice.data.HabitFinding
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.StudyHabits
import com.roro.futurevoice.data.StudyPlan
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.animateFloat
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.ArrowCircleRight
import androidx.compose.material.icons.filled.Error
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.automirrored.filled.EventNote
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.data.FeatureUse
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.RowScope
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.SmartDisplay
import com.roro.futurevoice.ui.FeedbackContext
import com.roro.futurevoice.ui.FeedbackPrompt
import com.roro.futurevoice.ui.brand.ContinuousShape
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

/**
 * "Your week" — the closed week as a deck of cards, swiped through like
 * stories, ending on the week's test (iOS `WeekRecapSheet`, `633418f`).
 *
 * Cards: the week at a glance → talk → what you studied and then SAID →
 * review work → new phrases from the fluent self → what tripped you up →
 * grammar → words → the coach → the test. A card with nothing to say is not
 * dealt, so a quiet week is a short deck, never a row of zeros.
 *
 * The same deck is the TRIAL REPORT ([TrialReportSheet], see [TrialReport]):
 * the free minutes instead of a week, then the test (required — the level and
 * routine cards are dealt only once it is done), the level, and the routine,
 * whose button opens the plans.
 */
enum class WeekRecapAction { TEST, TALK }

private enum class RecapCard(
    /** iOS `WeekRecapSheet.Card`'s case name — the narration's card key,
     *  which its prompt carries. */
    val iosName: String,
) {
    COVER("cover"), TALK("talk"), USED("used"), REVIEW("review"), FRESH("fresh"), STUMBLES("stumbles"),
    GRAMMAR("grammar"), WORDS("words"), COACH("coach"), TEST("test"),
    TRIAL_TEST("trialTest"), LEVEL("level"), ROUTINE("routine"),
}

private val Green = Color(0xFF34C759)
private val Orange = Color(0xFFFF9500)

/** Where the deck's last-card choice goes: the test (Practice opens it) or a
 *  free talk through the same gate the Talk ring uses. */
fun performWeekRecapAction(action: WeekRecapAction) {
    when (action) {
        WeekRecapAction.TEST -> {
            WeeklyTestInbox.pending.value = true
            DeepLinkInbox.pending.value = DeepLinkInbox.Destination.PRACTICE
        }
        WeekRecapAction.TALK -> DeepLinkInbox.requestFreeTalk(com.roro.futurevoice.talk.TalkEntry.WEEK_RECAP)
    }
}

private fun nativeLanguage(c: Context): String =
    c.getSharedPreferences("futurevoice", 0).getString("futurevoice.nativeLanguage", null)
        ?: Locale.getDefault().language

/** The deck as a sheet. The chosen action runs once the sheet is gone, so
 *  nothing opens underneath a closing sheet. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeekRecapSheet(recap: WeekRecap, level: CefrLevel, onDismiss: (WeekRecapAction?) -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    ModalBottomSheet(onDismissRequest = { onDismiss(null) }, sheetState = sheet,
        containerColor = AppSurfaces.ground) {
        Box(Modifier.fillMaxHeight(0.94f)) {
            WeekRecapDeck(recap = recap, level = level) { action ->
                scope.launch { sheet.hide() }.invokeOnCompletion { onDismiss(action) }
            }
        }
    }
}

/** The free minutes' report as a sheet (iOS `WeekRecapSheet(trial:)`).
 *  [onMeasuredLevel] sets the level quietly — no level-up sheet; the
 *  report's own card is the announcement. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrialReportSheet(report: TrialReport, level: CefrLevel, onMeasuredLevel: (String) -> Unit,
                     voiceId: String? = null, onDismiss: () -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet,
        containerColor = AppSurfaces.ground) {
        Box(Modifier.fillMaxHeight(0.94f)) {
            WeekRecapDeck(recap = report.recap, level = level, trial = report,
                onMeasuredLevel = onMeasuredLevel, voiceId = voiceId) {
                scope.launch { sheet.hide() }.invokeOnCompletion { onDismiss() }
            }
        }
    }
}

@Composable
fun WeekRecapDeck(
    recap: WeekRecap,
    level: CefrLevel,
    startPage: Int = 0,
    /** Don't call the coach (the capture run's recap is pre-written). */
    writeCoach: Boolean = true,
    /** Set: the deck is the trial report ([TrialReport]). */
    trial: TrialReport? = null,
    onMeasuredLevel: (String) -> Unit = {},
    /** The fluent self's voice (iOS `speakingVoiceId`), for the narration. */
    voiceId: String? = null,
    onClose: (WeekRecapAction?) -> Unit,
) {
    val context = LocalContext.current
    var current by remember(recap.end) { mutableStateOf(recap) }
    var coachFailed by remember { mutableStateOf(false) }
    var coachAttempt by remember { mutableStateOf(0) }
    var testState by remember { mutableStateOf<WeeklyTestSchedule.State>(WeeklyTestSchedule.State.Ready) }
    val language = remember { LanguageScope.active(context) }

    // Trial report only.
    val isTrial = trial != null
    var trialState by remember { mutableStateOf(trial) }
    var trialTest by remember { mutableStateOf<WeeklyTest?>(null) }
    var showingTrialTest by remember { mutableStateOf(false) }
    var trialLevel by remember { mutableStateOf(trial?.level?.let { raw ->
        CefrLevel.entries.firstOrNull { it.code.equals(raw, ignoreCase = true) } }) }
    var trialRationale by remember { mutableStateOf(trial?.levelRationale) }
    var levelSettled by remember { mutableStateOf(trial?.level != null) }
    var routine by remember { mutableStateOf<List<RoutineRecipe.Line>>(emptyList()) }
    var routineIsOwn by remember { mutableStateOf(false) }
    /** How they used the app ([StudyHabits]): what the rules found, the
     *  wording once it lands, and which routine block each finding touched
     *  (block id → rule). */
    var habitFindings by remember { mutableStateOf<List<HabitFinding>>(emptyList()) }
    var habitAdvice by remember { mutableStateOf<HabitAdvice?>(null) }
    var habitAdviceFailed by remember { mutableStateOf(false) }
    var routineRules by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var showingPaywall by remember { mutableStateOf(false) }
    var showingFeedback by remember { mutableStateOf(false) }
    /** The trial's second card: every feature, and how much of each was used. */
    var featureUses by remember { mutableStateOf<List<FeatureUse>>(emptyList()) }
    /** Foreground time in the app over the trial window. */
    var appSeconds by remember { mutableStateOf(0) }
    var learnerName by remember { mutableStateOf<String?>(null) }
    var jumpToLevel by remember { mutableStateOf(false) }
    /** The deck's start-up runs once per opening (iOS `trialStarted`): a
     *  second run would count a second offer and reset the thin flag under
     *  the learner. */
    var trialStarted by remember { mutableStateOf(false) }
    /** The trial's test is done, or could not be made — either way the level
     *  and the routine are the learner's to see. */
    val trialTestCleared = trialTest?.isFinished == true || trialState?.testThin == true

    // The narration ([ReportNarration]): the fluent self reads each card.
    val narrationScope = rememberCoroutineScope()
    val narrator = remember { ReportNarrationPlayer(context, narrationScope) }
    var narration by remember { mutableStateOf(ReportNarration()) }
    /** Cards a script has been asked for, so a half is written once. */
    val narrationAsked = remember { mutableSetOf<String>() }
    /** The deck's start-up has loaded what was kept; the script may be asked for. */
    var narrationReady by remember { mutableStateOf(false) }
    /** Whether the deck reads itself: the trial report, for now. */
    val narrates = isTrial

    val cards = buildList {
        val r = current
        add(RecapCard.COVER)
        if (r.talkSeconds > 0 || r.talks.isNotEmpty()) add(RecapCard.TALK)
        if (r.usedCount > 0) add(RecapCard.USED)
        if (r.nowYours.isNotEmpty() || r.sentencesGot.isNotEmpty() || r.shadowTakes + r.scenes > 0) add(RecapCard.REVIEW)
        if (r.newExpressionCount > 0 || r.newCards > 0) add(RecapCard.FRESH)
        if (r.stumbles.isNotEmpty() || r.shakyLines.isNotEmpty() || testMissed(r) > 0) add(RecapCard.STUMBLES)
        // The coach's cards are dealt whether or not its read has landed —
        // they show their own loading state — so the deck never reshuffles.
        if (r.hasActivity) { add(RecapCard.GRAMMAR); add(RecapCard.WORDS) }
        add(RecapCard.COACH)
        if (isTrial) {
            // The test is offered, never required (2026-10-22, founder).
            add(RecapCard.TRIAL_TEST); add(RecapCard.LEVEL); add(RecapCard.ROUTINE)
        } else {
            add(RecapCard.TEST)
        }
    }
    val cardsNow by androidx.compose.runtime.rememberUpdatedState(cards)
    val pager = rememberPagerState(initialPage = startPage.coerceIn(0, cards.size - 1)) { cards.size }
    val revealed = remember { mutableStateListOf(startPage) }
    LaunchedEffect(pager) {
        snapshotFlow { pager.currentPage }.collect { if (it !in revealed) revealed.add(it) }
    }

    val trialScope = rememberCoroutineScope()
    /** Re-read the report and its test: the test screen writes both. */
    /** [jump]: back from the test. A report whose test was done in an
     *  earlier sitting opens at the cover like any deck. */
    suspend fun reloadTrialTest(jump: Boolean) {
        val wasCleared = trialTest?.isFinished == true || trialState?.testThin == true
        val saved = TrialReportStore.load(context, trialState?.targetLanguage ?: language)
        if (saved != null) trialState = trialState?.copy(testThin = saved.testThin, testId = saved.testId)
        saved?.testId?.let { id ->
            WeeklyTestStore.shared(context).load(language).firstOrNull { it.id == id }?.let { trialTest = it }
        }
        // Done in this sitting: straight on to the level.
        val cleared = trialTest?.isFinished == true || trialState?.testThin == true
        if (jump && !wasCleared && cleared) jumpToLevel = true
    }
    /** Re-read before writing: the test screen saves its id into the same file. */
    fun updateTrial(change: (TrialReport) -> TrialReport) {
        val reportLanguage = trialState?.targetLanguage ?: return
        trialScope.launch {
            val latest = TrialReportStore.update(context, reportLanguage, change)
            if (latest != null) trialState = latest
            else trialState?.let { copy ->
                val next = change(copy)
                TrialReportStore.save(context, next)
                trialState = next
            }
        }
    }

    // MARK: Narration

    /** The script's key for a card — iOS's card name, which the prompt
     *  carries. The trial test's line changes once the test is done, so the
     *  done state is a key of its own. */
    fun narrationKey(card: RecapCard): String {
        if (card == RecapCard.TRIAL_TEST && trialTest?.isFinished == true) return "trialTestDone"
        return card.iosName
    }

    fun narrationContext(): ReportNarrator.Context {
        val res = context.resources
        val done = trialTest?.isFinished == true
        return ReportNarrator.Context(
            recap = current, isTrial = isTrial,
            level = trialLevel, levelRationale = trialRationale,
            testScore = if (done) trialTest?.score else null,
            testTotal = if (done) trialTest?.total else null,
            testThin = trialState?.testThin == true,
            routineHeadline = context.getString(RoutineRecipe.headline(LearningPurposeStore.purposes(context))),
            routine = routine.map { "${RoutineText.titled(res, it.block.kind, it.block.minutes)}, ${routineWeekdaySummary(res, it.block.weekdays)}" },
            habits = habitFindings,
            usage = if (isTrial) usageFacts(featureUses, appSeconds) else emptyList(),
        )
    }

    /** Speaks the card on screen. [onlyIfIdle]: a script that just arrived
     *  starts its card's line, but never cuts one already playing. */
    fun speakCurrentCard(onlyIfIdle: Boolean = false) {
        if (!narrates) return
        val at = pager.currentPage
        val card = cardsNow.getOrNull(at) ?: return
        if (onlyIfIdle && (narrator.speakingCard != null || narrator.loadingCard != null)) return
        val line = narration.line(narrationKey(card)) ?: run { narrator.stop(); return }
        narrator.speak(line) {
            // The deck moves on by itself, except past a card that asks the
            // learner something (the test, the routine).
            if (card in listOf(RecapCard.TRIAL_TEST, RecapCard.ROUTINE, RecapCard.TEST) ||
                at != pager.currentPage || at >= cardsNow.size - 1) return@speak
            narrationScope.launch {
                delay(900)
                if (at != pager.currentPage || showingTrialTest || showingPaywall) return@launch
                pager.animateScrollToPage(minOf(pager.currentPage + 1, cardsNow.size - 1))
            }
        }
    }

    /** Asks for the lines of every card whose content is known and that has
     *  none yet — the counts cards at once, the coach and the level as they
     *  land. Each card is asked for once per opening. */
    suspend fun writeNarration() {
        if (!narrates) return
        val ctx = narrationContext()
        val wanted = cardsNow.mapNotNull { card ->
            val key = narrationKey(card)
            if (narration.line(key) != null || key in narrationAsked) return@mapNotNull null
            if (card == RecapCard.LEVEL && !levelSettled) return@mapNotNull null
            ReportNarrator.facts(card.iosName, ctx)?.copy(card = key)
        }
        if (wanted.isEmpty()) return
        wanted.forEach { narrationAsked += it.card }
        try {
            val lines = ReportNarrator.write(
                cards = wanted, firstTalks = isTrial, targetLanguage = language,
                nativeLanguage = nativeLanguage(context), level = trialLevel ?: level,
                learnerName = PersonaStore.shared(context).load()?.displayName)
            narration = narration.merged(lines)
            if (isTrial) { val kept = narration; updateTrial { it.copy(narration = kept) } }
            narrator.prefetch(cardsNow.mapNotNull { narration.line(narrationKey(it)) })
            speakCurrentCard(onlyIfIdle = true)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            wanted.forEach { narrationAsked -= it.card }
            Analytics.capture("report_narration_failed", mapOf("error" to e.toString().take(160)))
        }
    }

    suspend fun phraseHabits() {
        try {
            val advice = HabitAdvice.phrase(habitFindings, firstTalks = isTrial,
                nativeLanguage = nativeLanguage(context))
            habitAdvice = advice
            updateTrial { it.copy(habitAdvice = advice) }
            writeNarration()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            habitAdviceFailed = true
            Analytics.capture("habit_advice_failed", mapOf("error" to e.toString().take(160)))
        }
    }

    /** A block a finding changed says which finding — its "change" line. */
    fun routineWhy(block: StudyPlan.Block): String? {
        val rule = routineRules[block.id] ?: return null
        val line = habitAdvice?.lines?.firstOrNull { it.rule == rule } ?: return null
        return line.change ?: line.title
    }

    LaunchedEffect(recap.end) {
        if (isTrial) {
            if (trialStarted) return@LaunchedEffect
            trialStarted = true
            TrialReportStore.countOffer(context)
            Analytics.capture("trial_report_opened", mapOf("talk_min" to recap.talkMinutes, "cards" to cards.size))
            // A test that could not be made last time (offline, a failed
            // write) is tried again: the minutes can't grow, but the network
            // can come back.
            trialState?.takeIf { it.testThin && it.testId == null }?.let { thin ->
                // Written before the reload below reads the file back.
                trialState = TrialReportStore.update(context, thin.targetLanguage) { it.copy(testThin = false) }
                    ?: thin.copy(testThin = false).also { TrialReportStore.save(context, it) }
            }
            reloadTrialTest(jump = false)
            // The routine: the one the learner already built (onboarding's
            // routine builder, or setup's suggested week before it), else the
            // one their purposes suggest. A routine they built is never
            // replaced from here.
            val plan = StudyPlanStore.current(context)
            val builtOwn = LearningPurposeStore.routineApplied(context) ||
                OnboardingFlags.seen(context, OnboardingFlags.DAILY_CALL)
            // Since 2026-10-27 the routine is built from HOW they used the app
            // ([StudyHabits] → [HabitAdvisor]), never from a template their
            // minutes had no say in: their own routine, or just the talk their
            // purposes start with, plus what each finding changes.
            val base: List<StudyPlan.Block> = if (builtOwn && plan.blocks.isNotEmpty()) {
                routineIsOwn = true
                plan.blocks
            } else {
                RoutineRecipe.lines(LearningPurposeStore.purposes(context), StudyPlanStore.goalMinutes(context))
                    .map { it.block }.filter { it.kind == StudyPlan.Kind.TALK }.take(1)
            }
            val habits = StudyHabits.read(context, current.start, current.end, current)
            featureUses = FeatureUse.list(habits)
            appSeconds = trialAppSeconds(context, current)
            learnerName = com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName
            habitFindings = HabitAdvisor.findings(habits)
            val built = HabitAdvisor.routine(base, habits, habitFindings, StudyPlanStore.goalMinutes(context))
            routine = built.map { RoutineRecipe.Line(it.block, 0) }
            routineRules = buildMap { built.forEach { l -> l.rule?.let { putIfAbsent(l.block.id, it) } } }
            val keptAdvice = trialState?.habitAdvice
            if (keptAdvice != null) habitAdvice = keptAdvice else trialScope.launch { phraseHabits() }
            narrator.configure(voiceId)
            val keptNarration = trialState?.narration
            if (keptNarration != null) narration = keptNarration
            narrationReady = true
            if (keptNarration != null) {
                // A reopened report has its whole script already; nothing new
                // arrives to start the card on screen, so start it here.
                narrator.prefetch(cardsNow.mapNotNull { narration.line(narrationKey(it)) })
                speakCurrentCard(onlyIfIdle = true)
            }
            trialScope.launch { writeNarration() }
            if (trialLevel == null) {
                val read = assessTrialLevel(context, language, nativeLanguage(context), onMeasuredLevel)
                trialLevel = read?.first
                trialRationale = read?.second
                levelSettled = true
                if (read != null) updateTrial { it.copy(level = read.first.code, levelRationale = read.second) }
            }
            return@LaunchedEffect
        }
        // Shown means SEEN: marked here, not where it was raised.
        WeekRecapStore.markShown(context, recap)
        testState = WeeklyTestSettings.schedule(context).state(
            WeeklyTestStore.shared(context).load(language), { WeeklyTestSettings.isThin(context, it) })
        Analytics.capture("week_recap_opened", mapOf("days" to recap.daysActive,
            "talk_min" to recap.talkMinutes, "cards" to cards.size))
    }
    LaunchedEffect(recap.end, coachAttempt) {
        if (!writeCoach || current.coach != null || !current.hasActivity) return@LaunchedEffect
        runCatching {
            WeekRecapCoach.write(context, current, language, level, nativeLanguage(context),
                firstTalks = isTrial)
        }.onSuccess { coach ->
            current = current.copy(coach = coach)
            if (isTrial) {
                val written = current
                updateTrial { it.copy(recap = written) }
            } else {
                WeekRecapStore.save(context, current)
            }
        }.onFailure { e ->
            coachFailed = true
            Analytics.capture("week_recap_coach_error", mapOf("error" to e.toString().take(160)))
        }
    }
    // One row per viewing, never one per swipe.
    // The test and the plans are Dialogs over the deck, so the deck stays
    // composed under them: covered is not closed.
    androidx.compose.runtime.DisposableEffect(Unit) {
        if (isTrial) TrialReportStore.isShowing = true
        onDispose {
            narrator.stop()
            if (isTrial) TrialReportStore.isShowing = false
            Analytics.capture(if (isTrial) "trial_report_closed" else "week_recap_closed",
                mapOf("reached" to ((revealed.maxOrNull() ?: 0) + 1), "cards" to cards.size))
        }
    }

    // The narration follows the page, the coach and the level as they land,
    // and stands down under the test and the plans.
    LaunchedEffect(pager) {
        snapshotFlow { pager.currentPage }.distinctUntilChanged().drop(1).collect { speakCurrentCard() }
    }
    LaunchedEffect(narrationReady, current.coach, levelSettled, trialTest?.isFinished) {
        if (narrationReady) trialScope.launch { writeNarration() }
    }
    LaunchedEffect(showingTrialTest, showingPaywall) {
        if (showingTrialTest || showingPaywall) narrator.stop()
    }

    fun finish(action: WeekRecapAction?) {
        if (action != null) Analytics.capture("week_recap_action",
            mapOf("action" to if (action == WeekRecapAction.TEST) "test" else "talk"))
        onClose(action)
    }

    val scope = rememberCoroutineScope()
    LaunchedEffect(jumpToLevel, cards.size) {
        if (!jumpToLevel) return@LaunchedEffect
        val index = cards.indexOf(RecapCard.LEVEL)
        if (index >= 0) { jumpToLevel = false; pager.animateScrollToPage(index) }
    }
    fun advance() {
        scope.launch { pager.animateScrollToPage(minOf(pager.currentPage + 1, cards.size - 1)) }
    }
    fun keepRoutine() {
        if (!routineIsOwn && routine.isNotEmpty()) {
            StudyPlanStore.update(context, RoutineRecipe.plan(routine))
            LearningPurposeStore.setRoutineApplied(context)
        } else if (routineIsOwn && routineRules.isNotEmpty()) {
            // Their own routine keeps everything they set; only the blocks
            // a finding changed or added are written.
            StudyPlanStore.update(context, StudyPlanStore.current(context).copy(blocks = routine.map { it.block }))
        }
        Analytics.capture("trial_report_routine", mapOf("own" to routineIsOwn,
            "changed" to routineRules.size,
            "rules" to habitFindings.joinToString(",") { it.rule }))
        showingPaywall = true
    }
    if (showingTrialTest) {
        Dialog(
            onDismissRequest = { showingTrialTest = false; scope.launch { reloadTrialTest(jump = true) } },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            DialogSystemBarsLikeActivity()
            WeeklyTestScreen(language = language, level = level,
                onClose = { showingTrialTest = false; scope.launch { reloadTrialTest(jump = true) } },
                trialScope = WeeklyTestEngine.Scope(start = current.start,
                    minimum = TrialReportStore.MIN_TEST_ITEMS, coach = current.coach),
                onTrialFinished = {
                    val wasCleared = trialTest?.isFinished == true || trialState?.testThin == true
                    trialTest = it
                    if (!wasCleared) jumpToLevel = true
                })
        }
    }
    if (showingPaywall) {
        PaywallDialog(onDismiss = {
            // The report has done its job whether or not they bought. Then
            // what they thought of it, once, and the store's own rating sheet.
            showingPaywall = false
            TrialReportStore.setFinished(context)
            if (FeedbackPrompt.shouldShow(context, FeedbackContext.TRIAL_REPORT)) {
                FeedbackPrompt.markShown(context, FeedbackContext.TRIAL_REPORT)
                showingFeedback = true
            } else {
                endTrialReport(context, onClose)
            }
        })
    }
    if (showingFeedback) {
        FeedbackSheet(FeedbackContext.TRIAL_REPORT, onDismiss = {
            showingFeedback = false
            endTrialReport(context, onClose)
        })
    }
    Column(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
        TopBar(current, cards.size, pager.currentPage, isTrial,
            onSelect = { scope.launch { pager.animateScrollToPage(it) } },
            onClose = { finish(null) },
            narration = if (narrates) narrator.isOn else null,
            onNarration = {
                narrator.isOn = !narrator.isOn
                if (narrator.isOn) speakCurrentCard() else narrator.stop()
            })
        HorizontalPager(state = pager, modifier = Modifier.weight(1f)) { index ->
            val shown = index in revealed
            val alpha by animateFloatAsState(if (shown) 1f else 0f, tween(400), label = "recapReveal")
            Box(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 8.dp)
                .background(AppSurfaces.card, ContinuousShape(24.dp))) {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp)
                    .alpha(alpha).offset(y = ((1f - alpha) * 14).dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    val pending: @Composable () -> Unit = {
                        CoachPending(coachFailed, isTrial) { coachFailed = false; coachAttempt++ }
                    }
                    when (cards[index]) {
                        RecapCard.COVER -> if (isTrial) TrialCover(current, trialState, learnerName) else Cover(current)
                        RecapCard.TALK -> if (isTrial) UsageCard(featureUses, appSeconds) else TalkCard(current)
                        RecapCard.USED -> UsedCard(current)
                        RecapCard.REVIEW -> ReviewCard(current, isTrial)
                        RecapCard.FRESH -> FreshCard(current)
                        RecapCard.STUMBLES -> StumblesCard(current)
                        RecapCard.GRAMMAR -> GrammarCard(current, pending)
                        RecapCard.WORDS -> WordsCard(current, pending)
                        RecapCard.COACH -> CoachCard(current, pending, isTrial)
                        RecapCard.TEST -> { TestCard(testState); ReminderOffer() }
                        RecapCard.TRIAL_TEST -> TrialTestCard(trialTest, trialState?.testThin == true)
                        RecapCard.LEVEL -> LevelCard(trialLevel, trialRationale, levelSettled, trialTest, trialState)
                        RecapCard.ROUTINE -> RoutineCard(routine, habitFindings, habitAdvice, habitAdviceFailed,
                            onRetry = { habitAdviceFailed = false; trialScope.launch { phraseHabits() } },
                            fromWhatWeSaw = !(routineRules.isEmpty() && routineIsOwn),
                            why = ::routineWhy)
                    }
                }
            }
        }
        if (narrates) cards.getOrNull(pager.currentPage)?.let { card ->
            narration.line(narrationKey(card))?.let { line ->
                CaptionBox(line, speaking = narrator.speakingCard == line.card,
                    showCaption = line.caption.isNotEmpty() &&
                        !LanguageCatalog.sameLanguage(language, nativeLanguage(context)),
                    onTap = { speakCurrentCard() })
            }
        }
        // The deck's one button clears the navigation bar wherever the deck is
        // drawn (a sheet, or the capture's full page, where Next sat under it).
        Box(Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 20.dp).padding(bottom = 12.dp, top = 4.dp)) {
            val card = cards.getOrNull(pager.currentPage)
            if (isTrial && (card == RecapCard.TRIAL_TEST || card == RecapCard.ROUTINE)) {
                val t = trialTest
                when {
                    card == RecapCard.ROUTINE ->
                        Primary(stringResource(R.string.trial_keep_routine)) { keepRoutine() }
                    trialTestCleared -> Primary(stringResource(R.string.trial_see_level)) { advance() }
                    else -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (t != null && t.answers.isNotEmpty())
                            Primary(stringResource(R.string.wr_continue_test)) { showingTrialTest = true }
                        else Primary(stringResource(R.string.trial_take_test)) { showingTrialTest = true }
                        TextButton(onClick = {
                            Analytics.capture("trial_test_skipped", emptyMap())
                            advance()
                        }, modifier = Modifier.fillMaxWidth().height(48.dp)) {
                            Text(stringResource(R.string.skip))
                        }
                    }
                }
            } else if (card == RecapCard.TEST) {
                when (testState) {
                    WeeklyTestSchedule.State.Ready ->
                        Primary(stringResource(R.string.wr_start_test)) { finish(WeekRecapAction.TEST) }
                    is WeeklyTestSchedule.State.InProgress ->
                        Primary(stringResource(R.string.wr_continue_test)) { finish(WeekRecapAction.TEST) }
                    is WeeklyTestSchedule.State.Done ->
                        Primary(stringResource(R.string.wr_see_results)) { finish(WeekRecapAction.TEST) }
                    is WeeklyTestSchedule.State.Thin ->
                        Primary(stringResource(R.string.start_a_talk)) { finish(WeekRecapAction.TALK) }
                }
            } else {
                Primary(stringResource(R.string.next)) { advance() }
            }
        }
    }
}

private fun testMissed(r: WeekRecap): Int {
    val score = r.testScore ?: return 0
    val total = r.testTotal ?: return 0
    return total - score
}

// MARK: - Chrome

@Composable
private fun chromeLocale(): Locale {
    val context = LocalContext.current
    return Locale.forLanguageTag(UILanguage.current(context) ?: Locale.getDefault().toLanguageTag())
}

@Composable
private fun TopBar(recap: WeekRecap, count: Int, page: Int, isTrial: Boolean, onSelect: (Int) -> Unit,
                   onClose: () -> Unit, narration: Boolean? = null, onNarration: () -> Unit = {}) {
    val locale = chromeLocale()
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 4.dp, bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Stories-style segments: where you are in the deck, tappable.
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            repeat(count) { i ->
                Box(Modifier.weight(1f).height(3.dp)
                    .background(if (i <= page) MaterialTheme.colorScheme.primary else tertiaryFill(), CircleShape)
                    .clickable { onSelect(i) })
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (isTrial) {
                Text(stringResource(R.string.trial_your_first_minutes,
                    // Invite minutes can make the free time longer than the grant.
                    maxOf(com.roro.futurevoice.data.BillingConfig.freeTalkSeconds(LocalContext.current) / 60, recap.talkMinutes)),
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f))
            } else {
                Text(stringResource(R.string.wr_your_week), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold)
                // The date gives way, never the close button (at a 1.3 font it
                // pushed the ✕ off the row).
                Text(dateRange(recap, locale), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f))
            }
            if (narration != null) {
                Box(Modifier.size(32.dp).background(tertiaryFill(), CircleShape).clickable(onClick = onNarration),
                    contentAlignment = Alignment.Center) {
                    Icon(if (narration) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                        contentDescription = stringResource(if (narration) R.string.trial_mute_narration
                            else R.string.trial_play_narration),
                        tint = if (narration) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp))
                }
            }
            Box(Modifier.size(32.dp).background(tertiaryFill(), CircleShape).clickable(onClick = onClose),
                contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun Primary(label: String, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.fillMaxWidth().height(52.dp)) {
        Text(label, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun tertiaryFill() = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f)

@Composable
private fun Kicker(title: String, icon: ImageVector, tint: Color = MaterialTheme.colorScheme.primary) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = tint)
    }
}

@Composable
private fun BigNumber(value: Int, unit: String? = null) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("$value", fontSize = 64.sp, fontWeight = FontWeight.Bold, lineHeight = 64.sp)
        if (unit != null) Text(unit, style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 8.dp))
    }
}

@Composable
private fun Lead(text: String) = Text(text, style = MaterialTheme.typography.titleMedium)

@Composable
private fun Secondary(text: String) =
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)

@Composable
private fun Tile(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(tertiaryFill(), RoundedCornerShape(14.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
}

@Composable
private fun LabelRow(icon: ImageVector, tint: Color = MaterialTheme.colorScheme.primary, content: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp).width(22.dp))
        content()
    }
}

private fun quoted(s: String) = "“$s”"

// MARK: - Cards

@Composable
private fun Cover(r: WeekRecap) {
    val locale = chromeLocale()
    Kicker(stringResource(R.string.wr_last_week), Icons.Filled.CalendarMonth)
    if (r.hasActivity) {
        BigNumber(r.daysActive, stringResource(R.string.wr_of_7_days))
        Lead(stringResource(when (r.daysActive) {
            7 -> R.string.wr_every_day
            5, 6 -> R.string.wr_most_of_week
            3, 4 -> R.string.wr_few_days_in
            else -> R.string.wr_showed_up
        }))
    } else {
        Text(stringResource(R.string.wr_quiet_week), fontSize = 40.sp, fontWeight = FontWeight.Bold, lineHeight = 44.sp)
        Lead(stringResource(R.string.wr_quiet_body))
    }
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        for (i in 0 until 7) {
            val on = r.activeDays.getOrNull(i) == true
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(30.dp).background(if (on) MaterialTheme.colorScheme.primary else tertiaryFill(), CircleShape),
                    contentAlignment = Alignment.Center) {
                    if (on) Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.size(16.dp))
                }
                Text(weekdayLetter(r.start, i, locale), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    if (r.streak > 1) {
        LabelRow(Icons.Filled.LocalFireDepartment, Orange) {
            Text(stringResource(R.string.lld_day_streak, r.streak), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold, color = Orange)
        }
    }
    if (r.hasActivity) SummaryRow(r)
}

/** The whole week in one glance, before the cards take it apart. */
@Composable
private fun SummaryRow(r: WeekRecap) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (r.talkSeconds > 0) LabelRow(Icons.Filled.GraphicEq) {
                Text(pluralStringResource(R.plurals.wr_min_of_talk_talks, r.talks.size, r.talkMinutes, r.talks.size))
            }
            if (r.usedCount > 0) LabelRow(Icons.Filled.Verified) {
                Text(pluralStringResource(R.plurals.wr_things_said, r.usedCount, r.usedCount))
            }
            if (r.nowYours.isNotEmpty()) LabelRow(Icons.Filled.ViewAgenda) {
                Text(pluralStringResource(R.plurals.wr_became_yours, r.nowYours.size, r.nowYours.size))
            }
            if (r.newExpressionCount > 0) LabelRow(Icons.Filled.AutoAwesome) {
                Text(pluralStringResource(R.plurals.wr_new_phrases, r.newExpressionCount, r.newExpressionCount))
            }
        }
}

@Composable
private fun TalkCard(r: WeekRecap) {
    val locale = chromeLocale()
    Kicker(stringResource(R.string.talks), Icons.Filled.GraphicEq)
    BigNumber(r.talkMinutes, stringResource(R.string.wr_min))
    val previous = r.previousTalkSeconds / 60
    if (r.talkMinutes > previous && previous > 0) {
        LabelRow(Icons.AutoMirrored.Filled.TrendingUp, Green) {
            Text(stringResource(R.string.wr_min_more_than_week_before, r.talkMinutes - previous),
                fontWeight = FontWeight.SemiBold, color = Green)
        }
    } else if (previous > 0) {
        Secondary(stringResource(R.string.wr_week_before_min, previous))
    }
    if (r.talks.isNotEmpty()) {
        Column(Modifier.fillMaxWidth().background(tertiaryFill(), RoundedCornerShape(14.dp))
            .padding(horizontal = 12.dp, vertical = 4.dp)) {
            r.talks.take(6).forEachIndexed { i, t ->
                if (i > 0) HorizontalDivider(Modifier.padding(start = 40.dp))
                Row(Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(talkIcon(t.kind), contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp).width(28.dp))
                    Column {
                        Text(t.title.ifBlank { stringResource(R.string.conversation) },
                            style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 2)
                        Text(stringResource(R.string.wr_talk_line_day_min, weekday(t.day, locale), t.minutes),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (r.talks.size > 6) {
                Text(stringResource(R.string.wr_and_more, r.talks.size - 6),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 40.dp, top = 4.dp, bottom = 8.dp))
            }
        }
    }
}

private fun talkIcon(kind: String): ImageVector = when (kind) {
    "person" -> Icons.Filled.Person
    "scenario" -> Icons.Filled.TheaterComedy
    "news" -> Icons.Filled.Newspaper
    else -> Icons.Filled.GraphicEq
}

@Composable
private fun UsedCard(r: WeekRecap) {
    Kicker(stringResource(R.string.you_used_what_you_practiced), Icons.Filled.Verified, Green)
    BigNumber(r.usedCount)
    Lead(stringResource(R.string.wr_studied_then_said))
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        r.used.forEach { e ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(e.item, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Secondary(quoted(e.quote))
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ReviewCard(r: WeekRecap, isTrial: Boolean = false) {
    // Like every card it leads with ONE number, and that number is the count
    // of the list right under it.
    Kicker(stringResource(R.string.practice), Icons.Filled.ViewAgenda)
    if (r.nowYours.isNotEmpty()) {
        BigNumber(r.nowYours.size)
        Lead(stringResource(if (isTrial) R.string.trial_became_yours_body else R.string.wr_became_yours_body))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            r.nowYours.take(12).forEach {
                Text(it, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium,
                    modifier = Modifier.background(tertiaryFill(), CircleShape).padding(horizontal = 12.dp, vertical = 7.dp))
            }
        }
        if (r.nowYours.size > 12) Secondary(stringResource(R.string.wr_plus_more, r.nowYours.size - 12))
    }
    if (r.sentencesGot.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(pluralStringResource(R.plurals.wr_sentences_got, r.sentencesGot.size, r.sentencesGot.size),
                style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            r.sentencesGot.take(3).forEach { line ->
                LabelRow(Icons.Filled.Check, Green) { Text(line, style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
    if (r.shadowTakes > 0 || r.scenes > 0) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (r.shadowTakes > 0) LabelRow(Icons.Filled.RecordVoiceOver) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(pluralStringResource(R.plurals.wr_shadow_takes, r.shadowTakes, r.shadowTakes))
                    r.shadowAverage?.let { avg ->
                        Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.wr_average, avg))
                        val prev = r.previousShadowAverage
                        if (prev != null && avg != prev) {
                            Text(if (avg > prev) "+${avg - prev}" else "${avg - prev}",
                                color = if (avg > prev) Green else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            if (r.scenes > 0) LabelRow(Icons.Filled.PlayCircle) {
                Text(pluralStringResource(R.plurals.wr_scenes_watched, r.scenes, r.scenes))
            }
        }
    }
}

@Composable
private fun FreshCard(r: WeekRecap) {
    Kicker(stringResource(R.string.wr_new_from_fluent), Icons.Filled.AutoAwesome)
    if (r.newExpressionCount > 0) {
        BigNumber(r.newExpressionCount)
        Lead(stringResource(R.string.wr_things_fluent_said))
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            r.newExpressions.forEach { e ->
                Tile {
                    Text(e.item, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    if (e.quote.isNotEmpty()) Secondary(quoted(e.quote))
                }
            }
        }
        Secondary(stringResource(R.string.wr_waiting_in_expressions))
    }
    if (r.newCards > 0) LabelRow(Icons.Filled.LibraryAdd) {
        Text(pluralStringResource(R.plurals.wr_new_cards, r.newCards, r.newCards), fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun StumblesCard(r: WeekRecap) {
    Kicker(stringResource(R.string.wr_where_stuck), Icons.Filled.Autorenew, Orange)
    if (r.stumbles.isNotEmpty()) {
        Lead(stringResource(R.string.wr_same_fix_back))
        r.stumbles.forEach { s ->
            Tile {
                Text(s.was, textDecoration = TextDecoration.LineThrough, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(s.now, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f))
                    Text("×${s.count}", fontWeight = FontWeight.SemiBold, color = Orange)
                }
            }
        }
    } else if (r.shakyLines.isNotEmpty()) {
        Lead(stringResource(R.string.wr_shaky_lines))
        r.shakyLines.forEach { s ->
            Tile {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(s.now, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f))
                    Text("${s.count}", fontWeight = FontWeight.SemiBold, color = Orange)
                }
            }
        }
    }
    val missed = testMissed(r)
    if (missed > 0) LabelRow(Icons.Filled.Checklist, MaterialTheme.colorScheme.onSurfaceVariant) {
        Secondary(pluralStringResource(R.plurals.wr_last_test_missed, missed, r.testScore ?: 0, r.testTotal ?: 0, missed))
    }
}

@Composable
private fun GrammarCard(r: WeekRecap, pending: @Composable () -> Unit) {
    Kicker(stringResource(R.string.wr_grammar_title), Icons.Filled.Spellcheck, Orange)
    val c = r.coach ?: return pending()
    if (c.grammar.isEmpty()) { Lead(stringResource(R.string.wr_no_grammar)); return }
    Lead(stringResource(R.string.wr_same_point))
    c.grammar.forEach { p ->
        Tile {
            Text(p.rule, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            p.examples.forEach { e ->
                Column(Modifier.padding(top = 4.dp)) {
                    Text(e.was, textDecoration = TextDecoration.LineThrough,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                    Text(e.now, fontWeight = FontWeight.Medium, style = MaterialTheme.typography.bodyMedium)
                }
            }
            if (p.tip.isNotEmpty()) Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Lightbulb, contentDescription = null, tint = Orange, modifier = Modifier.size(18.dp))
                Text(p.tip, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun WordsCard(r: WeekRecap, pending: @Composable () -> Unit) {
    Kicker(stringResource(R.string.wr_words_level_up), Icons.Filled.ArrowCircleUp)
    val c = r.coach ?: return pending()
    if (c.upgrades.isEmpty()) { Lead(stringResource(R.string.wr_no_word)); return }
    Lead(stringResource(R.string.wr_words_leaned_on))
    c.upgrades.forEach { u ->
        Tile {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(u.instead, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("×${u.count}", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                Text(u.better, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
            if (u.rewritten.isNotEmpty()) {
                Secondary(quoted(u.original))
                Text(quoted(u.rewritten), style = MaterialTheme.typography.bodyMedium)
            }
            if (u.note.isNotEmpty()) Text(u.note, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun CoachCard(r: WeekRecap, pending: @Composable () -> Unit, isTrial: Boolean = false) {
    Kicker(stringResource(R.string.wr_from_coach), Icons.Filled.FormatQuote)
    val c = r.coach
    when {
        c != null -> {
            Text(c.headline, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            if (c.insight.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.wr_how_you_speak), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(c.insight, style = MaterialTheme.typography.bodyLarge)
                    if (c.insightQuote.isNotEmpty()) Secondary(quoted(c.insightQuote))
                }
            }
            if (c.plan.isNotEmpty()) PlanBox(c.plan, isTrial)
        }
        r.hasActivity -> pending()
        else -> {
            Lead(stringResource(R.string.wr_new_week_start_small))
            PlanBox(listOf(fallbackFocus(r)), isTrial)
        }
    }
}

/** Written in code when the coach can't be — from the same evidence. */
@Composable
private fun fallbackFocus(r: WeekRecap): String {
    r.stumbles.firstOrNull()?.let { return stringResource(R.string.wr_say_in_next_talk, it.now) }
    r.newExpressions.firstOrNull()?.let { return stringResource(R.string.wr_try_in_next_talk, it.item) }
    r.shakyLines.firstOrNull()?.let { return stringResource(R.string.wr_shadow_once_more, it.now) }
    return stringResource(R.string.wr_one_talk_plan)
}

@Composable
private fun PlanBox(items: List<String>, isTrial: Boolean = false) {
    val accent = MaterialTheme.colorScheme.primary
    Column(Modifier.fillMaxWidth().background(accent.copy(alpha = 0.12f), RoundedCornerShape(16.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(if (isTrial) R.string.trial_next_up else R.string.wr_this_week),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold, color = accent)
        items.forEachIndexed { i, item ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("${i + 1}", fontWeight = FontWeight.Bold, color = accent)
                Text(item, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            }
        }
    }
}

/** The coach's read hasn't landed: waiting, or failed with a way back. */
@Composable
private fun CoachPending(failed: Boolean, isTrial: Boolean, onRetry: () -> Unit) {
    if (failed) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Lead(stringResource(if (isTrial) R.string.trial_coach_failed else R.string.wr_coach_failed))
            OutlinedButton(onClick = onRetry) {
                Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.try_again))
            }
        }
    } else {
        Row(Modifier.padding(vertical = 20.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            Secondary(stringResource(if (isTrial) R.string.trial_reading else R.string.wr_reading))
        }
    }
}

@Composable
private fun TestCard(state: WeeklyTestSchedule.State) {
    Kicker(stringResource(R.string.wr_this_weeks_test), Icons.Filled.Checklist)
    Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.CheckCircleOutline, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(72.dp))
    }
    Lead(when (state) {
        WeeklyTestSchedule.State.Ready -> stringResource(R.string.wr_test_ready_body)
        is WeeklyTestSchedule.State.InProgress ->
            stringResource(R.string.wr_test_in_progress, state.test.answers.size, state.test.total)
        is WeeklyTestSchedule.State.Done -> stringResource(R.string.wr_test_done, state.test.score, state.test.total)
        is WeeklyTestSchedule.State.Thin -> stringResource(R.string.wr_test_thin)
    })
}

/**
 * The deck slides up by itself only when the app is opened; the notice is
 * what reaches someone who doesn't. Offered here, once the learner has seen
 * what the notice would bring — never as a cold permission prompt (iOS
 * `reminderOffer`). Only while the reminder is off and the phone could still
 * ring: a refusal the system won't ask about again leaves the offer gone.
 */
@Composable
private fun ReminderOffer() {
    val context = LocalContext.current
    fun canAsk(): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled() ||
            (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
    var offer by remember { mutableStateOf(!WeeklyTestSettings.reminderOn(context) && canAsk()) }
    var justOn by remember { mutableStateOf(false) }
    fun settle(granted: Boolean) {
        val on = granted && NotificationManagerCompat.from(context).areNotificationsEnabled()
        WeeklyTestSettings.setReminderOn(context, on)     // re-arms the alarm
        justOn = on
        offer = false
        Analytics.capture("week_recap_reminder", mapOf("on" to on))
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission(), ::settle)
    when {
        justOn -> Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.Notifications, contentDescription = null, modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Secondary(stringResource(R.string.wr_next_week_arrives,
                weekReadyDate(WeeklyTestSettings.schedule(context).nextOpening(), weekLocale(context))))
        }
        offer -> OutlinedButton(onClick = {
            val needsAsk = Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            if (needsAsk) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else settle(true)
        }) {
            Icon(Icons.Filled.NotificationsNone, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.wr_tell_me_next_week))
        }
    }
}

// MARK: - Trial report

// 1 — the free minutes, handed over (iOS 2026-10-28, founder: "clean, with
// their name, friendly, and the feeling of being looked after"). Their face
// and name first, so the deck reads as made for one person; then the three
// numbers the rest of it is read from.
@Composable
private fun TrialCover(r: WeekRecap, trial: TrialReport?, displayName: String?) {
    val locale = chromeLocale()
    val primary = MaterialTheme.colorScheme.primary
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.border(2.5.dp, primary, CircleShape).padding(5.dp)) {
            ProfileAvatar(displayName ?: "", 64.dp)
        }
        Spacer(Modifier.weight(1f))
        Text("${monthDay(r.start, locale)} – ${monthDay(r.end - 1, locale)}", style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Kicker(stringResource(R.string.trial_made_for_you), Icons.Filled.CardGiftcard)
        val name = coverName(displayName)
        Text(if (name != null) stringResource(R.string.trial_report_ready_named, name)
             else stringResource(R.string.trial_report_ready),
            fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.trial_cover_just_for_you), style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Row(Modifier.fillMaxWidth().background(tertiaryFill(), ContinuousShape(18.dp)).padding(vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically) {
        CoverStat(r.talkMinutes, stringResource(R.string.trial_stat_min_of_talk))
        StatDivider()
        CoverStat(r.talks.size, stringResource(R.string.trial_stat_talks))
        val own = trial?.ownSpeechSeconds
        if (own != null && own > 0) {
            StatDivider()
            CoverStat(maxOf(1, own / 60), stringResource(R.string.trial_stat_min_you_spoke))
        }
    }
    LabelRow(Icons.Filled.CalendarMonth, MaterialTheme.colorScheme.onSurfaceVariant) {
        Text(stringResource(R.string.trial_weekly_report_note), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** "Oct 26" in the chrome's language. */
private fun monthDay(at: Long, locale: java.util.Locale): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd")
    return java.text.SimpleDateFormat(pattern, locale).format(java.util.Date(at))
}

/** The name the cover greets: the first word of a spaced name ("Anna
 *  Schmidt" → Anna), the whole of an unspaced one (이응규). */
private fun coverName(full: String?): String? {
    val t = full?.trim().orEmpty()
    if (t.isEmpty()) return null
    return t.split(Regex("\\s+")).firstOrNull() ?: t
}

@Composable
private fun RowScope.CoverStat(value: Int, label: String) {
    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("$value", fontSize = 30.sp, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun StatDivider() {
    Box(Modifier.width(1.dp).height(44.dp).background(MaterialTheme.colorScheme.outlineVariant))
}

// 2 — how they used the app (iOS 2026-10-28, founder): the time it took, said
// as time that didn't go to scrolling, then EVERY practice feature with how
// much of it was used, so the ones they never opened are on the page too, and
// one line on what to add.
@Composable
private fun UsageCard(uses: List<FeatureUse>, appSeconds: Int) {
    Kicker(stringResource(R.string.trial_how_you_used_it), Icons.Filled.GridView)
    BigNumber(maxOf(1, appSeconds / 60), stringResource(R.string.trial_min_in_app))
    Lead(stringResource(R.string.trial_not_scrolling))
    if (uses.isEmpty()) return
    Text(stringResource(R.string.trial_tried_n_of_m, uses.count { it.used }, uses.size),
        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(top = 4.dp))
    UsageAdvice(FeatureUse.advice(uses))
    Column {
        uses.forEachIndexed { index, use ->
            if (index > 0) Box(Modifier.padding(start = 46.dp).fillMaxWidth().height(0.5.dp)
                .background(MaterialTheme.colorScheme.outlineVariant))
            FeatureRow(use)
        }
    }
}

@Composable
private fun FeatureRow(use: FeatureUse) {
    val res = LocalContext.current.resources
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Row(Modifier.fillMaxWidth().padding(vertical = 9.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(34.dp).background(if (use.used) featureColor(use.feature) else tertiaryFill(), CircleShape),
            contentAlignment = Alignment.Center) {
            Icon(featureIcon(use.feature), contentDescription = null,
                tint = if (use.used) Color.White else muted, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(featureName(res, use.feature), style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold, color = if (use.used) MaterialTheme.colorScheme.onSurface else muted)
            Text(stringResource(featureBlurb(use.feature)), style = MaterialTheme.typography.bodySmall, color = muted)
        }
        Text(when {
                !use.used -> stringResource(R.string.not_yet)
                use.feature == FeatureUse.Feature.TALK -> "${maxOf(1, use.minutes)} ${stringResource(R.string.wr_min)}"
                else -> stringResource(R.string.lld_17887f, use.count)
            }, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
            color = if (use.used) MaterialTheme.colorScheme.onSurface else muted.copy(alpha = 0.6f))
    }
}

@Composable
private fun UsageAdvice(advice: FeatureUse.Advice) {
    val text = stringResource(when (advice) {
        FeatureUse.Advice.OnlyTalk -> R.string.trial_advice_only_talk
        FeatureUse.Advice.NoTalk -> R.string.trial_advice_no_talk
        FeatureUse.Advice.WideMix -> R.string.trial_advice_wide_mix
        is FeatureUse.Advice.Next -> when (advice.feature) {
            FeatureUse.Feature.SAY_IT_AGAIN -> R.string.trial_advice_say_it_again
            FeatureUse.Feature.REVIEW -> R.string.trial_advice_review
            FeatureUse.Feature.SHADOW -> R.string.trial_advice_shadow
            FeatureUse.Feature.SCENE -> R.string.trial_advice_scene
            FeatureUse.Feature.LISTEN -> R.string.trial_advice_listen
            FeatureUse.Feature.SPEECH -> R.string.trial_advice_speech
            FeatureUse.Feature.TALK -> R.string.trial_advice_no_talk
        }
    })
    val tint = when (advice) {
        FeatureUse.Advice.OnlyTalk -> Orange
        FeatureUse.Advice.WideMix -> Green
        else -> MaterialTheme.colorScheme.primary
    }
    Row(Modifier.fillMaxWidth().background(tertiaryFill(), ContinuousShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(if (advice == FeatureUse.Advice.WideMix) Icons.Filled.ThumbUp else Icons.Filled.Lightbulb,
            contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

private fun planKind(f: FeatureUse.Feature): StudyPlan.Kind = when (f) {
    FeatureUse.Feature.TALK, FeatureUse.Feature.SCENE -> StudyPlan.Kind.TALK
    FeatureUse.Feature.SAY_IT_AGAIN -> StudyPlan.Kind.SAY_IT_AGAIN
    FeatureUse.Feature.REVIEW -> StudyPlan.Kind.REVIEW
    FeatureUse.Feature.SHADOW -> StudyPlan.Kind.SHADOW
    FeatureUse.Feature.LISTEN -> StudyPlan.Kind.LISTEN
    FeatureUse.Feature.SPEECH -> StudyPlan.Kind.SPEECH
}

private fun featureName(res: android.content.res.Resources, f: FeatureUse.Feature): String =
    if (f == FeatureUse.Feature.SCENE) res.getString(R.string.scenes) else RoutineText.label(res, planKind(f))

private fun featureIcon(f: FeatureUse.Feature): ImageVector =
    if (f == FeatureUse.Feature.SCENE) Icons.Filled.SmartDisplay else planKind(f).icon()

/** Mint for scenes: the one system colour no routine kind uses (indigo is the Core's). */
private fun featureColor(f: FeatureUse.Feature): Color =
    if (f == FeatureUse.Feature.SCENE) Color(0xFF00C7BE) else planKind(f).color()

private fun featureBlurb(f: FeatureUse.Feature): Int = when (f) {
    FeatureUse.Feature.TALK -> R.string.trial_blurb_talk
    FeatureUse.Feature.SAY_IT_AGAIN -> R.string.trial_blurb_say_it_again
    FeatureUse.Feature.REVIEW -> R.string.trial_blurb_review
    FeatureUse.Feature.SHADOW -> R.string.trial_blurb_shadow
    FeatureUse.Feature.SCENE -> R.string.trial_blurb_scene
    FeatureUse.Feature.LISTEN -> R.string.trial_blurb_listen
    FeatureUse.Feature.SPEECH -> R.string.trial_blurb_speech
}

/** Foreground time over the window, never less than the metered talk (a call
 *  in a pocket is metered but not foregrounded), like the day card. */
private fun trialAppSeconds(context: android.content.Context, r: WeekRecap): Int {
    val zone = java.time.ZoneId.systemDefault()
    var day = java.time.Instant.ofEpochMilli(r.start).atZone(zone).toLocalDate()
    var seconds = 0
    while (true) {
        val at = day.atStartOfDay(zone).toInstant().toEpochMilli()
        if (at >= r.end) break
        seconds += com.roro.futurevoice.data.AppUsageLog.secondsWithOpenStint(context, at)
        day = day.plusDays(1)
    }
    return maxOf(seconds, r.talkSeconds)
}

/** The usage card's facts for the narration, in place of the talk card's. */
private fun usageFacts(uses: List<FeatureUse>, appSeconds: Int): List<String> {
    if (uses.isEmpty()) return emptyList()
    val f = mutableListOf("How they used the app: ${appSeconds / 60} min in the app in total (time not spent scrolling).")
    for (u in uses) {
        val name = u.feature.raw
        f += if (!u.used) "$name: never used"
            else if (u.feature == FeatureUse.Feature.TALK) "$name: ${u.minutes} min, ${u.count} talk(s)"
            else "$name: ${u.count}"
    }
    f += when (val a = FeatureUse.advice(uses)) {
        FeatureUse.Advice.OnlyTalk -> "They only talked; suggest Say it again after a call and a few review cards a day."
        is FeatureUse.Advice.Next -> "Suggest adding ${a.feature.raw} next."
        FeatureUse.Advice.WideMix -> "They tried most features; praise the mix."
        FeatureUse.Advice.NoTalk -> "They never talked; talking is the heart of it."
    }
    return f
}

/** The deck's last step: the store's rating sheet follows whatever the
 *  feedback sheet said (never gated on its stars), then the deck goes. Asked
 *  after the deck has gone: over a screen mid-dismissal it can be dropped. */
private fun endTrialReport(context: android.content.Context, onClose: (WeekRecapAction?) -> Unit) {
    val activity = context as? android.app.Activity
    onClose(null)
    if (activity != null) android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
        com.roro.futurevoice.data.ReviewRequest.askAtTrialReportEnd(activity)
    }, 1_200)
}

// The test — required: the level and the routine come after it.
@Composable
private fun TrialTestCard(test: WeeklyTest?, thin: Boolean) {
    val finished = test?.isFinished == true
    Kicker(stringResource(R.string.trial_first_test), Icons.Filled.Checklist)
    Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
        Icon(when {
            finished -> Icons.Filled.CheckCircle
            thin -> Icons.AutoMirrored.Filled.EventNote
            else -> Icons.Filled.CheckCircleOutline
        }, contentDescription = null,
            tint = when {
                finished -> Green
                thin -> MaterialTheme.colorScheme.onSurfaceVariant
                else -> MaterialTheme.colorScheme.primary
            }, modifier = Modifier.size(72.dp))
    }
    when {
        test != null && finished -> {
            Text(stringResource(R.string.wr_test_done, test.score, test.total),
                style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Secondary(stringResource(R.string.trial_next_level))
        }
        thin -> Lead(stringResource(R.string.trial_test_thin))
        test != null && test.answers.isNotEmpty() ->
            Lead(stringResource(R.string.wr_test_in_progress, test.answers.size, test.total))
        else -> {
            Lead(stringResource(R.string.trial_test_body))
        }
    }
}

// The level — the first assessment, run early for the report.
@Composable
private fun LevelCard(level: CefrLevel?, rationale: String?, settled: Boolean, test: WeeklyTest?, trial: TrialReport?) {
    val context = LocalContext.current
    Kicker(stringResource(R.string.your_level_0ad2c2), Icons.Filled.BarChart)
    when {
        level != null -> {
            Text(LanguageCatalog.levelLabel(level, LanguageScope.active(context)),
                fontSize = 64.sp, fontWeight = FontWeight.Bold, lineHeight = 64.sp)
            Lead(canDoAt(level.code))
            if (!rationale.isNullOrEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.trial_how_we_read), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(rationale, style = MaterialTheme.typography.bodyMedium)
                }
            }
            if (test != null && test.isFinished) LabelRow(Icons.Filled.Checklist, MaterialTheme.colorScheme.onSurfaceVariant) {
                Secondary(stringResource(R.string.trial_test_score, test.score, test.total))
            }
            SpeechBasis(trial)
        }
        settled -> Lead(stringResource(R.string.trial_level_later))
        else -> Row(Modifier.padding(vertical = 20.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            Secondary(stringResource(R.string.trial_reading_level))
        }
    }
}

/** What the level was read from, said plainly (iOS `speechBasis`): twenty
 *  minutes of call is a few minutes of the learner's own voice, and a confident
 *  letter from four of them is the letter Progress contradicts later. A second
 *  language spoken in the window is named, so its minutes aren't silently
 *  missing from a report about the other one. */
@Composable
private fun SpeechBasis(trial: TrialReport?) {
    val locale = chromeLocale()
    val style = MaterialTheme.typography.bodySmall
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val seconds = trial?.ownSpeechSeconds
        Text(when {
            seconds == null || seconds <= 0 -> stringResource(R.string.trial_level_moves)
            seconds < TrialReport.THIN_SPEECH_SECONDS -> stringResource(R.string.trial_first_read, maxOf(1, seconds / 60))
            else -> stringResource(R.string.trial_read_from, maxOf(1, seconds / 60))
        }, style = style, color = muted)
        trial?.otherLanguages?.forEach { other ->
            Text(stringResource(R.string.trial_also_spoke,
                    LanguageCatalog.ownName(other.language, nativeLanguage(LocalContext.current)), maxOf(1, other.seconds / 60)),
                style = style, color = muted)
        }
    }
}

// The routine — the way on, and the button to the plans.
@Composable
private fun RoutineCard(
    routine: List<RoutineRecipe.Line>,
    findings: List<HabitFinding>,
    advice: HabitAdvice?,
    adviceFailed: Boolean,
    onRetry: () -> Unit,
    /** False when the routine is the learner's own, untouched by a finding. */
    fromWhatWeSaw: Boolean,
    why: (StudyPlan.Block) -> String?,
) {
    val context = LocalContext.current
    val res = context.resources
    Kicker(stringResource(R.string.trial_keep_it_going), Icons.Filled.CalendarMonth)
    HabitSection(findings, advice, adviceFailed, onRetry)
    Text(stringResource(if (fromWhatWeSaw) R.string.trial_routine_from_what_we_saw else R.string.trial_routine_as_set),
        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    RoutineWeekPicture(routine.map { it.block })
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        routine.forEach { line ->
            val b = line.block
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(b.kind.icon(), contentDescription = null, tint = b.kind.color(),
                    modifier = Modifier.padding(top = 2.dp).size(20.dp).width(22.dp))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(RoutineText.titled(res, b.kind, b.minutes),
                        style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    Text(routineWeekdaySummary(b.weekdays), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    why(b)?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
    }
    Text(stringResource(R.string.trial_change_later), style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** What the rules found about how they practise, worded — firm first, the
 *  good news last. The numbers are the evidence for the routine under it. */
@Composable
private fun HabitSection(findings: List<HabitFinding>, advice: HabitAdvice?, failed: Boolean, onRetry: () -> Unit) {
    when {
        findings.isEmpty() -> Unit
        advice != null -> Column(Modifier.fillMaxWidth().background(tertiaryFill(), RoundedCornerShape(14.dp)).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.trial_how_youve_been_practising), style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
            advice.lines.forEach { line ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(habitIcon(line.tone), contentDescription = null, tint = habitColor(line.tone),
                        modifier = Modifier.padding(top = 2.dp).size(20.dp).width(22.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(line.title, style = MaterialTheme.typography.titleSmall)
                        Text(line.body, style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        failed -> OutlinedButton(onClick = onRetry) {
            Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.try_again))
        }
        else -> Row(Modifier.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            Secondary(stringResource(R.string.trial_reading_how_you_practise))
        }
    }
}

private fun habitIcon(tone: HabitFinding.Tone): ImageVector = when (tone) {
    HabitFinding.Tone.FIRM -> Icons.Filled.Error
    HabitFinding.Tone.NUDGE -> Icons.Filled.ArrowCircleRight
    HabitFinding.Tone.GOOD -> Icons.Filled.CheckCircle
}

@Composable
private fun habitColor(tone: HabitFinding.Tone): Color = when (tone) {
    HabitFinding.Tone.FIRM -> Orange
    HabitFinding.Tone.NUDGE -> MaterialTheme.colorScheme.primary
    HabitFinding.Tone.GOOD -> Green
}

/** The line being spoken, in the target language, with its native caption —
 *  under the card, above the button (iOS `captionBox`). */
@Composable
private fun CaptionBox(line: ReportNarration.Line, speaking: Boolean, showCaption: Boolean, onTap: () -> Unit) {
    val pulse = rememberInfiniteTransition(label = "narrationPulse")
    val wave by pulse.animateFloat(0.35f, 1f, infiniteRepeatable(tween(600), RepeatMode.Reverse), label = "wave")
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 8.dp)
        .background(AppSurfaces.card, ContinuousShape(14.dp)).clickable(onClick = onTap).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(if (speaking) Icons.Filled.GraphicEq else Icons.AutoMirrored.Outlined.Chat, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = 2.dp).size(14.dp).alpha(if (speaking) wave else 1f))
            Text(line.text, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        }
        if (showCaption) Text(line.caption, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 22.dp))
    }
}

// MARK: - Helpers

private fun weekday(at: Long, locale: Locale): String =
    Instant.ofEpochMilli(at).atZone(ZoneId.systemDefault()).dayOfWeek.getDisplayName(TextStyle.SHORT, locale)

private fun weekdayLetter(start: Long, offset: Int, locale: Locale): String =
    Instant.ofEpochMilli(start).atZone(ZoneId.systemDefault()).plusDays(offset.toLong())
        .dayOfWeek.getDisplayName(TextStyle.NARROW_STANDALONE, locale)

private fun dateRange(r: WeekRecap, locale: Locale): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd")
    val f = java.time.format.DateTimeFormatter.ofPattern(pattern, locale)
    val zone = ZoneId.systemDefault()
    // Seven days, as in the archive.
    return "${f.format(Instant.ofEpochMilli(r.start).atZone(zone))} – ${f.format(Instant.ofEpochMilli(r.end - 86_400_000L).atZone(zone))}"
}

// MARK: - Practice row

/**
 * "Your week" on the Today card (iOS `weekRecapRow`, 2026-10-03): the week IN
 * PROGRESS ("ready Sat, Oct 10") — its deck arrives when it closes — and a tap
 * opens the archive of every closed week behind it. Drawn once the week has
 * something in it, or there is a past week to look back on.
 */
@Composable
fun WeekRecapRow(level: CefrLevel, reloadKey: Any?) {
    val context = LocalContext.current
    var week by remember { mutableStateOf<WeekInProgress?>(null) }
    var hasPastWeeks by remember { mutableStateOf(false) }
    var showing by remember { mutableStateOf(false) }
    var reload by remember { mutableStateOf(0) }
    val asked by WeekRecapInbox.archive.collectAsStateWithLifecycle()
    LaunchedEffect(reloadKey, reload) {
        WeekRecapStore.lastWeek(context)        // freezes the closed week
        week = WeekRecapBuilder.thisWeek(context)
        hasPastWeeks = WeekRecapStore.archive(context).isNotEmpty()
    }
    // A notice tapped for a week already seen lands here.
    LaunchedEffect(asked) {
        if (asked) { WeekRecapInbox.archive.value = false; showing = true }
    }
    val w = week
    if (w != null && (w.hasActivity || hasPastWeeks)) {
        Row(Modifier.fillMaxWidth().clickable { showing = true }.padding(horizontal = 14.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.ViewAgenda, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp))
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.wr_your_week), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium)
                Text(stringResource(R.string.wr_week_in_progress_ready, weekReadyDate(w.readyAt, weekLocale(context))),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
        }
    }
    if (showing) {
        WeekRecapArchiveSheet(level) { action ->
            showing = false
            reload++
            action?.let(::performWeekRecapAction)
        }
    }
}

// MARK: - Root host

/**
 * Raises the closed week's cards — softly, a beat after the app is up, and
 * never over a call or another sheet (iOS `RootTabView.offerWeekRecap`).
 * Unasked it appears once per week and only for a week that had something in
 * it. The notice shares that one showing: tapped after the deck was seen, it
 * opens the archive instead.
 */
@Composable
fun WeekRecapHost(ready: Boolean, blocked: Boolean, level: CefrLevel, onShowing: (Boolean) -> Unit = {}) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val asked by WeekRecapInbox.asked.collectAsStateWithLifecycle()
    val debug by WeekRecapInbox.debug.collectAsStateWithLifecycle()
    val reoffer by WeekRecapInbox.reoffer.collectAsStateWithLifecycle()
    var showing by remember { mutableStateOf<WeekRecap?>(null) }
    var resumes by remember { mutableStateOf(0) }
    val stillBlocked by androidx.compose.runtime.rememberUpdatedState(blocked)
    // Every return to the foreground is a chance the week has turned.
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { resumes++ }
    }
    LaunchedEffect(ready, asked, resumes, reoffer) {
        if (!ready || showing != null) return@LaunchedEffect
        val wasAsked = asked
        WeekRecapInbox.asked.value = false
        delay(if (wasAsked) 400 else 1_200)
        val recap = WeekRecapStore.lastWeek(context)
        // The notice and the automatic slide-up share ONE showing: a notice
        // tapped after the deck was already seen opens the archive on
        // Practice, not the same deck again (iOS `offerWeekRecap`).
        if (wasAsked && WeekRecapStore.wasShown(context, recap)) {
            WeekRecapInbox.archive.value = true
            DeepLinkInbox.pending.value = DeepLinkInbox.Destination.PRACTICE
            return@LaunchedEffect
        }
        if (!wasAsked && (!recap.hasActivity || WeekRecapStore.wasShown(context, recap))) return@LaunchedEffect
        if (showing != null || stillBlocked || TrialReportStore.isShowing) return@LaunchedEffect
        showing = recap
    }
    LaunchedEffect(debug) {
        val recap = debug ?: return@LaunchedEffect
        WeekRecapInbox.debug.value = null
        showing = recap
    }
    LaunchedEffect(showing != null) { onShowing(showing != null) }
    showing?.let {
        WeekRecapSheet(it, level) { action ->
            showing = null
            action?.let(::performWeekRecapAction)
        }
    }
}

/**
 * The free minutes' report (iOS `RootTabView.offerTrialReport` and the call's
 * `trialReport` sheet): raised when the call that spent the pool closes
 * ([TrialReportInbox]), and again on a later open — a beat after the app is
 * up, never over a call or another sheet — when it was closed before its last
 * card. The account is asked fresh; the gate is [TrialReportStore.shouldOffer].
 */
@Composable
fun TrialReportHost(ready: Boolean, inCall: Boolean, blocked: Boolean, level: CefrLevel,
                    onMeasuredLevel: (String) -> Unit, voiceId: String? = null,
                    onShowing: (Boolean) -> Unit = {}) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val pending by com.roro.futurevoice.data.TrialReportInbox.pending.collectAsStateWithLifecycle()
    val preview by com.roro.futurevoice.data.TrialReportInbox.preview.collectAsStateWithLifecycle()
    var showing by remember { mutableStateOf<TrialReport?>(null) }
    // Me → Developer's preview: past every gate, over whatever is up.
    LaunchedEffect(preview) {
        val report = preview ?: return@LaunchedEffect
        com.roro.futurevoice.data.TrialReportInbox.preview.value = null
        showing = report
    }
    var resumes by remember { mutableStateOf(0) }
    val stillBlocked by androidx.compose.runtime.rememberUpdatedState(blocked)
    /** Nothing else is up — another sheet, a live call (a daily call or one
     *  launched from anywhere), or this deck already on screen (iOS
     *  `quietForTrialReport`). */
    fun quiet() = !stillBlocked && !com.roro.futurevoice.data.DailyCallScheduler.isLiveCall &&
        !TrialReportStore.isShowing
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { resumes++ }
    }
    // From the call that spent the pool: it has already asked the gate.
    LaunchedEffect(pending, inCall) {
        if (!pending || inCall || showing != null) return@LaunchedEffect
        com.roro.futurevoice.data.TrialReportInbox.pending.value = false
        showing = TrialReportStore.current(context, LanguageScope.active(context))
    }
    LaunchedEffect(ready, resumes) {
        if (!ready || showing != null || TrialReportStore.finished(context) ||
            TrialReportStore.offers(context) >= TrialReportStore.MAX_OFFERS) return@LaunchedEffect
        delay(1_500)
        // Cheapest first: a paying account (cached) or a pool not yet spent
        // never reaches the network; only a likely yes is asked fresh, since
        // a purchase a minute ago must not see the report.
        val gate = com.roro.futurevoice.data.BillingGate
        val cached = gate.snapshot() ?: return@LaunchedEffect
        if (!TrialReportStore.shouldOffer(context, cached)) return@LaunchedEffect
        val account = gate.snapshot(force = true) ?: return@LaunchedEffect
        if (!TrialReportStore.shouldOffer(context, account)) return@LaunchedEffect
        // WAIT for the screen to clear, never give up on it (iOS, prod
        // 2026-10-21: a tab's own sheet came up 2 s after the call and the
        // report was never seen).
        repeat(120) { if (showing == null && !quiet()) delay(1_000) }
        if (showing != null || !quiet()) return@LaunchedEffect
        showing = TrialReportStore.current(context, LanguageScope.active(context))
    }
    LaunchedEffect(showing != null) { onShowing(showing != null) }
    showing?.let {
        TrialReportSheet(it, level, onMeasuredLevel, voiceId) { showing = null }
    }
}
