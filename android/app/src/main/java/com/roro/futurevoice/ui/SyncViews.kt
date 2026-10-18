package com.roro.futurevoice.ui

import android.content.Context
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudDone
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.CloudQueue
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.NetworkCell
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.sync.DriveAuth
import com.roro.futurevoice.sync.DriveTransport
import com.roro.futurevoice.sync.SyncEngine
import com.roro.futurevoice.sync.SyncStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import com.roro.futurevoice.ui.brand.IosButton as Button

// ── The Google grant ────────────────────────────────────────────────────

/** Why turning sync on (or checking for another device) didn't happen. */
enum class DriveConsentResult { GRANTED, DENIED, NO_ACCOUNT, FAILED }

/**
 * The one door to the `drive.appdata` grant from a screen: asks without UI
 * first (a grant the Google account already gave — the phone's, seen from the
 * tablet — needs no sheet), and only then shows Google's own consent sheet.
 * The token it gets is handed to the engine's transport.
 */
class DriveConsent internal constructor(
    private val context: Context,
    private val launch: (IntentSenderRequest) -> Unit,
) {
    internal var pending: CompletableDeferred<DriveAuth.Outcome>? = null

    suspend fun ensure(): DriveConsentResult {
        val first = DriveAuth.authorize(context)
        val outcome = if (first is DriveAuth.Outcome.NeedsConsent) {
            val wait = CompletableDeferred<DriveAuth.Outcome>()
            pending = wait
            launch(IntentSenderRequest.Builder(first.intent.intentSender).build())
            wait.await()
        } else first
        return when (outcome) {
            is DriveAuth.Outcome.Token -> {
                (SyncEngine.shared(context).transport as? DriveTransport)?.adopt(outcome.accessToken)
                DriveConsentResult.GRANTED
            }
            is DriveAuth.Outcome.NeedsConsent, DriveAuth.Outcome.Denied -> DriveConsentResult.DENIED
            is DriveAuth.Outcome.Failed ->
                if ("account" in outcome.reason.lowercase()) DriveConsentResult.NO_ACCOUNT else DriveConsentResult.FAILED
        }
    }
}

@Composable
fun rememberDriveConsent(): DriveConsent {
    val context = LocalContext.current
    var holder by remember { mutableStateOf<DriveConsent?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        val outcome = if (result.resultCode == android.app.Activity.RESULT_OK)
            DriveAuth.fromConsent(context, result.data)
        else DriveAuth.Outcome.Denied
        holder?.pending?.complete(outcome)
    }
    return remember { DriveConsent(context) { launcher.launch(it) }.also { holder = it } }
}

@Composable
fun consentMessage(r: DriveConsentResult): String = stringResource(when (r) {
    DriveConsentResult.DENIED -> R.string.google_drive_access_wasn_t_allowed_try_again_and_choose_allo_7f36e7
    DriveConsentResult.NO_ACCOUNT -> R.string.sign_in_to_a_google_account_on_this_device_then_try_again
    else -> R.string.google_drive_can_t_be_reached_right_now_check_your_connectio_286681
})

/** What an enable failed on, in the learner's words. */
private fun enableFailure(e: Throwable): DriveConsentResult = when ((e as? SyncEngine.EnableError)?.reason) {
    SyncEngine.EnableError.Reason.NEEDS_CONSENT -> DriveConsentResult.DENIED
    SyncEngine.EnableError.Reason.NO_ACCOUNT -> DriveConsentResult.NO_ACCOUNT
    else -> DriveConsentResult.FAILED
}

/** Grant, then turn on — the one sequence every "turn it on" button runs. */
suspend fun turnOnDriveSync(context: Context, consent: DriveConsent): DriveConsentResult {
    val granted = consent.ensure()
    if (granted != DriveConsentResult.GRANTED) return granted
    return runCatching { SyncEngine.shared(context).enable() }
        .fold({ DriveConsentResult.GRANTED }, { enableFailure(it) })
}

@Composable
private fun progressText(p: SyncEngine.Progress): String = when (p.phase) {
    SyncEngine.Progress.Phase.PULLING -> stringResource(R.string.getting_what_your_other_devices_did)
    SyncEngine.Progress.Phase.PUSHING -> stringResource(R.string.sending_lld_of_lld, p.done, p.total)
    SyncEngine.Progress.Phase.UPLOADING_AUDIO -> stringResource(R.string.uploading_audio_lld_of_lld, p.done, p.total)
    SyncEngine.Progress.Phase.DOWNLOADING_AUDIO -> stringResource(R.string.downloading_audio_lld_of_lld, p.done, p.total)
}

