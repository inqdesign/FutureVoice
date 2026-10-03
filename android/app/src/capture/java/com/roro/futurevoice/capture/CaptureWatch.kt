package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.capture.flags.WatchCaptureFlags
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.ComposerHost
import com.roro.futurevoice.ui.FindPeopleScreen
import com.roro.futurevoice.ui.PersonaDeepenSheet
import com.roro.futurevoice.ui.PersonaIntakeScreen
import com.roro.futurevoice.ui.PublicIntroPreviewSheet
import androidx.compose.foundation.layout.Box
import com.roro.futurevoice.ui.PracticeBody
import com.roro.futurevoice.ui.ScenarioComposer
import com.roro.futurevoice.ui.WatchSceneScreen
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * Capture modes for the Watch area. This file owns exactly these iOS modes:
 *
 *   watch
 *   watchtab
 *   watchtab-empty
 *   composer
 *   scene-end
 *   people
 *   intake-people
 *   deepen
 *   deepen-full
 *   intro-preview
 *   profile-notes
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 *
 * Absent on purpose: `watchtab` and `watchtab-empty`. The Watch tab's body
 * (`WatchBody`) and its tab chrome (`HomeScreen`) are PRIVATE to
 * `RootScreen.kt`, so no capture can call them without a change there.
 */
