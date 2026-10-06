package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosButton as Button
import com.roro.futurevoice.ui.brand.IosSwitch
import java.time.DayOfWeek
import java.time.format.TextStyle
import java.time.temporal.WeekFields

/**
 * Onboarding's "once a week" step (iOS `WeeklyRhythmOnboardingView`,
 * 2026-10-03): introduces the week's two things — the week looked back on
 * (`WeekRecap`) and the test made from it (`WeeklyTest`) — and asks WHEN,
 * because both open at the same moment (`WeeklyTestSettings`' weekday +
 * time). Placed right BEFORE the daily call: the week's rhythm first, then
 * the day's.
 *
 * It asks no permission. The reminder toggle only records the wish; the
 * daily-call step that follows asks for notifications and then settles this
 * reminder (`WeeklyTestReminder.settleAfterPermission`), so the learner meets
 * one permission sheet, not two in a row.
 *
 * Shown to new installs only (the root gates it on the daily call not yet
 * onboarded): an existing learner already has a test day.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeeklyRhythmOnboardingScreen(context: Context, onDone: () -> Unit) {
    var weekday by remember { mutableIntStateOf(WeeklyTestSettings.weekday(context)) }
    val time = rememberTimePickerState(initialHour = WeeklyTestSettings.hour(context),
        initialMinute = WeeklyTestSettings.minute(context), is24Hour = true)
    var remind by remember { mutableStateOf(true) }
    val locale = weekLocale(context)
    // The week in the app language, starting where the learner's calendar
    // starts it (Monday in most places, Sunday in the US and Korea).
    val days = remember(locale) {
        val first = WeekFields.of(locale).firstDayOfWeek
        (0L until 7L).map { offset ->
            val day = first.plus(offset)
            // WeeklyTestSettings counts 1 = Sunday … 7 = Saturday (iOS's).
            val id = if (day == DayOfWeek.SUNDAY) 1 else day.value + 1
            id to day.getDisplayName(TextStyle.SHORT_STANDALONE, locale)
        }
    }

    fun save() {
        WeeklyTestSettings.setWeekday(context, weekday)
        WeeklyTestSettings.setTime(context, time.hour, time.minute)
        // A wish until the next screen asks for notifications; settled there.
        WeeklyTestSettings.setReminderOn(context, remind)
        com.roro.futurevoice.core.Analytics.capture("weekly_rhythm_onboarding",
            mapOf("weekday" to weekday, "hour" to time.hour, "remind" to remind))
        OnboardingFlags.markSeen(context, OnboardingFlags.WEEKLY_RHYTHM)
        onDone()
    }

    Column(
        Modifier.fillMaxSize().background(AppSurfaces.ground).systemBarsPadding().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.size(8.dp))
            Icon(Icons.Filled.EventAvailable, contentDescription = null,
                modifier = Modifier.size(52.dp), tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.wrh_title), style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Text(stringResource(R.string.wrh_body), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            Text(stringResource(R.string.wrh_footnote), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline, textAlign = TextAlign.Center)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                days.forEach { (id, label) ->
                    val selected = weekday == id
                    val accent = MaterialTheme.colorScheme.primary
                    Box(Modifier.weight(1f).heightIn(min = 36.dp)
                        .background(if (selected) accent.copy(alpha = 0.15f) else AppSurfaces.card,
                            RoundedCornerShape(50))
                        .border(if (selected) 1.5.dp else 0.dp, if (selected) accent else Color.Transparent,
                            RoundedCornerShape(50))
                        .clickable { weekday = id }, Alignment.Center) {
                        Text(label, maxLines = 1, overflow = TextOverflow.Clip,
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            color = if (selected) accent else MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
            // The wheel speaks for itself — iOS hides its "Opens at" label.
            TimePicker(state = time)
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Filled.NotificationsNone, contentDescription = null, modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.wrh_remind), Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyLarge)
                IosSwitch(checked = remind, onCheckedChange = { remind = it })
            }
        }
        Spacer(Modifier.size(12.dp))
        Button(onClick = ::save, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.wrh_cta))
        }
    }
}
