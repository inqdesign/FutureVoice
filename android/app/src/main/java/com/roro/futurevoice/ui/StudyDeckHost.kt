package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
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
    kind: StudyScheduleStore.Kind,
    language: String,
    nativeLanguage: String,
    level: CefrLevel,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val vocab = remember { VocabStore.shared(context) }
    var items by remember { mutableStateOf<List<StudyDeckItem>?>(null) }

    LaunchedEffect(kind, language) {
        val goal = 10
        items = when (kind) {
            StudyScheduleStore.Kind.WORD ->
                DailyStudyPick.words(context, goal, language, level).map(StudyDeckItem::word)
            StudyScheduleStore.Kind.EXPRESSION ->
                DailyStudyPick.expressions(context, goal, language).map(StudyDeckItem::expression)
        }
    }

    val dealt = items
    if (dealt == null) return
    if (dealt.isEmpty()) {
        EmptyDeck(kind, onBack)
        return
    }

    StudyDeckScreen(
        title = stringResource(
            if (kind == StudyScheduleStore.Kind.WORD) R.string.words else R.string.expressions),
        items = dealt,
        language = language,
        nativeLanguage = nativeLanguage,
        onResolve = { item, bin ->
            val manual = bin.manual
            if (manual != null) {
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
private fun EmptyDeck(kind: StudyScheduleStore.Kind, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Text(stringResource(
                        if (kind == StudyScheduleStore.Kind.WORD) R.string.words
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
