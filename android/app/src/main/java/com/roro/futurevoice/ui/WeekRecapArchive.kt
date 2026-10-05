package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.fillMaxHeight
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.core.UILanguage
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.WeekInProgress
import com.roro.futurevoice.data.WeekRecap
import com.roro.futurevoice.data.WeekRecapBuilder
import com.roro.futurevoice.data.WeekRecapStore
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * "Your week" from the Practice row (iOS `WeekRecapArchiveView`, 2026-10-03):
 * the week still running, whose deck isn't ready until it closes, and every
 * closed week's deck behind it, newest first.
 *
 * A deck slides up by itself once, when its week closes (`WeekRecapHost`);
 * after that this list is the only way back to it. A closed week is never
 * rebuilt here — what was frozen is what is shown.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeekRecapArchiveSheet(level: CefrLevel, onDismiss: (WeekRecapAction?) -> Unit) {
    val context = LocalContext.current
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    var thisWeek by remember { mutableStateOf<WeekInProgress?>(null) }
    var weeks by remember { mutableStateOf<List<WeekRecap>>(emptyList()) }
    var open by remember { mutableStateOf<WeekRecap?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    val locale = weekLocale(context)

    LaunchedEffect(reload) {
        WeekRecapStore.lastWeek(context)           // freezes the closed week
        thisWeek = WeekRecapBuilder.thisWeek(context)
        weeks = WeekRecapStore.archive(context)
    }
    fun close(action: WeekRecapAction?) {
        scope.launch { sheet.hide() }.invokeOnCompletion { onDismiss(action) }
    }

    ModalBottomSheet(onDismissRequest = { onDismiss(null) }, sheetState = sheet,
        containerColor = AppSurfaces.ground) {
        // iOS: a plain `.sheet` — the large detent, full height however short
        // the list. Sized to content, two rows read as a half sheet.
        Column(Modifier.fillMaxWidth().fillMaxHeight().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            SheetHeader(stringResource(R.string.wr_your_week),
                trailing = { com.roro.futurevoice.ui.brand.IosGlassTextButton(
                    stringResource(R.string.done), { close(null) }, bold = true) })
            thisWeek?.let { week ->
                FormSection(header = stringResource(R.string.wr_in_progress)) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Filled.HourglassEmpty, contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(22.dp))
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.wr_ready_on, weekReadyDate(week.readyAt, locale)),
                                style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                            Text(pluralStringResource(R.plurals.wr_days_min_of_talk, week.daysActive,
                                week.daysActive, week.talkMinutes),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            FormSection(header = stringResource(R.string.wr_past_weeks)) {
                if (weeks.isEmpty()) {
                    Text(stringResource(R.string.wr_first_week_arrives),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
                }
                weeks.forEachIndexed { i, recap ->
                    if (i > 0) FormDivider(inset = 56.dp)
                    PastWeekRow(recap, isNew = !WeekRecapStore.wasShown(context, recap), locale) { open = recap }
                }
            }
        }
    }

    open?.let { shown ->
        WeekRecapSheet(shown, level) { action ->
            open = null
            reload++
            // A deck's last card chose something: it runs once this sheet is
            // gone too, so nothing opens underneath a closing sheet.
            if (action != null) close(action)
        }
    }
}

@Composable
private fun PastWeekRow(recap: WeekRecap, isNew: Boolean, locale: Locale, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.Filled.ViewAgenda, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f)) {
            Text(weekRange(recap, locale), style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium)
            Text(pluralStringResource(R.plurals.wr_days_min_of_talk, recap.daysActive,
                recap.daysActive, recap.talkMinutes),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        // The closed week whose deck hasn't been opened yet.
        if (isNew) {
            Text(stringResource(R.string.wr_new_badge), style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(2.dp))
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
    }
}

// MARK: - Text

/** The APP language, not the phone's. */
internal fun weekLocale(c: Context): Locale = Locale.forLanguageTag(UILanguage.current(c) ?: "en")

private fun pattern(locale: Locale, skeleton: String): DateTimeFormatter =
    DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(locale, skeleton), locale)

/** "Sat, Oct 10" — a DATE, not just a weekday: on the opening day itself
 *  "Sat" can't say whether it means today or a week from now. */
internal fun weekReadyDate(at: Long, locale: Locale): String =
    pattern(locale, "EEEMMMd").format(Instant.ofEpochMilli(at).atZone(ZoneId.systemDefault()))

/** "Sep 26 – Oct 2": seven days, so it doesn't share a day with the next
 *  week's label (the opening day belongs to the week it starts). */
internal fun weekRange(r: WeekRecap, locale: Locale): String {
    val f = pattern(locale, "MMMd")
    val zone = ZoneId.systemDefault()
    return "${f.format(Instant.ofEpochMilli(r.start).atZone(zone))} – " +
        f.format(Instant.ofEpochMilli(r.end - 86_400_000L).atZone(zone))
}
