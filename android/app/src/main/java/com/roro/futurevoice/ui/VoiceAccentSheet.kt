package com.roro.futurevoice.ui

import com.roro.futurevoice.core.Analytics
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PauseCircleFilled
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.VoiceAccent
import com.roro.futurevoice.data.VoiceAccentCatalog
import com.roro.futurevoice.net.VoiceRemixClient
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch

/**
 * Accent picker for the cloned voice — iOS `VoiceAccentSheet`, section for
 * section: pick an accent, audition a few remix takes of your OWN clone
 * speaking with it, keep the one that sounds most like you. Presented from
 * onboarding's meet act and from Me → Voice.
 *
 * The layout is iOS's inset-grouped List under an inline title with Cancel:
 * ① "Hear your voice" (headed "Your new voice is ready" right after a
 * re-record), ② Original + every accent as checkmark rows — a tap makes that
 * accent's takes at once, ③ the takes (a tap plays AND picks), ④ "Use this
 * voice". Applying replaces the live voice; the recording stays on the phone,
 * so the original is always rebuildable.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceAccentSheet(
    voiceId: String,
    targetLanguage: String,
    /** The accent the live clone was remixed with, if any. */
    appliedAccentId: String?,
    /** A voice was put in place — a take applied, or the accent removed
     *  (`accentId` empty). */
    onApplied: (voiceId: String, accentId: String) -> Unit,
    /**
     * Opened from an accent pill (the meet act, the revival screen): start
     * making this accent's takes at once, so the tap that picked the accent
     * is the one that asked (iOS `ce34464`). Listening and choosing stay the
     * learner's.
     */
    initialAccent: VoiceAccent? = null,
    /** Opened right after a re-record (iOS 2026-10-13, founder: the new
     *  voice closed the screen before it could be heard). Heads the sheet
     *  with the new voice to listen to, then the accent choice. */
    justMade: Boolean = false,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember { VoiceRemixClient(AuthRepository()) }
    val player = remember { Mp3Player(context.cacheDir, source = "accent_preview") }

    val options = remember(targetLanguage) { VoiceAccentCatalog.options(targetLanguage) }
    val appliedAccent = options.firstOrNull { it.id == appliedAccentId }
    var accent by remember { mutableStateOf<VoiceAccent?>(null) }
    /** The month's one voice change (iOS `canChangeVoice`, 2026-10-09). */
    val changeStatus by com.roro.futurevoice.data.VoiceChanges.status
        .collectAsStateWithLifecycle()
    val canChange = changeStatus?.canChange ?: true
    val againLine = com.roro.futurevoice.data.VoiceChangeStatus.againLine(context, changeStatus?.nextAt)
    LaunchedEffect(Unit) { com.roro.futurevoice.data.VoiceChanges.refresh() }
    var removing by remember { mutableStateOf(false) }
    var confirmingRemove by remember { mutableStateOf(false) }
    /** No recording on disk, no way back: "Original" can't be reached. */
    val canRemoveAccent = !appliedAccentId.isNullOrEmpty() &&
        VoiceComparison.exists(context.filesDir)
    var previews by remember { mutableStateOf<List<VoiceRemixClient.Preview>>(emptyList()) }
    var picked by remember { mutableStateOf<String?>(null) }
    var playing by remember { mutableStateOf<String?>(null) }
    var generating by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    DisposableEffect(Unit) { onDispose { runCatching { player.stop() } } }

    fun describe(e: Throwable): String =
        (e as? com.roro.futurevoice.data.VoiceChangeLimit)?.line(context)
            ?: (e as? com.roro.futurevoice.data.VoiceQuotaFull)?.line(context)
            ?: e.localizedMessage ?: e.toString()

    /** The voice as it is now, to listen to before picking anything. */
    var playingVoice by remember { mutableStateOf(false) }
    fun hearVoice() {
        if (playingVoice) { player.stop(); playingVoice = false; return }
        player.stop(); playing = null
        playingVoice = true
        scope.launch {
            runCatching {
                val data = com.roro.futurevoice.net.ElevenLabsClient(AuthRepository()).synthesize(
                    voiceId = voiceId, text = VoiceAccentCatalog.sampleText(targetLanguage),
                    purpose = "voice_comparison")
                player.play(data)
            }
            playingVoice = false
        }
    }

    /**
     * Pick an accent → its takes: the ones this recording already has, or
     * fresh ones. Re-tapping the accent whose takes are on screen
     * regenerates: "none of these sound like me" needs a way forward.
     * iOS `choose(_:)`.
     */
    fun choose(option: VoiceAccent) {
        player.stop(); playing = null; playingVoice = false
        // Takes this recording already has for this accent are shown, never
        // made again (`RemixTakeCache`). Only re-tapping the accent whose
        // takes are ON SCREEN asks for new ones.
        val regenerate = accent?.id == option.id && previews.isNotEmpty()
        accent = option
        picked = null
        if (!regenerate) {
            RemixTakeCache.get(context, option.id)?.let {
                previews = it
                Analytics.capture("voice_accent_previews_reused", mapOf("accent" to option.id))
                return
            }
        }
        // No change left this month: new takes could never be kept, so none
        // are made (the server would refuse them too).
        previews = emptyList()
        if (!com.roro.futurevoice.data.VoiceChanges.canChange) return
        generating = true
        Analytics.capture("voice_accent_previews_requested", mapOf("accent" to option.id))
        scope.launch {
            // No rebuild first (iOS 2026-10-09): the takes for every accent
            // are made at the clone (`remixIntoDefaultAccent`) and found
            // above; only when they are gone (a reinstall) are takes made
            // from the live voice.
            runCatching {
                client.previews(voiceId, option.prompt, VoiceAccentCatalog.sampleText(targetLanguage))
            }.onSuccess { takes ->
                RemixTakeCache.put(context, option.id, takes)
                // The learner may have tapped another accent while this ran.
                if (accent?.id == option.id) {
                    previews = takes
                    if (takes.isEmpty()) error = context.getString(R.string.no_takes_came_back_please_try_again)
                }
            }.onFailure { e ->
                if (e is kotlinx.coroutines.CancellationException) throw e
                // Said every time, and back to whatever is actually live.
                error = describe(e)
                if (accent?.id == option.id) accent = appliedAccent
            }
            generating = false
        }
    }

    /** Listening IS selecting: a tap plays the take and marks it as the one
     *  to keep; "Use this voice" does the committing. */
    fun audition(p: VoiceRemixClient.Preview) {
        picked = p.id
        if (playing == p.id) { player.stop(); playing = null; return }
        player.stop(); playingVoice = false
        playing = p.id
        scope.launch {
            runCatching { player.play(p.audio) }
            if (playing == p.id) playing = null
        }
    }

    fun apply() {
        val id = picked ?: return
        val chosen = accent ?: return
        player.stop(); playing = null
        saving = true
        scope.launch {
            runCatching {
                client.save(id,
                    // iOS sends `voiceDisplayName` — the library entry says whose it is.
                    com.roro.futurevoice.data.VoiceName.display(context,
                        com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName),
                    chosen.prompt)
            }.onSuccess { newId ->
                HapticEngine.success(context)
                onApplied(newId, chosen.id)
                onDismiss()
            }.onFailure { e ->
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (e is com.roro.futurevoice.data.VoiceChangeLimit) {
                    // Someone else's device used it first; say the date.
                    com.roro.futurevoice.data.VoiceChanges.refresh()
                } else {
                    // A remembered take can go stale upstream; the next pick
                    // of this accent makes fresh ones instead of failing again.
                    RemixTakeCache.drop(context, chosen.id)
                }
                error = describe(e)
            }
            saving = false
        }
    }

    /** Back to the voice the recording makes on its own (iOS `removeAccent`). */
    fun removeAccent() {
        if (removing) return
        player.stop(); playing = null
        removing = true
        Analytics.capture("voice_accent_removed")
        scope.launch {
            runCatching {
                com.roro.futurevoice.net.VoiceCloneClient(AuthRepository()).cloneVoice(
                    name = com.roro.futurevoice.data.VoiceName.display(context,
                        com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName),
                    sample = VoiceComparison.sampleFile(context.filesDir),
                    removeBackgroundNoise = false,
                )
            }.onSuccess { newId ->
                HapticEngine.success(context)
                onApplied(newId, "")
                onDismiss()
            }.onFailure { e ->
                if (e is kotlinx.coroutines.CancellationException) throw e
                error = describe(e)
            }
            removing = false
        }
    }

    LaunchedEffect(Unit) {
        if (justMade) hearVoice()
        // Show what's already live; or, opened from a pill, that accent's takes.
        val first = initialAccent?.let { a -> options.firstOrNull { it.id == a.id } }
        if (first != null) choose(first) else if (accent == null) accent = appliedAccent
    }

    // iOS `.interactiveDismissDisabled(generating || saving || removing)`:
    // the remix takes ~30 s, and a swipe would throw the request away.
    val busy by rememberUpdatedState(generating || saving || removing)
    ModalBottomSheet(
        sheetState = com.roro.futurevoice.ui.rememberModalBottomSheetState(
            skipPartiallyExpanded = true,
            confirmValueChange = { it != SheetValue.Hidden || !busy }),
        onDismissRequest = { if (!busy) { player.stop(); onDismiss() } },
        containerColor = AppSurfaces.ground,
    ) {
        // "Cancel", not "Done": nothing here is committed by leaving it.
        SheetHeader(
            title = stringResource(R.string.accent_233064),
            leading = {
                IosGlassTextButton(stringResource(R.string.cancel),
                    onClick = { player.stop(); onDismiss() },
                    enabled = !generating && !removing)
            },
            modifier = Modifier.padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 8.dp),
        )
        Column(Modifier.fillMaxWidth().bottomBarInsets().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp).padding(bottom = 28.dp)) {
            // ① The voice as it is now.
            FormSection(header = if (justMade) stringResource(R.string.your_new_voice_is_ready) else null) {
                AccentSheetRow(
                    title = stringResource(if (playingVoice) R.string.stop else R.string.hear_your_voice),
                    icon = if (playingVoice) Icons.Filled.StopCircle else Icons.Filled.PlayCircleFilled,
                    tinted = true,
                    enabled = !generating && !saving && !removing,
                    onClick = { hearVoice() })
            }

            // ② Original + the accents.
            FormSection(
                header = null,
                footer = when {
                    generating -> stringResource(R.string.making_a_few_takes_about_half_a_minute_keep_this_open)
                    !canChange -> againLine
                    else -> stringResource(R.string.your_clone_speaks_with_whatever_accent_the_ai_guesses_pick_o_a36d21)
                },
            ) {
                // "Original" is an option (iOS 2026-10-12): the voice as
                // recorded, checked whenever no accent is applied; with one
                // applied, a tap asks and rebuilds from the saved recording.
                AccentSheetRow(
                    title = stringResource(R.string.accent_original),
                    checked = appliedAccentId.isNullOrEmpty() && accent == null,
                    busy = removing,
                    enabled = !generating && !saving && !removing &&
                        (appliedAccentId.isNullOrEmpty() || (canRemoveAccent && canChange)),
                    onClick = { if (!appliedAccentId.isNullOrEmpty()) confirmingRemove = true })
                options.forEach { o ->
                    GroupedRowDivider(inset = false)
                    AccentSheetRow(
                        title = accentLabel(o),
                        checked = accent?.id == o.id,
                        busy = generating && accent?.id == o.id,
                        enabled = !generating && !saving && !removing,
                        onClick = { choose(o) })
                }
            }

            if (previews.isNotEmpty()) {
                // ③ The takes.
                FormSection(
                    header = stringResource(R.string.takes),
                    footer = stringResource(R.string.listen_to_each_take_and_keep_the_one_that_sounds_most_like_y_2ee5f5),
                ) {
                    previews.forEachIndexed { i, p ->
                        if (i > 0) GroupedRowDivider()
                        AccentSheetRow(
                            title = stringResource(R.string.take_lld, i + 1),
                            icon = if (playing == p.id) Icons.Filled.PauseCircleFilled
                                else Icons.Filled.PlayCircleOutline,
                            checked = picked == p.id,
                            enabled = !saving,
                            onClick = { audition(p) })
                    }
                }
                // ④ Keep it.
                FormSection(header = null, footer = if (canChange)
                    stringResource(R.string.replaces_your_current_voice_your_recording_is_kept_so_you_ca_dff313)
                    else againLine) {
                    AccentSheetRow(
                        title = stringResource(R.string.use_this_voice),
                        tinted = true,
                        busy = saving,
                        enabled = picked != null && !saving && canChange,
                        onClick = { apply() })
                }
            }
        }
    }

    if (confirmingRemove) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmingRemove = false },
            title = { Text(stringResource(R.string.remove_the_accent)) },
            text = { Text(stringResource(R.string.rebuilds_your_voice_from_your_saved_recording_which_takes_a_90f303)) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    confirmingRemove = false
                    removeAccent()
                }) { Text(stringResource(R.string.remove), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { confirmingRemove = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
    error?.let { msg ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { error = null },
            title = { Text(stringResource(R.string.couldn_t_remix_your_voice)) },
            text = { Text(msg) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { error = null }) {
                    Text(stringResource(R.string.ok))
                }
            },
        )
    }
}

