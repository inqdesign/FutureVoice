package com.roro.futurevoice.ui

import androidx.compose.foundation.Canvas
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
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
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
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
import androidx.compose.material3.Button
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
import com.roro.futurevoice.ui.brand.BookCard
import com.roro.futurevoice.ui.brand.Books
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
import com.roro.futurevoice.talk.Scenario
import androidx.compose.material3.AlertDialog
import com.roro.futurevoice.talk.SuggestedTopic
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.TurnRole
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

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
    var showPrivacy by remember { mutableStateOf(false) }
    val referralJoin by com.roro.futurevoice.data.ReferralJoins.pending.collectAsStateWithLifecycle()
    referralJoin?.let { ReferralJoinSheet(join = it, onDismiss = com.roro.futurevoice.data.ReferralJoins::dismiss) }
    // A measured level-up, announced once wherever the learner happens to be.
    state.levelUp?.let { (from, to) ->
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
    var welcomeDone by remember { mutableStateOf(false) }
    var showMe by remember { mutableStateOf(false) }
    var showDeck by remember { mutableStateOf(false) }
    /** A per-item reminder's target (iOS `.reviewItem`): the card or word it named. */
    var focusCardId by remember { mutableStateOf<String?>(null) }
    /** A talk book's "Review this talk": the deck on that talk's cards. */
    var deckSessionId by remember { mutableStateOf<String?>(null) }
    var focusStudyItem by remember { mutableStateOf<StudyDeckItem?>(null) }
    var showActivity by remember { mutableStateOf(false) }
    var showAssessment by remember { mutableStateOf(false) }
    var library by remember { mutableStateOf<LibraryKind?>(null) }
    val paywalled by BillingGate.showPaywall.collectAsStateWithLifecycle()
    val gateScope = rememberCoroutineScope()
    /** Run a metered action, or raise the paywall. See [BillingGate]. */
    fun gate(action: () -> Unit) {
        gateScope.launch { BillingGate.start(AuthRepository(), action) }
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
                showMe = false; showDeck = false; library = null; detailSessionId = null
                bookScenarioId = null; watchScenarioId = null; shadowLine = null
                tab = HomeTab.TALK
            }
            is DeepLinkInbox.WidgetRoute.Book -> {
                tab = HomeTab.PRACTICE
                showMe = false; showDeck = false; library = null; watchScenarioId = null
                if (route.kind == "watch") bookScenarioId = route.id else detailSessionId = route.id
            }
            DeepLinkInbox.WidgetRoute.FreeTalk -> {
                tab = HomeTab.TALK
                gate {
                    showMe = false; showDeck = false; library = null; detailSessionId = null
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
    var pendingAccount by remember { mutableStateOf(false) }
    var dailyCallOnboarded by remember {
        mutableStateOf(OnboardingFlags.seen(context, OnboardingFlags.DAILY_CALL))
    }
    var onboardingPaywallSeen by remember {
        mutableStateOf(OnboardingFlags.seen(context, OnboardingFlags.PAYWALL))
    }
    // Null while unknown — the step must not flash for an account that turns
    // out to have nothing to buy, so it waits for the answer rather than
    // guessing at one.
    var onboardingNeedsPlan by remember { mutableStateOf<Boolean?>(null) }
    // Sign-up landed: the account act resolves itself with no second tap.
    LaunchedEffect(state.signedIn, state.isAnonymous) {
        if (state.signedIn && !state.isAnonymous) pendingAccount = false
    }
    LaunchedEffect(state.voiceId, dailyCallOnboarded) {
        if (state.voiceId != null && !onboardingPaywallSeen && onboardingNeedsPlan == null) {
            onboardingNeedsPlan = AccountStatus.load(AuthRepository())
                .also { BillingGate.remember(it) }
                .needsSubscription
            // Nothing to sell: mark it seen now, so the check is paid once.
            if (onboardingNeedsPlan == false) {
                OnboardingFlags.markSeen(context, OnboardingFlags.PAYWALL)
                onboardingPaywallSeen = true
            }
        }
    }
    var welcomePreview by remember { mutableStateOf(false) }
    // "Here is time to talk with your fluent self." The grant is otherwise
    // invisible — onboarding's paywall steps aside for any account with a
    // balance, so without this nobody is told the minutes exist (iOS
    // `ef9af00`). Once per install, and never to someone who has talked.
    var welcomeMinutes by remember { mutableStateOf<Int?>(null) }
    var startAfterWelcome by remember { mutableStateOf(false) }
    LaunchedEffect(state.voiceId, state.setupComplete) {
        if (state.voiceId == null || !state.setupComplete) return@LaunchedEffect
        FreeTalkWelcome.minutesToAnnounce(context)?.let { minutes ->
            FreeTalkWelcome.markShown(context)
            com.roro.futurevoice.core.Analytics.capture(
                "free_talk_welcome_shown", mapOf("minutes" to minutes))
            welcomeMinutes = minutes
        }
    }
    welcomeMinutes?.let { minutes ->
        FreeTalkWelcomeSheet(
            minutes = minutes,
            onStart = { startAfterWelcome = true; welcomeMinutes = null },
            onDismiss = { welcomeMinutes = null },
        )
    }
    // "Start talking" on the sheet opens the call the sheet was about.
    LaunchedEffect(startAfterWelcome) {
        if (startAfterWelcome) {
            startAfterWelcome = false
            com.roro.futurevoice.core.Analytics.capture(
                "free_talk_welcome_closed", mapOf("started" to true))
            callTopic = ""; callFacts = emptyList(); callScenarioId = null; inCall = true
        }
    }

    val morphScope = rememberCoroutineScope()
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
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
            onSaveVoice = { pendingAccount = true },
        )

        state.resolvingSession -> Loading()
        // The pitch before the ask — the five beats a first-time user must
        // agree with before an account means anything. Returning users
        // (stored session) never see it.
        !state.signedIn && !welcomeDone -> WelcomeScreen(
            onGetStarted = {
                welcomeDone = true
                // Account-free entry (iOS order): the server needs a session,
                // not an account — the sign-up asks to KEEP the voice, after
                // Meet.
                app.startAnonymous()
            },
            // A returning learner goes to the real sign-in instead, so their
            // voice and progress come back with them.
            onSignIn = { welcomeDone = true },
            // No invite link yet: redeeming needs an account, and iOS's
            // "capture the code, then sign in" path has no Android half. A
            // button that can only land on the sign-in screen would be the
            // sign-in link wearing a second name.
        )
        !state.signedIn -> SignInScreen(
            state,
            googleAvailable = app.isGoogleConfigured,
            onGoogleSignIn = app::signInWithGoogle,
            onSignIn = app::signIn,
            onDevSignIn = app::devSignIn,
        )
        // First-run answers before anything else — what to teach and how to
        // calibrate. (iOS order puts Welcome before sign-in; Android's
        // account-free entry arrives with the Google-auth work.)
        !state.setupComplete -> SetupFlowScreen(
            initialNative = state.nativeLanguage,
            initialTarget = state.targetLanguage,
            initialLevel = state.level,
            onBackToWelcome = app::signOut,
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
            onBack = { showDeck = false; focusCardId = null; deckSessionId = null },
        )

        detailSessionId != null -> TalkDetailScreen(
            sessionId = detailSessionId!!,
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

        bookScenarioId != null -> ScenarioBookScreen(
            scenarioId = bookScenarioId!!,
            language = state.targetLanguage,
            // A fresh take costs a scene count, so the wall is asked at the
            // tap here exactly as it is on the Watch tab.
            onWatch = { id -> gate { watchScenarioId = id } },
            onTalk = { sc -> gate {
                bookScenarioId = null
                callTopic = sc.promptBlurb; callFacts = emptyList(); callScenarioId = sc.id
                inCall = true
            } },
            onShadow = { shadowLine = it },
            onBack = { bookScenarioId = null },
        )

        // Above everything: an account that cannot spend must not be looking
        // at a call screen behind a sheet.
        paywalled -> PaywallScreen(onDismiss = { BillingGate.showPaywall.value = false })

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

        showActivity -> ActivityScreen(
            language = state.targetLanguage,
            onOpenTalk = { showActivity = false; detailSessionId = it },
            onBack = { showActivity = false },
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
        )

        showPeople -> FindPeopleScreen(
            language = state.targetLanguage,
            persona = state.persona,
            onOpenPerson = { personDetailId = it },
            onTalk = { p ->
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
                    callTopic = ""; callFacts = emptyList(); callScenarioId = null
                    showPeople = false; inCall = true
                }
            },
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

        // Light taps before the heavy ask (iOS order): persona cards build
        // the investment and the first call's context BEFORE the recording.
        state.personaResolved && state.persona == null -> PersonaIntakeScreen(
            initial = com.roro.futurevoice.talk.UserPersona(),
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onBackToSetup = { app.reopenSetup() },
            onFinish = app::savePersona,
        )

        // The crash/kill guard (iOS `resumeUnclaimedVoice`): an anonymous
        // session with a voice must not reach the tabs — its data dies with
        // the install. The flow reopens on the account step.
        state.signedIn && state.isAnonymous && state.voiceId != null && !state.restoringVoice ->
            AccountScreen(
                googleAvailable = app.isGoogleConfigured,
                onGoogleSignIn = app::signInWithGoogle,
                onAppleSignIn = app::signIn,
            )

        // No voice on the account: an Android user starts HERE — they clone
        // on Android (roadmap §1.2), they are not sent to an iPhone. Mic
        // permission is asked by the flow's record button via HomeScreen's
        // launcher pattern; the screen itself only records after it.
        !state.restoringVoice && state.voiceId == null -> CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onCloned = app::onVoiceCloned,
            // The sign-up is the flow's LAST act, not a gate in front of it:
            // by then the learner has heard the voice they are being asked to
            // keep. An anonymous session gets the ask; a real account skips
            // straight into the first call.
            signedIn = state.signedIn && !state.isAnonymous,
            onSaveVoice = { pendingAccount = true },
        )

        // The sign-up itself, raised by the clone flow's last act.
        pendingAccount -> AccountScreen(
            googleAvailable = app.isGoogleConfigured,
            onGoogleSignIn = app::signInWithGoogle,
            onAppleSignIn = app::signIn,
        )

        // The clone's first real job, introduced right after it exists — so
        // it reads as a promise rather than a permissions request.
        state.voiceId != null && !dailyCallOnboarded ->
            DailyCallOnboardingScreen(context) { dailyCallOnboarded = true }

        // The plans, offered ONCE at the end — so the first tap on Talk stops
        // being where the hard paywall introduces itself. Skipped silently
        // for anyone who has nothing to buy (already subscribed, or credited).
        state.voiceId != null && !onboardingPaywallSeen && onboardingNeedsPlan == true ->
            PaywallScreen(onDismiss = {
                OnboardingFlags.markSeen(context, OnboardingFlags.PAYWALL)
                onboardingPaywallSeen = true
            })

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
                        inCall = false; callTopic = ""; callFacts = emptyList()
                        callScenarioId = null; callOpener = ""; callCast = null
                        callCastVoice = null; callCounterpartId = null
                    }
                },
            )
          }

        else -> HomeScreen(
            state = state,
            onStartCall = { topic, facts, scenarioId ->
                // The paywall is asked here, at the TAP — every metered
                // launcher (free talk, a news story, a scenario, a widget
                // deep link) meets in this one callback, so one gate covers
                // them all. Met only as a 402, it would arrive after the call
                // screen was already up.
                gate {
                    callTopic = topic; callFacts = facts; callScenarioId = scenarioId
                    // The FREE talk is the ring's own tap: its surface morphs
                    // into the call pill (iOS). Every other launcher opens flat.
                    if (topic.isEmpty() && scenarioId == null && tab == HomeTab.TALK)
                        TalkMorph.open(morphScope) { inCall = true }
                    else inCall = true
                }
            },
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
            onWatch = { id -> gate { watchScenarioId = id } },
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
            onOpenDueReview = { showDueReview = true },
            onSwitchLanguage = app::switchLanguage,
            // Adding one asks for a level, which is Me's sheet — the home
            // header is not the place for a form.
            onAddLanguage = { showMe = true },
        )
    }
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
            // Google first — the PRIMARY provider on Android; Apple stays for
            // iPhone switchers (their clone follows the account).
            if (googleAvailable) {
                Button(onClick = { onGoogleSignIn(activityContext) }, enabled = !state.busy,
                    modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(if (state.busy) R.string.opening_ellipsis else R.string.continue_with_google))
                }
            }
            Button(onClick = onSignIn, enabled = !state.busy, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(if (state.busy) R.string.opening_ellipsis else R.string.continue_with_apple))
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

