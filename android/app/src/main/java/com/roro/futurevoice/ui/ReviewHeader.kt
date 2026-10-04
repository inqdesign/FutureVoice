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
import androidx.compose.material.icons.outlined.EventAvailable
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
import com.roro.futurevoice.data.WeeklyTestSchedule
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.data.WeeklyTestStore
import com.roro.futurevoice.ui.brand.IosGlassButton

/**
 * The Review page's HEADER (iOS `weekToolbar`, 2026-10-03, user decision): the
 * week's things live here — they are the week's, not today's, and the page
 * below is the books. Icons with a dot, never numbers: put off (a stack of
 * cards, orange dot when something is due), the week's report (calendar, dot
 * while a closed week hasn't been opened), the monthly test while it is open,
 * and the weekly test as its host's face, apart at the far right.
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
    var weekly by remember { mutableStateOf<WeeklyTestSchedule.State>(WeeklyTestSchedule.State.Ready) }
    var monthly by remember { mutableStateOf<WeeklyTestSchedule.MonthlyState>(WeeklyTestSchedule.MonthlyState.None) }
    var dueBack by remember { mutableIntStateOf(0) }
    var week by remember { mutableStateOf<WeekInProgress?>(null) }
    var hasPastWeeks by remember { mutableStateOf(false) }
    var hasUnseenWeek by remember { mutableStateOf(false) }
    /** false = weekly, true = monthly. */
    var openTest by remember { mutableStateOf<Boolean?>(null) }
    var showingArchive by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }

    LaunchedEffect(language, revision, settingsRevision, reload) {
        val tests = WeeklyTestStore.shared(context).load(language)
        val schedule = WeeklyTestSettings.schedule(context)
        weekly = schedule.state(tests, { WeeklyTestSettings.isThin(context, it) })
        monthly = schedule.monthlyState(tests)
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
        if (testInbox) { WeeklyTestInbox.pending.value = false; openTest = false }
    }
    // A notice tapped for a week already seen lands here.
    LaunchedEffect(archiveAsked) {
        if (archiveAsked) { WeekRecapInbox.archive.value = false; showingArchive = true }
    }

    val weeklyNeedsYou = weekly is WeeklyTestSchedule.State.Ready || weekly is WeeklyTestSchedule.State.InProgress
    val monthlyOpen = monthly is WeeklyTestSchedule.MonthlyState.Ready ||
        monthly is WeeklyTestSchedule.MonthlyState.InProgress
    val w = week
    val showsWeekArchive = w != null && (w.hasActivity || hasPastWeeks)
    val accent = MaterialTheme.colorScheme.primary

    Row(Modifier.padding(end = 12.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        // The two lists and the month's paper share one glass capsule; the
        // test sits apart — a different kind of thing.
        GlassCapsule {
            HeaderIcon(Icons.Outlined.Layers, stringResource(R.string.back_from_earlier),
                dot = if (dueBack > 0) Color(0xFFFF9500) else null, onClick = onOpenPutOff)
            if (showsWeekArchive) {
                HeaderIcon(Icons.Outlined.CalendarMonth, stringResource(R.string.wr_your_week),
                    dot = if (hasUnseenWeek) accent else null) { showingArchive = true }
            }
            if (monthlyOpen) {
                HeaderIcon(Icons.Outlined.EventAvailable, stringResource(R.string.monthly_test),
                    dot = accent) { openTest = true }
            }
        }
        // The weekly test is its host's face — the same eyes the test itself
        // is run by, so the door looks like who is behind it.
        val testLabel = stringResource(R.string.weekly_test)
        Box(
            Modifier.size(44.dp)
                .semantics { contentDescription = testLabel },
            contentAlignment = Alignment.Center,
        ) {
            IosGlassButton(onClick = { openTest = false }, circle = true) {
                WeeklyTestCharacter(WeeklyTestHost.Mood.WAITING, 0L, Modifier.size(32.dp),
                    tile = com.roro.futurevoice.ui.brand.iosFill())
            }
            if (weeklyNeedsYou) Dot(accent, Modifier.align(Alignment.TopEnd).offset(x = (-4).dp, y = 4.dp))
        }
    }

    val which = openTest
    if (which != null) {
        Dialog(
            onDismissRequest = { openTest = null; reload++ },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            WeeklyTestScreen(language = language, level = level, monthly = which,
                onClose = { openTest = null; reload++; StoreEvents.bump() })
        }
    }
    if (showingArchive) {
        WeekRecapArchiveSheet(level) { action ->
            showingArchive = false
            reload++
            action?.let(::performWeekRecapAction)
        }
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
private fun GlassCapsule(content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
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