object CaptureWatch {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        // iOS: "The Watch tab folded into Practice's shelves" — `PracticeTab()`
        // on its default shelf, over the seeded books.
        "watch" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("watch") { CaptureSeed.seedScenarios(c) } }) {
                TabPage {
                    PracticeBody(
                        language = lang(c), level = level(c),
                        onOpenDeck = {}, onOpenWords = {}, onOpenExpressions = {},
                        onOpenScenarioBook = {}, onOpenTalk = {},
                    )
                }
            }
        },
        // The composer with Cafe picked and the sample ideas as its chips
        // (iOS `composerPreview`), opened from Talk ("Talk" CTA on iOS).
        "composer" to @Composable { c: Context ->
            Seeded({
                CaptureSeed.once("composer") { CaptureSeed.seedNews(c) }
                WatchCaptureFlags.composerPreviewIdeas = CaptureSeed.sampleCategoryIdeas
            }) {
                ScenarioComposer(
                    targetLanguage = lang(c), existingCategories = emptyList(),
                    host = ComposerHost.TALK, onDismiss = {},
                )
            }
        },
        // A finished barista scene: every line up, the end buttons showing,
        // nothing generated or spoken (iOS `previewSceneFinished`).
        "scene-end" to @Composable { c: Context ->
            var id by remember { mutableStateOf<String?>(null) }
            Seeded({
                id = CaptureSeed.seedSceneEndScenario(c)
                WatchCaptureFlags.previewSceneFinished = true
            }) {
                WatchSceneScreen(
                    scenarioId = id!!, voiceId = "", persona = null,
                    targetLanguage = lang(c), proficiency = level(c).code, onBack = {},
                )
            }
        },
        // The ONE people page: own people on top, the pool below — the pool
        // from sample rows, since the live table is out of reach offline.
        "people" to @Composable { c: Context ->
            Seeded({ WatchCaptureFlags.samplePool = CaptureSeed.samplePublicPersonas }) {
                FindPeopleScreen(language = lang(c), onTalk = {}, onOpenPerson = {}, onBack = {})
            }
        },
        // The guided new-person intake on its first card, blank — iOS
        // `CounterpartVoiceIntakeView()` with no `-intakeStep`.
        "intake-people" to @Composable { c: Context -> Intake(c, null) },
        // Android-only: the later cards, with iOS's `-intakeStep` stand-in
        // (Boram, a fellow parent) — 1 relationship · 2–4 narrative ·
        // 5 interests · 6 style. iOS reaches these with `-intakeStep <n>`.
        "intake-people-1" to @Composable { c: Context -> Intake(c, 1) },
        "intake-people-2" to @Composable { c: Context -> Intake(c, 2) },
        "intake-people-5" to @Composable { c: Context -> Intake(c, 5) },
        "intake-people-6" to @Composable { c: Context -> Intake(c, 6) },
        // Android-only: the person form (iOS `CounterpartFormView`) over a
        // parsed intake draft, the way the intake hands off.
        "person-form" to @Composable { c: Context ->
            Box(Modifier.fillMaxSize().background(AppSurfaces.ground))
            com.roro.futurevoice.ui.PersonEditor(
                person = com.roro.futurevoice.data.Counterpart(
                    name = "Boram", relationship = "Fellow parent — same Kita",
                    howWeMet = "Our kids are in the same Kita group", location = "Munich",
                    conversationStyle = "Warm, Talkative", commonTopics = "The kids, weekend plans"),
                onSave = {}, onDismiss = {},
            )
        },
        // The post-first-talk persona sheet. Android's sheet has ONE height
        // (always fully expanded), so "deepen" and "deepen-full" are the same
        // state; and it opens over a blank ground, not the Talk home, because
        // `HomeScreen` is private to RootScreen.kt.
        "deepen" to @Composable { c: Context -> Deepen(c) },
        "deepen-full" to @Composable { c: Context -> Deepen(c) },
        // iOS `watchtab`: the Watch tab over the seeded scenarios.
        "watchtab" to { c ->
            CaptureTalk.TabShot(c, com.roro.futurevoice.ui.HomeTab.WATCH) {
                CaptureSeed.seedScenarios(c)
            }
        },
        // The mirrored Find-people intro, seen before anything is published:
        // work · town · situations · the unlocked lines only (iOS
        // `PublicIntroPreviewSheet` over the sample persona). Nothing here
        // can publish — every exit is a no-op.
        "intro-preview" to @Composable { c: Context ->
            var persona by remember { mutableStateOf<UserPersona?>(null) }
            Seeded({
                CaptureSeed.once("sample-persona") { CaptureSeed.seedSamplePersona(c) }
                persona = PersonaStore.shared(c).load()
            }) {
                Box(Modifier.fillMaxSize().background(AppSurfaces.ground))
                PublicIntroPreviewSheet(
                    persona = persona, targetLanguage = lang(c),
                    nativeLanguage = c.getSharedPreferences("futurevoice", 0)
                        .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative(),
                    onPublish = { false }, onEditFirst = {}, onDecline = {}, onDismiss = {},
                )
            }
        },
        // Me → Profile on its home step: the remembered lines with their
        // rungs and evidence — one let out whole, one as its gist, two kept
        // (iOS `PersonaOnboardingView(startStep: 1)`).
        "profile-notes" to @Composable { c: Context ->
            var persona by remember { mutableStateOf<UserPersona?>(null) }
            Seeded({
                CaptureSeed.once("sample-persona") { CaptureSeed.seedSamplePersona(c) }
                persona = PersonaStore.shared(c).load()
            }) {
                PersonaIntakeScreen(
                    initial = persona ?: UserPersona(), targetLanguage = lang(c),
                    nativeLanguage = c.getSharedPreferences("futurevoice", 0)
                        .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative(),
                    onBackToSetup = {}, onFinish = {}, startStep = 1,
                )
            }
        },
        // Android-only (plan 2.46): the WRITING door — the situation box,
        // empty, with the example reel rolling over its middle.
        "composer-box" to @Composable { c: Context ->
            Seeded({}) {
                ScenarioComposer(
                    targetLanguage = lang(c), existingCategories = emptyList(),
                    host = ComposerHost.WATCH, mode = com.roro.futurevoice.ui.ComposerMode.CUSTOM,
                    onCommitted = {}, onDismiss = {},
                )
            }
        },
        // Android-only (plan 2.46): the BROWSE door from Watch — the category
        // grid with no text field anywhere.
        "composer-browse" to @Composable { c: Context ->
            Seeded({}) {
                ScenarioComposer(
                    targetLanguage = lang(c), existingCategories = emptyList(),
                    host = ComposerHost.WATCH, mode = com.roro.futurevoice.ui.ComposerMode.BROWSE,
                    onCommitted = {}, onDismiss = {},
                )
            }
        },
        // Android-only (plan 2.46b): a saved scenario reopened from its card
        // — the composer in EDIT mode: the live field, the other person, the
        // Material list and the delete row.
        "composer-edit" to @Composable { c: Context ->
            var sc by remember { mutableStateOf<com.roro.futurevoice.talk.Scenario?>(null) }
            Seeded({
                val sid = CaptureSeed.seedSceneEndScenario(c)
                sc = com.roro.futurevoice.data.ScenarioStore.shared(c).load(lang(c))
                    .firstOrNull { it.id == sid }?.copy(brief = sampleBrief)
            }) {
                ScenarioComposer(
                    targetLanguage = lang(c), existingCategories = emptyList(),
                    host = ComposerHost.WATCH, editing = sc!!,
                    onCommitted = {}, onDelete = {}, onDismiss = {},
                )
            }
        },
        // Android-only (plan 2.46): the board while attached material is
        // read — one source done, the summary in, the questions being written.
        "brief-board" to @Composable { _: Context ->
            Box(Modifier.fillMaxSize().background(AppSurfaces.ground).statusBarsPadding()) {
                com.roro.futurevoice.ui.BriefProgressBoard(
                    sources = sampleBrief.sources,
                    progress = com.roro.futurevoice.net.ScenarioBriefEngine.Progress(
                        sourcesRead = listOf(true, false), summary = true, counterpartFacts = 5),
                )
            }
        },
        // Android-only (plan 2.46): a book whose situation carries a read
        // brief — the two halves, the sources, "Read again".
        "book-brief" to @Composable { c: Context ->
            var id by remember { mutableStateOf<String?>(null) }
            Seeded({
                val sid = CaptureSeed.seedSceneEndScenario(c)
                val store = com.roro.futurevoice.data.ScenarioStore.shared(c)
                store.load(lang(c)).firstOrNull { it.id == sid }?.let {
                    store.save(it.copy(brief = sampleBrief), lang(c))
                }
                id = sid
            }) {
                com.roro.futurevoice.ui.ScenarioBookScreen(
                    scenarioId = id!!, language = lang(c), onWatch = {}, onShadow = {}, onBack = {})
            }
        },
        // iOS `watchtab-empty`: a learner with no scenarios yet.
        "watchtab-empty" to { c ->
            CaptureTalk.TabShot(c, com.roro.futurevoice.ui.HomeTab.WATCH) {
                val store = com.roro.futurevoice.data.ScenarioStore.shared(c)
                store.load().forEach { store.delete(it.id) }
            }
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf()

    @Composable
    private fun Intake(c: Context, step: Int?) {
        WatchCaptureFlags.intakeStep = step
        com.roro.futurevoice.ui.CounterpartIntakeScreen(
            nativeLanguage = c.getSharedPreferences("futurevoice", 0)
                .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative(),
            targetLanguage = lang(c), onDraft = { _, _ -> }, onCancel = {},
        )
    }

    @Composable
    private fun Deepen(c: Context) {
        var persona by remember { mutableStateOf<UserPersona?>(null) }
        Seeded({
            CaptureSeed.once("deepen") {
                CaptureSeed.seedVocab(c); CaptureSeed.seedSessions(c)
                CaptureSeed.seedNews(c); CaptureSeed.seedScenarios(c)
            }
            persona = PersonaStore.shared(c).load()
        }) {
            PersonaDeepenSheet(
                persona = persona,
                nativeLanguage = c.getSharedPreferences("futurevoice", 0)
                    .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative(),
                targetLanguage = lang(c),
                onSave = {}, onDismiss = {},
            )
        }
    }
}

