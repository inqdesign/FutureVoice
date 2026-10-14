package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.PublicIntroComposer
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosBackButton
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.IosNavTitle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The ONE "me" page (iOS `MyProfileView`, 2026-10-12, founder: "my avatar
 * and my public profile being two places is odd"). The Watch map's own face,
 * Find people's "You" row and Me's profile header all open it. The intro is
 * not a separate thing — `PublicIntroComposer` writes it FROM the profile —
 * so both halves sit on one page: the profile on top, what other learners
 * see under it.
 *
 * The consent rule is untouched: nothing goes into the pool from here
 * without the paragraph being on screen first — Publish lands in
 * [PublicIntroScreen], seeded with the text shown here.
 *
 * The public-intro editor is pushed inside this page's own stack, so the
 * page behaves the same from every door.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyProfileScreen(
    persona: UserPersona?,
    targetLanguage: String,
    /** Watch presents this as its own sheet and needs a way out; pushed from
     *  Me or Find people it has a back button. */
    showsDone: Boolean = false,
    onBack: () -> Unit,
    /** The profile editor (iOS `PersonaOnboardingView` sheet) — the host's. */
    onEditProfile: () -> Unit,
    /** Find people redraws its "You" row from this. */
    onPublicChange: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember { PublicPersonaClient(AuthRepository()) }

    var mine by remember { mutableStateOf<PublicPersonaClient.PublicPersona?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var confirmingWithdraw by remember { mutableStateOf(false) }
    var isWorking by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    /** The public-intro editor, pushed (iOS `NavigationLink { introEditor }`). */
    var editingIntro by rememberSaveable { mutableStateOf(false) }
    var reloadToken by remember { mutableStateOf(0) }

    val languageName = LanguageCatalog.englishName(targetLanguage)

    suspend fun loadMine() {
        mine = runCatching { client.fetchMine(targetLanguage) }.getOrNull()
        loaded = true
    }
    LaunchedEffect(targetLanguage, reloadToken) { loadMine() }
    // A saved profile re-syncs an auto-approved row in the background; read
    // it again so the paragraph below follows (iOS: on the editor's dismiss).
    var seenPersona by remember { mutableStateOf(persona) }
    LaunchedEffect(persona) {
        if (persona == seenPersona) return@LaunchedEffect
        seenPersona = persona
        delay(1500)
        loadMine()
    }

    fun withdraw() {
        isWorking = true
        errorText = null
        scope.launch {
            runCatching { client.withdrawMine(targetLanguage) }
                .onSuccess {
                    // Same as the editor's Take down: a deliberate choice the
                    // launch-time mirror must not quietly undo.
                    PublicPersonaClient.prefs(context).edit()
                        .putBoolean(PublicPersonaClient.MANUAL_INTRO_KEY, true).apply()
                    mine = null
                    onPublicChange?.invoke()
                }
                .onFailure {
                    errorText = context.getString(
                        R.string.couldn_t_take_it_down_check_your_connection_and_try_again)
                }
            isWorking = false
        }
    }

    val stack = if (editingIntro) listOf("profile", "intro") else listOf("profile")
    IosNavStack(stack = stack, onPop = { editingIntro = false; reloadToken++ }) { page ->
        if (page == "intro") {
            PublicIntroScreen(
                persona = persona,
                targetLanguage = targetLanguage,
                onBack = { editingIntro = false; reloadToken++ },
                onDecided = {
                    reloadToken++
                    onPublicChange?.invoke()
                },
            )
            return@IosNavStack
        }
        NavPageBackHandler(onBack = onBack)
        Scaffold(
            containerColor = AppSurfaces.ground,
            topBar = {
                CenterAlignedTopAppBar(
                    colors = AppSurfaces.topBarColors(),
                    title = { IosNavTitle(stringResource(R.string.profile)) },
                    navigationIcon = { if (!showsDone) IosBackButton(onBack) },
                    actions = {
                        if (showsDone) {
                            IosGlassTextButton(stringResource(R.string.done), onClick = onBack,
                                modifier = Modifier.padding(end = 12.dp))
                        }
                    },
                )
            },
            contentWindowInsets = fieldScaffoldInsets,
        ) { padding ->
            Column(
                Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp).padding(bottom = 32.dp),
            ) {
                ProfileSection(persona, onEditProfile)
                PublicSection(
                    persona = persona,
                    targetLanguage = targetLanguage,
                    languageName = languageName,
                    loaded = loaded,
                    mine = mine,
                    isWorking = isWorking,
                    errorText = errorText,
                    onEditIntro = { editingIntro = true },
                    onTakeDown = { confirmingWithdraw = true },
                )
            }
        }
        if (confirmingWithdraw) {
            AlertDialog(
                onDismissRequest = { confirmingWithdraw = false },
                title = { Text(stringResource(R.string.take_down)) },
                text = { Text(stringResource(R.string.take_your_intro_out_of_the_pool_learners_who_already_met_you_863b54)) },
                confirmButton = {
                    TextButton(onClick = { confirmingWithdraw = false; withdraw() }) {
                        Text(stringResource(R.string.take_down), color = MaterialTheme.colorScheme.error)
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
}

/** "What your fluent self knows about you": avatar, name, one line, Edit. */
@Composable
private fun ProfileSection(persona: UserPersona?, onEdit: () -> Unit) {
    GroupedSectionHeader(stringResource(R.string.what_your_fluent_self_knows_about_you))
    GroupedCard {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onEdit)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            ProfileAvatar(initials = persona?.displayName.orEmpty(), size = 56.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    persona?.displayName?.takeIf { it.isNotEmpty() }
                        ?: stringResource(R.string.set_up_your_profile),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface)
                // "Berlin · Solo founder" — what the editor's first pages
                // hold, in one line. The learner's own words.
                val line = persona?.let { p ->
                    listOf(p.city, p.occupation).map { it.trim() }.filter { it.isNotEmpty() }
                        .joinToString(" · ")
                }.orEmpty()
                if (line.isNotEmpty()) {
                    Text(line, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                }
            }
            // Only "Edit" says it's tappable.
            Text(stringResource(R.string.edit), style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.primary)
        }
    }
}

/** "What strangers can see": the live row, or the composed paragraph and Publish. */
@Composable
private fun PublicSection(
    persona: UserPersona?,
    targetLanguage: String,
    languageName: String,
    loaded: Boolean,
    mine: PublicPersonaClient.PublicPersona?,
    isWorking: Boolean,
    errorText: String?,
    onEditIntro: () -> Unit,
    onTakeDown: () -> Unit,
) {
    val green = Color(0xFF34C759)
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 28.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(R.string.what_strangers_can_see),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f))
        if (loaded) {
            if (mine != null) {
                Icon(Icons.Filled.CheckCircle, null, tint = green, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.published), style = MaterialTheme.typography.titleMedium,
                    color = green)
            } else {
                Icon(Icons.Filled.VisibilityOff, null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.not_published), style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    GroupedCard {
        when {
            !loaded -> Row(Modifier.fillMaxWidth().padding(vertical = 14.dp),
                horizontalArrangement = Arrangement.Center) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            }
            mine != null -> {
                Text(mine.intro, style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp))
                val greeting = mine.greeting.orEmpty()
                if (greeting.isNotEmpty()) {
                    GroupedRowDivider(inset = false)
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(stringResource(R.string.greeting), style = MaterialTheme.typography.bodyLarge)
                        Text(greeting, style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.End, modifier = Modifier.weight(1f))
                    }
                }
                GroupedRowDivider(inset = false)
                LinkRow(stringResource(R.string.edit), onEditIntro)
                GroupedRowDivider(inset = false)
                Text(stringResource(R.string.take_down), style = MaterialTheme.typography.bodyLarge,
                    color = if (isWorking) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.error,
                    modifier = Modifier.fillMaxWidth().clickable(enabled = !isWorking, onClick = onTakeDown)
                        .padding(horizontal = 16.dp, vertical = 12.dp))
            }
            else -> {
                if (persona != null) {
                    // iOS `ComposedIntroLoader`: the portrait, written once
                    // and cached; the wait is shown rather than the notes.
                    // Keyed like iOS's `.task(id:)`: on the inputs' hash, so a
                    // persona re-emitted with the same intro inputs does not
                    // restart the wait.
                    val introKey = PublicIntroComposer.sources(persona, targetLanguage).key
                    val composed by produceState<String?>(null, introKey) {
                        value = null
                        value = PublicIntroComposer.compose(persona, targetLanguage)
                    }
                    val text = composed
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        when {
                            text == null -> {
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                                Text(stringResource(R.string.writing_your_introduction),
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            text.isEmpty() -> Text(stringResource(R.string.nothing_yet),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            else -> Text(text, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                    GroupedRowDivider(inset = false)
                }
                LinkRow(stringResource(R.string.publish), onEditIntro)
            }
        }
    }
    when {
        errorText != null -> Text(errorText, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
        mine != null -> GroupedFooter(stringResource(
            R.string.you_re_in_the_pool_other_learners_can_find_and_talk_with_you_b020a3, languageName))
        loaded -> GroupedFooter(stringResource(R.string.other_learners_can_t_find_you_yet))
    }
}

/** A `NavigationLink` row in a Form: the label in ink, the list's chevron. */
@Composable
private fun LinkRow(label: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(start = 16.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        MeChevron()
    }
}
