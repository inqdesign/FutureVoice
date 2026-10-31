package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.CoPresent
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.UpcomingGoal
import com.roro.futurevoice.data.UpcomingGoalStore
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.IosMenu
import com.roro.futurevoice.ui.brand.IosMenuItem
import com.roro.futurevoice.ui.brand.IosSwitch
import com.roro.futurevoice.ui.brand.iosFill
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

// The learner's upcoming goals (iOS `UpcomingGoalViews.swift`): one row, the
// editor, and the goal's own page.

/** iOS `UpcomingGoal.Kind.symbol`. */
fun UpcomingGoal.Kind.icon(): ImageVector = when (this) {
    UpcomingGoal.Kind.INTERVIEW -> Icons.Filled.Badge
    UpcomingGoal.Kind.EXAM -> Icons.Filled.Checklist
    UpcomingGoal.Kind.PRESENTATION -> Icons.Filled.CoPresent
    UpcomingGoal.Kind.MOVE -> Icons.Filled.Home
    UpcomingGoal.Kind.TRIP -> Icons.Filled.Flight
    UpcomingGoal.Kind.OTHER -> Icons.Filled.Star
}

fun UpcomingGoal.Kind.color(): Color = Color(tint)

/** A date as iOS's `.formatted(date: .abbreviated, time: .omitted)` in the
 *  app language ("Nov 14, 2026" / "2026년 11월 14일"). */
@Composable
fun abbreviatedDate(millis: Long): String {
    val locale = LocalConfiguration.current.locales[0]
    return java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM, locale).format(java.util.Date(millis))
}

/**
 * One upcoming goal as a row (iOS `UpcomingGoalRow`): its kind's glyph, the
 * title, where and when, and the countdown at the trailing edge.
 */
@Composable
fun UpcomingGoalRow(goal: UpcomingGoal, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val tint = goal.kind.color()
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(30.dp).background(tint, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
            Icon(goal.kind.icon(), contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // Wraps rather than truncates: the tutor's rows are narrow.
            Text(goal.title.ifEmpty { stringResource(goal.kind.label) }, style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface)
            val detail = listOfNotNull(goal.place.ifEmpty { null }, goal.date?.let { abbreviatedDate(it) })
                .joinToString(" · ")
            if (detail.isNotEmpty()) {
                Text(detail, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        goal.countdown(context)?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Default,
                fontFeatureSettings = "tnum"), fontWeight = FontWeight.SemiBold, color = tint)
        }
    }
}

/**
 * Me → Profile's "Coming up" (iOS `MyProfileView.upcomingSection`): what the
 * learner is preparing for, each row opening its editor, and Add a goal.
 */
@Composable
fun UpcomingGoalsSection(targetLanguage: String) {
    val context = LocalContext.current
    var editing by remember { mutableStateOf<UpcomingGoal?>(null) }
    var adding by remember { mutableStateOf(false) }
    val goals = remember(UpcomingGoalStore.goals, targetLanguage) {
        UpcomingGoalStore.active(context, targetLanguage)
    }
    GroupedSectionHeader(stringResource(R.string.coming_up))
    GroupedCard {
        goals.forEach { goal ->
            UpcomingGoalRow(goal, Modifier.fillMaxWidth().clickable { editing = goal }
                .padding(horizontal = 16.dp, vertical = 10.dp))
            GroupedRowDivider(inset = false)
        }
        Text(stringResource(R.string.add_a_goal), style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.fillMaxWidth().clickable { adding = true }.padding(horizontal = 16.dp, vertical = 12.dp))
    }
    GroupedFooter(stringResource(R.string.an_exam_an_interview_a_move_your_tutor_prepares_you_for_it))
    editing?.let { g -> UpcomingGoalEditor(goal = g, language = targetLanguage, onDismiss = { editing = null }) }
    if (adding) UpcomingGoalEditor(goal = null, language = targetLanguage, onDismiss = { adding = false })
}

