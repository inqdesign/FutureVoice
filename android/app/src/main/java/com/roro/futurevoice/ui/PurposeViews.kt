package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ExpandMore
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.ExamKind
import com.roro.futurevoice.data.LearningPurpose
import com.roro.futurevoice.data.LearningPurposeStore
import com.roro.futurevoice.data.PurposeDetails
import com.roro.futurevoice.data.RoutineText
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.Symbols
import com.roro.futurevoice.ui.brand.iosFill

/**
 * "Why are you learning?" — many answers, numbered in the order tapped
 * (iOS `PurposePickerRows`). Setup asks it and Talk's settings change it;
 * one set of rows for both. Drawn INSIDE a card.
 *
 * An ACCORDION: picking a purpose that has more to say opens it right under
 * its row — which exam, the role applied for, the job and the role in it,
 * the school and the subject. All optional.
 */
@Composable
fun PurposePickerRows(
    purposes: List<LearningPurpose>,
    onPurposes: (List<LearningPurpose>) -> Unit,
    details: PurposeDetails,
    onDetails: (PurposeDetails) -> Unit,
    exam: ExamKind,
    onExam: (ExamKind) -> Unit,
    language: String,
) {
    LearningPurpose.entries.forEachIndexed { i, p ->
        if (i > 0) FormDivider(inset = 58.dp)
        val n = purposes.indexOf(p).takeIf { it >= 0 }
        // At most three: each purpose adds a chip to Talk, and past three
        // the row stops being a choice and becomes a list.
        val full = n == null && purposes.size >= MAX_PICKED
        Row(
            Modifier.fillMaxWidth()
                .alpha(if (full) 0.4f else 1f)
                .clickable(enabled = !full) {
                    onPurposes(if (n != null) purposes - p else purposes + p)
                }
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.size(30.dp).background(Color(p.tint), RoundedCornerShape(7.dp)),
                contentAlignment = Alignment.Center) {
                Icon(Symbols.icon(p.symbol), contentDescription = null, tint = Color.White,
                    modifier = Modifier.size(18.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(p.title), style = MaterialTheme.typography.bodyLarge)
                Text(stringResource(p.subtitle), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Box(Modifier.size(24.dp)
                .then(if (n != null) Modifier.background(MaterialTheme.colorScheme.primary, CircleShape)
                else Modifier.border(1.5.dp, MaterialTheme.colorScheme.outline, CircleShape)),
                contentAlignment = Alignment.Center) {
                if (n != null) Text("${n + 1}", color = Color.White, fontSize = 13.sp,
                    fontWeight = FontWeight.Bold)
            }
        }
        if (n != null) PurposeDetail(p, details, onDetails, exam, onExam, language)
    }
}

/** iOS `PurposePickerRows.maxPicked`. */
private const val MAX_PICKED = 3

@Composable
private fun PurposeDetail(
    p: LearningPurpose,
    details: PurposeDetails,
    onDetails: (PurposeDetails) -> Unit,
    exam: ExamKind,
    onExam: (ExamKind) -> Unit,
    language: String,
) {
    when (p) {
        LearningPurpose.EXAM -> {
            val options = ExamKind.options(language)
            val shown = if (exam in options) exam else options[0]
            if (shown != exam) androidx.compose.runtime.LaunchedEffect(language) { onExam(shown) }
            FormDivider(inset = 58.dp)
            var open by remember { mutableStateOf(false) }
            Row(Modifier.fillMaxWidth().clickable { open = true }
                .padding(start = 58.dp, end = 16.dp, top = 11.dp, bottom = 11.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.which_exam), style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f))
                Box {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(shown.examName, style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Icon(Icons.Filled.ExpandMore, contentDescription = null, modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    com.roro.futurevoice.ui.brand.IosPickerMenu(
                        expanded = open, onDismissRequest = { open = false },
                        options = options.map { it to it.examName },
                        selected = shown, onPick = onExam)
                }
            }
        }
        LearningPurpose.STUDY -> {
            DetailField(stringResource(R.string.school_or_university), details.school) { onDetails(details.copy(school = it)) }
            DetailField(stringResource(R.string.subject_e_g_mechanical_engineering), details.subject) { onDetails(details.copy(subject = it)) }
        }
        LearningPurpose.JOB ->
            DetailField(stringResource(R.string.role_you_re_applying_for_e_g_backend_developer), details.target) { onDetails(details.copy(target = it)) }
        LearningPurpose.WORK -> {
            DetailField(stringResource(R.string.your_job_e_g_product_manager), details.job) { onDetails(details.copy(job = it)) }
            DetailField(stringResource(R.string.what_you_do_in_it_e_g_i_run_the_mobile_team), details.role) { onDetails(details.copy(role = it)) }
        }
        else -> {}
    }
}

/** `TextField(prompt, axis: .vertical)` at subheadline size, indented under
 *  the row's text. */
@Composable
private fun DetailField(placeholder: String, value: String, onChange: (String) -> Unit) {
    FormDivider(inset = 58.dp)
    val style = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface)
    BasicTextField(
        value = value, onValueChange = onChange, textStyle = style,
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        modifier = Modifier.fillMaxWidth().padding(start = 58.dp, end = 16.dp, top = 11.dp, bottom = 11.dp),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = style,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
                inner()
            }
        },
    )
}

