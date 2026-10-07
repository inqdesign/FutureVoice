package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.capture.flags.PracticeCaptureFlags
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.DrillDeckScreen
import com.roro.futurevoice.ui.FinishedBooksScreen
import com.roro.futurevoice.ui.LibraryKind
import com.roro.futurevoice.ui.LibraryScreen
import com.roro.futurevoice.ui.PracticeBody
import com.roro.futurevoice.ui.ScenarioBookScreen
import com.roro.futurevoice.ui.ScoreBlock
import com.roro.futurevoice.ui.ShadowScreen
import com.roro.futurevoice.ui.Shelf
import com.roro.futurevoice.ui.StudyDeckHost
import com.roro.futurevoice.ui.TalkDetailScreen
import com.roro.futurevoice.ui.TalkTranscriptScreen
import com.roro.futurevoice.ui.VocabularyCloudScreen
import com.roro.futurevoice.ui.WordCardSheet
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.runBlocking

/**
 * Capture modes for the Practice area. This file owns exactly these iOS modes:
 *
 *   practice-talk
 *   practice-watch
 *   practice-due
 *   practice-review-route
 *   practice-studying
 *   review-due
 *   review-item-word
 *   review-item-sentence
 *   drills
 *   drills-tray
 *   drills-folder
 *   daily-words
 *   daily-words-tray
 *   daily-words-full
 *   daily-expressions
 *   vocab
 *   vocab-card
 *   vocab-failed
 *   vocab-loading
 *   wordcard-ja
 *   expr
 *   expr-card
 *   transcript
 *   book
 *   book-words
 *   book-lines
 *   talkdetail
 *   talkdetail-mid
 *   talkdetail-low
 *   talkdetail-words
 *   talkdetail-expressions
 *   talkdetail-lines
 *   talkdetail-cards
 *   talkdetail-ja
 *   say-again
 *   say-again-reading
 *   say-again-done
 *   say-again-scene
 *   say-again-scene-reading
 *   say-again-scene-done
 *   finished
 *   finished-empty
 *   shadow
 *   shadow-ja
 *   score
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 */
object CapturePractice {

    private const val MIN = 60_000L
    private const val DAY = 86_400_000L

    private fun lang(c: Context) = LanguageScope.active(c)
    private fun native(c: Context) =
        c.getSharedPreferences("futurevoice", 0).getString("futurevoice.nativeLanguage", null) ?: "en"
    private fun level(c: Context) =
        CefrLevel.from(c.getSharedPreferences("futurevoice", 0).getString("futurevoice.proficiency", "b1"))

    /**
     * One mode: flags first, then the seeds (synchronously, before the real
     * screen's first read — iOS seeds inside `view(for:)` for the same
     * reason), then the screen. Lookups are offline in every mode: the
     * capture app has no session, and iOS's lookups come back nil for the
     * same reason.
     */
    private fun mode(
        seed: suspend (Context) -> Unit = {},
        screen: @Composable (Context) -> Unit,
    ): @Composable (Context) -> Unit = { ctx ->
        remember {
            PracticeCaptureFlags.offlineLookups = true
            runBlocking { seed(ctx) }
            true
        }
        screen(ctx)
    }

    // ── Seeds (the iOS route bodies) ──

    private suspend fun seedSessionsAndBooks(c: Context, name: String) = CaptureSeed.once(name) {
        CaptureSeed.seedSessions(c, scored = true); CaptureSeed.seedScenarios(c)
    }

    private suspend fun snoozePast(c: Context, agoMs: Long,
                                   words: List<String>, expressions: List<String>) {
        val store = StudyScheduleStore.shared(c)
        val at = System.currentTimeMillis() - agoMs
        words.forEach { store.snooze(StudyScheduleStore.Kind.WORD, it, lang(c), at) }
        expressions.forEach { store.snooze(StudyScheduleStore.Kind.EXPRESSION, it, lang(c), at) }
    }

