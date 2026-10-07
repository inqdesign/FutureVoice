package com.roro.futurevoice.ui

import androidx.compose.foundation.Canvas
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.graphics.Color
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Delete
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Newspaper
import com.roro.futurevoice.talk.PathIdeasContent
import com.roro.futurevoice.talk.PathIdeas
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.ScenarioIdeaCache
import androidx.compose.foundation.horizontalScroll
import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material.icons.outlined.People
import com.roro.futurevoice.BuildConfig
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.layout.layout
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import com.roro.futurevoice.ui.brand.Symbols
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.PersonAddAlt
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.filled.Tune
import com.roro.futurevoice.R
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Spacer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.School
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.ChildCare
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.IconButton
import androidx.compose.foundation.background
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.ui.brand.AppSurfaces
import androidx.compose.ui.draw.shadow
import com.roro.futurevoice.ui.brand.DiscoverRow
import com.roro.futurevoice.ui.brand.SegmentChip
import com.roro.futurevoice.ui.brand.DisplayFace
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme
import com.roro.futurevoice.ui.brand.HeroGreeting
import com.roro.futurevoice.ui.brand.TalkRing
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.NewsTopicStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.SituationTree
import androidx.compose.material3.AssistChip
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartStore
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.style.TextOverflow
import com.roro.futurevoice.data.DeepLinkInbox
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.net.NewsClient
import com.roro.futurevoice.net.TopicClient
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StarterSituation
import com.roro.futurevoice.talk.Scenario
import androidx.compose.material3.AlertDialog
import com.roro.futurevoice.talk.SuggestedTopic
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.Session