/**
 * One row of the accent sheet, as iOS draws a `Button` in a `List`: an
 * optional accent glyph, the title (primary ink, or the accent for a row that
 * acts — "Hear your voice", "Use this voice"), then a spinner while it works
 * or the accent checkmark when it is the chosen one.
 */
@Composable
private fun AccentSheetRow(
    title: String,
    icon: ImageVector? = null,
    tinted: Boolean = false,
    checked: Boolean = false,
    busy: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    val alpha = if (enabled) 1f else 0.4f
    Row(
        Modifier.fillMaxWidth()
            .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier)
            .heightIn(min = 52.dp)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let {
            Icon(it, contentDescription = null, tint = accent.copy(alpha = alpha),
                modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(12.dp))
        }
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge,
            color = (if (tinted) accent else MaterialTheme.colorScheme.onSurface).copy(alpha = alpha))
        Box(contentAlignment = Alignment.Center) {
            if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            else if (checked) Icon(Icons.Filled.Check, contentDescription = null,
                tint = accent, modifier = Modifier.size(20.dp))
        }
    }
}


/**
 * The accent picked in setup (iOS `AppState.preferredAccentId`, 2026-10-08) —
 * what a new clone is remixed into. Null = the language's default.
 */
internal object PreferredAccent {
    private const val KEY = "futurevoice.preferredAccentId"
    /** "Keep my voice as recorded" (iOS `SetupFlowView.noAccent`): no remix
     *  at all. */
    const val NONE = "none"
    private fun prefs(c: android.content.Context) = c.getSharedPreferences("futurevoice", 0)
    fun get(c: android.content.Context): String? = prefs(c).getString(KEY, null)
    fun set(c: android.content.Context, id: String?) {
        prefs(c).edit().apply { if (id != null) putString(KEY, id) else remove(KEY) }.apply()
    }
}