/**
 * The ONE settings page for Talk's chip row — whichever chip is showing, the
 * same button opens it (iOS `DiscoverSettingsSheet`): why you're learning,
 * which exam (while an exam is among the purposes), and the interests the
 * News chip searches for. Typed interests are chips like the presets, so
 * they can be seen and taken off, and the six the news pool reads is shown.
 *
 * Nothing is written until Save.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DiscoverSettingsSheet(
    persona: UserPersona?,
    language: String,
    onSavePersona: (UserPersona) -> Unit,
    onDismiss: () -> Unit,
    /** Called after Save wrote everything — the row re-reads its chips. */
    onSaved: () -> Unit,
) {
    val context = LocalContext.current
    var purposes by remember { mutableStateOf(LearningPurposeStore.purposes(context)) }
    var exam by remember { mutableStateOf(LearningPurposeStore.exam(context, language)) }
    var details by remember { mutableStateOf(LearningPurposeStore.details(context)) }
    var interests by remember { mutableStateOf(persona?.interests.orEmpty().take(MAX_INTERESTS)) }
    var draft by remember { mutableStateOf("") }
    val canAdd = interests.size < MAX_INTERESTS

    fun addDraft() {
        var list = interests
        for (piece in draft.split(",").map { it.trim() }) {
            if (piece.isNotEmpty() && list.size < MAX_INTERESTS &&
                list.none { it.equals(piece, ignoreCase = true) }) list = list + piece
        }
        interests = list
        draft = ""
    }

    fun save() {
        addDraft()
        LearningPurposeStore.setPurposes(context, purposes)
        LearningPurposeStore.setExam(context, exam, language)
        LearningPurposeStore.setDetails(context, details)
        if (interests != persona?.interests.orEmpty()) {
            onSavePersona((persona ?: UserPersona()).copy(interests = interests))
        }
        onSaved()
        onDismiss()
    }

    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
        containerColor = AppSurfaces.ground,
    ) {
        SheetHeader(
            title = stringResource(R.string.talk_settings),
            leading = { IosGlassTextButton(stringResource(R.string.cancel), onClick = onDismiss) },
            trailing = { IosGlassTextButton(stringResource(R.string.save), onClick = { save() }, bold = true) },
            modifier = Modifier.padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 8.dp),
        )
        Column(Modifier.fillMaxWidth().bottomBarInsets().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp).padding(bottom = 28.dp)) {
            FormSection(
                header = stringResource(R.string.why_are_you_learning),
                footer = stringResource(R.string.up_to_three_the_chips_under_talk_follow_them_in_the_order_yo_4b1735),
            ) {
                PurposePickerRows(purposes, { purposes = it }, details, { details = it }, exam, { exam = it },
                    language)
            }

            // Header with the count the news pool reads (`news-topics`
            // MAX_CATEGORIES) — past six it used to drop interests silently.
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 8.dp)) {
                Text(stringResource(R.string.interests), style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                Text("${interests.size} / $MAX_INTERESTS", style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            FormCard {
                // Picked ones first (presets and typed alike, each with its
                // ×), then the presets not picked yet. A flow, not a grid: a
                // typed interest is as long as its name.
                FlowRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    interests.forEach { tag ->
                        val label = presetLabel(tag)
                        val remove = stringResource(R.string.remove_4f3891, label)
                        Row(Modifier.background(MaterialTheme.colorScheme.primary, CircleShape)
                            .clickable { interests = interests - tag }
                            .semantics { contentDescription = remove }
                            .padding(horizontal = 12.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(label, maxLines = 1, style = MaterialTheme.typography.bodyMedium,
                                color = AppSurfaces.card)
                            Icon(Icons.Filled.Close, contentDescription = null, tint = AppSurfaces.card,
                                modifier = Modifier.size(12.dp))
                        }
                    }
                    INTEREST_PRESETS.filter { it !in interests }.forEach { tag ->
                        Text(presetLabel(tag), maxLines = 1, style = MaterialTheme.typography.bodyMedium,
                            color = if (canAdd) MaterialTheme.colorScheme.onSurface
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.background(iosFill(), CircleShape)
                                .clickable(enabled = canAdd) { interests = interests + tag }
                                .padding(horizontal = 12.dp, vertical = 7.dp))
                    }
                }
                FormDivider()
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    val style = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface)
                    BasicTextField(
                        value = draft, onValueChange = { draft = it }, textStyle = style, singleLine = true,
                        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { addDraft() }),
                        modifier = Modifier.weight(1f).padding(vertical = 11.dp),
                        decorationBox = { inner ->
                            Box {
                                if (draft.isEmpty()) Text(stringResource(R.string.a_company_a_team_a_person_anything),
                                    style = style, maxLines = 1,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
                                inner()
                            }
                        },
                    )
                    val enabled = canAdd && draft.isNotBlank()
                    Icon(Icons.Filled.AddCircle, contentDescription = stringResource(R.string.add),
                        tint = if (enabled) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
                        modifier = Modifier.size(24.dp).clickable(enabled = enabled) { addDraft() })
                }
            }
            Text(stringResource(R.string.the_news_chip_brings_this_week_s_stories_for_each_one),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
        }
    }
}

