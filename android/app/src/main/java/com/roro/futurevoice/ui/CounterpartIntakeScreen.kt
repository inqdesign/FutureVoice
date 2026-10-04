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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechRegister
import com.roro.futurevoice.data.defaultRegisters
import com.roro.futurevoice.talk.CounterpartParser
import com.roro.futurevoice.talk.PublicFigureLookup
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.DisplayFace
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.iosFill
import kotlinx.coroutines.launch
import androidx.annotation.StringRes

/**
 * Guided new-person flow, one card per category (iOS
 * `CounterpartVoiceIntakeView`). Name is typed, the relationship is a chip
 * pick, and the relationship then TAILORS the three narrative cards (a fellow
 * Kita parent is asked about the kids; a manager about 1:1s). Narrative cards
 * are tap-first — common answers as chips plus a speak-or-type field for what
 * a chip can't say; picks and narration merge into one answer, parsed into a
 * draft that lands in the form prefilled. "Rather just fill in a form?" stays
 * for anyone who'd rather type fields.
 *
 * Drawn the way iOS draws it (`GuidedIntake.swift`): a plain white page, a
 * Cancel glass capsule beside the title in the display face, a thin accent
 * progress line, the question in bold with a grey line under it, grey FILLED
 * fields and chip cards (never an outline), and Back / Next as full-width
 * capsules pinned to a bar at the bottom.
 *
 * Every line is drawn in the app language (iOS ships this flow in English;
 * the Android keys live in strings_android.xml). Chip VALUES stay English on
 * purpose — they are what the parser reads and what a saved pick is keyed
 * by — and only their labels are translated ([intakeLabel]); the parser
 * writes the profile in the learner's own language whatever it is handed.
 */