/**
 * Remix takes already made from THIS recording, per accent id, for as long as
 * the process runs (iOS `AppState.remixTakeCache`, 2026-10-08). The accent
 * sheet used to drop its takes on close, so cancelling and reopening it on the
 * same accent paid for a fresh remix (~25 s and upstream credits) of the same
 * voice; the default-accent remix also gets several takes and keeps one.
 * Takes from the same recording are interchangeable whichever plain clone they
 * came from, so a rebuild of that clone doesn't invalidate them — a NEW
 * recording does ([recordingKey]).
 */
internal object RemixTakeCache {
    private var recording: String? = null
    private val takes = mutableMapOf<String, List<VoiceRemixClient.Preview>>()

    /** Which recording the voice is made from: the saved sample's size and
     *  date, which change with every new take. */
    private fun recordingKey(context: android.content.Context): String? {
        val f = VoiceComparison.sampleFile(context.filesDir)
        if (!f.exists()) return null
        return "${f.length()}-${f.lastModified() / 1000}"
    }

    /** Kept on disk too (iOS 2026-10-08): a memory-only cache was gone after
     *  the app was closed, and reopening the sheet paid for the same remix
     *  again. `cacheDir/accent-takes/<recordingKey>/` holds one
     *  `<accentId>.json` manifest ([{id, file}]) and `<accentId>-<i>.mp3`
     *  per take — only the current recording's folder is ever there. */
    private fun root(context: android.content.Context) = java.io.File(context.cacheDir, "accent-takes")

