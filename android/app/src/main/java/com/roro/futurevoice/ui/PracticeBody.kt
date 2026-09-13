package com.roro.futurevoice.ui

import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.IconButton
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
    /** The browser behind the dealt hand — iOS's `all` on the tile. */
    onShadowAll: () -> Unit = {},
    /** The full dictionaries behind the day's hand — iOS's "all" on each tile.
     *  Without them the library is reachable only from a widget. */
    onWordsAll: () -> Unit = {},
    /** Snoozed items whose time has come — what the learner asked to see again. */
    dueBack: Int = 0,
    onDueBack: () -> Unit = {},
    onExpressionsAll: () -> Unit = {},
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
            IconButton(onClick = onEditGoals, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.edit_daily_goals),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            }
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

        // Above the tiles, because it is a promise already made: these came
        // back because the learner put them away for exactly this long.
        if (dueBack > 0) {
            Row(Modifier.fillMaxWidth().clickable(onClick = onDueBack)
                .padding(horizontal = 14.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.History, contentDescription = null,
                    tint = Color(0xFFFF9500), modifier = Modifier.size(20.dp))
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.back_from_earlier),
                        style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                    Text(stringResource(R.string.you_asked_to_see_these_again),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text("$dueBack", style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold, color = Color(0xFFFF9500))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                    tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
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
                        onAll = onWordsAll,
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
                        onAll = onExpressionsAll,
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
                        onAll = onShadowAll,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        // The last seven days: what the streak is actually made of. Drawn only
        // where a day CAN be met — with every goal at zero there is nothing to
        // tick, and a row of empty circles reads as a week of failure.
        if (goals.anyEnabled) {
            val context = LocalContext.current
            val days = remember(goals, today) {
                (6 downTo 0).map { back ->
                    val at = System.currentTimeMillis() - back * 86_400_000L
                    at to GoalStore.met(context, goals, at)
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp)) {
                days.forEachIndexed { i, (at, met) ->
                    val isToday = i == days.lastIndex
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(java.text.SimpleDateFormat("EEEEE", java.util.Locale.getDefault())
                            .format(java.util.Date(at)),
                            style = MaterialTheme.typography.labelSmall,
                            color = if (isToday) MaterialTheme.colorScheme.onSurface
                            else MaterialTheme.colorScheme.onSurfaceVariant)
                        Icon(
                            if (met) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                            contentDescription = null, modifier = Modifier.size(18.dp),
                            tint = when {
                                met -> Color(0xFF34C759)
                                isToday -> MaterialTheme.colorScheme.primary
                                else -> MaterialTheme.colorScheme.outlineVariant
                            })
                    }
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
    /** Opens everything behind the tile, not just today's hand. */
    onAll: (() -> Unit)? = null,
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
        onAll?.let {
            Text(stringResource(R.string.all), style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable(onClick = it).padding(top = 2.dp))
        }
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
