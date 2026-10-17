package com.roro.futurevoice.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import com.roro.futurevoice.data.BriefAttachmentCache
import com.roro.futurevoice.data.ScenarioAttachmentReader
import com.roro.futurevoice.talk.CounterpartIdeas
import com.roro.futurevoice.talk.ScenarioBrief
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.UnfoldMore
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import com.roro.futurevoice.ui.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.knowsLearnersLife
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.ScenarioIdeaCache
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.net.TopicClient
import com.roro.futurevoice.talk.PathIdeas
import com.roro.futurevoice.talk.PathIdeasContent
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.identityIn
import com.roro.futurevoice.talk.SuggestedTopic
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Symbols
import kotlinx.coroutines.launch

/**
 * The ONE scenario creator (iOS `ScenarioComposerSheet`) — "make your own
 * situation". Talk's "+" and every Watch flow land here.
 *
 * Three ways in, one field: pick a category and narrow it down, type the real
 * upcoming thing, or tap the mic and say it. Whatever route was taken, the
 * text stays editable — a prefill is a head start, never a script.
 *
 * Categorizing is a nicety and never blocks a commit (iOS rule): a failure
 * just leaves the free text as the scenario, with no breadcrumb.
 */
/** Which surface the CTA serves. Talk offers "Future self" (a call with no
 *  one attached is a call with your own fluent voice); Watch offers "From the
 *  situation" — nobody picked, and the scene casts the other side from what
 *  was written (iOS `Host`). */
enum class ComposerHost { TALK, WATCH }

/**
 * Which door the sheet opens on (iOS `ScenarioComposerSheet.Mode`). The two
 * are genuinely different screens, not one composer opened twice (iOS
 * `9fe8cc7`): [BROWSE] is tap-tap-tap — a category grid, a breadcrumb to undo
 * a step, and at the leaf the assembled sentence READ-ONLY — with no text
 * field at all; [CUSTOM] is the one-line BOX, where writing lives and ONLY
 * there, with the material attached as chips above it. Watch's "Your own
 * situation" opens CUSTOM; "Common situations" and every other caller BROWSE.
 */
enum class ComposerMode { BROWSE, CUSTOM }

/** One step of the composer's drill-down. */
private data class Crumb(
    val label: String,
    val icon: String?,
    /** The sentence this step writes into the box (iOS `Crumb.scenario`) —
     *  empty for a category, a chip's blurb for a narrowing pick. */
    val scenario: String = "",
)

