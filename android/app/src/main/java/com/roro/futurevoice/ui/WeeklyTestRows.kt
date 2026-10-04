package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.WeeklyTestInbox
import com.roro.futurevoice.data.WeeklyTestReminder
import com.roro.futurevoice.data.WeeklyTestSchedule
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.data.WeeklyTestStore
import java.time.Instant
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

/**
 * The weekly test's row on the Today card, and the monthly paper's when there
 * is something to collect (iOS `weeklyTestRow` / `monthlyTestRow`). Same row
 * shape as "Back from earlier": what it is, where it stands, one tap in. A
 * finished test shows its score until the next opening, so the week has a
 * place to be looked at. The test itself opens full screen over the tab.
 */
@Composable
fun WeeklyTestRows(language: String, level: CefrLevel) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val settingsRevision by WeeklyTestSettings.revision.collectAsStateWithLifecycle()
    val inbox by WeeklyTestInbox.pending.collectAsStateWithLifecycle()
    var weekly by remember { mutableStateOf<WeeklyTestSchedule.State>(WeeklyTestSchedule.State.Ready) }
    var monthly by remember { mutableStateOf<WeeklyTestSchedule.MonthlyState>(WeeklyTestSchedule.MonthlyState.None) }
    var open by remember { mutableStateOf<Boolean?>(null) }   // false = weekly, true = monthly
    var reload by remember { mutableStateOf(0) }

    LaunchedEffect(language, revision, settingsRevision, reload) {
        val tests = WeeklyTestStore.shared(context).load(language)
        val schedule = WeeklyTestSettings.schedule(context)
        weekly = schedule.state(tests, { WeeklyTestSettings.isThin(context, it) })
        monthly = schedule.monthlyState(tests)
        // Alarms don't survive a reboot; the tab re-arms the next opening.
        WeeklyTestReminder.reschedule(context)
    }
    // `futurevoice://weeklytest` (the reminder's tap) lands here.
    LaunchedEffect(inbox) {
        if (inbox) { WeeklyTestInbox.pending.value = false; open = false }
    }

    val locale = Locale.forLanguageTag(com.roro.futurevoice.core.UILanguage.current(context) ?: "en")
    fun weekday(at: Long, style: TextStyle) =
        Instant.ofEpochMilli(at).atZone(ZoneId.systemDefault()).dayOfWeek.getDisplayName(style, locale)

    val (weeklySubtitle, weeklyTrailing) = when (val w = weekly) {
        WeeklyTestSchedule.State.Ready -> stringResource(R.string.made_from_this_week_s_talks) to null
        is WeeklyTestSchedule.State.InProgress ->
            stringResource(R.string.pick_up_where_you_left_off) to ("${w.test.answers.size}/${w.test.total}" to false)
        is WeeklyTestSchedule.State.Done ->
            stringResource(R.string.next_one, weekday(w.next, TextStyle.FULL)) to ("${w.test.score}/${w.test.total}" to true)
        is WeeklyTestSchedule.State.Thin ->
            stringResource(R.string.a_talk_or_two_first_next, weekday(w.next, TextStyle.SHORT)) to null
    }
    // The week behind, as cards — reachable until the next one turns.
    WeekRecapRow(level, reloadKey = settingsRevision to reload)
    TestRow(Icons.Filled.Checklist, stringResource(R.string.weekly_test), weeklySubtitle, weeklyTrailing) {
        open = false
    }
    if (monthly != WeeklyTestSchedule.MonthlyState.None) {
        val (sub, trailing) = when (val m = monthly) {
            is WeeklyTestSchedule.MonthlyState.InProgress ->
                stringResource(R.string.pick_up_where_you_left_off) to ("${m.test.answers.size}/${m.test.total}" to false)
            is WeeklyTestSchedule.MonthlyState.Done ->
                stringResource(R.string.done_for_this_month) to ("${m.test.score}/${m.test.total}" to true)
            else -> stringResource(R.string.everything_you_missed_this_month) to null
        }
        TestRow(Icons.Filled.EventAvailable, stringResource(R.string.monthly_test), sub, trailing) { open = true }
    }

    val which = open
    if (which != null) {
        Dialog(
            onDismissRequest = { open = null; reload++ },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            WeeklyTestScreen(language = language, level = level, monthly = which,
                onClose = { open = null; reload++; StoreEvents.bump() })
        }
    }
}

/** [trailing]: the figure and whether it is a finished score (tinted). */
@Composable
private fun TestRow(icon: ImageVector, title: String, subtitle: String,
                    trailing: Pair<String, Boolean>?, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        trailing?.let { (text, done) ->
            Text(text, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                color = if (done) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
    }
}
