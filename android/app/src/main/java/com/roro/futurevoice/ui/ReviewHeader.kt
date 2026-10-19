package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.border
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.luminance
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.WeekInProgress
import com.roro.futurevoice.data.WeekRecapBuilder
import com.roro.futurevoice.data.WeekRecapInbox
import com.roro.futurevoice.data.WeekRecapStore
import com.roro.futurevoice.data.WeeklyTestInbox
import com.roro.futurevoice.data.WeeklyTestReminder
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.ui.brand.IosGlassButton

/**
 * The Review page's HEADER (iOS `weekToolbar`, 2026-10-03, user decision): the
 * week's things live here — they are the week's, not today's, and the page
 * below is the books. Icons with a dot, never numbers: put off (a stack of
 * cards, orange dot when something is due), the week's report (calendar, dot
 * while a closed week hasn't been opened). The weekly test's door left the
 * header (iOS 2026-10-16) and the Studying page's banner went too (iOS
 * 4f706d92): the test lives inside the week's report deck; the reminder's
 * tap still opens it here.
 * There is no monthly test (iOS 70dd26a9): a month's misses come back in the
 * weekly paper.
 *
 * It owns the screens those open (the test, the archive), and the two inboxes
 * that route to them — the weekly reminder's tap and a notice tapped for a
 * week already seen — which used to live on the Today card this replaced.
 */
@Composable
fun ReviewHeaderActions(language: String, level: CefrLevel, onOpenPutOff: () -> Unit) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val settingsRevision by WeeklyTestSettings.revision.collectAsStateWithLifecycle()
    val testInbox by WeeklyTestInbox.pending.collectAsStateWithLifecycle()
    val archiveAsked by WeekRecapInbox.archive.collectAsStateWithLifecycle()
    var dueBack by remember { mutableIntStateOf(0) }
    var week by remember { mutableStateOf<WeekInProgress?>(null) }
    var hasPastWeeks by remember { mutableStateOf(false) }
    var hasUnseenWeek by remember { mutableStateOf(false) }
    var openTest by remember { mutableStateOf(false) }
    var showingArchive by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }

    LaunchedEffect(language, revision, settingsRevision, reload) {
        // Alarms don't survive a reboot; the tab re-arms the next opening.
        WeeklyTestReminder.reschedule(context)
        dueBack = putOffDueCount(context, language)
        WeekRecapStore.lastWeek(context)        // freezes the closed week
        week = WeekRecapBuilder.thisWeek(context)
        val past = WeekRecapStore.archive(context)
        hasPastWeeks = past.isNotEmpty()
        hasUnseenWeek = past.any { it.hasActivity && !WeekRecapStore.wasShown(context, it) }
    }
    // `futurevoice://weeklytest` (the reminder's tap) lands here.
    LaunchedEffect(testInbox) {
        if (testInbox) { WeeklyTestInbox.pending.value = false; openTest = true }
    }
    // A notice tapped for a week already seen lands here.
    LaunchedEffect(archiveAsked) {
        if (archiveAsked) { WeekRecapInbox.archive.value = false; showingArchive = true }
    }

    val w = week
    val showsWeekArchive = w != null && (w.hasActivity || hasPastWeeks)
    val accent = MaterialTheme.colorScheme.primary

    Row(Modifier.padding(end = 12.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        // The two lists share one glass capsule.
        GlassCapsule {
            HeaderIcon(Icons.Outlined.Layers, stringResource(R.string.back_from_earlier),
                dot = if (dueBack > 0) Color(0xFFFF9500) else null, onClick = onOpenPutOff)
            if (showsWeekArchive) {
                HeaderIcon(Icons.Outlined.CalendarMonth, stringResource(R.string.wr_your_week),
                    dot = if (hasUnseenWeek) accent else null) { showingArchive = true }
            }
        }
    }

    if (openTest) {
        WeeklyTestDialog(language, level) { openTest = false; reload++ }
    }
    if (showingArchive) {
        WeekRecapArchiveSheet(level) { action ->
            showingArchive = false
            reload++
            action?.let(::performWeekRecapAction)
        }
    }
}

/** The weekly test, full screen over the tab — opened by the Studying page's
 *  banner and by the reminder's tap. */
@Composable
internal fun WeeklyTestDialog(language: String, level: CefrLevel, onClose: () -> Unit) {
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        DialogSystemBarsLikeActivity()
        WeeklyTestScreen(language = language, level = level,
            onClose = { onClose(); StoreEvents.bump() })
    }
}

@Composable
private fun HeaderIcon(icon: ImageVector, label: String, dot: Color?, onClick: () -> Unit) {
    androidx.compose.material3.IconButton(onClick = onClick, modifier = Modifier.size(40.dp)) {
        Box {
            Icon(icon, contentDescription = label, tint = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(22.dp))
            if (dot != null) Dot(dot, Modifier.align(Alignment.TopEnd).offset(x = 3.dp, y = (-2).dp))
        }
    }
}

@Composable
private fun Dot(color: Color, modifier: Modifier = Modifier) {
    Box(modifier.size(7.dp).background(color, CircleShape))
}

/** The glass capsule of [IosGlassButton], holding its own buttons — iOS
 *  groups a toolbar's icons in ONE glass shape. */
@Composable
internal fun GlassCapsule(content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    Row(
        Modifier
            .height(44.dp)
            .shadow(if (dark) 0.dp else 12.dp, CircleShape,
                ambientColor = Color.Black.copy(alpha = 0.16f), spotColor = Color.Black.copy(alpha = 0.16f))
            .background(if (dark) Color(0xFF2C2C2E) else Color.White, CircleShape)
            .border(0.5.dp, Color.Black.copy(alpha = if (dark) 0f else 0.06f), CircleShape)
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}
