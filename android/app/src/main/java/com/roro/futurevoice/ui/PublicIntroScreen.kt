package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.clickable
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch

/**
 * Write and publish your own self-introduction into the shared persona pool,
 * so other learners can practise talking with "you".
 *
 * What they meet is a model playing this introduction in a STOCK preset voice
 * — never your cloned voice — and their talks never reach you: no
 * notification, no shared record.
 *
 * The intro is written in the TARGET language on purpose: it doubles as the
 * persona's conversational substance and as writing practice for its author.
 * Density is the entry ticket — a one-liner can't carry a conversation, so
 * publishing unlocks at a minimum length, the same one the database enforces.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PublicIntroScreen(
    persona: UserPersona?,
    targetLanguage: String,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember { PublicPersonaClient(AuthRepository()) }

    var displayName by remember { mutableStateOf("") }
    var intro by remember { mutableStateOf("") }
    var location by remember { mutableStateOf("") }
    var occupation by remember { mutableStateOf("") }
    var interests by remember { mutableStateOf("") }
    var voiceId by remember { mutableStateOf(StockPerson.catalog.first().voiceId) }
    var publishedId by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmingWithdraw by remember { mutableStateOf(false) }

    val languageName = LanguageCatalog.englishName(targetLanguage)
    val trimmed = intro.trim()
    val canPublish = displayName.isNotBlank() &&
        trimmed.length >= PublicPersonaClient.MIN_INTRO && !saving

    LaunchedEffect(targetLanguage) {
        loading = true
        val mine = runCatching { client.fetchMine(targetLanguage) }.getOrNull()
        if (mine != null) {
            publishedId = mine.id
            displayName = mine.display_name; intro = mine.intro
            location = mine.location; occupation = mine.occupation
            interests = mine.interests
            if (mine.voice_preset_id.isNotBlank()) voiceId = mine.voice_preset_id
        } else {
            // A draft seeds from the profile onboarding already has — the
            // intro itself stays theirs to write.
            displayName = persona?.displayName.orEmpty()
            persona?.let { p ->
                location = listOf(p.city, p.country).filter { it.isNotBlank() }.joinToString(", ")
                occupation = p.occupation
                interests = p.interests.joinToString(", ")
            }
        }
        loading = false
    }

    fun markManual() {
        // From here on the learner curates their own row — the launch-time
        // auto-sync from the onboarding profile must never overwrite it, and
        // must never quietly put a taken-down row back.
        context.getSharedPreferences("futurevoice", 0).edit()
            .putBoolean(PublicPersonaClient.MANUAL_INTRO_KEY, true).apply()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.find_people)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        if (loading) {
            Box(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground),
                contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(bottom = 32.dp),
        ) {
            GroupedCard {
                FieldRow(displayName, { displayName = it },
                    stringResource(R.string.name), singleLine = true)
            }
            GroupedFooter(stringResource(R.string.the_name_other_learners_will_see))

            GroupedSectionHeader(stringResource(R.string.introduction))
            GroupedCard {
                FieldRow(intro, { intro = it }, "", singleLine = false)
                Row(Modifier.fillMaxWidth().padding(end = 14.dp, bottom = 8.dp),
                    horizontalArrangement = Arrangement.End) {
                    Text("${trimmed.length} / ${PublicPersonaClient.MIN_INTRO}",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (trimmed.length >= PublicPersonaClient.MIN_INTRO)
                            MaterialTheme.colorScheme.onSurfaceVariant
                        else MaterialTheme.colorScheme.outline)
                }
            }
            GroupedFooter(stringResource(
                R.string.write_it_in_lld_its_what_you_will_talk_from, languageName))

            GroupedSectionHeader(stringResource(R.string.details))
            GroupedCard {
                FieldRow(location, { location = it },
                    stringResource(R.string.city_country), singleLine = true)
                GroupedRowDivider(inset = false)
                FieldRow(occupation, { occupation = it },
                    stringResource(R.string.what_you_do), singleLine = true)
                GroupedRowDivider(inset = false)
                FieldRow(interests, { interests = it },
                    stringResource(R.string.interests), singleLine = true)
            }

            GroupedSectionHeader(stringResource(R.string.voice))
            GroupedCard {
                StockPerson.catalog.forEachIndexed { i, v ->
                    if (i > 0) GroupedRowDivider(inset = false)
                    Row(
                        Modifier.fillMaxWidth()
                            .selectable(selected = voiceId == v.voiceId,
                                onClick = { voiceId = v.voiceId })
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        RadioButton(selected = voiceId == v.voiceId, onClick = null)
                        Text(v.identity, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            GroupedFooter(stringResource(R.string.a_stock_voice_that_plays_you))

            androidx.compose.foundation.layout.Spacer(Modifier.height(24.dp))
            GroupedCard {
                Row(
                    Modifier.fillMaxWidth()
                        .clickable(enabled = canPublish) {
                            saving = true; error = null
                            scope.launch {
                                runCatching {
                                    client.publishMine(
                                        displayName = displayName.trim(), intro = trimmed,
                                        location = location.trim(),
                                        occupation = occupation.trim(),
                                        interests = interests.trim(),
                                        voicePresetId = voiceId, language = targetLanguage)
                                }.onSuccess {
                                    markManual()
                                    if (publishedId == null) {
                                        publishedId = runCatching { client.fetchMine(targetLanguage) }
                                            .getOrNull()?.id
                                    }
                                }.onFailure {
                                    error = context.getString(
                                        R.string.couldnt_publish_check_your_connection)
                                }
                                saving = false
                            }
                        }
                        .padding(horizontal = 14.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(stringResource(
                        if (publishedId == null) R.string.publish else R.string.update),
                        color = if (canPublish) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.outline,
                        modifier = Modifier.weight(1f))
                    if (saving) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                }
                if (publishedId != null) {
                    GroupedRowDivider(inset = false)
                    Row(
                        Modifier.fillMaxWidth()
                            .clickable(enabled = !saving) { confirmingWithdraw = true }
                            .padding(horizontal = 14.dp, vertical = 14.dp),
                    ) {
                        Text(stringResource(R.string.take_down),
                            color = MaterialTheme.colorScheme.error)
                    }
                }
            }
            error?.let { GroupedFooter(it) }
                ?: if (publishedId != null) {
                    GroupedFooter(stringResource(
                        R.string.youre_in_the_pool_other_lld_learners_can_find_you, languageName))
                } else Unit
        }
    }

    if (confirmingWithdraw) {
        AlertDialog(
            onDismissRequest = { confirmingWithdraw = false },
            title = { Text(stringResource(R.string.take_down)) },
            text = { Text(stringResource(R.string.take_your_intro_out_of_the_pool)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingWithdraw = false; saving = true
                    scope.launch {
                        runCatching { client.withdrawMine(targetLanguage) }
                            .onSuccess {
                                // Taking it down is as deliberate as
                                // publishing — stop the auto-sync from
                                // quietly putting the row back next launch.
                                markManual(); publishedId = null
                            }
                            .onFailure {
                                error = context.getString(R.string.couldnt_take_it_down)
                            }
                        saving = false
                    }
                }) {
                    Text(stringResource(R.string.take_down),
                        color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingWithdraw = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/**
 * A text field drawn as a LIST ROW: iOS's `Form` puts a bare `TextField` in a
 * grouped row, with no box of its own. An outlined box per field would put a
 * second border inside the card the row already sits in.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FieldRow(
    value: String,
    onValue: (String) -> Unit,
    label: String,
    singleLine: Boolean,
) {
    androidx.compose.material3.OutlinedTextField(
        value = value,
        onValueChange = onValue,
        placeholder = if (label.isEmpty()) null else ({ Text(label) }),
        singleLine = singleLine,
        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
            unfocusedBorderColor = androidx.compose.ui.graphics.Color.Transparent,
            focusedBorderColor = androidx.compose.ui.graphics.Color.Transparent,
        ),
        modifier = Modifier.fillMaxWidth()
            .then(if (singleLine) Modifier else Modifier.heightIn(min = 150.dp)),
    )
}