    @kotlinx.serialization.Serializable
    private data class StoredTake(val id: String, val file: String)

    private val manifestSerializer =
        kotlinx.serialization.builtins.ListSerializer(StoredTake.serializer())

    @Synchronized
    fun get(context: android.content.Context, accentId: String): List<VoiceRemixClient.Preview>? {
        val key = recordingKey(context) ?: return null
        if (recording == key) takes[accentId]?.let { return it }
        // From disk: only this recording's folder is ever there. Every file
        // the manifest names must be present, or it is a miss.
        val dir = java.io.File(root(context), key)
        val stored = runCatching {
            kotlinx.serialization.json.Json.decodeFromString(manifestSerializer,
                java.io.File(dir, "$accentId.json").readText())
        }.getOrNull() ?: return null
        val loaded = stored.mapNotNull { t ->
            runCatching { VoiceRemixClient.Preview(t.id, java.io.File(dir, t.file).readBytes()) }.getOrNull()
        }
        if (loaded.size != stored.size || loaded.isEmpty()) return null
        if (recording != key) { recording = key; takes.clear() }
        takes[accentId] = loaded
        return loaded
    }

    @Synchronized
    fun put(context: android.content.Context, accentId: String, list: List<VoiceRemixClient.Preview>) {
        val key = recordingKey(context) ?: return
        if (recording != key) { recording = key; takes.clear() }
        if (list.isEmpty()) takes.remove(accentId) else takes[accentId] = list
        runCatching {
            val root = root(context)
            // Another recording's takes can never be shown again.
            root.listFiles()?.forEach { if (it.name != key) it.deleteRecursively() }
            val dir = java.io.File(root, key)
            val manifest = java.io.File(dir, "$accentId.json")
            if (list.isEmpty()) { manifest.delete(); return@runCatching }
            dir.mkdirs()
            val stored = list.mapIndexed { i, take ->
                val file = "$accentId-$i.mp3"
                java.io.File(dir, file).writeBytes(take.audio)
                StoredTake(take.id, file)
            }
            manifest.writeText(kotlinx.serialization.json.Json.encodeToString(manifestSerializer, stored))
        }
    }

