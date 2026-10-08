package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.capture.flags.TalkCaptureFlags
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.talk.FreeTalkOpeners
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.TalkPhase
import com.roro.futurevoice.talk.TalkUiState
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.AppState
import com.roro.futurevoice.ui.HomeScreen
import com.roro.futurevoice.ui.HomeTab
import com.roro.futurevoice.ui.SummaryBoard
import com.roro.futurevoice.ui.TalkDetailScreen
import com.roro.futurevoice.ui.TalkGoalItem
import com.roro.futurevoice.ui.TalkScreen
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme
import com.roro.futurevoice.talk.GrammarFocus
import com.roro.futurevoice.talk.GrammarFocusRecord
import com.roro.futurevoice.talk.LearnerPattern
import com.roro.futurevoice.talk.TurnFix
import com.roro.futurevoice.talk.TurnSuggestion
import com.roro.futurevoice.ui.CallSettings
import com.roro.futurevoice.ui.CallSettingsSheet
import com.roro.futurevoice.ui.GrammarFocusResultRow
import com.roro.futurevoice.ui.GrammarFocusSheet
import com.roro.futurevoice.ui.GroupedCard
import com.roro.futurevoice.ui.GroupedSectionSpacer
import androidx.compose.foundation.layout.statusBarsPadding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Capture modes for the Talk area. This file owns exactly these iOS modes:
 *
 *   home
 *   home-ring
 *   home-plus
 *   home-light
 *   home-light-fresh
 *   first-call
 *   free-minutes-welcome
 *   glow
 *   tabs
 *   talk-alt
 *   talk-alt-call
 *   talk-alt-demo
 *   level-header
 *   level-sheet
 *   themes
 *   call-meter
 *   call-meter-low
 *   call-goals
 *   call-feed-fade
 *   call-goal-sheet
 *   summary-progress
 *   summary-progress-start
 *   carryover
 *   transcript-ja
 *   call-focus
 *   call-focus-sheet
 *   focus-result
 *   call-settings
 *   voice-revival
 *   voice-revival-tune
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 *
 * The call modes render the REAL `TalkScreen` from a prepared state
 * (`TalkCaptureFlags.callPreview`): the screen draws it and never starts the
 * call, so no socket and no mic are opened. iOS stages the same states from
 * sample lines.
 */
object CaptureTalk {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "home" to { ctx -> Home(ctx, "home") },
        "home-ring" to { ctx -> Home(ctx, "home-ring") },
        "home-plus" to { ctx -> Home(ctx, "home-plus") },
        "home-light" to { ctx -> Home(ctx, "home-light") },
        "home-light-fresh" to { ctx -> Home(ctx, "home-light-fresh") },
        // Talk's Discover on its Everyday chip (iOS `5b0587a`).
        "home-scenarios" to { ctx -> Home(ctx, "home-scenarios") },
        // iOS: the full RootTabView. Android's tab shell IS HomeScreen.
        "tabs" to { ctx -> Home(ctx, "tabs") },
        "first-call" to { ctx -> FirstCall(ctx) },
        "level-header" to { ctx -> LevelHeader(ctx) },
        "call-meter" to { ctx -> CallMeter(ctx, minutes = 7) },
        "call-meter-low" to { ctx -> CallMeter(ctx, minutes = 2) },
        "call-goals" to { ctx -> CallGoals(ctx) },
        "call-coach" to { ctx -> CallCoach(ctx) },
        "first-call-check" to { ctx -> FirstCallCheckShot(ctx, hard = false) },
        "first-call-check-hard" to { ctx -> FirstCallCheckShot(ctx, hard = true) },
        "call-feed-fade" to { ctx -> CallFeedFade(ctx) },
        "call-goal-sheet" to { ctx -> CallGoalSheet(ctx) },
        "call-focus" to { ctx -> CallFocus(ctx, sheet = false) },
        "call-focus-sheet" to { ctx -> CallFocus(ctx, sheet = true) },
        "focus-result" to { ctx -> FocusResult(ctx) },
        "call-settings" to { ctx -> CallSettingsShot(ctx) },
        "voice-revival" to { ctx -> Revival(ctx, tune = false) },
        "voice-revival-tune" to { ctx -> Revival(ctx, tune = true) },
        "summary-progress" to { _ -> SummaryProgress(start = false) },
        "summary-progress-start" to { _ -> SummaryProgress(start = true) },
        "carryover" to { ctx -> Carryover(ctx) },
        "glow" to { _ -> GlowGallery() },
        "themes" to { _ -> Themes() },
        // The grant said out loud, once: onboarding's paywall steps aside for
        // an account with a balance, so this is the only place the minutes
        // are ever mentioned.
        "free-minutes-welcome" to { _ ->
            com.roro.futurevoice.ui.FreeTalkWelcomeSheet(minutes = 10, onStart = {}, onDismiss = {})
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
        "level-sheet" to
            "No LevelInfoSheet on Android (the call title shows the level but opens nothing) — 4.3",
        "talk-alt" to
            "iOS design-review experiment (TalkHomeExperiment), never shipped — n/a (not an Android gap)",
        "talk-alt-call" to
            "iOS design-review experiment (TalkHomeExperiment), never shipped — n/a (not an Android gap)",
        "talk-alt-demo" to
            "iOS design-review experiment (TalkHomeExperiment), never shipped — n/a (not an Android gap)",
    )

