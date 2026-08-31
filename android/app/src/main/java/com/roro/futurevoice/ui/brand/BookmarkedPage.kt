package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

/** One ribbon bookmark — id, icon, and the progress it carries. */
data class BookmarkTab<ID>(
    val id: ID,
    val icon: ImageVector,
    val title: String,
    val done: Int? = null,
    val total: Int? = null,
    val count: Int? = null,
)

/**
 * A full-height book page with ribbon bookmarks fixed on its edge — shared
 * by both book detail pages so both books read as the same object
 * (`BookmarkPage.swift`).
 *
 * The layout is FIXED: the page fills the space and the ribbons never move;
 * only the page's content scrolls, inside the page. The selected ribbon
 * shares the page's fill and sits flush against its edge, so tab and page
 * read as one sheet of paper — which is why the page is SQUARE at the corner
 * the ribbons attach to. Tapping swaps the content in place; no navigation.
 */
@Composable
fun <ID> BookmarkedPage(
    tabs: List<BookmarkTab<ID>>,
    selection: ID?,
    onSelect: (ID) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Row(modifier.fillMaxSize(), verticalAlignment = Alignment.Top) {
        Column(
            Modifier.width(44.dp).padding(top = 4.dp),
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            tabs.forEach { tab ->
                val selected = tab.id == selection
                Column(
                    Modifier
                        .width(40.dp)
                        .clip(RoundedCornerShape(topStart = 10.dp, bottomStart = 10.dp))
                        .background(AppSurfaces.card.copy(alpha = if (selected) 1f else 0.55f))
                        .clickable { onSelect(tab.id) }
                        .padding(vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(tab.icon, contentDescription = tab.title,
                        tint = if (selected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant)
                    val done = tab.done; val total = tab.total
                    if (done != null && total != null && total > 0) {
                        if (done == total) {
                            Icon(Icons.Filled.Check, contentDescription = null,
                                tint = Books.mastery)
                        } else {
                            Text("$done/$total", style = MaterialTheme.typography.labelSmall,
                                color = if (selected) MaterialTheme.colorScheme.onSurface
                                else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    } else if ((tab.count ?: 0) > 0) {
                        Text("${tab.count}", style = MaterialTheme.typography.labelSmall,
                            color = if (selected) MaterialTheme.colorScheme.onSurface
                            else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        Column(
            Modifier
                .fillMaxSize()
                // Square where the ribbons attach — a rounded corner there
                // would curve away from the first ribbon and break the
                // tab-and-page-are-one-paper illusion.
                .clip(RoundedCornerShape(topStart = 0.dp, topEnd = 16.dp,
                    bottomEnd = 16.dp, bottomStart = 16.dp))
                .background(AppSurfaces.card)
                .verticalScroll(rememberScrollState())
                .padding(bottom = 14.dp),
        ) { content() }
    }
}
