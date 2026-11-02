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
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.MicExternalOn
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.CoPresent
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.collectAsState
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
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.roro.futurevoice.data.BriefAttachmentCache
import com.roro.futurevoice.data.LearningPurposeStore
import com.roro.futurevoice.data.ScenarioAttachmentReader
import com.roro.futurevoice.talk.ScenarioBrief
import kotlinx.coroutines.launch
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
    /** "Add your exam": a new goal opened on that kind. */
    var addingKind by remember { mutableStateOf<UpcomingGoal.Kind?>(null) }
    val goals = remember(UpcomingGoalStore.goals, targetLanguage) {
        UpcomingGoalStore.active(context, targetLanguage)
    }
    // The purposes redraw this from any surface (or another device).
    val revision by com.roro.futurevoice.data.StoreEvents.revision.collectAsState()
    val purposes = remember(revision) { LearningPurposeStore.purposes(context) }
    /** A purpose whose goal isn't on file yet — "Add your exam" opens the
     *  editor on that kind. One row per kind, in the order the purposes were
     *  picked. */
    val missingKinds = remember(goals, purposes) {
        val have = goals.map { it.kind }.toSet()
        val out = mutableListOf<UpcomingGoal.Kind>()
        for (kind in purposes.mapNotNull { it.goalKinds.firstOrNull() }) {
            if (kind !in have && kind !in out) out += kind
        }
        out
    }
    GroupedSectionHeader(stringResource(R.string.coming_up))
    GroupedCard {
        goals.forEach { goal ->
            UpcomingGoalRow(goal, Modifier.fillMaxWidth().clickable { editing = goal }
                .padding(horizontal = 16.dp, vertical = 10.dp))
            GroupedRowDivider(inset = false)
        }
        missingKinds.forEach { kind ->
            Row(Modifier.fillMaxWidth().clickable { addingKind = kind }
                .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Outlined.AddCircleOutline, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                Text(stringResource(kind.addPrompt), style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary)
            }
            GroupedRowDivider(inset = false)
        }
        Text(stringResource(R.string.add_a_goal), style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.fillMaxWidth().clickable { adding = true }.padding(horizontal = 16.dp, vertical = 12.dp))
    }
    GroupedFooter(stringResource(R.string.an_exam_an_interview_a_move_your_tutor_prepares_you_for_it))
    editing?.let { g -> UpcomingGoalEditor(goal = g, language = targetLanguage, onDismiss = { editing = null }) }
    if (adding) UpcomingGoalEditor(goal = null, language = targetLanguage, onDismiss = { adding = false })
    addingKind?.let { k ->
        UpcomingGoalEditor(goal = null, language = targetLanguage, onDismiss = { addingKind = null }, kind = k)
    }
}