private data class PendingLaunch(val topic: String, val facts: List<String>, val scenarioId: String?)

/**
 * "Make it yours" — the sign-up AFTER the clone: keep a voice already in the
 * learner's ears. No skip: a session is not an account, and data on one dies
 * with the install.
 */
@Composable
internal fun AccountScreen(
    googleAvailable: Boolean,
    onGoogleSignIn: (android.content.Context) -> Unit,
    onAppleSignIn: () -> Unit,
) {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxSize().systemBarsPadding().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.make_it_yours), style = MaterialTheme.typography.headlineSmall)
        Text(
            stringResource(R.string.your_voice_is_ready_sign_in_to_keep_it),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 12.dp),
        )
        if (googleAvailable) {
            Button(onClick = { onGoogleSignIn(context) }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.continue_with_google))
            }
        }
        Button(onClick = onAppleSignIn, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.continue_with_apple))
        }
    }
}

/** The four verbs, in the order the product does them. Internal so the
 *  capture build can open the shell on a tab. */
internal enum class HomeTab(val label: Int) {
    TALK(R.string.talk), WATCH(R.string.watch),
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
    onOpenDueReview: () -> Unit = {},
    onSwitchLanguage: (String) -> Unit = {},
    onAddLanguage: () -> Unit = {},
    /** Which shelf Practice opens on — the capture harness's seam. */
    initialPracticeShelf: Shelf = Shelf.STUDYING,
) {
    val context = LocalContext.current
    var showDeepen by remember { mutableStateOf(false) }

    // The finished shelf is counted for the HEADER, where iOS keeps it: one
    // number visible from every Practice shelf. A curriculum build per talk,
    // so off the main thread, and only once Practice has been opened.
    var finished by remember { mutableStateOf<List<FinishedBook>>(emptyList()) }
    val onPractice = tab == HomeTab.PRACTICE
    val storeRevision by StoreEvents.revision.collectAsStateWithLifecycle()
    LaunchedEffect(onPractice, state.targetLanguage, state.level, storeRevision) {
        if (!onPractice) return@LaunchedEffect
        finished = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            runCatching { loadFinishedBooks(context, state.targetLanguage, state.level) }
                .getOrDefault(emptyList())
        }
    }

    // The call's first word, on disk before the tap. Synthesizing the
    // openers here costs one round trip per NEW line, once, and takes the
    // gateway's own ElevenLabs round trip out of the front of every call
    // (iOS `26a246c`). A line already cached costs nothing.
    LaunchedEffect(state.voiceId, state.targetLanguage, tab) {
        if (tab != HomeTab.TALK) return@LaunchedEffect
        val voice = state.voiceId ?: return@LaunchedEffect
        runCatching {
            com.roro.futurevoice.talk.FreeTalkOpeners(context)
                .warmAudio(state.targetLanguage, state.persona?.displayName, voice)
        }
    }

    // Auto-present exactly once, right after the first talk ends — the moment
    // the "richer persona = more real talks" pitch has lived evidence behind
    // it. Before that it is a promise, and asked in onboarding it is a form.
    LaunchedEffect(state.persona, tab) {
        val prefs = context.getSharedPreferences("futurevoice", 0)
        val prompted = prefs.getBoolean("futurevoice.personaDeepenPrompted", false)
        val talks = com.roro.futurevoice.data.SessionStore.shared(context)
            .load(state.targetLanguage).count { it.endedAt != null }
        if (!prompted && talks > 0 && personaNeedsDepth(state.persona)) {
            prefs.edit().putBoolean("futurevoice.personaDeepenPrompted", true).apply()
            showDeepen = true
        }
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
        if (granted) pendingLaunch?.let { onStartCall(it.topic, it.facts, it.scenarioId) }
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
    fun launch(topic: String, facts: List<String>, scenarioId: String? = null) {
        pendingLaunch = PendingLaunch(topic, facts, scenarioId)
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
                            DropdownMenu(expanded = languageMenu, onDismissRequest = { languageMenu = false }) {
                                state.enrolledLanguages.forEach { code ->
                                    DropdownMenuItem(
                                        text = { Text(LanguageCatalog.endonym(code)) },
                                        leadingIcon = {
                                            if (code == state.targetLanguage) {
                                                Icon(Icons.Filled.Check, contentDescription = null,
                                                    tint = MaterialTheme.colorScheme.primary)
                                            }
                                        },
                                        onClick = { languageMenu = false; onSwitchLanguage(code) })
                                }
                                HorizontalDivider()
                                DropdownMenuItem(
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
                        // Books taken all the way to mastered — a running
                        // tally, so it sits in the chrome (iOS `finishedShelfButton`).
                        if (tab == HomeTab.PRACTICE) {
                            FinishedShelfButton(count = finished.size,
                                onClick = { onOpenFinished(finished) },
                                modifier = Modifier.padding(end = 12.dp))
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
            Column(
                Modifier.padding(top = padding.calculateTopPadding()).fillMaxSize()
                    // A hidden tab stays composed but is neither measured nor
                    // placed: nothing drawn, no touches.
                    .then(if (t == tab) Modifier else Modifier.layout { _, _ -> layout(0, 0) {} })
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
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
                            onWatch = onWatch,
                            // They all live on Watch — that IS the collection.
                            onAllScenarios = { onTabChange(HomeTab.WATCH) },
                        )
                        RecentTalks(language = state.targetLanguage,
                            nativeLanguage = state.nativeLanguage, level = state.level,
                            onOpen = onOpenTalk)
                        state.error?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error)
                        }
                        if (BuildConfig.DEBUG && BuildConfig.BUILD_TYPE != "capture") {
                            TextButton(onClick = onClonePreview) { Text("Clone flow (debug)") }
                            TextButton(onClick = onWelcomePreview) { Text("Welcome (debug)") }
                        }
                    }

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
                        onOpenDueReview = onOpenDueReview,
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
                Spacer(Modifier.height(IosTabBarClearance)
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
    val screenHeightPx = with(density) {
        LocalConfiguration.current.screenHeightDp.dp.toPx()
    }
    var heroTopPx by remember { mutableStateOf(0f) }
    val heroHeight = with(density) {
        val offset = (RING_DIAMETER / 2 + RING_TAIL).toPx()
        maxOf(380.dp.toPx(), screenHeightPx / 2f + offset - heroTopPx).toDp()
    }

    Column(
        Modifier
            .fillMaxWidth()
            .height(heroHeight)
            // Measured ONCE, at rest. The page scrolls, so the hero's window
            // top moves with it — and feeding a scrolled position back into
            // the hero's own height made the page oscillate between two scroll
            // offsets on a fling (seen as a double image). The first layout is
            // always at scroll 0, and nothing above the hero changes height.
            .onGloballyPositioned { if (heroTopPx == 0f) heroTopPx = it.boundsInWindow().top }
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
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
                    style = MaterialTheme.typography.labelMedium,
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
        Text(stringResource(R.string.tap_let_s_talk_or_a_scenario_or_story_below_to_have_your_fir_d9b4f5),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** iOS's `talkRing` frame. The tail below it is what the centring solves for. */
private val RING_DIAMETER = 280.dp
private val RING_TAIL = 20.dp

/**
 * The talks already on this phone — proof the loop persists. Reloads every
 * time Home comes back into composition (i.e. after every call).
 */
@Composable
private fun RecentTalks(language: String, nativeLanguage: String, level: CefrLevel,
                        onOpen: (String) -> Unit = {}) {
    val context = LocalContext.current
    val store = remember { SessionStore.shared(context) }
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val inFlight by SessionSummarizer.inFlight.collectAsStateWithLifecycle()
    val progressBySession by SessionSummarizer.progressBySession.collectAsStateWithLifecycle()
    LaunchedEffect(language, revision) { talks = store.load(language) }
    if (talks.isEmpty()) return
    HorizontalDivider()
    Text(stringResource(R.string.talks), style = MaterialTheme.typography.titleMedium)
    val formatter = remember { DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT) }
    talks.take(10).forEach { s ->
        Column {
            BookCard(
                title = s.displayTitle ?: stringResource(R.string.conversation),
                origin = when (s.origin?.name?.lowercase()) {
                    "news" -> stringResource(R.string.news)
                    "scenario" -> stringResource(R.string.scenarios)
                    else -> stringResource(R.string.free_talk)
                },
                accent = if (s.origin?.name?.lowercase() == "news") Books.topics else Books.talks,
                detail = formatter.format(Instant.ofEpochMilli(s.rank).atZone(ZoneId.systemDefault())) +
                    " · " + stringResource(R.string.lld_turns, s.turns.count { it.role == TurnRole.USER }) +
                    (s.summary?.scorecard?.let { " · ${it.overall}" } ?: ""),
                onClick = { onOpen(s.id) },
                trailing = s.summary?.scorecard?.overall?.let { score ->
                    @Composable {
                        Text("$score", style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary)
                    }
                },
                modifier = Modifier.padding(vertical = 4.dp),
            )
            // The rescue path (iOS: ConversationDetailView): a talk saved
            // before its analysis finished isn't half a book, it's no book —
            // so it can always be run again from here.
            if (SessionSummarizer.needsSummary(s)) {
                val working = s.id in inFlight
                if (working) {
                    SummaryBoard(progressBySession[s.id] ?: SessionSummarizer.Progress())
                } else {
                    TextButton(
                        onClick = { SessionSummarizer.summarizeInBackground(context, s, nativeLanguage, level) },
                    ) { Text(stringResource(R.string.generate_review_material)) }
                }
            }
        }
    }
}

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
    onWatch: (String) -> Unit,
    onSavePersona: (com.roro.futurevoice.talk.UserPersona) -> Unit = {},
    /** The full collection — the Watch tab, which is where they all live. */
    onAllScenarios: () -> Unit = {},
) {
    var editingInterests by remember { mutableStateOf(false) }
    var newsFailed by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var newsTab by remember { mutableStateOf(true) }
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
            SegmentChip(stringResource(R.string.news), newsTab) { newsTab = true }
            SegmentChip(stringResource(R.string.scenarios), !newsTab) { newsTab = false }
            Spacer(Modifier.weight(1f))
            if (newsTab) {
                // Interests FIRST, then refresh — iOS's order, and the one that
                // reads left to right: what the stories are about, then get
                // more of them.
                IconButton(onClick = { editingInterests = true }) {
                    Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.edit_interests),
                        tint = MaterialTheme.colorScheme.primary)
                }
                if (loading) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                } else if (topics.isNotEmpty()) {
                    IconButton(onClick = {
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
            } else {
                IconButton(onClick = { composing = true }) {
                    Icon(Icons.Filled.Add,
                        contentDescription = stringResource(R.string.make_your_own_situation),
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
        } else {
            val live = scenarios.filter { it.archivedAt == null && it.isMeeting != true }
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
                        trailing = {
                            TextButton(onClick = { onWatch(sc.id) }) {
                                Text(stringResource(R.string.watch))
                            }
                        },
                    )
                    DropdownMenu(expanded = rowMenu, onDismissRequest = { rowMenu = false }) {
                        DropdownMenuItem(
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
            // until the home screen is a filing cabinet.
            if (live.size > 5) {
                DiscoverRow(
                    title = stringResource(R.string.all_scenarios),
                    caption = "${live.size}",
                    icon = Icons.Filled.Layers,
                    onClick = onAllScenarios,
                )
            }
            if (scenarios.none { it.archivedAt == null && it.isMeeting != true }) {
                DiscoverRow(
                    title = stringResource(R.string.make_your_own_situation),
                    icon = Icons.Filled.Add,
                    onClick = { composing = true },
                )
            }
        }
    }

    if (composing) {
        ScenarioComposer(
            targetLanguage = language,
            existingCategories = scenarios.mapNotNull { it.category }.distinct(),
            onDismiss = { composing = false },
        )
    }
}

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
    LaunchedEffect(revision) { days = TalkTimeLog.streakDays(context) }
    // A capsule, and tappable: the streak is a claim about a history, so it
    // opens the record rather than asking to be taken on trust.
    Row(
        Modifier
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            if (days > 0) Icons.Filled.LocalFireDepartment else Icons.Filled.CalendarMonth,
            contentDescription = null,
            // iOS: `flame.fill` in .orange — a streak is fire, not the accent.
            tint = if (days > 0) androidx.compose.ui.graphics.Color(0xFFFF9500)
            else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(14.dp))
        Text(
            if (days > 0) stringResource(R.string.lld_day_streak_94de2a, days)
            else stringResource(R.string.activity),
            style = MaterialTheme.typography.bodySmall.copy(
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
    Box(
        Modifier.padding(end = 8.dp).size(44.dp)
            .shadow(2.dp, CircleShape, clip = false)
            .clip(CircleShape).background(AppSurfaces.card)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
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
    Row(
        Modifier
            .padding(horizontal = 8.dp)
            .shadow(2.dp, CircleShape, clip = false)
            .clip(CircleShape)
            .background(AppSurfaces.card)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        icon?.let {
            Icon(it, contentDescription = null, modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.primary)
        }
        Text(label, style = MaterialTheme.typography.labelLarge,
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
}