    // MARK: - Seeding

    /** Runs [work] off the main thread once, then draws [content]. */
    @Composable
    private fun Seeded(work: suspend () -> Unit, content: @Composable () -> Unit) {
        val ready by produceState(false) {
            withContext(Dispatchers.IO) { work() }
            value = true
        }
        if (ready) content()
    }

    /** What iOS's `home`-family routes seed: vocab, sessions, news, scenarios. */
    private suspend fun seedHome(context: Context, name: String) {
        CaptureSeed.once(name) {
            CaptureSeed.seedVocab(context)
            CaptureSeed.seedSessions(context)
            CaptureSeed.seedNews(context)
            CaptureSeed.seedScenarios(context)
        }
    }

    /** The app state HomeScreen/TalkScreen are handed — signed in, set up, voiced. */
    private suspend fun appState(context: Context): AppState {
        val lang = LanguageScope.active(context)
        return AppState(
            resolvingSession = false,
            signedIn = true,
            setupComplete = true,
            persona = PersonaStore.shared(context).load(),
            personaResolved = true,
            voiceId = "capture-voice",
            targetLanguage = lang,
            enrolledLanguages = listOf(lang),
            nativeLanguage = context.getSharedPreferences("futurevoice", 0)
                .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative(),
            level = CefrLevel.B1,
        )
    }

    // MARK: - Home

    /**
     * iOS `ConversationHome.refreshAccount` under capture: `home-light*`
     * injects a Light subscriber mid-period, `home-plus` a Plus one (no
     * ring), every other capture a free account with 2000 s left.
     */
    private fun headerAccount(mode: String): AccountStatus = when {
        mode.startsWith("home-light") -> CaptureSeed.sampleLightAccount
        mode.startsWith("home-plus") -> AccountStatus(
            secondsBalance = 0, planId = "plus_monthly", subscriptionStatus = "active",
            secondsUsedPeriod = 3300, monthlyCapSeconds = 108_000,
            scenesUsedPeriod = 12, monthlyScenesCap = 120)
        else -> AccountStatus(secondsBalance = 2000, planId = null, subscriptionStatus = "inactive")
    }

    /** `-ringSeconds N` on iOS; `--ei ringSeconds N` (or `--es`) here. */
    private fun ringSeconds(context: Context): Int {
        val intent = (context as? android.app.Activity)?.intent ?: return 0
        return intent.getIntExtra("ringSeconds", -1).takeIf { it >= 0 }
            ?: intent.getStringExtra("ringSeconds")?.toIntOrNull() ?: 0
    }