    private suspend fun seedPracticeDue(c: Context, expressions: List<String>) =
        CaptureSeed.once("practice-due") {
            CaptureSeed.seedVocab(c); CaptureSeed.seedSessions(c)
            CaptureSeed.seedNews(c); CaptureSeed.seedScenarios(c)
            snoozePast(c, 15 * MIN, listOf("reschedule", "overwhelmed"), expressions)
        }

    private suspend fun seedVocab(c: Context, fresh: Boolean = false) =
        CaptureSeed.once("vocab") { CaptureSeed.seedVocab(c, freshSchedule = fresh) }

    private suspend fun seedDrills(c: Context) =
        CaptureSeed.once("drills") { CaptureSeed.seedVocab(c); CaptureSeed.seedDrillFolders(c) }

    // ── Screens ──

    /** The Practice tab's body. The tab shell (title, tab bar) is RootScreen's. */
    @Composable
    internal fun Practice(c: Context, shelf: Shelf) {
        // The real tab shell, so the header — the large title and the week's
        // icons at its right (put off, the week, the tests) — is in the shot,
        // as on iOS.
        val state = remember {
            val l = lang(c)
            com.roro.futurevoice.ui.AppState(
                resolvingSession = false, signedIn = true, setupComplete = true,
                persona = runBlocking { com.roro.futurevoice.data.PersonaStore.shared(c).load() },
                personaResolved = true, voiceId = "capture-voice",
                targetLanguage = l, enrolledLanguages = listOf(l),
                nativeLanguage = native(c), level = level(c))
        }
        var tab by androidx.compose.runtime.remember {
            androidx.compose.runtime.mutableStateOf(com.roro.futurevoice.ui.HomeTab.PRACTICE)
        }
        var finished by androidx.compose.runtime.remember {
            androidx.compose.runtime.mutableStateOf<List<com.roro.futurevoice.ui.FinishedBook>?>(null)
        }
        finished?.let { books ->
            FinishedBooksScreen(books = books, onOpen = {}, onBack = { finished = null })
            return
        }
        // A shelf card opens its book through the shared push host (tap one
        // on the emulator to see the transition, or swipe from the edge).
        var page by androidx.compose.runtime.remember {
            androidx.compose.runtime.mutableStateOf<com.roro.futurevoice.ui.RootRoute>(
                com.roro.futurevoice.ui.RootRoute.Tabs)
        }
        val stack = if (page == com.roro.futurevoice.ui.RootRoute.Tabs) listOf(page)
            else listOf(com.roro.futurevoice.ui.RootRoute.Tabs, page)
        com.roro.futurevoice.ui.IosNavStack(stack = stack,
            onPop = { page = com.roro.futurevoice.ui.RootRoute.Tabs }, pageKey = { it.key }) { p ->
            when (p) {
                is com.roro.futurevoice.ui.RootRoute.TalkBook -> com.roro.futurevoice.ui.TalkDetailScreen(
                    sessionId = p.id, language = lang(c), level = level(c),
                    onBack = { page = com.roro.futurevoice.ui.RootRoute.Tabs })
                is com.roro.futurevoice.ui.RootRoute.ScenarioBook -> com.roro.futurevoice.ui.ScenarioBookScreen(
                    scenarioId = p.id, language = lang(c), onWatch = {}, onShadow = {},
                    onBack = { page = com.roro.futurevoice.ui.RootRoute.Tabs })
                else ->
                    com.roro.futurevoice.ui.HomeScreen(state = state, onStartCall = { _, _, _ -> }, onOpenMe = {},
                        tab = tab, onTabChange = { tab = it }, initialPracticeShelf = shelf,
                        onOpenFinished = { finished = it },
                        onOpenTalk = { page = com.roro.futurevoice.ui.RootRoute.TalkBook(it) },
                        onOpenBook = { page = com.roro.futurevoice.ui.RootRoute.ScenarioBook(it) })
            }
        }
    }

    @Composable
    private fun DueDeck(c: Context) =
        StudyDeckHost(kind = null, language = lang(c), nativeLanguage = native(c),
            level = level(c), onBack = {})

