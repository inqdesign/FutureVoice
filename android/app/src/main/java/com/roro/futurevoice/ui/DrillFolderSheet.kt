package com.roro.futurevoice.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.ui.brand.DrillBin

/**
 * What is inside a folder, and the way back out of it.
 *
 * A folder is a WINDOW on the return time, not a record of which button was
 * last pressed — so a card can be re-filed from here, and the menu that does
 * it is the tray's full set of verdicts minus the one the card already has.
 * "Got it" is the exception: it ERASES the return date rather than writing
 * one, so it never appears as a no-op on a card that already has it.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun DrillFolderSheet(
    bin: DrillBin,
    cards: List<DrillCard>,
    onRefile: (DrillCard, DrillBin) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()
            .padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(bin.folderTitleRes), style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 6.dp))
            if (cards.isEmpty()) {
                Text(stringResource(R.string.nothing_waiting_here),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                return@Column
            }
            LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(cards.size) { i ->
                    val card = cards[i]
                    var menu by remember(card.id) { mutableStateOf(false) }
                    Column(Modifier.fillMaxWidth()
                        .combinedClickable(onClick = { menu = true }, onLongClick = { menu = true })
                        .padding(vertical = 10.dp)) {
                        Text(card.targetPhrase, style = MaterialTheme.typography.bodyMedium, maxLines = 2)
                        Text(returnLabel(card.nextReviewAt),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            DrillBin.entries.filterNot { it == bin && it == DrillBin.GOT_IT }.forEach { target ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(target.titleRes)) },
                                    leadingIcon = {
                                        if (target == bin) {
                                            Icon(Icons.Filled.Check, contentDescription = null,
                                                tint = MaterialTheme.colorScheme.primary)
                                        }
                                    },
                                    onClick = { menu = false; onRefile(card, target) })
                            }
                        }
                    }
                }
            }
            // An affordance nothing points at is the same dead end as not
            // having one.
            GroupedFooter(stringResource(R.string.touch_and_hold_to_file_it_again))
        }
    }
}

/** When it comes back, said the way a phone says it ("in 3 days"). The
 *  system formatter follows the default locale, which the app language sets. */
@Composable
private fun returnLabel(at: Long): String = stringResource(
    R.string.back_2fe063,
    android.text.format.DateUtils.getRelativeTimeSpanString(
        at, System.currentTimeMillis(), android.text.format.DateUtils.MINUTE_IN_MILLIS).toString())
