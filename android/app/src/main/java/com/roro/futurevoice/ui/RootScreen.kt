package com.roro.futurevoice.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
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
import com.roro.futurevoice.BuildConfig
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
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
import androidx.compose.foundation.layout.height
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
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.IconButton
import androidx.compose.foundation.background
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.ui.brand.AppSurfaces
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
    var inCall by remember { mutableStateOf(false) }
    var callTopic by remember { mutableStateOf("") }
    var callFacts by remember { mutableStateOf<List<String>>(emptyList()) }
    var callScenarioId by remember { mutableStateOf<String?>(null) }
    var callOpener by remember { mutableStateOf("") }
    var callCast by remember { mutableStateOf<com.roro.futurevoice.talk.ConversationEngine.Cast?>(null) }
    var callCastVoice by remember { mutableStateOf<String?>(null) }
    var showPrivacy by remember { mutableStateOf(false) }
    var showPublicIntro by remember { mutableStateOf(false) }
    var showInvite by remember { mutableStateOf(false) }
    var showCreditGuide by remember { mutableStateOf(false) }
    // Existing learners appear in Find people automatically. Gated on a real
    // account: an anonymous session's data dies with the install, so
    // publishing it would put a row in the pool nobody can ever talk to
    // again.
    LaunchedEffect(state.signedIn, state.isAnonymous, state.persona, state.targetLanguage) {
        if (state.signedIn && !state.isAnonymous) app.syncPublicPersona()
    }
    var showPeople by remember { mutableStateOf(false) }
    var clonePreview by remember { mutableStateOf(false) }
    var welcomeDone by remember { mutableStateOf(false) }
    var showMe by remember { mutableStateOf(false) }
    var showDeck by remember { mutableStateOf(false) }
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
            DeepLinkInbox.Destination.PRACTICE -> tab = HomeTab.PRACTICE
            null -> Unit
        }
    }
    var studyDeckKind by remember { mutableStateOf<StudyScheduleStore.Kind?>(null) }
    var detailSessionId by remember { mutableStateOf<String?>(null) }
    var watchScenarioId by remember { mutableStateOf<String?>(null) }
    var shadowLine by remember { mutableStateOf<String?>(null) }
    var bookScenarioId by remember { mutableStateOf<String?>(null) }
    val callAnswered by com.roro.futurevoice.data.DailyCallInbox.answered.collectAsStateWithLifecycle()
    LaunchedEffect(callAnswered) {
        // Answering the daily call IS starting the talk — no second tap, and
        // no overlay (Me, a deck, a book) may stand in front of it.
        if (callAnswered > 0 && state.voiceId != null) {
            showMe = false; showDeck = false; detailSessionId = null
            watchScenarioId = null; shadowLine = null; clonePreview = false
            callTopic = ""; callFacts = emptyList(); callScenarioId = null
            // The pre-written voicemail IS the call's first line; consumed
            // so a plain free talk later doesn't replay it.
            callOpener = com.roro.futurevoice.data.DailyCallStore.script(context).orEmpty()
            com.roro.futurevoice.data.DailyCallStore.setScript(context, null)
            inCall = true
        }
    }
    var editProfile by remember { mutableStateOf(false) }
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

    when {
        welcomePreview -> WelcomeScreen(onGetStarted = { welcomePreview = false })

        // DEBUG-only preview of the clone flow (iOS: `-onboardingPreview`):
        // the dev account already has a voice, so the real gate never shows.
        clonePreview -> CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            onCloned = { clonePreview = false },
        )

        state.resolvingSession -> Loading()
        // The pitch before the ask — the five beats a first-time user must
        // agree with before an account means anything. Returning users
        // (stored session) never see it.
        !state.signedIn && !welcomeDone -> WelcomeScreen(onGetStarted = {
            welcomeDone = true
            // Account-free entry (iOS order): the server needs a session, not
            // an account — the sign-up asks to KEEP the voice, after Meet.
            app.startAnonymous()
        })
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
            onFinish = app::completeSetup,
        )
        editProfile -> PersonaIntakeScreen(
            initial = state.persona ?: com.roro.futurevoice.talk.UserPersona(),
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onBackToSetup = { editProfile = false },
            onFinish = { app.savePersona(it); editProfile = false },
        )

        shadowLine != null -> ShadowScreen(
            line = shadowLine!!,
            voiceId = state.voiceId ?: "",
            targetLanguage = state.targetLanguage,
            onBack = { shadowLine = null },
        )

        watchScenarioId != null -> WatchSceneScreen(
            scenarioId = watchScenarioId!!,
            voiceId = state.voiceId ?: "",
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            proficiency = state.level.code,
            onBack = { watchScenarioId = null },
        )

        detailSessionId != null -> TalkDetailScreen(
            sessionId = detailSessionId!!,
            language = state.targetLanguage,
            onBack = { detailSessionId = null },
            onShadow = { shadowLine = it },
        )

        bookScenarioId != null -> ScenarioBookScreen(
            scenarioId = bookScenarioId!!,
            language = state.targetLanguage,
            onWatch = { watchScenarioId = it },
            onShadow = { shadowLine = it },
            onBack = { bookScenarioId = null },
        )

        // Above everything: an account that cannot spend must not be looking
        // at a call screen behind a sheet.
        paywalled -> PaywallScreen(onDismiss = { BillingGate.showPaywall.value = false })

        library != null -> LibraryScreen(
            kind = library!!,
            language = state.targetLanguage,
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

        showDeck -> DrillDeckScreen(
            language = state.targetLanguage,
            persona = state.persona,
            nativeLanguage = state.nativeLanguage,
            onBack = { showDeck = false },
        )

        studyDeckKind != null -> StudyDeckHost(
            kind = studyDeckKind!!,
            language = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            level = state.level,
            onBack = { studyDeckKind = null },
        )

        showPeople -> FindPeopleScreen(
            language = state.targetLanguage,
            onTalk = { p ->
                callCast = com.roro.futurevoice.talk.ConversationEngine.Cast(
                    name = p.display_name, intro = p.intro, location = p.location,
                    occupation = p.occupation, interests = p.interests,
                    conversationStyle = p.conversation_style)
                callCastVoice = p.voice_preset_id.takeIf { it.isNotBlank() }
                gate {
                    callTopic = ""; callFacts = emptyList(); callScenarioId = null
                    showPeople = false; inCall = true
                }
            },
            onBack = { showPeople = false },
        )

        // Above Me, so backing out of these lands on Me rather than the tabs.
        showCreditGuide -> CreditGuideScreen(onBack = { showCreditGuide = false })

        showInvite -> InviteScreen(onBack = { showInvite = false })

        showPublicIntro -> PublicIntroScreen(
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            onBack = { showPublicIntro = false },
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
            hasVoice = state.voiceId != null,
            onOpenPeople = { showMe = false; showPeople = true },
            onOpenPublicIntro = { showPublicIntro = true },
            onOpenInvite = { showInvite = true },
            onOpenCreditGuide = { showCreditGuide = true },
            voiceId = state.voiceId,
            voiceAccentId = state.voiceAccentId,
            onAccentApplied = app::adoptRemixedVoice,
            onEditProfile = { editProfile = true },
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
                onExit = { inCall = false; callTopic = ""; callFacts = emptyList()
                    callScenarioId = null; callOpener = ""; callCast = null; callCastVoice = null },
            )

        else -> HomeScreen(
            state = state,
            onStartCall = { topic, facts, scenarioId ->
                // The paywall is asked here, at the TAP — every metered
                // launcher (free talk, a news story, a scenario, a widget
                // deep link) meets in this one callback, so one gate covers
                // them all. Met only as a 402, it would arrive after the call
                // screen was already up.
                gate { callTopic = topic; callFacts = facts
                    callScenarioId = scenarioId; inCall = true }
            },
            onOpenMe = { showMe = true },
            onOpenBook = { bookScenarioId = it },
            onOpenPeople = { showPeople = true },
            onOpenActivity = { showActivity = true },
            onOpenAssessment = { showAssessment = true },
            tab = tab,
            onTabChange = { tab = it },
            onOpenDeck = { showDeck = true },
            onOpenWords = { studyDeckKind = StudyScheduleStore.Kind.WORD },
            onOpenExpressions = { studyDeckKind = StudyScheduleStore.Kind.EXPRESSION },
            onOpenTalk = { detailSessionId = it },
            onWatch = { id -> gate { watchScenarioId = id } },
            onClonePreview = { clonePreview = true },
            onWelcomePreview = { welcomePreview = true },
            onSavePersona = app::savePersona,
        )
    }
}