@Composable
fun CounterpartIntakeScreen(
    nativeLanguage: String,
    targetLanguage: String,
    /** The parsed draft (or null for the plain form) and the photo picked on
     *  the first card — the person doesn't exist yet, so it rides along. */
    onDraft: (Counterpart?, Bitmap?) -> Unit,
    onCancel: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    // Screenshot harness (iOS `-intakeStep <n>`): jump to a card with
    // iOS's stand-in data. Null in every normal build.
    val standIn = remember { com.roro.futurevoice.capture.flags.WatchCaptureFlags.intakeStep
        ?.let { Step.entries.getOrNull(it) } }
    var step by remember { mutableStateOf(standIn ?: Step.WHO) }
    var name by remember { mutableStateOf(if (standIn != null) "Boram" else "") }
    var kind by remember { mutableStateOf(if (standIn != null) RelationshipKind.FELLOW_PARENT else null) }
    var kindDetail by remember { mutableStateOf("") }
    // How the two of them talk (iOS `ede039e`): prefilled from the
    // relationship chip so the card reads as a confirmation, until the
    // learner touches it.
    var myRegister by remember { mutableStateOf(SpeechRegister.POLITE) }
    var theirRegister by remember { mutableStateOf(SpeechRegister.POLITE) }
    var speechTouched by remember { mutableStateOf(false) }
    var iCallThem by remember { mutableStateOf("") }
    var theyCallMe by remember { mutableStateOf("") }
    LaunchedEffect(kind) {
        if (!speechTouched) {
            val (mine, theirs) = defaultRegisters(kind?.label)
            myRegister = mine; theirRegister = theirs
        }
    }
    // A public figure is name → "Public figure" → done: the model knows the
    // rest, so nothing else is asked (iOS `steps`).
    val steps = if (kind == RelationshipKind.PUBLIC_FIGURE) listOf(Step.WHO, Step.RELATIONSHIP)
        else Step.entries
    val stepIndex = steps.indexOf(step).coerceAtLeast(0)
    val isLast = stepIndex == steps.lastIndex
    androidx.activity.compose.BackHandler {
        if (step == Step.WHO) onCancel() else step = steps[(stepIndex - 1).coerceAtLeast(0)]
    }
    val answers = remember { mutableStateListOf("", "", "") }
    val chips = remember { mutableStateListOf<Set<String>>(emptySet(), emptySet(), emptySet()) }
    var interests by remember { mutableStateOf<Set<String>>(emptySet()) }
    var styleTraits by remember { mutableStateOf<Set<String>>(emptySet()) }
    var styleNotes by remember { mutableStateOf("") }
    var photo by remember { mutableStateOf<Bitmap?>(null) }
    var parsing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    // Answered IN the learner's own language by default: that's where people
    // say the most about someone they know.
    val locale = remember { LanguageCatalog.sttLocale(nativeLanguage) }

    val canAdvance = when (step) {
        Step.WHO -> name.isNotBlank()
        Step.RELATIONSHIP -> kind != null
        else -> true
    }

    /** What the speech card settled, onto the draft the form opens with. Only
     *  what the learner actually saw: a skipped card leaves the person on its
     *  cast's default (polite, never corrected). */
    fun applySpeech(draft: Counterpart): Counterpart {
        val withKind = draft.copy(relationshipKind = kind?.label)
        if (Step.SPEECH !in steps) return withKind
        return withKind.copy(myRegister = myRegister, theirRegister = theirRegister,
            iCallThem = iCallThem.trim(), theyCallMe = theyCallMe.trim())
    }

    fun parseAndContinue() {
        scope.launch {
            parsing = true; error = null
            val k = kind ?: RelationshipKind.OTHER
            // A public figure: the model already knows the person, so the
            // only question is WHICH one — look that up and hand the form an
            // identity to confirm. Not found still opens the form, where the
            // name can be fixed and looked up again.
            if (k == RelationshipKind.PUBLIC_FIGURE) {
                try {
                    val identity = PublicFigureLookup.identify(name.trim(), nativeLanguage)
                    onDraft(Counterpart(
                        name = name.trim(),
                        relationship = kindDetail.ifBlank { context.getString(k.title) },
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
            val kindLabel = listOf(k.label, kindDetail).filter { it.isNotBlank() }.joinToString(" — ")
            val styleLine = (styleTraits.joinToString(", ") +
                if (styleNotes.isBlank()) "" else ". $styleNotes").trim()
            val sections = mutableListOf("Their name: ${name.trim()}")
            if (kindLabel.isNotEmpty()) sections += "Relationship to me: $kindLabel"
            k.cards.forEachIndexed { i, card ->
                // Chip picks + whatever was spoken or typed form ONE answer.
                val parts = buildList {
                    if (chips[i].isNotEmpty()) add(chips[i].joinToString(", "))
                    answers[i].trim().takeIf { it.isNotEmpty() }?.let(::add)
                }
                if (parts.isNotEmpty()) sections += "Q: ${context.getString(card.question)}\nA: ${parts.joinToString(". ")}"
            }
            if (interests.isNotEmpty()) sections += "What they're into: ${interests.joinToString(", ")}"
            if (styleLine.isNotEmpty()) sections += "How they talk: $styleLine"
            val relationshipFallback = kindDetail.ifBlank { context.getString(k.title) }
            try {
                val draft = when {
                    // Nothing to extract — skip the model, straight to the form.
                    answers.all { it.isBlank() } && chips.all { it.isEmpty() } -> Counterpart(
                        name = name.trim(), relationship = relationshipFallback,
                        conversationStyle = styleLine, commonTopics = interests.joinToString(", "))
                    else -> CounterpartParser.parse(sections.joinToString("\n\n"), locale, nativeLanguage)
                        .copy(name = name.trim())
                }
                // The relationship card was required, so there always is one —
                // but the parser won't invent, and an empty relationship leaves
                // the form's Save greyed out.
                onDraft(applySpeech(draft.copy(
                    relationship = draft.relationship.ifBlank { relationshipFallback })), photo)
            } catch (e: Exception) {
                error = context.getString(R.string.intake_parse_failed, e.message.orEmpty())
            } finally {
                parsing = false
            }
        }
    }

    val page = MaterialTheme.colorScheme.surface
    Column(Modifier.fillMaxSize().background(page)) {
        // The navigation bar: Cancel as a glass capsule, the title centred
        // in the display face (iOS `.navigationBarTitleDisplayMode(.inline)`).
        val title = stringResource(R.string.tell_me_about_them)
        SheetHeader(title,
            leading = { IosGlassTextButton(stringResource(R.string.cancel), onClick = onCancel) },
            modifier = Modifier.statusBarsPadding().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 4.dp))
        IntakeProgress((stepIndex + 1f) / steps.size,
            Modifier.padding(horizontal = 20.dp).padding(top = 8.dp))
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // Keyed by card, so a card's unsubmitted "add your own" text is
            // folded into THAT card as it leaves, never carried to the next.
            androidx.compose.runtime.key(step) { when (step) {
                Step.WHO -> {
                    IntakeStepHeader(stringResource(R.string.intake_who_title),
                        stringResource(R.string.intake_who_detail))
                    // Their face, optional; saved small and square with the
                    // person, never sent anywhere.
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        PersonPhotoControl(image = photo?.asImageBitmap(), name = name, size = 96.dp,
                            onImage = { photo = it },
                            onRemove = if (photo == null) null else ({ photo = null }))
                        Text(androidx.compose.ui.res.stringResource(com.roro.futurevoice.R.string.a_photo_is_optional_without_one_their_initials_stand_in),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    FilledField(name, { name = it }, stringResource(R.string.their_name_as_you_call_them),
                        textStyle = MaterialTheme.typography.titleLarge,
                        capitalization = KeyboardCapitalization.Words)
                    Text(stringResource(R.string.rather_just_fill_in_a_form),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.align(Alignment.CenterHorizontally)
                            .clickable(interactionSource = remember { MutableInteractionSource() },
                                indication = null, role = Role.Button) { onDraft(null, photo) }
                            .padding(vertical = 4.dp))
                }
                Step.RELATIONSHIP -> {
                    IntakeStepHeader(stringResource(R.string.intake_relationship_title),
                        stringResource(R.string.intake_relationship_detail))
                    IntakeCard {
                        ChipGrid(RelationshipKind.entries.map { it.label }, setOfNotNull(kind?.label)) { tag ->
                            kind = RelationshipKind.entries.first { it.label == tag }
                        }
                        InlineField(kindDetail, { kindDetail = it }, stringResource(R.string.intake_more_precisely))
                    }
                    if (kind == RelationshipKind.PUBLIC_FIGURE) {
                        Text(stringResource(R.string.rel_public_figure_we_find_you_confirm),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                // How the learner and this person speak to each other. The
                // profile cards say who the person IS; nothing said how the
                // two of them TALK, so a best friend was voiced in polite
                // speech. Both directions: Korean and Japanese let them differ.
                Step.SPEECH -> {
                    val who = name.trim()
                    IntakeStepHeader(
                        if (who.isEmpty()) stringResource(R.string.rel_how_do_you_two_talk)
                        else stringResource(R.string.rel_how_do_you_and_s_talk, who),
                        stringResource(R.string.rel_calls_and_scenes_change_later))
                    Column(Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill())
                        .padding(14.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                        RegisterSegmentedRow(stringResource(R.string.rel_you_talk_to_them), myRegister,
                            targetLanguage, nativeLanguage) { speechTouched = true; myRegister = it }
                        RegisterSegmentedRow(
                            if (who.isEmpty()) stringResource(R.string.rel_they_talk_to_you)
                            else stringResource(R.string.rel_s_talks_to_you, who),
                            theirRegister, targetLanguage, nativeLanguage,
                        ) { speechTouched = true; theirRegister = it }
                    }
                    Column(Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill())) {
                        Box(Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
                            InlineField(iCallThem, { iCallThem = it },
                                stringResource(R.string.rel_what_you_call_them_optional))
                        }
                        androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 14.dp),
                            thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
                        Box(Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
                            InlineField(theyCallMe, { theyCallMe = it },
                                stringResource(R.string.rel_what_they_call_you_optional))
                        }
                    }
                }
                Step.NARRATIVE1, Step.NARRATIVE2, Step.NARRATIVE3 -> {
                    val i = step.ordinal - Step.NARRATIVE1.ordinal
                    val card = (kind ?: RelationshipKind.OTHER).cards[i]
                    IntakeStepHeader(stringResource(card.question), card.detail?.let { stringResource(it) }.orEmpty())
                    ChipPickerField(card.chips, chips[i], allowsCustom = true) { tag ->
                        chips[i] = if (tag in chips[i]) chips[i] - tag else chips[i] + tag
                    }
                    SpeakOrTypeField(
                        text = answers[i], onText = { answers[i] = it },
                        usedVoice = false, onUsedVoice = {},
                        placeholder = stringResource(R.string.intake_anything_more),
                        locale = locale,
                    )
                }
                Step.INTERESTS -> {
                    IntakeStepHeader(if (name.isBlank()) stringResource(R.string.intake_interests_title)
                        else stringResource(R.string.intake_interests_title_named, name.trim()),
                        stringResource(R.string.intake_interests_detail))
                    ChipPickerField(INTEREST_PRESETS, interests, allowsCustom = true) { tag ->
                        interests = if (tag in interests) interests - tag else interests + tag
                    }
                }
                Step.STYLE -> {
                    IntakeStepHeader(if (name.isBlank()) stringResource(R.string.intake_style_title)
                        else stringResource(R.string.intake_style_title_named, name.trim()),
                        if (name.isBlank()) stringResource(R.string.intake_style_detail)
                        else stringResource(R.string.intake_style_detail_named, name.trim()))
                    ChipPickerField(STYLE_PRESETS, styleTraits, allowsCustom = false) { tag ->
                        styleTraits = if (tag in styleTraits) styleTraits - tag else styleTraits + tag
                    }
                    FilledField(styleNotes, { styleNotes = it },
                        stringResource(R.string.intake_style_notes),
                        minLines = 2, maxLines = 4)
                }
            } }
            error?.let {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Warning, contentDescription = null, modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.error)
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
        }
        IntakeBottomBar(
            backVisible = step != Step.WHO,
            nextTitle = stringResource(if (isLast) R.string.continue_ else R.string.next),
            nextEnabled = canAdvance,
            working = parsing,
            onBack = { step = steps[(stepIndex - 1).coerceAtLeast(0)] },
            onNext = {
                if (isLast) parseAndContinue()
                else step = steps[stepIndex + 1]
            },
        )
    }
}

private enum class Step { WHO, RELATIONSHIP, SPEECH, NARRATIVE1, NARRATIVE2, NARRATIVE3, INTERESTS, STYLE }

// MARK: - The shared intake pieces (iOS `GuidedIntake.swift`)

/** iOS `secondarySystemBackground`: the grey an intake card or field sits
 *  on, over the white page. */
@Composable
private fun cardFill() = iosFill()

/** `ProgressView(value:total:)` — a 4 pt capsule track, the accent fill. */
@Composable
private fun IntakeProgress(fraction: Float, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(iosFill())) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(4.dp).clip(CircleShape)
            .background(MaterialTheme.colorScheme.primary))
    }
}

/** iOS `IntakeStepHeader`: `.title2.bold()` and a `.callout` grey line. */
@Composable
private fun IntakeStepHeader(question: String, detail: String) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(question, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (detail.isNotEmpty()) Text(detail, style = MaterialTheme.typography.bodyLarge.copy(
            fontSize = MaterialTheme.typography.bodyLarge.fontSize * (16f / 17f)),
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The grey rounded card chips and an inline field sit in (padding 14, r 12). */
@Composable
private fun IntakeCard(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill()).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
}

/** A filled text box (iOS `TextField` + `.padding(14)` on
 *  `secondarySystemBackground`, r 12) — no outline, the prompt as placeholder. */
@Composable
private fun FilledField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    textStyle: TextStyle = MaterialTheme.typography.bodyLarge,
    minLines: Int = 1,
    maxLines: Int = 1,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
) {
    val style = textStyle.copy(color = MaterialTheme.colorScheme.onSurface)
    BasicTextField(
        value = value, onValueChange = onChange, textStyle = style,
        singleLine = maxLines == 1, minLines = minLines, maxLines = maxOf(minLines, maxLines),
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(capitalization = capitalization),
        modifier = Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill()).padding(14.dp),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = style,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.28f))
                inner()
            }
        },
    )
}

