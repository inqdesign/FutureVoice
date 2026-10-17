package com.roro.futurevoice.ui

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.defaultRegisters
import com.roro.futurevoice.talk.CounterpartParser
import com.roro.futurevoice.talk.PublicFigureLookup
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.iosFill
import kotlinx.coroutines.launch
import androidx.annotation.StringRes

/**
 * New person, on ONE card (iOS `CounterpartVoiceIntakeView`, 2026-10-16,
 * founder: "간편하게 — 이게 너무 복잡해"). It was eight: name, relationship,
 * how you talk, three relationship-tailored question cards, interests, style.
 * Now the card asks only what a form can't guess — the face and name, who
 * they are to you, and one free note (spoken or typed, any language) — and
 * the parse fills the form, where everything else (how you two talk, what you
 * call each other, topics, manner) is prefilled to confirm. A public figure
 * still skips the note: the model knows them, the lookup names them.
 *
 * Drawn the way iOS draws it: a plain page, a Cancel glass capsule beside the
 * title in the display face, three sections each a headline label over one
 * grey filled card, "Rather just fill in a form?" at the foot of the scroll,
 * and one full-width Continue capsule pinned to a bar at the bottom.
 *
 * Relationship chip VALUES stay English on purpose — they are what the parser
 * reads and what `Counterpart.relationshipKind` stores — and only their labels
 * are translated ([intakeLabel]).
 */