    @Composable
    private fun Home(context: Context, mode: String) {
        TalkCaptureFlags.headerAccount = headerAccount(mode)
        TalkCaptureFlags.discoverTab =
            if (mode == "home-scenarios") com.roro.futurevoice.ui.DiscoverTab.EVERYDAY else null
        var state by remember { mutableStateOf<AppState?>(null) }
        Seeded(work = {
            when (mode) {
                // `-fresh` seeds nothing, so the hero ring sits at zero.
                "home-light-fresh" -> Unit
                "home-ring" -> {
                    seedHome(context, mode)
                    // Seeds only the shortfall — reinstall between runs to go DOWN.
                    val want = ringSeconds(context) - TalkTimeLog.secondsToday(context)
                    TalkTimeLog.add(context, want, LanguageScope.active(context))
                }
                "home-plus", "home-light" -> CaptureSeed.once(mode) {
                    seedHome(context, "$mode-home")
                    // The arc reads TalkTimeLog, so today is part-spent.
                    TalkTimeLog.add(context, 180, LanguageScope.active(context))
                }
                else -> seedHome(context, mode)
            }
            state = appState(context)
        }) {
            var tab by remember { mutableStateOf(HomeTab.TALK) }
            state?.let { s ->
                HomeScreen(
                    state = s,
                    onStartCall = { _, _, _ -> },
                    onOpenMe = {},
                    tab = tab,
                    onTabChange = { tab = it },
                )
            }
        }
    }

    /**
     * The real tab shell opened on [tab], over whatever [work] seeds — for
     * the other areas' tab modes (iOS `watchtab`), so they carry the same
     * title bar and tab bar a learner sees.
     */
    @Composable
    internal fun TabShot(context: Context, tab: HomeTab, work: suspend () -> Unit) {
        var state by remember { mutableStateOf<AppState?>(null) }
        Seeded(work = { work(); state = appState(context) }) {
            var current by remember { mutableStateOf(tab) }
            state?.let { s ->
                HomeScreen(state = s, onStartCall = { _, _, _ -> }, onOpenMe = {},
                    tab = current, onTabChange = { current = it })
            }
        }
    }

    // MARK: - The call (prepared states)

    private fun fluent(text: String, i: Int) = Turn(
        id = "capture-turn-$i", role = TurnRole.FLUENT_SELF, transcript = text,
        durationMs = 3000, timestamp = System.currentTimeMillis() - (20 - i) * 10_000L)

    private fun user(text: String, i: Int) = Turn(
        id = "capture-turn-$i", role = TurnRole.USER, transcript = text,
        durationMs = 5000, timestamp = System.currentTimeMillis() - (20 - i) * 10_000L)

    /** The real TalkScreen over a prepared call. */
    @Composable
    private fun Call(context: Context, preview: TalkCaptureFlags.CallPreview, topic: String = "",
                     seed: suspend () -> Unit = {}) {
        TalkCaptureFlags.callPreview = preview
        var state by remember { mutableStateOf<AppState?>(null) }
        Seeded(work = { seed(); state = appState(context) }) {
            state?.let { s ->
                TalkScreen(
                    voiceId = "capture-voice",
                    targetLanguage = s.targetLanguage,
                    nativeLanguage = s.nativeLanguage,
                    level = s.level,
                    persona = s.persona,
                    topic = topic,
                    onExit = {},
                )
            }
        }
    }

    /**
     * iOS `first-call`: the real call screen for a learner the fluent self has
     * never met (`metAt` nil) — the introduction opener on screen as text.
     */
    @Composable
    private fun FirstCall(context: Context) {
        val lang = LanguageScope.active(context)
        Call(context, TalkCaptureFlags.CallPreview(TalkUiState(
            phase = TalkPhase.LISTENING,
            turns = listOf(fluent(FreeTalkOpeners.introOpener(lang), 0)),
        )), seed = { CaptureSeed.once("first-call") { CaptureSeed.seedUnmetPersona(context) } })
    }

