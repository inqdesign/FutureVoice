package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import androidx.compose.runtime.LaunchedEffect
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.ui.brand.CoreSeal
import com.roro.futurevoice.talk.UserPersona

/**
 * Me — the settings surface, reduced to what exists on Android today:
 * profile (name/home + what the future self has learned, each note
 * removable — a memory that can't be corrected is a liability), the daily
 * goal, the learning language row, and sign out. Buying/metering rows arrive
 * with Play Billing.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MeScreen(
    email: String?,
    persona: UserPersona?,
    targetLanguage: String,
    nativeLanguage: String,
    onSavePersona: (UserPersona) -> Unit,
    onEditProfile: () -> Unit,
    onSignOut: () -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    var confirmingSignOut by remember { mutableStateOf(false) }
    var coreProgress by remember { mutableStateOf<CoreClubClient.Progress?>(null) }
    LaunchedEffect(targetLanguage) {
        coreProgress = CoreClubClient(AuthRepository()).progress(targetLanguage)
    }
    var callEnabled by remember {
        mutableStateOf(com.roro.futurevoice.data.DailyCallStore.isEnabled(context))
    }
    var callHour by remember {
        mutableStateOf(com.roro.futurevoice.data.DailyCallStore.hour(context))
    }
    val notifPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { }
    var goal by remember {
        mutableStateOf(context.getSharedPreferences("futurevoice", 0)
            .getInt("futurevoice.dailyGoalMinutes", 10))
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.me)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // ── Profile ──
            Column(Modifier.fillMaxWidth().clickable { onEditProfile() }) {
                Text(stringResource(R.string.profile), style = MaterialTheme.typography.titleMedium)
                Text(
                    listOfNotNull(persona?.displayName?.takeIf { it.isNotBlank() },
                        persona?.city?.takeIf { it.isNotBlank() }).joinToString(" · ")
                        .ifEmpty { email.orEmpty() },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            // What the future self has learned — the other half of the
            // profile. Each note removable; the learner can always correct
            // the memory.
            persona?.learnedNotes?.takeIf { it.isNotEmpty() }?.let { notes ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    notes.forEach { note ->
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(note.text, style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.weight(1f))
                            TextButton(onClick = {
                                onSavePersona(persona.copy(
                                    learnedNotes = persona.learnedNotes.filterNot { it.id == note.id }))
                            }) { Text("×") }
                        }
                    }
                }
            }
            HorizontalDivider()

            // ── Daily goal ──
            Column {
                Text(stringResource(R.string.daily_goal), style = MaterialTheme.typography.titleMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(5, 10, 15, 20, 30).forEach { m ->
                        FilterChip(selected = goal == m, onClick = {
                            goal = m
                            context.getSharedPreferences("futurevoice", 0).edit()
                                .putInt("futurevoice.dailyGoalMinutes", m).apply()
                        }, label = { Text(stringResource(R.string.lld_min_a_day, m)) })
                    }
                }
            }
            HorizontalDivider()

            // ── Daily call — the habit anchor. Answering opens the talk. ──
            Column {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.daily_call),
                        style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                    androidx.compose.material3.Switch(checked = callEnabled, onCheckedChange = { on ->
                        callEnabled = on
                        com.roro.futurevoice.data.DailyCallStore.set(context, on, callHour, 0)
                        if (on) notifPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
                    })
                }
                if (callEnabled) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(7, 8, 9, 12, 19, 21).forEach { h ->
                            FilterChip(selected = callHour == h, onClick = {
                                callHour = h
                                com.roro.futurevoice.data.DailyCallStore.set(context, true, h, 0)
                            }, label = { Text("%02d:00".format(h)) })
                        }
                    }
                }
            }
            HorizontalDivider()

            // ── Learning language (display; enrollment work comes later) ──
            Column {
                Text(stringResource(R.string.learn_which_language), style = MaterialTheme.typography.titleMedium)
                Text(
                    "${LanguageCatalog.endonym(targetLanguage)} · " +
                        LanguageCatalog.ownName(targetLanguage, nativeLanguage),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            HorizontalDivider()

            // ── The Core — a standing and a record, and it grants NOTHING.
            // Numbers only, no grid: the progress IS the number.
            coreProgress?.let { core ->
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(stringResource(R.string.the_core),
                            style = MaterialTheme.typography.titleMedium)
                        if (core.seated) CoreSeal()
                    }
                    Text(
                        if (core.seated) stringResource(R.string.you_re_in)
                        // A BAR, never a rank: how many days in a row, against
                        // the entry streak. No grid — the progress is the number.
                        else "${core.streak} / ${core.entry_streak}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(stringResource(R.string.s_100_seats_30_days_in_a_row_to_enter),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider()

            // ── Account ──
            Text(email.orEmpty(), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (com.roro.futurevoice.BuildConfig.DEBUG) {
                TextButton(onClick = { com.roro.futurevoice.data.DailyCallScheduler.ring(context) }) {
                    Text("Ring now (debug)")
                }
            }
            TextButton(onClick = { confirmingSignOut = true }) {
                Text(stringResource(R.string.sign_out_dc1649), color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (confirmingSignOut) {
        AlertDialog(
            onDismissRequest = { confirmingSignOut = false },
            title = { Text(stringResource(R.string.sign_out_b11555)) },
            confirmButton = {
                TextButton(onClick = { confirmingSignOut = false; onSignOut() }) {
                    Text(stringResource(R.string.sign_out_dc1649))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingSignOut = false }) {
                    Text(stringResource(R.string.back_b52b36))
                }
            },
        )
    }
}