@Composable
fun CounterpartIntakeScreen(
    nativeLanguage: String,
    @Suppress("UNUSED_PARAMETER") targetLanguage: String,
    /** The parsed draft (or null for the plain form) and the photo picked on
     *  the card — the person doesn't exist yet, so it rides along. */
    onDraft: (Counterpart?, Bitmap?) -> Unit,
    onCancel: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    // Screenshot harness (iOS `-intakeStep <any>`): fills the card with iOS's
    // stand-in data. Null in every normal build.
    val standIn = remember { com.roro.futurevoice.capture.flags.WatchCaptureFlags.intakeStep != null }
    var name by remember { mutableStateOf(if (standIn) "Boram" else "") }
    var kind by remember { mutableStateOf(if (standIn) RelationshipKind.FELLOW_PARENT else null) }
    var kindDetail by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var photo by remember { mutableStateOf<Bitmap?>(null) }
    var parsing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    // Answered IN the learner's own language by default: that's where people
    // say the most about someone they know.
    val locale = remember { LanguageCatalog.sttLocale(nativeLanguage) }
    androidx.activity.compose.BackHandler { onCancel() }

    val canContinue = name.isNotBlank() && kind != null

    /** The relationship's own speech levels, so the form opens on them as a
     *  confirmation — the card no longer asks how the two of them talk. */
    fun applyDefaults(draft: Counterpart): Counterpart {
        val (mine, theirs) = defaultRegisters(kind?.label)
        return draft.copy(relationshipKind = kind?.label, myRegister = mine, theirRegister = theirs)
    }

    fun parseAndContinue() {
        scope.launch {
            parsing = true; error = null
            val k = kind ?: RelationshipKind.OTHER
            val relationshipLabel = kindDetail.ifBlank { context.getString(k.title) }
            // A public figure: the model already knows the person, so the
            // only question is WHICH one — look that up and hand the form an
            // identity to confirm. Not found opens nothing; the error says so
            // and the name can be fixed here.
            if (k == RelationshipKind.PUBLIC_FIGURE) {
                try {
                    val identity = PublicFigureLookup.identify(name.trim(), nativeLanguage)
                    onDraft(Counterpart(
                        name = name.trim(),
                        relationship = relationshipLabel,
                        relationshipKind = k.label,
                        isPublicFigure = true,
                        publicIdentity = identity,
                        factsRefreshedAt = System.currentTimeMillis(),
                    ), photo)
                } catch (e: Exception) {
                    error = context.getString(R.string.intake_lookup_failed, e.message.orEmpty())
                } finally {
                    parsing = false
                }
                return@launch
            }
            val typed = note.trim()
            if (typed.isEmpty()) {
                // Nothing to extract — skip the model, straight to the form.
                onDraft(applyDefaults(Counterpart(name = name.trim(), relationship = relationshipLabel)), photo)
                parsing = false
                return@launch
            }
            val kindLabel = listOf(k.label, kindDetail).filter { it.isNotBlank() }.joinToString(" — ")
            val sections = mutableListOf("Their name: ${name.trim()}")
            if (kindLabel.isNotEmpty()) sections += "Relationship to me: $kindLabel"
            sections += "About them: $typed"
            try {
                val draft = CounterpartParser.parse(sections.joinToString("\n\n"), locale, nativeLanguage)
                    // What the user typed outright wins over the parse.
                    .copy(name = name.trim())
                // The parser is told not to invent, so it can return no
                // relationship; the form's Save needs one.
                onDraft(applyDefaults(draft.copy(
                    relationship = draft.relationship.ifBlank { relationshipLabel })), photo)
            } catch (e: Exception) {
                error = context.getString(R.string.intake_parse_failed, e.message.orEmpty())
            } finally {
                parsing = false
            }
        }
    }

    val page = MaterialTheme.colorScheme.surface
    val sectionTitle = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold)
    Column(Modifier.fillMaxSize().background(page)) {
        // The navigation bar: Cancel as a glass capsule, the title centred
        // in the display face (iOS `.navigationBarTitleDisplayMode(.inline)`).
        val title = stringResource(R.string.tell_me_about_them)
        SheetHeader(title,
            leading = { IosGlassTextButton(stringResource(R.string.cancel), onClick = onCancel) },
            modifier = Modifier.statusBarsPadding().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 4.dp))
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // Same shape as the two sections under it: a label, then one grey
            // card — the face and the name on a single row, like Contacts.
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stringResource(R.string.name), style = sectionTitle)
                Row(Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill()).padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    // Their face, optional; saved small and square with the
                    // person, never sent anywhere.
                    PersonPhotoControl(image = photo?.asImageBitmap(), name = name, size = 56.dp,
                        onImage = { photo = it },
                        onRemove = if (photo == null) null else ({ photo = null }))
                    val nameStyle = MaterialTheme.typography.titleLarge.copy(color = MaterialTheme.colorScheme.onSurface)
                    BasicTextField(
                        value = name, onValueChange = { name = it }, textStyle = nameStyle, singleLine = true,
                        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                        modifier = Modifier.weight(1f),
                        decorationBox = { inner ->
                            Box {
                                if (name.isEmpty()) Text(stringResource(R.string.their_name_as_you_call_them),
                                    style = nameStyle,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.28f))
                                inner()
                            }
                        },
                    )
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stringResource(R.string.intake_relationship_title), style = sectionTitle)
                IntakeCard {
                    ChipGrid(RelationshipKind.entries.map { it.label }, setOfNotNull(kind?.label)) { tag ->
                        kind = RelationshipKind.entries.first { it.label == tag }
                    }
                    // Writing the relationship IS answering, so it lights
                    // Other, which the learner can still change.
                    InlineField(kindDetail, {
                        kindDetail = it
                        if (kind == null && it.isNotBlank()) kind = RelationshipKind.OTHER
                    }, stringResource(R.string.intake_more_precisely))
                }
                if (kind == RelationshipKind.PUBLIC_FIGURE) {
                    Text(stringResource(R.string.rel_public_figure_we_find_you_confirm),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            // The one free note — everything the old question cards asked,
            // in the learner's own words, optional.
            if (kind != RelationshipKind.PUBLIC_FIGURE) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.intake_q_what_else), style = sectionTitle)
                    SpeakOrTypeField(
                        text = note, onText = { note = it },
                        usedVoice = false, onUsedVoice = {},
                        placeholder = stringResource(R.string.intake_anything_more),
                        locale = locale,
                    )
                }
            }
            error?.let {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Warning, contentDescription = null, modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.error)
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
            Text(stringResource(R.string.rather_just_fill_in_a_form),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.CenterHorizontally)
                    .clickable(interactionSource = remember { MutableInteractionSource() },
                        indication = null, role = Role.Button) { onDraft(null, photo) }
                    .padding(vertical = 4.dp))
        }
        IntakeBottomBar(
            backVisible = false,
            nextTitle = stringResource(R.string.continue_),
            nextEnabled = canContinue,
            working = parsing,
            onBack = {},
            onNext = { parseAndContinue() },
        )
    }
}

// MARK: - The shared intake pieces (iOS `GuidedIntake.swift`)

/** iOS `secondarySystemBackground`: the grey an intake card or field sits
 *  on, over the white page. */
@Composable
internal fun cardFill() = iosFill()

