package com.roro.futurevoice.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.outlined.PlayCircle
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartPhotoStore
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.CounterpartCast
import com.roro.futurevoice.data.cast
import com.roro.futurevoice.data.knowsLearnersLife
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.captionIn
import com.roro.futurevoice.talk.nameIn
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.DisplayFace
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.IosRadius
import com.roro.futurevoice.ui.brand.IosSwitch
import kotlinx.coroutines.launch

/**
 * The learner's OWN people — the ones Watch's stories row is made of.
 * Strangers are a different sheet (`FindPeopleScreen`) and a different idea:
 * these are people whose relationship to the learner is the whole point, and
 * a scene with them is grounded in it.
 *
 * Kept deliberately short. A person is not a form to complete — name and
 * "who are they to you" is enough to run a scene, and everything below that
 * only sharpens it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PeopleSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { CounterpartStore.shared(context) }
    var people by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    var editing by remember { mutableStateOf<Counterpart?>(null) }
    var editingIsNew by remember { mutableStateOf(false) }

    suspend fun reload() { people = store.load().filter { it.remoteId == null } }
    LaunchedEffect(Unit) { reload() }

    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = onDismiss, containerColor = AppSurfaces.ground,
        dragHandle = null) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 16.dp).padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            SheetHeader(stringResource(R.string.people),
                trailing = { com.roro.futurevoice.ui.brand.IosGlassTextButton(
                    stringResource(R.string.done), onClick = onDismiss, bold = true) })
            FormCard {
                people.forEachIndexed { i, person ->
                    if (i > 0) FormDivider(inset = 68.dp)
                    Row(
                        Modifier.fillMaxWidth().clickable { editing = person; editingIsNew = false }
                            .padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        PersonBubble(person.name, person.id, size = 40.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(person.name, style = MaterialTheme.typography.bodyLarge)
                            if (person.caption.isNotEmpty()) {
                                Text(person.caption, style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        IconButton(onClick = {
                            scope.launch { store.delete(person.id); reload(); StoreEvents.bump() }
                        }) {
                            Icon(Icons.Filled.Delete,
                                contentDescription = stringResource(R.string.delete),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                if (people.isEmpty()) {
                    Text(stringResource(R.string.add_someone_you_actually_talk_to),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
                }
            }
            Spacer(Modifier.height(20.dp))
            FormCard {
                Text(stringResource(R.string.add_a_person),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.fillMaxWidth()
                        .clickable { editing = Counterpart(); editingIsNew = true }
                        .padding(horizontal = 16.dp, vertical = 11.dp))
            }
        }
    }

    editing?.let { draft ->
        PersonEditor(
            person = draft,
            isNew = editingIsNew,
            onSave = {
                scope.launch { store.save(it); reload(); StoreEvents.bump() }
                editing = null
            },
            onDismiss = { editing = null },
        )
    }
}

/**
 * The add/edit form (iOS `CounterpartFormView`): an inset-grouped `Form` in a
 * sheet — Cancel and Save as glass capsules in the header, the photo on the
 * page ground, then Who · Public info · About them · Your history together ·
 * How they talk · Voice · Anything else. Every text field is a row inside its
 * section's card with the prompt as the placeholder, never a floating label.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PersonEditor(
    person: Counterpart,
    onSave: (Counterpart) -> Unit,
    onDismiss: () -> Unit,
    /** A photo picked before the person existed (the intake's first card). */
    initialPhoto: android.graphics.Bitmap? = null,
    /** iOS titles the form "New persona" only when it opened with nothing
     *  (`initial == nil`); an intake draft or an existing person is "Edit". */
    isNew: Boolean = false,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var draft by remember(person.id) { mutableStateOf(person) }
    /** The photo to save with this person on Save; `removePhoto` = delete
     *  the one on file. Saved only on Save, so Cancel leaves the face alone. */
    var pendingPhoto by remember(person.id) { mutableStateOf(initialPhoto) }
    var removePhoto by remember(person.id) { mutableStateOf(false) }
    val onFile = rememberPersonPhoto(person.id)
    val shownPhoto = pendingPhoto?.asImageBitmap() ?: if (removePhoto) null else onFile
    var lookingUp by remember { mutableStateOf(false) }
    var lookupError by remember { mutableStateOf<String?>(null) }
    /** The voice list, pushed over the form like iOS's NavigationLink. */
    var pickingVoice by remember { mutableStateOf(false) }
    // Once there is something to lose, Cancel is the ONLY way out: a small
    // vertical drag while reaching for a field used to take the whole form
    // with it (iOS `32f20a1`).
    val dirty = draft != person || pendingPhoto != null || removePhoto
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { value ->
            value != androidx.compose.material3.SheetValue.Hidden || !dirty
        },
    )
    val prefs = remember { context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE) }
    val nativeLanguage = remember {
        prefs.getString("futurevoice.nativeLanguage", null)
            ?: com.roro.futurevoice.data.LanguageCatalog.defaultNative()
    }
    val targetLanguage = remember { prefs.getString("futurevoice.targetLanguage", null) ?: "en" }

    fun save() {
        val saved = draft.copy(voicePresetId = draft.voicePresetId.ifBlank {
            StockPerson.catalog.first().voiceId
        })
        val photo = pendingPhoto
        val drop = removePhoto
        scope.launch {
            when {
                photo != null -> CounterpartPhotoStore.save(context, saved.id, photo)
                drop -> CounterpartPhotoStore.delete(context, saved.id)
            }
        }
        onSave(saved)
    }

    ModalBottomSheet(
        onDismissRequest = { if (!dirty) onDismiss() },
        // Fully expanded from the start: the form is taller than a half
        // sheet, so a partial one hides Save and asks the learner to discover
        // a scroll before they can finish what they opened.
        sheetState = sheetState,
        containerColor = AppSurfaces.ground,
        dragHandle = null,
    ) {
        if (pickingVoice) {
            androidx.activity.compose.BackHandler { pickingVoice = false }
            VoicePresetPicker(
                selection = draft.voicePresetId.ifBlank { StockPerson.catalog.first().voiceId },
                targetLanguage = targetLanguage,
                onSelect = { draft = draft.copy(voicePresetId = it) },
                onBack = { pickingVoice = false },
            )
            return@ModalBottomSheet
        }
        Column(
            Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 16.dp).padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            val canSave = draft.isMinimallyComplete
            SheetHeader(
                stringResource(if (isNew) R.string.new_persona else R.string.edit_persona),
                leading = { com.roro.futurevoice.ui.brand.IosGlassTextButton(
                    stringResource(R.string.cancel), onClick = onDismiss) },
                trailing = {
                    IosGlassButton(onClick = { if (canSave) save() }) {
                        Text(stringResource(R.string.save), style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = if (canSave) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
                    }
                },
            )
            // Their face, optional — on the page ground, no card (iOS
            // `.listRowBackground(Color.clear)`).
            Box(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp), contentAlignment = Alignment.Center) {
                PersonPhotoControl(
                    image = shownPhoto, name = draft.name, size = 88.dp,
                    onImage = { pendingPhoto = it; removePhoto = false },
                    onRemove = if (shownPhoto == null) null else ({ pendingPhoto = null; removePhoto = true }),
                )
            }

            FormSection(
                header = stringResource(R.string.who),
                footer = stringResource(if (draft.isPublicFigure == true)
                    R.string.a_public_figure_s_profile_comes_from_public_coverage_their_v_f715e8
                else R.string.required_everything_below_is_optional_but_the_more_you_fill_1416ce),
            ) {
                FormTextRow(draft.name, { draft = draft.copy(name = it) }, stringResource(R.string.name),
                    capitalization = KeyboardCapitalization.Words)
                FormDivider()
                FormTextRow(draft.relationship, { draft = draft.copy(relationship = it) },
                    stringResource(R.string.relationship_e_g_best_friend_kita_parent_manager))
                FormDivider()
                // A public figure is a RELATIONSHIP, not "Other" (iOS
                // `59c6481`): their profile comes from public coverage, and
                // their voice is a preset like any stranger's.
                Row(
                    Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
                        .padding(start = 16.dp, end = 12.dp, top = 6.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(stringResource(R.string.public_figure), style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f))
                    IosSwitch(checked = draft.isPublicFigure == true,
                        onCheckedChange = { draft = draft.copy(isPublicFigure = if (it) true else null) })
                }
            }

            if (draft.isPublicFigure == true) {
                // The whole profile of a public figure: WHO it is, for the
                // learner to confirm. The model knows the rest (iOS `ede039e`).
                val found = !draft.publicIdentity.isNullOrBlank()
                FormSection(
                    header = stringResource(R.string.rel_who_they_are),
                    footer = when {
                        lookupError != null -> lookupError!!
                        found -> stringResource(R.string.rel_public_figure_found_footer)
                        draft.factsRefreshedAt != null -> stringResource(R.string.rel_public_figure_nobody_footer)
                        else -> stringResource(R.string.rel_public_figure_look_up_footer)
                    },
                    footerIsError = lookupError != null,
                ) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp)) {
                        Text(stringResource(R.string.who), style = MaterialTheme.typography.bodyLarge)
                        Spacer(Modifier.width(12.dp))
                        val shown = draft.publicIdentity?.takeIf { it.isNotBlank() }
                            ?: if (draft.factsRefreshedAt != null) stringResource(R.string.rel_not_found) else ""
                        Text(shown, style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.End,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                    }
                    FormDivider()
                    val enabled = !lookingUp && draft.name.isNotBlank()
                    Row(
                        Modifier.fillMaxWidth()
                            .clickable(enabled = enabled) {
                                lookingUp = true; lookupError = null
                                scope.launch {
                                    runCatching {
                                        com.roro.futurevoice.talk.PublicFigureLookup.identify(draft.name.trim(), nativeLanguage)
                                    }.onSuccess {
                                        draft = draft.copy(publicIdentity = it,
                                            factsRefreshedAt = System.currentTimeMillis())
                                    }.onFailure { lookupError = it.message }
                                    lookingUp = false
                                }
                            }
                            .padding(horizontal = 16.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        val tint = if (enabled) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
                        Icon(Icons.Filled.Search, contentDescription = null, tint = tint,
                            modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(stringResource(R.string.rel_look_up_again), color = tint,
                            style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                        if (lookingUp) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    }
                }
            } else {
                FormSection(stringResource(R.string.about_them)) {
                    FormTextRow(draft.location, { draft = draft.copy(location = it) },
                        stringResource(R.string.where_they_live_what_they_do), maxLines = 4)
                }
                FormSection(stringResource(R.string.your_history_together)) {
                    FormTextRow(draft.howWeMet, { draft = draft.copy(howWeMet = it) },
                        stringResource(R.string.how_you_met_and_how_long), maxLines = 3)
                    FormDivider()
                    FormTextRow(draft.background, { draft = draft.copy(background = it) },
                        stringResource(R.string.shared_context_memories_inside_jokes), minLines = 2, maxLines = 8)
                }
                FormSection(stringResource(R.string.how_they_talk)) {
                    FormTextRow(draft.conversationStyle, { draft = draft.copy(conversationStyle = it) },
                        stringResource(R.string.style_e_g_direct_loves_jokes_formal_careful), maxLines = 3)
                    FormDivider()
                    FormTextRow(draft.commonTopics, { draft = draft.copy(commonTopics = it) },
                        stringResource(R.string.what_you_usually_talk_about), maxLines = 3)
                }
            }
            // How the two of them talk, both directions (iOS `ede039e`). Calls
            // and scenes speak this way; "Automatic" leaves it to the
            // relationship, as every person made before this did.
            val ownPerson = draft.cast == CounterpartCast.OWN_PERSON
            FormSection(
                header = stringResource(R.string.rel_how_you_two_talk),
                footer = stringResource(if (ownPerson) R.string.rel_calls_and_scenes_knows_your_life
                    else R.string.rel_calls_and_scenes),
            ) {
                RegisterMenuRow(stringResource(R.string.rel_you_talk_to_them), draft.myRegister,
                    targetLanguage) { draft = draft.copy(myRegister = it) }
                FormDivider()
                RegisterMenuRow(stringResource(R.string.rel_they_talk_to_you), draft.theirRegister,
                    targetLanguage) { draft = draft.copy(theirRegister = it) }
                FormDivider()
                FormTextRow(draft.iCallThem, { draft = draft.copy(iCallThem = it) },
                    stringResource(R.string.rel_what_you_call_them))
                FormDivider()
                FormTextRow(draft.theyCallMe, { draft = draft.copy(theyCallMe = it) },
                    stringResource(R.string.rel_what_they_call_you))
                if (ownPerson) {
                    FormDivider()
                    Row(
                        Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
                            .padding(start = 16.dp, end = 12.dp, top = 6.dp, bottom = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(R.string.rel_knows_your_life), style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.weight(1f))
                        IosSwitch(checked = draft.knowsLearnersLife,
                            onCheckedChange = { draft = draft.copy(knowsMyLife = it) })
                    }
                }
            }
            // Never a clone — the person on the other end is someone else.
            FormSection(stringResource(R.string.voice)) {
                Row(
                    Modifier.fillMaxWidth().clickable { pickingVoice = true }
                        .padding(start = 16.dp, end = 12.dp, top = 11.dp, bottom = 11.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(stringResource(R.string.voice), style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f))
                    Text(StockPerson.by(draft.voicePresetId.ifBlank { null }).nameIn(targetLanguage),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    FormChevron()
                }
            }
            if (draft.isPublicFigure != true) {
                FormSection(stringResource(R.string.anything_else)) {
                    FormTextRow(draft.freeNotes, { draft = draft.copy(freeNotes = it) },
                        stringResource(R.string.free_notes_quirks_recent_events_anything_that_helps),
                        minLines = 2, maxLines = 6)
                }
            }
        }
    }
}