    /**
     * iOS `level-header`: the two-line title in a real bar over an empty
     * screen. Android's is the call screen's own title (topic · level).
     */
    @Composable
    private fun LevelHeader(context: Context) {
        Call(context, TalkCaptureFlags.CallPreview(TalkUiState(phase = TalkPhase.IDLE)),
            topic = "Ordering at a cafe")
    }

    /** iOS `call-meter` / `-low`: the remaining-minutes figure at 7 and at 2. */
    @Composable
    private fun CallMeter(context: Context, minutes: Int) {
        Call(context, TalkCaptureFlags.CallPreview(TalkUiState(
            phase = TalkPhase.LISTENING,
            level = 0.35f,
            minutesRemaining = minutes,
            turns = listOf(
                fluent("So — how did the interview go yesterday?", 0),
                user("Honestly, it went really well. I felt prepared.", 1),
            ),
        )), topic = "Job interview")
    }

    /** iOS `call-goals`: the studying chips over a call, one already said. */
    @Composable
    private fun CallGoals(context: Context) {
        Call(context, TalkCaptureFlags.CallPreview(
            TalkUiState(
                phase = TalkPhase.LISTENING,
                level = 0.35f,
                turns = listOf(
                    fluent("So — how did the interview go yesterday?", 0),
                    user("It went well. I commuted for almost an hour, though.", 1),
                ),
            ),
            // NOT PORTED: iOS draws "hectic" as claimedKnown (an empty checked
            // circle) — Android's TalkGoalItem has no such field (2.20).
            goals = listOf(
                TalkGoalItem("hectic", "hectic", isWord = true),
                TalkGoalItem("commute", "commute", isWord = true),
                TalkGoalItem("it slipped my mind", "it slipped my mind", isWord = false),
                TalkGoalItem("run me through it", "run me through it", isWord = false),
                TalkGoalItem("eventually", "eventually", isWord = true),
            ),
            goalsUsed = setOf("commute"),
        ), topic = "Job interview")
    }

    /**
     * iOS `call-coach` (`6e9eb92`): coach mode's "try saying" above the pill,
     * the listening bubble plain.
     */
    @Composable
    private fun CallCoach(context: Context) {
        val ko = (context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative()).startsWith("ko")
        Call(context, TalkCaptureFlags.CallPreview(
            TalkUiState(
                phase = TalkPhase.LISTENING,
                level = 0.35f,
                turns = listOf(
                    user("Not yet, but I want to go there next week.", 0),
                    fluent("Oh, nice! Next week will be here before you know it. Do you have a specific place in mind?", 1),
                ),
                coachReply = com.roro.futurevoice.talk.CoachReply(
                    say = "Yes, I want to try [the one in Sinjeon].",
                    meaning = if (ko) "응, [신전떡볶이] 먹어보고 싶어." else "",
                    turnId = "capture-turn-1"),
            ),
            goals = listOf(
                TalkGoalItem("total", "total", isWord = true),
                TalkGoalItem("battery", "battery", isWord = true),
                TalkGoalItem("next", "next", isWord = true),
            ),
            goalsUsed = setOf("next"),
            titleRes = R.string.lets_talk,
        ), seed = { com.roro.futurevoice.talk.CoachMode.setChoice(context, true) })
    }

    /** iOS `first-call-check[-hard]`: the after-first-call sheet, on A2. */
    @Composable
    private fun FirstCallCheckShot(context: Context, hard: Boolean) {
        var state by remember { mutableStateOf<AppState?>(null) }
        Seeded(work = { state = appState(context) }) {
            state?.let { s ->
                com.roro.futurevoice.ui.FirstCallCheckSheet(
                    targetLanguage = s.targetLanguage,
                    currentLevel = com.roro.futurevoice.data.CefrLevel.A2,
                    initialFeeling = if (hard) com.roro.futurevoice.ui.FirstCallCheck.Feeling.HARD else null,
                    onDismiss = {})
            }
        }
    }