/** Category + 2 narrowing picks. Past this the scenario is specific enough. */
private const val MAX_DEPTH = 3

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ScenarioComposer(
    targetLanguage: String,
    existingCategories: List<String>,
    /** A leaf dropped in by a caller — shown read-only on the browse door. */
    prefill: String = "",
    /** Who the scene is with, when the composer was opened from a face. */
    person: Counterpart? = null,
    /**
     * Which surface the composer serves. Talk offers "Future self" — a call
     * with no one attached is a call with your own fluent voice, the
     * product's core. Watch doesn't: a scene always needs an other person,
     * so its default partner is a character.
     */
    host: ComposerHost = ComposerHost.TALK,
    /** Which door the sheet opens on — see [ComposerMode]. */
    mode: ComposerMode = ComposerMode.BROWSE,
    /**
     * Called with the minted scenario once it is saved. Watch passes this to
     * play the scene straight away (iOS: the composer's CTA IS "Watch"); a
     * host that passes nothing just gets the scenario saved.
     */
    onCommitted: ((Scenario) -> Unit)? = null,
    /**
     * When set, the sheet EDITS this saved scenario instead of minting a new
     * one (iOS `editing:`): every field prefills from it, the commit keeps its
     * identity (id, book, mastery, history), and a delete row appears at the
     * bottom. Editing always uses the Form — never the box — whatever [mode].
     */
    editing: Scenario? = null,
    /** Edit mode only — remove the scenario, and with it its Practice book. */
    onDelete: (() -> Unit)? = null,
    onDismiss: () -> Unit,
    /**
     * Hosted IN the Watch tab under the people map rather than as a sheet
     * (iOS `embedded`, 2026-10-12): the box and its chips exactly as the
     * sheet draws them, with the map standing where the title and the
     * rolling examples were. The CTA rides at the end of the box's row.
     */
    embedded: Boolean = false,
    /** The other person, shared with the map (iOS `partnerSync`): picking
     *  here rings them there, and a pick on the map lands here. */
    partnerSync: Counterpart? = null,
    onPartnerSync: ((Counterpart?) -> Unit)? = null,
    /** A line handed in from outside, written into the box as if a reel line
     *  had been tapped (iOS `situationSync`); [onSituationTaken] clears it. */
    situationSync: String = "",
    onSituationTaken: () -> Unit = {},
    /** A category chip was tapped — the host picks who it is with. */
    onPickCategory: ((String) -> Unit)? = null,
    /** Off when the box was opened FOR someone (a person's "Make a
     *  situation"): that door is for describing, not browsing. */
    showsCategoryChips: Boolean = true,
    /** Open with the field focused and the keyboard up. */
    focusOnAppear: Boolean = false,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    /** The box is the writing door for a NEW situation only; editing keeps
     *  the Form, where the delete row and the category crumb live. */
    val usesBox = mode == ComposerMode.CUSTOM && editing == null
    var draft by remember { mutableStateOf(editing?.environment ?: prefill) }
    var committing by remember { mutableStateOf(false) }
    var path by remember { mutableStateOf<List<Crumb>>(emptyList()) }
    var options by remember { mutableStateOf<List<SuggestedTopic>>(emptyList()) }
    var loadingOptions by remember { mutableStateOf(false) }
    var optionsError by remember { mutableStateOf<String?>(null) }
    /** The tidy card summary — a picked chip's short label, or the model's
     *  paraphrase of typed text. Never the raw prompt. */
    var summary by remember { mutableStateOf(editing?.summary.orEmpty()) }
    var usedVoice by remember { mutableStateOf(false) }
    /** Raised in place of the CTA when the account can't pay for what it
     *  starts. Presented from THIS sheet, never from the host behind it: a
     *  sheet raised underneath an open sheet never appears, and the composer
     *  staying up means the situation just written is still there after. */
    var showPaywall by remember { mutableStateOf(false) }

    // WHO the other side is. nil = the future self (Talk only). Materialized
    // into CounterpartStore on commit, so downstream it is an ordinary person.
    // The host may already have picked them (a person's card, their bubble):
    // start on them, never on the default first — the map would fly to that
    // one and back.
    var partner by remember { mutableStateOf(person ?: partnerSync) }
    var pickingPartner by remember { mutableStateOf(false) }

    /** The material on this situation — links and files read where they
     *  live. Bytes go to [BriefAttachmentCache] at the pick; nothing is
     *  copied. Read ONCE, before the first scene. */
    var sources by remember { mutableStateOf(editing?.brief?.sources.orEmpty()) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var attachError by remember { mutableStateOf<String?>(null) }
    var addingLink by remember { mutableStateOf(false) }
    /** Relationship-grounded ideas for the attached person, for the reel.
     *  Held here too because a stranger isn't on file until a scenario is
     *  actually built with them. */
    var personIdeas by remember { mutableStateOf<List<SuggestedTopic>>(emptyList()) }
    var boxFocused by remember { mutableStateOf(false) }
    /** The box's text is the learner's own (iOS `customMode`): typed, or a
     *  reel line picked. The chips above the box give way to one mark. */
    var customMode by remember { mutableStateOf(false) }
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
    val boxFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    if (embedded) {
        LaunchedEffect(partner?.id) {
            if (partnerSync?.id != partner?.id) onPartnerSync?.invoke(partner)
        }
        LaunchedEffect(partnerSync?.id) {
            if (partnerSync != null && partnerSync.id != partner?.id) partner = partnerSync
        }
        LaunchedEffect(situationSync) {
            if (situationSync.isEmpty()) return@LaunchedEffect
            draft = situationSync
            customMode = true
            onSituationTaken()
        }
        LaunchedEffect(Unit) {
            if (!focusOnAppear) return@LaunchedEffect
            // After the box's rise, or the focus is lost mid-move.
            kotlinx.coroutines.delay(350)
            runCatching { boxFocus.requestFocus() }
        }
    }

    LaunchedEffect(Unit) {
        // Editing: the person the saved scenario was built with.
        if (editing != null && person == null) {
            val people = CounterpartStore.shared(context).load()
            partner = editing.counterpartId?.let { id -> people.firstOrNull { it.id == id } }
        }
        // Watch + nobody picked stays null: the situation decides who the
        // other side is (an empty `Scenario.role`, the scene's preset voice).
        // It used to open on the first built-in character, which was harmless
        // while the slot picked a VOICE and wrong once a person came with it
        // — a job interview played by someone with their own job and manner
        // (iOS `5217c2cc`). A legacy scenario with no person keeps its voice
        // the same way (`commit` carries voicePresetId). Talk with nobody
        // attached stays the fluent self.
        // Capture only (iOS `composerPreview`): Cafe already picked, with
        // sample ideas as its chips, so the narrowing step renders offline.
        com.roro.futurevoice.capture.flags.WatchCaptureFlags.composerPreviewIdeas?.let { ideas ->
            if (path.isEmpty() && mode == ComposerMode.BROWSE) {
                val cafe = PathIdeasContent.categories.first { it.title == "Cafe" }
                path = listOf(Crumb(cafe.title, cafe.icon))
                options = ideas
            }
        }
    }

    // What rolls past the box. With a person attached it is THEIR ideas —
    // grounded in the relationship, one call per person per language, kept on
    // the person. The generic examples are deliberately NOT the fallback
    // there: a landlord and a doctor mean nothing on a box opened from a
    // friend, so until theirs arrive the middle simply stays empty.
    LaunchedEffect(person?.id, mode) {
        val p = person ?: return@LaunchedEffect
        if (mode != ComposerMode.CUSTOM) return@LaunchedEffect
        val store = CounterpartStore.shared(context)
        val live = store.load().firstOrNull { it.id == p.id } ?: p
        val stored = live.scenariosByLanguage[targetLanguage].orEmpty()
        // A failed generation's generic lines, saved once by mistake, are no
        // ideas at all (iOS `TopicEngine.isFallback`).
        if (stored.isNotEmpty() && !CounterpartIdeas.isFallback(stored, live, targetLanguage)) {
            personIdeas = stored; return@LaunchedEffect
        }
        val learner = PersonaStore.shared(context).load()
        val fresh = runCatching {
            CounterpartIdeas.suggest(
                learner, live, targetLanguage,
                // Close people know the learner's life; everyone else hears
                // only what the learner lets strangers hear.
                learnerFacts = if (live.knowsLearnersLife) learner?.currentNotes()?.map { it.text }.orEmpty()
                    else learner?.strangerLines.orEmpty(),
                allowFallback = false,
            )
        }.getOrNull().orEmpty()
        if (fresh.isEmpty()) return@LaunchedEffect
        personIdeas = fresh
        // Persist only for someone already on file — a stranger becomes a
        // real row when a scenario is built with them, not when the sheet
        // that might build one opens.
        store.load().firstOrNull { it.id == p.id }?.let { owned ->
            store.save(owned.copy(scenariosByLanguage = owned.scenariosByLanguage + (targetLanguage to fresh)))
        }
    }
    val exampleLines = listOf(
        stringResource(R.string.a_final_round_interview_next_thursday_in_english_with_the_hi_60558a),
        stringResource(R.string.telling_my_landlord_the_heating_has_been_broken_for_three_we_9a0ae9),
        stringResource(R.string.meeting_my_partner_s_parents_for_the_first_time_over_dinner_7291f9),
        stringResource(R.string.explaining_a_symptom_i_ve_had_for_a_week_to_a_doctor_and_ask_7b3337),
        stringResource(R.string.asking_my_manager_for_a_raise_in_our_next_one_on_one_with_th_36621c),
        stringResource(R.string.returning_something_expensive_without_the_receipt_to_a_clerk_fccd8a),
    )
    val reelLines = if (person == null) exampleLines
    else personIdeas.map { it.blurb.trim().ifEmpty { it.title } }

    // Dictation language. The app language is what a situation gets described
    // in, but pinning it silently meant a learner who spoke the language they
    // are LEARNING got nonsense back with nothing on screen to explain why —
    // so the choice is visible and one tap away. Typing is language-agnostic.
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)
            // AppViewModel's key, spelled out: its companion is private, and
            // the composer only ever READS the choice made in setup / Me.
            .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative()
    }
    var dictationLocale by remember { mutableStateOf(nativeLanguage) }

    // MARK: Attaching — read where the file lives, never copied.
    fun addSource(read: ScenarioAttachmentReader.Read, label: String? = null, keepUri: Boolean = true) {
        val src = read.source.copy(
            label = label ?: read.source.label,
            androidUri = if (keepUri) read.source.androidUri else null)
        BriefAttachmentCache.put(src.id, read.data, read.mime)
        sources = sources + src
    }
    fun photoLabel() = context.getString(R.string.photo_lld,
        sources.count { it.kind == ScenarioBrief.Kind.IMAGE } + 1)
    val pickFiles = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        scope.launch {
            for (uri in uris) {
                try { addSource(ScenarioAttachmentReader.read(context, uri)) }
                catch (e: ScenarioAttachmentReader.ReadError) { attachError = e.describe(context) }
            }
        }
    }
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            // The photo picker's grant is temporary, so a photo is read now
            // and kept in memory only — like iOS, a photo has no way back.
            try { addSource(ScenarioAttachmentReader.read(context, uri), photoLabel(), keepUri = false) }
            catch (e: ScenarioAttachmentReader.ReadError) { attachError = e.describe(context) }
        }
    }
    val takePhoto = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bmp ->
        bmp ?: return@rememberLauncherForActivityResult
        val read = ScenarioAttachmentReader.read(bmp, photoLabel())
        if (read == null) attachError = context.getString(R.string.couldn_t_read_that_photo)
        else addSource(read)
    }
    fun attachLink(raw: String) {
        var text = raw.trim()
        if (text.isEmpty()) return
        if (!text.lowercase().startsWith("http://") && !text.lowercase().startsWith("https://")) {
            text = "https://$text"
        }
        val host = runCatching { java.net.URI(text).host }.getOrNull()
        if (host == null || !host.contains('.')) {
            attachError = context.getString(R.string.that_doesn_t_look_like_a_link); return
        }
        if (sources.any { it.kind == ScenarioBrief.Kind.LINK && it.label == text }) return
        sources = sources + ScenarioBrief.Source(kind = ScenarioBrief.Kind.LINK, label = text)
    }
    fun removeSource(src: ScenarioBrief.Source) {
        BriefAttachmentCache.drop(src.id)
        sources = sources.filterNot { it.id == src.id }
    }
    val attachActions = AttachActions(
        link = { addingLink = true },
        file = { pickFiles.launch(ScenarioAttachmentReader.pickerTypes) },
        photo = { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
        camera = { runCatching { takePhoto.launch(null) } },
    )

    suspend fun refreshOptions(force: Boolean = false) {
        val labels = path.map { it.label }
        if (labels.isEmpty() || labels.size >= MAX_DEPTH) { options = emptyList(); return }
        // The ideas are MATERIAL (target language); the labels are app-language
        // chrome — the language has to be in the key or a switch serves the
        // other language's ideas.
        val key = targetLanguage + "|" + ScenarioIdeaCache.key(person?.id, labels)
        if (!force) ScenarioIdeaCache.topics(context, key)?.let { options = it; return }
        // Level 1 of a preset category: shipped seeds, zero round-trip. The
        // sub-areas of "Cafe" are the same for everyone, and waiting on the
        // model for them costs the learner the pause right after their first
        // tap. "More" (force) asks the model here too.
        // The seeds are written in English, so they only stand in for an
        // English target; every other language asks the model.
        if (!force && person == null && labels.size == 1 && targetLanguage == "en") {
            PathIdeasContent.seedSubAreas(labels[0])?.let { seed ->
                options = seed.map { SuggestedTopic(title = it.title, blurb = it.blurb) }
                return
            }
        }
        loadingOptions = true; optionsError = null; options = emptyList()
        runCatching {
            PathIdeas.suggest(labels, PersonaStore.shared(context).load(), person, targetLanguage)
        }.onSuccess { result ->
            ScenarioIdeaCache.store(context, key, result)
            // Guard against a stale response (they navigated during the await).
            if (path.map { it.label } == labels) options = result
        }.onFailure { optionsError = context.getString(R.string.composer_ideaserr) }
        loadingOptions = false
    }

    // MARK: The box's category chips (iOS 7dbd60b4) — the same chain the
    // browse door walks, one row above the box.
    /** Move to a new path: the deepest step's sentence goes into the box,
     *  then that level's options load (iOS `navigate(to:)`). */
    fun navigate(newPath: List<Crumb>) {
        path = newPath
        customMode = false   // browsing chips, not free-typing
        newPath.lastOrNull()?.scenario?.takeIf { it.isNotEmpty() }?.let {
            draft = it          // this write isn't the learner typing
            focusManager.clearFocus()
        }
        scope.launch { refreshOptions() }
    }

    fun commit() {
        committing = true
        val text = draft.trim()
        scope.launch {
            // The CTA is the paid tap: the account is asked HERE, before
            // anything is generated. Blocked means the plans and nothing
            // else — no categorize call, no scenario minted.
            // Talk host = a call (iOS `blocks()`); Watch host = a scene,
            // which a free account with its free scenes spent can't start
            // (iOS `blocksScene()`) — it can still talk off its balance.
            val allowed = BillingGate.start(
                AuthRepository(),
                if (host == ComposerHost.WATCH) com.roro.futurevoice.data.VoiceRevival.Purpose.SCENE
                else com.roro.futurevoice.data.VoiceRevival.Purpose.CALL) { }
            if (!allowed && !BillingGate.showPaywall.value) {
                // Not the paywall: a PARKED voice's revival screen was closed
                // (see `VoiceRevival`). Nothing to buy; stay on the sheet.
                committing = false
                return@launch
            }
            if (!allowed) {
                // The gate raises the ROOT paywall, which would replace the
                // screen this sheet is on and lose the situation just
                // written. This sheet owns its own.
                BillingGate.showPaywall.value = false
                showPaywall = true
                committing = false
                return@launch
            }
            // Editing: the saved category and summary still describe the text
            // only while the text is unchanged; a rewrite is filed afresh.
            val textChanged = editing != null && editing.environment.trim() != text
            var categoryName = if (editing != null) editing.category.takeUnless { textChanged }
                else path.firstOrNull()?.label
            var icon = if (editing != null) editing.categoryIcon.takeUnless { textChanged }
                else path.firstOrNull()?.icon
            var sum = if (textChanged) "" else summary
            // Typed and never categorized → tidy it up now, so the card shows
            // a clean category + summary rather than the raw prompt.
            if (categoryName == null || sum.isBlank()) {
                runCatching {
                    TopicClient(AuthRepository()).categorize(
                        text = text,
                        existing = (PathIdeasContent.categories.map { it.title } +
                            existingCategories).distinct(),
                        iconOptions = TopicClient.ICON_PALETTE,
                        targetLanguage = targetLanguage)
                }.getOrNull()?.let { r ->
                    categoryName = categoryName ?: r.category.takeIf { it.isNotBlank() }
                    icon = icon ?: r.icon
                    if (sum.isBlank()) sum = r.summary
                }
            }
            // A picked character/user becomes a real row the moment a
            // scenario is built with them — from here on they are an
            // ordinary person.
            val who = partner
            if (who != null) {
                val store = CounterpartStore.shared(context)
                if (store.load().none { it.id == who.id }) store.save(who)
            }
            val scenario = if (editing != null) {
                // Edit in place: id, curriculum, mastery and history survive —
                // only the settings the sheet exposes change. Stored openers
                // were written for the OLD situation text, so a text change
                // invalidates them (they regenerate on the next talk).
                val e = editing
                val brief = when {
                    sources.isEmpty() -> null
                    // An unchanged source set keeps its reading; any change
                    // to the set asks for a new one.
                    e.brief != null && e.brief.sources.map { it.id } == sources.map { it.id } ->
                        e.brief.copy(sources = sources)
                    else -> ScenarioBrief(sources = sources)
                }
                e.copy(
                    environment = text,
                    openers = if (textChanged) null else e.openers,
                    openerCursor = if (textChanged) null else e.openerCursor,
                    role = if (who != null) roleLine(who)
                        else if (e.counterpartId != null) "" else e.role,
                    counterpartId = who?.id,
                    // An attached person IS the voice; with nobody attached a
                    // legacy scenario keeps the scene voice it already had.
                    voicePresetId = if (who != null) who.voicePresetId.takeIf { it.isNotBlank() }
                        else e.voicePresetId,
                    category = categoryName,
                    categoryIcon = icon,
                    summary = sum.takeIf { it.isNotBlank() },
                    brief = brief,
                )
            } else Scenario(
                environment = text,
                category = categoryName,
                categoryIcon = icon,
                summary = sum.takeIf { it.isNotBlank() },
                // An EMPTY role is what lets a scene infer its own
                // counterpart, so it stays empty when nobody was picked — and
                // for a stranger or a character, whose identity rides in the
                // prompt's counterpart block instead.
                role = roleLine(who),
                counterpartId = who?.id,
                // Android's scene reads the voice off the scenario, so an
                // attached person's preset has to be written here or the
                // scene plays in the default character's voice.
                voicePresetId = who?.voicePresetId?.takeIf { it.isNotBlank() },
                // The material rides on the scenario and is read ONCE,
                // before the first scene.
                brief = sources.takeIf { it.isNotEmpty() }?.let { ScenarioBrief(sources = it) },
            )
            ScenarioStore.shared(context).save(scenario, targetLanguage)
            StoreEvents.bump()
            committing = false
            onDismiss()
            onCommitted?.invoke(scenario)
        }
    }

    val playsScene = host == ComposerHost.WATCH && onCommitted != null
    // Talk's builder goes straight into the call (iOS ConversationHome:
    // `ctaTitle: "Talk", ctaIcon: "mic.fill"`).
    val startsCall = host == ComposerHost.TALK && onCommitted != null
    val ctaTitle = stringResource(when {
        playsScene -> R.string.watch
        startsCall -> R.string.talk
        else -> R.string.create
    })
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    /** The chips and the box — the bottom of the custom door, and all of the
     *  embedded one. One implementation, so the Watch tab's box can never
     *  drift from the sheet's. */
    val boxBottom: @Composable () -> Unit = {
        // The common situations, as chips right above the box: a
        // tap goes one step deeper in the same row (Cafe →
        // Ordering → …), and the last step writes its sentence
        // into the box, where it can still be changed. Once the
        // learner types, the row gives way to one mark saying
        // this one is theirs.
        androidx.compose.animation.Crossfade(
            targetState = customMode && draft.isNotBlank(),
            animationSpec = tween(250),
            modifier = Modifier.padding(bottom = if (showsCategoryChips || customMode) 10.dp else 0.dp),
            label = "chips",
        ) { custom ->
            if (custom) {
                Row(Modifier.fillMaxWidth().heightIn(min = 50.dp).padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.EditNote, contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp))
                    Text(stringResource(R.string.composer_customsituation),
                        style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.sp),
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else if (showsCategoryChips) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (path.isEmpty()) {
                        PathIdeasContent.categories.forEach { c ->
                            SoftChip(categoryTitle(c.title), icon = c.icon) {
                                onPickCategory?.invoke(c.title)
                                navigate(listOf(Crumb(c.title, c.icon)))
                            }
                        }
                    } else {
                        SoftChip(categoryTitle(path.last().label), back = true, selected = true) {
                            val back = path.dropLast(1)
                            if (back.isEmpty()) { path = emptyList(); options = emptyList() }
                            else navigate(back)
                        }
                        if (loadingOptions) {
                            CircularProgressIndicator(Modifier.padding(horizontal = 8.dp).size(16.dp),
                                strokeWidth = 2.dp)
                        } else if (path.size < MAX_DEPTH) {
                            options.forEach { o ->
                                SoftChip(o.title) {
                                    summary = o.title   // the chip's short label is the tidy card title
                                    navigate(path + Crumb(o.title, null, o.blurb.ifBlank { o.title }))
                                }
                            }
                        }
                    }
                }
            }
        }
        Column(
            Modifier.padding(horizontal = 12.dp).padding(bottom = 12.dp).fillMaxWidth()
                .clip(ContinuousShape(24.dp))
                .background(AppSurfaces.card)
                .padding(vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (sources.isNotEmpty()) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(horizontal = 14.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    sources.forEach { src -> AttachmentChip(src) { removeSource(src) } }
                }
                if (sources.any { it.kind != ScenarioBrief.Kind.LINK }) {
                    Text(stringResource(R.string.your_files_stay_on_your_phone_only_what_was_read_is_kept_her_ec86b8),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 14.dp))
                }
            }
            SpeakOrTypeField(
                text = draft,
                onText = {
                    draft = it
                    // A keystroke makes it the learner's own
                    // situation: the chips give way to a "Custom
                    // situation" mark, and a chip's category is
                    // dropped — the CTA files what was actually
                    // written. Emptied, the chips come back.
                    customMode = it.isNotBlank()
                    if (path.isNotEmpty()) { path = emptyList(); options = emptyList() }
                    summary = ""
                },
                usedVoice = usedVoice,
                onUsedVoice = { usedVoice = it },
                placeholder = stringResource(R.string.what_situation_should_we_build_the_more_detail_the_better),
                locale = LanguageCatalog.sttLocale(dictationLocale),
                plainMic = true,
                fieldModifier = Modifier.focusRequester(boxFocus).onFocusEvent { boxFocused = it.hasFocus },
                leadingControls = {
                    AttachMenuButton(attachActions)
                    // A fixed label when the box was opened from a
                    // person — the entry point chose them — and a
                    // free choice when it was opened from the tab.
                    if (person != null) PersonChip(person, host, fixed = true) {}
                    else PersonChip(partner, host, fixed = false) { pickingPartner = true }
                },
                trailingControls = {
                    DictationLanguagePill(dictationLocale) { dictationLocale = it }
                },
                // Hosted in the tab there is no header for the CTA, so it
                // rides at the end of the box's own row — and only once
                // there is something to watch.
                endControls = if (!embedded) null else ({
                    if (draft.isNotBlank()) {
                        Box(
                            Modifier.size(40.dp).clip(CircleShape)
                                .background(MaterialTheme.colorScheme.primary)
                                .clickable(enabled = !committing,
                                    role = androidx.compose.ui.semantics.Role.Button) { commit() }
                                .semantics { contentDescription = ctaTitle },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (committing) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp,
                                color = Color.White)
                            else Icon(if (playsScene) Icons.Filled.PlayArrow else Icons.Filled.Mic,
                                contentDescription = null, modifier = Modifier.size(20.dp), tint = Color.White)
                        }
                    }
                }),
            )
        }
    }
    /** Everything the box can raise, whichever way it is hosted. */
    val dialogs: @Composable () -> Unit = {
        if (pickingPartner) {
            PartnerPickerSheet(
                host = host,
                language = targetLanguage,
                current = partner,
                onPick = { partner = it; pickingPartner = false },
                onDismiss = { pickingPartner = false },
            )
        }

        if (addingLink) {
            var linkText by remember { mutableStateOf("") }
            AlertDialog(
                onDismissRequest = { addingLink = false },
                title = { Text(stringResource(R.string.paste_a_link)) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(stringResource(R.string.a_job_posting_a_listing_an_event_page_anything_about_the_sit_623078),
                            style = MaterialTheme.typography.bodyMedium)
                        OutlinedTextField(
                            value = linkText, onValueChange = { linkText = it },
                            placeholder = { Text("https://…", color = com.roro.futurevoice.ui.brand.iosPlaceholder()) }, singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                            modifier = Modifier.fillMaxWidth())
                    }
                },
                confirmButton = {
                    TextButton(onClick = { attachLink(linkText); addingLink = false }) {
                        Text(stringResource(R.string.add))
                    }
                },
                dismissButton = {
                    TextButton(onClick = { addingLink = false }) { Text(stringResource(R.string.cancel)) }
                },
            )
        }

        if (confirmingDelete) {
            AlertDialog(
                onDismissRequest = { confirmingDelete = false },
                title = { Text(stringResource(R.string.delete_this_scenario)) },
                text = { Text(stringResource(R.string.its_book_in_review_goes_with_it_study_items_and_mastery_incl_ad0876)) },
                confirmButton = {
                    TextButton(onClick = {
                        confirmingDelete = false
                        onDelete?.invoke()
                        onDismiss()
                    }) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
                },
                dismissButton = {
                    TextButton(onClick = { confirmingDelete = false }) { Text(stringResource(R.string.cancel)) }
                },
            )
        }

        attachError?.let { msg ->
            AlertDialog(
                onDismissRequest = { attachError = null },
                title = { Text(stringResource(R.string.couldn_t_attach_that)) },
                text = { Text(msg) },
                confirmButton = { TextButton(onClick = { attachError = null }) { Text(stringResource(R.string.ok)) } },
            )
        }

        // The plans, when the CTA can't be paid for — from HERE, so the sheet
        // (and the situation in it) survives being told no.
        if (showPaywall) PaywallDialog(onDismiss = { showPaywall = false })
    }
    if (embedded) {
        Column(Modifier.fillMaxWidth()) { boxBottom() }
        dialogs()
        return
    }

    // A SHEET, not a dialog: non-primary content lives in sheets (iOS UI
    // rules), and a dialog over a full-width composer reads as an alert.
    // FULL height, like iOS's `NavigationStack` presentation.
    ModalBottomSheet(
        onDismissRequest = { if (!committing) onDismiss() },
        sheetState = sheetState,
        dragHandle = null,
        containerColor = AppSurfaces.ground,
    ) {
        Column(Modifier.fillMaxSize().imePadding()) {
            // Cancel · title · the primary action. The CTA lives in the
            // HEADER on both doors (iOS `9fe8cc7`): one primary button, one
            // place, and the box's row never changes width with it.
            // iOS 26's inline bar: a glass Cancel, the title CENTRED in the
            // display face, and the prominent CTA as a toolbar circle — the
            // toolbar draws a Label icon-only, its title the button's name.
            val ready = draft.isNotBlank() && !committing
            SheetHeader(
                title = when {
                    usesBox -> stringResource(R.string.your_situation)
                    editing != null -> stringResource(R.string.edit_scenario)
                    person != null -> stringResource(R.string.a_scene_with_lls, person.name)
                    else -> stringResource(R.string.new_scenario)
                },
                leading = {
                    IosGlassTextButton(stringResource(R.string.cancel), onClick = onDismiss,
                        enabled = !committing)
                },
                trailing = {
                    Box(
                        Modifier.size(44.dp).clip(CircleShape)
                            .background(if (ready) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.18f))
                            .clickable(enabled = ready, role = androidx.compose.ui.semantics.Role.Button) { commit() }
                            .semantics { contentDescription = ctaTitle },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (committing) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp,
                            color = Color.White)
                        else Icon(when {
                                playsScene -> Icons.Filled.PlayArrow
                                startsCall -> Icons.Filled.Mic
                                else -> Icons.Filled.Add
                            },
                            contentDescription = null, modifier = Modifier.size(22.dp), tint = Color.White)
                    }
                },
                modifier = Modifier.padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 4.dp),
            )

            if (usesBox) {
                // MARK: The box — the writing door.
                Column(Modifier.weight(1f).fillMaxWidth().bottomBarInsets()) {
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = 32.dp).padding(top = 20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(stringResource(R.string.go_through_it_before_it_happens),
                            style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center)
                        Text(stringResource(R.string.the_more_you_write_the_closer_the_scene_lands_tap_to_bring_t_74325e),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center)
                    }
                    // Examples roll through the empty middle — the answer to
                    // "what do I even put here". They go the moment there IS
                    // something to write.
                    Box(Modifier.weight(1f).fillMaxWidth()
                        // The empty middle closes the keyboard when tapped.
                        .clickable(remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                            indication = null) { focusManager.clearFocus() },
                        contentAlignment = Alignment.Center) {
                        androidx.compose.animation.AnimatedVisibility(
                            visible = draft.isBlank() && !boxFocused && reelLines.isNotEmpty() && path.isEmpty(),
                            enter = androidx.compose.animation.fadeIn(tween(250)),
                            exit = androidx.compose.animation.fadeOut(tween(250)),
                        ) {
                            SituationReel(reelLines, onPick = { draft = it; customMode = true })
                        }
                    }
                    boxBottom()
                }
            } else Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState())
                    .bottomBarInsets()
                    .padding(horizontal = 20.dp).padding(bottom = 32.dp),
            ) {
                // MARK: The browse door — tap, tap, tap. Nothing here asks the
                // learner to WRITE (iOS `9fe8cc7`): the writing door is the
                // other one. The path needs somewhere to live so a step can
                // be undone, and it floats — a breadcrumb is where you are,
                // not content, so it has no card behind it (`9ebb3f4`).
                if (person != null) {
                    GroupedCard { PersonRow(person) }
                }
                if (editing != null) {
                    // MARK: Edit mode — the saved scenario, open for editing.
                    // Its field is live (iOS `overviewSection`): someone who
                    // reopens a saved card came to change the words. The
                    // saved category shows above it only while the text is
                    // still the text it was filed under.
                    GroupedSectionHeader(stringResource(R.string.your_scenario))
                    GroupedCard {
                        Column(Modifier.padding(vertical = 6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            val cat = editing.category?.takeIf { it.isNotBlank() }
                            if (cat != null && draft.trim() == editing.environment.trim()) {
                                Row(Modifier.padding(horizontal = 14.dp, vertical = 4.dp)) {
                                    CrumbChip(cat, editing.categoryIcon, selected = true) {}
                                }
                            }
                            SpeakOrTypeField(
                                text = draft,
                                onText = { draft = it },
                                usedVoice = usedVoice,
                                onUsedVoice = { usedVoice = it },
                                placeholder = stringResource(R.string.composer_placeholder),
                                locale = LanguageCatalog.sttLocale(dictationLocale),
                                plainMic = true,
                                trailingControls = {
                                    DictationLanguagePill(dictationLocale) { dictationLocale = it }
                                },
                            )
                        }
                    }
                }
                if (editing == null && path.isNotEmpty()) {
                    Row(
                        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                            .padding(top = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        path.forEachIndexed { i, crumb ->
                            if (i > 0) Icon(
                                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.outline,
                                modifier = Modifier.size(16.dp))
                            CrumbChip(crumb.label, crumb.icon, selected = i == path.lastIndex) {
                                // The CATEGORY crumb returns to the grid;
                                // deeper crumbs back up to that step.
                                path = if (i == 0) emptyList() else path.take(i + 1)
                                if (path.isEmpty()) { draft = ""; summary = "" }
                                scope.launch { refreshOptions() }
                            }
                        }
                    }
                }

                // MARK: Choices — the current drill level
                when {
                    editing != null -> Unit

                    path.isEmpty() && draft.isNotBlank() -> LeafSentence(draft, ctaTitle)

                    path.isEmpty() -> {
                        GroupedSectionHeader(stringResource(R.string.pick_a_category))
                        ChoiceGrid(PathIdeasContent.categories.map { it.title to it.icon }) { i ->
                            val c = PathIdeasContent.categories[i]
                            path = listOf(Crumb(c.title, c.icon))
                            scope.launch { refreshOptions() }
                        }
                    }

                    path.size < MAX_DEPTH || loadingOptions -> {
                        Row(
                            Modifier.fillMaxWidth().padding(top = 20.dp, bottom = 6.dp, start = 4.dp, end = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                stringResource(if (path.size == 1) R.string.narrow_it_down
                                else R.string.pick_a_scenario).uppercase(),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f))
                            if (loadingOptions) {
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            } else {
                                TextButton(
                                    onClick = { scope.launch { refreshOptions(force = true) } },
                                    contentPadding = PaddingValues(horizontal = 8.dp),
                                ) {
                                    Icon(Icons.Filled.Refresh, contentDescription = null,
                                        modifier = Modifier.size(16.dp))
                                    Spacer(Modifier.width(4.dp))
                                    Text(stringResource(R.string.more))
                                }
                            }
                        }
                        if (loadingOptions && options.isEmpty()) {
                            // Skeletons keep the grid the SAME shape while
                            // the model writes, so nothing jumps and the wait
                            // reads as "writing", not "broken".
                            SkeletonGrid()
                        } else {
                            ChoiceGrid(options.map { it.title to null }) { i ->
                                val o = options[i]
                                // The blurb IS the scenario if they stop here;
                                // one more step only narrows it.
                                draft = o.blurb.ifBlank { o.title }
                                summary = o.title
                                if (path.size < MAX_DEPTH) {
                                    path = path + Crumb(o.title, null)
                                    scope.launch { refreshOptions() }
                                } else options = emptyList()
                            }
                        }
                        optionsError?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                                modifier = Modifier.padding(top = 6.dp, start = 4.dp))
                        }
                        GroupedFooter(stringResource(
                            if (path.size == 1) R.string.pick_an_area_to_go_one_step_deeper
                            else R.string.tap_the_one_closest_to_what_you_re_going_in_to_do))
                    }

                    // The end of the drill-down: the assembled situation,
                    // READ-ONLY. Knowing what is about to be generated is not
                    // the same as being asked to write it.
                    else -> LeafSentence(draft, ctaTitle)
                }

                // MARK: The other person — one row, because the choice is a
                // person, not a setting: the detail lives in the picker.
                if (person == null) {
                    GroupedSectionHeader(stringResource(R.string.the_other_person))
                    GroupedCard {
                        Row(
                            Modifier.fillMaxWidth().clickable { pickingPartner = true }
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            PartnerAvatar(partner, host)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(partner?.name ?: noPartnerName(host),
                                    style = MaterialTheme.typography.bodyLarge)
                                Text(partnerCaption(partner, host),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Icon(Icons.Filled.UnfoldMore, contentDescription = null,
                                tint = MaterialTheme.colorScheme.outline,
                                modifier = Modifier.size(18.dp))
                        }
                    }
                    GroupedFooter(stringResource(
                        R.string.their_role_comes_from_the_situation_you_describe_here_you_pi_35598a))
                }

                // MARK: Material (edit mode) — the same attachments as a list,
                // so material can be added to a situation that started life
                // without any, or a stale posting taken off it.
                if (editing != null && host == ComposerHost.WATCH) {
                    MaterialSection(sources, attachActions, onRemove = { removeSource(it) })
                }

                // MARK: Delete (edit mode)
                if (editing != null && onDelete != null) {
                    GroupedSectionSpacer()
                    GroupedCard {
                        Row(
                            Modifier.fillMaxWidth().clickable { confirmingDelete = true }
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Icon(Icons.Filled.Delete, contentDescription = null,
                                tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(20.dp))
                            Text(stringResource(R.string.delete_scenario),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        }

        dialogs()
    }
}

/** The four ways to attach — each opens its own system picker. */
private class AttachActions(
    val link: () -> Unit,
    val file: () -> Unit,
    val photo: () -> Unit,
    val camera: () -> Unit,
)

/** "+" — the ways to attach, as one round control in the box's strip. */
@Composable
private fun AttachMenuButton(actions: AttachActions) {
    var open by remember { mutableStateOf(false) }
    Box {
        FilledTonalIconButton(
            onClick = { open = true },
            colors = IconButtonDefaults.filledTonalIconButtonColors(
                containerColor = com.roro.futurevoice.ui.brand.iosFill(),
                contentColor = MaterialTheme.colorScheme.onSurface),
        ) {
            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.attach_material))
        }
        com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.paste_a_link)) },
                leadingIcon = { Icon(Icons.Filled.Link, contentDescription = null) },
                onClick = { open = false; actions.link() })
            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.pick_a_file)) },
                leadingIcon = { Icon(Icons.Filled.Description, contentDescription = null) },
                onClick = { open = false; actions.file() })
            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.photo_library)) },
                leadingIcon = { Icon(Icons.Filled.PhotoLibrary, contentDescription = null) },
                onClick = { open = false; actions.photo() })
            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.take_a_photo)) },
                leadingIcon = { Icon(Icons.Filled.CameraAlt, contentDescription = null) },
                onClick = { open = false; actions.camera() })
        }
    }
}

