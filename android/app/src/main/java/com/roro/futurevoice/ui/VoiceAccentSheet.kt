package com.roro.futurevoice.ui

import com.roro.futurevoice.core.Analytics
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.VoiceAccent
import com.roro.futurevoice.data.VoiceAccentCatalog
import com.roro.futurevoice.net.VoiceRemixClient
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch

/**
 * Accent picker for the cloned voice — pick an accent, audition a few remix
 * takes of your OWN clone speaking with it, keep the one that sounds most
 * like you.
 *
 * It exists because a clone recorded in the learner's NATIVE language carries
 * no target-language accent at all, and the TTS model fills that gap with its
 * own default (US English for `en`) — wrong for a learner living in London.
 *
 * **Generate, audition, then choose explicitly.** No take is adopted just by
 * being played: remixing REPLACES the live clone and deletes the outgoing
 * voice upstream, so applying one is not something to do by accident.
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
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember { VoiceRemixClient(AuthRepository()) }
    val player = remember { Mp3Player(context.cacheDir, source = "accent_preview") }

    val options = remember(targetLanguage) { VoiceAccentCatalog.options(targetLanguage) }
    var accent by remember { mutableStateOf<VoiceAccent?>(null) }
    /** The month's one voice change (iOS `canChangeVoice`, 2026-10-09). */
    val changeStatus by com.roro.futurevoice.data.VoiceChanges.status
        .collectAsStateWithLifecycle()
    val canChange = changeStatus?.canChange ?: true
    LaunchedEffect(Unit) { com.roro.futurevoice.data.VoiceChanges.refresh() }
    var removing by remember { mutableStateOf(false) }
    var confirmingRemove by remember { mutableStateOf(false) }
    var confirmingApply by remember { mutableStateOf(false) }
    val canRemoveAccent = !appliedAccentId.isNullOrEmpty() &&
        VoiceComparison.exists(context.filesDir)
    var previews by remember { mutableStateOf<List<VoiceRemixClient.Preview>>(emptyList()) }
    var picked by remember { mutableStateOf<String?>(null) }
    var playing by remember { mutableStateOf<String?>(null) }
    var generating by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    DisposableEffect(Unit) { onDispose { runCatching { player.stop() } } }

    fun generate(chosen: VoiceAccent) {
        generating = true; error = null
        Analytics.capture("voice_accent_previews_requested", mapOf("accent" to chosen.id))
        scope.launch {
            runCatching {
                // No rebuild first (iOS 2026-10-09). Rebuilding the plain
                // clone to make takes spent a whole voice of the month's
                // allowance on LISTENING. The takes for every accent are made
                // at the clone (`remixIntoDefaultAccent`) and found in
                // [RemixTakeCache]; only when they are gone (a reinstall) are
                // takes made from the live voice — one generation of drift,
                // against a voice.
                client.previews(voiceId, chosen.prompt,
                    VoiceAccentCatalog.sampleText(targetLanguage))
            }.onSuccess { previews = it; RemixTakeCache.put(context, chosen.id, it) }
                .onFailure {
                    error = context.getString(R.string.couldnt_make_the_takes_try_again)
                }
            generating = false
        }
    }

    LaunchedEffect(initialAccent) {
        initialAccent?.let { first ->
            if (options.any { it.id == first.id }) {
                accent = first
                val cached = RemixTakeCache.get(context, first.id)
                if (cached != null) {
                    previews = cached
                    Analytics.capture("voice_accent_previews_reused", mapOf("accent" to first.id))
                // No change left this month: new takes could never be kept,
                // so none are made (the server would refuse them too).
                } else if (com.roro.futurevoice.data.VoiceChanges.canChange) generate(first)
            }
        }
    }

    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = { if (!saving && !generating && !removing) onDismiss() }) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(R.string.accent), style = MaterialTheme.typography.titleLarge)
            Text(stringResource(R.string.your_clone_speaking_with_a_different_accent),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                options.forEach { o ->
                    FilterChip(
                        selected = accent?.id == o.id,
                        onClick = {
                            // Takes this recording already has for this accent
                            // are shown, never made again (`RemixTakeCache`) —
                            // closing the sheet and reopening it used to pay for
                            // the same remix twice. Only re-tapping the accent
                            // whose takes are ON SCREEN asks for new ones.
                            val regenerate = accent?.id == o.id && previews.isNotEmpty()
                            // A new accent invalidates the takes on screen —
                            // keeping them would let a British take be applied
                            // under an American label.
                            accent = o; picked = null; error = null
                            val cached = if (regenerate) null else RemixTakeCache.get(context, o.id)
                            if (cached != null) {
                                previews = cached
                                Analytics.capture("voice_accent_previews_reused", mapOf("accent" to o.id))
                            } else previews = emptyList()
                        },
                        label = {
                            val label = accentLabel(o)
                            Text(if (o.id == appliedAccentId) "$label ✓" else label)
                        },
                    )
                }
            }

            // With no change left, takes already on file can still be heard;
            // the line says when a change comes back (iOS footer).
            if (!canChange && !generating) {
                Text(com.roro.futurevoice.data.VoiceChangeStatus.againLine(context, changeStatus?.nextAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            val chosen = accent
            if (chosen != null && previews.isEmpty()) {
                Button(
                    onClick = { generate(chosen) },
                    enabled = !generating && canChange,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (generating) {
                        Row(verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Text(stringResource(R.string.making_a_few_takes))
                        }
                    } else Text(stringResource(R.string.hear_some_takes))
                }
            }

            if (previews.isNotEmpty()) {
                HorizontalDivider()
                Text(stringResource(R.string.pick_the_one_that_sounds_most_like_you),
                    style = MaterialTheme.typography.titleSmall)
                previews.forEachIndexed { i, p ->
                    Row(
                        Modifier.fillMaxWidth()
                            .selectable(selected = picked == p.id, onClick = { picked = p.id })
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        RadioButton(selected = picked == p.id, onClick = null)
                        Text(stringResource(R.string.take_lld, i + 1), Modifier.weight(1f))
                        IconButton(onClick = {
                            scope.launch {
                                if (playing == p.id) { player.stop(); playing = null }
                                else {
                                    playing = p.id
                                    runCatching { player.play(p.audio) }
                                    playing = null
                                }
                            }
                        }) {
                            Icon(
                                if (playing == p.id) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                                contentDescription = stringResource(
                                    if (playing == p.id) R.string.stop else R.string.play),
                            )
                        }
                    }
                }

                // Saving a take is the learner's one change for 30 days, so
                // it is asked, not done on the tap (iOS 2026-10-09).
                Button(
                    onClick = { if (picked != null) confirmingApply = true },
                    enabled = picked != null && !saving && canChange,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (saving) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    else Text(stringResource(R.string.use_this_take))
                }
                // Said out loud because it can't be undone from here: the old
                // voice is deleted upstream, and the only way back is a fresh
                // clone from the saved recording.
                Text(if (canChange) stringResource(R.string.this_replaces_your_current_voice)
                    else com.roro.futurevoice.data.VoiceChangeStatus.againLine(context, changeStatus?.nextAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedButton(
                    onClick = { previews = emptyList(); picked = null },
                    enabled = !saving,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.try_again)) }
            }

            // The way back — LAST, its own section, so it reads as an action
            // and not a fourth option (iOS `removeAccentSection`).
            if (canRemoveAccent) {
                HorizontalDivider()
                OutlinedButton(
                    onClick = { confirmingRemove = true },
                    enabled = !generating && !saving && !removing && canChange,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (removing) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    else Text(stringResource(R.string.remove_accent), color = MaterialTheme.colorScheme.error)
                }
                Text(stringResource(R.string.back_to_the_voice_your_recording_makes_on_its_own),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (confirmingApply) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmingApply = false },
            title = { Text(stringResource(R.string.use_this_voice_q)) },
            text = { Text(com.roro.futurevoice.data.VoiceChangeStatus.usesItLine(context)) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    confirmingApply = false
                    val id = picked ?: return@TextButton
                    val chosen = accent
                    player.stop()
                    saving = true; error = null
                    scope.launch {
                        runCatching {
                            client.save(id,
                                // iOS sends `voiceDisplayName` — the library entry says whose it is.
                                com.roro.futurevoice.data.VoiceName.display(context,
                                    com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName),
                                chosen?.prompt.orEmpty())
                        }.onSuccess { newId ->
                            onApplied(newId, chosen?.id.orEmpty())
                            onDismiss()
                        }.onFailure { e ->
                            if (e is com.roro.futurevoice.data.VoiceChangeLimit) {
                                // Someone else's device used it first; say the date.
                                com.roro.futurevoice.data.VoiceChanges.refresh()
                                error = e.line(context)
                            } else {
                                // A remembered take can go stale upstream; the next
                                // pick of this accent makes fresh ones instead of
                                // failing again.
                                chosen?.let { RemixTakeCache.drop(context, it.id) }
                                error = context.getString(R.string.couldnt_apply_that_take_try_again)
                            }
                        }
                        saving = false
                    }
                }) { Text(stringResource(R.string.use_this_voice)) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { confirmingApply = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
    if (confirmingRemove) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmingRemove = false },
            title = { Text(stringResource(R.string.remove_the_accent)) },
            text = { Text(stringResource(R.string.rebuilds_your_voice_from_your_saved_recording_which_takes_a_90f303) +
                "\n\n" + com.roro.futurevoice.data.VoiceChangeStatus.usesItLine(context)) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    confirmingRemove = false
                    player.stop()
                    removing = true; error = null
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
                            onApplied(newId, "")
                            onDismiss()
                        }.onFailure { e ->
                            error = (e as? com.roro.futurevoice.data.VoiceChangeLimit)?.line(context)
                                ?: e.localizedMessage ?: e.toString()
                        }
                        removing = false
                    }
                }) { Text(stringResource(R.string.remove), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { confirmingRemove = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
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
