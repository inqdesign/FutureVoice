package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R

/**
 * The trophy shelf: books where every single word and line is mastered, Talk
 * and Watch together, archived or not.
 *
 * Archiving is tidying; THIS is the achievement. The app already computed
 * mastery per book and then hid it inside a per-shelf archive list, so the
 * one thing worth being proud of had nowhere to be seen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FinishedBooksSheet(books: List<FinishedBook>, onOpen: (FinishedBook) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(R.string.finished), style = MaterialTheme.typography.titleLarge)
            if (books.isEmpty()) {
                Text(stringResource(R.string.nothing_finished_yet),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 12.dp))
            } else {
                Text(stringResource(R.string.lld_words_and_lines_mastered_inside_them,
                    books.sumOf { it.itemCount }),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 6.dp))
                GroupedCard {
                    books.forEachIndexed { i, book ->
                        if (i > 0) GroupedRowDivider(inset = false)
                        Row(Modifier.fillMaxWidth().clickable { onOpen(book) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(book.icon, contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                            Column(Modifier.weight(1f)) {
                                Text(book.title, style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Medium, maxLines = 2)
                                Text("${book.subtitle} · " + stringResource(
                                    R.string.lld_of_lld_mastered, book.itemCount, book.itemCount),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Icon(Icons.Filled.WorkspacePremium, contentDescription = null,
                                tint = Color(0xFF34C759), modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            GroupedFooter(stringResource(R.string.a_book_lands_here_once_every_word_and_line_in_it_is_mastered_d3fa9a))
        }
    }
}

/** A finished book, prepared by Practice so this sheet never has to know how
 *  Talk and Watch books compute mastery. */
data class FinishedBook(
    val id: String,
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val itemCount: Int,
    val isTalk: Boolean,
)