/**
 * Who plays the other side, as one pill in the box's strip. The avatar is
 * BUILT at the pill's size — framing a bigger one down crops the slot, not
 * the circle, and the disc draws through the pill's edge (iOS `9fe8cc7`).
 * `fixed`: the box was opened from this person's card, so it is a label, not
 * a picker — offering to change it would undo the choice just made.
 */
@Composable
private fun PersonChip(p: Counterpart?, host: ComposerHost, fixed: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.height(40.dp).clip(CircleShape)
            .background(com.roro.futurevoice.ui.brand.iosFill())
            .then(if (fixed) Modifier else Modifier.clickable(onClick = onClick))
            .padding(start = 6.dp, end = 12.dp)
            .widthIn(max = 160.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (p == null) {
            Box(Modifier.size(28.dp)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape),
                contentAlignment = Alignment.Center) {
                Icon(noPartnerIcon(host), contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(14.dp))
            }
        } else PersonBubble(p.name, p.id, size = 28.dp)
        Text(p?.name ?: noPartnerName(host),
            style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The dictation language, wearing the same fill as the buttons beside it —
 *  bare, it read as loose text rather than a control. */
@Composable
private fun DictationLanguagePill(current: String, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val choices = remember { LanguageCatalog.nativeChoices() }
    Box {
        Row(
            Modifier.height(36.dp).clip(CircleShape)
                .background(com.roro.futurevoice.ui.brand.iosFill())
                .clickable { open = true }.padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(LanguageCatalog.endonym(current), style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            Icon(Icons.Filled.UnfoldMore, contentDescription = stringResource(R.string.language),
                tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(14.dp))
        }
        com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            choices.forEach { code ->
                com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(LanguageCatalog.endonym(code)) },
                    onClick = { onPick(code); open = false })
            }
        }
    }
}