@Composable
private fun Loading() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun SignInScreen(
    state: AppState,
    googleAvailable: Boolean = false,
    onGoogleSignIn: (android.content.Context) -> Unit = {},
    onSignIn: () -> Unit,
    onDevSignIn: (String, String) -> Unit,
) {
    val activityContext = LocalContext.current
    var devEmail by remember { mutableStateOf("") }
    var devPassword by remember { mutableStateOf("") }
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Future Voice", style = MaterialTheme.typography.headlineMedium)
            Text(
                "Sign in with the same Apple ID you use on iPhone — your cloned " +
                    "voice comes with you.",
                style = MaterialTheme.typography.bodyMedium,
            )
            // Google first — the PRIMARY provider on Android; Apple stays for
            // iPhone switchers (their clone follows the account).
            if (googleAvailable) {
                Button(onClick = { onGoogleSignIn(activityContext) }, enabled = !state.busy,
                    modifier = Modifier.fillMaxWidth()) {
                    Text(if (state.busy) "Opening…" else "Continue with Google")
                }
            }
            Button(onClick = onSignIn, enabled = !state.busy) {
                Text(if (state.busy) "Opening…" else "Continue with Apple")
            }
            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
            // Emulator escape hatch while Apple web-OAuth setup is pending.
            // Debug builds only — this whole block is compiled out of release,
            // and production accounts are Apple-only so email reaches nothing real.
            if (BuildConfig.DEBUG) {
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
private fun AccountScreen(
    googleAvailable: Boolean,
    onGoogleSignIn: (android.content.Context) -> Unit,
    onAppleSignIn: () -> Unit,
) {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxSize().padding(24.dp),
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

/** The four verbs, in the order the product does them. */
private enum class HomeTab(val label: Int) {
    TALK(R.string.talk), WATCH(R.string.watch),
    PRACTICE(R.string.practice), PROGRESS(R.string.progress)
}

/**
 * The app shell — `RootTabView`: Talk · Watch · Practice · Progress,
 * do → create → review → measure. Me opens from the Talk header, as on iOS.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScreen(
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
    onOpenActivity: () -> Unit = {},
    onOpenAssessment: () -> Unit = {},
    /** Hoisted by the root — see the comment on its declaration there. */
    tab: HomeTab,
    onTabChange: (HomeTab) -> Unit,
    onOpenBook: (String) -> Unit = {},
    onClonePreview: () -> Unit = {},
    onWelcomePreview: () -> Unit = {},
    onSavePersona: (com.roro.futurevoice.talk.UserPersona) -> Unit = {},
) {
    val context = LocalContext.current
    var showDeepen by remember { mutableStateOf(false) }

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
    val permission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) pendingLaunch?.let { onStartCall(it.topic, it.facts, it.scenarioId) }
        pendingLaunch = null
    }
    fun launch(topic: String, facts: List<String>, scenarioId: String? = null) {
        pendingLaunch = PendingLaunch(topic, facts, scenarioId)
        permission.launch(Manifest.permission.RECORD_AUDIO)
    }

    Scaffold(
        topBar = {
            // CENTER-aligned: the streak is the one Today stat that lives up
            // here and it holds the MIDDLE (iOS puts it in `.principal`). A
            // plain TopAppBar left-aligns its title, which clustered the
            // streak against the language chip and left the bar lopsided.
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                // No title on Talk: the hero's time-of-day question IS the
                // greeting, and a title above it doubled it (iOS). The bar
                // carries just the controls — language · streak · account.
                title = {
                    if (tab == HomeTab.TALK) StreakChip(
                        language = state.targetLanguage, onClick = onOpenActivity)
                    else Text(stringResource(tab.label))
                },
                navigationIcon = {
                    if (tab == HomeTab.TALK) {
                        HeaderButton(LanguageCatalog.endonym(state.targetLanguage),
                            onClick = onOpenMe)
                    }
                },
                actions = {
                    // The people page opens from the WATCH header, as on iOS.
                    if (tab == HomeTab.WATCH) {
                        IconButton(onClick = onOpenPeople) {
                            Icon(Symbols.icon("person.2"),
                                contentDescription = stringResource(R.string.people))
                        }
                    }
                    if (tab == HomeTab.TALK) {
                        HeaderButton(stringResource(R.string.me), onClick = onOpenMe)
                    }
                },
            )
        },
        bottomBar = {
            NavigationBar {
                HomeTab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t,
                        onClick = { onTabChange(t) },
                        icon = {
                            Icon(
                                when (t) {
                                    HomeTab.TALK -> Icons.Filled.Phone
                                    HomeTab.WATCH -> Icons.Filled.PlayArrow
                                    HomeTab.PRACTICE -> Icons.Filled.School
                                    HomeTab.PROGRESS -> Icons.Filled.BarChart
                                },
                                contentDescription = null,
                            )
                        },
                        label = { Text(stringResource(t.label)) },
                    )
                }
            }
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            when (tab) {
                HomeTab.TALK -> {
                    TalkHero(
                        state = state,
                        enabled = state.voiceId != null,
                        onTap = { launch("", emptyList()) },
                        onOpenActivity = onOpenActivity,
                    )
                    if (personaNeedsDepth(state.persona)) {
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
                    )
                    RecentTalks(language = state.targetLanguage,
                        nativeLanguage = state.nativeLanguage, level = state.level,
                        onOpen = onOpenTalk)
                    state.error?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error)
                    }
                    if (BuildConfig.DEBUG) {
                        TextButton(onClick = onClonePreview) { Text("Clone flow (debug)") }
                        TextButton(onClick = onWelcomePreview) { Text("Welcome (debug)") }
                    }
                }

                // Watch: simulate the situation BEFORE it happens. Scenarios
                // are reusable templates — a tap writes a fresh take.
                HomeTab.WATCH -> WatchBody(
                    language = state.targetLanguage,
                    enabled = state.voiceId != null,
                    onWatch = onWatch,
                    onTalk = { sc -> launch(sc.promptBlurb, emptyList(), sc.id) },
                )

                HomeTab.PRACTICE -> PracticeBody(
                    level = state.level,
                    language = state.targetLanguage,
                    onOpenDeck = onOpenDeck,
                    onOpenWords = onOpenWords,
                    onOpenExpressions = onOpenExpressions,
                    onOpenScenarioBook = onOpenBook,
                    onOpenTalk = onOpenTalk,
                )

                HomeTab.PROGRESS -> ProgressBody(
                    language = state.targetLanguage,
                    nativeLanguage = state.nativeLanguage,
                    onOpenAssessment = onOpenAssessment,
                    onOpenActivity = onOpenActivity,
                    goalMinutes = LocalContext.current
                        .getSharedPreferences("futurevoice", 0)
                        .getInt("futurevoice.dailyGoalMinutes", 10),
                )
            }
            Spacer(Modifier.height(16.dp))
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
    LaunchedEffect(revision) {
        seconds = TalkTimeLog.secondsToday(context)
        sessionCount = SessionStore.shared(context).load(state.targetLanguage).size
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
            .onGloballyPositioned { heroTopPx = it.boundsInWindow().top }
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
            // The display face — the brand's voice, not the reading font.
            style = DisplayFace.style(line, MaterialTheme.typography.headlineSmall),
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
                val label = stringResource(R.string.lets_talk)
                Text(label, style = DisplayFace.style(label,
                    MaterialTheme.typography.titleMedium))
                Text(
                    stringResource(R.string.lld_of_lld_min_today, seconds / 60, goalMinutes),
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

/** The day's metered talk against the learner's own goal. */
@Composable
private fun TodayRow() {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val goalMinutes = remember {
        context.getSharedPreferences("futurevoice", 0).getInt("futurevoice.dailyGoalMinutes", 10)
    }
    var seconds by remember { mutableStateOf(0) }
    LaunchedEffect(revision) { seconds = TalkTimeLog.secondsToday(context) }
    Column {
        Text(stringResource(R.string.today), style = MaterialTheme.typography.titleMedium)
        Text(
            stringResource(R.string.lld_of_lld_min_today, seconds / 60, goalMinutes),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        LinearProgressIndicator(
            progress = { (seconds / 60f / goalMinutes).coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
        )
    }
}

/**
 * Discover — what to talk about today, in two chips (`DiscoverSection`):
 * the day's stories from the platform pool, or a situation the learner
 * built. One full-width card list on the 20pt grid; a horizontal rail read
 * as posters and this reads as a list.
 */
@Composable
private fun DiscoverSection(
    state: AppState,
    enabled: Boolean,
    onPickNews: (SuggestedTopic) -> Unit,
    onPickScenario: (Scenario) -> Unit,
    onWatch: (String) -> Unit,
    onSavePersona: (com.roro.futurevoice.talk.UserPersona) -> Unit = {},
) {
    var editingInterests by remember { mutableStateOf(false) }
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
        } finally { loading = false }
    }

    LaunchedEffect(interests, language) {
        // Stories come from the shared platform pool (a cheap read), so
        // auto-load on open; the local cache skips even the network hop
        // within the same day.
        if (interests.isNotEmpty()) {
            val cached = store.valid(interests, language)
            if (cached != null) topics = displaySelection(cached) else fetchNews(false)
        }
    }
    LaunchedEffect(language, revision) { scenarios = scenarioStore.load(language) }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SegmentChip(stringResource(R.string.news), newsTab) { newsTab = true }
            SegmentChip(stringResource(R.string.scenarios), !newsTab) { newsTab = false }
            Spacer(Modifier.weight(1f))
            if (newsTab) {
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
                    }) { Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.refresh)) }
                }
                IconButton(onClick = { editingInterests = true }) {
                    Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.interests))
                }
            } else {
                IconButton(onClick = { composing = true }) {
                    Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.make_your_own_situation))
                }
            }
        }

        if (newsTab) {
            topics.forEach { topic ->
                DiscoverRow(
                    title = topic.title,
                    caption = topic.category,
                    icon = categoryIcon(topic.category),
                    accent = Books.topics,
                    onClick = if (enabled) ({ onPickNews(topic) }) else null,
                )
            }
        } else {
            scenarios.filter { it.archivedAt == null && it.isMeeting != true }.forEach { sc ->
                DiscoverRow(
                    title = sc.cardTitle,
                    caption = sc.category,
                    // The icon the categorizer picked for this scenario —
                    // a fixed pin made every scenario look like a place.
                    icon = Symbols.icon(sc.categoryIcon),
                    accent = Books.scenarios,
                    onClick = if (enabled) ({
                        scope.launch { scenarioStore.touch(sc.id, language); StoreEvents.bump() }
                        onPickScenario(sc)
                    }) else null,
                    trailing = {
                        TextButton(onClick = { onWatch(sc.id) }) {
                            Text(stringResource(R.string.watch))
                        }
                    },
                )
            }
            if (scenarios.none { it.archivedAt == null && it.isMeeting != true }) {
                DiscoverRow(
                    title = stringResource(R.string.make_your_own_situation),
                    icon = Icons.Filled.Add,
                    accent = Books.scenarios,
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

/** Days in a row with metered talk — the one Today stat that lives up here. */
@Composable
private fun StreakChip(language: String, onClick: () -> Unit) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var days by remember { mutableStateOf(0) }
    LaunchedEffect(revision) { days = TalkTimeLog.streakDays(context) }
    if (days <= 0) return
    // A capsule, and tappable: the streak is a claim about a history, so it
    // opens the record rather than asking to be taken on trust.
    Row(
        Modifier
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(Icons.Filled.LocalFireDepartment, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
        Text("$days", style = MaterialTheme.typography.labelLarge)
    }
}

/**
 * A header control that looks like one.
 *
 * These were bare `TextButton`s, which in a header read as labels — and a
 * label that does something is a thing the learner has to discover by
 * poking. Same quiet capsule the streak wears, so the three read as one row
 * of controls rather than three unrelated bits of text.
 */
@Composable
private fun HeaderButton(label: String, onClick: () -> Unit) {
    Text(
        label,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier
            .padding(horizontal = 8.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

/**
 * Watch — simulate a specific situation BEFORE it happens. "Make your own
 * situation" is the DEFAULT entry (describe the real upcoming thing; no
 * person needed), with the learner's saved scenarios under it. A saved
 * scenario is a reusable TEMPLATE: watching writes a FRESH take every time.
 */
@Composable
private fun WatchBody(
    language: String,
    enabled: Boolean,
    onWatch: (String) -> Unit,
    onTalk: (Scenario) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val store = remember { ScenarioStore.shared(context) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    var composing by remember { mutableStateOf(false) }
    var prefill by remember { mutableStateOf("") }
    /** Which category is drilled open, if any. */
    var branch by remember { mutableStateOf<SituationTree.Branch?>(null) }
    /** The person a composed scene is scoped to, if any. */
    var withPerson by remember { mutableStateOf<Counterpart?>(null) }
    var people by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    var managingPeople by remember { mutableStateOf(false) }
    LaunchedEffect(language, revision) {
        scenarios = store.load(language)
        // Own people only. A stranger met in Find people has `remoteId` set
        // and lives in that sheet's "People you've met" — putting them here
        // would crowd out the people the learner actually knows.
        people = CounterpartStore.shared(context).load().filter { it.remoteId == null }
    }
    val live = scenarios.filter { it.archivedAt == null && it.isMeeting != true }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // The people you actually talk to. Tapping one scopes the composer to
        // them, so the scene is grounded in a real relationship rather than a
        // generic "the other person".
        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(people, key = { it.id }) { person ->
                PersonBubble(
                    name = person.name,
                    onClick = { withPerson = person; composing = true },
                )
            }
            // Always last: the way in when the row is empty, and the way to
            // edit when it isn't.
            item {
                PersonBubble(
                    name = stringResource(R.string.people),
                    isAction = true,
                    onClick = { managingPeople = true },
                )
            }
        }

        DiscoverRow(
            title = stringResource(R.string.make_your_own_situation),
            icon = Icons.Filled.Add,
            accent = Books.scenarios,
            onClick = { composing = true },
        )
        if (live.isNotEmpty()) {
            Text(stringResource(R.string.your_scenarios),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp))
            live.forEach { sc ->
                DiscoverRow(
                    title = sc.cardTitle,
                    caption = sc.category,
                    // The icon the categorizer picked for this scenario —
                    // a fixed pin made every scenario look like a place.
                    icon = Symbols.icon(sc.categoryIcon),
                    accent = Books.scenarios,
                    onClick = if (enabled) ({ onWatch(sc.id) }) else null,
                    trailing = {
                        TextButton(onClick = {
                            scope.launch { store.touch(sc.id, language); StoreEvents.bump() }
                            onTalk(sc)
                        }) { Text(stringResource(R.string.talk)) }
                    },
                )
            }
        }

        // Deliberately LIGHTER than the scenario rows above: these are
        // starting points that open the composer, not saved content that
        // plays. Chips keep the two tap behaviours visually distinct.
        Text(stringResource(R.string.likely_situations),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 12.dp))
        // Deliberately LIGHTER than the scenario rows above — these open the
        // composer, they are not saved content that plays. A filled tile with
        // its own icon, not an outlined filter chip: a chip reads as "narrow
        // the list", and nothing here is a filter.
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SituationTree.roots.forEach { root ->
                Row(
                    Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                        .clickable { branch = root }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Symbols.icon(root.icon), contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(18.dp))
                    Text(root.label, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        Text(stringResource(R.string.tap_a_category_the_composer_suggests_specific_scenarios),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }

    branch?.let { root ->
        SituationDrillDown(
            root = root,
            onPick = { situation ->
                branch = null
                prefill = situation
                composing = true
            },
            onDismiss = { branch = null },
        )
    }

    if (managingPeople) {
        PeopleSheet(onDismiss = { managingPeople = false })
    }

    if (composing) {
        ScenarioComposer(
            targetLanguage = language,
            existingCategories = scenarios.mapNotNull { it.category }.distinct(),
            prefill = prefill,
            person = withPerson,
            onDismiss = { composing = false; prefill = ""; withPerson = null },
        )
    }
}

/**
 * One face in the stories row. There is no photo of these people and there
 * should not be — the app never asks for one — so the bubble is an initial on
 * the book accent, which is enough to pick a name out of five.
 */
@Composable
private fun PersonBubble(name: String, isAction: Boolean = false, onClick: () -> Unit) {
    Column(
        Modifier.width(72.dp).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            Modifier.size(56.dp).background(
                if (isAction) MaterialTheme.colorScheme.surfaceVariant
                else Books.scenarios.copy(alpha = 0.18f),
                CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (isAction) {
                Icon(Icons.Filled.Add, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Text(name.take(1).uppercase(),
                    style = MaterialTheme.typography.titleMedium,
                    color = Books.scenarios)
            }
        }
        Text(name, style = MaterialTheme.typography.labelSmall,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * The chain, one level at a time: a category's sub-areas, then the specific
 * things that go wrong in them. The leaf's text lands in the composer, where
 * it is always editable — a prefill is a head start, never a script.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SituationDrillDown(
    root: SituationTree.Branch,
    onPick: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var open by remember { mutableStateOf<SituationTree.Branch?>(null) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(open?.label ?: root.label, style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 8.dp))
            (open?.children ?: root.children).forEach { child ->
                Row(
                    Modifier.fillMaxWidth()
                        .clickable {
                            val situation = child.situation
                            if (situation != null) onPick(situation) else open = child
                        }
                        .padding(vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(child.label, style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f))
                    if (child.situation == null) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/**
 * "Make your own situation" — describe the real upcoming thing in your own
 * words. Categorizing is a nicety and never blocks a commit (iOS rule): a
 * failure just leaves the free text as the scenario.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScenarioComposer(
    targetLanguage: String,
    existingCategories: List<String>,
    /** A "Likely situations" leaf, dropped in ready to edit — never locked. */
    prefill: String = "",
    /** Who the scene is with, when the composer was opened from a face. */
    person: Counterpart? = null,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var draft by remember { mutableStateOf(prefill) }
    var committing by remember { mutableStateOf(false) }
    // A SHEET, not a dialog: non-primary content lives in sheets (iOS UI
    // rules), and a dialog over a full-width composer reads as an alert.
    ModalBottomSheet(onDismissRequest = { if (!committing) onDismiss() }) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                if (person != null) stringResource(R.string.a_scene_with_lls, person.name)
                else stringResource(R.string.make_your_own_situation),
                style = MaterialTheme.typography.titleLarge)
            Text(stringResource(R.string.the_real_thing_coming_up_an_interview_a_call_a_visit_describ_a97c73),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(value = draft, onValueChange = { draft = it },
                minLines = 3, modifier = Modifier.fillMaxWidth())
            Button(
                enabled = draft.isNotBlank() && !committing,
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    committing = true
                    val text = draft.trim()
                    scope.launch {
                        // Categorizing is a nicety and never blocks a commit
                        // (iOS rule): a failure leaves the free text as the
                        // scenario, with no breadcrumb.
                        val result = runCatching {
                            TopicClient(AuthRepository()).categorize(
                                text = text, existing = existingCategories,
                                iconOptions = TopicClient.ICON_PALETTE,
                                targetLanguage = targetLanguage)
                        }.getOrNull()
                        ScenarioStore.shared(context).save(Scenario(
                            environment = text,
                            category = result?.category?.takeIf { it.isNotBlank() },
                            categoryIcon = result?.icon,
                            summary = result?.summary?.takeIf { it.isNotBlank() },
                            // Scoping to a person is what makes the scene
                            // theirs: the role names them, and the id links
                            // the scenario back so the book can say who it
                            // was with. An EMPTY role is what lets a scene
                            // infer its own counterpart, so it must stay
                            // empty when nobody was picked.
                            role = person?.let { "${'$'}{it.name} — ${'$'}{it.relationship}" }.orEmpty(),
                            counterpartId = person?.id,
                        ), targetLanguage)
                        StoreEvents.bump()
                        committing = false; onDismiss()
                    }
                },
            ) { Text(stringResource(if (committing) R.string.working else R.string.create)) }
        }
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
            .background(AppSurfaces.card, RoundedCornerShape(20.dp))
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
