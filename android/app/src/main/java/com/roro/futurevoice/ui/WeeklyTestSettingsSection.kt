package com.roro.futurevoice.ui

import android.Manifest
import android.app.TimePickerDialog
import android.content.pm.PackageManager
import android.os.Build
import android.text.format.DateFormat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.core.UILanguage
import com.roro.futurevoice.data.WeeklyTestSettings
import java.time.DayOfWeek
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.util.Locale

/**
 * The weekly test's day, time, reminder and sounds — one section in the goals
 * sheet, where the Practice tab's own settings live (iOS
 * `WeeklyTestSettingsSection`). Device-local: two devices must not both ring.
 */
@Composable
fun WeeklyTestSettingsSection() {
    val context = LocalContext.current
    // Redraw on every change the settings object publishes.
    val revision by WeeklyTestSettings.revision.collectAsStateWithLifecycle()
    val weekday = remember(revision) { WeeklyTestSettings.weekday(context) }
    val hour = remember(revision) { WeeklyTestSettings.hour(context) }
    val minute = remember(revision) { WeeklyTestSettings.minute(context) }
    val reminderOn = remember(revision) { WeeklyTestSettings.reminderOn(context) }
    val soundsOn = remember(revision) { WeeklyTestSettings.soundsOn(context) }
    var dayMenu by remember { mutableStateOf(false) }
    // The APP language, not the phone's.
    val locale = Locale.forLanguageTag(UILanguage.current(context) ?: "en")

    fun dayName(w: Int): String =
        (if (w == 1) DayOfWeek.SUNDAY else DayOfWeek.of(w - 1)).getDisplayName(TextStyle.FULL, locale)

    // Turning the reminder on asks for notification permission if needed; a
    // denial leaves the toggle off rather than lying.
    val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        WeeklyTestSettings.setReminderOn(context,
            granted && NotificationManagerCompat.from(context).areNotificationsEnabled())
    }
    fun setReminder(on: Boolean) {
        if (!on) { WeeklyTestSettings.setReminderOn(context, false); return }
        val needsAsk = Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,
            Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        if (needsAsk) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        else WeeklyTestSettings.setReminderOn(context,
            NotificationManagerCompat.from(context).areNotificationsEnabled())
    }

    GroupedSectionHeader(stringResource(R.string.weekly_test))
    GroupedCard {
        // iOS `Picker(.menu)`: the whole row opens it, the menu hangs off the
        // trailing value (the shared iOS menu, never Material's dropdown).
        SettingRow(Icons.Filled.Checklist, stringResource(R.string.test_day),
            Modifier.clickable { dayMenu = true }) {
            Box {
                MePickerValue(dayName(weekday))
                com.roro.futurevoice.ui.brand.IosPickerMenu(
                    expanded = dayMenu, onDismissRequest = { dayMenu = false },
                    options = (1..7).map { it to dayName(it) }, selected = weekday,
                    onPick = { WeeklyTestSettings.setWeekday(context, it) })
            }
        }
        GroupedRowDivider()
        SettingRow(Icons.Filled.Schedule, stringResource(R.string.opens_at), Modifier.clickable {
            TimePickerDialog(context, { _, h, m -> WeeklyTestSettings.setTime(context, h, m) },
                hour, minute, DateFormat.is24HourFormat(context)).show()
        }) {
            Text(LocalTime.of(hour, minute).format(
                DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale)),
                color = MaterialTheme.colorScheme.primary)
        }
        GroupedRowDivider()
        SettingRow(Icons.Filled.Notifications, stringResource(R.string.remind_me)) {
            com.roro.futurevoice.ui.brand.IosSwitch(checked = reminderOn, onCheckedChange = ::setReminder)
        }
        GroupedRowDivider()
        SettingRow(Icons.Filled.VolumeUp, stringResource(R.string.sounds)) {
            com.roro.futurevoice.ui.brand.IosSwitch(checked = soundsOn, onCheckedChange = { WeeklyTestSettings.setSoundsOn(context, it) })
        }
    }
    GroupedFooter(stringResource(
        R.string.one_test_a_week_from_your_talks_words_and_corrections_it_ope_cb8368))
}

@Composable
private fun SettingRow(icon: ImageVector, label: String, modifier: Modifier = Modifier,
                       trailing: @Composable () -> Unit) {
    Row(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        trailing()
    }
}
