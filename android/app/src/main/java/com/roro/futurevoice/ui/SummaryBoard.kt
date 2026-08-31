package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.SessionSummarizer
import kotlinx.coroutines.delay

/**
 * The wait at the end of a talk, told as what is actually being built —
 * Android's `SummaryProgressView`. Every line is a REAL step with a real
 * number from `SessionSummarizer.Progress`; the reveal trails the truth by
 * [REVEAL_INTERVAL_MS] per step so sections landing in one burst still walk
 * on one at a time. Nothing is shown before it is genuinely done.
 * The same board serves the live wrap-up and the rescue path, as on iOS.
 */
@Composable
fun SummaryBoard(progress: SessionSummarizer.Progress, facts: String? = null) {
    data class Step(val title: Int, val done: Boolean, val count: Int?)
    val steps = listOf(
        Step(R.string.reading_the_conversation_back, progress.readBack, null),
        Step(R.string.lines_worth_saying_differently, progress.wroteCorrections, progress.phrases),
        Step(R.string.review_cards, progress.wroteDrills, progress.cards),
        Step(R.string.words_and_expressions_you_used, progress.wroteExpressions, progress.words),
        Step(R.string.new_expressions_from_the_call, progress.offered != null, progress.offered),
        Step(R.string.corrections_worth_keeping, progress.wroteGrammar, progress.corrections),
        Step(R.string.things_you_d_been_studying, progress.carryovers != null, progress.carryovers),
    )
    val doneCount = steps.count { it.done }
    var shown by remember { mutableIntStateOf(0) }
    LaunchedEffect(doneCount) {
        while (shown < doneCount) { shown += 1; delay(REVEAL_INTERVAL_MS) }
    }

    Column(Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.building_your_review_material),
            style = MaterialTheme.typography.titleSmall)
        LinearProgressIndicator(
            progress = { shown / steps.size.toFloat() },
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        )
        steps.forEachIndexed { index, step ->
            val done = index < shown
            val isCurrent = index == shown
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                when {
                    done -> Icon(Icons.Filled.CheckCircle, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                    isCurrent -> CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    else -> Icon(Icons.Outlined.Circle, contentDescription = null,
                        tint = MaterialTheme.colorScheme.outlineVariant, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(stringResource(step.title), style = MaterialTheme.typography.bodyMedium,
                        color = if (done || isCurrent) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.onSurfaceVariant)
                    // The one long step gets the talk's own numbers under it.
                    if (isCurrent && index == 0 && facts != null) {
                        Text(facts, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                step.count?.takeIf { it > 0 }?.let {
                    Text("$it", style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

private const val REVEAL_INTERVAL_MS = 180L