@Composable
private fun SyncProgressBar(p: SyncEngine.Progress) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (p.total > 0) LinearProgressIndicator(progress = { p.done.toFloat() / p.total }, modifier = Modifier.fillMaxWidth())
        else LinearProgressIndicator(Modifier.fillMaxWidth())
        Text(progressText(p), style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// ── Settings → Devices ──────────────────────────────────────────────────

/**
 * iOS `SyncSection`: one toggle, the numbers under it, and the things a
 * learner might need to do (sync now; audio over mobile data; delete from
 * Drive). Off by default: it spends the learner's Google storage, so it is
 * their call. Turning it off deletes nothing anywhere.
 */
@Composable
fun SyncDevicesPage(onBack: () -> Unit) {
    val context = LocalContext.current
    val engine = remember { SyncEngine.shared(context) }
    // The engine holds an account only for a real (non-anonymous) sign-in.
    val signedIn = engine.userId != null
    val scope = rememberCoroutineScope()
    val consent = rememberDriveConsent()
    val status by engine.status.collectAsStateWithLifecycle()
    val progress by engine.progress.collectAsStateWithLifecycle()
    val counts by engine.counts.collectAsStateWithLifecycle()
    val quotaFull by engine.quotaFull.collectAsStateWithLifecycle()
    val lastSync by engine.lastSyncAt.collectAsStateWithLifecycle()
    var enabled by remember { mutableStateOf(engine.isEnabled) }
    var enabling by remember { mutableStateOf(false) }
    var cellular by remember { mutableStateOf(SyncStore.cellularForAudio(context)) }
    var error by remember { mutableStateOf<DriveConsentResult?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var localBytes by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(Unit) { localBytes = measurePractice(context) }
    // The engine can switch itself off (the folder was deleted elsewhere).
    LaunchedEffect(status) { if (status is SyncEngine.Status.Off || status == SyncEngine.Status.Paused(SyncEngine.Pause.ZONE_MISSING)) enabled = engine.isEnabled }

    fun set(on: Boolean) {
        if (!on) { engine.disable(); enabled = false; return }
        enabled = true
        enabling = true
        scope.launch {
            val r = turnOnDriveSync(context, consent)
            enabling = false
            if (r != DriveConsentResult.GRANTED) { error = r; enabled = false }
        }
    }

    MeSubpage(stringResource(R.string.devices), onBack) {
        GroupedSectionHeader(stringResource(R.string.devices))
        GroupedCard {
            MeRow(Icons.Outlined.Devices, stringResource(R.string.continue_on_your_other_devices),
                stringResource(R.string.uses_your_google_drive), kind = MeRowKind.PLAIN,
                enabled = signedIn && !enabling,
                trailing = { com.roro.futurevoice.ui.brand.IosSwitch(checked = enabled,
                    onCheckedChange = if (signedIn && !enabling) { v -> set(v) } else null) })
            if (enabled) {
                GroupedRowDivider()
                val pendingParts = listOfNotNull(
                    counts.items.takeIf { it > 0 }?.let { stringResource(R.string.lld_to_send, it) },
                    counts.audioUp.takeIf { it > 0 }?.let { stringResource(R.string.lld_audio_files_to_upload, it) },
                    counts.audioDown.takeIf { it > 0 }?.let { stringResource(R.string.lld_audio_files_to_download, it) })
                when {
                    quotaFull -> MeRow(Icons.Outlined.CloudOff,
                        stringResource(R.string.google_drive_is_full_so_audio_isn_t_syncing), kind = MeRowKind.PLAIN)
                    status == SyncEngine.Status.Syncing -> MeRow(Icons.Outlined.Sync,
                        stringResource(R.string.syncing), kind = MeRowKind.PLAIN)
                    status == SyncEngine.Status.Paused(SyncEngine.Pause.NEEDS_CONSENT) -> MeRow(Icons.Outlined.CloudOff,
                        stringResource(R.string.allow_google_drive_access_to_keep_syncing), kind = MeRowKind.ACTION,
                        onClick = { scope.launch {
                            if (consent.ensure() == DriveConsentResult.GRANTED) engine.syncNow()
                        } })
                    status == SyncEngine.Status.Paused(SyncEngine.Pause.OFFLINE) -> MeRow(Icons.Outlined.CloudOff,
                        stringResource(R.string.offline_will_sync_when_you_re_back), kind = MeRowKind.PLAIN)
                    status == SyncEngine.Status.Paused(SyncEngine.Pause.ZONE_MISSING) -> MeRow(Icons.Outlined.CloudOff,
                        stringResource(R.string.sync_was_turned_off_from_another_device), kind = MeRowKind.PLAIN)
                    status is SyncEngine.Status.Failed -> MeRow(Icons.Outlined.CloudOff,
                        stringResource(R.string.couldn_t_sync, (status as SyncEngine.Status.Failed).reason), kind = MeRowKind.PLAIN)
                    else -> MeRow(Icons.Outlined.CloudDone,
                        lastSync?.let { stringResource(R.string.up_to_date,
                            DateUtils.getRelativeTimeSpanString(it, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()) }
                            ?: stringResource(R.string.waiting_for_the_first_sync),
                        pendingParts.joinToString(" · ").ifEmpty { null }, kind = MeRowKind.PLAIN)
                }
                progress?.let { p ->
                    GroupedRowDivider()
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) { SyncProgressBar(p) }
                }
                GroupedRowDivider()
                MeRow(Icons.Outlined.Sync, stringResource(R.string.sync_now), kind = MeRowKind.ACTION,
                    enabled = status != SyncEngine.Status.Syncing, onClick = { engine.syncNow() })
                GroupedRowDivider()
                MeRow(Icons.Outlined.NetworkCell, stringResource(R.string.move_audio_over_cellular_too),
                    kind = MeRowKind.PLAIN,
                    trailing = { com.roro.futurevoice.ui.brand.IosSwitch(checked = cellular, onCheckedChange = { v ->
                        cellular = v
                        SyncStore.setCellularForAudio(context, v)
                        com.roro.futurevoice.sync.SyncBackground.schedule(context)
                    }) })
                GroupedRowDivider()
                MeRow(Icons.Outlined.CloudOff, stringResource(R.string.delete_from_google_drive),
                    kind = MeRowKind.DESTRUCTIVE, onClick = { confirmDelete = true })
            }
        }
        val size = localBytes?.takeIf { it > 0 }?.let { android.text.format.Formatter.formatShortFileSize(context, it) }
        GroupedFooter(listOfNotNull(
            if (!enabled && (localBytes ?: 0) > 0)
                stringResource(R.string.right_now_your_practice_is_on_this_device_only_if_you_delete_40da0e) else null,
            stringResource(if (enabled) R.string.your_talks_cards_words_and_recordings_audio_included_stay_th_0bead2
                           else R.string.practise_on_your_phone_pick_it_up_on_your_tablet_everything_0cf690),
            stringResource(R.string.your_voice_recording_goes_too_so_a_new_phone_makes_your_voic_c72584),
            size?.let { stringResource(R.string.your_practice_on_this_device_takes_about_that_s_roughly_the_b9cf59, it) },
        ).joinToString("\n\n"))
    }

    error?.let { e ->
        AlertDialog(onDismissRequest = { error = null },
            title = { Text(stringResource(R.string.couldn_t_turn_on_sync)) },
            text = { Text(consentMessage(e)) },
            confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) } })
    }
    if (confirmDelete) {
        AlertDialog(onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_your_practice_from_google_drive)) },
            text = { Text(stringResource(R.string.everything_synced_to_google_drive_is_removed_and_syncing_sto_32a900)) },
            confirmButton = { TextButton(onClick = {
                confirmDelete = false
                scope.launch { runCatching { engine.deleteFromCloud() }; enabled = false }
            }) { Text(stringResource(R.string.delete_from_google_drive), color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.not_now)) } })
    }
}