// MARK: - Voice picker with preview

/**
 * iOS `VoicePresetPickerView`: every voice can be HEARD before it's chosen.
 * The line is spoken in the target language (what the person will actually
 * speak) and cached per voice + text, so each voice costs one synthesis ever.
 */
@Composable
internal fun VoicePresetPicker(
    selection: String,
    targetLanguage: String,
    onSelect: (String) -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val player = remember { Mp3Player(context.cacheDir, source = "voice_preview") }
    var loadingId by remember { mutableStateOf<String?>(null) }
    var playingId by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf(false) }
    DisposableEffect(Unit) { onDispose { player.stop() } }

    fun preview(id: String) {
        if (playingId == id) { player.stop(); playingId = null; return }
        player.stop(); playingId = null; error = false
        val text = voicePreviewLine(targetLanguage)
        scope.launch {
            loadingId = id
            val audio = runCatching {
                // The voice speaking NOW — never a take an older voice of
                // this slot made before it got a native one (iOS `b49e91b`).
                com.roro.futurevoice.data.cachedSynthesis(context, voiceId = id, text = text,
                    purpose = "voice_preview", allowLineage = false)
            }.getOrNull()
            loadingId = null
            if (audio == null) { error = true; return@launch }
            playingId = id
            player.play(audio)
            if (playingId == id) playingId = null
        }
    }

    Column(
        Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 16.dp).padding(bottom = 32.dp)
            .verticalScroll(rememberScrollState()),
    ) {
        SheetHeader(stringResource(R.string.voice), leading = {
            IosGlassButton(onClick = onBack, circle = true) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = stringResource(R.string.back),
                    modifier = Modifier.size(28.dp))
            }
        })
        FormSection(
            header = null,
            footer = if (error) stringResource(R.string.couldn_t_play_audio)
            else stringResource(R.string.tap_to_hear_a_sample_in,
                com.roro.futurevoice.data.LanguageCatalog.ownName(targetLanguage,
                    com.roro.futurevoice.data.LanguageCatalog.defaultNative().let { d ->
                        context.getSharedPreferences("futurevoice", 0)
                            .getString("futurevoice.nativeLanguage", null) ?: d })),
            footerIsError = error,
        ) {
            StockPerson.catalog.forEachIndexed { i, v ->
                if (i > 0) FormDivider(inset = 56.dp)
                Row(
                    Modifier.fillMaxWidth().clickable { onSelect(v.voiceId) }
                        .padding(start = 12.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(Modifier.size(32.dp).clip(CircleShape).clickable { preview(v.voiceId) },
                        contentAlignment = Alignment.Center) {
                        when {
                            loadingId == v.voiceId ->
                                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            else -> Icon(
                                if (playingId == v.voiceId) Icons.Filled.StopCircle else Icons.Outlined.PlayCircle,
                                contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(28.dp))
                        }
                    }
                    Column(Modifier.weight(1f)) {
                        Text(v.nameIn(targetLanguage), style = MaterialTheme.typography.bodyLarge)
                        Text(v.captionIn(targetLanguage),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (selection == v.voiceId) {
                        Icon(Icons.Filled.Check, contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                    }
                }
            }
        }
    }
}

/** One neutral greeting per target language — phrasings that avoid
 *  speaker-gender agreement so any voice can say them (iOS `previewLine`).
 *  The `<break>` is ElevenLabs' pause tag: measured on the Korean line, the
 *  period after 반가워요 gave NO pause at all. It is spoken as silence, never
 *  read out; this line is audio only, never drawn as text. */
private fun voicePreviewLine(code: String): String = when (code.substringBefore("-")) {
    "es" -> "¡Hola! Qué alegría verte. <break time=\"0.5s\" /> ¿Empezamos?"
    "de" -> "Hallo! Schön, dich zu sehen. <break time=\"0.5s\" /> Sollen wir anfangen?"
    "fr" -> "Bonjour ! Ça me fait plaisir de te voir. <break time=\"0.5s\" /> On commence ?"
    "it" -> "Ciao! Che bello vederti. <break time=\"0.5s\" /> Iniziamo?"
    "pt" -> "Oi! Que bom te ver. <break time=\"0.5s\" /> Vamos começar?"
    "ja" -> "こんにちは！会えてうれしいです。<break time=\"0.5s\" />始めましょうか？"
    "ko" -> "안녕하세요! 만나서 반가워요. <break time=\"0.5s\" /> 시작해 볼까요?"
    "zh" -> "你好！很高兴见到你。<break time=\"0.5s\" />我们开始吧？"
    else -> "Hi! It's good to see you. <break time=\"0.5s\" /> Shall we get started?"
}

// MARK: - The photo control

/**
 * The big round photo control the intake and the form share (iOS
 * `PersonPhotoCircle` inside `PersonPhotoButton`): the photo when there is one,
 * the initials once a name is typed, else a grey person placeholder — with the
 * blue camera badge at its corner.
 */
@Composable
internal fun PersonPhotoControl(
    image: ImageBitmap?,
    name: String,
    size: Dp,
    onImage: (android.graphics.Bitmap) -> Unit,
    onRemove: (() -> Unit)?,
) {
    val accent = MaterialTheme.colorScheme.primary
    val badge = size * 0.3f
    Box(Modifier.size(size + 2.dp)) {
        PersonPhotoButton(onImage = onImage, onRemove = onRemove) {
            Box(Modifier.size(size).clip(CircleShape), contentAlignment = Alignment.Center) {
                when {
                    image != null -> Image(image, contentDescription = null, contentScale = ContentScale.Crop,
                        modifier = Modifier.size(size))
                    name.isNotBlank() -> Box(Modifier.size(size).background(accent.copy(alpha = 0.15f)),
                        contentAlignment = Alignment.Center) {
                        Text(initials(name), fontSize = (size.value * 0.36f).sp,
                            fontWeight = FontWeight.SemiBold, color = accent)
                    }
                    // `person.crop.circle.fill` in `.tertiary`.
                    else -> Icon(Icons.Filled.AccountCircle, contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.22f),
                        modifier = Modifier.requiredSize(size * 1.2f))
                }
            }
        }
        Box(
            Modifier.align(Alignment.BottomEnd).offset(x = 2.dp, y = 0.dp).size(badge)
                .background(accent, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.CameraAlt, contentDescription = null, tint = Color.White,
                modifier = Modifier.size(badge * 0.52f))
        }
    }
}

// MARK: - Form pieces (iOS inset-grouped Form)

/** A sheet's header: optional leading/trailing glass buttons, the title
 *  centred in the display face — iOS's inline navigation title, which stays
 *  centred until it would run into a button and then sits beside it. */
@Composable
internal fun SheetHeader(
    title: String,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    modifier: Modifier = Modifier.padding(top = 12.dp, bottom = 8.dp),
) {
    androidx.compose.ui.layout.Layout(
        content = {
            Box { leading?.invoke() }
            Text(title, style = DisplayFace.style(title, MaterialTheme.typography.bodyLarge),
                maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
            Box { trailing?.invoke() }
        },
        modifier = modifier.fillMaxWidth().height(48.dp),
    ) { m, c ->
        val w = c.maxWidth
        val h = c.maxHeight
        val gap = 12.dp.roundToPx()
        val loose = c.copy(minWidth = 0, minHeight = 0)
        val lead = m[0].measure(loose)
        val trail = m[2].measure(loose)
        val room = w - lead.width - trail.width - 2 * gap
        val t = m[1].measure(loose.copy(maxWidth = room.coerceAtLeast(0)))
        val minX = if (lead.width > 0) lead.width + gap else 0
        val maxX = w - t.width - (if (trail.width > 0) trail.width + gap else 0)
        val x = ((w - t.width) / 2).coerceAtLeast(minX).coerceAtMost(maxX.coerceAtLeast(minX))
        layout(w, h) {
            lead.place(0, (h - lead.height) / 2)
            t.place(x, (h - t.height) / 2)
            trail.place(w - trail.width, (h - trail.height) / 2)
        }
    }
}

/** A white card with iOS 26's continuous corners, rows edge to edge. */
@Composable
internal fun FormCard(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()
        .clip(ContinuousShape(IosRadius.groupedCard))
        .background(AppSurfaces.card), content = content)
}

/** Header · card · footer, spaced the way an inset-grouped section is. */
@Composable
internal fun FormSection(
    header: String?,
    footer: String? = null,
    footerIsError: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(top = 20.dp)) {
        header?.let {
            Text(it, style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, bottom = 8.dp))
        }
        FormCard(content)
        footer?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodySmall,
                color = if (footerIsError) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
        }
    }
}

/** A hairline between rows, inset to the text like iOS's separator. */
@Composable
internal fun FormDivider(inset: Dp = 16.dp) {
    HorizontalDivider(Modifier.padding(start = inset), thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outlineVariant)
}

@Composable
internal fun FormChevron() {
    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
        modifier = Modifier.padding(start = 4.dp).size(22.dp),
        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
}

/** A `TextField` row inside a Form card: the prompt is the placeholder. */
@Composable
internal fun FormTextRow(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    minLines: Int = 1,
    maxLines: Int = 1,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
) {
    val style = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface)
    BasicTextField(
        value = value, onValueChange = onChange,
        textStyle = style,
        singleLine = maxLines == 1,
        minLines = minLines, maxLines = maxOf(minLines, maxLines),
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(capitalization = capitalization),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = style,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
                    maxLines = if (maxLines == 1) 1 else Int.MAX_VALUE,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                inner()
            }
        },
    )
}