/** The news pool reads at most this many (`news-topics` MAX_CATEGORIES). */
private const val MAX_INTERESTS = 6

private val INTEREST_PRESETS = listOf(
    "AI / tech", "parenting", "language learning", "music", "podcasts",
    "cooking", "travel", "sports", "fashion", "finance", "science", "art",
)

/**
 * The week as a picture (iOS `RoutineWeekPicture`): Monday to Sunday, one
 * column a day, one bar per thing planned in the day's order. Talks are
 * drawn taller, because they are the time; everything else is a count. The
 * weekly test sits on its own day from its own settings.
 */
@Composable
fun RoutineWeekPicture(blocks: List<StudyPlan.Block>) {
    val context = LocalContext.current
    val res = context.resources
    val locale = LocalConfiguration.current.locales[0]
    val testDay = remember { WeeklyTestSettings.weekday(context) }
    fun kinds(day: Int): List<StudyPlan.Kind> {
        val list = blocks.filter { day in it.weekdays }.sortedBy { it.startMinute }.map { it.kind }
        return if (day == testDay) list + StudyPlan.Kind.TEST else list
    }
    val legend = buildList {
        blocks.forEach { if (it.kind !in this) add(it.kind) }
        add(StudyPlan.Kind.TEST)
    }
    val label = stringResource(R.string.the_week_at_a_glance)
    Column(Modifier.semantics(mergeDescendants = true) { contentDescription = label },
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth().height(110.dp), verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(2, 3, 4, 5, 6, 7, 1).forEach { day ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.Bottom)) {
                    kinds(day).forEach { k ->
                        Box(Modifier.fillMaxWidth().height(if (k == StudyPlan.Kind.TALK) 22.dp else 12.dp)
                            .background(k.color(), RoundedCornerShape(3.dp)))
                    }
                    val dow = java.time.DayOfWeek.of(if (day == 1) 7 else day - 1)
                    Text(dow.getDisplayName(java.time.format.TextStyle.NARROW, locale),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 2.dp))
                }
            }
        }
        FlowRow12 {
            legend.forEach { k ->
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(Modifier.size(8.dp).background(k.color(), CircleShape))
                    Text(RoutineText.label(res, k), style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

/** iOS's legend is an `HStack(spacing: 12)`; a row that runs out of room
 *  wraps here rather than clipping a label. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FlowRow12(content: @Composable () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) { content() }
}
