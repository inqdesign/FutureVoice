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
 * The copy is English, exactly as iOS ships it: none of these lines is in the
 * iOS catalog either, so translating them is one job for both platforms.
 * Chip VALUES stay English on purpose — they are what the parser reads, and it
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
                        relationship = kindDetail.ifBlank { k.label },
                        relationshipKind = k.label,
                        isPublicFigure = true,
                        publicIdentity = identity,
                        factsRefreshedAt = System.currentTimeMillis(),
                    ), photo)
                } catch (e: Exception) {
                    error = "Couldn't look them up: ${e.message.orEmpty()}"
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
                if (parts.isNotEmpty()) sections += "Q: ${card.question}\nA: ${parts.joinToString(". ")}"
            }
            if (interests.isNotEmpty()) sections += "What they're into: ${interests.joinToString(", ")}"
            if (styleLine.isNotEmpty()) sections += "How they talk: $styleLine"
            val relationshipFallback = kindDetail.ifBlank { k.label }
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
                error = "Couldn't parse: ${e.message.orEmpty()}"
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
                    IntakeStepHeader("Who are we adding?",
                        "Someone you actually talk to — dialogues get simulated with them, in their manner.")
                    // Their face, optional; saved small and square with the
                    // person, never sent anywhere.
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        PersonPhotoControl(image = photo?.asImageBitmap(), name = name, size = 96.dp,
                            onImage = { photo = it },
                            onRemove = if (photo == null) null else ({ photo = null }))
                        Text("A photo is optional. Without one, their initials stand in.",
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
                    IntakeStepHeader("Who are they to you?",
                        "This shapes what I ask next — a manager and a best friend live in different worlds.")
                    IntakeCard {
                        ChipGrid(RelationshipKind.entries.map { it.label }, setOfNotNull(kind?.label)) { tag ->
                            kind = RelationshipKind.entries.first { it.label == tag }
                        }
                        InlineField(kindDetail, { kindDetail = it }, "More precisely? — e.g. College roommate")
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
                    IntakeStepHeader(card.question, card.detail)
                    ChipPickerField(card.chips, chips[i], allowsCustom = true) { tag ->
                        chips[i] = if (tag in chips[i]) chips[i] - tag else chips[i] + tag
                    }
                    SpeakOrTypeField(
                        text = answers[i], onText = { answers[i] = it },
                        usedVoice = false, onUsedVoice = {},
                        placeholder = "Anything more? Type — or tap the mic and talk.",
                        locale = locale,
                    )
                }
                Step.INTERESTS -> {
                    IntakeStepHeader(if (name.isBlank()) "What are they into?" else "What's ${name.trim()} into?",
                        "Tap what fits — these become what you two talk about.")
                    ChipPickerField(INTEREST_PRESETS, interests, allowsCustom = true) { tag ->
                        interests = if (tag in interests) interests - tag else interests + tag
                    }
                }
                Step.STYLE -> {
                    IntakeStepHeader(if (name.isBlank()) "How do they talk?" else "How does ${name.trim()} talk?",
                        "Tap what fits — the simulated ${name.trim().ifBlank { "person" }} should sound like the real one.")
                    ChipPickerField(STYLE_PRESETS, styleTraits, allowsCustom = false) { tag ->
                        styleTraits = if (tag in styleTraits) styleTraits - tag else styleTraits + tag
                    }
                    FilledField(styleNotes, { styleNotes = it },
                        "In your own words (optional) — e.g. switches to English when excited",
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
        presetLabel(text),
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

private const val TAP_OR_TALK = "Tap what fits, add your own — or just talk, your native language is fine."
private const val REAL = "This is what makes the dialogues feel real."

private class NarrativeCard(val question: String, val detail: String, val chips: List<String>)

/** Card 2's pick — each kind supplies the three narrative cards that follow
 *  (iOS `RelationshipKind`). Adding a kind or reworking copy happens only here. */
private enum class RelationshipKind(val label: String, val cards: List<NarrativeCard>) {
    FRIEND("Friend", listOf(
        NarrativeCard("How did you two meet?", TAP_OR_TALK, listOf("From school", "From work", "Through friends", "Online", "Childhood friends", "Met recently")),
        NarrativeCard("What's their life like right now?", "", listOf("Works full-time", "Studying", "Recently moved", "Raising kids", "Lives nearby", "Lives abroad")),
        NarrativeCard("What's just between you two?", REAL, listOf("Inside jokes", "We tease each other", "Deep talks", "Mostly banter", "Shared hobby", "They know everything about me")))),
    FAMILY("Family", listOf(
        NarrativeCard("Who are they in your family?", TAP_OR_TALK, listOf("Older sibling", "Younger sibling", "Parent", "Grandparent", "Cousin", "In-law")),
        NarrativeCard("What's going on in their life?", "", listOf("Busy with work", "Retired", "New hobby", "Just moved", "Raising kids", "Health ups and downs")),
        NarrativeCard("What do you two usually talk about?", REAL, listOf("Family news", "Food and recipes", "Health", "Old memories", "Money and plans", "They nag me lovingly")))),
    PARTNER("Partner", listOf(
        NarrativeCard("How did your story start?", TAP_OR_TALK, listOf("Together for years", "Newly dating", "Met through friends", "Met online", "Living together", "Long distance")),
        NarrativeCard("What fills your conversations these days?", "", listOf("Daily logistics", "Future plans", "Food and cooking", "Travel plans", "Work stories", "Our pets")),
        NarrativeCard("What's your dynamic like?", REAL, listOf("Playful teasing", "Pet names", "Lots of inside jokes", "Calm and cozy", "We debate everything", "They call me out")))),
    COWORKER("Coworker", listOf(
        NarrativeCard("How do you work together?", TAP_OR_TALK, listOf("Same team", "Cross-team", "We share projects", "Desk neighbors", "Worked together for years", "They're new")),
        NarrativeCard("What do your work chats look like?", "", listOf("Daily standups", "Reviews", "Lunch together", "Coffee breaks", "Mostly chat apps", "Casual between us")),
        NarrativeCard("What's the context around you two?", REAL, listOf("Deadline crunch", "Office jokes", "New project starting", "We vent together", "After-work drinks", "Company changes going on")))),
    MANAGER("Manager", listOf(
        NarrativeCard("What's your working relationship?", TAP_OR_TALK, listOf("My direct manager", "Weekly 1:1s", "Manager for years", "New to me", "Skip-level", "We talk daily")),
        NarrativeCard("What do you usually discuss?", "", listOf("Project updates", "Feedback", "Career growth", "Priorities", "Pretty formal", "Fairly casual")),
        NarrativeCard("What else should I know about them?", REAL, listOf("Direct style", "Supportive", "Detail-oriented", "Big-picture person", "Busy calendar", "Knows my life a bit")))),
    FELLOW_PARENT("Fellow parent", listOf(
        NarrativeCard("How are your families connected?", TAP_OR_TALK, listOf("Same Kita", "Same school", "Same class", "Playground friends", "Kids are best friends", "Known for years")),
        NarrativeCard("Where do you usually run into each other?", "", listOf("Drop-off", "Pick-up", "Playdates", "Birthday parties", "School events", "The playground")),
        NarrativeCard("What do you two talk about?", REAL, listOf("The kids", "School news", "Logistics and schedules", "Weekend plans", "Parenting tips", "Neighborhood news")))),
    NEIGHBOR("Neighbor", listOf(
        NarrativeCard("How did you become neighbors?", TAP_OR_TALK, listOf("Next door", "Same building", "Same street", "Neighbors for years", "I moved in recently", "They moved in recently")),
        NarrativeCard("Where do your chats happen?", "", listOf("Hallway", "Elevator", "Garden or yard", "On the street", "Neighborhood events", "Walking the dog")),
        NarrativeCard("What do you usually talk about?", REAL, listOf("Neighborhood news", "The weather", "Their family", "Pets", "Home projects", "We trade favors")))),
    TEACHER("Teacher", listOf(
        NarrativeCard("Whose teacher — and of what?", TAP_OR_TALK, listOf("My teacher", "My kid's teacher", "Language teacher", "Music teacher", "Sports coach", "Known for a while")),
        NarrativeCard("When do you talk with them?", "", listOf("In class", "Office hours", "Parent meetings", "Over messages", "Pretty formal", "Fairly relaxed")),
        NarrativeCard("What else should I know about them?", REAL, listOf("Strict but fair", "Encouraging", "Patient", "Talks fast", "Recent school events", "I want to ask more questions")))),
    /** Someone not in the learner's life — its own kind, not "Other": the
     *  profile is the public record, not the learner's guess. */
    PUBLIC_FIGURE("Public figure", emptyList()),
    OTHER("Other", listOf(
        NarrativeCard("How do you know each other?", TAP_OR_TALK, listOf("Through friends", "From work", "From a hobby", "From the neighborhood", "Online", "Met recently")),
        NarrativeCard("What's their life like?", "", listOf("Works full-time", "Studying", "Raising kids", "Lives nearby", "Lives abroad", "Busy lately")),
        NarrativeCard("What's the context between you?", REAL, listOf("Recurring topics", "Inside jokes", "We meet regularly", "Mostly texting", "They know my life well", "Still getting to know each other")))),
}