    @Composable
    private fun DailyDeck(c: Context, kind: StudyScheduleStore.Kind) =
        StudyDeckHost(kind = kind, language = lang(c), nativeLanguage = native(c),
            level = level(c), onBack = {})

    // iOS's drills modes render `DrillSheet`: "Sentences" with Done.
    @Composable
    private fun Drills(c: Context) =
        DrillDeckScreen(language = lang(c), nativeLanguage = native(c), onBack = {},
            title = androidx.compose.ui.res.stringResource(com.roro.futurevoice.R.string.sentences))

    @Composable
    private fun Cloud(c: Context, language: String? = null) =
        VocabularyCloudScreen(language = language ?: lang(c), onBack = {})

    private fun talkDetail(chapter: String?, variant: String = "") = mode(
        seed = { c ->
            seedVocab(c)
            var s = CaptureSeed.talkDetailSession
            // iOS: the "-mid"/"-low" variants blank the UPPER sections so a
            // screenshot reaches the lower ones.
            if (variant.isNotEmpty()) {
                s = s.copy(summary = s.summary?.copy(scorecard = null, overallNote = ""))
            }
            if (variant == "low") {
                s = s.copy(turns = s.turns.filter { it.role == TurnRole.USER },
                    summary = s.summary?.copy(newWordsUsed = emptyList()))
            }
            PracticeCaptureFlags.talkDetailSession = s
            PracticeCaptureFlags.talkDetailChapter = chapter
        },
    ) { c ->
        // iOS: the cover modes are the WRAP-UP of a call just ended (Done,
        // "Review book", no Continue); the chapter modes are the book opened
        // from the shelf (the talk's title, ⋯, Continue beside Replay).
        TalkDetailScreen(sessionId = CaptureSeed.talkDetailSession.id, language = lang(c),
            level = level(c), onBack = {},
            onDone = if (chapter == null) ({}) else null,
            onContinue = if (chapter == null) null else ({ _: String -> }))
    }

    private fun sayAgain(stage: String) = mode(
        seed = {
            PracticeCaptureFlags.talkDetailSession = CaptureSeed.talkDetailSession
            PracticeCaptureFlags.sayItAgainStage = stage
        },
    ) { c ->
        TalkDetailScreen(sessionId = CaptureSeed.talkDetailSession.id, language = lang(c),
            level = level(c), onBack = {})
    }

    private fun sayAgainScene(stage: String) = mode(
        seed = {
            PracticeCaptureFlags.bookScenario = CaptureSeed.bookScenario
            PracticeCaptureFlags.sayItAgainStage = stage
        },
    ) { c ->
        ScenarioBookScreen(scenarioId = CaptureSeed.bookScenario.id, language = lang(c),
            onWatch = {}, onShadow = {}, onBack = {})
    }

