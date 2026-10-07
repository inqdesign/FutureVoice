package com.roro.futurevoice.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
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
    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().bottomBarInsets()
            .padding(horizontal = 16.dp).padding(bottom = 28.dp)) {
            // iOS's folder sheet: the folder's name centred, Done on the right.
            androidx.compose.foundation.layout.Box(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
                Text(stringResource(bin.folderTitleRes), style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.align(androidx.compose.ui.Alignment.Center))
                androidx.compose.material3.TextButton(onClick = onDismiss,
                    modifier = Modifier.align(androidx.compose.ui.Alignment.CenterEnd)) {
                    Text(stringResource(R.string.done), style = MaterialTheme.typography.titleMedium)
                }
            }
            if (cards.isEmpty()) {
                Text(stringResource(R.string.nothing_waiting_here),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 4.dp))
                return@Column
            }
            // One inset-grouped card holding the rows, as iOS's List does.
            LazyColumn(Modifier
                .background(com.roro.futurevoice.ui.brand.AppSurfaces.card,
                    com.roro.futurevoice.ui.brand.ContinuousShape(com.roro.futurevoice.ui.brand.IosRadius.groupedCard))) {
                items(cards.size) { i ->
                    val card = cards[i]
                    var menu by remember(card.id) { mutableStateOf(false) }
                    Column(Modifier.fillMaxWidth()
                        .combinedClickable(onClick = { menu = true }, onLongClick = { menu = true })
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(card.targetPhrase, style = MaterialTheme.typography.bodyMedium, maxLines = 2)
                        // Known says it is KNOWN: a retired card has no
                        // return, so a countdown here would announce one the
                        // learner just said they didn't need.
                        Text(if (bin == DrillBin.GOT_IT) stringResource(bin.dropHintRes)
                             else returnLabel(card.nextReviewAt),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            DrillBin.entries.filterNot { it == bin && it == DrillBin.GOT_IT }.forEach { target ->
                                com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                                    text = { Text(stringResource(target.titleRes)) },
                                    leadingIcon = {
                                        if (target == bin) {
                                            Icon(Icons.Filled.Check, contentDescription = null)
                                        }
                                    },
                                    onClick = { menu = false; onRefile(card, target) })
                            }
                        }
                    }
                    if (i < cards.lastIndex) androidx.compose.material3.HorizontalDivider(
                        Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
            // An affordance nothing points at is the same dead end as not
            // having one.
            GroupedFooter(stringResource(R.string.touch_and_hold_to_file_it_again))
        }
    }
}

/** When it comes back, said the way iOS's `.relative(presentation: .named)`
 *  says it — "13시간 후", "내일", "in 3 days". The phrase carries its own
 *  preposition in every language, so it stands alone: wrapped in a "back %s"
 *  shell it doubled ("13시간 후 뒤에 다시"). The system formatter follows the
 *  default locale, which the app language sets. */
@Composable
private fun returnLabel(at: Long): String =
    android.text.format.DateUtils.getRelativeTimeSpanString(
        at, System.currentTimeMillis(), android.text.format.DateUtils.MINUTE_IN_MILLIS).toString()