    /**
     * iOS `call-feed-fade`: a long feed resting at its end under the call's
     * bottom bar (the screen scrolls to the last line on its own).
     * NOT PORTED: iOS's `-captureScrolled` variant (a bubble parked under the bar).
     */
    @Composable
    private fun CallFeedFade(context: Context) {
        val turns = (0 until 14).map { i ->
            if (i % 2 == 0) fluent("So — how did the interview go yesterday? Anything you'd do differently next time?", i)
            else user("Honestly, it went really well. I felt prepared. $i", i)
        }
        Call(context, TalkCaptureFlags.CallPreview(TalkUiState(
            phase = TalkPhase.LISTENING, level = 0.3f, turns = turns)))
    }

    /** iOS `call-goal-sheet`: a chip's sheet open over the call, entry stubbed. */
    @Composable
    private fun CallGoalSheet(context: Context) {
        TalkCaptureFlags.stubGoalEntry = WordLore.Entry(
            pos = "Adjective",
            senses = listOf(WordLore.Sense(pos = "형용사", meaning = "정신없이 바쁜, 빡빡한",
                note = "일정·하루처럼 '쉴 틈 없이 바쁜' 상태에 써요.")),
            examples = listOf(WordLore.Example(text = "It's been a hectic week at work.",
                meaning = "회사에서 정신없는 한 주였어요.")),
        )
        val hectic = TalkGoalItem("hectic", "hectic", isWord = true)
        Call(context, TalkCaptureFlags.CallPreview(
            TalkUiState(
                phase = TalkPhase.LISTENING,
                turns = listOf(fluent("So — how did the interview go yesterday?", 0)),
            ),
            goals = listOf(
                TalkGoalItem("commute", "commute", isWord = true),
                TalkGoalItem("it slipped my mind", "it slipped my mind", isWord = false),
                hectic,
            ),
            goalsUsed = setOf("commute"),
            openGoal = hectic,
        ))
    }

    private fun koNative(context: Context) = (context.getSharedPreferences("futurevoice", 0)
        .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative()).startsWith("ko")

    /** iOS `call-focus` sample: the grammar focus coach mode pins this call to. */
    private fun sampleFocus(context: Context): GrammarFocus {
        val ko = koNative(context)
        return GrammarFocus(
            pattern = LearnerPattern(mistake = "Yesterday I go to the office",
                correction = "Yesterday I went to the office", context = "", frequency = 3),
            label = if (ko) "과거 시제" else "Past tense",
            tip = if (ko) "어제·지난주처럼 지난 일을 말할 때는 과거형을 써요."
            else "Use the past form when you talk about yesterday or last week.",
            talks = 3,
        )
    }

    /**
     * iOS `call-focus` / `call-focus-sheet`: coach mode's grammar focus pinned
     * above the chips, one repeat already counted, and the learner's card
     * wearing the badge. iOS stages it from parts; here it is the real call
     * screen over a prepared state with coach mode on. `-sheet` opens the
     * focus sheet over it (the screen's own open flag is local state).
     */
    @Composable
    private fun CallFocus(context: Context, sheet: Boolean) {
        val ko = koNative(context)
        val focus = sampleFocus(context)
        val said = "I go to the office early yesterday, so I left at four."
        val learner = user(said, 1).copy(suggestion = TurnSuggestion(
            alternative = "I went to the office early yesterday, so I left at four.",
            reason = if (ko) "어제 일이라 과거형이 자연스러워요." else "It happened yesterday, so the past form.",
            fixes = listOf(TurnFix(was = "I go to the office", now = "I went to the office",
                why = if (ko) "과거 시제" else "Past tense")),
        ))
        Call(context, TalkCaptureFlags.CallPreview(
            TalkUiState(
                phase = TalkPhase.LISTENING,
                level = 0.3f,
                turns = listOf(fluent("Busy day? What did you do this morning?", 0), learner),
                grammarFocus = focus,
                focusRepeatTurns = setOf(learner.id),
            ),
            goals = listOf(
                TalkGoalItem("hectic", "hectic", isWord = true),
                TalkGoalItem("commute", "commute", isWord = true),
                TalkGoalItem("it slipped my mind", "it slipped my mind", isWord = false),
            ),
            goalsUsed = setOf("commute"),
            titleRes = R.string.free_talk,
        ), seed = { com.roro.futurevoice.talk.CoachMode.setChoice(context, true) })
        if (sheet) GrammarFocusSheet(focus, repeats = 1, onDismiss = {})
    }