/** Add or change one upcoming goal (iOS `UpcomingGoalEditor`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpcomingGoalEditor(goal: UpcomingGoal?, language: String, onDismiss: () -> Unit,
                       onSaved: (UpcomingGoal?) -> Unit = {},
                       /** For a new goal: the one asked for (the profile's
                        *  "Add your exam"), else the first the learner's
                        *  purposes point to. */
                       kind: UpcomingGoal.Kind? = null) {
    val context = LocalContext.current
    val isNew = goal == null
    val start = remember {
        goal ?: UpcomingGoal(
            kind = kind ?: LearningPurposeStore.purposes(context).firstNotNullOfOrNull { it.goalKinds.firstOrNull() }
                ?: UpcomingGoal.Kind.INTERVIEW,
            title = "", language = language)
    }
    var draft by remember { mutableStateOf(start) }
    var hasDate by remember { mutableStateOf(start.date != null) }
    /** A date picked once survives the toggle being flipped off and on. */
    var pickedDate by remember {
        mutableStateOf(start.date ?: StudyPlan.addDays(StudyPlan.startOfDay(System.currentTimeMillis()), 14))
    }
    var kindMenu by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var addingLink by remember { mutableStateOf(false) }
    var attachMenu by remember { mutableStateOf(false) }
    var attachError by remember { mutableStateOf<String?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    /** The sources as opened, so a save knows whether to read them again. */
    val sourcesBefore = remember { start.brief?.sources?.map { it.id } ?: emptyList() }
    val sources = draft.brief?.sources ?: emptyList()

    fun save() {
        var g = draft.copy(
            title = draft.title.trim(), place = draft.place.trim(), notes = draft.notes.trim(),
            date = if (hasDate) StudyPlan.startOfDay(pickedDate) else null,
        )
        val changed = (g.brief?.sources?.map { it.id } ?: emptyList()) != sourcesBefore
        if (changed && g.brief != null) {
            // New material: what was found in the old set no longer stands.
            val kept = g.brief?.sources ?: emptyList()
            g = g.copy(brief = if (kept.isEmpty()) null else ScenarioBrief(sources = kept))
        }
        UpcomingGoalStore.save(context, g)
        if (g.brief?.needsReading == true) UpcomingGoalStore.readMaterialSoon(context, g.id)
        onSaved(UpcomingGoalStore.goal(context, g.id))
        onDismiss()
    }

    // Read from where the file lives: never copied into the app.
    fun add(source: ScenarioBrief.Source) {
        val brief = draft.brief ?: ScenarioBrief()
        draft = draft.copy(brief = brief.copy(sources = brief.sources + source))
    }
    fun addRead(read: ScenarioAttachmentReader.Read, label: String? = null, keepUri: Boolean = true) {
        val src = read.source.copy(label = label ?: read.source.label,
            androidUri = if (keepUri) read.source.androidUri else null)
        BriefAttachmentCache.put(src.id, read.data, read.mime)
        add(src)
    }
    fun photoLabel() = context.getString(R.string.photo_lld,
        sources.count { it.kind == ScenarioBrief.Kind.IMAGE } + 1)
    val pickFiles = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        scope.launch {
            for (uri in uris) {
                try { addRead(ScenarioAttachmentReader.read(context, uri)) }
                catch (e: ScenarioAttachmentReader.ReadError) { attachError = e.describe(context) }
            }
        }
    }
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            try { addRead(ScenarioAttachmentReader.read(context, uri), photoLabel(), keepUri = false) }
            catch (e: ScenarioAttachmentReader.ReadError) { attachError = e.describe(context) }
        }
    }
    val takePhoto = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bmp ->
        bmp ?: return@rememberLauncherForActivityResult
        val read = ScenarioAttachmentReader.read(bmp, photoLabel())
        if (read == null) attachError = context.getString(R.string.couldn_t_read_that_photo)
        else addRead(read)
    }
    fun attachLink(raw: String) {
        var text = raw.trim()
        if (text.isEmpty()) return
        if (!text.lowercase().startsWith("http://") && !text.lowercase().startsWith("https://")) text = "https://$text"
        val host = runCatching { java.net.URI(text).host }.getOrNull()
        if (host == null || !host.contains('.')) {
            attachError = context.getString(R.string.that_doesn_t_look_like_a_link); return
        }
        if (sources.any { it.kind == ScenarioBrief.Kind.LINK && it.label == text }) return
        add(ScenarioBrief.Source(kind = ScenarioBrief.Kind.LINK, label = text))
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
        FormSection(stringResource(R.string.material),
            footer = stringResource(R.string.read_once_when_you_save_files_stay_where_they_are_on_your_ph_cbc3e0)) {
            sources.forEach { src ->
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(briefSourceIcon(src), contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.width(22.dp).size(20.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(briefChipLabel(src), style = MaterialTheme.typography.bodyLarge, maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.MiddleEllipsis)
                        src.detail?.takeIf { it.isNotEmpty() }?.let {
                            Text(it, style = MaterialTheme.typography.labelMedium,
                                color = if (src.readOK) MaterialTheme.colorScheme.onSurfaceVariant
                                    else MaterialTheme.colorScheme.error)
                        }
                    }
                    // iOS deletes a source with a swipe (or a right-click on the Mac).
                    androidx.compose.material3.IconButton(onClick = {
                        BriefAttachmentCache.drop(src.id)
                        val b = draft.brief
                        if (b != null) draft = draft.copy(brief = b.copy(sources = b.sources.filter { it.id != src.id }))
                    }) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.remove),
                            tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
                    }
                }
                FormDivider()
            }
            Box {
                Row(Modifier.fillMaxWidth().clickable { attachMenu = true }.padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Filled.AttachFile, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp))
                    Text(stringResource(R.string.attach_a_posting_a_cv_the_exam_s_page), style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.primary)
                }
                IosMenu(attachMenu, { attachMenu = false }) {
                    IosMenuItem(stringResource(R.string.paste_a_link), onClick = { attachMenu = false; addingLink = true },
                        icon = Icons.Filled.Link, reserveCheck = false)
                    IosMenuItem(stringResource(R.string.pick_a_file), onClick = {
                        attachMenu = false; pickFiles.launch(ScenarioAttachmentReader.pickerTypes)
                    }, icon = Icons.Filled.Description, reserveCheck = false)
                    IosMenuItem(stringResource(R.string.photo_library), onClick = {
                        attachMenu = false
                        pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }, icon = Icons.Filled.PhotoLibrary, reserveCheck = false)
                    IosMenuItem(stringResource(R.string.take_a_photo), onClick = {
                        attachMenu = false; runCatching { takePhoto.launch(null) }
                    }, icon = Icons.Filled.CameraAlt, reserveCheck = false)
                }
            }
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
    if (addingLink) {
        var linkText by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { addingLink = false },
            title = { Text(stringResource(R.string.paste_a_link)) },
            text = {
                androidx.compose.material3.OutlinedTextField(value = linkText, onValueChange = { linkText = it },
                    placeholder = { Text("https://…", color = com.roro.futurevoice.ui.brand.iosPlaceholder()) },
                    singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        keyboardType = androidx.compose.ui.text.input.KeyboardType.Uri),
                    modifier = Modifier.fillMaxWidth())
            },
            confirmButton = {
                TextButton(onClick = { attachLink(linkText); addingLink = false }) { Text(stringResource(R.string.add)) }
            },
            dismissButton = { TextButton(onClick = { addingLink = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    attachError?.let { msg ->
        AlertDialog(
            onDismissRequest = { attachError = null },
            title = { Text(msg) },
            confirmButton = { TextButton(onClick = { attachError = null }) { Text(stringResource(R.string.ok)) } },
        )
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

/**
 * One goal's own page (iOS `UpcomingGoalPage`, 2c8133c8), opened from the
 * tutor's note: the countdown, what the day will most likely ask (tap one to
 * drill it with the tutor), and every day of preparation so far.
 */
@Composable
fun UpcomingGoalPage(initial: UpcomingGoal, state: AppState, onDismiss: () -> Unit) {
    val context = LocalContext.current
    /** The goal as stored now — reading its material saves it again. */
    val goal = UpcomingGoalStore.goals.firstOrNull { it.id == initial.id } ?: initial
    var questions by remember { mutableStateOf<List<com.roro.futurevoice.talk.GoalPrep.Question>?>(null) }
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }
    var reading by remember { mutableStateOf<com.roro.futurevoice.talk.TutorReading?>(null) }
    var editing by remember { mutableStateOf(false) }

    val scope = androidx.compose.runtime.rememberCoroutineScope()
    LaunchedEffect(goal.updatedAt, attempt) {
        questions = null
        if (goal.brief?.needsReading == true && goal.id !in UpcomingGoalStore.materialFailed) {
            UpcomingGoalStore.readMaterial(context, goal.id, state.persona, state.nativeLanguage)
            // Read and saved: this effect runs again for the new goal. Not
            // read: the questions go ahead without it.
            if (UpcomingGoalStore.goal(context, goal.id)?.brief?.needsReading != true) return@LaunchedEffect
        }
        questions = com.roro.futurevoice.talk.GoalPrep.cachedQuestions(context, goal) ?: try {
            com.roro.futurevoice.talk.GoalPrep.questions(context, goal, state.nativeLanguage, state.level)
        } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (_: Exception) {
            failed = true; null
        }
    }

    /** A tutor-mode call on this one question. The page goes first, and the
     *  chat too when it was opened from there (iOS ec0de1e5). */
    fun drill(question: String) {
        com.roro.futurevoice.core.Analytics.capture("upcoming_goal_question_drill", mapOf("kind" to goal.kind.raw))
        onDismiss()
        com.roro.futurevoice.talk.TutorBot.chatOpen = false
        com.roro.futurevoice.talk.TutorBot.goalCall = com.roro.futurevoice.talk.TutorBot.GoalCall(
            topic = "“$question” — ${goal.title}", blurb = goal.drillBlurb)
    }

    com.roro.futurevoice.ui.speech.SpeechSheet(onDismiss) {
        SheetHeader(stringResource(goal.kind.label),
            leading = { IosGlassTextButton(stringResource(R.string.edit), onClick = { editing = true }) },
            trailing = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss, bold = true) })
        FormSection(null) {
            UpcomingGoalRow(goal, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp))
            if (goal.notes.isNotEmpty()) {
                FormDivider()
                Text(goal.notes, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
            }
        }
        if (goal.brief?.hasSources == true) {
            // What the material is and what the reading found, with Read again.
            val brief = goal.brief ?: ScenarioBrief()
            val reading = goal.id in UpcomingGoalStore.readingMaterial
            FormSection(stringResource(R.string.material),
                footer = brief.readAt?.let { stringResource(R.string.read, abbreviatedDate(it)) }) {
                if (reading) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text(stringResource(R.string.reading_your_material), style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    FormDivider()
                } else if (brief.summary.isNotEmpty()) {
                    Text(brief.summary, style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
                    FormDivider()
                }
                brief.sources.forEach { src ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(briefSourceIcon(src), contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(briefChipLabel(src), style = MaterialTheme.typography.bodyLarge, maxLines = 1,
                                overflow = androidx.compose.ui.text.style.TextOverflow.MiddleEllipsis)
                            src.detail?.takeIf { it.isNotEmpty() }?.let {
                                Text(it, style = MaterialTheme.typography.labelMedium,
                                    color = if (src.readOK) MaterialTheme.colorScheme.onSurfaceVariant
                                        else MaterialTheme.colorScheme.error)
                            }
                        }
                    }
                    FormDivider()
                }
                if (goal.id in UpcomingGoalStore.materialFailed) {
                    Text(stringResource(R.string.couldn_t_read_it_this_time), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    FormDivider()
                }
                if (!reading) {
                    Text(stringResource(if (brief.readAt == null) R.string.read_it else R.string.read_again),
                        style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.fillMaxWidth().clickable {
                            val g = goal.copy(brief = brief.copy(readAt = null))
                            UpcomingGoalStore.save(context, g)
                            scope.launch {
                                UpcomingGoalStore.readMaterial(context, g.id, state.persona, state.nativeLanguage)
                            }
                        }.padding(horizontal = 16.dp, vertical = 12.dp))
                }
            }
        }
        val loaded = questions
        FormSection(stringResource(R.string.likely_questions),
            footer = if (loaded != null) stringResource(R.string.tap_one_to_practice_it_with_your_tutor_until_it_comes_out_cl_2ab412) else null) {
            when {
                loaded != null -> loaded.forEachIndexed { i, q ->
                    if (i > 0) FormDivider()
                    Row(Modifier.fillMaxWidth().clickable { drill(q.text) }
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(q.text, style = MaterialTheme.typography.bodyLarge)
                            if (q.looksFor.isNotEmpty()) {
                                Text(q.looksFor, style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Icon(Icons.Filled.School, contentDescription = null, tint = goal.kind.color(),
                            modifier = Modifier.size(20.dp))
                    }
                }
                failed -> Text(stringResource(R.string.try_again), style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.fillMaxWidth().clickable { failed = false; attempt += 1 }
                        .padding(horizontal = 16.dp, vertical = 12.dp))
                else -> Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Text(stringResource(R.string.working_out_what_they_ll_ask), style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        val days = remember(goal.updatedAt, reading) { com.roro.futurevoice.talk.GoalPrep.days(context, goal) }
        if (days.isNotEmpty()) {
            FormSection(stringResource(R.string.prepared_so_far)) {
                days.forEachIndexed { i, day ->
                    if (i > 0) FormDivider()
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(day.focus, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        PreparedLink(Icons.AutoMirrored.Filled.MenuBook, day.reading.title) {
                            reading = com.roro.futurevoice.talk.TutorReading(
                                script = day.script(com.roro.futurevoice.talk.GoalPrep.Part.READING),
                                goal = goal, part = com.roro.futurevoice.talk.GoalPrep.Part.READING)
                        }
                        PreparedLink(Icons.Filled.MicExternalOn, day.speech.question ?: day.speech.title) {
                            reading = com.roro.futurevoice.talk.TutorReading(
                                script = day.script(com.roro.futurevoice.talk.GoalPrep.Part.SPEECH),
                                goal = goal, part = com.roro.futurevoice.talk.GoalPrep.Part.SPEECH)
                        }
                    }
                }
            }
        }
    }
    reading?.let { r -> TutorReadingSheet(r, state, onDismiss = { reading = null }) }
    if (editing) {
        UpcomingGoalEditor(goal = goal, language = goal.language, onDismiss = { editing = false },
            onSaved = { saved ->
                // Saved or deleted: the page shows a goal that may be gone.
                if (saved == null) onDismiss()
            })
    }
}

/** A day's reading or answer on the goal page (iOS `.buttonStyle(.borderless)` Label). */
@Composable
private fun PreparedLink(icon: ImageVector, title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick), verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(top = 2.dp).size(18.dp))
        Text(title, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
    }
}