/** `ProgressView(value:total:)` — a 4 pt capsule track, the accent fill. */
@Composable
internal fun IntakeProgress(fraction: Float, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(iosFill())) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(4.dp).clip(CircleShape)
            .background(MaterialTheme.colorScheme.primary))
    }
}

/** iOS `IntakeStepHeader`: `.title2.bold()` and a `.callout` grey line. */
@Composable
internal fun IntakeStepHeader(question: String, detail: String) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(question, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (detail.isNotEmpty()) Text(detail, style = MaterialTheme.typography.bodyLarge.copy(
            fontSize = MaterialTheme.typography.bodyLarge.fontSize * (16f / 17f)),
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The grey rounded card chips and an inline field sit in (padding 14, r 12). */
@Composable
internal fun IntakeCard(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill()).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
}


/** A bare `TextField` inside a card: text and placeholder, nothing drawn around it. */
@Composable
internal fun InlineField(value: String, onChange: (String) -> Unit, placeholder: String,
                        onDone: (() -> Unit)? = null) {
    val style = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface)
    BasicTextField(
        value = value, onValueChange = onChange, textStyle = style, singleLine = true,
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(imeAction = if (onDone != null) ImeAction.Done else ImeAction.Default),
        keyboardActions = KeyboardActions(onDone = { onDone?.invoke() }),
        modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = style,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.28f),
                    maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                inner()
            }
        },
    )
}

/** iOS `IntakeChipLabel`: `.subheadline` in a capsule, 12 × 6 padding —
 *  the accent with a white label when picked, the grey fill otherwise. */
@Composable
internal fun IntakeChipLabel(text: String, isOn: Boolean, onClick: () -> Unit) {
    Text(
        intakeLabel(text),
        style = MaterialTheme.typography.bodyMedium,
        color = if (isOn) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.onSurface,
        modifier = Modifier
            .clip(CircleShape)
            .background(if (isOn) MaterialTheme.colorScheme.primary else iosFill())
            .clickable(role = Role.Checkbox, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

/**
 * `LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
 * alignment: .leading, spacing: 8)` — as many ≥110 pt columns as fit, each
 * chip at the LEADING edge of its cell, so the chips line up in columns
 * rather than flowing like words.
 */
@Composable
private fun ChipGrid(items: List<String>, selection: Set<String>, onToggle: (String) -> Unit) {
    Layout(
        content = { items.forEach { tag -> IntakeChipLabel(tag, tag in selection) { onToggle(tag) } } },
        modifier = Modifier.fillMaxWidth(),
    ) { measurables, constraints ->
        val gap = 8.dp.roundToPx()
        val min = 110.dp.roundToPx()
        val width = constraints.maxWidth
        val cols = maxOf(1, (width + gap) / (min + gap))
        val cell = (width - gap * (cols - 1)) / cols
        val placeables = measurables.map { it.measure(Constraints(maxWidth = cell)) }
        val rows = placeables.chunked(cols)
        val heights = rows.map { r -> r.maxOf { it.height } }
        val total = heights.sum() + gap * (rows.size - 1).coerceAtLeast(0)
        layout(width, total) {
            var y = 0
            rows.forEachIndexed { ri, r ->
                r.forEachIndexed { ci, p -> p.place(ci * (cell + gap), y) }
                y += heights[ri] + gap
            }
        }
    }
}

/**
 * iOS `ChipPickerField`: the chips, flowing, in a grey card, and — with
 * [allowsCustom] — a bare "Add your own (comma-separated)" line under it.
 * What is typed there is folded in on Done and when the card leaves (Next),
 * split on commas; custom picks show as chips beside the presets.
 */
@Composable
internal fun ChipPickerField(presets: List<String>, selection: Set<String>, allowsCustom: Boolean,
                            onToggle: (String) -> Unit) {
    var draft by remember { mutableStateOf("") }
    val currentSelection by rememberUpdatedState(selection)
    val toggle by rememberUpdatedState(onToggle)
    fun merge() {
        draft.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            .filter { it !in currentSelection }.distinct().forEach { toggle(it) }
        draft = ""
    }
    DisposableEffect(Unit) { onDispose { merge() } }
    IntakeCard {
        // iOS `FlowLayout(spacing: 8, lineSpacing: 8)`: chips flow like words
        // (the adaptive 110 pt grid is the relationship card's, not this one).
        @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
        androidx.compose.foundation.layout.FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            (presets + selection.filter { it !in presets }).forEach { tag ->
                IntakeChipLabel(tag, tag in selection) { onToggle(tag) }
            }
        }
        if (allowsCustom) {
            InlineField(draft, { draft = it }, stringResource(R.string.add_your_own_comma_separated),
                onDone = { merge() })
        }
    }
}

/**
 * iOS `IntakeBottomBar`: Back (`.bordered`, chevron + label) and Next
 * (`.borderedProminent`) as large full-width capsules on the bar material;
 * Next shows a spinner and "Sorting it out…" while the parse runs.
 */
@Composable
internal fun IntakeBottomBar(
    backVisible: Boolean,
    nextTitle: String,
    nextEnabled: Boolean,
    working: Boolean,
    onBack: () -> Unit,
    onNext: () -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    val faded = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.25f)
    Row(
        Modifier.fillMaxWidth().background(com.roro.futurevoice.ui.brand.AppSurfaces.ground.copy(alpha = 0.55f))
            .bottomBarInsets().padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (backVisible) {
            CapsuleButton(enabled = !working, fill = iosFill(), onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = null,
                    tint = if (!working) accent else faded, modifier = Modifier.size(24.dp))
                Spacer(Modifier.width(2.dp))
                Text(stringResource(R.string.back), style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium, color = if (!working) accent else faded)
            }
        }
        val on = nextEnabled && !working
        // Disabled, iOS draws the prominent capsule barely there on the bar.
        CapsuleButton(enabled = on, fill = if (on) accent
            else MaterialTheme.colorScheme.surface.copy(alpha = 0.6f), onClick = onNext) {
            if (working) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = faded)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.sorting_it_out), style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium, color = faded)
            } else {
                Text(nextTitle, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium,
                    color = if (on) MaterialTheme.colorScheme.surface else faded)
            }
        }
    }
}

