package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.GoalStore
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * Practice's three shelves, split by ACTIVITY rather than source: Studying is
 * the cross-cutting page, Talk is the calls you had, Watch the scenes you
 * watched. Each book carries its own origin tag for the orthogonal question.
 */
enum class Shelf(val labelRes: Int) {
    STUDYING(R.string.studying),
    TALK(R.string.talk),
    WATCH(R.string.watch),
}

@Composable
fun ShelfChips(selected: Shelf, counts: (Shelf) -> Int?, onSelect: (Shelf) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Shelf.entries.forEach { s ->
            FilterChip(
                selected = s == selected,
                onClick = { onSelect(s) },
                label = {
                    val n = counts(s)
                    Text(if (n == null) stringResource(s.labelRes)
                    else "${stringResource(s.labelRes)}  $n")
                },
            )
        }
    }
}

/**
 * Today's work, in one card: the streak it adds up to, anything whose snooze
 * ran out, and the four challenges as a 2×2 grid.
 *
 * A GRID, not stacked rows. Full-width rows made the card tall and gave each
 * bar more room than a bar deserves; a tile carries the same numbers in half
 * the height (iOS `todayCard`).
 */
@Composable
fun TodayCard(
    goals: GoalStore.Goals,
    today: PracticeLog.Day,
    streak: Int,
    dueSentences: Int,
    dueWords: Int,
    dueExpressions: Int,
    onSentences: () -> Unit,
    onWords: () -> Unit,
    onExpressions: () -> Unit,
    onShadowing: () -> Unit,
    onEditGoals: () -> Unit,
) {
    Column(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, RoundedCornerShape(16.dp))
            .padding(vertical = 12.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.today), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f))
            if (streak > 0) {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Icon(Icons.Filled.LocalFireDepartment, contentDescription = null,
                        tint = Color(0xFFFF9500), modifier = Modifier.size(16.dp))
                    Text("$streak", style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold, color = Color(0xFFFF9500))
                }
            }
        }

        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                // Sentences is the only conditional one: it is a moving target
                // (clear today's deck), and on a day with nothing due and
                // nothing done there is nothing to ask for.
                if (goals.sentences > 0 && (dueSentences > 0 || today.drillDone > 0)) {
                    ChallengeTile(
                        icon = Icons.Filled.CheckCircle,
                        title = stringResource(R.string.sentences),
                        done = today.drillDone,
                        // Never more than exists to do — asking for 20 when 3
                        // cards are due makes the day unwinnable through no
                        // fault of the learner's.
                        goal = maxOf(today.drillDone,
                            minOf(today.drillDone + dueSentences, goals.sentences)),
                        onClick = onSentences,
                        modifier = Modifier.weight(1f),
                    )
                }
                if (goals.words > 0) {
                    ChallengeTile(
                        icon = Icons.Filled.CheckCircle,
                        title = stringResource(R.string.words),
                        done = today.wordDone,
                        goal = maxOf(today.wordDone, minOf(today.wordDone + dueWords, goals.words)),
                        onClick = onWords,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (goals.expressions > 0) {
                    ChallengeTile(
                        icon = Icons.Filled.CheckCircle,
                        title = stringResource(R.string.expressions),
                        done = today.expressionDone,
                        goal = maxOf(today.expressionDone,
                            minOf(today.expressionDone + dueExpressions, goals.expressions)),
                        onClick = onExpressions,
                        modifier = Modifier.weight(1f),
                    )
                }
                if (goals.shadows > 0) {
                    ChallengeTile(
                        icon = Icons.Filled.CheckCircle,
                        title = stringResource(R.string.shadowing),
                        done = today.shadowDone,
                        goal = goals.shadows,
                        onClick = onShadowing,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

/**
 * One challenge. The fraction above already carries the number, so the bar
 * only has to be glanceable — it is slim by design.
 */
@Composable
private fun ChallengeTile(
    icon: ImageVector,
    title: String,
    done: Int,
    goal: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val complete = done >= goal && goal > 0
    val green = Color(0xFF34C759)
    Column(
        modifier
            .background(AppSurfaces.ground, RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(14.dp),
                tint = if (complete) green else MaterialTheme.colorScheme.primary)
            Text(title, style = MaterialTheme.typography.labelMedium, maxLines = 1,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("$done/$goal", style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            if (complete) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null,
                    tint = green, modifier = Modifier.size(14.dp))
            }
        }
        LinearProgressIndicator(
            progress = { if (goal <= 0) 0f else (done.coerceAtMost(goal) / goal.toFloat()) },
            color = if (complete) green else MaterialTheme.colorScheme.primary,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * One activity's in-progress shelf: a header naming it (tap to jump to the
 * full shelf) over a horizontally scrolling row of books. The row is wide
 * enough that a second card and the edge of a third show, so it reads as
 * scrollable without an affordance.
 */
@Composable
fun <T> BookRow(
    title: String,
    count: Int,
    items: List<T>,
    onOpenShelf: () -> Unit,
    card: @Composable (T) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onOpenShelf),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text("$count", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(items.size) { i ->
                Column(Modifier.width(ROW_CARD_WIDTH)) { card(items[i]) }
            }
        }
    }
}

private val ROW_CARD_WIDTH = 190.dp

@Composable
private fun stringResource(id: Int) = androidx.compose.ui.res.stringResource(id)
