package com.roro.futurevoice.ui

import androidx.compose.ui.layout.boundsInRoot
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
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
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
import androidx.compose.material.icons.filled.Checkroom
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
import com.roro.futurevoice.net.PurposeTopicClient
import com.roro.futurevoice.data.DiscoverChip
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
    /** Context the call is told beside the topic (iOS `CallLaunch.blurb`). */
    var callBlurb by call.blurb
    var callScenarioId by call.scenarioId
    var callOpener by call.opener
    var callCast by call.cast
    var callCastVoice by call.castVoice
    /** Who the call is with, so the saved talk lands on their card. */
    var callCounterpartId by call.counterpartId
    /** A saved talk the call picks back up (Continue on its book). */
    var callResume by call.resume
    var callFromHomeCard by call.fromHomeCard
    /** Which screen started the call — `conversation_started.entry` only. */
    var callEntry by call.entry
    /** The topics page's "my own topic" — the call opens by asking what to talk about. */
    var callPicksTopic by call.picksTopic
    /** Set when a Talk-home card's call closes; the home consumes it and
     *  offers the persona-deepen sheet (iOS `maybePromptDeepen`). */
    var deepenPending by remember { mutableStateOf(false) }
    /** Set when ANY call closes; the home consumes it and may offer the
     *  backup file once (iOS `maybeOfferBackup`). */
    var backupPending by remember { mutableStateOf(false) }
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
    // The store waiting on the learner's consent before it charges (iOS
    // `PriceConsentSheet` on RootTabView), said in our words first.
    val priceConsent by com.roro.futurevoice.data.PriceConsent.pending.collectAsStateWithLifecycle()
    val priceConsentShowing by com.roro.futurevoice.data.PriceConsent.showing.collectAsStateWithLifecycle()
    if (tabsArrived && priceConsentShowing) priceConsent?.let {
        PriceConsentSheet(pending = it, onDismiss = com.roro.futurevoice.data.PriceConsent::dismiss)
    }
    // A measured level-up, announced once wherever the learner happens to be.
    if (tabsArrived) state.levelUp?.let { (from, to) ->
        LevelUpSheet(from = from, to = to, onDismiss = app::clearLevelUp)
    }
    var showPublicIntro by remember { mutableStateOf(false) }
    /** The one "me" page (iOS `MyProfileView`), pushed inside the Me sheet
     *  from its profile header. */
    var showMyProfile by remember { mutableStateOf(false) }
    /** The same page as its own sheet, with Done — iOS opens it so from the
     *  Watch map's own face (`WatchTab.showingProfile`). */
    var showMyProfileSheet by remember { mutableStateOf(false) }
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
    /** A Speech challenge's board, pushed from the Speech tab. */
    var speechChallengeId by remember { mutableStateOf<String?>(null) }
    /** Every challenge, live and past — pushed from the Speech tab. */
    var showSpeechChallenges by remember { mutableStateOf(false) }
    var showDueReview by remember { mutableStateOf(false) }
    /** Progress's effort page (iOS `EffortDetailView`, pushed from the card). */
    var showEffort by remember { mutableStateOf(false) }
    /** The routine's Review block, dealt: its cards, then its shadow lines
     *  (iOS `DueReviewView(hand:shadowPicks:)`). */
    var routineReview by remember {
        mutableStateOf<Pair<List<StudyDeckItem>, List<com.roro.futurevoice.data.ShadowPicks.Pick>>?>(null)
    }
    var showCreditGuide by remember { mutableStateOf(false) }
    var showPlanPage by remember { mutableStateOf(false) }
    // Keep the learner's pool row in step with the profile — but only a row
    // they APPROVED (the Watch-tab preview's Publish). Before that nothing is
    // inserted; a row an older build put up unasked is only rewritten to the
    // current composition or taken down. Gated on a real account: an
    // anonymous session's data dies with the install.
    LaunchedEffect(state.signedIn, state.isAnonymous, state.persona, state.targetLanguage) {
        if (state.signedIn && !state.isAnonymous) app.syncPublicPersona(withPhoto = true)
    }
    val localActivity = androidx.compose.ui.platform.LocalContext.current as? android.app.Activity
    var showPeople by remember { mutableStateOf(false) }
    /** The finished-books page (iOS "Finished"), opened from Practice's header seal. */
    var finishedBooks by remember { mutableStateOf<List<FinishedBook>?>(null) }
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
    /** Talk's topics page, behind "Find a topic" (iOS `TalkTopicsPage`). */
    var showTopics by remember { mutableStateOf(false) }
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
    /** The talk page was opened from Me → Profile's "Show the talk" (iOS
     *  presents `ConversationDetailView` over the form): drawn ABOVE the
     *  editor, in the language the talk was found in, which can be another
     *  enrolled language than the active one. */
    var talkOverProfile by remember { mutableStateOf(false) }
    var detailLanguage by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(detailSessionId) {
        if (detailSessionId == null) { talkOverProfile = false; detailLanguage = null }
    }
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
    /** A scene's "Study this" (iOS `SceneWatchView` pushes `ScenarioDetailView`):
     *  the book over the finished scene, so its back returns to the scene. */
    var bookOverWatchId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(watchScenarioId) { if (watchScenarioId == null) bookOverWatchId = null }
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
                    callTopic = ""; callFacts = emptyList(); callBlurb = ""; callScenarioId = null
                    callEntry = DeepLinkInbox.freeTalkEntry ?: com.roro.futurevoice.talk.TalkEntry.WIDGET
                    DeepLinkInbox.freeTalkEntry = null
                    inCall = true
                }
            }
        }
    }
    val callAnswered by com.roro.futurevoice.data.DailyCallInbox.answered.collectAsStateWithLifecycle()
    LaunchedEffect(callAnswered) {
        // Answering the daily call IS starting the talk — no second tap, and
        // no overlay (Me, a deck, a book) may stand in front of it.
        // Through the same gate as the Talk ring (iOS `consumeAnsweredCall`,
        // 2026-10-10): a call armed before the pool ran out opens the plans,
        // not a call that 402s before the learner speaks.
        if (callAnswered > 0 && state.voiceId != null) gate {
            showMe = false; showDeck = false; detailSessionId = null
            watchScenarioId = null; shadowLine = null; clonePreview = false
            shadowHand = emptyList(); shadowAt = 0
            callTopic = ""; callFacts = emptyList(); callBlurb = ""; callScenarioId = null
            // The pre-written voicemail IS the call's first line; consumed
            // so a plain free talk later doesn't replay it.
            callOpener = com.roro.futurevoice.data.DailyCallStore.script(context).orEmpty()
            com.roro.futurevoice.data.DailyCallStore.setScript(context, null)
            callEntry = com.roro.futurevoice.talk.TalkEntry.DAILY_CALL
            inCall = true
        }
    }
    var editProfile by remember { mutableStateOf(false) }
    var editProfileStep by remember { mutableStateOf(0) }
    /** Whether the routine (daily call, study time) has been set up. The key
     *  is the daily-call screen's, which the routine builder replaced (iOS
     *  2026-10-18), so every install that saw that screen is past this one.
     *  Onboarding shows no paywall: the plans are asked at the first paid tap. */
    var dailyCallOnboarded by remember {
        mutableStateOf(OnboardingFlags.seen(context, OnboardingFlags.DAILY_CALL))
    }
    /** The routine builder is over the tabs (iOS `holdingForRoutine`). */
    val buildingRoutine = state.voiceId != null && !dailyCallOnboarded
    val routineHint by RoutineHandoff.showHint.collectAsStateWithLifecycle()
    /** The first-run sheets (age check, Talk's guide, the free minutes) wait
     *  until the builder has gone into the Activity chip and that chip's hint
     *  is closed (iOS `firstRunHeld`). */
    var firstRunHeld by remember { mutableStateOf(false) }
    // The second device's question, asked once per account per install.
    val secondDeviceUser = remember(state.signedIn, state.isAnonymous) {
        if (state.signedIn && !state.isAnonymous) com.roro.futurevoice.data.AuthRepository().userId else null
    }
    var syncOfferSeen by remember(secondDeviceUser) {
        mutableStateOf(secondDeviceUser == null ||
            com.roro.futurevoice.sync.SyncStore.wasOffered(context, secondDeviceUser) ||
            com.roro.futurevoice.sync.SyncEngine.shared(context).isEnabled)
    }
    var localDataOnboarded by remember {
        mutableStateOf(OnboardingFlags.seen(context, OnboardingFlags.LOCAL_DATA))
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
    fun offerFirstRunSheets() {
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
    fun arriveAtTabs() {
        if (tabsArrived) return
        tabsArrived = true
        if (buildingRoutine) firstRunHeld = true else offerFirstRunSheets()
    }
    // The chip's hint has closed (on its own or by a tap): what arrival held.
    var hintWasUp by remember { mutableStateOf(false) }
    LaunchedEffect(routineHint) {
        if (routineHint) { hintWasUp = true; return@LaunchedEffect }
        if (!hintWasUp || !firstRunHeld) return@LaunchedEffect
        hintWasUp = false
        firstRunHeld = false
        offerFirstRunSheets()
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
    var showAddLanguage by remember { mutableStateOf(false) }
    if (showAddLanguage) {
        AddLanguageSheet(
            nativeLanguage = state.nativeLanguage,
            targetLanguage = state.targetLanguage,
            enrolled = state.enrolledLanguages,
            onAdd = { code, level -> showAddLanguage = false; app.addLanguage(code, level) },
            onDismiss = { showAddLanguage = false },
        )
    }
    // What's new in this release, once (iOS `offerWhatsNew`): a beat after
    // the tabs are up, never over another sheet.
    var showWhatsNew by remember { mutableStateOf(false) }
    LaunchedEffect(tabsArrived) {
        if (!tabsArrived) return@LaunchedEffect
        delay(1200)
        // The tab's guide counts as a sheet too: on iOS a second `.sheet`
        // over the page intro is dropped by SwiftUI, here both would stack.
        val anotherSheetUp = showAgeCheck || paywalled || welcomeMinutes != null || showIntroPreview ||
            inCall || state.levelUp != null || referralJoin != null ||
            com.roro.futurevoice.data.AppUpdateService.pending.value != null ||
            com.roro.futurevoice.data.PageIntroStore.showing.value
        if (!showWhatsNew && !anotherSheetUp && WhatsNew.isDue(context, state.setupComplete)) showWhatsNew = true
    }
    var whatsNewGoals by remember { mutableStateOf(false) }
    if (showWhatsNew) {
        WhatsNewSheet(
            // iOS opens `DiscoverSettingsSheet` on top of the card.
            onChooseGoal = { whatsNewGoals = true },
            onDismiss = { showWhatsNew = false },
        )
    }
    if (whatsNewGoals) {
        DiscoverSettingsSheet(
            persona = state.persona,
            language = state.targetLanguage,
            onSavePersona = app::savePersona,
            onDismiss = { whatsNewGoals = false },
            // The Talk row re-reads its chips on a store revision.
            onSaved = { StoreEvents.bump() },
        )
    }
    // The voice queued at signup (the month's voices were spent) was just
    // built from their recording — said once, here.
    if (state.queuedVoiceArrived) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = app::clearQueuedVoiceArrived,
            title = { Text(stringResource(R.string.your_voice_is_ready)) },
            text = { Text(stringResource(R.string.from_now_on_your_fluent_self_speaks_in_your_own_voice)) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = app::clearQueuedVoiceArrived) {
                    Text(stringResource(R.string.ok))
                }
            },
        )
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
            gate { callTopic = ""; callFacts = emptyList(); callBlurb = ""; callScenarioId = null
                callEntry = com.roro.futurevoice.talk.TalkEntry.WELCOME; inCall = true }
        }
    }

    // "Your week": the closed week's cards, raised once per week on the
    // first open after it turns (and on the week-turn notification), never
    // over a call or another sheet.
    val updatePending by com.roro.futurevoice.data.AppUpdateService.pending.collectAsStateWithLifecycle()
    var weekRecapUp by remember { mutableStateOf(false) }
    var trialReportUp by remember { mutableStateOf(false) }
    WeekRecapHost(
        ready = state.setupComplete && state.voiceId != null && tabsArrived,
        blocked = inCall || trialReportUp || paywalled || showIntroPreview || state.levelUp != null ||
            referralJoin != null || welcomeMinutes != null || updatePending != null || guideUp ||
            showAgeCheck || showWhatsNew,
        level = state.level,
        onShowing = { weekRecapUp = it },
    )
    // The free minutes' report: at the end of the call that spent them, and
    // again on a later open if it was closed before its last card (iOS
    // `offerTrialReport`).
    TrialReportHost(
        ready = state.setupComplete && tabsArrived,
        inCall = inCall,
        blocked = inCall || weekRecapUp || paywalled || showIntroPreview || state.levelUp != null ||
            referralJoin != null || welcomeMinutes != null || updatePending != null || guideUp ||
            showAgeCheck || showWhatsNew,
        level = state.level,
        onMeasuredLevel = { app.applyMeasuredLevel(it, announce = false) },
        onShowing = { trialReportUp = it },
    )

    // A PARKED voice is rebuilt at the metered tap, on top of whatever is
    // up — sheets included (see `VoiceRevival`).
    VoiceRevivalHost(app)

    val morphScope = rememberCoroutineScope()
    /** Every metered launcher from the home lands here (`mint` = an unsaved
     *  ready-made situation, saved once the gate passes). */
    fun startCall(topic: String, facts: List<String>, scenarioId: String?, mint: Scenario?, blurb: String = "",
                  entry: String = com.roro.futurevoice.talk.TalkEntry.OTHER, learnerPicksTopic: Boolean = false) {
        // The paywall is asked here, at the TAP — every metered
        // launcher (free talk, a news story, a scenario, a widget
        // deep link) meets in this one callback, so one gate covers
        // them all. Met only as a 402, it would arrive after the call
        // screen was already up.
        gate {
            fun open() {
                callTopic = topic; callFacts = facts; callScenarioId = scenarioId; callBlurb = blurb
                callEntry = entry
                callPicksTopic = learnerPicksTopic
                // A news story's title IS its opener — written by `news-topics`
                // as a friend bringing it up ("Did you see the news about…?")
                // and spoken verbatim, as iOS does (`openNewsConversation`).
                // Left to a generated opener, the model read that question as
                // the learner's and answered it ("Yes, I heard…").
                callOpener = if (facts.isNotEmpty()) topic else ""
                // The topics page's calls are the home's `callLaunch` too.
                callFromHomeCard = topic.isNotEmpty() || scenarioId != null || learnerPicksTopic
                // The FREE talk is the ring's own tap: its surface morphs
                // into the call pill (iOS). Every other launcher opens flat.
                if (topic.isEmpty() && scenarioId == null && !learnerPicksTopic && tab == HomeTab.TALK)
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
    // Everything before the app proper — previews, onboarding, the gates —
    // is ONE still page: it swaps in place and is never swiped.
    val gateScreen: (@Composable () -> Unit)? = when {
        welcomePreview -> {{ WelcomeScreen(onGetStarted = { welcomePreview = false })

        // DEBUG-only preview of the clone flow (iOS: `-onboardingPreview`):
        // the dev account already has a voice, so the real gate never shows.
        }}
        clonePreview -> {{ CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onCloned = { clonePreview = false },
        )

        // Match the launch screen until we know whether there's a stored
        // session — but never while onboarding is under way or a voice act
        // is on stage (iOS `launchScreenTwin`'s vetoes).
        }}
        state.resolvingSession && !state.onboardingStarted && !state.holdVoiceOnboarding -> {{ Loading()
        // The pitch before the ask — the short film the fluent self narrates
        // (iOS WelcomeView). Welcome gates on "has the journey begun", NOT on
        // the session: "Get started" enters onboarding account-free, and the
        // session only opens at the clone's "Use this voice". The sign-in
        // here is for returning users restoring.
        }}
        !state.signedIn && !state.onboardingStarted && !state.holdVoiceOnboarding && !devSignInOpen -> {{
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
        }}
        !state.signedIn && devSignInOpen -> {{ SignInScreen(
            state,
            googleAvailable = app.isGoogleConfigured,
            onGoogleSignIn = app::signInWithGoogle,
            onSignIn = app::signIn,
            onDevSignIn = app::devSignIn,
        )
        // First-run answers before anything else — what to teach and how to
        // calibrate.
        }}
        // A signed-in account on an install that hasn't been set up, which
        // already has a voice (adopted from the server) — practice exists on
        // another device. Offer to bring it over before setup asks again
        // (iOS `SyncContinuePromptView` / `SyncOtherDeviceHintView`).
        !state.setupComplete && state.signedIn && !state.isAnonymous && state.voiceId != null &&
            secondDeviceUser != null && !syncOfferSeen -> {{ SyncContinueScreen(
            userId = secondDeviceUser,
            onPulled = app::adoptPulledPractice,
            onDone = { syncOfferSeen = true },
        )
        }}
        !state.setupComplete -> {{ SetupFlowScreen(
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
        }}
        !state.personaResolved -> {{ Loading()
        // Light taps before the heavy ask (iOS order): persona cards build
        // the investment and the first call's context BEFORE the recording.
        }}
        state.persona == null -> {{ PersonaIntakeScreen(
            initial = state.reopenedPersona ?: com.roro.futurevoice.talk.UserPersona(),
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onBackToSetup = { app.reopenSetup() },
            onFinish = app::savePersona,
        )
        // An anonymous session is being looked at for a voice it already
        // made — hold rather than flash the intro before the account act.
        }}
        state.signedIn && state.isAnonymous && state.restoringVoice && !state.holdVoiceOnboarding -> {{ Loading()
        // The voice. `holdVoiceOnboarding` keeps this screen up through the
        // meet act and the sign-up after the clone id has already landed.
        // The anonymous clause is the crash/kill guard: a session is not an
        // account, and letting it through would hand someone an app whose
        // data dies with the install — the flow reopens on its sign-up act.
        // An Android user with no voice starts HERE — they clone on Android.
        }}
        (!state.restoringVoice && state.voiceId == null) || state.holdVoiceOnboarding ||
            (state.signedIn && state.isAnonymous) -> {{ CloneFlowScreen(
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
            voiceIsStandIn = state.voiceIsStandIn,
            voiceQueuedUntil = state.voiceQueuedUntil,
            onQueued = app::adoptStandInVoice,
            standInVoiceId = if (state.voiceIsStandIn) state.voiceId else null,
            onChooseStandIn = app::chooseStandInVoice,
        )
        // Where everything they are about to say will live, said before the
        // first call, ahead of the routine builder (iOS
        // `LocalDataOnboardingView`). Gated on the builder's flag, so an
        // install past the routine never sees it.
        }}
        state.voiceId != null && !localDataOnboarded && !dailyCallOnboarded -> {{
            LocalDataOnboardingScreen(context) { localDataOnboarded = true }
        }}
        else -> null
    }
    // Every page of the app proper, as iOS's navigation stack would hold it:
    // the order below is the stack, top first — the page drawn is the first
    // one whose flag is up, and the one under it is what its back reveals.
    // Pages iOS PUSHES (see [rootPushes]) slide in and swipe back; covers,
    // sheets and the call swap in place, as before.
    val rootStack: List<RootRoute> = if (gateScreen != null) listOf(RootRoute.Gate) else buildList {
        // A call is a cover over everything — including the profile editor,
        // when a talk opened from it was continued (Continue clears the talk
        // page, so this can't wait on `talkOverProfile`).
        val callOverProfile = editProfile && inCall && state.voiceId != null
        if (callOverProfile) add(RootRoute.Call)
        // What that talk page opens (a shadow line, its review deck) stays
        // above the editor too, as iOS presents it over the sheet.
        val overProfile = editProfile && talkOverProfile
        if (overProfile) {
            shadowLine?.let { add(RootRoute.ShadowLine(it)) }
            if (showDeck) add(RootRoute.Deck)
            detailSessionId?.let { add(RootRoute.TalkBook(it)) }
        }
        if (editProfile) add(RootRoute.EditProfile)
        if (shadowHand.isNotEmpty()) add(RootRoute.ShadowHand)
        if (!overProfile) shadowLine?.let { add(RootRoute.ShadowLine(it)) }
        if (watchScenarioId != null) bookOverWatchId?.let { add(RootRoute.ScenarioBook(it)) }
        watchScenarioId?.let { add(RootRoute.Watch(it)) }
        if (showDeck && !overProfile) add(RootRoute.Deck)
        if (!overProfile) detailSessionId?.let { add(RootRoute.TalkBook(it)) }
        bookScenarioId?.let { add(RootRoute.ScenarioBook(it)) }
        if (showSentences) add(RootRoute.Sentences)
        library?.let { add(RootRoute.Library(it)) }
        if (showAssessment) add(RootRoute.Assessment)
        if (sayAgainPending) add(RootRoute.SayAgainPick)
        if (routineEditorOpen) add(RootRoute.RoutineEditor)
        if (routineReview != null) add(RootRoute.RoutineReview)
        if (showActivity) add(RootRoute.Activity)
        // Under Activity: its "Calendar and routine" link opens the routine on top.
        if (showEffort) add(RootRoute.Effort)
        studyDeckKind?.let { add(RootRoute.StudyDeck(it)) }
        if (showMyProfileSheet) add(RootRoute.MyProfile(sheet = true))
        finishedBooks?.let { add(RootRoute.Finished(it)) }
        // Settings is a SHEET over the tabs (iOS `.sheet` from the Talk
        // header), and what it pushes lives inside it — see [meSheetStack].
        if (!showMe) {
            if (showCreditGuide) add(RootRoute.CreditGuide)
            if (showPlanPage) add(RootRoute.PlanPage)
            if (showInvite) add(RootRoute.Invite)
        }
        if (showShadowBrowser) add(RootRoute.ShadowBrowser)
        speechChallengeId?.let { add(RootRoute.SpeechChallenge(it)) }
        if (showSpeechChallenges) add(RootRoute.SpeechChallenges)
        if (!showMe) {
            if (showPublicIntro) add(RootRoute.PublicIntro)
            if (showPrivacy) add(RootRoute.Privacy)
        }
        if (inCall && state.voiceId != null && !callOverProfile) add(RootRoute.Call)
        // Under the call: a topic picked here starts a call over the page,
        // and hanging up comes back to it (iOS: a cover over the pushed page).
        if (showTopics) add(RootRoute.Topics)
        add(RootRoute.Tabs)
    }.reversed()
    /** What a committed back on [top] does — exactly its own back button. */
    fun popRoute(top: RootRoute) {
            when (top) {
                is RootRoute.TalkBook -> detailSessionId = null
                // iOS SceneWatchView: the book is a sheet over the finished
                // scene, and however it goes away the scene goes with it.
                is RootRoute.ScenarioBook ->
                    if (top.id == bookOverWatchId && watchScenarioId != null) { bookOverWatchId = null; watchScenarioId = null }
                    else bookScenarioId = null
                is RootRoute.Watch -> watchScenarioId = null
                RootRoute.Deck -> { showDeck = false; focusCardId = null; deckSessionId = null; deckPushed = false }
                RootRoute.Sentences -> showSentences = false
                is RootRoute.Library -> library = null
                RootRoute.Assessment -> showAssessment = false
                RootRoute.Activity -> showActivity = false
                RootRoute.Topics -> showTopics = false
                RootRoute.Effort -> showEffort = false
                is RootRoute.Person -> personDetailId = null
                is RootRoute.Finished -> finishedBooks = null
                RootRoute.CreditGuide -> showCreditGuide = false
                RootRoute.PlanPage -> showPlanPage = false
                RootRoute.Invite -> showInvite = false
                RootRoute.ShadowBrowser -> showShadowBrowser = false
                is RootRoute.SpeechChallenge -> speechChallengeId = null
                RootRoute.SpeechChallenges -> showSpeechChallenges = false
                RootRoute.PublicIntro -> {
                    showPublicIntro = false
                    if (introEditFromPreview && app.needsIntroDecision()) showIntroPreview = true
                    introEditFromPreview = false
                }
                RootRoute.Privacy -> showPrivacy = false
                is RootRoute.MyProfile -> if (top.sheet) showMyProfileSheet = false else showMyProfile = false
                else -> Unit
            }
    }
    /** Settings, and everything it pushes inside its sheet (iOS `MeTab`'s
     *  own NavigationStack), bottom → top. */
    val meSheetStack: List<RootRoute> = buildList {
        add(RootRoute.Me)
        if (showMyProfile) add(RootRoute.MyProfile(sheet = false))
        if (showPlanPage) add(RootRoute.PlanPage)
        if (showInvite) add(RootRoute.Invite)
        if (showCreditGuide) add(RootRoute.CreditGuide)
        if (showPrivacy) add(RootRoute.Privacy)
        if (showPublicIntro) add(RootRoute.PublicIntro)
    }
    /** Find people and the put-off deck are sheets over the tabs too (iOS
     *  `WatchTab`'s `.sheet(isPresented: $showingFind)`, `PracticeTab`'s
     *  `DueReviewView` sheet), in the same host as Me: one sheet at a time,
     *  Me first. A person opened from Find people is pushed inside it. */
    val tabSheetStack: List<RootRoute>? = when {
        showMe -> meSheetStack
        showPeople -> buildList {
            add(RootRoute.People)
            personDetailId?.let { add(RootRoute.Person(it)) }
        }
        showDueReview -> listOf(RootRoute.DueReview)
        else -> null
    }
    /** The whole sheet goes, whichever of its pages is showing. */
    fun dismissMe() {
        showMe = false
        showPlanPage = false; showInvite = false; showCreditGuide = false
        showPrivacy = false
        showMyProfile = false
        if (showPublicIntro) popRoute(RootRoute.PublicIntro)
    }
    @Composable
    fun DrawRoute(r: RootRoute) {
    when (r) {
        RootRoute.Gate -> gateScreen?.invoke()
        is RootRoute.TalkBook -> TalkDetailScreen(
                sessionId = r.id,
                language = detailLanguage ?: state.targetLanguage,
                level = state.level,
                onBack = { detailSessionId = null },
                onShadow = { shadowLine = it },
                onReviewTalk = { id -> deckSessionId = id; showDeck = true },
                // Picking a talk back up is a metered call, so it goes through
                // the same gate every other launcher does.
                // It RESUMES the talk (iOS `ConversationView(resumeSession:)`):
                // same session, its topic, its scenario, the person it was with.
                onContinue = { s ->
                    gate { gateScope.launch {
                        val person = s.counterpartId?.let { id ->
                            runCatching {
                                com.roro.futurevoice.data.CounterpartStore.shared(context).load()
                                    .firstOrNull { it.id == id }
                            }.getOrNull()
                        }
                        detailSessionId = null
                        callTopic = s.topic.orEmpty(); callFacts = emptyList(); callBlurb = ""
                        callScenarioId = s.originScenarioId
                        callCounterpartId = s.counterpartId
                        callCast = person?.let { com.roro.futurevoice.talk.ConversationEngine.Cast.of(it) }
                        callCastVoice = person?.voicePresetId?.takeIf { it.isNotBlank() }
                        callResume = s
                        callEntry = com.roro.futurevoice.talk.TalkEntry.RESUME
                        inCall = true
                    } }
                },
            )


        is RootRoute.ScenarioBook -> {
            // Over a finished scene by its "Study this" (iOS: a sheet whose
            // dismissal closes the scene too): back returns to Watch; the
            // book's own Watch replays the scene underneath.
            val overWatch = r.id == bookOverWatchId && watchScenarioId != null
            ScenarioBookScreen(
                scenarioId = r.id,
                language = state.targetLanguage,
                // A fresh take costs a scene count, so the wall is asked at the
                // tap here exactly as it is on the Watch tab.
                // Watch on the book replays THE scene the book was extracted
                // from (iOS `WatchView(savedDialogue:)`): free after the first
                // listen, so no gate and no new take.
                onWatch = { id ->
                    if (overWatch) { bookOverWatchId = null; watchReplay = true }
                    else { watchReplay = true; watchScenarioId = id }
                },
                onTalk = { sc -> gate {
                    bookScenarioId = null; bookOverWatchId = null; watchScenarioId = null
                    callTopic = sc.promptBlurb; callFacts = emptyList(); callBlurb = ""; callScenarioId = sc.id
                    callEntry = com.roro.futurevoice.talk.TalkEntry.SCENARIO_BOOK
                    inCall = true
                } },
                onShadow = { shadowLine = it },
                onBack = { if (overWatch) { bookOverWatchId = null; watchScenarioId = null } else bookScenarioId = null },
                // The talk page sits above the book, so back returns here.
                onOpenTalk = { id ->
                    if (overWatch) {
                        watchScenarioId = null; bookOverWatchId = null; bookScenarioId = r.id
                    }
                    detailSessionId = id
                },
            )
        }
        // iOS `PersonaOnboardingView` (Me → Profile): its own form, saved
        // page by page — not the first-run intake cards.
        RootRoute.EditProfile -> PersonaEditScreen(
            initial = state.persona ?: com.roro.futurevoice.talk.UserPersona(),
            saved = state.persona,
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onSave = app::savePersona,
            onClose = { editProfile = false },
            startStep = editProfileStep,
            onShowTalk = { id, language ->
                detailLanguage = language; talkOverProfile = true; detailSessionId = id
            },
        )

        RootRoute.ShadowHand -> ShadowScreen(
            line = shadowHand[shadowAt].turn.transcript,
            turnId = shadowHand[shadowAt].turn.id,
            voiceId = state.voiceId ?: "",
            targetLanguage = state.targetLanguage,
            position = (shadowAt + 1) to shadowHand.size,
            onNext = if (shadowAt + 1 < shadowHand.size) ({ shadowAt += 1 }) else null,
            onBack = { shadowHand = emptyList(); shadowAt = 0 },
        )

        is RootRoute.ShadowLine -> ShadowScreen(
            line = r.line,
            voiceId = state.voiceId ?: "",
            targetLanguage = state.targetLanguage,
            onBack = { shadowLine = null },
        )

        is RootRoute.Watch -> WatchSceneScreen(
            scenarioId = r.id,
            // Over the scene, as iOS's sheet: back returns to it.
            onShadow = { shadowLine = it },
            // iOS `SceneHandoff`: from the Watch tab the book is pushed over
            // the scene; opened FROM the book, it pops back to it.
            onStudy = { id -> if (bookScenarioId == id) watchScenarioId = null else bookOverWatchId = id },
            voiceId = state.voiceId ?: "",
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            proficiency = state.level.code,
            onBack = { watchScenarioId = null },
            replaySaved = watchReplay,
        )

        // Above the book: "Review this talk" opens the deck from a book page,
        // and back from the deck returns to that page.
        RootRoute.Deck -> DrillDeckScreen(
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
        RootRoute.Sentences -> SentencesScreen(
            language = state.targetLanguage,
            onOpenCard = { id -> focusCardId = id; deckPushed = true; showDeck = true },
            onBack = { showSentences = false },
        )

        is RootRoute.Library -> LibraryScreen(
            kind = r.kind,
            language = state.targetLanguage,
            onShadow = { library = null; shadowLine = it },
            onBack = { library = null },
        )

        RootRoute.Assessment -> AssessmentScreen(
            language = state.targetLanguage,
            onBack = { showAssessment = false },
        )

        // A routine reminder's "say it again": which talk (iOS `SayItAgainPicker`).
        RootRoute.SayAgainPick -> SayItAgainPicker(
            language = state.targetLanguage,
            onClose = { com.roro.futurevoice.data.PlanReminder.pendingSayItAgain.value = false },
        )

        // The routine editor opened from somewhere other than the routine page
        // (the Review tab's Today card — iOS `e1b3501`).
        RootRoute.RoutineEditor -> WeeklyPlanEditor(onClose = { RoutineNav.editorOpen.value = false })

        RootRoute.Effort -> EffortDetailScreen(
            language = state.targetLanguage,
            goalMinutes = context.getSharedPreferences("futurevoice", 0)
                .getInt("futurevoice.dailyGoalMinutes", 10),
            onOpenActivity = { showActivity = true },
            onBack = { showEffort = false },
        )

        RootRoute.Topics -> TalkTopicsPage(
            state = state,
            onBack = { showTopics = false },
            onStartCall = { topic, facts, scenarioId, entry -> startCall(topic, facts, scenarioId, null, entry = entry) },
            onStartStarter = { sc, entry -> startCall(sc.promptBlurb, emptyList(), sc.id, sc, entry = entry) },
            onStartTopic = { topic, blurb, entry -> startCall(topic, emptyList(), null, null, blurb, entry) },
            // A call about a subject the learner names once it starts.
            onStartOwnTopic = {
                startCall("", emptyList(), null, null,
                    entry = com.roro.futurevoice.talk.TalkEntry.TALK_OWN_TOPIC, learnerPicksTopic = true)
            },
            onSavePersona = app::savePersona,
            // They all live on Watch — that IS the collection.
            onAllScenarios = { showTopics = false; tab = HomeTab.WATCH },
        )

        RootRoute.Activity -> ActivityScreen(
            language = state.targetLanguage,
            onOpenTalk = { detailSessionId = it },
            onBack = { showActivity = false },
            // Every routine line is a door to that kind of practice.
            onStartTalk = { showActivity = false; DeepLinkInbox.requestFreeTalk(com.roro.futurevoice.talk.TalkEntry.ROUTINE) },
            onOpenReview = { showActivity = false; showDueReview = true },
            onOpenRoutineReview = {
                gateScope.launch {
                    val deck = routineDeck(context,
                        goal = com.roro.futurevoice.data.GoalStore.target(context,
                            com.roro.futurevoice.data.StudyPlan.Kind.REVIEW)
                            ?: com.roro.futurevoice.data.StudyPlan.Kind.REVIEW.defaultAmount,
                        language = state.targetLanguage, level = state.level)
                    // No cards but lines to say: straight to the lines.
                    if (deck.first.isEmpty() && deck.second.isNotEmpty()) {
                        shadowHand = deck.second; shadowAt = 0
                    } else routineReview = deck
                }
            },
            onOpenTest = { showActivity = false; tab = HomeTab.PRACTICE },
        )

        // Everything snoozed whose time has come, both kinds together — the
        // promise the learner made to themselves, kept.
        RootRoute.DueReview -> StudyDeckHost(
            kind = null,
            language = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            level = state.level,
            focus = focusStudyItem,
            asSheet = true,
            onBack = { showDueReview = false; focusStudyItem = null },
        )

        // A sheet over the routine page, as iOS presents it.
        RootRoute.RoutineReview -> {
            val deck = routineReview ?: (emptyList<StudyDeckItem>() to emptyList())
            StudyDeckHost(
                kind = null,
                language = state.targetLanguage,
                nativeLanguage = state.nativeLanguage,
                level = state.level,
                hand = deck.first,
                handTitle = stringResource(R.string.review),
                emptyTitle = stringResource(R.string.all_caught_up),
                emptyMessage = stringResource(
                    R.string.words_expressions_and_sentences_from_your_talks_show_up_here_9e17d7),
                nextStep = if (deck.second.isEmpty()) null else StudyDeckNextStep(
                    title = stringResource(R.string.next_shadowing),
                    icon = Icons.Filled.GraphicEq,
                    action = { shadowHand = deck.second; shadowAt = 0; routineReview = null },
                ),
                onBack = { routineReview = null },
            )
        }

        is RootRoute.StudyDeck -> StudyDeckHost(
            kind = r.kind,
            language = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            level = state.level,
            onBack = { studyDeckKind = null },
        )

        is RootRoute.Person -> CounterpartDetailScreen(
            counterpartId = r.id,
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

        RootRoute.People -> FindPeopleScreen(
            language = state.targetLanguage,
            persona = state.persona,
            onEditProfile = { editProfileStep = 0; editProfile = true },
            onOpenPerson = { personDetailId = it },
            // iOS WatchTab's `onCompose`: close the page, open Watch's
            // writing door with this person and nothing written yet.
            onCompose = { person ->
                WatchComposeRequest.pending.value = person to ""
                showPeople = false; tab = HomeTab.WATCH
            },
            // A past talk on a card pushes its book; back returns to the card.
            onOpenTalk = { detailSessionId = it },
            onPickUp = { p, meet ->
                callCastVoice = p.voice_preset_id.takeIf { it.isNotBlank() }
                callCounterpartId = p.id
                gate {
                    callCast = com.roro.futurevoice.talk.ConversationEngine.Cast(meet(), pickUp = true)
                    callTopic = ""; callFacts = emptyList(); callBlurb = ""; callScenarioId = null
                    showPeople = false; inCall = true
                }
            },
            onTalk = { p, meet ->
                callCastVoice = p.voice_preset_id.takeIf { it.isNotBlank() }
                // The talk saves as an ordinary Session carrying this, so the
                // person's card lists it and every review mechanism works on
                // it for free. The local row's id IS the remote persona's.
                callCounterpartId = p.id
                gate {
                    // Cast as the person the meeting saved — the met row, or
                    // the pool row materialized (iOS `onTalk(savedPerson())`),
                    // so the call reads the fields iOS reads.
                    callCast = com.roro.futurevoice.talk.ConversationEngine.Cast.of(meet())
                    callTopic = ""; callFacts = emptyList(); callBlurb = ""; callScenarioId = null
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
        is RootRoute.Finished -> FinishedBooksScreen(
            books = r.books,
            onOpen = { book ->
                if (book.isTalk) detailSessionId = book.id else bookScenarioId = book.id
            },
            onBack = { finishedBooks = null },
        )

        RootRoute.CreditGuide -> CreditGuideScreen(onBack = { showCreditGuide = false })

        RootRoute.PlanPage -> PlanPageScreen(
            onOpenCreditGuide = { showCreditGuide = true },
            onOpenInvite = { showInvite = true },
            onBack = { showPlanPage = false },
        )

        RootRoute.Invite -> InviteScreen(onBack = { showInvite = false })

        is RootRoute.SpeechChallenge -> com.roro.futurevoice.ui.speech.SpeechChallengeScreen(
            challengeId = r.id,
            native = state.nativeLanguage,
            level = state.level,
            suggestedName = state.persona?.displayName.orEmpty(),
            onBack = { speechChallengeId = null },
        )

        RootRoute.SpeechChallenges -> com.roro.futurevoice.ui.speech.SpeechChallengeListScreen(
            language = state.targetLanguage,
            onOpen = { speechChallengeId = it.id },
            onBack = { showSpeechChallenges = false },
        )

        RootRoute.ShadowBrowser -> ShadowBrowserScreen(
            language = state.targetLanguage,
            // iOS presents the drill as a sheet OVER the list: closing it
            // returns here, so the list stays under the hand.
            onShadow = { turn ->
                shadowHand = listOf(com.roro.futurevoice.data.ShadowPicks.Pick(turn, "")); shadowAt = 0
            },
            onBack = { showShadowBrowser = false },
        )

        RootRoute.PublicIntro -> PublicIntroScreen(
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

        is RootRoute.MyProfile -> MyProfileScreen(
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            showsDone = r.sheet,
            onBack = { if (r.sheet) showMyProfileSheet = false else showMyProfile = false },
            onEditProfile = { editProfileStep = 0; editProfile = true },
        )

        RootRoute.Privacy -> PrivacyScreen(
            voiceId = state.voiceId,
            // Withdrawing deletes the model, so the app has no voice to hold
            // a call with — the flow has to ask for a new one, which is what
            // reopening setup does.
            onVoiceDeleted = { showPrivacy = false; showMe = false; app.reopenSetup() },
            onBack = { showPrivacy = false },
        )

        RootRoute.Me -> MeScreen(
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
            onVoiceRecorded = app::adoptRecordedVoice,
            onPickAppLanguage = { code ->
                app.setNativeLanguage(code)
                // Every string on screen was resolved from a context built at
                // attach time; only a fresh one speaks the new language.
                (localActivity as? android.app.Activity)?.recreate()
            },
            onOpenPeople = { showMe = false; showPeople = true },
            onOpenPlanPage = { showPlanPage = true },
            voiceId = state.voiceId,
            voiceAccentId = state.voiceAccentId,
            onAccentApplied = app::adoptRemixedVoice,
            onApplyDefaultAccent = app::applyDefaultAccent,
            voiceIsStandIn = state.voiceIsStandIn,
            voiceQueuedUntil = state.voiceQueuedUntil,
            onChooseStandIn = app::chooseStandInVoice,
            onOpenProfile = { showMyProfile = true },
            onOpenPaywall = { BillingGate.showPaywall.value = true },
            onSignOut = { showMe = false; app.signOut() },
            onOpenPrivacy = { showPrivacy = true },
            onRestored = app::adoptRestoredData,
            onBack = { dismissMe() },
        )

        RootRoute.Call ->
          Box(Modifier.fillMaxSize().graphicsLayer {
              alpha = if (TalkMorph.active) TalkMorph.callAlpha.value else 1f }) {
            TalkScreen(
                voiceId = state.voiceId ?: "",
                targetLanguage = state.targetLanguage,
                nativeLanguage = state.nativeLanguage,
                level = state.level,
                persona = state.persona,
                topic = callTopic,
                topicBlurb = callBlurb,
                newsFacts = callFacts,
                scenarioId = callScenarioId,
                initialOpener = callOpener,
                cast = callCast,
                castVoiceId = callCastVoice,
                counterpartId = callCounterpartId,
                resume = callResume,
                entry = callEntry,
                learnerPicksTopic = callPicksTopic,
                onExit = {
                    // A call that flew in from the ring flies back to it.
                    TalkMorph.close(morphScope) {
                        if (callFromHomeCard) deepenPending = true
                        backupPending = true
                        callFromHomeCard = false
                        inCall = false; callTopic = ""; callFacts = emptyList(); callBlurb = ""
                        callScenarioId = null; callOpener = ""; callCast = null
                        callCastVoice = null; callCounterpartId = null; callResume = null
                        callEntry = com.roro.futurevoice.talk.TalkEntry.OTHER
                        callPicksTopic = false
                    }
                },
            )
          }

        RootRoute.Tabs -> {
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
          // The routine builder sits over the Talk tab, because that is where
          // it goes when done: into the Activity chip in the header (iOS
          // `RootView.tabs(buildingRoutine:)`).
          LaunchedEffect(buildingRoutine) { if (buildingRoutine) tab = HomeTab.TALK }
          Box(Modifier.fillMaxSize()) {
          // Held while the sheet slides away, so it doesn't empty mid-exit.
          // A tab's own page sheet (the week archive, Your scenarios) comes
          // after these: one sheet at a time.
          val pageSheet by TabPageSheet.current
          var sheetShown by remember { mutableStateOf(tabSheetStack) }
          var pageShown by remember { mutableStateOf(pageSheet) }
          if (tabSheetStack != null) { sheetShown = tabSheetStack; pageShown = null }
          else if (pageSheet != null) { pageShown = pageSheet; sheetShown = null }
          IosSheetHost(
            presented = tabSheetStack != null || pageSheet != null,
            onDismiss = {
                when {
                    showMe -> dismissMe()
                    showPeople -> { showPeople = false; personDetailId = null }
                    showDueReview -> { showDueReview = false; focusStudyItem = null }
                    else -> pageSheet?.onDismiss?.invoke()
                }
            },
            sheet = {
                sheetShown?.let { stack ->
                    IosNavStack(stack = stack, onPop = { popRoute(stack.last()) },
                        pageKey = { it.key }) { DrawRoute(it) }
                }
                pageShown?.content?.invoke()
            },
            background = {
          HomeScreen(
            state = state,
            onStartCall = { topic, facts, scenarioId, entry -> startCall(topic, facts, scenarioId, null, entry = entry) },
            onStartStarter = { sc, entry -> startCall(sc.promptBlurb, emptyList(), sc.id, sc, entry = entry) },
            onStartTopic = { topic, blurb, entry -> startCall(topic, emptyList(), null, null, blurb, entry) },
            onOpenTopics = { showTopics = true },
            onOpenMe = { showMe = true },
            onOpenBook = { bookScenarioId = it },
            onOpenPeople = { showPeople = true },
            onOpenProfile = { showMyProfileSheet = true },
            // The Watch map's person card (iOS `SkyPersonCard`): Talk is a call
            // with them, Watch a scene of the two of them past the hellos.
            onPickUpWithPerson = { c ->
                callCast = com.roro.futurevoice.talk.ConversationEngine.Cast(c, pickUp = true)
                callCastVoice = c.voicePresetId.takeIf { it.isNotBlank() }
                callCounterpartId = c.id
                gate {
                    callTopic = ""; callFacts = emptyList(); callScenarioId = null
                    callEntry = com.roro.futurevoice.talk.TalkEntry.WATCH_PERSON
                    inCall = true
                }
            },
            onTalkWithPerson = { c ->
                // A met stranger is cast from their saved row, as on iOS.
                callCast = com.roro.futurevoice.talk.ConversationEngine.Cast.of(c)
                callCastVoice = c.voicePresetId.takeIf { it.isNotBlank() }
                callCounterpartId = c.id
                gate {
                    callTopic = ""; callFacts = emptyList(); callScenarioId = null
                    callEntry = com.roro.futurevoice.talk.TalkEntry.WATCH_PERSON
                    inCall = true
                }
            },
            onWatchWithPerson = { c -> gateScene {
                gateScope.launch {
                    val sc = meetingScenario(context, c, state.targetLanguage)
                    watchReplay = false; watchScenarioId = sc.id
                }
            } },
            onOpenFinished = { finishedBooks = it },
            onOpenActivity = { showActivity = true },
            onOpenEffort = { showEffort = true },
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
            onOpenSpeechChallenge = { speechChallengeId = it.id },
            onOpenAllSpeechChallenges = { showSpeechChallenges = true },
            // The dictionaries. Until now the library had no in-app entrance
            // at all — only the widget's deep link reached it.
            onOpenWordsAll = { library = LibraryKind.WORDS },
            onOpenExpressionsAll = { library = LibraryKind.EXPRESSIONS },
            onOpenSentencesAll = { showSentences = true },
            onOpenDueReview = { showDueReview = true },
            // A book's Grammar chapter: that talk's sentence cards.
            onOpenSessionDeck = { deckSessionId = it; showDeck = true },
            onSwitchLanguage = app::switchLanguage,
            // iOS `ConversationHome`: the header's "Add a language" presents
            // `AddLanguageSheet` right here, over the home.
            onAddLanguage = { showAddLanguage = true },
            deepenPending = deepenPending,
            onDeepenConsumed = { deepenPending = false },
            backupPending = backupPending,
            onBackupConsumed = { backupPending = false },
            // A tab's first-visit guide never rises over a sheet the root owns.
            guideBlocked = paywalled || showIntroPreview || state.levelUp != null ||
                referralJoin != null || welcomeMinutes != null || updatePending != null || showAgeCheck ||
                showWhatsNew || buildingRoutine || firstRunHeld,
        )
            },
          )
          if (buildingRoutine) RoutineOnboardingOverlay(onFinished = {
              OnboardingFlags.markSeen(context, OnboardingFlags.DAILY_CALL)
              OnboardingFlags.markSeen(context, OnboardingFlags.WEEKLY_RHYTHM)
              dailyCallOnboarded = true
          })
          }
        }
    }
    }
    IosNavStack(
        stack = rootStack,
        // A committed back (system back, predictive gesture, edge swipe):
        // exactly what the page's own back button does.
        onPop = { popRoute(rootStack.last()) },
        animates = { from, to -> rootPushes(from, to, deckPushed) },
        pageKey = { it.key },
    ) { r -> DrawRoute(r) }
    // The plans, OVER whatever raised them (iOS presents `PaywallView` as a
    // sheet from the screen on top). It used to be one branch of the page
    // switch above, BELOW the shadow, scene and deck pages — so a 402 there
    // set the flag and nothing appeared until the page was closed, and a
    // branch that replaced the page would have thrown away a scene mid-play
    // (re-entering it writes a fresh take, a second scene count).
    if (paywalled) PaywallDialog(onDismiss = { BillingGate.showPaywall.value = false })
    // Not enough talk time for a scene, said at the tap (2026-10-19).
    val sceneShort by BillingGate.showSceneShort.collectAsStateWithLifecycle()
    if (sceneShort) AllowanceSpentSheet(SpentPool.TALK,
        onReview = { BillingGate.showSceneShort.value = false },
        onUpgrade = { BillingGate.showSceneShort.value = false; BillingGate.showPaywall.value = true },
        onDismiss = { BillingGate.showSceneShort.value = false })
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

internal data class PendingLaunch(val topic: String, val facts: List<String>, val scenarioId: String?,
                                  /** An unsaved ready-made situation, saved once the gate passes. */
                                  val mint: Scenario? = null,
                                  /** Context told to the call beside the topic. */
                                  val blurb: String = "",
                                  val entry: String = com.roro.futurevoice.talk.TalkEntry.OTHER,
                                  /** The topics page's "my own topic" (iOS `runOwnTopic`). */
                                  val ownTopic: Boolean = false)

/**
 * A call launched from a Talk surface (the home, the topics page): the
 * microphone is asked for at the tap, and a refusal says why the tap did
 * nothing. [onStartOwnTopic] is the topics page's "my own topic".
 */
@Composable
internal fun rememberCallLauncher(
    onStartCall: (topic: String, newsFacts: List<String>, scenarioId: String?, entry: String) -> Unit,
    onStartStarter: (Scenario, entry: String) -> Unit,
    onStartTopic: (topic: String, blurb: String, entry: String) -> Unit,
    onStartOwnTopic: () -> Unit,
): (PendingLaunch) -> Unit {
    var pendingLaunch by remember { mutableStateOf<PendingLaunch?>(null) }
    var micDenied by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) pendingLaunch?.let { p ->
            when {
                p.ownTopic -> onStartOwnTopic()
                p.mint != null -> onStartStarter(p.mint, p.entry)
                p.blurb.isNotEmpty() -> onStartTopic(p.topic, p.blurb, p.entry)
                else -> onStartCall(p.topic, p.facts, p.scenarioId, p.entry)
            }
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
    return { p: PendingLaunch ->
        pendingLaunch = p
        permission.launch(Manifest.permission.RECORD_AUDIO)
    }

}

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
    /** The last argument is the screen it came from ([com.roro.futurevoice.talk.TalkEntry]). */
    onStartCall: (topic: String, newsFacts: List<String>, scenarioId: String?, entry: String) -> Unit,
    /** A ready-made situation (`StarterSituation`), saved only once the tap passes the gate. */
    onStartStarter: (Scenario, entry: String) -> Unit = { _, _ -> },
    /** A topic with its own context — an exam question, a topic from the
     *  learner's field (iOS `runExam` / `runFieldTopic`). */
    onStartTopic: (topic: String, blurb: String, entry: String) -> Unit = { _, _, _ -> },
    /** The topics page's "my own topic" (iOS `runOwnTopic`). */
    onStartOwnTopic: () -> Unit = {},
    /** The bottom row's "Find a topic" → the topics page (iOS `TalkTopicsPage`). */
    onOpenTopics: () -> Unit = {},
    onOpenMe: () -> Unit,
    onOpenPractice: () -> Unit = {},
    onOpenDeck: () -> Unit = {},
    onOpenWords: () -> Unit = {},
    onOpenExpressions: () -> Unit = {},
    onOpenTalk: (String) -> Unit = {},
    onWatch: (String) -> Unit = {},
    onOpenPeople: () -> Unit = {},
    /** The learner in the middle of the Watch map — their profile. */
    onOpenProfile: () -> Unit = {},
    /** The Watch map's person card: a call with them (gated here). */
    onTalkWithPerson: (com.roro.futurevoice.data.Counterpart) -> Unit = {},
    /** The card's "Continue the last talk" (gated here). */
    onPickUpWithPerson: (com.roro.futurevoice.data.Counterpart) -> Unit = {},
    /** The Watch map's person card: a scene of the two of them (gated here). */
    onWatchWithPerson: (com.roro.futurevoice.data.Counterpart) -> Unit = {},
    /** Practice's header seal → the finished-books page, with the books it counted. */
    onOpenFinished: (List<FinishedBook>) -> Unit = {},
    onOpenActivity: () -> Unit = {},
    /** Progress's effort card → its page (iOS `EffortDetailView`). */
    onOpenEffort: () -> Unit = {},
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
    onOpenSpeechChallenge: (com.roro.futurevoice.data.SpeechScript) -> Unit = {},
    onOpenAllSpeechChallenges: () -> Unit = {},
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
    /** Any call has just closed — the once-only backup offer may follow. */
    backupPending: Boolean = false,
    onBackupConsumed: () -> Unit = {},
) {
    val context = LocalContext.current
    var showDeepen by remember { mutableStateOf(false) }
    /** The situation player sheet (iOS `PlaylistButton`'s `.sheet`). */
    var showPlayer by remember { mutableStateOf(false) }
    // "Why & how" — each tab's guide, the first time it is opened (iOS
    // `RootTabView.offerPageIntro`).
    PageIntroHost(tab.guidePage(), blocked = guideBlocked || showDeepen)

    // The call's first word, on disk before the tap. Synthesizing the
    // openers here costs one round trip per NEW line, once, and takes the
    // gateway's own synthesis round trip out of the front of every call
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

    // iOS `maybeOfferBackup`: after the third finished talk, once, while sync
    // is off, never on top of the deepen sheet. iOS offers its iCloud here;
    // Android offers the learner's Google Drive.
    var showBackupOffer by remember { mutableStateOf(false) }
    LaunchedEffect(backupPending) {
        if (!backupPending) return@LaunchedEffect
        onBackupConsumed()
        kotlinx.coroutines.delay(900)
        if (showDeepen) return@LaunchedEffect
        val prefs = context.getSharedPreferences("futurevoice", 0)
        if (prefs.getBoolean(BACKUP_OFFERED_KEY, false) || !state.signedIn || state.isAnonymous ||
            com.roro.futurevoice.sync.SyncEngine.shared(context).isEnabled) return@LaunchedEffect
        val talks = com.roro.futurevoice.data.SessionStore.shared(context)
            .load(state.targetLanguage).count { it.endedAt != null }
        if (talks >= 3) {
            prefs.edit().putBoolean(BACKUP_OFFERED_KEY, true).apply()
            showBackupOffer = true
        }
    }
    if (showBackupOffer) BackupOfferSheet(onDismiss = { showBackupOffer = false })

    if (showDeepen) {
        PersonaDeepenSheet(
            persona = state.persona,
            nativeLanguage = state.nativeLanguage,
            targetLanguage = state.targetLanguage,
            onSave = onSavePersona,
            onDismiss = { showDeepen = false },
        )
    }

    val launchCall = rememberCallLauncher(onStartCall, onStartStarter, onStartTopic, onStartOwnTopic)
    fun launch(topic: String, facts: List<String>, scenarioId: String? = null, mint: Scenario? = null,
               blurb: String = "", entry: String) =
        launchCall(PendingLaunch(topic, facts, scenarioId, mint, blurb, entry))

    // Writing a situation on the Watch map: the tab bar steps aside for the
    // box, and the title for Cancel (iOS `WatchCreation`).
    val watchCreating by WatchCreation.creating.collectAsStateWithLifecycle()
    val writingSituation = tab == HomeTab.WATCH && watchCreating
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
                        // Writing a situation, the title steps aside for
                        // Cancel in its place (top left, like any compose
                        // screen); the options on the right stay.
                        if (writingSituation) {
                            com.roro.futurevoice.ui.brand.IosGlassTextButton(stringResource(R.string.cancel),
                                onClick = { WatchCreation.cancelTick.value += 1 })
                        } else {
                            val title = stringResource(tab.label)
                            Text(title, style = DisplayFace.style(title,
                                MaterialTheme.typography.headlineMedium))
                        }
                    },
                    actions = {
                        // iOS 26 toolbar buttons: white glass, a circle for an
                        // icon and a capsule for icon + count.
                        // The people page opens from the WATCH header, as on iOS.
                        if (tab == HomeTab.WATCH) {
                            WatchHeaderActions(onOpenPeople = onOpenPeople)
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
            // Watch is the people map: the whole screen is its canvas, under
            // the header and the floating bar alike (iOS ignores both safe
            // areas there), and it pans itself.
            val canvas = t == HomeTab.WATCH
            Column(
                Modifier.then(if (canvas) Modifier else Modifier.padding(top = padding.calculateTopPadding()))
                    .fillMaxSize()
                    // A hidden tab stays composed but is neither measured nor
                    // placed: nothing drawn, no touches.
                    .then(if (t == tab) Modifier else Modifier.layout { _, _ -> layout(0, 0) {} })
                    .then(if (paged || canvas) Modifier
                        else Modifier.verticalScroll(pageScroll).padding(horizontal = 20.dp)),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                when (t) {
                    HomeTab.TALK -> {
                        TalkHero(
                            state = state,
                            enabled = state.voiceId != null,
                            onTap = { launch("", emptyList(), entry = com.roro.futurevoice.talk.TalkEntry.TALK_RING) },
                            onOpenActivity = onOpenActivity,
                            heroTop = padding.calculateTopPadding(),
                        )
                        // No card under the ring: the "tell me more about you" row
                        // was removed 2026-10-18 (iOS 3b927c6f), and the discover
                        // block moved behind "Find a topic" the same day (iOS
                        // deed6cf4) — the home is a launcher, not a feed.
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
                        onOpenChallenge = onOpenSpeechChallenge,
                        onOpenAllChallenges = onOpenAllSpeechChallenges,
                    )

                    // Watch: simulate the situation BEFORE it happens. Scenarios
                    // are reusable templates — a tap writes a fresh take.
                    HomeTab.WATCH -> WatchTabBody(
                        language = state.targetLanguage,
                        visible = tab == HomeTab.WATCH,
                        enabled = state.voiceId != null,
                        onWatch = onWatch,
                        meName = state.persona?.displayName.orEmpty(),
                        onOpenProfile = onOpenProfile,
                        onTalkWith = onTalkWithPerson,
                        onPickUpWith = onPickUpWithPerson,
                        onWatchWith = onWatchWithPerson,
                        onOpenTalk = onOpenTalk,
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
                        onTalkScenario = { sc -> onStartCall(sc.promptBlurb, emptyList(), sc.id, com.roro.futurevoice.talk.TalkEntry.PRACTICE_BOOK) },
                    )

                    HomeTab.PROGRESS -> ProgressBody(
                        onMeasuredLevel = onMeasuredLevel,
                        language = state.targetLanguage,
                        nativeLanguage = state.nativeLanguage,
                        onOpenAssessment = onOpenAssessment,
                        onOpenActivity = onOpenActivity,
                        onOpenEffort = onOpenEffort,
                        goalMinutes = LocalContext.current
                            .getSharedPreferences("futurevoice", 0)
                            .getInt("futurevoice.dailyGoalMinutes", 10),
                        // The advice on a measured page ends in "go talk", so the
                        // page gets the door rather than describing one.
                        onStartTalk = { onTabChange(HomeTab.TALK) },
                    )
                }
                // Room to scroll the last item up past the floating bar —
                // and on Talk past the button row above it (iOS 88 pt).
                if (!paged && !canvas) Spacer(Modifier.height(IosTabBarClearance + (if (t == HomeTab.TALK) 64.dp else 0.dp))
                    .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.navigationBars))
            }

          }
        }
        // Talk's bottom row (iOS `ConversationHome`'s overlay, 2026-10-18,
        // founder): the situation player on the left, "Find a topic" centred,
        // the quick quiz's face on the right. The two side slots take equal
        // widths so the centre never moves. Above the floating bar, fixed
        // while the page scrolls under it. 21 dp in from the edges, flush with
        // the tab bar's capsule: measured off iOS, where the row lands at 21pt
        // (its `.padding(16)` notwithstanding).
        if (tab == HomeTab.TALK && !writingSituation) {
            Row(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.navigationBars)
                    .padding(start = 21.dp, end = 21.dp, bottom = 76.dp + 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    PlaylistButton(onClick = { showPlayer = true })
                }
                // Drawn exactly like Watch's "New situation": glass capsule,
                // accent label.
                com.roro.futurevoice.ui.brand.IosGlassButton(onClick = onOpenTopics,
                    modifier = Modifier.height(50.dp)) {
                    Icon(Icons.Filled.AutoAwesome, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.find_a_topic), style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary,
                        maxLines = 1)
                }
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
                    QuickQuizButton(language = state.targetLanguage, native = state.nativeLanguage,
                        level = state.level)
                }
            }
        }
        // The feather under the floating bar (iOS `tabBarScrollFeather`):
        // from the physical bottom edge, 44 dp of page colour and a 72 dp
        // ramp to transparent above it, so pages dissolve as they slide
        // under the bar instead of running razor-sharp off the screen.
        androidx.compose.animation.AnimatedVisibility(
            visible = !writingSituation,
            enter = androidx.compose.animation.fadeIn(androidx.compose.animation.core.tween(300)) +
                androidx.compose.animation.slideInVertically(androidx.compose.animation.core.tween(300)) { it },
            exit = androidx.compose.animation.fadeOut(androidx.compose.animation.core.tween(300)) +
                androidx.compose.animation.slideOutVertically(androidx.compose.animation.core.tween(300)) { it },
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            Box(contentAlignment = Alignment.BottomCenter) {
                ScrollEdgeFeather(color = AppSurfaces.ground)
                IosTabBar(selected = tab, onSelect = onTabChange)
            }
        }
        // The player floats over the page, the bar included (iOS sheet).
        ScenePlayerSheet(visible = showPlayer, state = state,
            topInset = padding.calculateTopPadding(), onDismiss = { showPlayer = false })
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
                     onOpenActivity: () -> Unit,
                     /** Where the hero starts at rest: the page's top padding,
                      *  i.e. the header with the status bar in it. */
                     heroTop: androidx.compose.ui.unit.Dp) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    // The FIRST frame is written from the real numbers (iOS `heroLine`:
    // `HeroGreeting.live()` reads the stores directly rather than painting a
    // placeholder that a later read corrects). Zero as a placeholder read as
    // "no talks yet", so coming back to Talk flashed "Ready for your first
    // talk?" before the real line. Saveable, so a page pushed over the tabs
    // and popped finds them still here. -1 = not known yet: no line at all
    // rather than a wrong one.
    var seconds by androidx.compose.runtime.saveable.rememberSaveable {
        mutableStateOf(TalkTimeLog.secondsToday(context))
    }
    var sessionCount by androidx.compose.runtime.saveable.rememberSaveable(state.targetLanguage) {
        mutableStateOf(SessionStore.shared(context).cachedCount(state.targetLanguage) ?: -1)
    }
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
    val theme = FutureselfTheme.stored(context)

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
    // The hero's top is the page's top padding, known before the first
    // frame. It used to be MEASURED and adopted from a settle-sample (iOS's
    // way), starting from 0 — so a cold launch drew the ring low and lifted
    // it, greeting and all, a quarter-second later (founder: the Talk tab
    // "clunks" on open). iOS fixed the same jump by seeding a close guess
    // (2026-09-28); here the exact value is at hand.
    val heroTopPx = with(density) { heroTop.toPx() }
    // An unfolded foldable or a tablet (≥ 600 dp across) is the one
    // exception: the ring is a fixed 280 dp, so centring it on a screen that
    // wide left it floating in empty space with the list pushed to the
    // bottom edge (founder, 2026-10-08, on a Z Fold). There the hero takes
    // only its own floor and the list below rises into view.
    val wideWindow = with(density) {
        androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.width.toDp()
    } >= 600.dp
    val heroHeight = with(density) {
        val offset = (RING_DIAMETER / 2 + RING_TAIL).toPx()
        if (wideWindow) 380.dp
        else maxOf(380.dp.toPx(), screenHeightPx / 2f + offset - heroTopPx).toDp()
    }

    Column(
        Modifier
            .fillMaxWidth()
            .height(heroHeight)
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        // No spacing of its own (iOS `VStack(spacing: 0)`): the two weighted
        // spacers place the question, and the ring's centre must sit exactly
        // `RING_TAIL + radius` above the bottom — a 20 dp gap here put it
        // 20 dp off the midline the height is solved for.
    ) {
        Spacer(Modifier.weight(1f))
        // Cached once written (iOS `@State heroLine`): the line never
        // changes while it is on screen, only when its inputs do.
        val computed = if (sessionCount < 0) "" else HeroGreeting.text(HeroGreeting.Input(
            sessionCount = sessionCount,
            todaySpokenSeconds = seconds,
            dailyGoalMinutes = goalMinutes,
        ))
        var heroLine by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("") }
        if (computed.isNotEmpty() && computed != heroLine) heroLine = computed
        val line = heroLine
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

/** iOS's `talkRing` frame. The tail below it is what the centring solves for. */
private val RING_DIAMETER = 280.dp
private val RING_TAIL = 20.dp

/**
 * Discover — what to talk about today (`DiscoverSection`). The chips are the
 * learner's purposes (`LearningPurposeStore.chips`): each purpose's own chip
 * first, in the order picked, then news and their own situations. Never
 * answered = the row as it always was (News · Everyday · Scenarios). One
 * full-width card list on the 20pt grid; a horizontal rail read as posters
 * and this reads as a list.
 */
@Composable
@OptIn(ExperimentalFoundationApi::class)
internal fun DiscoverSection(
    state: AppState,
    enabled: Boolean,
    onPickNews: (SuggestedTopic) -> Unit,
    onPickScenario: (Scenario) -> Unit,
    /** A ready-made situation, possibly not saved yet (`StarterSituation`). */
    onPickStarter: (Scenario) -> Unit = {},
    /** A common exam question (iOS `runExam`). */
    onPickExam: (com.roro.futurevoice.data.ExamTopic, com.roro.futurevoice.data.ExamKind) -> Unit = { _, _ -> },
    /** A topic made from the learner's own field (iOS `runFieldTopic`). */
    onPickTopic: (SuggestedTopic) -> Unit = {},
    onSavePersona: (com.roro.futurevoice.talk.UserPersona) -> Unit = {},
    /** The full collection — the Watch tab, which is where they all live. */
    onAllScenarios: () -> Unit = {},
) {
    /** The one settings page for the whole row (`DiscoverSettingsSheet`). */
    var showingSettings by remember { mutableStateOf(false) }
    /** Bumped when settings close, so the row re-reads its chips. */
    var settingsVersion by remember { mutableIntStateOf(0) }
    var newsFailed by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val chips = remember(settingsVersion, state.level) {
        com.roro.futurevoice.data.LearningPurposeStore.chips(context, state.level)
    }
    // The row opens on the first chip once, then stays where the learner put it.
    var discoverTab by remember {
        mutableStateOf(com.roro.futurevoice.capture.flags.TalkCaptureFlags.discoverTab ?: chips.first())
    }
    if (discoverTab !in chips) discoverTab = chips.first()
    val newsTab = discoverTab == DiscoverChip.NEWS
    val interests = state.persona?.interests.orEmpty()
    val language = state.targetLanguage
    /** Exam chip: which slice of the topic list is showing, and the filter. */
    var examShift by remember { mutableIntStateOf(0) }
    var exam by remember(language) {
        mutableStateOf(com.roro.futurevoice.data.LearningPurposeStore.exam(context, language))
    }
    val details = remember(settingsVersion) { com.roro.futurevoice.data.LearningPurposeStore.details(context) }
    fun fieldContext(chip: DiscoverChip): String? = PurposeTopicClient.field(chip, details)
    /** Field topics per chip, once loaded; the chips being written now. */
    val fieldTopics = remember { androidx.compose.runtime.mutableStateMapOf<DiscoverChip, List<SuggestedTopic>>() }
    val writingTopics = remember { androidx.compose.runtime.mutableStateListOf<DiscoverChip>() }
    val failedTopics = remember { androidx.compose.runtime.mutableStateListOf<DiscoverChip>() }
    /** Where in a field's pool the shown eight start. */
    val fieldShift = remember { androidx.compose.runtime.mutableStateMapOf<DiscoverChip, Int>() }

    /** `fresh`: the refresh button. Walk on through the pool while it has
     *  unseen topics; at its end, ask the server to grow it (capped there). */
    suspend fun loadFieldTopics(chip: DiscoverChip, fresh: Boolean) {
        if (fieldContext(chip) == null || chip in writingTopics) return
        val level = state.level
        if (!fresh) {
            PurposeTopicClient.cached(context, chip, details, language, level)?.let {
                fieldTopics[chip] = it; return
            }
        }
        if (fresh) fieldTopics[chip]?.let { pool ->
            val next = (fieldShift[chip] ?: 0) + PurposeTopicClient.SHOWN
            if (next < pool.size) { fieldShift[chip] = next; return }
        }
        writingTopics += chip
        failedTopics -= chip
        val before = fieldTopics[chip]?.size ?: 0
        try {
            val topics = runCatching {
                PurposeTopicClient.fetch(context, chip, details, language, level, refresh = fresh)
            }.getOrNull()
            if (!topics.isNullOrEmpty()) {
                fieldTopics[chip] = topics
                // Grown: show the new ones. Not grown (the pool is full): start over.
                fieldShift[chip] = if (fresh) (if (topics.size > before) before else 0) else 0
            } else if (fieldTopics[chip] == null) {
                failedTopics += chip
            }
        } finally { writingTopics -= chip }
    }

    /** Settings closed: the chips may have changed (stay on the chip if it
     *  is still there, else the new first one), the exam, the interests. */
    fun settingsClosed() {
        settingsVersion += 1
        val newChips = com.roro.futurevoice.data.LearningPurposeStore.chips(context, state.level)
        if (discoverTab !in newChips) discoverTab = newChips.first()
        val newExam = com.roro.futurevoice.data.LearningPurposeStore.exam(context, language)
        if (newExam != exam) { exam = newExam; examShift = 0 }
        val newDetails = com.roro.futurevoice.data.LearningPurposeStore.details(context)
        fieldTopics.keys.filter { PurposeTopicClient.field(it, newDetails) == null }.forEach { fieldTopics.remove(it) }
    }
    // A goal saved from somewhere else (the What's new card) reaches the row
    // through a store revision, like iOS re-reading on appear.
    val seenRevision = remember { mutableIntStateOf(revision) }
    LaunchedEffect(revision) {
        if (revision != seenRevision.intValue) { seenRevision.intValue = revision; settingsClosed() }
    }

    if (showingSettings) {
        DiscoverSettingsSheet(
            persona = state.persona,
            language = language,
            onSavePersona = onSavePersona,
            onDismiss = { showingSettings = false; settingsClosed() },
            onSaved = { settingsClosed() },
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
        } else topics = emptyList()
    }
    LaunchedEffect(language, revision) {
        scenarios = scenarioStore.load(language)
        people = CounterpartStore.shared(context).load()
    }

    /** The ready-made situations behind a situation chip. A tap starts the
     *  call; one already talked through carries a check. */
    @Composable
    fun StarterRows(starters: List<StarterSituation>) {
        starters.forEach { starter ->
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
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (chips.size > 3) {
                // Four chips and two buttons don't fit a phone in every
                // language; past three the chips scroll sideways, clipped
                // BEFORE the buttons and faded at that edge so the cut reads
                // as "slide for more" rather than a chip broken in half.
                Row(
                    Modifier.weight(1f)
                        .graphicsLayer { compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen }
                        .drawWithContent {
                            drawContent()
                            val fade = 20.dp.toPx()
                            drawRect(
                                androidx.compose.ui.graphics.Brush.horizontalGradient(
                                    listOf(androidx.compose.ui.graphics.Color.Black,
                                        androidx.compose.ui.graphics.Color.Transparent),
                                    startX = size.width - fade, endX = size.width),
                                topLeft = androidx.compose.ui.geometry.Offset(size.width - fade, 0f),
                                size = androidx.compose.ui.geometry.Size(fade, size.height),
                                blendMode = androidx.compose.ui.graphics.BlendMode.DstIn)
                        }
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    chips.forEach { c -> SegmentChip(stringResource(c.label), discoverTab == c) { discoverTab = c } }
                    Spacer(Modifier.width(16.dp))
                }
            } else {
                chips.forEach { c -> SegmentChip(stringResource(c.label), discoverTab == c) { discoverTab = c } }
                Spacer(Modifier.weight(1f))
            }
            // The row's own buttons as one group, spaced for a thumb — at the
            // row's 8 dp they read as one control and a tap hit the wrong one.
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                if (discoverTab == DiscoverChip.EXAM) {
                    DiscoverHeaderButton(onClick = { examShift += EXAM_SHOWN }) {
                        Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.other_topics),
                            tint = MaterialTheme.colorScheme.primary)
                    }
                } else if (fieldContext(discoverTab) != null) {
                    if (discoverTab in writingTopics) {
                        Box(Modifier.size(DiscoverHeaderIcon), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        }
                    } else {
                        val chip = discoverTab
                        DiscoverHeaderButton(onClick = { scope.launch { loadFieldTopics(chip, fresh = true) } }) {
                            Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.other_topics),
                                tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                } else if (newsTab && topics.isNotEmpty()) {
                    // iOS: the refresh slot exists only once there are stories,
                    // and while loading it holds the spinner in the same place.
                    if (loading) {
                        Box(Modifier.size(DiscoverHeaderIcon), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        }
                    } else {
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
                } else if (discoverTab == DiscoverChip.SCENARIOS) {
                    DiscoverHeaderButton(onClick = { composing = true }) {
                        Icon(Icons.Filled.Add,
                            contentDescription = stringResource(R.string.build_a_scenario),
                            tint = MaterialTheme.colorScheme.primary)
                    }
                }
                // One settings button whatever chip is showing — the chips,
                // the exam and the interests are one page.
                DiscoverHeaderButton(onClick = { showingSettings = true }) {
                    Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.talk_settings),
                        tint = MaterialTheme.colorScheme.primary)
                }
            }
        }

        when (discoverTab) {
            DiscoverChip.NEWS -> {
                if (interests.isEmpty()) {
                    // Nothing to build stories from yet — the fix is one tap, so
                    // offer it instead of an empty section.
                    DiscoverRow(
                        title = stringResource(R.string.add_interests),
                        icon = Icons.Filled.Add,
                        onClick = { showingSettings = true },
                    )
                } else if (topics.isEmpty()) {
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
            }
            DiscoverChip.EXAM -> {
                // Common questions of the picked exam, five at a time; refresh
                // shows the next five. Same card as a news story.
                val all = com.roro.futurevoice.data.ExamTopics.topics(exam, language)
                val start = if (all.isEmpty()) 0 else examShift % all.size
                (0 until minOf(EXAM_SHOWN, all.size)).map { all[(start + it) % all.size] }.forEach { topic ->
                    DiscoverRow(
                        title = topic.title,
                        caption = "${exam.examName} · ${topic.part}",
                        icon = Symbols.icon("graduationcap.fill"),
                        onClick = if (enabled) ({ onPickExam(topic, exam) }) else null,
                    )
                }
            }
            DiscoverChip.STUDY, DiscoverChip.WORK, DiscoverChip.INTERVIEW -> {
                // Topics from what the learner wrote about their field, then —
                // for work and interviews — the ready-made situations under
                // them. Nothing written yet: one row that says what writing it
                // buys, opening the settings.
                val chip = discoverTab
                val field = fieldContext(chip)
                LaunchedEffect(chip, field, language) { loadFieldTopics(chip, fresh = false) }
                val pool = fieldTopics[chip]
                if (field == null) {
                    DiscoverRow(
                        title = stringResource(when (chip) {
                            DiscoverChip.STUDY -> R.string.add_your_school_and_subject_for_topics_from_your_field
                            DiscoverChip.INTERVIEW -> R.string.add_the_role_you_re_applying_for_i_ll_ask_its_questions
                            else -> R.string.add_your_job_and_role_for_topics_from_your_work
                        }),
                        icon = Symbols.icon("square.and.pencil"),
                        onClick = { showingSettings = true },
                    )
                } else if (!pool.isNullOrEmpty()) {
                    val begin = (fieldShift[chip] ?: 0) % pool.size
                    (0 until minOf(PurposeTopicClient.SHOWN, pool.size)).map { pool[(begin + it) % pool.size] }
                        .forEach { t ->
                            DiscoverRow(
                                title = t.title,
                                icon = Symbols.icon(when (chip) {
                                    DiscoverChip.STUDY -> "book.fill"
                                    DiscoverChip.INTERVIEW -> "person.crop.square"
                                    else -> "briefcase.fill"
                                }),
                                onClick = if (enabled) ({
                                    onPickTopic(SuggestedTopic(title = t.title,
                                        blurb = PurposeTopicClient.launchBlurb(t, chip, details)))
                                }) else null,
                            )
                        }
                } else if (chip in failedTopics) {
                    TextButton(onClick = { scope.launch { loadFieldTopics(chip, fresh = true) } }) {
                        Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.couldn_t_write_topics_try_again),
                            style = MaterialTheme.typography.bodyMedium)
                    }
                } else {
                    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        Text(stringResource(R.string.writing_topics_for_your_field),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                chip.starters?.let { StarterRows(it) }
            }
            DiscoverChip.SCENARIOS -> {
                // The learner's own situations — ready-made ones live on their chips.
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
            else -> StarterRows(discoverTab.starters ?: StarterSituation.all)
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

/** iOS `DiscoverSection.examShown`: exam questions show five at a time. */
private const val EXAM_SHOWN = 5

/**
 * Best-effort glyph for a free-form interest category — the fallback is the
 * newspaper, because every story is at least news.
 */
internal fun categoryIcon(category: String?): androidx.compose.ui.graphics.vector.ImageVector {
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
        c.contains("fashion") -> Icons.Filled.Checkroom
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
    // The routine builder shrinks into this chip, so it says where it is
    // (iOS `RoutineHandoff`): its bounds, a bounce on landing, then the hint.
    val landed by RoutineHandoff.landed.collectAsStateWithLifecycle()
    val hint by RoutineHandoff.showHint.collectAsStateWithLifecycle()
    val bounce = remember { androidx.compose.animation.core.Animatable(1f) }
    LaunchedEffect(landed) {
        if (landed == 0) return@LaunchedEffect
        bounce.animateTo(1.3f, androidx.compose.animation.core.tween(120))
        bounce.animateTo(1f, androidx.compose.animation.core.spring(dampingRatio = 0.4f))
    }
    Box(Modifier.onGloballyPositioned { RoutineHandoff.chipBounds.value = it.boundsInRoot() }) {
    com.roro.futurevoice.ui.brand.IosGlassButton(onClick = {
        RoutineHandoff.showHint.value = false
        onClick()
    }) {
        val lit = days > 0 || keptToday
        Icon(
            if (lit) Icons.Filled.LocalFireDepartment else Icons.Filled.CalendarMonth,
            contentDescription = null,
            // iOS: `flame.fill`, orange only once today is kept.
            tint = if (keptToday) androidx.compose.ui.graphics.Color(0xFFFF9500)
            else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp).graphicsLayer { scaleX = bounce.value; scaleY = bounce.value })
        Spacer(Modifier.width(5.dp))
        Text(
            if (lit) stringResource(R.string.lld_day_streak_94de2a, maxOf(days, 1))
            else stringResource(R.string.activity),
            style = MaterialTheme.typography.bodyLarge.copy(
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold))
    }
    if (hint) RoutineHintPopover(onDismiss = { RoutineHandoff.showHint.value = false })
    }
}

/** "Your routine is here", hanging under the Activity chip (iOS's popover
 *  with its arrow on the top edge). */
@Composable
private fun RoutineHintPopover(onDismiss: () -> Unit) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    androidx.compose.ui.window.Popup(
        alignment = Alignment.TopCenter,
        offset = with(density) { androidx.compose.ui.unit.IntOffset(0, (44 + 10).dp.roundToPx()) },
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.PopupProperties(focusable = true),
    ) {
        val dark = androidx.compose.foundation.isSystemInDarkTheme()
        Column(
            Modifier.padding(8.dp)
                .shadow(12.dp, RoundedCornerShape(14.dp))
                .background(if (dark) androidx.compose.ui.graphics.Color(0xFF2C2C2E)
                    else androidx.compose.ui.graphics.Color.White, RoundedCornerShape(14.dp))
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(stringResource(R.string.your_routine_is_here), style = MaterialTheme.typography.titleSmall,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
            Text(stringResource(R.string.tap_to_see_it_or_change_it), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
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

/** Which call is on screen — retained across activity recreation (see [RootScreen]). */
class CallRoute : androidx.lifecycle.ViewModel() {
    val inCall = mutableStateOf(false)
    val topic = mutableStateOf("")
    val facts = mutableStateOf<List<String>>(emptyList())
    val blurb = mutableStateOf("")
    val scenarioId = mutableStateOf<String?>(null)
    val opener = mutableStateOf("")
    val cast = mutableStateOf<com.roro.futurevoice.talk.ConversationEngine.Cast?>(null)
    val castVoice = mutableStateOf<String?>(null)
    val counterpartId = mutableStateOf<String?>(null)
    val resume = mutableStateOf<com.roro.futurevoice.talk.Session?>(null)
    /** Launched from a Talk-home card (a scenario or a news story) — iOS
     *  `ConversationHome.callLaunch`, whose dismissal is the one moment the
     *  persona-deepen sheet is offered. The ring's free talk is not one. */
    val fromHomeCard = mutableStateOf(false)
    /** [com.roro.futurevoice.talk.TalkEntry] — telemetry only. */
    val entry = mutableStateOf(com.roro.futurevoice.talk.TalkEntry.OTHER)
    /** A "my own topic" call (topics page, iOS `CallLaunch.learnerPicksTopic`). */
    val picksTopic = mutableStateOf(false)
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

/**
 * A page of the app proper, as iOS's navigation stack would hold it. Each
 * carries what it needs to draw itself, so a page can still be drawn while
 * it slides away after its flag is already down.
 */
internal sealed interface RootRoute {
    val key: String
    data object Gate : RootRoute { override val key = "gate" }
    data object EditProfile : RootRoute { override val key = "editProfile" }
    data object ShadowHand : RootRoute { override val key = "shadowHand" }
    data class ShadowLine(val line: String) : RootRoute { override val key = "shadowLine" }
    data class Watch(val id: String) : RootRoute { override val key = "watch:$id" }
    data object Deck : RootRoute { override val key = "deck" }
    data class TalkBook(val id: String) : RootRoute { override val key = "talk:$id" }
    data class ScenarioBook(val id: String) : RootRoute { override val key = "scenario:$id" }
    data object Sentences : RootRoute { override val key = "sentences" }
    data class Library(val kind: LibraryKind) : RootRoute { override val key = "library:$kind" }
    data object Assessment : RootRoute { override val key = "assessment" }
    data object SayAgainPick : RootRoute { override val key = "sayAgainPick" }
    data object RoutineEditor : RootRoute { override val key = "routineEditor" }
    data object Activity : RootRoute { override val key = "activity" }
    data object Topics : RootRoute { override val key = "topics" }
    data object Effort : RootRoute { override val key = "effort" }
    data object DueReview : RootRoute { override val key = "dueReview" }
    data object RoutineReview : RootRoute { override val key = "routineReview" }
    data class StudyDeck(val kind: StudyScheduleStore.Kind) : RootRoute { override val key = "studyDeck:$kind" }
    data class Person(val id: String) : RootRoute { override val key = "person:$id" }
    data object People : RootRoute { override val key = "people" }
    data class Finished(val books: List<FinishedBook>) : RootRoute { override val key = "finished" }
    data object CreditGuide : RootRoute { override val key = "creditGuide" }
    data object PlanPage : RootRoute { override val key = "planPage" }
    data object Invite : RootRoute { override val key = "invite" }
    data object ShadowBrowser : RootRoute { override val key = "shadowBrowser" }
    data class SpeechChallenge(val id: String) : RootRoute { override val key = "speechChallenge:$id" }
    data object SpeechChallenges : RootRoute { override val key = "speechChallenges" }
    data object PublicIntro : RootRoute { override val key = "publicIntro" }
    data object Privacy : RootRoute { override val key = "privacy" }
    data class MyProfile(val sheet: Boolean) : RootRoute {
        override val key = if (sheet) "myProfileSheet" else "myProfile"
    }
    data object Me : RootRoute { override val key = "me" }
    data object Call : RootRoute { override val key = "call" }
    data object Tabs : RootRoute { override val key = "tabs" }
}

/**
 * Whether going from [from] to [to] is an iOS PUSH (slides, swipes back)
 * rather than a cover, a sheet or the call (swaps in place). Read off where
 * iOS presents each page — `docs/android-master-plan.md` "Pushed pages".
 * Me is a SHEET over the tabs ([IosSheetHost]) with its own stack inside it,
 * so it never appears here.
 */
internal fun rootPushes(from: RootRoute, to: RootRoute, deckPushed: Boolean): Boolean {
    val pageUnder = from !is RootRoute.Gate && from !is RootRoute.Call && from !is RootRoute.ShadowHand &&
        from !is RootRoute.ShadowLine && from !is RootRoute.EditProfile && from !is RootRoute.SayAgainPick &&
        from !is RootRoute.RoutineEditor && from !is RootRoute.DueReview && from !is RootRoute.StudyDeck &&
        from !is RootRoute.RoutineReview
    if (!pageUnder) return false
    return when (to) {
        // Books: `navigationDestination` from a shelf card, Activity, a
        // person, the finished shelf, a scene book's study record.
        is RootRoute.TalkBook, is RootRoute.ScenarioBook -> from !is RootRoute.Me &&
            // Find people pushes a talk book only from a person's card
            // ("Your talks together", a `NavigationLink` inside the sheet).
            (from !is RootRoute.People || to is RootRoute.TalkBook)
        // A scene: `SceneWatchView` / `WatchView` are pushed (Watch tab, book).
        is RootRoute.Watch -> from is RootRoute.Tabs || from is RootRoute.ScenarioBook || from is RootRoute.Person
        // "Review this talk" (book) and a Sentences row push `DrillView`;
        // every other deck is a sheet.
        RootRoute.Deck -> from is RootRoute.TalkBook || (deckPushed && from is RootRoute.Sentences)
        // Practice's library tiles; Progress's latest assessment; the
        // streak's Activity; the finished shelf.
        RootRoute.Sentences, is RootRoute.Library, RootRoute.ShadowBrowser,
        RootRoute.Assessment, is RootRoute.Finished, RootRoute.Effort -> from is RootRoute.Tabs
        // The streak's Activity, and the effort page's "Calendar and routine".
        RootRoute.Activity -> from is RootRoute.Tabs || from is RootRoute.Effort
        // Talk's "Find a topic" pushes the topics page.
        RootRoute.Topics -> from is RootRoute.Tabs
        // The Speech tab's challenge rows push the board.
        is RootRoute.SpeechChallenge -> from is RootRoute.Tabs || from is RootRoute.SpeechChallenges
        RootRoute.SpeechChallenges -> from is RootRoute.Tabs
        // Find people's own-people rows push the person.
        is RootRoute.Person -> from is RootRoute.People
        // Inside the Me sheet: Usage, Privacy, the public intro; inside
        // Usage: the guide and the invite.
        RootRoute.PlanPage, RootRoute.Privacy -> from is RootRoute.Me
        RootRoute.PublicIntro -> from is RootRoute.Me || from is RootRoute.People
        // Me's profile header pushes the one "me" page; from Watch it is a sheet.
        is RootRoute.MyProfile -> !to.sheet && from is RootRoute.Me
        RootRoute.CreditGuide, RootRoute.Invite -> from is RootRoute.PlanPage
        else -> false
    }
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
