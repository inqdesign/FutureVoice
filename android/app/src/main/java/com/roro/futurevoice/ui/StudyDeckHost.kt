package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DailyStudyPick
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.ReviewQueue
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DrillBin

/**
 * Deals today's hand and writes each verdict — the two `DailyWordsView` /
 * `DailyExpressionsView` halves, which differ only in which store a card
 * lands in. The hand is picked once and stays fixed for the session.
 *
 * A rep is a RESOLVED card, and the store logs it on a STATE CHANGE
 * (`addStudying` / `markKnown` both log): re-snoozing an item already in the
 * notebook changes no state, so the rep is logged here instead. Missing that
 * is how a deck ends up logging nothing on its second pass through the same
 * word.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudyDeckHost(
    /** null = the PUT-OFF pile: everything put off — words, expressions and
     *  sentence cards, due or not — in return order ([putOffDeck]). A
     *  per-kind deck deals today's hand instead. */
    kind: StudyScheduleStore.Kind?,
    language: String,
    nativeLanguage: String,
    level: CefrLevel,
    /** The one item a per-item reminder named — dealt on its own (iOS
     *  `DueReviewView(focus:)`). */
    focus: StudyDeckItem? = null,
    /** A book chapter's own deck (the Review tab's chapter buttons): these
     *  items, under [handTitle], instead of a dealt hand or the put-off pile
     *  (iOS `DueReviewView(hand:title:)`). */
    hand: List<StudyDeckItem>? = null,
    handTitle: String? = null,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val vocab = remember { VocabStore.shared(context) }
    var items by remember { mutableStateOf<List<StudyDeckItem>?>(null) }

    LaunchedEffect(kind, language, focus, hand) {
        val goal = 10
        items = if (focus != null) listOf(focus) else if (hand != null) hand else when (kind) {
            null -> putOffDeck(context, language)
            StudyScheduleStore.Kind.WORD ->
                DailyStudyPick.words(context, goal, language, level).map(StudyDeckItem::word)
            StudyScheduleStore.Kind.EXPRESSION ->
                DailyStudyPick.expressions(context, goal, language).map(StudyDeckItem::expression)
        }
    }

    val dealt = items
    if (dealt == null) return
    if (dealt.isEmpty()) {
        EmptyDeck(kind, onBack, handTitle)
        return
    }

    StudyDeckScreen(
        title = handTitle ?: stringResource(when (kind) {
            null -> R.string.back_from_earlier
            StudyScheduleStore.Kind.WORD -> R.string.words
            else -> R.string.expressions
        }),
        items = dealt,
        language = language,
        nativeLanguage = nativeLanguage,
        onResolve = { item, bin ->
            val manual = bin.manual
            val cardId = item.cardId
            if (cardId != null) {
                // The sentence deck's own verdicts (`DrillDeckScreen.apply`).
                val drills = com.roro.futurevoice.data.DrillStore.shared(context)
                val card = drills.load(language).firstOrNull { it.id == cardId }
                if (card != null) {
                    if (manual != null) {
                        drills.fileInBin(card, manual.first, manual.second, language)
                        ReviewQueue.armSentence(context, card, System.currentTimeMillis() + manual.second)
                    } else {
                        drills.markKnown(card, language)
                        ReviewQueue.cancelSentence(context, card.id)
                    }
                }
            } else if (manual != null) {
                // A delay means "still learning": the item joins the notebook
                // if it wasn't there, and its return goes into the schedule
                // the next deal reads.
                when (item.kind) {
                    StudyScheduleStore.Kind.WORD ->
                        if (vocab.isStudying(item.text, language))
                            PracticeLog.record(context, PracticeLog.Kind.WORD)
                        else vocab.addStudying(item.text, language)
                    StudyScheduleStore.Kind.EXPRESSION ->
                        if (vocab.isStudyingExpression(item.text, language))
                            PracticeLog.record(context, PracticeLog.Kind.EXPRESSION)
                        else vocab.setStudyingExpression(item.text, true, language)
                }
                com.roro.futurevoice.data.DrillReminder.reschedule(context)
                ReviewQueue.snooze(context, item.kind, item.text, language, manual.second)
            } else {
                when (item.kind) {
                    StudyScheduleStore.Kind.WORD -> vocab.markKnown(item.text, language)
                    StudyScheduleStore.Kind.EXPRESSION ->
                        vocab.setKnownExpression(item.text, true, language)
                }
                ReviewQueue.retire(context, item.kind, item.text, language)
            }
        },
        onBack = onBack,
    )
}

/** Where the material comes from — the deck can't be stocked from this screen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EmptyDeck(kind: StudyScheduleStore.Kind?, onBack: () -> Unit, handTitle: String? = null) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Text(handTitle ?: stringResource(
                        if (kind == null) R.string.back_from_earlier
                        else if (kind == StudyScheduleStore.Kind.WORD) R.string.words
                        else R.string.expressions))
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().padding(30.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (kind == null && handTitle == null) {
                // The put-off pile: it says what lands here, never invents work.
                Icon(Icons.Filled.CheckCircle, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.nothing_put_off),
                    style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.nothing_put_off_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center)
                return@Column
            }
            Icon(Icons.AutoMirrored.Filled.MenuBook, contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                stringResource(
                    if (kind == StudyScheduleStore.Kind.WORD)
                        R.string.nothing_to_study_yet_have_a_talk_or_watch_a_scene_first
                    else R.string.expressions_from_your_calls_will_collect_here),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * EVERYTHING the learner put off — words, expressions and sentence cards, due
 * or not — in the order it comes back (iOS `DueReviewView.putOffDeck`,
 * 2026-10-03: "what I put off, show me all of it", and "1 of N" counts all of
 * it). A put-off item is still a promise the learner made; one whose time
 * hasn't come is not hidden for that.
 */
suspend fun putOffDeck(context: android.content.Context, language: String,
                       now: Long = System.currentTimeMillis()): List<StudyDeckItem> {
    val snap = StudyScheduleStore.shared(context).snapshot(language)
    val scheduled = (snap.dueItems(now) + snap.upcoming(now))
        .map { StudyDeckItem(it.kind, it.text) to it.at }
    val sentences = com.roro.futurevoice.data.DrillStore.shared(context).putOffCards(language)
        .map { StudyDeckItem.sentence(it) to it.nextReviewAt }
    return (scheduled + sentences).sortedBy { it.second }.map { it.first }.distinctBy { it.id }
}

/** What the header's put-off dot counts: words, expressions and sentence
 *  cards whose return time has COME (iOS `dueReviewCount`). */
suspend fun putOffDueCount(context: android.content.Context, language: String,
                           now: Long = System.currentTimeMillis()): Int =
    StudyScheduleStore.shared(context).snapshot(language).dueItems(now).size +
        com.roro.futurevoice.data.DrillStore.shared(context).putOffCards(language).count { it.nextReviewAt <= now }