@Composable
fun RootScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val app: AppViewModel = viewModel(factory = androidx.lifecycle.viewmodel.viewModelFactory {
        initializer { AppViewModel(context.applicationContext) }
    })
    val state by app.state.collectAsStateWithLifecycle()
    // The call being on screen outlives the activity: a rotation, a dark-mode
    // switch or an app-language change recreates it, and with `remember`
    // these fell back to "not in a call", the call screen left composition
    // and its dispose hung up — the learner's talk restarted from a fresh
    // opener mid-sentence and the half left behind was saved as a book.
    val call: CallRoute = viewModel()
    var inCall by call.inCall
    var callTopic by call.topic
    var callFacts by call.facts
    var callScenarioId by call.scenarioId
    var callOpener by call.opener
    var callCast by call.cast
    var callCastVoice by call.castVoice
    /** Who the call is with, so the saved talk lands on their card. */
    var callCounterpartId by call.counterpartId
    var callFromHomeCard by call.fromHomeCard
    /** Set when a Talk-home card's call closes; the home consumes it and
     *  offers the persona-deepen sheet (iOS `maybePromptDeepen`). */
    var deepenPending by remember { mutableStateOf(false) }
    // Debug only: `--ez debugHomeCardCallEnded true` plays the moment a
    // Talk-home card's call has just closed, without a call.
    LaunchedEffect(Unit) {
        if (BuildConfig.DEBUG && (context as? android.app.Activity)?.intent
                ?.getBooleanExtra("debugHomeCardCallEnded", false) == true) deepenPending = true
    }
    var showPrivacy by remember { mutableStateOf(false) }
    val referralJoin by com.roro.futurevoice.data.ReferralJoins.pending.collectAsStateWithLifecycle()
    /** The tab shell has been reached this run (see `arriveAtTabs`). iOS
     *  hosts the referral and level-up sheets on `RootTabView`, so neither
     *  can rise over onboarding; here the root is both, so they wait. */
    var tabsArrived by remember { mutableStateOf(false) }
    if (tabsArrived) referralJoin?.let { ReferralJoinSheet(join = it, onDismiss = com.roro.futurevoice.data.ReferralJoins::dismiss) }
    // A measured level-up, announced once wherever the learner happens to be.
    if (tabsArrived) state.levelUp?.let { (from, to) ->
        LevelUpSheet(from = from, to = to, onDismiss = app::clearLevelUp)
    }
    var showPublicIntro by remember { mutableStateOf(false) }
    // The one look at the mirrored intro before anything reaches the pool,
    // raised from the Watch tab (iOS `needsIntroDecision`).
    var showIntroPreview by remember { mutableStateOf(false) }
    /** The editor was opened from the preview's "Edit first" — backing out
     *  of it undecided returns to the preview rather than dropping it. */
    var introEditFromPreview by remember { mutableStateOf(false) }
    if (showIntroPreview) {
        PublicIntroPreviewSheet(
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onPublish = app::publishIntroMirror,
            onEditFirst = {
                showIntroPreview = false
                introEditFromPreview = true
                showPublicIntro = true
            },
            onDecline = { app.declinePublicIntro(); showIntroPreview = false },
            onDismiss = { showIntroPreview = false },
        )
    }
    var showInvite by remember { mutableStateOf(false) }
    var showShadowBrowser by remember { mutableStateOf(false) }
    var showDueReview by remember { mutableStateOf(false) }
    var showCreditGuide by remember { mutableStateOf(false) }
    var showPlanPage by remember { mutableStateOf(false) }
    // Keep the learner's pool row in step with the profile — but only a row
    // they APPROVED (the Watch-tab preview's Publish). Before that nothing is
    // inserted; a row an older build put up unasked is only rewritten to the
    // current composition or taken down. Gated on a real account: an
    // anonymous session's data dies with the install.
    LaunchedEffect(state.signedIn, state.isAnonymous, state.persona, state.targetLanguage) {
        if (state.signedIn && !state.isAnonymous) app.syncPublicPersona()
    }
    val localActivity = androidx.compose.ui.platform.LocalContext.current as? android.app.Activity
    var showPeople by remember { mutableStateOf(false) }
    /** The finished-books page (iOS "Finished"), opened from Practice's header seal. */
    var finishedBooks by remember { mutableStateOf<List<FinishedBook>?>(null) }
    var recloning by remember { mutableStateOf(false) }
    var personDetailId by remember { mutableStateOf<String?>(null) }
    var clonePreview by remember { mutableStateOf(false) }
    /** Debug only: the developer email sign-in screen, opened from Welcome. */
    var devSignInOpen by remember { mutableStateOf(false) }
    /** Debug only (iOS `-cloneStage`): `--es cloneStage meet` opens the
     *  voice act on one stage with stand-in data. */
    val debugCloneStage = remember {
        if (BuildConfig.DEBUG) (context as? android.app.Activity)?.intent?.getStringExtra("cloneStage") else null
    }
    // Saveable: picking an app language recreates the activity, and iOS
    // comes back on Settings with the new language — not on the Talk tab.
    var showMe by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }
    var showDeck by remember { mutableStateOf(false) }
    /** A per-item reminder's target (iOS `.reviewItem`): the card or word it named. */
    var focusCardId by remember { mutableStateOf<String?>(null) }
    /** A talk book's "Review this talk": the deck on that talk's cards. */
    var deckSessionId by remember { mutableStateOf<String?>(null) }
    var focusStudyItem by remember { mutableStateOf<StudyDeckItem?>(null) }
    var showActivity by remember { mutableStateOf(false) }
    val routineEditorOpen by RoutineNav.editorOpen.collectAsStateWithLifecycle()
    val sayAgainPending by com.roro.futurevoice.data.PlanReminder.pendingSayItAgain.collectAsStateWithLifecycle()
    var showAssessment by remember { mutableStateOf(false) }
    var library by remember { mutableStateOf<LibraryKind?>(null) }
    /** The sentence-card list (iOS `SentencesView`), and whether the deck
     *  above it was pushed from one of its rows (back, not Done). */
    var showSentences by remember { mutableStateOf(false) }
    var deckPushed by remember { mutableStateOf(false) }
    val paywalled by BillingGate.showPaywall.collectAsStateWithLifecycle()
    val gateScope = rememberCoroutineScope()
    /** Run a metered action, or raise the paywall. See [BillingGate]. */
    fun gate(action: () -> Unit) {
        gateScope.launch { BillingGate.start(AuthRepository(), action = action) }
    }
    /** [gate] for a launch that plays a Watch scene (the revival's button
     *  then reads Continue, not Start the call). */
    fun gateScene(action: () -> Unit) {
        gateScope.launch {
            BillingGate.start(AuthRepository(),
                com.roro.futurevoice.data.VoiceRevival.Purpose.SCENE, action)
        }
    }
    // A widget tap or a review reminder arrives before anything is drawn, so
    // the Activity parks it and this reads it when there is a screen to open.
    /**
     * Which tab is up. Owned HERE, not by the home shell: every overlay (a
     * deck, a book, the Library, Activity) REPLACES the shell in the `when`
     * below, so a tab remembered inside it dies with the composition — and
     * coming back from a Practice deck dropped the learner on Talk.
     */
    var tab by remember { mutableStateOf(HomeTab.TALK) }
    // A Speech block's reminder or routine line: the Speech tab, with nothing
    // left open in front of it (iOS `consumeSpeechTap`).
    val speechPending by com.roro.futurevoice.data.PlanReminder.pendingSpeech.collectAsStateWithLifecycle()
    LaunchedEffect(speechPending) {
        if (!speechPending) return@LaunchedEffect
        com.roro.futurevoice.data.PlanReminder.pendingSpeech.value = false
        showActivity = false; showMe = false; showDeck = false; library = null; showSentences = false; deckPushed = false
        tab = HomeTab.SPEECH
    }
    val deepLink by DeepLinkInbox.pending.collectAsStateWithLifecycle()
    LaunchedEffect(deepLink) {
        when (DeepLinkInbox.consume()) {
            DeepLinkInbox.Destination.VOCABULARY -> library = LibraryKind.WORDS
            DeepLinkInbox.Destination.EXPRESSIONS -> library = LibraryKind.EXPRESSIONS
            DeepLinkInbox.Destination.REVIEW -> showDeck = true
            DeepLinkInbox.Destination.REVIEW_ITEM -> {
                val (kind, value) = DeepLinkInbox.reviewItem.value ?: (null to null)
                DeepLinkInbox.reviewItem.value = null
                when (kind) {
                    com.roro.futurevoice.data.ReviewQueue.SENTENCE -> { focusCardId = value; showDeck = true }
                    "word" -> { focusStudyItem = value?.let(StudyDeckItem::word); showDueReview = true }
                    "expression" -> { focusStudyItem = value?.let(StudyDeckItem::expression); showDueReview = true }
                    else -> showDueReview = true
                }
            }
            DeepLinkInbox.Destination.PRACTICE -> tab = HomeTab.PRACTICE
            null -> Unit
        }
    }
    var studyDeckKind by remember { mutableStateOf<StudyScheduleStore.Kind?>(null) }
    var detailSessionId by remember { mutableStateOf<String?>(null) }
    var watchScenarioId by remember { mutableStateOf<String?>(null) }
    /** The book's Watch replays the saved scene (free, no gate); the Watch
     *  tab writes a fresh take. */
    var watchReplay by remember { mutableStateOf(false) }
    var shadowLine by remember { mutableStateOf<String?>(null) }
    // Today's shadow hand and where we are in it. A dealt hand, not a
    // browser: opening everything ever said and asking the learner to choose
    // is a decision they have no basis for making.
    var shadowHand by remember { mutableStateOf<List<com.roro.futurevoice.data.ShadowPicks.Pick>>(emptyList()) }
    var shadowAt by remember { mutableIntStateOf(0) }
    var bookScenarioId by remember { mutableStateOf<String?>(null) }
    // Widget taps that carry more than a tab (iOS RootTabView "talk" /
    // "book" / "freetalk"). A free talk goes through the SAME gate the Talk ring does,
    // and waits for the voice to load rather than being dropped on a cold start.
    val widgetRoute by DeepLinkInbox.widgetRoute.collectAsStateWithLifecycle()
    LaunchedEffect(widgetRoute, state.voiceId) {
        val route = widgetRoute ?: return@LaunchedEffect
        if (route is DeepLinkInbox.WidgetRoute.FreeTalk && state.voiceId == null) return@LaunchedEffect
        DeepLinkInbox.widgetRoute.value = null
        when (route) {
            // Streak widget: the Talk tab itself, not a page left open over it.
            DeepLinkInbox.WidgetRoute.Talk -> {
                showMe = false; showDeck = false; library = null; showSentences = false; deckPushed = false; detailSessionId = null
                bookScenarioId = null; watchScenarioId = null; shadowLine = null
                tab = HomeTab.TALK
            }
            is DeepLinkInbox.WidgetRoute.Book -> {
                tab = HomeTab.PRACTICE
                showMe = false; showDeck = false; library = null; showSentences = false; deckPushed = false; watchScenarioId = null
                if (route.kind == "watch") bookScenarioId = route.id else detailSessionId = route.id
            }
            DeepLinkInbox.WidgetRoute.FreeTalk -> {
                tab = HomeTab.TALK
                gate {
                    showMe = false; showDeck = false; library = null; showSentences = false; deckPushed = false; detailSessionId = null
                    bookScenarioId = null; watchScenarioId = null; shadowLine = null
                    callTopic = ""; callFacts = emptyList(); callScenarioId = null
                    inCall = true
                }
            }
        }
    }
    val callAnswered by com.roro.futurevoice.data.DailyCallInbox.answered.collectAsStateWithLifecycle()
    LaunchedEffect(callAnswered) {
        // Answering the daily call IS starting the talk — no second tap, and
        // no overlay (Me, a deck, a book) may stand in front of it.
        if (callAnswered > 0 && state.voiceId != null) {
            showMe = false; showDeck = false; detailSessionId = null
            watchScenarioId = null; shadowLine = null; clonePreview = false
            shadowHand = emptyList(); shadowAt = 0
            callTopic = ""; callFacts = emptyList(); callScenarioId = null
            // The pre-written voicemail IS the call's first line; consumed
            // so a plain free talk later doesn't replay it.
            callOpener = com.roro.futurevoice.data.DailyCallStore.script(context).orEmpty()
            com.roro.futurevoice.data.DailyCallStore.setScript(context, null)
            inCall = true
        }
    }
    var editProfile by remember { mutableStateOf(false) }
    var editProfileStep by remember { mutableStateOf(0) }
    var dailyCallOnboarded by remember {
        mutableStateOf(OnboardingFlags.seen(context, OnboardingFlags.DAILY_CALL))
    }
    var weeklyRhythmOnboarded by remember {
        mutableStateOf(OnboardingFlags.seen(context, OnboardingFlags.WEEKLY_RHYTHM))
    }
    var onboardingPaywallSeen by remember {
        mutableStateOf(OnboardingFlags.seen(context, OnboardingFlags.PAYWALL))
    }
    // Null while unknown — the step must not flash for an account that turns
    // out to have nothing to buy, so it waits for the answer rather than
    // guessing at one.
    var onboardingNeedsPlan by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(state.voiceId, dailyCallOnboarded) {
        if (state.voiceId != null && !onboardingPaywallSeen && onboardingNeedsPlan == null) {
            // No session is "couldn't ask", never "no plan" (iOS
            // `BillingGate.load`): a signed-out read answers with an empty
            // account, which would pitch someone we merely failed to identify.
            val auth = AuthRepository()
            val account = if (auth.userId == null) null
                else runCatching { AccountStatus.load(auth) }.getOrNull()
                    ?.also { BillingGate.remember(it) }
            // Couldn't ask, or nothing to sell — step aside for good. A failed
            // lookup must not park the learner on a paywall forever; the
            // first paid tap asks the server again anyway.
            onboardingNeedsPlan = account?.needsSubscription ?: false
            if (onboardingNeedsPlan == false) {
                OnboardingFlags.markSeen(context, OnboardingFlags.PAYWALL)
                onboardingPaywallSeen = true
                // The skip is silent on screen, so it has to be loud here: a
                // free-call grant makes EVERY new account take this branch.
                val reason = when {
                    account == null -> "lookup_failed"
                    account.isEntitled -> "entitled"
                    account.unlimited -> "unlimited"
                    account.secondsBalance > 0 -> "balance"
                    else -> "unknown"
                }
                com.roro.futurevoice.core.Analytics.capture("onboarding_paywall_skipped",
                    mapOf("reason" to reason, "balance_s" to (account?.secondsBalance ?: -1).toString()))
            }
        }
    }
    var welcomePreview by remember { mutableStateOf(false) }
    /** iOS `showingAgeCheck` — see [AgeCheckSheet]. */
    var showAgeCheck by remember { mutableStateOf(false) }
    if (showAgeCheck) AgeCheckSheet(onDismiss = { showAgeCheck = false })
    // "Here is time to talk with your fluent self." The grant is otherwise
    // invisible — onboarding's paywall steps aside for any account with a
    // balance, so without this nobody is told the minutes exist (iOS
    // `ef9af00`). Once per install, and never to someone who has talked.
    var welcomeMinutes by remember { mutableStateOf<Int?>(null) }
    var startAfterWelcome by remember { mutableStateOf(false) }
    // The welcome waits behind the Talk guide on a first launch: "this is
    // Talk" reads before "here are your minutes" (iOS `welcomeAfterIntro`).
    val guideRevision by com.roro.futurevoice.data.PageIntroStore.revision.collectAsStateWithLifecycle()
    val guideUp by com.roro.futurevoice.data.PageIntroStore.showing.collectAsStateWithLifecycle()
    // What the tab root asks for on ARRIVAL (iOS `RootTabView.onAppear`),
    // once per run — the tab shell here is recomposed after every overlay
    // (Me, a deck, a call), and an `onAppear` there is not a new arrival:
    //   1. a voice with no age on record → the age check, and nothing else
    //      this run (the guide follows it; the welcome waits for next launch);
    //   2. else on Talk with its guide still due → the guide first, the
    //      welcome held behind it (`welcomeAfterIntro`);
    //   3. else the welcome check now.
    var welcomeAfterIntro by remember { mutableStateOf(false) }
    var checkWelcome by remember { mutableStateOf(false) }
    fun arriveAtTabs() {
        if (tabsArrived) return
        tabsArrived = true
        when (TabArrival.decide(
            hasVoice = state.voiceId != null,
            ageOnRecord = com.roro.futurevoice.data.ConsentStore.ageConfirmedAt(context) != null,
            onTalk = tab == HomeTab.TALK,
            talkGuideDue = BuildConfig.BUILD_TYPE != "capture" &&
                !com.roro.futurevoice.data.PageIntroStore.wasSeen(context,
                    com.roro.futurevoice.data.PageIntroStore.Page.TALK),
        )) {
            TabArrival.AGE_CHECK -> showAgeCheck = true
            TabArrival.GUIDE_THEN_WELCOME -> welcomeAfterIntro = true
            TabArrival.WELCOME -> checkWelcome = true
        }
    }
    // The held welcome follows the guide off screen (iOS `pageIntro`'s
    // onDismiss / `releaseHeldWelcome`): released once no guide is up and
    // the tab now showing has none left to offer. Re-checked a beat later,
    // because a guide is marked seen a frame before it reports itself up.
    LaunchedEffect(welcomeAfterIntro, guideUp, guideRevision, tab) {
        if (!welcomeAfterIntro || guideUp) return@LaunchedEffect
        if (com.roro.futurevoice.data.PageIntroStore.isDue(context, tab.guidePage())) return@LaunchedEffect
        delay(600)
        if (com.roro.futurevoice.data.PageIntroStore.showing.value) return@LaunchedEffect
        welcomeAfterIntro = false
        checkWelcome = true
    }
    LaunchedEffect(checkWelcome) {
        if (!checkWelcome) return@LaunchedEffect
        // Asked before the check, which marks the install shown: a repeat is
        // time ADDED to the pool, and the two read nothing alike in the funnel.
        val repeatWelcome = FreeTalkWelcome.hasBeenShown(context)
        FreeTalkWelcome.minutesToAnnounce(context)?.let { minutes ->
            com.roro.futurevoice.core.Analytics.capture("free_talk_welcome_shown",
                mapOf("minutes" to minutes, "kind" to if (repeatWelcome) "topup" else "first"))
            welcomeMinutes = minutes
        }
        checkWelcome = false
    }
    welcomeMinutes?.let { minutes ->
        FreeTalkWelcomeSheet(
            minutes = minutes,
            onStart = { startAfterWelcome = true; welcomeMinutes = null },
            onDismiss = {
                welcomeMinutes = null
                com.roro.futurevoice.core.Analytics.capture(
                    "free_talk_welcome_closed", mapOf("started" to false))
            },
        )
    }
    // "Start talking" on the sheet opens the call the sheet was about —
    // through the same gate the ring's tap meets (iOS `startFreeTalk`).
    LaunchedEffect(startAfterWelcome) {
        if (startAfterWelcome) {
            startAfterWelcome = false
            com.roro.futurevoice.core.Analytics.capture(
                "free_talk_welcome_closed", mapOf("started" to true))
            tab = HomeTab.TALK
            gate { callTopic = ""; callFacts = emptyList(); callScenarioId = null; inCall = true }
        }
    }

    // "Your week": the closed week's cards, raised once per week on the
    // first open after it turns (and on the week-turn notification), never
    // over a call or another sheet.
    val updatePending by com.roro.futurevoice.data.AppUpdateService.pending.collectAsStateWithLifecycle()
    WeekRecapHost(
        ready = state.setupComplete && state.voiceId != null && tabsArrived,
        blocked = inCall || paywalled || showIntroPreview || state.levelUp != null ||
            referralJoin != null || welcomeMinutes != null || updatePending != null || guideUp ||
            showAgeCheck,
        level = state.level,
    )

    // A PARKED voice is rebuilt at the metered tap, on top of whatever is
    // up — sheets included (see `VoiceRevival`).
    VoiceRevivalHost(app)

    val morphScope = rememberCoroutineScope()
    /** Every metered launcher from the home lands here (`mint` = an unsaved
     *  ready-made situation, saved once the gate passes). */
    fun startCall(topic: String, facts: List<String>, scenarioId: String?, mint: Scenario?) {
        // The paywall is asked here, at the TAP — every metered
        // launcher (free talk, a news story, a scenario, a widget
        // deep link) meets in this one callback, so one gate covers
        // them all. Met only as a 402, it would arrive after the call
        // screen was already up.
        gate {
            fun open() {
                callTopic = topic; callFacts = facts; callScenarioId = scenarioId
                callFromHomeCard = topic.isNotEmpty() || scenarioId != null
                // The FREE talk is the ring's own tap: its surface morphs
                // into the call pill (iOS). Every other launcher opens flat.
                if (topic.isEmpty() && scenarioId == null && tab == HomeTab.TALK)
                    TalkMorph.open(morphScope) { inCall = true }
                else inCall = true
            }
            // A ready-made situation (`StarterSituation`) is minted on
            // its first tap that gets past the gate — never before it —
            // and saved on every tap after (the row is refreshed from
            // the catalog), BEFORE the call reads it.
            if (mint == null) open()
            else gateScope.launch {
                val store = ScenarioStore.shared(context)
                val isNew = store.load(state.targetLanguage).none { it.id == mint.id }
                store.save(mint.copy(lastUsedAt = System.currentTimeMillis()), state.targetLanguage)
                StoreEvents.bump()
                if (isNew) com.roro.futurevoice.core.Analytics.capture("scenario_created",
                    mapOf("is_topic" to false, "starter" to (mint.starterId ?: "")))
                open()
            }
        }
    }
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
    // A book opens the way a pushed page does on iOS (`navigationDestination`
    // from a shelf card): it slides in from the right over the page it came
    // from, which drifts left a little; back reverses it. Only the book
    // pages move — every other screen swaps as before, and a screen that
    // sits ABOVE a book (shadowing, the deck, a scene) never animates.
    val coveredAbove = welcomePreview || clonePreview || recloning || state.resolvingSession ||
        !state.signedIn || !state.setupComplete || editProfile || shadowHand.isNotEmpty() ||
        shadowLine != null || watchScenarioId != null || showDeck
    val bookPage: BookPage = when {
        coveredAbove -> BookPage.Under(still = true)
        detailSessionId != null -> BookPage.Talk(detailSessionId!!)
        bookScenarioId != null -> BookPage.Scenario(bookScenarioId!!)
        else -> BookPage.Under(still = inCall && state.voiceId != null)
    }
    BookPushHost(bookPage) { page ->
        when (page) {
            is BookPage.Talk -> TalkDetailScreen(
                sessionId = page.id,
                language = state.targetLanguage,
                level = state.level,
                onBack = { detailSessionId = null },
                onShadow = { shadowLine = it },
                onReviewTalk = { id -> deckSessionId = id; showDeck = true },
                // Picking a talk back up is a metered call, so it goes through
                // the same gate every other launcher does.
                onContinue = { topic ->
                    gate {
                        detailSessionId = null
                        callTopic = topic; callFacts = emptyList(); callScenarioId = null
                        inCall = true
                    }
                },
            )

            is BookPage.Scenario -> ScenarioBookScreen(
                scenarioId = page.id,
                language = state.targetLanguage,
                // A fresh take costs a scene count, so the wall is asked at the
                // tap here exactly as it is on the Watch tab.
                // Watch on the book replays THE scene the book was extracted
                // from (iOS `WatchView(savedDialogue:)`): free after the first
                // listen, so no gate and no new take.
                onWatch = { id -> watchReplay = true; watchScenarioId = id },
                onTalk = { sc -> gate {
                    bookScenarioId = null
                    callTopic = sc.promptBlurb; callFacts = emptyList(); callScenarioId = sc.id
                    inCall = true
                } },
                onShadow = { shadowLine = it },
                onBack = { bookScenarioId = null },
                // The talk page sits above the book, so back returns here.
                onOpenTalk = { id -> detailSessionId = id },
            )
            is BookPage.Under -> {
    when {
        welcomePreview -> WelcomeScreen(onGetStarted = { welcomePreview = false })

        // DEBUG-only preview of the clone flow (iOS: `-onboardingPreview`):
        // the dev account already has a voice, so the real gate never shows.
        clonePreview -> CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onCloned = { clonePreview = false },
        )

        // Re-record from Me: the same flow as the first clone; the new voice
        // replaces the old one only once it is kept.
        recloning -> CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onCloned = { id -> app.onVoiceCloned(id); recloning = false },
            signedIn = state.signedIn && !state.isAnonymous,
            onBack = { recloning = false },
        )

        // Match the launch screen until we know whether there's a stored
        // session — but never while onboarding is under way or a voice act
        // is on stage (iOS `launchScreenTwin`'s vetoes).
        state.resolvingSession && !state.onboardingStarted && !state.holdVoiceOnboarding -> Loading()
        // The pitch before the ask — the short film the fluent self narrates
        // (iOS WelcomeView). Welcome gates on "has the journey begun", NOT on
        // the session: "Get started" enters onboarding account-free, and the
        // session only opens at the clone's "Use this voice". The sign-in
        // here is for returning users restoring.
        !state.signedIn && !state.onboardingStarted && !state.holdVoiceOnboarding && !devSignInOpen ->
            WelcomeScreen(
                onGetStarted = app::startOnboarding,
                // A returning learner signs in right there — the account
                // buttons take the Get started button's place, as on iOS.
                onGoogleSignIn = if (app.isGoogleConfigured) app::signInWithGoogle else null,
                onAppleSignIn = app::signIn,
                signInBusy = state.busy,
                signInError = state.error,
                // Debug only: the developer email sign-in (iOS keeps "Skip
                // sign-in (debug)" in the same spot).
                onDevSignIn = if (BuildConfig.DEBUG && BuildConfig.BUILD_TYPE != "capture") {
                    { devSignInOpen = true }
                } else null,
            )
        !state.signedIn && devSignInOpen -> SignInScreen(
            state,
            googleAvailable = app.isGoogleConfigured,
            onGoogleSignIn = app::signInWithGoogle,
            onSignIn = app::signIn,
            onDevSignIn = app::devSignIn,
        )
        // First-run answers before anything else — what to teach and how to
        // calibrate.
        !state.setupComplete -> SetupFlowScreen(
            initialNative = state.nativeLanguage,
            initialTarget = state.targetLanguage,
            initialLevel = state.level,
            // Account-free onboarding (the normal path): Welcome is just the
            // previous screen. A real account crossing back means signing
            // out, which the screen confirms first.
            signedIn = state.signedIn && !state.isAnonymous,
            onBackToWelcome = {
                devSignInOpen = false
                if (state.signedIn) app.signOut() else app.setOnboardingStarted(false)
            },
            // The pick lands NOW: this screen is the language picker, and a
            // choice that only arrives at the end leaves the learner
            // answering in a language they just said they cannot read.
            onPickNative = app::setNativeLanguage,
            onFinish = { native, target, level, goal ->
                app.completeSetup(native, target, level, goal)
                // Setup speaks the picked language through its own wrapped
                // context; the activity was attached in the DEVICE language,
                // so everything after setup (persona, voice, Talk) read
                // English to a learner who had just chosen Korean. Same cure
                // as Me → App language: a fresh context.
                val activity = localActivity as? android.app.Activity
                val want = com.roro.futurevoice.core.UILanguage.normalize(native)
                    ?.let { java.util.Locale.forLanguageTag(it) }
                val have = activity?.resources?.configuration?.locales?.get(0)
                if (activity != null && want != null && have != null &&
                    (want.language != have.language || want.script != have.script)) activity.recreate()
            },
        )
        // The persona store is still being read — hold, never flash a gate.
        !state.personaResolved -> Loading()
        // Light taps before the heavy ask (iOS order): persona cards build
        // the investment and the first call's context BEFORE the recording.
        state.persona == null -> PersonaIntakeScreen(
            initial = state.reopenedPersona ?: com.roro.futurevoice.talk.UserPersona(),
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onBackToSetup = { app.reopenSetup() },
            onFinish = app::savePersona,
            persistDraft = true,
        )
        // An anonymous session is being looked at for a voice it already
        // made — hold rather than flash the intro before the account act.
        state.signedIn && state.isAnonymous && state.restoringVoice && !state.holdVoiceOnboarding -> Loading()
        // The voice. `holdVoiceOnboarding` keeps this screen up through the
        // meet act and the sign-up after the clone id has already landed.
        // The anonymous clause is the crash/kill guard: a session is not an
        // account, and letting it through would hand someone an app whose
        // data dies with the install — the flow reopens on its sign-up act.
        // An Android user with no voice starts HERE — they clone on Android.
        (!state.restoringVoice && state.voiceId == null) || state.holdVoiceOnboarding ||
            (state.signedIn && state.isAnonymous) -> CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            // iOS `finishMeet`: release the hold, then bake the first call's
            // opener — once, at the rung the learner just chose, instead of
            // at the default and again after the pick.
            onCloned = { id ->
                app.onVoiceCloned(id); app.holdVoiceOnboarding(false); app.warmFreeTalkOpeners()
            },
            signedIn = state.signedIn && !state.isAnonymous,
            sessionAnonymous = state.signedIn && state.isAnonymous,
            existingVoiceId = state.voiceId,
            adoptedExistingAccount = state.adoptedExistingAccount,
            // Cross-stage back: reopen the persona cards, pre-filled.
            onBack = app::reopenPersona,
            onStartSession = app::ensureAnonymousSession,
            onHold = app::holdVoiceOnboarding,
            googleAvailable = app.isGoogleConfigured,
            onGoogleSignIn = app::signInWithGoogle,
            onAppleSignIn = app::signIn,
            signInBusy = state.busy,
            signInError = state.error,
            redeemedInvite = state.redeemedInvite,
            debugStage = debugCloneStage,
        )
        // The week's rhythm before the day's: when the week is looked back on
        // and tested, then (next screen) when the daily call rings. Gated on
        // the daily call too, so an existing install never sees it.
        state.voiceId != null && !dailyCallOnboarded && !weeklyRhythmOnboarded ->
            WeeklyRhythmOnboardingScreen(context) { weeklyRhythmOnboarded = true }
        // The clone's first real job, introduced right after it exists — so
        // it reads as a promise rather than a permissions request.
        state.voiceId != null && !dailyCallOnboarded ->
            DailyCallOnboardingScreen(context) { dailyCallOnboarded = true }
        // The plans, offered ONCE at the end — LAST, and only for an account
        // with something to buy. While the answer is unknown: the same blank
        // hold, never a flash of a pitch (or of the tabs) at someone who
        // isn't going to be shown one.
        state.voiceId != null && !onboardingPaywallSeen && onboardingNeedsPlan != false ->
            if (onboardingNeedsPlan == true) PaywallScreen(onDismiss = {
                OnboardingFlags.markSeen(context, OnboardingFlags.PAYWALL)
                onboardingPaywallSeen = true
            }) else Loading()

        editProfile -> PersonaIntakeScreen(
            initial = state.persona ?: com.roro.futurevoice.talk.UserPersona(),
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onBackToSetup = { editProfile = false },
            onFinish = { app.savePersona(it); editProfile = false },
            startStep = editProfileStep,
        )

        shadowHand.isNotEmpty() -> ShadowScreen(
            line = shadowHand[shadowAt].turn.transcript,
            turnId = shadowHand[shadowAt].turn.id,
            voiceId = state.voiceId ?: "",
            targetLanguage = state.targetLanguage,
            position = (shadowAt + 1) to shadowHand.size,
            onNext = if (shadowAt + 1 < shadowHand.size) ({ shadowAt += 1 }) else null,
            onBack = { shadowHand = emptyList(); shadowAt = 0 },
        )

        shadowLine != null -> ShadowScreen(
            line = shadowLine!!,
            voiceId = state.voiceId ?: "",
            targetLanguage = state.targetLanguage,
            onBack = { shadowLine = null },
        )

        watchScenarioId != null -> WatchSceneScreen(
            scenarioId = watchScenarioId!!,
            onShadow = { watchScenarioId = null; shadowLine = it },
            onStudy = { id -> watchScenarioId = null; bookScenarioId = id },
            voiceId = state.voiceId ?: "",
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            proficiency = state.level.code,
            onBack = { watchScenarioId = null },
            replaySaved = watchReplay,
        )

        // Above the book: "Review this talk" opens the deck from a book page,
        // and back from the deck returns to that page.
        showDeck -> DrillDeckScreen(
            language = state.targetLanguage,
            persona = state.persona,
            nativeLanguage = state.nativeLanguage,
            voiceId = state.voiceId ?: "",
            onShadow = { showDeck = false; focusCardId = null; deckSessionId = null; shadowLine = it },
            focusCardId = focusCardId,
            sessionId = deckSessionId,
            onBack = { showDeck = false; focusCardId = null; deckSessionId = null; deckPushed = false },
            pushed = deckPushed,
        )

        // Under the deck, so a row's card opens over the list and back
        // returns to it (iOS pushes `DrillView(source: .card)`).
        showSentences -> SentencesScreen(
            language = state.targetLanguage,
            onOpenCard = { id -> focusCardId = id; deckPushed = true; showDeck = true },
            onBack = { showSentences = false },
        )

        library != null -> LibraryScreen(
            kind = library!!,
            language = state.targetLanguage,
            onShadow = { library = null; shadowLine = it },
            onBack = { library = null },
        )

        showAssessment -> AssessmentScreen(
            language = state.targetLanguage,
            onBack = { showAssessment = false },
        )

        // A routine reminder's "say it again": which talk (iOS `SayItAgainPicker`).
        sayAgainPending -> SayItAgainPicker(
            language = state.targetLanguage,
            onClose = { com.roro.futurevoice.data.PlanReminder.pendingSayItAgain.value = false },
        )

        // The routine editor opened from somewhere other than the routine page
        // (the Review tab's Today card — iOS `e1b3501`).
        routineEditorOpen -> WeeklyPlanEditor(onClose = { RoutineNav.editorOpen.value = false })

        showActivity -> ActivityScreen(
            language = state.targetLanguage,
            onOpenTalk = { showActivity = false; detailSessionId = it },
            onBack = { showActivity = false },
            // Every routine line is a door to that kind of practice.
            onStartTalk = { showActivity = false; DeepLinkInbox.widgetRoute.value = DeepLinkInbox.WidgetRoute.FreeTalk },
            onOpenReview = { showActivity = false; showDueReview = true },
            onOpenTest = { showActivity = false; tab = HomeTab.PRACTICE },
        )

        // Everything snoozed whose time has come, both kinds together — the
        // promise the learner made to themselves, kept.
        showDueReview -> StudyDeckHost(
            kind = null,
            language = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            level = state.level,
            focus = focusStudyItem,
            onBack = { showDueReview = false; focusStudyItem = null },
        )

        studyDeckKind != null -> StudyDeckHost(
            kind = studyDeckKind!!,
            language = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            level = state.level,
            onBack = { studyDeckKind = null },
        )

        personDetailId != null -> CounterpartDetailScreen(
            counterpartId = personDetailId!!,
            language = state.targetLanguage,
            onOpenBook = { bookScenarioId = it },
            onBack = { personDetailId = null },
            // A tapped idea closes the People page and opens Watch's writing
            // door with that person and that line (iOS 19b7882).
            onPickIdea = { person, line ->
                WatchComposeRequest.pending.value = person to line
                personDetailId = null; showPeople = false; tab = HomeTab.WATCH
            },
        )

        showPeople -> FindPeopleScreen(
            language = state.targetLanguage,
            persona = state.persona,
            onOpenPerson = { personDetailId = it },
            onTalk = { p, meet ->
                callCast = com.roro.futurevoice.talk.ConversationEngine.Cast(
                    name = p.display_name, intro = p.intro, location = p.location,
                    occupation = p.occupation, interests = p.interests,
                    conversationStyle = p.conversation_style,
                    commonGround = com.roro.futurevoice.talk.CommonGround.block(state.persona, com.roro.futurevoice.talk.CommonGround.of(p)))
                callCastVoice = p.voice_preset_id.takeIf { it.isNotBlank() }
                // The talk saves as an ordinary Session carrying this, so the
                // person's card lists it and every review mechanism works on
                // it for free. The local row's id IS the remote persona's.
                callCounterpartId = p.id
                gate {
                    meet()
                    callTopic = ""; callFacts = emptyList(); callScenarioId = null
                    showPeople = false; inCall = true
                }
            },
            // Watch on a person (iOS `WatchTab` → `freeTalkScenario(with:)`):
            // a scene of the two of them, past the hellos. Gated as a SCENE —
            // it writes a fresh take — and the scenario is reused per person,
            // so every watch lands in the same book.
            onWatch = { meet -> gateScene {
                val person = meet()
                gateScope.launch {
                    // On disk before the scene reads it (the card's own save
                    // is fire-and-forget; this one is awaited, idempotent).
                    com.roro.futurevoice.data.CounterpartStore.shared(context).save(person)
                    val sc = meetingScenario(context, person, state.targetLanguage)
                    showPeople = false; watchReplay = false; watchScenarioId = sc.id
                }
            } },
            onBack = { showPeople = false },
        )

        // Above Me, so backing out of these lands on Me rather than the tabs.
        // Below the book branches on purpose: a book opened from here comes
        // back to this page, as a pushed page does on iOS.
        finishedBooks != null -> FinishedBooksScreen(
            books = finishedBooks!!,
            onOpen = { book ->
                if (book.isTalk) detailSessionId = book.id else bookScenarioId = book.id
            },
            onBack = { finishedBooks = null },
        )

        showCreditGuide -> CreditGuideScreen(onBack = { showCreditGuide = false })

        showPlanPage -> PlanPageScreen(
            onOpenCreditGuide = { showCreditGuide = true },
            onOpenInvite = { showInvite = true },
            onBack = { showPlanPage = false },
        )

        showInvite -> InviteScreen(onBack = { showInvite = false })

        showShadowBrowser -> ShadowBrowserScreen(
            language = state.targetLanguage,
            onShadow = { turn ->
                showShadowBrowser = false
                shadowHand = listOf(com.roro.futurevoice.data.ShadowPicks.Pick(turn, "")); shadowAt = 0
            },
            onBack = { showShadowBrowser = false },
        )

        showPublicIntro -> PublicIntroScreen(
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            onBack = {
                showPublicIntro = false
                if (introEditFromPreview && app.needsIntroDecision()) showIntroPreview = true
                introEditFromPreview = false
            },
            onDecided = if (introEditFromPreview) ({
                showPublicIntro = false; introEditFromPreview = false
            }) else null,
        )

        showPrivacy -> PrivacyScreen(
            voiceId = state.voiceId,
            // Withdrawing deletes the model, so the app has no voice to hold
            // a call with — the flow has to ask for a new one, which is what
            // reopening setup does.
            onVoiceDeleted = { showPrivacy = false; showMe = false; app.reopenSetup() },
            onBack = { showPrivacy = false },
        )

        showMe -> MeScreen(
            email = state.email,
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onSavePersona = app::savePersona,
            enrolledLanguages = state.enrolledLanguages,
            onSwitchLanguage = app::switchLanguage,
            onAddLanguage = app::addLanguage,
            onSetLevel = app::setLevel,
            hasVoice = state.voiceId != null,
            onRerecordVoice = { showMe = false; recloning = true },
            onPickAppLanguage = { code ->
                app.setNativeLanguage(code)
                // Every string on screen was resolved from a context built at
                // attach time; only a fresh one speaks the new language.
                (localActivity as? android.app.Activity)?.recreate()
            },
            onOpenPeople = { showMe = false; showPeople = true },
            onOpenPublicIntro = { showPublicIntro = true },
            onOpenPlanPage = { showPlanPage = true },
            voiceId = state.voiceId,
            voiceAccentId = state.voiceAccentId,
            onAccentApplied = app::adoptRemixedVoice,
            onEditProfile = { editProfileStep = 0; editProfile = true },
            onEditNotes = { editProfileStep = 1; editProfile = true },
            onOpenPaywall = { BillingGate.showPaywall.value = true },
            onSignOut = { showMe = false; app.signOut() },
            onOpenPrivacy = { showPrivacy = true },
            onRestored = app::adoptRestoredData,
            onBack = { showMe = false },
        )

        inCall && state.voiceId != null ->
          Box(Modifier.fillMaxSize().graphicsLayer {
              alpha = if (TalkMorph.active) TalkMorph.callAlpha.value else 1f }) {
            TalkScreen(
                voiceId = state.voiceId!!,
                targetLanguage = state.targetLanguage,
                nativeLanguage = state.nativeLanguage,
                level = state.level,
                persona = state.persona,
                topic = callTopic,
                newsFacts = callFacts,
                scenarioId = callScenarioId,
                initialOpener = callOpener,
                cast = callCast,
                castVoiceId = callCastVoice,
                counterpartId = callCounterpartId,
                onExit = {
                    // A call that flew in from the ring flies back to it.
                    TalkMorph.close(morphScope) {
                        if (callFromHomeCard) deepenPending = true
                        callFromHomeCard = false
                        inCall = false; callTopic = ""; callFacts = emptyList()
                        callScenarioId = null; callOpener = ""; callCast = null
                        callCastVoice = null; callCounterpartId = null
                    }
                },
            )
          }

        else -> {
          // Entering the tabs with a voice but no age on record (iOS
          // `RootTabView.onAppear` → `showingAgeCheck`): the age check takes
          // this visit; the tab's guide waits behind it.
          // The arrival waits for the voice: a restore from the cloud puts
          // the tabs up before the voice id is known, and judged then the
          // age check (voice + no age) was always skipped. iOS only ever
          // reaches `RootTabView` with a voice.
          LaunchedEffect(state.voiceId, state.restoringVoice) {
              if (state.voiceId != null && !state.restoringVoice) arriveAtTabs()
          }
          HomeScreen(
            state = state,
            onStartCall = { topic, facts, scenarioId -> startCall(topic, facts, scenarioId, null) },
            onStartStarter = { sc -> startCall(sc.promptBlurb, emptyList(), sc.id, sc) },
            onOpenMe = { showMe = true },
            onOpenBook = { bookScenarioId = it },
            onOpenPeople = { showPeople = true },
            onOpenFinished = { finishedBooks = it },
            onOpenActivity = { showActivity = true },
            onOpenAssessment = { showAssessment = true },
            tab = tab,
            onTabChange = {
                tab = it
                com.roro.futurevoice.core.Analytics.capture("screen_viewed", mapOf("screen" to it.name.lowercase()))
                // Nothing about this learner reaches the pool until they have
                // seen the paragraph a stranger's phone would speak as "them".
                if (it == HomeTab.WATCH && app.needsIntroDecision()) showIntroPreview = true
            },
            onOpenDeck = { showDeck = true },
            onOpenWords = { studyDeckKind = StudyScheduleStore.Kind.WORD },
            onOpenExpressions = { studyDeckKind = StudyScheduleStore.Kind.EXPRESSION },
            onOpenTalk = { detailSessionId = it },
            onWatch = { id -> gateScene { watchReplay = false; watchScenarioId = id } },
            onClonePreview = { clonePreview = true },
            onWelcomePreview = { welcomePreview = true },
            onSavePersona = app::savePersona,
            onMeasuredLevel = app::applyMeasuredLevel,
            onShadowHand = { shadowHand = it; shadowAt = 0 },
            onShadowAll = { showShadowBrowser = true },
            // The dictionaries. Until now the library had no in-app entrance
            // at all — only the widget's deep link reached it.
            onOpenWordsAll = { library = LibraryKind.WORDS },
            onOpenExpressionsAll = { library = LibraryKind.EXPRESSIONS },
            onOpenSentencesAll = { showSentences = true },
            onOpenDueReview = { showDueReview = true },
            // A book's Grammar chapter: that talk's sentence cards.
            onOpenSessionDeck = { deckSessionId = it; showDeck = true },
            onSwitchLanguage = app::switchLanguage,
            // Adding one asks for a level, which is Me's sheet — the home
            // header is not the place for a form.
            onAddLanguage = { showMe = true },
            deepenPending = deepenPending,
            onDeepenConsumed = { deepenPending = false },
            // A tab's first-visit guide never rises over a sheet the root owns.
            guideBlocked = paywalled || showIntroPreview || state.levelUp != null ||
                referralJoin != null || welcomeMinutes != null || updatePending != null || showAgeCheck,
        )
        }
    }
            }
        }
    }
    // The plans, OVER whatever raised them (iOS presents `PaywallView` as a
    // sheet from the screen on top). It used to be one branch of the page
    // switch above, BELOW the shadow, scene and deck pages — so a 402 there
    // set the flag and nothing appeared until the page was closed, and a
    // branch that replaced the page would have thrown away a scene mid-play
    // (re-entering it writes a fresh take, a second scene count).
    if (paywalled) PaywallDialog(onDismiss = { BillingGate.showPaywall.value = false })
    TalkMorphOverlay(inCall = inCall)
    }
}

