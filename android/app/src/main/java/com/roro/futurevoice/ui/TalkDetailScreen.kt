package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Abc
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Comment
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Style
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.foundation.layout.size
import androidx.compose.ui.graphics.Color
import com.roro.futurevoice.R
import com.roro.futurevoice.data.BookDocument
import kotlinx.coroutines.launch
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.AxisScore
import com.roro.futurevoice.talk.Carryover
import com.roro.futurevoice.talk.GrammarIssue
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionScorecard
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.BookmarkTab
import com.roro.futurevoice.ui.brand.BookmarkedPage
import com.roro.futurevoice.ui.brand.Books
import com.roro.futurevoice.ui.brand.DialogueLine
import com.roro.futurevoice.ui.brand.DialogueScale
import com.roro.futurevoice.ui.brand.DisplayFace
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/** The Talk book's chapters — the same set iOS opens (`ConversationDetailView`). */
private enum class TalkChapter { INTRO, WORDS, EXPRESSIONS, LINES, CARDS }

/**
 * A finished talk's BOOK. Same object as the Watch book: one ribbon page,
 * chapters named by what you do in them. The intro is the COVER and the
 * report in one — title, how far its material is mastered, the score with
 * its per-axis notes, the coach's note, and what carried over from practice.
 *
 * The raw conversation sits behind Replay, as it does on iOS — a book opens
 * on what there is to learn, not on the log of the call.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TalkDetailScreen(
    sessionId: String,
    language: String,
    /** Decides which pickup words are worth keeping and which lines teach. */
    level: com.roro.futurevoice.data.CefrLevel = com.roro.futurevoice.data.CefrLevel.B1,
    onBack: () -> Unit,
    onShadow: (String) -> Unit = {},
    /** Pick the talk back up — a metered call, so the host gates it. */
    onContinue: ((String) -> Unit)? = null,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var session by remember { mutableStateOf<Session?>(null) }
    var chapter by remember { mutableStateOf(
        TalkChapter.entries.firstOrNull { it.name == com.roro.futurevoice.capture.flags.PracticeCaptureFlags.talkDetailChapter }
            ?: TalkChapter.INTRO) }
    LaunchedEffect(sessionId, revision) {
        session = com.roro.futurevoice.capture.flags.PracticeCaptureFlags.talkDetailSession?.takeIf { it.id == sessionId }
            ?: SessionStore.shared(context).load(language).firstOrNull { it.id == sessionId }
    }
    val s = session ?: return
    val sm = s.summary
    // The talk's review material, DERIVED — the same anatomy a Watch book
    // has. Words are the fluent self's PICKUP words (ones it used and the
    // learner hasn't), not the learner's own; shadow lines are the few worth
    // saying again, not every line it spoke.
    var curriculum by remember(sessionId, revision) {
        mutableStateOf(com.roro.futurevoice.data.TalkCurriculum.Snapshot())
    }
    // The Shadow chapter's turns, for the sheet; the ROWS come from
    // `curriculum.shadowLines` so the page and the count are one set.
    var shadowTurns by remember(sessionId, revision) {
        mutableStateOf<List<com.roro.futurevoice.talk.Turn>>(emptyList())
    }
    var bestTakes by remember(sessionId, revision) { mutableStateOf<Map<String, Int>>(emptyMap()) }
    LaunchedEffect(sessionId, revision, level) {
        val attempts = com.roro.futurevoice.data.ShadowAttemptStore.shared(context).load(language)
        curriculum = com.roro.futurevoice.data.TalkCurriculum.build(
            session = s, level = level, language = language,
            vocab = com.roro.futurevoice.data.VocabStore.shared(context),
            attempts = attempts,
            drillCards = com.roro.futurevoice.data.DrillStore.shared(context).load(language))
        shadowTurns = com.roro.futurevoice.data.TalkCurriculum.shadowPicks(s, level, language)
        bestTakes = attempts.groupBy { it.turnId }.mapValues { (_, v) -> v.maxOf { it.matchScore } }
    }
    // What the learner actually said, per correction: a turn-derived item
    // carries its source turn in its id; a summary one is matched by text.
    val saidByPhrase = sm?.phrasesUsed.orEmpty()
        .associateBy({ com.roro.futurevoice.talk.CarryoverDetector.normalized(it.fluentAlternative) }, { it.userSaid })
    fun originalOf(item: com.roro.futurevoice.talk.ScenarioCurriculum.Item): String? {
        val turnId = com.roro.futurevoice.data.TalkCurriculum.turnIdOfCorrection(item.id)
        val said = s.turns.firstOrNull { it.id == turnId }?.transcript
            ?: saidByPhrase[com.roro.futurevoice.talk.CarryoverDetector.normalized(item.text)]
        return said?.let { com.roro.futurevoice.data.DrillIngest.relevantFragment(it, item.text) }
    }
    val grammar = sm?.grammarIssues.orEmpty()
    // The transcript is the book's "scene": one tap away behind Replay, never
    // the first thing the cover shows. Android has no separate transcript
    // destination, so the page opens it in place.
    var showingTranscript by remember(sessionId) { mutableStateOf(false) }
    var showingGrammarReview by remember(sessionId) { mutableStateOf(false) }

    val tabs = buildList {
        add(BookmarkTab(TalkChapter.INTRO, Icons.Filled.MenuBook, stringResource(R.string.overview)))
        if (curriculum.words.isNotEmpty()) {
            // Words carry MASTERY, not a bare count — the ribbon is the
            // book's progress, the same way the Watch book's does it.
            add(BookmarkTab(TalkChapter.WORDS, Icons.Filled.Abc,
                stringResource(R.string.words_d26d55),
                done = curriculum.words.count { it.masteredAt != null },
                total = curriculum.words.size))
        }
        // Every chapter carries done/total now — each one counts toward the
        // book, so each ribbon shows how far along it is (iOS 54).
        if (curriculum.expressions.isNotEmpty()) {
            add(BookmarkTab(TalkChapter.EXPRESSIONS, Icons.Filled.FormatQuote,
                stringResource(R.string.expressions),
                done = curriculum.expressions.count { it.masteredAt != null },
                total = curriculum.expressions.size))
        }
        if (curriculum.shadowLines.isNotEmpty()) {
            add(BookmarkTab(TalkChapter.LINES, Icons.Filled.Mic,
                stringResource(R.string.shadow),
                done = curriculum.shadowLines.count { it.masteredAt != null },
                total = curriculum.shadowLines.size))
        }
        if (curriculum.corrections.isNotEmpty()) {
            add(BookmarkTab(TalkChapter.CARDS, Icons.Filled.Style,
                stringResource(R.string.drill),
                done = curriculum.corrections.count { it.masteredAt != null },
                total = curriculum.corrections.size))
        } else if (grammar.isNotEmpty()) {
            add(BookmarkTab(TalkChapter.CARDS, Icons.Filled.Style,
                stringResource(R.string.drill), count = grammar.size))
        }
    }

    if (showingGrammarReview) {
        GrammarReviewSheet(
            axis = sm?.scorecard?.grammar,
            issues = grammar,
            onDismiss = { showingGrammarReview = false })
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(s.displayTitle ?: stringResource(R.string.conversation)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    BookExportMenu(
                        document = { BookDocument.make(context, s) },
                        nativeLanguage = com.roro.futurevoice.core.UILanguage.current(context) ?: "en",
                        targetLanguage = language)
                },
            )
        }
    ) { padding ->
        BookmarkedPage(
            tabs = tabs,
            selection = if (tabs.any { it.id == chapter }) chapter else TalkChapter.INTRO,
            onSelect = { chapter = it },
            modifier = Modifier.padding(padding).background(AppSurfaces.ground)
                .padding(end = 16.dp, top = 8.dp, bottom = 16.dp),
        ) {
            Column(Modifier.fillMaxWidth()) {
                when (if (tabs.any { it.id == chapter }) chapter else TalkChapter.INTRO) {
                    TalkChapter.INTRO -> {
                        CoverBlock(
                            title = s.displayTitle ?: stringResource(R.string.conversation),
                            subtitle = coverSubtitle(s),
                            archived = s.archivedAt != null,
                            progress = curriculum.progress.toFloat()
                                .takeIf { curriculum.totalCount > 0 },
                            progressLabel = stringResource(R.string.lld_of_lld_mastered,
                                curriculum.masteredCount, curriculum.totalCount),
                            mastered = curriculum.isMastered,
                            onReplay = { showingTranscript = !showingTranscript },
                            onContinue = onContinue?.let { go ->
                                { go(s.topic ?: s.displayTitle.orEmpty()) }
                            })
                        if (curriculum.isMastered && s.archivedAt == null) {
                            MasteredBanner(onArchive = {
                                scope.launch {
                                    SessionStore.shared(context).setArchived(s.id, true, language)
                                    StoreEvents.bump()
                                }
                            })
                        }
                        sm?.scorecard?.let { card ->
                            HorizontalDivider(Modifier.padding(start = 20.dp))
                            ScoreBlock(
                                card = card,
                                // The scores grade THIS talk against the
                                // learner's level SETTING — say which, or the
                                // number reads as a level claim.
                                contextLine = card.cefrLevel?.uppercase()?.let {
                                    stringResource(
                                        R.string.scored_against_your_level_setting_this_talk_itself_read_as,
                                        level.code.uppercase(), it)
                                } ?: stringResource(
                                    R.string.scored_against_your_level_setting_how_this_talk_went_not_a_l_4b7213,
                                    level.code.uppercase()),
                                grammarIssueCount = grammar.size,
                                onGrammarReview = { showingGrammarReview = true })
                        }
                        sm?.overallNote?.takeIf { it.isNotBlank() }?.let {
                            HorizontalDivider(Modifier.padding(start = 20.dp, top = 8.dp))
                            GroupLabel(Icons.Filled.Comment, stringResource(R.string.coach_s_note))
                            Text(it, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 20.dp)
                                    .padding(top = 2.dp, bottom = 8.dp))
                        }
                        CarryoverBlock(sm?.carryovers.orEmpty())
                        if (showingTranscript) {
                            PageTitle(stringResource(R.string.transcript))
                            Column(Modifier.padding(horizontal = 20.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                // The BRANDED line (bubbles, speaker sides) —
                                // the one dialogue surface, same as the live
                                // call and the Watch scene. The flat overload
                                // this used to call is the legacy one.
                                s.turns.forEach {
                                    DialogueLine(turn = it, scale = DialogueScale.STANDARD)
                                }
                            }
                        }
                    }

                    TalkChapter.WORDS -> {
                        PageTitle(stringResource(R.string.words_d26d55))
                        Column(Modifier.padding(horizontal = 20.dp)) {
                            curriculum.words.forEach { item ->
                                Row(Modifier.fillMaxWidth().padding(vertical = 5.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    // Mastery is READ, never stored here: the
                                    // vocab store is the one source of truth.
                                    MasteryMark(item.masteredAt != null)
                                    Text(item.text, style = MaterialTheme.typography.bodyLarge)
                                }
                            }
                        }
                        PageFooter(stringResource(R.string.words_your_fluent_self_used_that_you_havent))
                    }

                    TalkChapter.EXPRESSIONS -> {
                        PageTitle(stringResource(R.string.expressions))
                        Column(Modifier.padding(horizontal = 20.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            // The curriculum's own list, split back into
                            // the two groups; offered ABOVE used — a book
                            // exists to teach what you can't say yet.
                            val mine = sm?.expressionsUsed.orEmpty()
                                .map { com.roro.futurevoice.talk.CarryoverDetector.normalized(it) }.toSet()
                            val (used, offered) = curriculum.expressions.partition {
                                com.roro.futurevoice.talk.CarryoverDetector.normalized(it.text) in mine
                            }
                            offered.forEach { MasteryRow(it.text, it.masteredAt != null) }
                            if (used.isNotEmpty()) {
                                if (offered.isNotEmpty()) HorizontalDivider(Modifier.padding(vertical = 4.dp))
                                used.forEach { MasteryRow(it.text, it.masteredAt != null) }
                            }
                        }
                        PageFooter(stringResource(
                            R.string.the_reusable_phrases_this_talk_produced_the_ones_your_fluent_1940be))
                    }

                    TalkChapter.LINES -> {
                        PageTitle(stringResource(R.string.shadow))
                        Column(Modifier.padding(horizontal = 20.dp)) {
                            curriculum.shadowLines.forEach { line ->
                                val text = shadowTurns.firstOrNull { it.id == line.id }?.transcript ?: line.text
                                MasteryRow(text, line.masteredAt != null,
                                    score = bestTakes[line.id],
                                    onClick = { onShadow(text) })
                            }
                        }
                        PageFooter(stringResource(R.string.repeat_your_fluent_self_s_lines_from_this_talk))
                    }

                    TalkChapter.CARDS -> {
                        PageTitle(stringResource(R.string.drill))
                        Column(Modifier.padding(horizontal = 20.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            // `curriculum.corrections` holds both sources (turn
                            // suggestions and the summary's own) in page
                            // order, so this list and the ribbon's done/total
                            // are the same set.
                            curriculum.corrections.forEach { item ->
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    MasteryMark(item.masteredAt != null, Modifier.padding(top = 3.dp))
                                    Column {
                                        originalOf(item)?.let {
                                            Text(it, style = MaterialTheme.typography.bodyMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                        Text(item.text,
                                            style = MaterialTheme.typography.bodyLarge,
                                            color = MaterialTheme.colorScheme.primary)
                                        if (item.note.isNotBlank()) {
                                            Text(item.note, style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                }
                            }
                            grammar.forEach { g ->
                                Column {
                                    Text(g.quote, style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(g.correction, style = MaterialTheme.typography.bodyLarge)
                                    if (g.note.isNotBlank()) {
                                        Text(g.note, style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** "13 Sep 2026, 22:26 · 2 turns spoken" — when it happened, and how much of
 *  it was the learner. Turns SPOKEN, not turns: the fluent self's half is not
 *  what the learner did. */
@Composable
private fun coverSubtitle(s: Session): String {
    val at = s.endedAt ?: s.startedAt
    val when_ = DateFormat
        .getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.getDefault())
        .format(Date(at))
    val spoken = s.turns.count { it.role == TurnRole.USER }
    return "$when_ · " + stringResource(R.string.lld_turns_spoken_38ecf5, spoken)
}

/**
 * The book's cover — the round mark, what the talk was, how far its material
 * is mastered, and the one action.
 *
 * iOS pairs Replay with Continue. Android has no way back into a live call
 * from this page yet, so the row carries Replay alone: a button that cannot
 * do its job teaches the learner the whole row is decorative.
 */
@Composable
private fun CoverBlock(
    title: String,
    subtitle: String,
    archived: Boolean,
    progress: Float?,
    progressLabel: String,
    mastered: Boolean,
    onReplay: () -> Unit,
    /** Pick the talk back up. Null when the host has nowhere to start a
     *  call from, in which case Replay stands alone rather than beside a
     *  dead button. */
    onContinue: (() -> Unit)?,
) {
    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                Modifier.size(56.dp)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Forum, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(26.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(title, style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold, maxLines = 2,
                    overflow = TextOverflow.Ellipsis)
                Text(subtitle, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (archived) {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Filled.Archive, contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.archived),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        if (progress != null) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth(),
                    color = if (mastered) Books.mastery else MaterialTheme.colorScheme.primary)
                Text(progressLabel, style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        // Continue leads — picking the talk back up is what this page is
        // for; Replay is the quieter half of the pair, as on iOS.
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (onContinue != null) {
                Button(onClick = onContinue, modifier = Modifier.weight(1f)) {
                    Icon(Icons.AutoMirrored.Filled.Chat, contentDescription = null,
                        modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.continue_))
                }
            }
            FilledTonalButton(
                onClick = onReplay,
                modifier = Modifier.weight(1f),
                // The accent wash iOS's `.bordered` button carries — derived
                // from the theme's primary, never a colour of its own.
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                    contentColor = MaterialTheme.colorScheme.primary),
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null,
                    modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.replay))
            }
        }
    }
}

/** Everything this talk had to teach is mastered — and the one thing left to
 *  do with it, filing it away, is offered right here as on iOS. Archiving is
 *  tidying, so it is never the achievement itself. */
@Composable
private fun MasteredBanner(onArchive: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.Filled.WorkspacePremium, contentDescription = null,
            tint = Books.mastery, modifier = Modifier.size(26.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.talk_mastered),
                style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.everything_this_conversation_had_to_teach_is_yours),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Button(onClick = onArchive,
            colors = ButtonDefaults.buttonColors(containerColor = Books.mastery)) {
            Text(stringResource(R.string.archive))
        }
    }
}

/**
 * The scorecard: the headline number and what it was graded against, the
 * coach's one-line verdict, then the axes — each a number, a bar and a line
 * saying what the number means.
 *
 * Pronunciation is drawn only when the analyzer produced it. It never does on
 * Android today, and an axis row reading "—" forever is a promise the app
 * can't keep.
 */
@Composable
internal fun ScoreBlock(
    card: SessionScorecard,
    contextLine: String,
    grammarIssueCount: Int,
    onGrammarReview: () -> Unit,
) {
    GroupLabel(Icons.Filled.BarChart, stringResource(R.string.score))
    Column(
        Modifier.padding(horizontal = 20.dp).padding(top = 2.dp, bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.overall), style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            val overall = "${card.overall}"
            Text(overall,
                style = DisplayFace.style(overall, MaterialTheme.typography.headlineSmall),
                color = scoreColor(card.overall))
        }
        Text(contextLine, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (card.topLine.isNotBlank()) {
            Text(card.topLine, style = MaterialTheme.typography.titleMedium)
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AxisRow(card.vocabulary, stringResource(R.string.vocabulary), Icons.Filled.Abc)
            AxisRow(card.grammar, stringResource(R.string.grammar), Icons.Filled.Verified,
                // A low score must never be a number the learner can't
                // interrogate — the slips behind it are one tap away.
                detailCount = grammarIssueCount.takeIf { it > 0 },
                onClick = onGrammarReview.takeIf { grammarIssueCount > 0 })
            AxisRow(card.expressiveness, stringResource(R.string.expressiveness),
                Icons.Filled.FormatQuote)
            AxisRow(card.fluency, stringResource(R.string.fluency_pace), Icons.Filled.Speed)
            card.pronunciation?.let {
                AxisRow(it, stringResource(R.string.pronunciation), Icons.Filled.GraphicEq)
            }
        }
    }
}

@Composable
private fun AxisRow(
    axis: AxisScore,
    label: String,
    icon: ImageVector,
    detailCount: Int? = null,
    onClick: (() -> Unit)? = null,
) {
    Column(
        Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.primary)
            Text(label, style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium)
            Spacer(Modifier.weight(1f))
            Text("${axis.score}", style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold, color = scoreColor(axis.score))
            if (detailCount != null) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.outline)
            }
        }
        LinearProgressIndicator(
            progress = { axis.score / 100f },
            modifier = Modifier.fillMaxWidth(),
            color = scoreColor(axis.score))
        if (axis.note.isNotBlank()) {
            Text(axis.note, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (detailCount != null) {
            Text(
                stringResource(R.string.review_lld_grammar_from_this_talk, detailCount,
                    stringResource(if (detailCount == 1) R.string.slip else R.string.slips)),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.primary)
        }
    }
}

/**
 * Studied, then SAID — the loop closing. No prompt was on screen when these
 * came out, which is why they get their own block rather than a line in the
 * score.
 */
@Composable
private fun CarryoverBlock(carryovers: List<Carryover>) {
    if (carryovers.isEmpty()) return
    GroupLabel(Icons.Filled.TrackChanges, stringResource(R.string.you_used_what_you_practiced))
    carryovers.forEach { c ->
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null,
                    tint = Books.mastery, modifier = Modifier.size(18.dp))
                Text(c.item, style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium)
            }
            Text("“${c.quote}”", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 26.dp))
            Row(Modifier.padding(start = 26.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(c.source.icon(), contentDescription = null, modifier = Modifier.size(13.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(c.source.labelRes()),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    PageFooter(stringResource(
        R.string.no_prompt_no_card_on_screen_you_reached_for_these_yourself_c_747561))
}

/** Where the learner met the item, in their words — the same five names the
 *  wrap-up and Progress use, so no surface describes a source differently. */
private fun Carryover.Source.labelRes(): Int = when (this) {
    Carryover.Source.DRILL_CARD -> R.string.review_cards
    Carryover.Source.CURRICULUM_ITEM -> R.string.your_books
    Carryover.Source.STUDYING_EXPRESSION -> R.string.expression_notebook
    Carryover.Source.STUDYING_WORD -> R.string.word_notebook
    Carryover.Source.SUGGESTION -> R.string.in_call_suggestions
}

private fun Carryover.Source.icon(): ImageVector = when (this) {
    Carryover.Source.DRILL_CARD -> Icons.Filled.Style
    Carryover.Source.CURRICULUM_ITEM -> Icons.Filled.MenuBook
    Carryover.Source.STUDYING_EXPRESSION -> Icons.Filled.Bookmark
    Carryover.Source.STUDYING_WORD -> Icons.Filled.Book
    Carryover.Source.SUGGESTION -> Icons.Filled.Lightbulb
}

/**
 * Every verified grammar slip behind the grammar score: what the learner
 * literally said, the grammar-only fix, and the point involved. Quotes are
 * hallucination-guarded upstream — all of it appeared in their own turns.
 *
 * iOS also lets a slip be flagged as misheard, which rescales the score.
 * Android has no exclusion API yet, so this page reads only.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GrammarReviewSheet(
    axis: AxisScore?,
    issues: List<GrammarIssue>,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
                .padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Verified, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.grammar_review),
                    style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.weight(1f))
                axis?.let {
                    Text("${it.score}", style = MaterialTheme.typography.titleLarge,
                        color = scoreColor(it.score))
                }
            }
            axis?.note?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(
                stringResource(R.string.lld_this_session, issues.size,
                    stringResource(if (issues.size == 1) R.string.slip else R.string.slips)),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            issues.forEach { issue ->
                val diff = remember(issue.id) { GrammarDiff(issue.quote, issue.correction) }
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Close, contentDescription = null,
                            modifier = Modifier.size(16.dp), tint = Color(0xFFFF3B30))
                        Text(diff.quote, style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Check, contentDescription = null,
                            modifier = Modifier.size(16.dp), tint = Books.mastery)
                        Text(diff.correction, style = MaterialTheme.typography.bodyLarge)
                    }
                    if (issue.note.isNotBlank()) {
                        Text(issue.note, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(start = 24.dp))
                    }
                }
            }
            Text(stringResource(
                R.string.every_slip_below_is_quoted_from_what_you_actually_said_this_8d3781),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * Word-level diff between a quote and its correction, so the review shows
 * WHICH words were wrong instead of making the learner spot the difference.
 * Computed in code — a score's evidence is never something the LLM re-writes.
 */
private class GrammarDiff(quote: String, correction: String) {
    val quote: androidx.compose.ui.text.AnnotatedString
    val correction: androidx.compose.ui.text.AnnotatedString

    init {
        val q = quote.split(' ').filter { it.isNotEmpty() }
        val c = correction.split(' ').filter { it.isNotEmpty() }
        val (keepQ, keepC) = commonIndices(q.map(::norm), c.map(::norm))
        this.quote = render(q, keepQ,
            SpanStyle(color = Color(0xFFFF3B30), textDecoration = TextDecoration.LineThrough))
        this.correction = render(c, keepC,
            SpanStyle(color = Books.mastery, fontWeight = FontWeight.Bold))
    }

    private fun render(
        words: List<String>, keep: Set<Int>, changed: SpanStyle,
    ) = buildAnnotatedString {
        words.forEachIndexed { i, w ->
            if (i > 0) append(" ")
            if (i in keep) append(w) else withStyle(changed) { append(w) }
        }
    }

    private companion object {
        /** Punctuation and casing come from the transcriber, never from the
         *  learner's mouth — "bank," vs "bank" must not light up as a change. */
        fun norm(s: String) = s.lowercase().filter { it.isLetterOrDigit() || it == '\'' }

        /** Longest common subsequence; returns the UNCHANGED indices on each
         *  side. Sentences are short, so the O(n·m) table is trivial. */
        fun commonIndices(a: List<String>, b: List<String>): Pair<Set<Int>, Set<Int>> {
            val dp = Array(a.size + 1) { IntArray(b.size + 1) }
            for (i in a.indices.reversed()) for (j in b.indices.reversed()) {
                dp[i][j] = if (a[i] == b[j]) dp[i + 1][j + 1] + 1
                else maxOf(dp[i + 1][j], dp[i][j + 1])
            }
            val keepA = HashSet<Int>(); val keepB = HashSet<Int>()
            var i = 0; var j = 0
            while (i < a.size && j < b.size) {
                when {
                    a[i] == b[j] -> { keepA.add(i); keepB.add(j); i++; j++ }
                    dp[i + 1][j] >= dp[i][j + 1] -> i++
                    else -> j++
                }
            }
            return keepA to keepB
        }
    }
}

/** iOS's three score bands, unchanged: 80+ is mastery green, the middle is
 *  the theme's own accent, below 50 is the warning orange. */
@Composable
private fun scoreColor(score: Int): Color = when {
    score >= 80 -> Books.mastery
    score >= 50 -> MaterialTheme.colorScheme.primary
    else -> Color(0xFFFF9500)
}

/** A small label above a group inside a page that stacks more than one kind
 *  of material. */
@Composable
private fun GroupLabel(icon: ImageVector, title: String) {
    Row(
        Modifier.padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(14.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun PageTitle(title: String) {
    Text(title, style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(horizontal = 20.dp).padding(top = 18.dp, bottom = 6.dp))
}

@Composable
private fun PageFooter(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 20.dp).padding(top = 10.dp, bottom = 6.dp))
}

/** A study row's state up front — the same mark on every chapter. Mastery is
 *  READ from the stores, never stored here. */
@Composable
private fun MasteryMark(mastered: Boolean, modifier: Modifier = Modifier) {
    Icon(
        if (mastered) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
        contentDescription = null,
        modifier = modifier.size(15.dp),
        tint = if (mastered) Color(0xFF34C759) else MaterialTheme.colorScheme.onSurfaceVariant)
}

/** Mark · text · (best take) — the row grammar every study list shares. */
@Composable
private fun MasteryRow(text: String, mastered: Boolean, score: Int? = null, onClick: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        MasteryMark(mastered)
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        if (score != null) {
            Text("$score", style = MaterialTheme.typography.labelMedium,
                color = if (score >= com.roro.futurevoice.data.TalkCurriculum.SHADOW_MASTERY_SCORE)
                    Color(0xFF34C759) else MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
