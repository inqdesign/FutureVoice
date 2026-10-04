package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleDown
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.BottomSheetDefaults
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AppUpdateService

/**
 * A newer build is out — `UpdateAvailableSheet.swift`.
 *
 * Two temperaments in one sheet, because the two cases are not the same
 * request:
 *
 *   * OPTIONAL — a notice. It can be closed, and it is shown once per build
 *     (`AppUpdateService.dismiss`). Nagging is how a notice stops being read.
 *   * REQUIRED — the server has moved somewhere this build misreports it, so
 *     there is no dismiss, no back press and no drag. That is not a growth
 *     device; it is reserved for the case that actually happened on iOS, when
 *     the billing model changed under builds already on phones and an old
 *     client kept describing allowances that no longer existed.
 *
 * The notes are the release notes shipped to the store, so they are a
 * paragraph plus a bullet list, not a sentence. The body SCROLLS with the
 * buttons pinned below it, and the bullets are parsed out ([ReleaseNotes]) so
 * "what's new" reads as a list of things rather than a wall of prose.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpdateAvailableSheet(
    update: AppUpdateService.AppUpdate,
    onDismiss: () -> Unit,
) {
    val uriHandler = LocalUriHandler.current
    val context = LocalContext.current
    val notes = remember(update.notes) { ReleaseNotes(update.notes) }

    // Both the drag and the back press are shut off from the SAME flag — an
    // `if` around the Later button alone leaves the sheet escapable by
    // swiping it away, which is the one gap that makes "required" a lie.
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { !update.required || it != SheetValue.Hidden },
    )

    ModalBottomSheet(
        onDismissRequest = { if (!update.required) onDismiss() },
        sheetState = sheetState,
        dragHandle = if (update.required) null else ({ BottomSheetDefaults.DragHandle() }),
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = !update.required),
    ) {
        Column(Modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp)
                    .padding(top = 8.dp, bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        if (update.required) Icons.Filled.ErrorOutline else Icons.Filled.ArrowCircleDown,
                        contentDescription = null,
                        tint = if (update.required) MaterialTheme.colorScheme.error
                               else MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(40.dp),
                    )
                    Text(
                        stringResource(
                            if (update.required) R.string.update_to_keep_going
                            else R.string.there_s_a_new_version
                        ),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center,
                    )
                    // Always names the build being offered. "A new version is
                    // available" with no number can't be checked against what
                    // the store then shows.
                    Text(
                        buildLine(update, AppUpdateService.currentBuild(context),
                                  AppUpdateService.currentVersion(context)),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }

                if (!notes.isEmpty) {
                    Column(
                        Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        notes.lead?.let {
                            Text(it,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (notes.bullets.isNotEmpty()) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(
                                    stringResource(R.string.what_s_new).uppercase(),
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                notes.bullets.forEach { line ->
                                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                        Icon(Icons.Filled.Circle, contentDescription = null,
                                            tint = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.padding(top = 7.dp).size(5.dp))
                                        Text(line, style = MaterialTheme.typography.bodyMedium)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Pinned, so the one thing the sheet asks for can never be
            // scrolled off — however long the notes are.
            Column(
                Modifier.fillMaxWidth().bottomBarInsets()
                    .padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                // Names the place the tap will actually open. A test install
                // sent to the store page reads as a broken link, not as an
                // update — the store has no build for them.
                Button(
                    onClick = { uriHandler.openUri(update.url) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(
                        if (update.fromPlay) R.string.open_google_play
                        else R.string.get_the_new_test_build))
                }
                // A required update has no way past. Everything else does.
                if (!update.required) {
                    TextButton(onClick = onDismiss) {
                        Text(stringResource(R.string.later),
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/**
 * Asks once, shows the sheet if there is anything to say, and is otherwise
 * invisible. Hosted next to the root screen rather than inside it so the
 * notice reaches the learner wherever they happen to be, and so it can never
 * be raised behind another sheet.
 *
 * iOS hosts it on the tab root, which also keeps it out of onboarding. Here
 * `RootScreen` is both, so there is no such seam — and it needs none: a Play
 * install that is mid-onboarding was installed minutes ago, so it IS the
 * latest build and there is nothing to say to it. A pre-release install that
 * sees this during setup is a tester, who is exactly who the notice is for.
 */
@Composable
fun UpdateGate() {
    val context = LocalContext.current
    val pending by AppUpdateService.pending.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { AppUpdateService.check(context) }
    pending?.let {
        UpdateAvailableSheet(update = it, onDismiss = { AppUpdateService.dismiss(context) })
    }
}

/** "1.0.0 (3) → 1.0.1 (4)", or just the two build numbers when the server
 *  hasn't named a version. Numbers and an arrow — nothing to translate. */
@Composable
private fun buildLine(
    update: AppUpdateService.AppUpdate,
    currentBuild: Int,
    currentVersion: String,
): String {
    val latest = update.latestVersion
        ?: return stringResource(R.string.build_lld_lld, currentBuild, update.latestBuild)
    return "$currentVersion ($currentBuild) → $latest (${update.latestBuild})"
}

/**
 * Release notes as written for the store: a paragraph, then a dash list.
 * Splitting them lets the sheet lay the list out as rows instead of letting a
 * hyphen wrap into the middle of a centred block.
 */
class ReleaseNotes(raw: String?) {
    val lead: String?
    val bullets: List<String>

    val isEmpty: Boolean get() = lead == null && bullets.isEmpty()

    init {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) {
            lead = null
            bullets = emptyList()
        } else {
            val leadLines = mutableListOf<String>()
            val items = mutableListOf<String>()
            for (line in text.lines()) {
                val trimmed = line.trim()
                if (trimmed.isEmpty()) {
                    // A blank line inside the lead is a paragraph break; keep
                    // it, but never let it open the block with one.
                    if (leadLines.isNotEmpty() && items.isEmpty()) leadLines += ""
                    continue
                }
                val marker = listOf("- ", "• ", "· ", "* ").firstOrNull { trimmed.startsWith(it) }
                when {
                    marker != null -> items += trimmed.removePrefix(marker).trim()
                    items.isEmpty() -> leadLines += trimmed
                    // Prose after the list is a wrapped bullet, not a new section.
                    else -> items[items.lastIndex] = items.last() + " " + trimmed
                }
            }
            lead = leadLines.joinToString("\n").trim().takeIf { it.isNotEmpty() }
            bullets = items
        }
    }
}