@Composable
private fun Loading() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
internal fun SignInScreen(
    state: AppState,
    googleAvailable: Boolean = false,
    onGoogleSignIn: (android.content.Context) -> Unit = {},
    onSignIn: () -> Unit,
    onDevSignIn: (String, String) -> Unit,
) {
    val activityContext = LocalContext.current
    var devEmail by remember { mutableStateOf("") }
    var devPassword by remember { mutableStateOf("") }
    Box(Modifier.fillMaxSize().systemBarsPadding().imePadding().padding(24.dp),
        contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("nawana", style = MaterialTheme.typography.headlineMedium)
            Text(
                stringResource(R.string.sign_in_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            // Apple first, then Google — iOS's order.
            Button(onClick = onSignIn, enabled = !state.busy, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(if (state.busy) R.string.opening_ellipsis else R.string.continue_with_apple))
            }
            if (googleAvailable) {
                Button(onClick = { onGoogleSignIn(activityContext) }, enabled = !state.busy,
                    modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(if (state.busy) R.string.opening_ellipsis else R.string.continue_with_google))
                }
            }
            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
            // Emulator escape hatch while Apple web-OAuth setup is pending.
            // Debug builds only — this whole block is compiled out of release,
            // and production accounts are Apple-only so email reaches nothing real.
            if (BuildConfig.DEBUG && BuildConfig.BUILD_TYPE != "capture") {
                OutlinedTextField(
                    value = devEmail,
                    onValueChange = { devEmail = it },
                    label = { Text("Dev email") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = devPassword,
                    onValueChange = { devPassword = it },
                    label = { Text("Dev password") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                TextButton(
                    onClick = { onDevSignIn(devEmail, devPassword) },
                    enabled = devEmail.isNotBlank() && devPassword.isNotBlank() && !state.busy,
                ) { Text("Dev sign-in") }
            }
        }
    }
}

private data class PendingLaunch(val topic: String, val facts: List<String>, val scenarioId: String?,
                                  /** An unsaved ready-made situation, saved once the gate passes. */
                                  val mint: Scenario? = null)

/** The four verbs, in the order the product does them. Internal so the
 *  capture build can open the shell on a tab. */
internal enum class HomeTab(val label: Int) {
    TALK(R.string.talk),
    // Speech sits second, as on iOS (Talk · Speech · Watch · Review · Progress).
    SPEECH(R.string.speech_d00d85),
    WATCH(R.string.watch),
    // "Review" since iOS 2026-09-30 (RootTabView): the tab is the review home.
    PRACTICE(R.string.review), PROGRESS(R.string.progress)
}

/**
 * The app shell — `RootTabView`: Talk · Watch · Practice · Progress,
 * do → create → review → measure. Me opens from the Talk header, as on iOS.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HomeScreen(
    state: AppState,
    onStartCall: (topic: String, newsFacts: List<String>, scenarioId: String?) -> Unit,
    /** A ready-made situation (`StarterSituation`), saved only once the tap passes the gate. */
    onStartStarter: (Scenario) -> Unit = {},
    onOpenMe: () -> Unit,
    onOpenPractice: () -> Unit = {},
    onOpenDeck: () -> Unit = {},
    onOpenWords: () -> Unit = {},
    onOpenExpressions: () -> Unit = {},
    onOpenTalk: (String) -> Unit = {},
    onWatch: (String) -> Unit = {},
    onOpenPeople: () -> Unit = {},
    /** Practice's header seal → the finished-books page, with the books it counted. */
    onOpenFinished: (List<FinishedBook>) -> Unit = {},
    onOpenActivity: () -> Unit = {},
    onOpenAssessment: () -> Unit = {},
    /** Hoisted by the root — see the comment on its declaration there. */
    tab: HomeTab,
    onTabChange: (HomeTab) -> Unit,
    onOpenBook: (String) -> Unit = {},
    onClonePreview: () -> Unit = {},
    onWelcomePreview: () -> Unit = {},
    onSavePersona: (com.roro.futurevoice.talk.UserPersona) -> Unit = {},
    onMeasuredLevel: (String) -> Unit = {},
    onShadowHand: (List<com.roro.futurevoice.data.ShadowPicks.Pick>) -> Unit = {},
    onShadowAll: () -> Unit = {},
    onOpenWordsAll: () -> Unit = {},
    onOpenExpressionsAll: () -> Unit = {},
    onOpenSentencesAll: () -> Unit = {},
    onOpenDueReview: () -> Unit = {},
    onOpenSessionDeck: (String) -> Unit = {},
    onSwitchLanguage: (String) -> Unit = {},
    onAddLanguage: () -> Unit = {},
    /** Which shelf Practice opens on — the capture harness's seam. */
    initialPracticeShelf: Shelf = Shelf.STUDYING,
    /** A root-owned sheet is up — the tab's first-visit guide waits. */
    guideBlocked: Boolean = false,
    /** A Talk-home card's call has just closed (see [CallRoute.fromHomeCard]). */
    deepenPending: Boolean = false,
    onDeepenConsumed: () -> Unit = {},
) {
    val context = LocalContext.current
    var showDeepen by remember { mutableStateOf(false) }
    // "Why & how" — each tab's guide, the first time it is opened (iOS
    // `RootTabView.offerPageIntro`).
    PageIntroHost(tab.guidePage(), blocked = guideBlocked || showDeepen)

    // The call's first word, on disk before the tap. Synthesizing the
    // openers here costs one round trip per NEW line, once, and takes the
    // gateway's own ElevenLabs round trip out of the front of every call
    // (iOS `26a246c`). A line already cached costs nothing.
    LaunchedEffect(state.voiceId, state.targetLanguage, tab) {
        if (tab != HomeTab.TALK) return@LaunchedEffect
        val voice = state.voiceId ?: return@LaunchedEffect
        runCatching {
            com.roro.futurevoice.talk.FreeTalkOpeners(context).warmFirstCall(
                state.targetLanguage, state.persona?.displayName, state.level, voice,
                firstMeeting = state.persona?.metAt == null)
        }
    }

    // Auto-present exactly once, right after the first talk ends — the moment
    // the "richer persona = more real talks" pitch has lived evidence behind
    // it. Before that it is a promise, and asked in onboarding it is a form.
    // Asked only as a Talk-home card's call closes (iOS `callLaunch`'s
    // onDismiss → `maybePromptDeepen`, 0.7 s late so the call is gone) —
    // never on opening the app, where it landed on top of the welcome, the
    // week's deck or the age check.
    var deepenAsk by remember { mutableStateOf(false) }
    LaunchedEffect(deepenPending) {
        if (deepenPending) { onDeepenConsumed(); deepenAsk = true }
    }
    LaunchedEffect(deepenAsk) {
        if (!deepenAsk) return@LaunchedEffect
        kotlinx.coroutines.delay(700)
        val prefs = context.getSharedPreferences("futurevoice", 0)
        val prompted = prefs.getBoolean("futurevoice.personaDeepenPrompted", false)
        val talks = com.roro.futurevoice.data.SessionStore.shared(context)
            .load(state.targetLanguage).count { it.endedAt != null }
        if (!prompted && talks > 0 && personaNeedsDepth(state.persona)) {
            prefs.edit().putBoolean("futurevoice.personaDeepenPrompted", true).apply()
            showDeepen = true
        }
        deepenAsk = false
    }

    if (showDeepen) {
        PersonaDeepenSheet(
            persona = state.persona,
            nativeLanguage = state.nativeLanguage,
            targetLanguage = state.targetLanguage,
            onSave = onSavePersona,
            onDismiss = { showDeepen = false },
        )
    }

    var pendingLaunch by remember { mutableStateOf<PendingLaunch?>(null) }
    var micDenied by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) pendingLaunch?.let { p ->
            p.mint?.let(onStartStarter) ?: onStartCall(p.topic, p.facts, p.scenarioId)
        }
        // A refusal has to be answerable: the tap did nothing and nothing on
        // screen said why, and the only route back is the system settings.
        else micDenied = true
        pendingLaunch = null
    }
    if (micDenied) {
        val ctx = LocalContext.current
        AlertDialog(
            onDismissRequest = { micDenied = false },
            title = { Text(stringResource(R.string.microphone_access_needed)) },
            text = { Text(stringResource(R.string.nawana_needs_the_microphone_and_speech_recognition_to_hear_y_121253)) },
            confirmButton = {
                TextButton(onClick = {
                    micDenied = false
                    ctx.startActivity(android.content.Intent(
                        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.fromParts("package", ctx.packageName, null))
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                }) { Text(stringResource(R.string.open_settings)) }
            },
            dismissButton = {
                TextButton(onClick = { micDenied = false }) { Text(stringResource(R.string.not_now)) }
            })
    }
    fun launch(topic: String, facts: List<String>, scenarioId: String? = null, mint: Scenario? = null) {
        pendingLaunch = PendingLaunch(topic, facts, scenarioId, mint)
        permission.launch(Manifest.permission.RECORD_AUDIO)
    }

    Scaffold(
        topBar = {
            if (tab == HomeTab.TALK) {
                // CENTER-aligned on Talk only: the streak is the one Today
                // stat that lives up here and it holds the MIDDLE (iOS puts it
                // in `.principal`). A plain TopAppBar left-aligns its title,
                // which clustered the streak against the language chip and
                // left the bar lopsided.
                CenterAlignedTopAppBar(
                    colors = AppSurfaces.topBarColors(),
                    // No title on Talk: the hero's time-of-day question IS the
                    // greeting, and a title above it doubled it (iOS). The bar
                    // carries just the controls — language · streak · account.
                    title = { StreakChip(language = state.targetLanguage, onClick = onOpenActivity) },
                    navigationIcon = {
                        // The language being practised, and the way to change
                        // it. It used to be a label that opened Me, which is
                        // three taps from the thing it names. The CODE, not the
                        // endonym: iOS puts a globe and two letters here, and an
                        // endonym ("English", "Deutsch") is as wide as the
                        // streak chip it sits beside.
                        var languageMenu by remember { mutableStateOf(false) }
                        Box {
                            HeaderButton(state.targetLanguage.uppercase(),
                                icon = Icons.Filled.Language,
                                onClick = { languageMenu = true })
                            com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = languageMenu, onDismissRequest = { languageMenu = false }) {
                                state.enrolledLanguages.forEach { code ->
                                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                                        text = { Text(LanguageCatalog.endonym(code)) },
                                        leadingIcon = {
                                            // iOS: `Label(name, systemImage: "checkmark")` — the
                                            // tick in ink, on the trailing side of the row.
                                            if (code == state.targetLanguage) {
                                                Icon(Icons.Filled.Check, contentDescription = null)
                                            }
                                        },
                                        onClick = { languageMenu = false; onSwitchLanguage(code) })
                                }
                                com.roro.futurevoice.ui.brand.IosMenuDivider()
                                com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                                    text = { Text(stringResource(R.string.add_a_language)) },
                                    leadingIcon = { Icon(Icons.Filled.Add, contentDescription = null) },
                                    onClick = { languageMenu = false; onAddLanguage() })
                            }
                        }
                    },
                    actions = {
                        // The learner's own face opens their own page — iOS's
                        // header control, not a text label.
                        HeaderAvatar(initials = state.persona?.displayName.orEmpty(),
                            onClick = onOpenMe)
                    },
                )
            } else {
                // Every other tab carries iOS's `.inlineLarge` title: big,
                // LEFT-aligned, in the display face. Centred and at label size
                // it read as a toolbar caption rather than the page's name.
                TopAppBar(
                    colors = AppSurfaces.topBarColors(),
                    title = {
                        val title = stringResource(tab.label)
                        Text(title, style = DisplayFace.style(title,
                            MaterialTheme.typography.headlineMedium))
                    },
                    actions = {
                        // iOS 26 toolbar buttons: white glass, a circle for an
                        // icon and a capsule for icon + count.
                        // The people page opens from the WATCH header, as on iOS.
                        if (tab == HomeTab.WATCH) {
                            com.roro.futurevoice.ui.brand.IosGlassButton(onClick = onOpenPeople,
                                circle = true, modifier = Modifier.padding(end = 12.dp)) {
                                // iOS draws `person.2` as an OUTLINE here.
                                Icon(Icons.Outlined.People,
                                    contentDescription = stringResource(R.string.people),
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(24.dp))
                            }
                        }
                        // The week's things — put off, the week, the tests — as
                        // icons with a dot (iOS `weekToolbar`, 2026-10-03). The
                        // finished books are a shelf chip now, not a seal here.
                        if (tab == HomeTab.SPEECH) com.roro.futurevoice.ui.speech.SpeechHeaderAction()
                        if (tab == HomeTab.PRACTICE) {
                            ReviewHeaderActions(language = state.targetLanguage, level = state.level,
                                onOpenPutOff = onOpenDueReview)
                        }
                    },
                )
            }
        },
        // No bottomBar and no bottom inset: the page runs to the bottom of the
        // screen and the tab bar FLOATS over it, as iOS 26's does. The top bar
        // takes the status bar itself.
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { padding ->
      Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
        // Each tab is built on its first visit and then KEPT, as iOS's
        // TabView keeps its pages (scroll position included). Rebuilding the
        // page on every switch stalled the main thread for 150-300 ms, and the
        // tab bar's sliding highlight jumped straight to its end in that gap.
        val visited = remember { mutableSetOf<HomeTab>() }
        visited += tab
        HomeTab.entries.filter { it in visited }.forEach { t ->
          androidx.compose.runtime.key(t) {
            val pageScroll = rememberScrollState()
            // Capture `home-scenarios` only: Talk opens scrolled to the
            // bottom, where the Everyday list ends (iOS
            // `defaultScrollAnchor(.bottom)`).
            if (t == HomeTab.TALK && com.roro.futurevoice.capture.flags.TalkCaptureFlags.discoverTab != null) {
                LaunchedEffect(pageScroll.maxValue) { pageScroll.scrollTo(pageScroll.maxValue) }
            }
            // Review and Progress are chip-tab PAGERS: each page scrolls
            // itself under a pinned chip bar (iOS), so the tab itself doesn't.
            val paged = t == HomeTab.PRACTICE || t == HomeTab.PROGRESS
            Column(
                Modifier.padding(top = padding.calculateTopPadding()).fillMaxSize()
                    // A hidden tab stays composed but is neither measured nor
                    // placed: nothing drawn, no touches.
                    .then(if (t == tab) Modifier else Modifier.layout { _, _ -> layout(0, 0) {} })
                    .then(if (paged) Modifier
                        else Modifier.verticalScroll(pageScroll).padding(horizontal = 20.dp)),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                when (t) {
                    HomeTab.TALK -> {
                        TalkHero(
                            state = state,
                            enabled = state.voiceId != null,
                            onTap = { launch("", emptyList()) },
                            onOpenActivity = onOpenActivity,
                        )
                        // Before the first talk the page explains itself; after it,
                        // the only card above Discover is the one asking for the
                        // learner's life. Never both — iOS's `else if`.
                        val revision by StoreEvents.revision.collectAsStateWithLifecycle()
                        var talkCount by remember { mutableStateOf(-1) }
                        LaunchedEffect(state.targetLanguage, revision) {
                            talkCount = com.roro.futurevoice.data.SessionStore.shared(context)
                                .load(state.targetLanguage).count { it.endedAt != null }
                        }
                        if (talkCount == 0) {
                            FirstRunCard()
                        } else if (personaNeedsDepth(state.persona)) {
                            DeepenRow(onClick = { showDeepen = true })
                        }
                        // One Discover section, two chips — what to talk about
                        // today: the day's stories, or a situation you built.
                        DiscoverSection(
                            state = state,
                            enabled = state.voiceId != null,
                            onSavePersona = onSavePersona,
                            onPickNews = { topic -> launch(topic.title, topic.facts.orEmpty()) },
                            onPickScenario = { sc -> launch(sc.promptBlurb, emptyList(), sc.id) },
                            onPickStarter = { sc -> launch(sc.promptBlurb, emptyList(), sc.id, mint = sc) },
                            // They all live on Watch — that IS the collection.
                            onAllScenarios = { onTabChange(HomeTab.WATCH) },
                        )
                        state.error?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error)
                        }
                        if (BuildConfig.DEBUG && BuildConfig.BUILD_TYPE != "capture") {
                            TextButton(onClick = onClonePreview) { Text("Clone flow (debug)") }
                            TextButton(onClick = onWelcomePreview) { Text("Welcome (debug)") }
                        }
                    }

                    // Speech: read a script aloud under a prompter that follows
                    // the voice, and get the take scored.
                    HomeTab.SPEECH -> com.roro.futurevoice.ui.speech.SpeechTabBody(
                        language = state.targetLanguage,
                        native = state.nativeLanguage,
                        level = state.level,
                    )

                    // Watch: simulate the situation BEFORE it happens. Scenarios
                    // are reusable templates — a tap writes a fresh take.
                    HomeTab.WATCH -> WatchTabBody(
                        language = state.targetLanguage,
                        enabled = state.voiceId != null,
                        onWatch = onWatch,
                    )

                    HomeTab.PRACTICE -> PracticeBody(
                        initialShelf = initialPracticeShelf,
                        level = state.level,
                        language = state.targetLanguage,
                        onOpenDeck = onOpenDeck,
                        onOpenWords = onOpenWords,
                        onOpenExpressions = onOpenExpressions,
                        onOpenScenarioBook = onOpenBook,
                        onOpenTalk = onOpenTalk,
                        onShadowHand = onShadowHand,
                        onShadowAll = onShadowAll,
                        onOpenWordsAll = onOpenWordsAll,
                        onOpenExpressionsAll = onOpenExpressionsAll,
                        onOpenSentencesAll = onOpenSentencesAll,
                        onOpenDueReview = onOpenDueReview,
                        onOpenSessionDeck = onOpenSessionDeck,
                        nativeLanguage = state.nativeLanguage,
                        onTalkScenario = { sc -> onStartCall(sc.promptBlurb, emptyList(), sc.id) },
                    )

                    HomeTab.PROGRESS -> ProgressBody(
                        onMeasuredLevel = onMeasuredLevel,
                        language = state.targetLanguage,
                        nativeLanguage = state.nativeLanguage,
                        onOpenAssessment = onOpenAssessment,
                        onOpenActivity = onOpenActivity,
                        goalMinutes = LocalContext.current
                            .getSharedPreferences("futurevoice", 0)
                            .getInt("futurevoice.dailyGoalMinutes", 10),
                        // The advice on a measured page ends in "go talk", so the
                        // page gets the door rather than describing one.
                        onStartTalk = { onTabChange(HomeTab.TALK) },
                    )
                }
                // Room to scroll the last item up past the floating bar.
                if (!paged) Spacer(Modifier.height(IosTabBarClearance)
                    .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.navigationBars))
            }

          }
        }
        // The feather under the floating bar (iOS `tabBarScrollFeather`):
        // from the physical bottom edge, 44 dp of page colour and a 72 dp
        // ramp to transparent above it, so pages dissolve as they slide
        // under the bar instead of running razor-sharp off the screen.
        ScrollEdgeFeather(color = AppSurfaces.ground, modifier = Modifier.align(Alignment.BottomCenter))
        IosTabBar(selected = tab, onSelect = onTabChange,
            modifier = Modifier.align(Alignment.BottomCenter))
      }
    }
}

