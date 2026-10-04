package com.roro.futurevoice.ui

import androidx.compose.runtime.remember
import androidx.compose.ui.layout.layout
import com.roro.futurevoice.ui.brand.ContinuousShape
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
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.horizontalScroll
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
    /** Books taken all the way to mastered — a chip of its own since iOS
     *  `790099d` (it was the header's seal and a page behind it). */
    FINISHED(R.string.finished),
}

@Composable
fun ShelfChips(selected: Shelf, counts: (Shelf) -> Int?, onSelect: (Shelf) -> Unit) {
    // Scrolls sideways: four chips with counts don't fit a narrow phone in
    // every language (iOS's chip bar is a horizontal ScrollView too).
    Row(Modifier.horizontalScroll(androidx.compose.foundation.rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Shelf.entries.forEach { s ->
            // Neutral for every shelf (iOS `912d6f4`): the page keeps colour
            // for its progress bars alone.
            com.roro.futurevoice.ui.brand.IosChip(
                label = stringResource(s.labelRes),
                count = counts(s),
                selected = s == selected,
                onClick = { onSelect(s) })
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
            // iOS: the count at the TITLE's size, regular weight, in grey —
            // one line read as "Talk 102", not a title with a footnote.
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text("$count", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Normal,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                modifier = Modifier.size(22.dp),
                tint = MaterialTheme.colorScheme.outline)
        }
        // The row runs to the SCREEN's edges (iOS): the page's 20 dp gutter is
        // given back as content padding, so the first card still lines up
        // with the header and the next one slides out from under the edge.
        LazyRow(
            Modifier.layout { m, c ->
                val extra = (PAGE_GUTTER * 2).roundToPx()
                val p = m.measure(c.copy(minWidth = c.minWidth + extra, maxWidth = c.maxWidth + extra))
                layout(p.width - extra, p.height) { p.place(-extra / 2, 0) }
            },
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = PAGE_GUTTER),
            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(items.size) { i ->
                Column(Modifier.width(ROW_CARD_WIDTH)) { card(items[i]) }
            }
        }
    }
}

/**
 * A shelf's books two to a row (iOS `LazyVGrid`, two flexible columns, 14 pt
 * apart). Both cards in a row end on the same line; [card] gets the modifier
 * that makes it fill its cell.
 */
@Composable
fun <T> BookGrid(items: List<T>, card: @Composable (T, Modifier) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        items.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                row.forEach { item ->
                    Box(Modifier.weight(1f).fillMaxHeight()) { card(item, Modifier.fillMaxHeight()) }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

private val ROW_CARD_WIDTH = 190.dp

/** The home shell's horizontal page padding, which [BookRow] bleeds past. */
private val PAGE_GUTTER = 20.dp

@Composable
private fun stringResource(id: Int) = androidx.compose.ui.res.stringResource(id)

/**
 * The app's one chip: a black capsule when it is where you are, a quiet white
 * one when it isn't (iOS). Material's tinted fill reads as "highlighted",
 * which is a different claim.
 */
@Composable
fun PillChip(label: String, selected: Boolean, count: Int? = null, onClick: () -> Unit) =
    com.roro.futurevoice.ui.brand.IosChip(label, selected, count, onClick = onClick)
