package com.roro.futurevoice.ui

import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.IconButton
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
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
            val on = s == selected
            val n = counts(s)
            Row(
                Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(if (on) MaterialTheme.colorScheme.onSurface
                    else MaterialTheme.colorScheme.surface)
                    .clickable { onSelect(s) }
                    .padding(horizontal = 16.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Text(stringResource(s.labelRes),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = if (on) MaterialTheme.colorScheme.surface
                    else MaterialTheme.colorScheme.onSurface)
                if (n != null) {
                    Text("$n", style = MaterialTheme.typography.labelMedium,
                        color = if (on) MaterialTheme.colorScheme.surface.copy(alpha = 0.7f)
                        else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
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
    /** How many are still to study behind each tile's hand — the footer's
     *  number, and on every tile it means the SAME thing (iOS `allCount`).
     *  Counted by the HOST, which already holds the stores and must count
     *  exactly what the page behind the footer lists; a count invented here
     *  would drift from the page it opens. Null until the host supplies it,
     *  and a null draws the footer with no number rather than a 0 that would
     *  claim the collection is empty. */
    sentencesToStudy: Int? = null,
    wordsToStudy: Int? = null,
    expressionsToStudy: Int? = null,
    shadowToStudy: Int? = null,
    /** The whole sentence deck, not today's cards. Optional because Android
     *  has no sentence library screen yet — with none the tile simply has no
     *  footer, rather than a row that leads nowhere. */
    onSentencesAll: (() -> Unit)? = null,
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
            // Streak first, the goals control last — the control belongs at
            // the card's edge, where every other settings affordance is.
            if (streak > 0) {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Icon(Icons.Filled.LocalFireDepartment, contentDescription = null,
                        tint = Color(0xFFFF9500), modifier = Modifier.size(16.dp))
                    Text("$streak", style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold, color = Color(0xFFFF9500))
                }
            }
            IconButton(onClick = onEditGoals, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.edit_daily_goals),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
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
            // `IntrinsicSize.Min` + `fillMaxHeight` so both tiles in a row end
            // at the same line: a tile with no footer would otherwise sit
            // short beside one that has it, and the grid would read as broken.
            Row(Modifier.height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                // Sentences is the only conditional one: it is a moving target
                // (clear today's deck), and on a day with nothing due and
                // nothing done there is nothing to ask for.
                if (goals.sentences > 0 && (dueSentences > 0 || today.drillDone > 0)) {
                    ChallengeTile(
                        icon = Icons.Filled.ViewAgenda,
                        title = stringResource(R.string.sentences),
                        done = today.drillDone,
                        // Never more than exists to do — asking for 20 when 3
                        // cards are due makes the day unwinnable through no
                        // fault of the learner's.
                        goal = maxOf(today.drillDone,
                            minOf(today.drillDone + dueSentences, goals.sentences)),
                        onClick = onSentences,
                        toStudy = sentencesToStudy,
                        onAll = onSentencesAll,
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                    )
                }
                if (goals.words > 0) {
                    ChallengeTile(
                        icon = Icons.AutoMirrored.Filled.MenuBook,
                        title = stringResource(R.string.words),
                        done = today.wordDone,
                        goal = maxOf(today.wordDone, minOf(today.wordDone + dueWords, goals.words)),
                        onClick = onWords,
                        toStudy = wordsToStudy,
                        onAll = onWordsAll,
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                    )
                }
            }
            Row(Modifier.height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (goals.expressions > 0) {
                    ChallengeTile(
                        icon = Icons.Filled.FormatQuote,
                        title = stringResource(R.string.expressions),
                        done = today.expressionDone,
                        goal = maxOf(today.expressionDone,
                            minOf(today.expressionDone + dueExpressions, goals.expressions)),
                        onClick = onExpressions,
                        toStudy = expressionsToStudy,
                        onAll = onExpressionsAll,
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                    )
                }
                if (goals.shadows > 0) {
                    ChallengeTile(
                        icon = Icons.Filled.GraphicEq,
                        title = stringResource(R.string.shadowing),
                        done = today.shadowDone,
                        goal = goals.shadows,
                        onClick = onShadowing,
                        toStudy = shadowToStudy,
                        onAll = onShadowAll,
                        modifier = Modifier.weight(1f).fillMaxHeight(),
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
 * One category as a TILE: today's ask on top, the whole collection behind it
 * at the bottom, each its own tap target (iOS `challengeTile`).
 *
 * Side by side in one row the two destinations needed an invented split
 * control, and the inventory count ended up louder than the ask. A tile has a
 * second dimension, so the two live in the natural places — what to do now
 * above, what you have below — separated by a hairline.
 */
@Composable
private fun ChallengeTile(
    icon: ImageVector,
    title: String,
    done: Int,
    goal: Int,
    onClick: () -> Unit,
    /** The whole collection behind today's hand. Same meaning on every tile:
     *  how many are still to study. Null = the host hasn't counted it yet. */
    toStudy: Int? = null,
    /** Opens that collection. Null where there is no page to open yet. */
    onAll: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val complete = done >= goal && goal > 0
    val green = Color(0xFF34C759)
    // The GLYPH says which category this is — one generic check on all four
    // made them read as the same thing four times. Only the COLOUR carries
    // state: green once the day's ask is met, the theme accent until then.
    val tint = if (complete) green else MaterialTheme.colorScheme.primary
    Column(
        modifier
            // Clipped before the background so both ripples stay inside the
            // tile's corners.
            .clip(RoundedCornerShape(12.dp))
            .background(AppSurfaces.ground),
    ) {
        Column(
            Modifier.clickable(onClick = onClick)
                .padding(start = 12.dp, end = 12.dp, top = 11.dp, bottom = 9.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(14.dp), tint = tint)
                Text(title, style = MaterialTheme.typography.labelMedium, maxLines = 1,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                // The fraction is the tile's headline — it is what the learner
                // is here to read, so it takes the largest type in the card.
                Text("$done/$goal", style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold)
                if (complete) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null,
                        tint = green, modifier = Modifier.size(15.dp))
                }
            }
            // Slim by design, and plain: the fraction above already carries the
            // number, so the bar only has to be glanceable. Material's stop dot
            // and track gap are a second reading of the same value — dropped,
            // because iOS draws one hairline.
            LinearProgressIndicator(
                progress = { if (goal <= 0) 0f else (done.coerceAtMost(goal) / goal.toFloat()) },
                color = tint,
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
                strokeCap = StrokeCap.Round,
                gapSize = 0.dp,
                drawStopIndicator = {},
                modifier = Modifier.fillMaxWidth().height(3.dp),
            )
        }
        if (onAll != null) {
            // Pushes the footer to the tile's bottom edge when this tile is
            // shorter than the one beside it.
            Spacer(Modifier.weight(1f))
            HorizontalDivider(Modifier.padding(horizontal = 10.dp), thickness = Dp.Hairline,
                color = MaterialTheme.colorScheme.outlineVariant)
            Row(
                Modifier.fillMaxWidth().clickable(onClick = onAll)
                    .padding(horizontal = 12.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(stringResource(R.string.to_study), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.outline)
                if (toStudy != null) {
                    Text("$toStudy", style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = if (toStudy == 0) MaterialTheme.colorScheme.outline
                        else MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                    modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.outline)
            }
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