@Composable
internal fun RowScope.CapsuleButton(enabled: Boolean, fill: androidx.compose.ui.graphics.Color,
                                   onClick: () -> Unit, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.weight(1f).height(50.dp).clip(CircleShape).background(fill)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}
/**
 * The label a relationship chip is DRAWN with. The value itself stays English
 * (prompt material, the selection key, `Counterpart.relationshipKind`);
 * anything not here — the persona intake's interest presets, a learner's own
 * typed chip — falls through to [presetLabel], which shows a typed tag as
 * written.
 */
private val INTAKE_LABELS: Map<String, Int> = mapOf(
    "Friend" to R.string.intake_rel_friend,
    "Family" to R.string.intake_rel_family,
    "Partner" to R.string.intake_rel_partner,
    "Coworker" to R.string.intake_rel_coworker,
    "Manager" to R.string.intake_rel_manager,
    "Fellow parent" to R.string.intake_rel_fellow_parent,
    "Neighbor" to R.string.intake_rel_neighbor,
    "Teacher" to R.string.intake_rel_teacher,
    "Other" to R.string.intake_rel_other,
    "Public figure" to R.string.public_figure,
)

@Composable
internal fun intakeLabel(tag: String): String =
    INTAKE_LABELS[tag]?.let { stringResource(it) } ?: presetLabel(tag)

/** The relationship chips on the card (iOS `RelationshipKind`). [label] is
 *  the STORED value (`Counterpart.relationshipKind`, read by
 *  `defaultRegisters` and the cast rules) and stays English; [title] is what
 *  the chip shows. */
private enum class RelationshipKind(val label: String, @StringRes val title: Int) {
    FRIEND("Friend", R.string.intake_rel_friend),
    FAMILY("Family", R.string.intake_rel_family),
    PARTNER("Partner", R.string.intake_rel_partner),
    COWORKER("Coworker", R.string.intake_rel_coworker),
    MANAGER("Manager", R.string.intake_rel_manager),
    FELLOW_PARENT("Fellow parent", R.string.intake_rel_fellow_parent),
    NEIGHBOR("Neighbor", R.string.intake_rel_neighbor),
    TEACHER("Teacher", R.string.intake_rel_teacher),
    /** A singer, an actor, an athlete — someone not in the learner's life.
     *  Its own kind, not "Other": the name is looked up, so the person is the
     *  public record rather than the learner's guess. */
    PUBLIC_FIGURE("Public figure", R.string.public_figure),
    OTHER("Other", R.string.intake_rel_other),
}