/** One attached source above the line — its kind, its name, and a way out. */
@Composable
private fun AttachmentChip(src: ScenarioBrief.Source, onRemove: () -> Unit) {
    Row(
        Modifier.clip(ContinuousShape(10.dp))
            .background(com.roro.futurevoice.ui.brand.iosFill())
            .padding(start = 10.dp, end = 4.dp, top = 2.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(briefSourceIcon(src), contentDescription = null,
            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(14.dp))
        Text(briefChipLabel(src), style = MaterialTheme.typography.labelMedium,
            maxLines = 1, overflow = TextOverflow.MiddleEllipsis, modifier = Modifier.widthIn(max = 180.dp))
        IconButton(onClick = onRemove, modifier = Modifier.size(28.dp)) {
            Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.remove),
                tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
        }
    }
}

/**
 * The attachments as a list section — edit mode's Material (iOS
 * `materialSection`): each source with what the reading said about it, a way
 * to take it off, and the same four ways to attach as the box's "+".
 */
@Composable
private fun MaterialSection(
    sources: List<ScenarioBrief.Source>,
    actions: AttachActions,
    onRemove: (ScenarioBrief.Source) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    GroupedSectionHeader(stringResource(R.string.material))
    GroupedCard {
        Column {
            sources.forEach { src ->
                Row(
                    Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(briefSourceIcon(src), contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                    Column(Modifier.weight(1f)) {
                        Text(briefChipLabel(src), style = MaterialTheme.typography.bodyLarge,
                            maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
                        src.detail?.takeIf { it.isNotBlank() }?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = if (src.readOK) MaterialTheme.colorScheme.onSurfaceVariant
                                else MaterialTheme.colorScheme.error)
                        }
                    }
                    IconButton(onClick = { onRemove(src) }) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.remove),
                            tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
                    }
                }
            }
            Box {
                Row(
                    Modifier.fillMaxWidth().clickable { open = true }
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(Icons.Filled.Add, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                    Text(stringResource(R.string.attach_a_link_or_a_file),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.primary)
                }
                com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.paste_a_link)) },
                        leadingIcon = { Icon(Icons.Filled.Link, contentDescription = null) },
                        onClick = { open = false; actions.link() })
                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.pick_a_file)) },
                        leadingIcon = { Icon(Icons.Filled.Description, contentDescription = null) },
                        onClick = { open = false; actions.file() })
                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.photo_library)) },
                        leadingIcon = { Icon(Icons.Filled.PhotoLibrary, contentDescription = null) },
                        onClick = { open = false; actions.photo() })
                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.take_a_photo)) },
                        leadingIcon = { Icon(Icons.Filled.CameraAlt, contentDescription = null) },
                        onClick = { open = false; actions.camera() })
                }
            }
        }
    }
    GroupedFooter(stringResource(R.string.a_posting_a_listing_your_cv_it_s_read_once_before_the_first_3993e3))
}