/**
 * The Talk hero: the day's goal ring around the Futureself surface, under
 * the line that opens the app. The ring IS the call button — one tap, like
 * placing a call.
 */
@Composable
private fun TalkHero(state: AppState, enabled: Boolean, onTap: () -> Unit,
                     onOpenActivity: () -> Unit) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var seconds by remember { mutableStateOf(0) }
    var sessionCount by remember { mutableStateOf(0) }
    val goalMinutes = remember {
        context.getSharedPreferences("futurevoice", 0).getInt("futurevoice.dailyGoalMinutes", 10)
    }
    // Keyed on the LANGUAGE as well as the store revision: the switcher chip
    // sits in this same screen, so a switch recomposes without anything
    // leaving composition and a revision-only key kept the previous
    // language's talk count — which is what the line above the ring is
    // written from, so a fresh language still read "it's been a while"
    // until the app was restarted.
    LaunchedEffect(revision, state.targetLanguage) {
        seconds = TalkTimeLog.secondsToday(context)
        sessionCount = SessionStore.shared(context).load(state.targetLanguage).size
        // The ledger is the receipt (iOS `backfillTalkTime`): re-read only
        // if it moved the number.
        if (TalkTimeLog.syncFromServer(context)) seconds = TalkTimeLog.secondsToday(context)
    }
    val theme = remember { FutureselfTheme.stored(context) }

    // The ring's CENTRE sits on the device screen's midline — iOS solves the
    // hero's height for exactly that rather than guessing at a padding, and
    // the ring is the thing the eye lands on when the app opens.
    //
    // Its centre is `RING_TAIL + ringRadius` above the hero's bottom, so:
    //   heroTop + heroHeight − (tail + radius) = screenHeight / 2
    // The hero's own top is MEASURED, never assumed: it moves with the status
    // bar, the header and whatever the OS puts above them.
    val density = LocalDensity.current
    // The WINDOW's height (iOS `UIScreen.main.bounds`): on API < 35
    // `screenHeightDp` leaves the system bars out, which would lift the ring
    // by half their height.
    val screenHeightPx = androidx.compose.ui.platform.LocalWindowInfo.current
        .containerSize.height.toFloat()
    var heroTopPx by remember { mutableStateOf(0f) }
    // Every report, kept WITHOUT laying out from it (iOS `latestHeroTopReport`).
    val latestTop = remember { floatArrayOf(0f) }
    // Adopted once, when it is plausible (a status bar is always above it) and
    // SETTLED (unchanged across two samples) — iOS's settle-sample. Taking the
    // very first report adopted a transient top before the header had landed,
    // and the hero came out ~46 dp too tall: the ring sat that far below the
    // midline.
    LaunchedEffect(Unit) {
        val floor = with(density) { 40.dp.toPx() }
        var previous = Float.NaN
        while (true) {
            val current = latestTop[0]
            if (current > floor && kotlin.math.abs(current - previous) < 0.5f) {
                heroTopPx = current; break
            }
            previous = current
            delay(250)
        }
    }
    val heroHeight = with(density) {
        val offset = (RING_DIAMETER / 2 + RING_TAIL).toPx()
        maxOf(380.dp.toPx(), screenHeightPx / 2f + offset - heroTopPx).toDp()
    }

    Column(
        Modifier
            .fillMaxWidth()
            .height(heroHeight)
            // Adopted ONCE, at rest (see the settle-sample above). The page
            // scrolls, so the hero's window top moves with it — and feeding a
            // scrolled position back into the hero's own height made the page
            // oscillate between two scroll offsets on a fling.
            .onGloballyPositioned { latestTop[0] = it.boundsInWindow().top }
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        // No spacing of its own (iOS `VStack(spacing: 0)`): the two weighted
        // spacers place the question, and the ring's centre must sit exactly
        // `RING_TAIL + radius` above the bottom — a 20 dp gap here put it
        // 20 dp off the midline the height is solved for.
    ) {
        Spacer(Modifier.weight(1f))
        val line = HeroGreeting.text(HeroGreeting.Input(
            sessionCount = sessionCount,
            todaySpokenSeconds = seconds,
            dailyGoalMinutes = goalMinutes,
        ))
        Text(
            line,
            // The display face — the brand's voice, not the reading font. Big
            // (iOS draws it at 28pt): it is the page's only greeting, and the
            // ring under it is the only other thing in the first viewport.
            style = DisplayFace.style(line, MaterialTheme.typography.headlineMedium),
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.weight(1f))
        TalkRing(
            diameter = RING_DIAMETER,
            progress = seconds / 60f / goalMinutes.coerceAtLeast(1),
            mode = FutureselfMode.IDLE,
            level = 0f,
            theme = theme,
            accent = theme.tint(),
            // The free-talk morph lifts this surface off and flies it to the
            // call's pill; while its proxy is up, the ring shows none.
            surfaceAlpha = if (TalkMorph.active) 0f else 1f,
            onSurfaceBounds = { TalkMorph.ringRect = it },
            modifier = Modifier.then(
                if (enabled) Modifier.clickable(indication = null,
                    interactionSource = remember { MutableInteractionSource() }) { onTap() }
                else Modifier),
        ) {
            // INSIDE the circle: what the tap does, and the day's one number
            // under it. Both used to sit as a line beneath the ring, which
            // left the ring an unlabelled ornament and the number homeless.
            Column(horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                // `let_s_talk` (the shared catalog), not the Android-only
                // `lets_talk`: the two had drifted into different Korean, and
                // this string is the one word both platforms print.
                val label = stringResource(R.string.let_s_talk)
                Text(label, style = DisplayFace.style(label,
                    MaterialTheme.typography.titleLarge))
                val sub = if (seconds > 0) com.roro.futurevoice.data.TalkTime.clock(seconds)
                    else stringResource(R.string.today_s_goal_lld_min, goalMinutes)
                // The morph's proxy wears these exact two lines.
                androidx.compose.runtime.SideEffect { TalkMorph.ringLabel = label; TalkMorph.ringSub = sub }
                Text(
                    sub,
                    // iOS `.footnote.weight(.medium).monospacedDigit()`.
                    style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        // Breathing room under the ring — close enough to invite the scroll,
        // far enough not to crowd it.
        Spacer(Modifier.height(RING_TAIL))
    }
}

/**
 * Under the hero before the first conversation — what the ring is, and that
 * everything below it is a way in (iOS `firstRunCard`).
 *
 * A CARD on the page grid, not centred prose inside the hero: it belongs to
 * the list it explains, and floating loose under the ring it read as a
 * caption on the ring itself.
 */
@Composable
private fun FirstRunCard() {
    Column(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, ContinuousShape(20.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.GraphicEq, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
            Text(stringResource(R.string.your_fluent_self_is_ready),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold)
        }
        Text(stringResource(R.string.tap_let_s_talk_or_a_scenario_or_story_below_to_have_your_fir_acaae8),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** iOS's `talkRing` frame. The tail below it is what the centring solves for. */
private val RING_DIAMETER = 280.dp
private val RING_TAIL = 20.dp

/**
 * Discover — what to talk about today, in two chips (`DiscoverSection`):
 * the day's stories from the platform pool, or a situation the learner
 * built. One full-width card list on the 20pt grid; a horizontal rail read
 * as posters and this reads as a list.
 */
@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun DiscoverSection(
    state: AppState,
    enabled: Boolean,
    onPickNews: (SuggestedTopic) -> Unit,
    onPickScenario: (Scenario) -> Unit,
    /** A ready-made situation, possibly not saved yet (`StarterSituation`). */
    onPickStarter: (Scenario) -> Unit = {},
    onSavePersona: (com.roro.futurevoice.talk.UserPersona) -> Unit = {},
    /** The full collection — the Watch tab, which is where they all live. */
    onAllScenarios: () -> Unit = {},
) {
    var editingInterests by remember { mutableStateOf(false) }
    var newsFailed by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    // News · Everyday · Scenarios (iOS `DiscoverSection.Tab`, `5b0587a`).
    var discoverTab by remember {
        mutableStateOf(com.roro.futurevoice.capture.flags.TalkCaptureFlags.discoverTab ?: DiscoverTab.NEWS)
    }
    val newsTab = discoverTab == DiscoverTab.NEWS
    val interests = state.persona?.interests.orEmpty()
    val language = state.targetLanguage

    if (editingInterests) {
        InterestsEditorSheet(
            persona = state.persona,
            onSave = onSavePersona,
            onDismiss = { editingInterests = false },
        )
    }
    val store = remember { NewsTopicStore.shared(context) }
    val scenarioStore = remember { ScenarioStore.shared(context) }
    var topics by remember { mutableStateOf<List<SuggestedTopic>>(emptyList()) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    /** Who a scene is with, for the row's caption and its initials. */
    var people by remember { mutableStateOf<List<com.roro.futurevoice.data.Counterpart>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var composing by remember { mutableStateOf(false) }

    fun displaySelection(pool: List<SuggestedTopic>): List<SuggestedTopic> {
        val seen = store.seenTitles(interests, language).toSet()
        val current = topics.map { it.title }.toSet()
        return (pool.filter { it.title !in seen } +
            pool.filter { it.title in seen && it.title !in current } +
            pool.filter { it.title in seen && it.title in current }).take(NewsClient.MAX_SHOWN)
    }

    suspend fun fetchNews(refresh: Boolean) {
        loading = true
        newsFailed = false
        try {
            val client = NewsClient(AuthRepository())
            var pool = client.fetch(interests, language, refresh)
            if (pool.topics.isNotEmpty()) {
                store.save(pool.topics, interests, language); topics = displaySelection(pool.topics)
            }
            var polls = 0
            var target = if (pool.growing) pool.topics.size + 1 else 0
            while (polls < NewsClient.MAX_POLLS && (!pool.isComplete || pool.topics.size < target)) {
                delay(NewsClient.POLL_INTERVAL_MS); polls += 1
                pool = client.fetch(interests, language)
                if (pool.topics.isNotEmpty()) {
                    store.save(pool.topics, interests, language); topics = displaySelection(pool.topics)
                }
                if (pool.topics.size >= target) target = 0
            }
        } catch (_: kotlinx.coroutines.CancellationException) {
        } catch (_: Exception) {
            // Said out loud rather than left as an empty section: the learner
            // is looking at a list that just refused to arrive.
            newsFailed = true
        } finally { loading = false }
    }

    LaunchedEffect(interests, language) {
        // Stories come from the shared platform pool (a cheap read), so
        // auto-load on open; the local cache skips even the network hop
        // within the same day.
        if (interests.isNotEmpty()) {
            val cached = store.valid(interests, language)
            if (cached != null) topics = displaySelection(cached) else {
                // No fresh cache: paint whatever was saved last (however old)
                // so the section is never empty on open, then fetch behind it.
                store.lastKnown(interests, language)?.let { topics = displaySelection(it) }
                fetchNews(false)
            }
        }
    }
    LaunchedEffect(language, revision) {
        scenarios = scenarioStore.load(language)
        people = CounterpartStore.shared(context).load()
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SegmentChip(stringResource(R.string.news), newsTab) { discoverTab = DiscoverTab.NEWS }
            SegmentChip(stringResource(R.string.everyday), discoverTab == DiscoverTab.EVERYDAY) {
                discoverTab = DiscoverTab.EVERYDAY
            }
            SegmentChip(stringResource(R.string.scenarios), discoverTab == DiscoverTab.SCENARIOS) {
                discoverTab = DiscoverTab.SCENARIOS
            }
            Spacer(Modifier.weight(1f))
            if (newsTab) {
                // Interests FIRST, then refresh — iOS's order, and the one that
                // reads left to right: what the stories are about, then get
                // more of them.
                DiscoverHeaderButton(onClick = { editingInterests = true }) {
                    Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.edit_interests),
                        tint = MaterialTheme.colorScheme.primary)
                }
                // iOS: the refresh slot exists only once there are stories,
                // and while loading it holds the spinner in the same place.
                if (topics.isNotEmpty() && loading) {
                    Box(Modifier.size(DiscoverHeaderIcon), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    }
                } else if (topics.isNotEmpty()) {
                    DiscoverHeaderButton(onClick = {
                        scope.launch {
                            // Rotating the unseen pool is free — only ask the
                            // server once the local pool is exhausted.
                            val cached = store.valid(interests, language)
                            if (cached != null && cached.size > topics.size) {
                                store.markSeen(topics.map { it.title }, interests, language)
                                val rotated = displaySelection(cached)
                                if (rotated.map { it.title } != topics.map { it.title }) {
                                    topics = rotated; return@launch
                                }
                            }
                            store.markSeen(topics.map { it.title }, interests, language)
                            fetchNews(true)
                        }
                    }) {
                        Icon(Icons.Filled.Refresh,
                            contentDescription = stringResource(R.string.refresh_stories),
                            tint = MaterialTheme.colorScheme.primary)
                    }
                }
            } else if (discoverTab == DiscoverTab.SCENARIOS) {
                DiscoverHeaderButton(onClick = { composing = true }) {
                    Icon(Icons.Filled.Add,
                        contentDescription = stringResource(R.string.build_a_scenario),
                        tint = MaterialTheme.colorScheme.primary)
                }
            }
        }

        if (newsTab && interests.isEmpty()) {
            // Nothing to build stories from yet — the fix is one tap, so
            // offer it instead of an empty section.
            DiscoverRow(
                title = stringResource(R.string.add_interests),
                icon = Icons.Filled.Add,
                onClick = { editingInterests = true },
            )
        } else if (newsTab && topics.isEmpty()) {
            if (loading) {
                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    Text(stringResource(R.string.finding_stories),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                // Auto-load happens on open; this is the retry path when that
                // failed or came back empty.
                DiscoverRow(
                    title = stringResource(R.string.load_stories),
                    icon = Icons.Filled.Newspaper,
                    onClick = { scope.launch { fetchNews(true) } },
                )
            }
        }
        if (newsTab) {
            topics.forEach { topic ->
                DiscoverRow(
                    title = topic.title,
                    // Capitalized, like iOS: the pool writes categories in
                    // lower case ("ai / tech") and a caption is a label.
                    caption = topic.category
                        ?.replaceFirstChar { it.titlecase(java.util.Locale.getDefault()) },
                    icon = categoryIcon(topic.category),
                    onClick = if (enabled) ({ onPickNews(topic) }) else null,
                )
            }
            if (newsFailed) {
                Text(stringResource(
                    if (topics.isEmpty()) R.string.couldn_t_load_stories
                    else R.string.showing_earlier_stories),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else if (discoverTab == DiscoverTab.EVERYDAY) {
            // Ready-made situations on a chip of their own, right under the
            // chips. A tap starts the call; one already talked through
            // carries a check.
            StarterSituation.all.forEach { starter ->
                val existing = scenarios.firstOrNull { it.starterId == starter.id }
                val title = stringResource(starter.title)
                val role = stringResource(starter.role)
                DiscoverRow(
                    title = title,
                    caption = if (starter.showsRole) stringResource(R.string.with, role) else null,
                    icon = Symbols.icon(starter.icon),
                    onClick = if (enabled) ({
                        onPickStarter(starter.scenario(scenarios, language, title, role))
                    }) else null,
                    trailing = if (existing?.lastUsedAt != null) ({
                        Row(verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Filled.CheckCircle, contentDescription = stringResource(R.string.done),
                                tint = androidx.compose.ui.graphics.Color(0xFF34C759),
                                modifier = Modifier.size(20.dp))
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                                tint = MaterialTheme.colorScheme.outline)
                        }
                    }) else null,
                )
            }
        } else {
            // The learner's own situations — ready-made ones live on Everyday.
            val live = scenarios.filter { it.archivedAt == null && it.isMeeting != true && it.starterId == null }
            live.take(5).forEach { sc ->
                // WHO the scene is with, not what shelf it sits on — a
                // category told the learner nothing they didn't already see.
                val personName = sc.counterpartId?.let { id -> people.firstOrNull { it.id == id }?.name }
                var rowMenu by remember(sc.id) { mutableStateOf(false) }
                Box {
                    DiscoverRow(
                        title = sc.cardTitle,
                        caption = (personName ?: sc.role?.takeIf { it.isNotBlank() })
                            ?.let { stringResource(R.string.with, it) } ?: sc.category,
                        // The icon the categorizer picked for this scenario —
                        // a fixed pin made every scenario look like a place.
                        icon = Symbols.icon(sc.categoryIcon),
                        onClick = null,
                        modifier = Modifier.combinedClickable(
                            onClick = {
                                if (enabled) {
                                    scope.launch { scenarioStore.touch(sc.id, language); StoreEvents.bump() }
                                    onPickScenario(sc)
                                }
                            },
                            onLongClick = { rowMenu = true }),
                    )
                    com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = rowMenu, onDismissRequest = { rowMenu = false }) {
                        com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                            text = { Text(stringResource(R.string.delete),
                                color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null,
                                tint = MaterialTheme.colorScheme.error) },
                            onClick = {
                                rowMenu = false
                                scope.launch { scenarioStore.delete(sc.id, language); StoreEvents.bump() }
                            })
                    }
                }
            }
            // The door to the rest of them, rather than a list that grows
            // until the home screen is a filing cabinet — always the list's
            // tail, as on iOS.
            if (live.isNotEmpty()) {
                DiscoverRow(
                    title = stringResource(R.string.all_scenarios),
                    caption = "${live.size}",
                    icon = Icons.Filled.Layers,
                    onClick = onAllScenarios,
                )
            }
            if (live.isEmpty()) {
                // iOS `scenariosContent`: a plain tinted "+" label, not a card.
                TextButton(onClick = { composing = true }) {
                    Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.build_your_first_scenario),
                        style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }

    if (composing) {
        // iOS: the box door (`.custom`), CTA "Talk" — the fresh scenario
        // goes straight into the call.
        ScenarioComposer(
            targetLanguage = language,
            existingCategories = scenarios.mapNotNull { it.category }.distinct(),
            mode = ComposerMode.CUSTOM,
            onCommitted = { sc -> onPickScenario(sc) },
            onDismiss = { composing = false },
        )
    }
}

/** Talk's Discover chips (iOS `DiscoverSection.Tab`). */
enum class DiscoverTab { NEWS, EVERYDAY, SCENARIOS }

/**
 * Best-effort glyph for a free-form interest category — the fallback is the
 * newspaper, because every story is at least news.
 */
private fun categoryIcon(category: String?): androidx.compose.ui.graphics.vector.ImageVector {
    val c = category?.lowercase() ?: return Icons.Filled.Article
    return when {
        c.contains("ai") || c.contains("tech") -> Icons.Filled.Memory
        c.contains("cook") || c.contains("food") -> Icons.Filled.Restaurant
        c.contains("sport") || c.contains("fitness") -> Icons.Filled.DirectionsRun
        c.contains("music") -> Icons.Filled.MusicNote
        c.contains("travel") -> Icons.Filled.Flight
        c.contains("science") -> Icons.Filled.Science
        c.contains("business") || c.contains("finance") -> Icons.Filled.TrendingUp
        c.contains("film") || c.contains("movie") || c.contains("tv") -> Icons.Filled.Movie
        c.contains("game") -> Icons.Filled.SportsEsports
        c.contains("health") -> Icons.Filled.FavoriteBorder
        c.contains("parent") -> Icons.Filled.ChildCare
        else -> Icons.Filled.Article
    }
}

/**
 * Days in a row with metered talk — the one Today stat that lives up here,
 * and the ONLY way into the activity calendar.
 *
 * It used to hide itself entirely until a streak existed, to avoid printing a
 * zero at someone. That was right about the number and wrong about the button:
 * the chip is also the navigation, so the learner most likely to be looking
 * for where they stand had no route to the page at all. It is always here now
 * and only its CONTENTS change; no zero is ever shown.
 */
@Composable
private fun StreakChip(language: String, onClick: () -> Unit) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var days by remember { mutableStateOf(0) }
    // Alive by one thing only (iOS `21df988`): the flame is grey until
    // today's promise is kept, then it lights up.
    var keptToday by remember { mutableStateOf(false) }
    LaunchedEffect(revision) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            // Judge today first, or a fresh launch reads yesterday's standing.
            runCatching { com.roro.futurevoice.data.PromiseJudge.refresh(context) }
            days = TalkTimeLog.streakDays(context)
            keptToday = TalkTimeLog.keptToday(context)
        }
    }
    // A capsule, and tappable: the streak is a claim about a history, so it
    // opens the record rather than asking to be taken on trust.
    // The same glass capsule as Speech's + and the two buttons beside it.
    com.roro.futurevoice.ui.brand.IosGlassButton(onClick = onClick) {
        val lit = days > 0 || keptToday
        Icon(
            if (lit) Icons.Filled.LocalFireDepartment else Icons.Filled.CalendarMonth,
            contentDescription = null,
            // iOS: `flame.fill`, orange only once today is kept.
            tint = if (keptToday) androidx.compose.ui.graphics.Color(0xFFFF9500)
            else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(5.dp))
        Text(
            if (lit) stringResource(R.string.lld_day_streak_94de2a, maxOf(days, 1))
            else stringResource(R.string.activity),
            style = MaterialTheme.typography.bodyLarge.copy(
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold))
    }
}

/**
 * The learner's face, with what's left of the month's talk pool drawn around
 * it (iOS `headerControl`): full pool = empty ring, the arc growing clockwise
 * from 12 o'clock as minutes are spent. No digits — a month-long balance must
 * not become a meter, and the exact figures live one tap away in Me.
 *
 * NOT drawn on Plus: an hour a day is a pool that tier will almost never
 * approach, so the arc would sit near-empty all month, and a gauge that never
 * moves is decoration on the one tier that paid its way out of counting.
 */
@Composable
private fun HeaderAvatar(initials: String, onClick: () -> Unit) {
    // Capture build only: an injected account, since a capture is signed out.
    val injected = com.roro.futurevoice.capture.flags.TalkCaptureFlags.headerAccount
    var account by remember { mutableStateOf(injected) }
    LaunchedEffect(Unit) {
        if (injected != null) return@LaunchedEffect
        runCatching { AccountStatus.load(AuthRepository()) }.getOrNull()?.let {
            BillingGate.remember(it)
            account = it
        }
    }
    // iOS: a 44pt glass circle, the 38pt ring inside its rim, the avatar
    // 2pt inside the ring. Drawn as a raised white disc — the glass over the
    // grouped ground reads as exactly that.
    com.roro.futurevoice.ui.brand.IosGlassButton(onClick = onClick,
        modifier = Modifier.padding(end = 12.dp), circle = true) {
        val a = account
        if (a != null && !a.isUncappedTalk && (a.monthlyCapSeconds != null || !a.isEntitled)) {
            // The full tank is this account's own pool, never a constant: the
            // period's cap for a subscriber, the signup grant otherwise.
            val cap = a.monthlyCapSeconds?.takeIf { a.isEntitled }
            val tank = cap ?: FREE_GRANT_SECONDS
            val left = if (cap != null) (cap - a.secondsUsedPeriod).coerceAtLeast(0)
            else a.secondsBalance.coerceAtLeast(0)
            val used = 1f - (left.toFloat() / tank.coerceAtLeast(1)).coerceIn(0f, 1f)
            // The track is a GROOVE for the arc to sit in — at full strength it
            // read as a second ring competing with the accent one.
            val track = MaterialTheme.colorScheme.surfaceVariant
            val arc = MaterialTheme.colorScheme.primary
            Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    val w = 3.dp.toPx()
                    // Inset by half the stroke so the ring stays INSIDE the
                    // 30dp slot — a centred stroke overhangs it and the header
                    // clips the arc's caps flat.
                    val box = Size(size.width - w, size.height - w)
                    drawArc(color = track, startAngle = 0f, sweepAngle = 360f,
                        useCenter = false, topLeft = Offset(w / 2f, w / 2f), size = box,
                        style = Stroke(width = w))
                    if (used > 0.005f) {
                        drawArc(color = arc, startAngle = -90f, sweepAngle = 360f * used,
                            useCenter = false, topLeft = Offset(w / 2f, w / 2f), size = box,
                            style = Stroke(width = w, cap = StrokeCap.Round))
                    }
                }
                ProfileAvatar(initials = initials, size = 28.dp)
            }
        } else {
            ProfileAvatar(initials = initials, size = 38.dp)
        }
    }
}

/**
 * The free tier's full tank — the signup grant, ten minutes since
 * 2026-09-21 (`20260921120000_ten_free_minutes`), 20 since 2026-09-26
 * (`20260926100000_twenty_free_minutes`). It used to be 66, which drew a ring
 * that barely moved for an account that now decides within a few calls.
 * Keep it equal to `handle_new_user_credits`.
 */
private const val FREE_GRANT_SECONDS = 1200

/**
 * A header control that looks like one.
 *
 * These were bare `TextButton`s, which in a header read as labels — and a
 * label that does something is a thing the learner has to discover by
 * poking. Same quiet capsule the streak wears, so the three read as one row
 * of controls rather than three unrelated bits of text.
 */
@Composable
private fun HeaderButton(
    label: String,
    onClick: () -> Unit,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
) {
    // The same glass capsule as Speech's + (iOS 26 toolbar glass).
    com.roro.futurevoice.ui.brand.IosGlassButton(onClick = onClick,
        modifier = Modifier.padding(start = 12.dp)) {
        icon?.let {
            Icon(it, contentDescription = null, modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(5.dp))
        }
        Text(label, style = MaterialTheme.typography.bodyLarge,
            fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary)
    }
}

/**
 * One face in the stories row (iOS `PersonBubble`). There is no photo of
 * these people and there should not be — the app never asks for one — so the
 * bubble is an initial on the accent, which is enough to pick a name out of
 * five. The ACTION bubble is a dashed outline instead: an empty slot asking
 * to be filled, not a person.
 */
@Composable
private fun PersonBubble(name: String, isAction: Boolean = false, onClick: () -> Unit) {
    Column(
        Modifier.width(72.dp).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val accent = MaterialTheme.colorScheme.primary
        val outline = MaterialTheme.colorScheme.outline
        Box(
            Modifier.size(64.dp).then(
                if (isAction) Modifier.drawBehind {
                    drawCircle(
                        color = outline,
                        radius = size.minDimension / 2f - 1.dp.toPx(),
                        style = Stroke(width = 1.5.dp.toPx(),
                            pathEffect = PathEffect.dashPathEffect(
                                floatArrayOf(5.dp.toPx(), 5.dp.toPx()))),
                    )
                }
                else Modifier
                    .background(accent.copy(alpha = 0.15f), CircleShape)
                    .border(1.5.dp, accent.copy(alpha = 0.35f), CircleShape)),
            contentAlignment = Alignment.Center,
        ) {
            if (isAction) {
                Icon(Icons.Filled.Add, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Text(name.take(1).uppercase(),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = accent)
            }
        }
        Text(name, style = MaterialTheme.typography.labelMedium,
            color = if (isAction) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * True while the persona's narrative fields are still blank — the ones
 * onboarding deliberately skips and [PersonaDeepenSheet] collects.
 *
 * The first call now asks these out loud and writes down the answers
 * (`UserPersona.learnedNotes`). Once it has, a form asking the same three
 * questions reads as the app not having listened.
 */
private fun personaNeedsDepth(p: com.roro.futurevoice.talk.UserPersona?): Boolean {
    if (p == null) return false
    if (p.learnedNotes.isNotEmpty()) return false
    return listOf(p.occupation, p.household, p.freeNotes).all { it.isBlank() }
}

/**
 * The persistent re-entry once the auto-prompt has passed — visible only
 * while those fields stay empty, so it disappears the moment it is answered
 * rather than sitting on the home as a permanent chore.
 */
@Composable
private fun DeepenRow(onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, ContinuousShape(20.dp))
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Filled.PersonAddAlt, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.tell_me_more_about_you),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.talks_get_more_real_when_i_know_your_life),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Which call is on screen — retained across activity recreation (see [RootScreen]). */
class CallRoute : androidx.lifecycle.ViewModel() {
    val inCall = mutableStateOf(false)
    val topic = mutableStateOf("")
    val facts = mutableStateOf<List<String>>(emptyList())
    val scenarioId = mutableStateOf<String?>(null)
    val opener = mutableStateOf("")
    val cast = mutableStateOf<com.roro.futurevoice.talk.ConversationEngine.Cast?>(null)
    val castVoice = mutableStateOf<String?>(null)
    val counterpartId = mutableStateOf<String?>(null)
    /** Launched from a Talk-home card (a scenario or a news story) — iOS
     *  `ConversationHome.callLaunch`, whose dismissal is the one moment the
     *  persona-deepen sheet is offered. The ring's free talk is not one. */
    val fromHomeCard = mutableStateOf(false)
}

/**
 * The Discover header's trailing glyph buttons (iOS: a bare `Button` with an
 * SF Symbol at body size — ~17 × 15 pt glyphs, no padded hit box). Material's
 * 48 dp IconButton made the header row 48 dp on News and Scenarios but only
 * the chips' 34 dp on Everyday, so the list jumped on every switch; at this
 * size the chips alone set the row height on every segment, as on iOS.
 */
private val DiscoverHeaderIcon = 22.dp

@Composable
private fun DiscoverHeaderButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        Modifier
            .size(DiscoverHeaderIcon)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = androidx.compose.material3.ripple(bounded = false, radius = 20.dp),
                role = androidx.compose.ui.semantics.Role.Button,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

/** What the root shows at the book layer: a book page, or whatever lies
 *  under the books. `still` marks an "under" that must not animate — a
 *  screen above the books (shadowing, the deck, a scene) or a call. */
internal sealed interface BookPage {
    data class Talk(val id: String) : BookPage
    data class Scenario(val id: String) : BookPage
    data class Under(val still: Boolean) : BookPage
}

/** iOS's push curve (UINavigationController: ~0.35 s, ease-out). */
/** The book layer: a book page pushed over what lies under the books, or
 *  popped back off it (see [bookPageTransition]). */
@Composable
internal fun BookPushHost(page: BookPage, content: @Composable (BookPage) -> Unit) {
    androidx.compose.animation.AnimatedContent(
        targetState = page,
        contentKey = { if (it is BookPage.Under) "under" else it },
        transitionSpec = { bookPageTransition(initialState, targetState) },
        label = "book-push",
    ) { p ->
        // A book page is opaque paper: its header must hide the page it
        // slides over (and, on the way back, the page sliding in under it).
        if (p is BookPage.Under) content(p)
        else Box(Modifier.fillMaxSize().background(com.roro.futurevoice.ui.brand.AppSurfaces.ground)) { content(p) }
    }
}

private val PushEasing = androidx.compose.animation.core.CubicBezierEasing(0.2f, 0.9f, 0.3f, 1f)
private const val PUSH_MS = 380

private fun bookPageTransition(from: BookPage, to: BookPage): androidx.compose.animation.ContentTransform {
    fun <T> spec() = androidx.compose.animation.core.tween<T>(PUSH_MS, easing = PushEasing)
    val none = androidx.compose.animation.ContentTransform(
        androidx.compose.animation.EnterTransition.None, androidx.compose.animation.ExitTransition.None)
    val fromBook = from !is BookPage.Under
    val toBook = to !is BookPage.Under
    val push = when {
        from is BookPage.Under && !from.still && toBook -> true
        // A scene book opens its talk page on top of it.
        from is BookPage.Scenario && to is BookPage.Talk -> true
        fromBook && to is BookPage.Under && !to.still -> false
        from is BookPage.Talk && to is BookPage.Scenario -> false
        else -> return none
    }
    return if (push) androidx.compose.animation.ContentTransform(
        // The new page comes in from the right edge; the one under it
        // drifts a third of the way left, as iOS's parallax does.
        androidx.compose.animation.slideInHorizontally(spec()) { it },
        androidx.compose.animation.slideOutHorizontally(spec()) { -it / 3 } +
            androidx.compose.animation.fadeOut(spec(), targetAlpha = 0.9f),
        targetContentZIndex = 1f,
    ) else androidx.compose.animation.ContentTransform(
        androidx.compose.animation.slideInHorizontally(spec()) { -it / 3 } +
            androidx.compose.animation.fadeIn(spec(), initialAlpha = 0.9f),
        androidx.compose.animation.slideOutHorizontally(spec()) { it },
        // The page leaving sits ON TOP of the one coming back.
        targetContentZIndex = -1f,
    )
}

/**
 * What the tab root asks for on ARRIVAL, in iOS `RootTabView.onAppear`'s
 * order: a voice with no age on record takes the whole arrival (the guide
 * follows the age check, the free-minutes welcome waits for the next run);
 * otherwise on Talk with its guide still due the welcome is held behind the
 * guide; otherwise the welcome is checked at once.
 */
enum class TabArrival {
    AGE_CHECK, GUIDE_THEN_WELCOME, WELCOME;

    companion object {
        fun decide(hasVoice: Boolean, ageOnRecord: Boolean, onTalk: Boolean, talkGuideDue: Boolean) = when {
            hasVoice && !ageOnRecord -> AGE_CHECK
            onTalk && talkGuideDue -> GUIDE_THEN_WELCOME
            else -> WELCOME
        }
    }
}


/**
 * The scenario behind "Watch" on a Find-people card (iOS
 * `WatchTab.freeTalkScenario(with:)`): no situation to build, just the two of
 * them talking. Reused, never re-minted, per person — the study material from
 * meeting them accumulates in one book. Kept deliberately short: the person's
 * intro and style already ride in the scene engine's counterpart block. The
 * voice is the person's preset (iOS reads it off the Counterpart; the Android
 * scene reads it off the scenario).
 */
internal suspend fun meetingScenario(
    context: android.content.Context, person: com.roro.futurevoice.data.Counterpart, language: String,
): Scenario {
    val store = com.roro.futurevoice.data.ScenarioStore.shared(context)
    store.load(language).firstOrNull {
        it.counterpartId == person.id && it.category == MEETING_CATEGORY
    }?.let { existing ->
        if (existing.voicePresetId == person.voicePresetId) return existing
        return existing.copy(voicePresetId = person.voicePresetId).also { store.save(it, language) }
    }
    val s = Scenario(
        environment = "Talking with someone you've just met, already past the hellos",
        role = person.relationship.ifBlank { person.name },
        notes = "Build the scene on the COMMON GROUND given below — that is " +
            "the subject. Get specific about it fast. NOT a " +
            "get-to-know-you interview: no running through where are you " +
            "from / what do you do / what are your hobbies. Land " +
            "mid-subject, the way real talk does.",
        counterpartId = person.id,
        voicePresetId = person.voicePresetId,
        isMeeting = true,
        category = MEETING_CATEGORY,
        categoryIcon = "person.2.wave.2",
        summary = "Free talk with ${person.name}",
    )
    store.save(s, language)
    com.roro.futurevoice.data.StoreEvents.bump()
    return s
}

private const val MEETING_CATEGORY = "Meeting"