/** Talks, cards, words and every recording live under these folders; caches
 *  don't, and aren't synced. Roughly what Drive needs. */
private suspend fun measurePractice(context: Context): Long = withContext(Dispatchers.IO) {
    listOf("lang", "turn-audio", "shadow-takes", "Speech").sumOf { name ->
        File(context.filesDir, name).walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }
}

// ── The second device ───────────────────────────────────────────────────

/**
 * iOS `SyncContinuePromptView` and `SyncOtherDeviceHintView`, as one screen.
 * On iOS the device can ask iCloud silently whether the account has practice
 * there; on Android the question needs the learner's Google grant, so the
 * screen asks first and checks on the button. Found → enable and pull, and
 * setup is skipped if the persona came with it. Not found → say which toggle
 * to turn on over there. "Start fresh" walks into setup; shown once per
 * account per install either way.
 */
@Composable
fun SyncContinueScreen(userId: String, onPulled: () -> Unit, onDone: () -> Unit) {
    val context = LocalContext.current
    val engine = remember { SyncEngine.shared(context) }
    val scope = rememberCoroutineScope()
    val consent = rememberDriveConsent()
    val progress by engine.progress.collectAsStateWithLifecycle()
    var working by remember { mutableStateOf(false) }
    var notYet by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<DriveConsentResult?>(null) }

    fun finish() { SyncStore.setOffered(context, userId); onDone() }

    fun go() = scope.launch {
        working = true; notYet = false
        val granted = consent.ensure()
        if (granted != DriveConsentResult.GRANTED) { working = false; error = granted; return@launch }
        when (engine.cloudHasData()) {
            true -> {
                val r = turnOnDriveSync(context, consent)
                working = false
                if (r == DriveConsentResult.GRANTED) {
                    Analytics.capture("sync_continue", mapOf("result" to "pulled"))
                    onPulled(); finish()
                } else error = r
            }
            false -> { working = false; notYet = true }
            null -> { working = false; error = DriveConsentResult.FAILED }
        }
    }

    BottomActionLayout(
        content = {
            Icon(Icons.Outlined.CloudDownload, contentDescription = null,
                modifier = Modifier.size(56.dp), tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.continue_where_you_left_off),
                style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center)
            Text(stringResource(R.string.practised_on_another_phone_or_tablet_with_sync_on_your_talks_dc3ff4),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            if (notYet && !working) {
                Text(stringResource(R.string.nothing_here_yet_check_that_it_s_on_over_there_then_try_agai_81004b) + "\n" +
                    stringResource(R.string.on_your_other_device_open_settings_turn_on_continue_on_your_c7fa99),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
            if (working) progress?.let { SyncProgressBar(it) }
        },
        actions = {
            Button(onClick = { go() }, enabled = !working, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(if (notYet) R.string.check_again else R.string.continue_))
            }
            TextButton(onClick = {
                Analytics.capture("sync_continue", mapOf("result" to if (notYet) "fresh_after_check" else "fresh"))
                finish()
            }, enabled = !working) {
                Text(stringResource(R.string.start_fresh_on_this_device))
            }
        },
    )

    error?.let { e ->
        AlertDialog(onDismissRequest = { error = null },
            title = { Text(stringResource(R.string.couldn_t_bring_your_practice_over)) },
            text = { Text(consentMessage(e)) },
            confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) } })
    }
}