private fun lang(c: Context) = LanguageScope.active(c)

/** A brief as one reading of a posting and a CV would leave it. */
private val sampleBrief = com.roro.futurevoice.talk.ScenarioBrief(
    sources = listOf(
        com.roro.futurevoice.talk.ScenarioBrief.Source(
            id = "capture-brief-link", kind = com.roro.futurevoice.talk.ScenarioBrief.Kind.LINK,
            label = "https://jobs.example.com/barista-lead", detail = "job posting · Berlin"),
        com.roro.futurevoice.talk.ScenarioBrief.Source(
            id = "capture-brief-cv", kind = com.roro.futurevoice.talk.ScenarioBrief.Kind.FILE,
            label = "CV_2026.pdf", detail = "CV, 2 pages"),
    ),
    summary = "Café Kleist · Shift lead · Berlin Mitte",
    counterpartFacts = listOf("Specialty café, two locations", "Needs someone to open at 6:30",
        "Cares about latte art and calm under pressure"),
    likelyQuestions = listOf("What drew you to specialty coffee?",
        "How would you handle a queue out the door?", "Can you do early shifts?"),
    learnerFacts = listOf("Three years at a roastery café", "Trained two new hires last year"),
    keyExpressions = listOf("open up the shop", "keep the line moving", "dial in the grinder"),
    readAt = System.currentTimeMillis(),
)

private fun level(c: Context): CefrLevel = CefrLevel.from(
    c.getSharedPreferences("futurevoice", 0).getString("futurevoice.level.${lang(c)}", null))

/** Run the seed (and set any flag) first, then draw the real screen over it. */
@Composable
private fun Seeded(seed: suspend () -> Unit, content: @Composable () -> Unit) {
    var ready by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { seed(); StoreEvents.bump(); ready = true }
    if (ready) content()
}

/**
 * The container a tab body sits in inside `HomeScreen` (same ground, gutter,
 * spacing and scroll) — the tab's top bar and bottom bar are NOT drawn: they
 * live in `HomeScreen`, which is private to RootScreen.kt.
 */
@Composable
private fun TabPage(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(AppSurfaces.ground).statusBarsPadding()
            .verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        content()
        Spacer(Modifier.height(16.dp))
    }
}