    /**
     * iOS `focus-result`: the focus line a talk's book page carries, both
     * outcomes — one slip that came back once, one that never did. iOS stages
     * the rows in a plain list titled "Focus"; the rows are the real ones.
     */
    @Composable
    private fun FocusResult(context: Context) {
        val ko = koNative(context)
        Column(Modifier.fillMaxSize().background(AppSurfaces.ground).statusBarsPadding()
            .padding(horizontal = 16.dp).padding(top = 16.dp)) {
            Text("Focus", style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 8.dp))
            GroupedSectionSpacer()
            GroupedCard {
                GrammarFocusResultRow(GrammarFocusRecord(
                    patternKey = "a", label = if (ko) "과거 시제" else "Past tense",
                    mistake = "Yesterday I go to the office",
                    correction = "Yesterday I went to the office", repeats = 1),
                    Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
            }
            GroupedSectionSpacer()
            GroupedCard {
                GrammarFocusResultRow(GrammarFocusRecord(
                    patternKey = "b", label = if (ko) "요일 전치사" else "Prepositions with days",
                    mistake = "I have a meeting in Monday",
                    correction = "I have a meeting on Monday", repeats = 0),
                    Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
            }
        }
    }

    /**
     * iOS `call-settings`: the same real call screen as `first-call`, with the
     * settings sheet up — the sheet's detent and the live screen behind it
     * are the point. The screen's own open flag is local state, so the real
     * sheet is raised over it here, on the stored settings.
     */
    @Composable
    private fun CallSettingsShot(context: Context) {
        FirstCall(context)
        CallSettingsSheet(
            showsTranscript = CallSettings.flag(context, CallSettings.SHOWS_TRANSCRIPT),
            showsCorrections = CallSettings.flag(context, CallSettings.SHOWS_CORRECTIONS),
            showsGoalChips = CallSettings.flag(context, CallSettings.SHOWS_GOAL_CHIPS),
            coachMode = com.roro.futurevoice.talk.CoachMode.resolve(
                com.roro.futurevoice.talk.CoachMode.choice(context), CefrLevel.B1.code),
            onCoachMode = {}, onFlag = { _, _ -> }, onSpeedChange = {}, onDismiss = {},
        )
    }

    /**
     * iOS `voice-revival` / `-tune`: a parked voice brought back at the call
     * tap — the rebuild, then the speed + accent page. The real screen, held
     * on its stage (`TalkCaptureFlags.revivalStage`) so nothing is rebuilt.
     */
    @Composable
    private fun Revival(context: Context, tune: Boolean) {
        TalkCaptureFlags.revivalStage = if (tune) "tune" else "rebuilding"
        val app = remember { com.roro.futurevoice.ui.AppViewModel(context.applicationContext) }
        androidx.compose.material3.Surface(Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background) {
            com.roro.futurevoice.ui.VoiceRevivalScreen(app = app,
                purpose = com.roro.futurevoice.data.VoiceRevival.Purpose.CALL, onFinish = {})
        }
    }

    // MARK: - After the call

    /**
     * iOS `summary-progress` / `-start`: the end-of-talk board mid-build (the
     * analysis landed, counts filling in), or on its long first step.
     */
    @Composable
    private fun SummaryProgress(start: Boolean) {
        val p = if (start) SessionSummarizer.Progress() else SessionSummarizer.Progress(
            readBack = true, wroteCorrections = true, phrases = 4, wroteDrills = true)
        Box(Modifier.fillMaxSize().background(AppSurfaces.ground).padding(16.dp),
            contentAlignment = Alignment.Center) {
            SummaryBoard(p, facts = stringResource(R.string.lld_of_your_turns_lld_min, 9, 6))
        }
    }

    /** iOS `carryover`: the finished talk with a carryover from every source. */
    @Composable
    private fun Carryover(context: Context) {
        var id by remember { mutableStateOf<String?>(null) }
        Seeded(work = {
            CaptureSeed.once("carryover") { CaptureSeed.seedCarryoverSession(context) }
            id = CaptureSeed.carryoverSession?.id
        }) {
            id?.let {
                TalkDetailScreen(sessionId = it, language = LanguageScope.active(context),
                    level = CefrLevel.B1, onBack = {}, onContinue = {})
            }
        }
    }

    // MARK: - Design review

    /**
     * iOS `glow`: the call pill's Futureself surface in every state, in the
     * exact pill styling the call screen uses (156×64, clipped capsule).
     */
    @Composable
    private fun GlowGallery() {
        val context = LocalContext.current
        val theme = remember { FutureselfTheme.stored(context) }
        data class Pill(val mode: FutureselfMode, val level: Float, val icon: ImageVector, val caption: String)
        val pills = listOf(
            Pill(FutureselfMode.IDLE, 0f, Icons.Filled.Mic, "idle"),
            Pill(FutureselfMode.LISTENING, 0.35f, Icons.Filled.Stop, "listening · quiet"),
            Pill(FutureselfMode.LISTENING, 0.95f, Icons.Filled.Stop, "listening · loud"),
            Pill(FutureselfMode.THINKING, 0f, Icons.Filled.MoreHoriz, "thinking"),
            Pill(FutureselfMode.SPEAKING, 0.7f, Icons.Filled.GraphicEq, "speaking"),
        )
        Column(Modifier.fillMaxSize().background(AppSurfaces.ground),
            verticalArrangement = Arrangement.spacedBy(28.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally) {
            pills.forEach { p ->
                Column(horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(width = 156.dp, height = 64.dp).clip(CircleShape)
                        .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape),
                        contentAlignment = Alignment.Center) {
                        Futureself(mode = p.mode, level = p.level, theme = theme,
                            modifier = Modifier.fillMaxSize())
                        Icon(p.icon, contentDescription = null, modifier = Modifier.size(24.dp),
                            tint = MaterialTheme.colorScheme.onSurface)
                    }
                    Text(p.caption, style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }

    /**
     * iOS `themes`: the Futureself theme grid in its List habitat — a page
     * titled Me, one Appearance section holding the picker, and its footer.
     */
    @Composable
    private fun Themes() {
        androidx.compose.foundation.layout.Column(
            Modifier.fillMaxSize().background(AppSurfaces.ground)
                .statusBarsPadding().padding(horizontal = 16.dp)) {
            val title = stringResource(com.roro.futurevoice.R.string.me)
            Text(title, style = com.roro.futurevoice.ui.brand.DisplayFace.style(title,
                MaterialTheme.typography.displaySmall),
                modifier = Modifier.padding(start = 4.dp, top = 56.dp, bottom = 20.dp))
            com.roro.futurevoice.ui.GroupedSectionHeader(stringResource(com.roro.futurevoice.R.string.appearance))
            com.roro.futurevoice.ui.GroupedCard {
                androidx.compose.foundation.layout.Box(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                    com.roro.futurevoice.ui.FutureselfThemePicker()
                }
            }
            com.roro.futurevoice.ui.GroupedFooter(stringResource(
                com.roro.futurevoice.R.string.future_self_is_the_pixel_surface_behind_every_call_button_ta_f0338e))
        }
    }
}