/** A bare `TextField` inside a card: text and placeholder, nothing drawn around it. */
@Composable
private fun InlineField(value: String, onChange: (String) -> Unit, placeholder: String,
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
private fun IntakeChipLabel(text: String, isOn: Boolean, onClick: () -> Unit) {
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
 * iOS `ChipPickerField`: the chip grid in a grey card, and — with
 * [allowsCustom] — a bare "Add your own (comma-separated)" line under it.
 * What is typed there is folded in on Done and when the card leaves (Next),
 * split on commas; custom picks show as chips beside the presets.
 */
@Composable
private fun ChipPickerField(presets: List<String>, selection: Set<String>, allowsCustom: Boolean,
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
        ChipGrid(presets + selection.filter { it !in presets }, selection, onToggle)
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
private fun IntakeBottomBar(
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
private fun RowScope.CapsuleButton(enabled: Boolean, fill: androidx.compose.ui.graphics.Color,
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
 * The label a stored intake value is DRAWN with: relationship kinds, style
 * traits and every narrative chip. The value itself stays English (prompt
 * material, the selection key, `Counterpart.relationshipKind`); anything not
 * here — the interest presets, a learner's own typed chip — falls through to
 * [presetLabel], which shows a typed tag as written.
 */
private val INTAKE_LABELS: Map<String, Int> = mapOf(
    "Direct" to R.string.intake_style_direct,
    "Playful" to R.string.intake_style_playful,
    "Sarcastic" to R.string.intake_style_sarcastic,
    "Formal" to R.string.intake_style_formal,
    "Warm" to R.string.intake_style_warm,
    "Talkative" to R.string.intake_style_talkative,
    "Quiet" to R.string.intake_style_quiet,
    "Blunt" to R.string.intake_style_blunt,
    "Fast talker" to R.string.intake_style_fast_talker,
    "Careful" to R.string.intake_style_careful,
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
    "From school" to R.string.intake_chip_from_school,
    "From work" to R.string.intake_chip_from_work,
    "Through friends" to R.string.intake_chip_through_friends,
    "Online" to R.string.intake_chip_online,
    "Childhood friends" to R.string.intake_chip_childhood_friends,
    "Met recently" to R.string.intake_chip_met_recently,
    "Works full-time" to R.string.intake_chip_works_full_time,
    "Studying" to R.string.intake_chip_studying,
    "Recently moved" to R.string.intake_chip_recently_moved,
    "Raising kids" to R.string.intake_chip_raising_kids,
    "Lives nearby" to R.string.intake_chip_lives_nearby,
    "Lives abroad" to R.string.intake_chip_lives_abroad,
    "Inside jokes" to R.string.intake_chip_inside_jokes,
    "We tease each other" to R.string.intake_chip_we_tease_each_other,
    "Deep talks" to R.string.intake_chip_deep_talks,
    "Mostly banter" to R.string.intake_chip_mostly_banter,
    "Shared hobby" to R.string.intake_chip_shared_hobby,
    "They know everything about me" to R.string.intake_chip_they_know_everything_about_me,
    "Older sibling" to R.string.intake_chip_older_sibling,
    "Younger sibling" to R.string.intake_chip_younger_sibling,
    "Parent" to R.string.intake_chip_parent,
    "Grandparent" to R.string.intake_chip_grandparent,
    "Cousin" to R.string.intake_chip_cousin,
    "In-law" to R.string.intake_chip_in_law,
    "Busy with work" to R.string.intake_chip_busy_with_work,
    "Retired" to R.string.intake_chip_retired,
    "New hobby" to R.string.intake_chip_new_hobby,
    "Just moved" to R.string.intake_chip_just_moved,
    "Health ups and downs" to R.string.intake_chip_health_ups_and_downs,
    "Family news" to R.string.intake_chip_family_news,
    "Food and recipes" to R.string.intake_chip_food_and_recipes,
    "Health" to R.string.intake_chip_health,
    "Old memories" to R.string.intake_chip_old_memories,
    "Money and plans" to R.string.intake_chip_money_and_plans,
    "They nag me lovingly" to R.string.intake_chip_they_nag_me_lovingly,
    "Together for years" to R.string.intake_chip_together_for_years,
    "Newly dating" to R.string.intake_chip_newly_dating,
    "Met through friends" to R.string.intake_chip_met_through_friends,
    "Met online" to R.string.intake_chip_met_online,
    "Living together" to R.string.intake_chip_living_together,
    "Long distance" to R.string.intake_chip_long_distance,
    "Daily logistics" to R.string.intake_chip_daily_logistics,
    "Future plans" to R.string.intake_chip_future_plans,
    "Food and cooking" to R.string.intake_chip_food_and_cooking,
    "Travel plans" to R.string.intake_chip_travel_plans,
    "Work stories" to R.string.intake_chip_work_stories,
    "Our pets" to R.string.intake_chip_our_pets,
    "Playful teasing" to R.string.intake_chip_playful_teasing,
    "Pet names" to R.string.intake_chip_pet_names,
    "Lots of inside jokes" to R.string.intake_chip_lots_of_inside_jokes,
    "Calm and cozy" to R.string.intake_chip_calm_and_cozy,
    "We debate everything" to R.string.intake_chip_we_debate_everything,
    "They call me out" to R.string.intake_chip_they_call_me_out,
    "Same team" to R.string.intake_chip_same_team,
    "Cross-team" to R.string.intake_chip_cross_team,
    "We share projects" to R.string.intake_chip_we_share_projects,
    "Desk neighbors" to R.string.intake_chip_desk_neighbors,
    "Worked together for years" to R.string.intake_chip_worked_together_for_years,
    "They're new" to R.string.intake_chip_they_re_new,
    "Daily standups" to R.string.intake_chip_daily_standups,
    "Reviews" to R.string.intake_chip_reviews,
    "Lunch together" to R.string.intake_chip_lunch_together,
    "Coffee breaks" to R.string.intake_chip_coffee_breaks,
    "Mostly chat apps" to R.string.intake_chip_mostly_chat_apps,
    "Casual between us" to R.string.intake_chip_casual_between_us,
    "Deadline crunch" to R.string.intake_chip_deadline_crunch,
    "Office jokes" to R.string.intake_chip_office_jokes,
    "New project starting" to R.string.intake_chip_new_project_starting,
    "We vent together" to R.string.intake_chip_we_vent_together,
    "After-work drinks" to R.string.intake_chip_after_work_drinks,
    "Company changes going on" to R.string.intake_chip_company_changes_going_on,
    "My direct manager" to R.string.intake_chip_my_direct_manager,
    "Weekly 1:1s" to R.string.intake_chip_weekly_1_1s,
    "Manager for years" to R.string.intake_chip_manager_for_years,
    "New to me" to R.string.intake_chip_new_to_me,
    "Skip-level" to R.string.intake_chip_skip_level,
    "We talk daily" to R.string.intake_chip_we_talk_daily,
    "Project updates" to R.string.intake_chip_project_updates,
    "Feedback" to R.string.intake_chip_feedback,
    "Career growth" to R.string.intake_chip_career_growth,
    "Priorities" to R.string.intake_chip_priorities,
    "Pretty formal" to R.string.intake_chip_pretty_formal,
    "Fairly casual" to R.string.intake_chip_fairly_casual,
    "Direct style" to R.string.intake_chip_direct_style,
    "Supportive" to R.string.intake_chip_supportive,
    "Detail-oriented" to R.string.intake_chip_detail_oriented,
    "Big-picture person" to R.string.intake_chip_big_picture_person,
    "Busy calendar" to R.string.intake_chip_busy_calendar,
    "Knows my life a bit" to R.string.intake_chip_knows_my_life_a_bit,
    "Same Kita" to R.string.intake_chip_same_kita,
    "Same school" to R.string.intake_chip_same_school,
    "Same class" to R.string.intake_chip_same_class,
    "Playground friends" to R.string.intake_chip_playground_friends,
    "Kids are best friends" to R.string.intake_chip_kids_are_best_friends,
    "Known for years" to R.string.intake_chip_known_for_years,
    "Drop-off" to R.string.intake_chip_drop_off,
    "Pick-up" to R.string.intake_chip_pick_up,
    "Playdates" to R.string.intake_chip_playdates,
    "Birthday parties" to R.string.intake_chip_birthday_parties,
    "School events" to R.string.intake_chip_school_events,
    "The playground" to R.string.intake_chip_the_playground,
    "The kids" to R.string.intake_chip_the_kids,
    "School news" to R.string.intake_chip_school_news,
    "Logistics and schedules" to R.string.intake_chip_logistics_and_schedules,
    "Weekend plans" to R.string.intake_chip_weekend_plans,
    "Parenting tips" to R.string.intake_chip_parenting_tips,
    "Neighborhood news" to R.string.intake_chip_neighborhood_news,
    "Next door" to R.string.intake_chip_next_door,
    "Same building" to R.string.intake_chip_same_building,
    "Same street" to R.string.intake_chip_same_street,
    "Neighbors for years" to R.string.intake_chip_neighbors_for_years,
    "I moved in recently" to R.string.intake_chip_i_moved_in_recently,
    "They moved in recently" to R.string.intake_chip_they_moved_in_recently,
    "Hallway" to R.string.intake_chip_hallway,
    "Elevator" to R.string.intake_chip_elevator,
    "Garden or yard" to R.string.intake_chip_garden_or_yard,
    "On the street" to R.string.intake_chip_on_the_street,
    "Neighborhood events" to R.string.intake_chip_neighborhood_events,
    "Walking the dog" to R.string.intake_chip_walking_the_dog,
    "The weather" to R.string.intake_chip_the_weather,
    "Their family" to R.string.intake_chip_their_family,
    "Pets" to R.string.intake_chip_pets,
    "Home projects" to R.string.intake_chip_home_projects,
    "We trade favors" to R.string.intake_chip_we_trade_favors,
    "My teacher" to R.string.intake_chip_my_teacher,
    "My kid's teacher" to R.string.intake_chip_my_kid_s_teacher,
    "Language teacher" to R.string.intake_chip_language_teacher,
    "Music teacher" to R.string.intake_chip_music_teacher,
    "Sports coach" to R.string.intake_chip_sports_coach,
    "Known for a while" to R.string.intake_chip_known_for_a_while,
    "In class" to R.string.intake_chip_in_class,
    "Office hours" to R.string.intake_chip_office_hours,
    "Parent meetings" to R.string.intake_chip_parent_meetings,
    "Over messages" to R.string.intake_chip_over_messages,
    "Fairly relaxed" to R.string.intake_chip_fairly_relaxed,
    "Strict but fair" to R.string.intake_chip_strict_but_fair,
    "Encouraging" to R.string.intake_chip_encouraging,
    "Patient" to R.string.intake_chip_patient,
    "Talks fast" to R.string.intake_chip_talks_fast,
    "Recent school events" to R.string.intake_chip_recent_school_events,
    "I want to ask more questions" to R.string.intake_chip_i_want_to_ask_more_questions,
    "From a hobby" to R.string.intake_chip_from_a_hobby,
    "From the neighborhood" to R.string.intake_chip_from_the_neighborhood,
    "Busy lately" to R.string.intake_chip_busy_lately,
    "Recurring topics" to R.string.intake_chip_recurring_topics,
    "We meet regularly" to R.string.intake_chip_we_meet_regularly,
    "Mostly texting" to R.string.intake_chip_mostly_texting,
    "They know my life well" to R.string.intake_chip_they_know_my_life_well,
    "Still getting to know each other" to R.string.intake_chip_still_getting_to_know_each_other,
)

@Composable
private fun intakeLabel(tag: String): String =
    INTAKE_LABELS[tag]?.let { stringResource(it) } ?: presetLabel(tag)

private val STYLE_PRESETS = listOf(
    "Direct", "Playful", "Sarcastic", "Formal", "Warm",
    "Talkative", "Quiet", "Blunt", "Fast talker", "Careful",
)

// `PersonaOnboardingView.interestPresets` — the same list the learner's own
// intake offers.
private val INTEREST_PRESETS = listOf(
    "AI / tech", "parenting", "language learning", "music", "podcasts",
    "cooking", "travel", "sports", "fashion", "finance", "science", "art",
)

private val TAP_OR_TALK = R.string.intake_tap_or_talk
private val REAL = R.string.intake_real

/** A narrative card. The question and its grey line are chrome, so they are
 *  resources; the chip VALUES stay English — they are what the parser reads
 *  and what a saved pick is keyed by — and are only DRAWN translated
 *  ([intakeLabel]). */
private class NarrativeCard(@StringRes val question: Int, @StringRes val detail: Int?, val chips: List<String>)

/** Card 2's pick — each kind supplies the three narrative cards that follow
 *  (iOS `RelationshipKind`). Adding a kind or reworking copy happens only here. */
/** [label] is the STORED value (`Counterpart.relationshipKind`, read by
 *  `defaultRegisters` and the cast rules) and stays English; [title] is what
 *  the chip shows. */
private enum class RelationshipKind(val label: String, @StringRes val title: Int, val cards: List<NarrativeCard>) {
    FRIEND("Friend", R.string.intake_rel_friend, listOf(
        NarrativeCard(R.string.intake_q_how_did_you_two_meet, TAP_OR_TALK, listOf("From school", "From work", "Through friends", "Online", "Childhood friends", "Met recently")),
        NarrativeCard(R.string.intake_q_life_right_now, null, listOf("Works full-time", "Studying", "Recently moved", "Raising kids", "Lives nearby", "Lives abroad")),
        NarrativeCard(R.string.intake_q_just_between_you, REAL, listOf("Inside jokes", "We tease each other", "Deep talks", "Mostly banter", "Shared hobby", "They know everything about me")))),
    FAMILY("Family", R.string.intake_rel_family, listOf(
        NarrativeCard(R.string.intake_q_who_in_family, TAP_OR_TALK, listOf("Older sibling", "Younger sibling", "Parent", "Grandparent", "Cousin", "In-law")),
        NarrativeCard(R.string.intake_q_going_on_in_life, null, listOf("Busy with work", "Retired", "New hobby", "Just moved", "Raising kids", "Health ups and downs")),
        NarrativeCard(R.string.intake_q_you_two_usually_talk, REAL, listOf("Family news", "Food and recipes", "Health", "Old memories", "Money and plans", "They nag me lovingly")))),
    PARTNER("Partner", R.string.intake_rel_partner, listOf(
        NarrativeCard(R.string.intake_q_story_start, TAP_OR_TALK, listOf("Together for years", "Newly dating", "Met through friends", "Met online", "Living together", "Long distance")),
        NarrativeCard(R.string.intake_q_fills_conversations, null, listOf("Daily logistics", "Future plans", "Food and cooking", "Travel plans", "Work stories", "Our pets")),
        NarrativeCard(R.string.intake_q_dynamic, REAL, listOf("Playful teasing", "Pet names", "Lots of inside jokes", "Calm and cozy", "We debate everything", "They call me out")))),
    COWORKER("Coworker", R.string.intake_rel_coworker, listOf(
        NarrativeCard(R.string.intake_q_work_together, TAP_OR_TALK, listOf("Same team", "Cross-team", "We share projects", "Desk neighbors", "Worked together for years", "They're new")),
        NarrativeCard(R.string.intake_q_work_chats, null, listOf("Daily standups", "Reviews", "Lunch together", "Coffee breaks", "Mostly chat apps", "Casual between us")),
        NarrativeCard(R.string.intake_q_context_around, REAL, listOf("Deadline crunch", "Office jokes", "New project starting", "We vent together", "After-work drinks", "Company changes going on")))),
    MANAGER("Manager", R.string.intake_rel_manager, listOf(
        NarrativeCard(R.string.intake_q_working_relationship, TAP_OR_TALK, listOf("My direct manager", "Weekly 1:1s", "Manager for years", "New to me", "Skip-level", "We talk daily")),
        NarrativeCard(R.string.intake_q_usually_discuss, null, listOf("Project updates", "Feedback", "Career growth", "Priorities", "Pretty formal", "Fairly casual")),
        NarrativeCard(R.string.intake_q_what_else, REAL, listOf("Direct style", "Supportive", "Detail-oriented", "Big-picture person", "Busy calendar", "Knows my life a bit")))),
    FELLOW_PARENT("Fellow parent", R.string.intake_rel_fellow_parent, listOf(
        NarrativeCard(R.string.intake_q_families_connected, TAP_OR_TALK, listOf("Same Kita", "Same school", "Same class", "Playground friends", "Kids are best friends", "Known for years")),
        NarrativeCard(R.string.intake_q_run_into, null, listOf("Drop-off", "Pick-up", "Playdates", "Birthday parties", "School events", "The playground")),
        NarrativeCard(R.string.intake_q_you_two_talk, REAL, listOf("The kids", "School news", "Logistics and schedules", "Weekend plans", "Parenting tips", "Neighborhood news")))),
    NEIGHBOR("Neighbor", R.string.intake_rel_neighbor, listOf(
        NarrativeCard(R.string.intake_q_become_neighbors, TAP_OR_TALK, listOf("Next door", "Same building", "Same street", "Neighbors for years", "I moved in recently", "They moved in recently")),
        NarrativeCard(R.string.intake_q_chats_happen, null, listOf("Hallway", "Elevator", "Garden or yard", "On the street", "Neighborhood events", "Walking the dog")),
        NarrativeCard(R.string.intake_q_you_usually_talk, REAL, listOf("Neighborhood news", "The weather", "Their family", "Pets", "Home projects", "We trade favors")))),
    TEACHER("Teacher", R.string.intake_rel_teacher, listOf(
        NarrativeCard(R.string.intake_q_whose_teacher, TAP_OR_TALK, listOf("My teacher", "My kid's teacher", "Language teacher", "Music teacher", "Sports coach", "Known for a while")),
        NarrativeCard(R.string.intake_q_when_talk, null, listOf("In class", "Office hours", "Parent meetings", "Over messages", "Pretty formal", "Fairly relaxed")),
        NarrativeCard(R.string.intake_q_what_else, REAL, listOf("Strict but fair", "Encouraging", "Patient", "Talks fast", "Recent school events", "I want to ask more questions")))),
    /** Someone not in the learner's life — its own kind, not "Other": the
     *  profile is the public record, not the learner's guess. */
    PUBLIC_FIGURE("Public figure", R.string.public_figure, emptyList()),
    OTHER("Other", R.string.intake_rel_other, listOf(
        NarrativeCard(R.string.intake_q_know_each_other, TAP_OR_TALK, listOf("Through friends", "From work", "From a hobby", "From the neighborhood", "Online", "Met recently")),
        NarrativeCard(R.string.intake_q_life_like, null, listOf("Works full-time", "Studying", "Raising kids", "Lives nearby", "Lives abroad", "Busy lately")),
        NarrativeCard(R.string.intake_q_context_between, REAL, listOf("Recurring topics", "Inside jokes", "We meet regularly", "Mostly texting", "They know my life well", "Still getting to know each other")))),
}