// ── After the third talk ────────────────────────────────────────────────

/** Same key as iOS `ConversationHome.backupOffered`: asked once per install. */
const val BACKUP_OFFERED_KEY = "futurevoice.backupOffered"

/**
 * iOS `BackupOfferSheet`, asked ONCE after the third finished talk while
 * sync is off: nothing tells an app it is being uninstalled, so the only
 * time to say what a deletion costs is before it happens. iOS answers with
 * the learner's iCloud; Android with their Google Drive.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupOfferSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val consent = rememberDriveConsent()
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<DriveConsentResult?>(null) }
    LaunchedEffect(Unit) { Analytics.capture("backup_offer_shown") }

    ModalBottomSheet(
        onDismissRequest = { if (!working) onDismiss() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets().verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp).padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Icon(Icons.Outlined.CloudUpload, contentDescription = null,
                modifier = Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.keep_your_practice_in_google_drive),
                style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.your_talks_books_and_recordings_are_on_this_phone_only_if_yo_02b0cd),
                style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(stringResource(R.string.kept_in_your_own_google_drive_it_waits_on_any_phone_or_table_45e1ff),
                style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            error?.let {
                Text(consentMessage(it), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
            Button(
                onClick = {
                    working = true; error = null
                    scope.launch {
                        val r = turnOnDriveSync(context, consent)
                        working = false
                        Analytics.capture("backup_offer_result",
                            mapOf("result" to if (r == DriveConsentResult.GRANTED) "enabled" else "failed"))
                        if (r == DriveConsentResult.GRANTED) onDismiss() else error = r
                    }
                },
                enabled = !working,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            ) { Text(stringResource(R.string.keep_in_google_drive)) }
            TextButton(
                onClick = {
                    Analytics.capture("backup_offer_result", mapOf("result" to "later"))
                    onDismiss()
                },
                enabled = !working,
                modifier = Modifier.fillMaxWidth().align(Alignment.CenterHorizontally),
            ) { Text(stringResource(R.string.not_now)) }
        }
    }
}