/** The browse door's end: the assembled situation, read-only, above the CTA. */
@Composable
private fun LeafSentence(text: String, ctaTitle: String) {
    GroupedSectionSpacer()
    GroupedCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (text.isNotBlank()) Text(text, style = MaterialTheme.typography.bodyMedium)
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                Text(stringResource(R.string.specific_enough_it_or_tap_a_breadcrumb_to_explore_more, ctaTitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/**
 * What `Scenario.role` should say for an attached person. Your OWN people
 * carry their relationship ("my landlord") — the scene is about them. A
 * character or a pool stranger carries NOTHING: the situation casts the role
 * and the person plays it, their identity riding in the prompt's counterpart
 * block. Empty = the scene infers its own counterpart.
 */
private fun roleLine(who: Counterpart?): String {
    if (who == null) return ""
    if (who.remoteId != null) return ""
    return who.relationship.ifBlank { who.name }
}

internal fun partnerCaptionOf(p: Counterpart): String {
    val rid = p.remoteId
    if (rid != null && rid.startsWith("builtin:"))
        return StockPerson.by(p.voicePresetId).identityIn(com.roro.futurevoice.talk.VoicePreset.activeLanguage())
    if (rid == null) return p.relationship
    return p.location
}

@Composable
private fun partnerCaption(p: Counterpart?, host: ComposerHost): String =
    if (p == null) stringResource(if (host == ComposerHost.WATCH) R.string.whoever_the_situation_calls_for
        else R.string.your_own_voice_already_fluent)
    else partnerCaptionOf(p)

/** Nobody picked: Talk's call is with the future self; a Watch scene is with
 *  whoever the situation calls for. */
@Composable
private fun noPartnerName(host: ComposerHost): String =
    stringResource(if (host == ComposerHost.WATCH) R.string.from_the_situation else R.string.future_self_1384d5)

/** The fluent self has no face — it is a voice; the situation's person isn't
 *  known yet (iOS `person.fill.questionmark`). */
private fun noPartnerIcon(host: ComposerHost) =
    if (host == ComposerHost.WATCH) Icons.Filled.PersonSearch else Icons.Filled.GraphicEq

// MARK: - Rows and chips

@Composable
private fun PersonRow(p: Counterpart) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PersonBubble(p.name, p.id, size = 40.dp)
        Spacer(Modifier.width(12.dp))
        Column {
            Text(p.name, style = MaterialTheme.typography.bodyLarge)
            if (p.relationship.isNotBlank()) {
                Text(p.relationship, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PartnerAvatar(p: Counterpart?, host: ComposerHost = ComposerHost.TALK) {
    Box(
        Modifier.size(40.dp)
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (p == null) {
            Icon(noPartnerIcon(host), contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
        } else {
            PersonBubble(p.name, p.id, size = 40.dp)
        }
    }
}

/**
 * A quiet chip (iOS `SoftChipStyle`): the page's card colour and plain text,
 * so a row of choices reads as an offer, not as something that must be
 * picked. Only [selected] (where you are — a breadcrumb, the chosen tab)
 * wears the accent.
 */
@Composable
internal fun SoftChip(
    label: String,
    icon: String? = null,
    selected: Boolean = false,
    /** A back chip: a chevron where the icon goes. */
    back: Boolean = false,
    onClick: () -> Unit,
) {
    val interaction = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ink = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    Row(
        Modifier.graphicsLayer { alpha = if (pressed) 0.6f else 1f }
            .clip(CircleShape)
            .background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.14f) else AppSurfaces.card)
            .clickable(interaction, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (back) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = null, tint = ink,
                modifier = Modifier.size(18.dp))
        } else if (icon != null) {
            Icon(Symbols.icon(icon), contentDescription = null, tint = ink, modifier = Modifier.size(17.dp))
        }
        Text(label, style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.sp),
            fontWeight = FontWeight.Medium, color = ink, maxLines = 1)
    }
}

/** A preset category's name in the app language (iOS `explain(c.title)`);
 *  any other category — the learner's, the model's — as written. */
@Composable
internal fun categoryTitle(title: String): String = when (title) {
    "Cafe" -> stringResource(R.string.cafe)
    "Travel" -> stringResource(R.string.travel_22fb76)
    "Work" -> stringResource(R.string.work)
    "Health" -> stringResource(R.string.health)
    "Shopping" -> stringResource(R.string.shopping)
    "Social" -> stringResource(R.string.social)
    "School" -> stringResource(R.string.school)
    "Phone" -> stringResource(R.string.phone)
    else -> title
}

@Composable
private fun CrumbChip(label: String, icon: String?, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.clip(CircleShape)
            .background(
                if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
            .clickable(onClick = onClick)
            .padding(horizontal = 11.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (icon != null) {
            Icon(Symbols.icon(icon), contentDescription = null,
                tint = if (selected) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(14.dp))
        }
        Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1,
            color = if (selected) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurface)
    }
}

/**
 * Two equal columns, not wrap-to-fit: iOS lays these on an adaptive grid, so
 * the tiles line up down the page instead of stepping in and out with the
 * length of each phrase. A LazyVerticalGrid can't nest in a scrolling column,
 * and these lists are six items long — chunked rows are the honest shape.
 */
@Composable
private fun ChoiceGrid(items: List<Pair<String, String?>>, onPick: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.withIndex().chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEach { (i, item) ->
                    Row(
                        Modifier.weight(1f)
                            .fillMaxHeight()
                            .heightIn(min = 46.dp)
                            .clip(ContinuousShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                            .clickable { onPick(i) }
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        item.second?.let {
                            Icon(Symbols.icon(it), contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(18.dp))
                        }
                        Text(item.first, style = MaterialTheme.typography.bodyMedium,
                            maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun SkeletonGrid() {
    val fractions = listOf(0.72f, 0.48f, 0.63f, 0.80f, 0.55f, 0.68f)
    val transition = rememberInfiniteTransition(label = "skeleton")
    val pulse by transition.animateFloat(
        initialValue = 0.45f, targetValue = 0.9f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "pulse")
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        fractions.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEach { f ->
                    Box(
                        Modifier.weight(1f).height(46.dp)
                            .clip(ContinuousShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                            .padding(horizontal = 12.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        Box(
                            Modifier.fillMaxWidth(f).height(9.dp).alpha(pulse)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.25f)))
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

// MARK: - Partner picker

/**
 * Pick WHO the other side is, from the same people system everything else
 * uses: the learner's own people, real users from the Find-people pool, and
 * characters. Talk also offers "Future self" — a call with nobody attached is
 * a call with your own fluent voice.
 *
 * Own people and the built-in characters render instantly; the pool streams
 * in and quietly stays absent offline.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PartnerPickerSheet(
    host: ComposerHost,
    language: String,
    current: Counterpart?,
    onPick: (Counterpart?) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var known by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    var pool by remember { mutableStateOf<List<PublicPersonaClient.PublicPersona>>(emptyList()) }
    var poolLoading by remember { mutableStateOf(true) }
    // "New person" from inside the picker — the scene usually IS about
    // someone not on file yet. Whoever the intake saves is picked (iOS
    // `PartnerPickerSheet.showingNewPerson`), hosted the way Find people
    // hosts it: the one-card intake, then its draft in the person form.
    val scope = rememberCoroutineScope()
    var showingNewPerson by remember { mutableStateOf(false) }
    var idsBeforeNewPerson by remember { mutableStateOf<Set<String>>(emptySet()) }
    var newPersonDraft by remember { mutableStateOf<Counterpart?>(null) }
    var newPersonPhoto by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    var newPersonIsNew by remember { mutableStateOf(false) }
    LaunchedEffect(language) {
        known = CounterpartStore.shared(context).load()
        pool = runCatching { PublicPersonaClient(AuthRepository()).fetchPool(language) }
            .getOrDefault(emptyList())
        poolLoading = false
    }
    // A person already on disk is reused rather than minted again, so picking
    // the same character twice can never leave two rows behind.
    val existing = known
    val metLabel = stringResource(R.string.met_on_nawana)
    val own = remember(known) { known.filter { it.remoteId == null } }
    val characters = remember(pool, known) {
        val builtins = StockPerson.catalog.map { it.asCounterpart(existing) }
        val fetched = pool.filter { !it.isRealUser }.map { it.asCounterpart(existing, metLabel) }
        val seen = builtins.map { it.id }.toMutableSet()
        builtins + fetched.filter { seen.add(it.id) }
    }
    val users = remember(pool, known) {
        pool.filter { it.isRealUser }.map { it.asCounterpart(existing, metLabel) }
    }

    ModalBottomSheet(
        sheetState = com.roro.futurevoice.ui.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = onDismiss, containerColor = AppSurfaces.ground) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 32.dp),
        ) {
            Text(stringResource(R.string.the_other_person),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 4.dp))
            // The "nobody" row: Talk's future self, or Watch's "from the
            // situation" — the scene casts the other side itself, with no persona.
            GroupedSectionSpacer()
            GroupedCard {
                PickerRow(
                    name = noPartnerName(host),
                    caption = partnerCaption(null, host),
                    person = null,
                    selected = current == null,
                    host = host,
                ) { onPick(null) }
            }
            GroupedSectionHeader(stringResource(R.string.your_people))
            GroupedCard {
                own.forEachIndexed { i, p ->
                    if (i > 0) GroupedRowDivider()
                    PickerRow(p.name, partnerCaptionOf(p), p, current?.id == p.id) { onPick(p) }
                }
                if (own.isNotEmpty()) GroupedRowDivider()
                Row(
                    Modifier.fillMaxWidth().clickable {
                        idsBeforeNewPerson = known.filter { it.remoteId == null }.map { it.id }.toSet()
                        showingNewPerson = true
                    }.padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.AddCircle, contentDescription = null,
                            modifier = Modifier.size(26.dp), tint = MaterialTheme.colorScheme.primary)
                    }
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.new_person), style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.primary)
                }
            }
            if (users.isNotEmpty() || poolLoading) {
                GroupedSectionHeader(stringResource(R.string.people))
                GroupedCard {
                    users.forEachIndexed { i, p ->
                        if (i > 0) GroupedRowDivider()
                        PickerRow(p.name, partnerCaptionOf(p), p, current?.id == p.id) { onPick(p) }
                    }
                    if (poolLoading && users.isEmpty()) {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                            Text(stringResource(R.string.finding_people),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            GroupedSectionHeader(stringResource(R.string.characters))
            GroupedCard {
                characters.forEachIndexed { i, p ->
                    if (i > 0) GroupedRowDivider()
                    PickerRow(p.name, partnerCaptionOf(p), p, current?.id == p.id) { onPick(p) }
                }
            }
        }
    }

    if (showingNewPerson) {
        androidx.compose.ui.window.Dialog(
            onDismissRequest = { showingNewPerson = false },
            properties = androidx.compose.ui.window.DialogProperties(
                usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            DialogSystemBarsLikeActivity()
            CounterpartIntakeScreen(
                nativeLanguage = com.roro.futurevoice.core.UILanguage.current(context) ?: "en",
                targetLanguage = language,
                onDraft = { draft, photo ->
                    showingNewPerson = false
                    newPersonPhoto = photo
                    newPersonIsNew = draft == null
                    newPersonDraft = draft ?: Counterpart()
                },
                // Cancelling returns to the picker unchanged.
                onCancel = { showingNewPerson = false },
            )
        }
    }
    newPersonDraft?.let { draft ->
        PersonEditor(
            person = draft,
            onSave = { saved ->
                newPersonDraft = null; newPersonPhoto = null
                scope.launch {
                    val store = CounterpartStore.shared(context)
                    store.save(saved)
                    StoreEvents.bump()
                    val all = store.load()
                    known = all
                    // Whoever the intake saved is picked, and the picker closes.
                    val made = all.firstOrNull { it.remoteId == null && it.id !in idsBeforeNewPerson }
                    if (made != null) onPick(made)
                }
            },
            onDismiss = { newPersonDraft = null; newPersonPhoto = null },
            initialPhoto = newPersonPhoto,
            isNew = newPersonIsNew,
        )
    }
}

@Composable
private fun PickerRow(
    name: String,
    caption: String,
    person: Counterpart?,
    selected: Boolean,
    host: ComposerHost = ComposerHost.TALK,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PartnerAvatar(person, host)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyLarge)
            if (caption.isNotBlank()) {
                Text(caption, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (selected) {
            Icon(Icons.Filled.Check, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
        }
    }
}

// MARK: - Materializing a person

/** A built-in character as an ordinary person — reusing the row already on
 *  disk when there is one, so picking the same character twice is one row. */
private fun StockPerson.asCounterpart(existing: List<Counterpart>): Counterpart {
    val rid = "builtin:$voiceId"
    // Named for the language being practised (시안 in Korean, Paige in
    // English) — one row serves every target language (iOS `b49e91b`).
    val language = com.roro.futurevoice.talk.VoicePreset.activeLanguage()
    existing.firstOrNull { it.remoteId == rid || it.id == localId }?.let {
        return com.roro.futurevoice.talk.VoicePreset.localized(it, language)
    }
    return com.roro.futurevoice.talk.VoicePreset.localized(Counterpart(
        id = localId,
        name = name,
        intro = identity,
        voicePresetId = voiceId,
        remoteId = rid,
        personaKind = "character",
    ), language)
}

/** A pool persona as an ordinary person, the SAME one Find people and the
 *  Watch map materialize (iOS `PublicPersonaService.asCounterpart`): the
 *  saved row when they were met before, else a person whose local id IS
 *  the remote one — so the same stranger is one person everywhere and the
 *  pool's photo, adopted under that id, is theirs. Their voice is never a
 *  clone — the person on the other end is a stranger, not the fluent self. */
private fun PublicPersonaClient.PublicPersona.asCounterpart(
    existing: List<Counterpart>, metLabel: String,
): Counterpart = existing.firstOrNull { it.remoteId == id } ?: asCounterpart(metLabel)