    /** A remembered take went stale upstream: forget this accent's set,
     *  on disk too, so the next pick makes fresh ones. */
    fun drop(context: android.content.Context, accentId: String) = put(context, accentId, emptyList())
}

/**
 * The remix half of iOS `AppState.applyDefaultAccent` (2026-10-08): remix
 * [voiceId] — a clone straight off the recording — into the target language's
 * default accent (`VoiceAccentCatalog.defaultAccent`) and keep the FIRST take.
 * The accent is the point here; the learner can still audition takes or
 * another accent from the pills. Best-effort: null (and
 * `voice_accent_default_failed`) on any failure, which leaves the plain
 * clone — it works. Null without a capture when the language has no default.
 * The caller adopts the returned voice (and deletes the outgoing one).
 */
internal suspend fun remixIntoDefaultAccent(
    context: android.content.Context,
    voiceId: String,
    targetLanguage: String,
): Pair<String, VoiceAccent>? {
    // The accent picked in setup, when it is one of this target's options;
    // else the language's default (iOS `applyDefaultAccent`).
    // Picked "as I recorded it" in setup: no remix.
    if (PreferredAccent.get(context) == PreferredAccent.NONE) return null
    val accent = VoiceAccentCatalog.options(targetLanguage)
        .firstOrNull { it.id == PreferredAccent.get(context) }
        ?: VoiceAccentCatalog.defaultAccent(targetLanguage) ?: return null
    val client = VoiceRemixClient(AuthRepository())
    // Takes for EVERY accent of the language, in parallel, while the plain
    // clone still exists (iOS 2026-10-09). Takes add no voice, and once the
    // remix below replaces the clone, takes for another accent would need the
    // clone rebuilt first — a whole voice spent just to LISTEN. With these on
    // file a later accent change is one save, nothing else.
    val text = VoiceAccentCatalog.sampleText(targetLanguage)
    val made: Map<String, List<VoiceRemixClient.Preview>> = kotlinx.coroutines.coroutineScope {
        VoiceAccentCatalog.options(targetLanguage).map { option ->
            async {
                option.id to runCatching {
                    client.previews(voiceId, option.prompt, text, VoiceAccentCatalog.PROMPT_STRENGTH)
                }.getOrNull()
            }
        }.awaitAll()
    }.mapNotNull { (id, takes) -> takes?.takeIf { it.isNotEmpty() }?.let { id to it } }.toMap()
    made.forEach { (id, takes) -> RemixTakeCache.put(context, id, takes) }
    return runCatching {
        val take = made[accent.id]?.firstOrNull() ?: error("no_takes")
        // "default": part of the clone it follows, not the learner's change.
        val newId = client.save(
            take.id,
            // iOS sends `voiceDisplayName` — the library entry says whose it is.
            com.roro.futurevoice.data.VoiceName.display(context,
                com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName),
            accent.prompt,
            purpose = "default",
        )
        newId to accent
    }.onFailure { e ->
        if (e is kotlinx.coroutines.CancellationException) throw e
        Analytics.capture("voice_accent_default_failed",
            mapOf("reason" to (e.localizedMessage ?: e.toString()).take(200)))
    }.getOrNull()
}

/** An accent's label in the app language (iOS uses the catalog keys
 *  "American" / "British" / "Australian", shortened per language so four
 *  pills fit one row: ja 米国, de USA, fr Anglais — iOS `6754be8`). */
@Composable
internal fun accentLabel(accent: VoiceAccent): String = when (accent.id) {
    "en-US" -> stringResource(R.string.accent_american)
    "en-GB" -> stringResource(R.string.accent_british)
    "en-AU" -> stringResource(R.string.accent_australian)
    "de-DE" -> stringResource(R.string.accent_standard_german)
    else -> accent.label
}