    private fun book(chapter: String?) = mode(
        seed = {
            PracticeCaptureFlags.bookScenario = CaptureSeed.bookScenario
            PracticeCaptureFlags.bookChapter = chapter
        },
    ) { c ->
        ScenarioBookScreen(scenarioId = CaptureSeed.bookScenario.id, language = lang(c),
            onWatch = {}, onTalk = {}, onShadow = {}, onBack = {})
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun Scorecard() {
        // The iOS route draws the same harness page around `ScorecardView`.
        Scaffold(topBar = { TopAppBar(title = { Text(androidx.compose.ui.res.stringResource(com.roro.futurevoice.R.string.scorecard)) }) }) { padding ->
            Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState()).padding(vertical = 14.dp)) {
                Text(androidx.compose.ui.res.stringResource(com.roro.futurevoice.R.string.last_talk), style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp))
                val card = CaptureSeed.sampleScorecard
                ScoreBlock(
                    card = card,
                    contextLine = stringResource(
                        R.string.scored_against_your_level_setting_this_talk_itself_read_as,
                        "B1", card.cefrLevel.orEmpty().uppercase()),
                    grammarIssueCount = 0,
                    onGrammarReview = {})
            }
        }
    }

    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "practice-talk" to mode({ seedSessionsAndBooks(it, "practice-talk") }) { Practice(it, Shelf.TALK) },
        "practice-watch" to mode({ seedSessionsAndBooks(it, "practice-watch") }) { Practice(it, Shelf.WATCH) },
        "practice-studying" to mode({ seedSessionsAndBooks(it, "practice-studying") }) {
            Practice(it, Shelf.STUDYING)
        },
        // The book-first Studying page (iOS `790099d`): library tiles, then
        // every unfinished book newest first with its four chapter buttons.
        "practice-today" to mode({ seedSessionsAndBooks(it, "practice-today") }) {
            Practice(it, Shelf.STUDYING)
        },
        "practice-finished" to mode({ seedSessionsAndBooks(it, "practice-finished") }) {
            Practice(it, Shelf.FINISHED)
        },
        "practice-due" to mode({ seedPracticeDue(it, listOf("walk you through")) }) {
            Practice(it, Shelf.STUDYING)
        },
        // What the review reminder opens: on Android the due deck is its own
        // screen rather than a sheet over the tab, so the route IS this deck.
        "practice-review-route" to mode({ seedPracticeDue(it, emptyList()) }) { DueDeck(it) },
        "review-due" to mode({ c ->
            CaptureSeed.once("review-due") {
                CaptureSeed.seedVocab(c)
                snoozePast(c, 10 * MIN, listOf("appreciate", "reschedule"), listOf("catch up on"))
                // Still waiting — must NOT appear in the due deck.
                StudyScheduleStore.shared(c).snooze(StudyScheduleStore.Kind.WORD, "nuanced",
                    lang(c), System.currentTimeMillis() + 3 * DAY)
            }
        }) { DueDeck(it) },

        "drills" to mode({ seedDrills(it) }) { Drills(it) },
        // Android-only: iOS's harness has no mode for `SentencesView` (the
        // Studying page's Sentences tile). To study, then Known.
        "sentences" to mode({ seedDrills(it); PracticeCaptureFlags.sentencesKnown = false }) {
            com.roro.futurevoice.ui.SentencesScreen(language = lang(it), onOpenCard = {}, onBack = {})
        },
        "sentences-known" to mode({ seedDrills(it); PracticeCaptureFlags.sentencesKnown = true }) {
            com.roro.futurevoice.ui.SentencesScreen(language = lang(it), onOpenCard = {}, onBack = {})
        },
        "drills-tray" to mode({ seedDrills(it); PracticeCaptureFlags.previewDrillTray = true }) { Drills(it) },
        "drills-folder" to mode({ seedDrills(it); PracticeCaptureFlags.previewDrillFolder = true }) { Drills(it) },

        "daily-words" to mode({ seedVocab(it, fresh = true) }) {
            DailyDeck(it, StudyScheduleStore.Kind.WORD)
        },
        "daily-words-tray" to mode({
            seedVocab(it, fresh = true)
            PracticeCaptureFlags.stubWordEntry = CaptureSeed.fatWordEntry
            PracticeCaptureFlags.previewStudyTray = true
        }) { DailyDeck(it, StudyScheduleStore.Kind.WORD) },
        "daily-words-full" to mode({
            seedVocab(it, fresh = true)
            PracticeCaptureFlags.stubWordEntry = CaptureSeed.fatWordEntry
        }) { DailyDeck(it, StudyScheduleStore.Kind.WORD) },
        "daily-expressions" to mode({ seedVocab(it, fresh = true) }) {
            DailyDeck(it, StudyScheduleStore.Kind.EXPRESSION)
        },

        "vocab" to mode({ seedVocab(it) }) { Cloud(it) },
        // The notebook's card at full height over the cloud (iOS `vocab-card`:
        // `previewWordCard` pulls the sheet to `.large`). Offline, so the
        // card is handed a stub entry — iOS's run had the word cached.
        "vocab-card" to mode({ c ->
            seedVocab(c)
            // Pinned to a seeded notebook word, so the stub below is ITS entry
            // whatever other modes left at the head of the notebook.
            PracticeCaptureFlags.cloudOpenWord = "hesitate"
            PracticeCaptureFlags.stubWordEntry = hesitateEntry
        }) { Cloud(it) },
        "vocab-loading" to mode({
            seedVocab(it)
            PracticeCaptureFlags.cloudOpenWord = "zzz-uncached-word"
            PracticeCaptureFlags.slowLookupMs = 30_000L
        }) { Cloud(it) },
        "vocab-failed" to mode({
            seedVocab(it)
            PracticeCaptureFlags.cloudOpenWord = "zzz-uncached-word"
        }) { Cloud(it) },
        "expr" to mode({ c ->
            CaptureSeed.once("expr") { CaptureSeed.seedVocab(c); CaptureSeed.seedSessions(c, scored = true) }
        }) { LibraryScreen(kind = LibraryKind.EXPRESSIONS, language = lang(it), onBack = {}) },
        // One phrase's card open over the expressions list (iOS `expr-card`).
        // Offline, so the card is handed iOS's phrase-shaped stub entry: one
        // sense with the register line, two examples, two near-variants.
        "expr-card" to mode({ c ->
            CaptureSeed.once("expr") { CaptureSeed.seedVocab(c); CaptureSeed.seedSessions(c, scored = true) }
            PracticeCaptureFlags.stubWordEntry = pushBackEntry
        }) {
            // An example's "Shadow this" opens the shadow screen as the app
            // does (RootScreen: the card closes, the line opens).
            var shadow by remember { mutableStateOf<String?>(null) }
            val line = shadow
            if (line != null) {
                ShadowScreen(line = line, voiceId = "", targetLanguage = "en", onBack = { shadow = null })
            } else {
                LibraryScreen(kind = LibraryKind.EXPRESSIONS, language = lang(it), onBack = {})
                WordCardSheet(terms = listOf("push back"), initialTerm = "push back",
                    kind = LibraryKind.EXPRESSIONS, language = lang(it),
                    onShadow = { s -> shadow = s }, onDismiss = {})
            }
        },

        "book" to book(null),
        "book-words" to book("WORDS"),
        "book-lines" to book("SHADOW"),

        "talkdetail" to talkDetail(null),
        "talkdetail-mid" to talkDetail(null, "mid"),
        "talkdetail-low" to talkDetail(null, "low"),
        "talkdetail-words" to talkDetail("WORDS"),
        "talkdetail-expressions" to talkDetail("EXPRESSIONS"),
        "talkdetail-lines" to talkDetail("LINES"),
        "talkdetail-cards" to talkDetail("CARDS"),

        // Say it again: the talk book (and the scenario book) opened straight
        // into the runner. The two running states are SEEDED — a capture run
        // has no mic (iOS `DebugCapture.sayItAgainStage`).
        "say-again" to sayAgain("intro"),
        "say-again-reading" to sayAgain("reading"),
        "say-again-done" to sayAgain("done"),
        "say-again-scene" to sayAgainScene("intro"),
        "say-again-scene-reading" to sayAgainScene("reading"),
        "say-again-scene-done" to sayAgainScene("done"),

        "finished" to mode { _ ->
            Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
                FinishedBooksScreen(books = CaptureSeed.sampleFinishedBooks, onOpen = {}, onBack = {})
            }
        },
        "finished-empty" to mode { _ ->
            Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
                FinishedBooksScreen(books = emptyList(), onOpen = {}, onBack = {})
            }
        },

        // Android's karaoke is always estimated locally and nothing plays
        // until tapped, so iOS's `captureShadow` seam has nothing to switch.
        "shadow" to mode { _ ->
            val turn = CaptureSeed.shadowTurn
            ShadowScreen(line = turn.transcript, voiceId = "", targetLanguage = "en",
                turnId = turn.id, onBack = {})
        },
        "score" to mode({ c -> CaptureSeed.once("score") { CaptureSeed.seedVocab(c) } }) { Scorecard() },

        // Japanese: the one target that writes no spaces. The line has to be
        // cut into WORDS — each lighting and tapping on its own, punctuation
        // riding on the word before — not left as one run.
        "shadow-ja" to mode { _ ->
            val turn = CaptureSeed.japaneseShadowTurn
            ShadowScreen(line = turn.transcript, voiceId = "", targetLanguage = "ja",
                turnId = turn.id, onBack = {})
        },
        "talkdetail-ja" to mode(
            seed = {
                PracticeCaptureFlags.talkDetailSession = CaptureSeed.japaneseTalkSession
                PracticeCaptureFlags.talkDetailChapter = "WORDS"
            },
        ) { c ->
            TalkDetailScreen(sessionId = CaptureSeed.japaneseTalkSession.id, language = "ja",
                level = level(c), onBack = {}, onContinue = {})
        },
        // The English talk's transcript (iOS `TalkTranscriptView` on the
        // talk-detail session) — the talk book's Replay page, corrections
        // under the learner's lines, Replay / Continue pinned at the bottom.
        "transcript" to mode { c ->
            TalkTranscriptScreen(session = CaptureSeed.talkDetailSession, language = "en",
                level = level(c), onBack = {}, onContinue = {})
        },
        "transcript-ja" to mode { c ->
            TalkTranscriptScreen(session = CaptureSeed.japaneseTalkSession, language = "ja",
                level = level(c), onBack = {}, onContinue = {})
        },
        // A kanji headword has to print its reading (あわてる), or the card
        // teaches a word nobody can say.
        "wordcard-ja" to mode({ c ->
            CaptureSeed.seedJapaneseWords(c)
            PracticeCaptureFlags.cloudOpenWord = "慌てる"
        }) { Cloud(it, "ja") },
    )

    /** The word card's offline entry for `vocab-card` — one sense, two examples. */
    private val hesitateEntry = WordLore.Entry(
        pos = "동사",
        senses = listOf(WordLore.Sense(pos = "동사", meaning = "망설이다, 주저하다",
            note = "결정이나 행동을 바로 하지 못하고 머뭇거릴 때 써요.")),
        examples = listOf(
            WordLore.Example(text = "Don't hesitate to ask if you need anything.",
                meaning = "필요한 게 있으면 망설이지 말고 물어보세요."),
            WordLore.Example(text = "She hesitated before answering the question.",
                meaning = "그녀는 질문에 답하기 전에 잠시 망설였어요."),
        ),
    )

    /** iOS `expr-card`'s `stubWordEntry`, verbatim. */
    private val pushBackEntry = WordLore.Entry(
        pos = "구동사 · 일상 대화",
        senses = listOf(WordLore.Sense(pos = "", meaning = "제안이나 결정에 반대 의견을 내다; 밀어내듯 저항하다.",
            note = "회의나 협상에서 정중하게 반대할 때 자주 써요.")),
        examples = listOf(
            WordLore.Example(text = "I had to push back on the deadline — two weeks wasn't realistic.",
                meaning = "마감에 반대 의견을 내야 했어요. 2주는 현실적이지 않았거든요."),
            WordLore.Example(text = "Don't be afraid to push back on feedback you disagree with.",
                meaning = "동의하지 않는 피드백에는 주저 말고 반대 의견을 내세요.")),
        phrases = listOf(WordLore.Phrase(phrase = "raise concerns about", meaning = "~에 대해 우려를 제기하다"),
            WordLore.Phrase(phrase = "challenge", meaning = "이의를 제기하다")),
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
        "review-item-word" to "4.8 — A review reminder can't open ONE item: Android's reminder opens " +
            "the whole due queue (DeepLinkInbox.REVIEW carries no item) — no master-plan item yet",
        "review-item-sentence" to "4.8 — A review reminder can't open ONE sentence card: Android's " +
            "reminder opens the whole due queue — no master-plan item yet",
    )
}