/** Add or change one upcoming goal (iOS `UpcomingGoalEditor`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpcomingGoalEditor(goal: UpcomingGoal?, language: String, onDismiss: () -> Unit,
                       onSaved: (UpcomingGoal?) -> Unit = {}) {
    val context = LocalContext.current
    val isNew = goal == null
    val start = remember { goal ?: UpcomingGoal(kind = UpcomingGoal.Kind.INTERVIEW, title = "", language = language) }
    var draft by remember { mutableStateOf(start) }
    var hasDate by remember { mutableStateOf(start.date != null) }
    /** A date picked once survives the toggle being flipped off and on. */
    var pickedDate by remember {
        mutableStateOf(start.date ?: StudyPlan.addDays(StudyPlan.startOfDay(System.currentTimeMillis()), 14))
    }
    var kindMenu by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }

    fun save() {
        val g = draft.copy(
            title = draft.title.trim(), place = draft.place.trim(), notes = draft.notes.trim(),
            date = if (hasDate) StudyPlan.startOfDay(pickedDate) else null,
        )
        UpcomingGoalStore.save(context, g)
        onSaved(UpcomingGoalStore.goal(context, g.id))
        onDismiss()
    }

    com.roro.futurevoice.ui.speech.SpeechSheet(onDismiss) {
        SheetHeader(stringResource(if (isNew) R.string.new_goal else R.string.goal),
            leading = { IosGlassTextButton(stringResource(R.string.cancel), onClick = onDismiss) },
            trailing = {
                IosGlassTextButton(stringResource(R.string.save), onClick = { save() }, bold = true,
                    enabled = draft.title.isNotBlank())
            })
        FormSection(null) {
            Box {
                Row(Modifier.fillMaxWidth().clickable { kindMenu = true }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.what_is_it), style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f))
                    Text(stringResource(draft.kind.label), style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Icon(Icons.Filled.UnfoldMore, contentDescription = null, modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IosMenu(kindMenu, { kindMenu = false }) {
                    UpcomingGoal.Kind.entries.forEach { kind ->
                        IosMenuItem(stringResource(kind.label), onClick = {
                            kindMenu = false
                            draft = draft.copy(kind = kind)
                        }, checked = draft.kind == kind, icon = kind.icon())
                    }
                }
            }
            FormDivider()
            FormTextRow(draft.title, { draft = draft.copy(title = it) }, stringResource(draft.kind.titlePrompt),
                maxLines = 6)
        }
        FormSection(null) {
            Row(Modifier.fillMaxWidth().clickable { hasDate = !hasDate }.padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.it_has_a_date), style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f))
                IosSwitch(hasDate, onCheckedChange = null)
            }
            if (hasDate) {
                FormDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.date), style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f))
                    CompactDatePicker(pickedDate) { pickedDate = it }
                }
            }
            FormDivider()
            FormTextRow(draft.place, { draft = draft.copy(place = it) }, stringResource(draft.kind.placePrompt))
        }
        FormSection(stringResource(R.string.notes),
            footer = stringResource(R.string.your_tutor_prepares_you_for_this_the_more_it_knows_the_close_b3fbe1)) {
            FormTextRow(draft.notes, { draft = draft.copy(notes = it) },
                stringResource(R.string.the_role_the_score_you_need_who_will_be_there), minLines = 3, maxLines = 8)
        }
        if (!isNew) {
            FormSection(null) {
                Text(stringResource(R.string.delete_goal), style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.fillMaxWidth().clickable { confirmingDelete = true }
                        .padding(horizontal = 16.dp, vertical = 12.dp))
            }
        }
    }
    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text(stringResource(R.string.delete_this_goal)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingDelete = false
                    UpcomingGoalStore.delete(context, draft.id)
                    onSaved(null)
                    onDismiss()
                }) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDelete = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

/**
 * iOS `DatePicker(.date)` in a Form (compact style): the date in a grey
 * rounded capsule; tapping it opens the calendar in a popover hanging off the
 * capsule. Days before today can't be picked (iOS `in: today...`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CompactDatePicker(millis: Long, onChange: (Long) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    Box {
        Text(abbreviatedDate(millis),
            Modifier.background(iosFill(), RoundedCornerShape(8.dp)).clickable { open = true }
                .padding(horizontal = 11.dp, vertical = 6.dp),
            style = MaterialTheme.typography.bodyLarge,
            color = if (open) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
        IosMenu(open, { open = false }, fixedWidth = 360.dp) {
            val utc = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
                .atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
            val state = rememberDatePickerState(initialSelectedDateMillis = utc,
                selectableDates = object : SelectableDates {
                    override fun isSelectableDate(utcTimeMillis: Long): Boolean =
                        !Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().isBefore(today)
                    override fun isSelectableYear(year: Int): Boolean = year >= today.year
                })
            LaunchedEffect(state.selectedDateMillis) {
                val picked = state.selectedDateMillis ?: return@LaunchedEffect
                if (picked == utc) return@LaunchedEffect
                val day = Instant.ofEpochMilli(picked).atZone(ZoneOffset.UTC).toLocalDate()
                onChange(day.atStartOfDay(zone).toInstant().toEpochMilli())
                open = false
            }
            DatePicker(state, title = null, headline = null, showModeToggle = false,
                colors = DatePickerDefaults.colors(containerColor = Color.Transparent))
        }
    }
}
