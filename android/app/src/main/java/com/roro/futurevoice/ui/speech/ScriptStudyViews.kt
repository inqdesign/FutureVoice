package com.roro.futurevoice.ui.speech

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.RecordVoiceOver
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.initializer
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.ScriptStudy
import com.roro.futurevoice.data.ScriptVoiceover
import com.roro.futurevoice.data.ScriptVoiceoverCenter
import com.roro.futurevoice.data.ScriptVoiceoverStore
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.ui.AllowanceSpentSheet
import com.roro.futurevoice.ui.FormCard
import com.roro.futurevoice.ui.FormDivider
import com.roro.futurevoice.ui.LibraryKind
import com.roro.futurevoice.ui.PaywallDialog
import com.roro.futurevoice.ui.ShadowScreen
import com.roro.futurevoice.ui.SpentPool
import com.roro.futurevoice.ui.WordCardSheet
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// MARK: - Study mode

/** iOS system colours, the same semantic literals the iOS study uses. */
private val SysYellow = Color(0xFFFFCC00)
private val SysOrange = Color(0xFFFF9500)
private val SysBlue = Color(0xFF007AFF)

internal object ScriptStudyStyle {
    fun fill(kind: ScriptStudy.Kind): Color? = when (kind) {
        ScriptStudy.Kind.EXPRESSION -> SysYellow.copy(alpha = 0.32f)
        ScriptStudy.Kind.GRAMMAR -> SysBlue.copy(alpha = 0.14f)
        ScriptStudy.Kind.WORD -> null
    }

    @Composable
    fun line(kind: ScriptStudy.Kind): Color = when (kind) {
        ScriptStudy.Kind.EXPRESSION -> SysOrange
        ScriptStudy.Kind.GRAMMAR -> SysBlue
        ScriptStudy.Kind.WORD -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    @Composable
    fun name(kind: ScriptStudy.Kind, count: Int): String = when (kind) {
        ScriptStudy.Kind.EXPRESSION -> stringResource(R.string.expressions_lld, count)
        ScriptStudy.Kind.GRAMMAR -> stringResource(R.string.grammar_lld, count)
        ScriptStudy.Kind.WORD -> stringResource(R.string.words_lld, count)
    }
}

/**
 * The script's paragraphs with the study highlights drawn IN the text and a
 * native-language translation under each paragraph (Script sheet, Study on) — iOS
 * `ScriptStudyText`. Tapping a highlight opens the app's own cards. Never on
 * the prompter.
 */
@Composable
internal fun ScriptStudyText(paragraphs: List<String>, study: ScriptStudy, onTap: (ScriptStudy.Highlight) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        paragraphs.forEachIndexed { p, para ->
            if (p > 0) FormDivider(inset = 0.dp)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                HighlightedParagraph(para, study.highlightsIn(p), onTap)
                study.paragraphNotes.getOrNull(p)?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun HighlightedParagraph(para: String, highlights: List<ScriptStudy.Highlight>,
                                 onTap: (ScriptStudy.Highlight) -> Unit) {
    val text: AnnotatedString = remember(para, highlights) {
        buildAnnotatedString {
            append(para)
            for (h in highlights) {
                val fill = ScriptStudyStyle.fill(h.kind) ?: continue
                if (h.offset + h.length <= para.length) addStyle(SpanStyle(background = fill), h.offset, h.offset + h.length)
            }
        }
    }
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val colors = highlights.associate { it.id to ScriptStudyStyle.line(it.kind) }
    val density = LocalDensity.current
    val stroke = with(density) { 1.3.dp.toPx() }
    val drop = with(density) { 2.dp.toPx() }
    val dots = with(density) { PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 2.5.dp.toPx())) }
    val base = MaterialTheme.typography.bodyLarge
    Text(
        text,
        style = base.copy(lineHeight = base.lineHeight * 1.25f),
        onTextLayout = { layout = it },
        modifier = Modifier
            .drawBehind {
                val l = layout ?: return@drawBehind
                for (h in highlights) {
                    val end = h.offset + h.length
                    if (end > l.layoutInput.text.length || h.length <= 0) continue
                    val first = l.getLineForOffset(h.offset)
                    val last = l.getLineForOffset(end - 1)
                    for (line in first..last) {
                        val x0 = if (line == first) l.getHorizontalPosition(h.offset, true) else l.getLineLeft(line)
                        val x1 = if (line == last) l.getBoundingBox(end - 1).right else l.getLineRight(line)
                        val y = l.getLineBaseline(line) + drop
                        drawLine(colors[h.id] ?: Color.Gray, Offset(x0, y), Offset(x1, y), stroke,
                            pathEffect = if (h.kind == ScriptStudy.Kind.WORD) dots else null)
                    }
                }
            }
            .pointerInput(highlights) {
                detectTapGestures { pos ->
                    val l = layout ?: return@detectTapGestures
                    val o = l.getOffsetForPosition(pos)
                    highlights.firstOrNull { o >= it.offset && o < it.offset + it.length }?.let(onTap)
                }
            },
    )
}

/** Kind · count for each kind present (iOS `ScriptStudyLegend`); how to use
 *  them is the study switch's footer, so this row never truncates. */
@Composable
internal fun ScriptStudyLegend(study: ScriptStudy, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        ScriptStudy.Kind.entries.forEach { kind ->
            val n = study.count(kind)
            if (n > 0) Row(verticalAlignment = Alignment.CenterVertically) {
                val lineColor = ScriptStudyStyle.line(kind)
                val dots = with(LocalDensity.current) { PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 2.dp.toPx())) }
                Box(Modifier.size(width = 14.dp, height = 12.dp)
                    .background(ScriptStudyStyle.fill(kind) ?: Color.Transparent)
                    .drawBehind {
                        val y = size.height - 1.dp.toPx()
                        drawLine(lineColor, Offset(0f, y), Offset(size.width, y), 1.3.dp.toPx(),
                            pathEffect = if (kind == ScriptStudy.Kind.WORD) dots else null)
                    })
                Spacer(Modifier.width(5.dp))
                Text(ScriptStudyStyle.name(kind, n), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
        }
    }
}

/** What a tapped highlight opens: the existing word card, or the expression
 *  card with the study note as its "In this script" section (iOS
 *  `ScriptStudyCardSheet`). Grammar opens the expression card. */
@Composable
internal fun ScriptStudyCard(highlight: ScriptStudy.Highlight, study: ScriptStudy, language: String,
                             onDismiss: () -> Unit) {
    if (highlight.kind == ScriptStudy.Kind.WORD) {
        fun key(h: ScriptStudy.Highlight) = VocabLemmas.lemma((h.lemma ?: h.text).trim(), language.substringBefore('-'))
        val words = study.highlights.filter { it.kind == ScriptStudy.Kind.WORD }.map(::key).distinct()
        WordCardSheet(terms = words, initialTerm = key(highlight), kind = LibraryKind.WORDS,
            language = language, onDismiss = onDismiss)
    } else {
        val phrases = study.highlights.filter { it.kind != ScriptStudy.Kind.WORD }
        WordCardSheet(terms = phrases.map { it.text }.distinct(), initialTerm = highlight.text,
            kind = LibraryKind.EXPRESSIONS, language = language, onDismiss = onDismiss,
            sceneContext = phrases.reversed().associate { it.text to (it.note to it.example) },
            contextHeading = stringResource(R.string.in_this_script))
    }
}

// MARK: - Walls

/** The answer when a voiceover can't be paid for — the same two surfaces
 *  every metered launch uses: the paywall for an account with nothing to
 *  spend, the spent-pool sheet for a subscriber whose month is used (iOS
 *  `TalkWall`). A fair-use stop is an alert. */
internal enum class VoiceoverWall { PAYWALL, SPENT, FAIR_USE }

internal fun EdgeError.voiceoverWall(): VoiceoverWall? = when (this) {
    EdgeError.InsufficientCredits -> { BillingGate.invalidate(); VoiceoverWall.PAYWALL }
    EdgeError.DailyCapReached -> VoiceoverWall.SPENT
    EdgeError.FairUseLimit -> VoiceoverWall.FAIR_USE
    else -> null
}

@Composable
internal fun VoiceoverWallHost(wall: VoiceoverWall?, onClear: () -> Unit) {
    var paywall by remember { mutableStateOf(false) }
    when (wall) {
        VoiceoverWall.PAYWALL -> { LaunchedEffect(Unit) { paywall = true; onClear() } }
        VoiceoverWall.SPENT -> AllowanceSpentSheet(SpentPool.TALK, onReview = onClear,
            onUpgrade = { onClear(); paywall = true }, onDismiss = onClear)
        VoiceoverWall.FAIR_USE -> AlertDialog(onDismissRequest = onClear,
            confirmButton = { TextButton(onClick = onClear) { Text(stringResource(R.string.ok)) } },
            text = { Text(EdgeError.FairUseLimit.message.orEmpty()) })
        null -> Unit
    }
    if (paywall) PaywallDialog(onDismiss = { paywall = false; BillingGate.invalidate() })
}

/** iOS `BillingGate.blocks()`: true = the account has nothing to spend. A
 *  no is never given from cache. */
internal suspend fun voiceoverBlocked(): Boolean {
    val auth = AuthRepository()
    val (go, fresh) = BillingGate.decide(BillingGate.account, auth.userId != null) {
        runCatching { AccountStatus.load(auth) }.getOrNull()
    }
    fresh?.let { BillingGate.remember(it) }
    return !go
}

/** The account a price line is drawn against: the gate's cache, read once
 *  if it has none (iOS `gate.warm()`). */
@Composable
internal fun rememberGateAccount(): AccountStatus? {
    var account by remember { mutableStateOf(BillingGate.account) }
    LaunchedEffect(Unit) {
        if (account == null && com.roro.futurevoice.capture.flags.SpeechCaptureFlags.account == null) {
            runCatching { AccountStatus.load(AuthRepository()) }.getOrNull()?.let {
                BillingGate.remember(it); account = it
            }
        }
    }
    return com.roro.futurevoice.capture.flags.SpeechCaptureFlags.account ?: account
}

/** "Uses 9 min of talk time · 42 min of talk time left" — the one line every
 *  price is shown with (iOS `ScriptVoiceover.priceLine`). */
@Composable
internal fun voiceoverPriceLine(minutes: Int, account: AccountStatus?): String =
    listOfNotNull(
        stringResource(R.string.uses_lld_min_of_talk_time, minutes),
        ScriptVoiceover.remainingMinutes(account)?.let { stringResource(R.string.lld_min_of_talk_time_left, it) },
    ).joinToString(" · ")

// MARK: - Hear it in my voice

/** The Script sheet's voiceover section: the priced button before it exists,
 *  a progress line while it is made, then Play and Shadow — free forever
 *  (iOS `ScriptVoiceoverSection`). */
@Composable
internal fun ScriptVoiceoverSection(script: SpeechScript, voiceId: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val jobs by ScriptVoiceoverCenter.jobs.collectAsStateWithLifecycle()
    val revision by ScriptVoiceoverCenter.revision.collectAsStateWithLifecycle()
    val account = rememberGateAccount()
    val player = remember { Mp3Player(context.cacheDir, source = "speech_voiceover") }
    var playing by remember { mutableStateOf(false) }
    var wall by remember { mutableStateOf<VoiceoverWall?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var shadowing by remember { mutableStateOf<ScriptVoiceoverStore.Stored?>(null) }
    var existing by remember { mutableStateOf<ScriptVoiceoverStore.Stored?>(null) }
    LaunchedEffect(script.body, voiceId, revision) {
        existing = withContext(Dispatchers.IO) { ScriptVoiceoverCenter.existing(context, script, voiceId) }
    }
    DisposableEffect(Unit) { onDispose { player.stop() } }
    val quote = remember(script.body, script.language) { ScriptVoiceover.quoteMinutes(script.body, script.language) }
    val job = jobs[ScriptVoiceoverCenter.keyFor(script, voiceId)]
    val accent = MaterialTheme.colorScheme.primary

    fun start() {
        scope.launch {
            if (voiceoverBlocked()) { wall = VoiceoverWall.PAYWALL; return@launch }
            ScriptVoiceoverCenter.clearFailure(script, voiceId)
            try {
                ScriptVoiceoverCenter.make(context, script, voiceId, quote)
            } catch (e: EdgeError) {
                val w = e.voiceoverWall()
                if (w != null) wall = w else error = e.message
            } catch (_: Exception) {
                // Shown in the footer from the job's state.
            }
        }
    }

    Column(Modifier.fillMaxWidth().padding(top = 20.dp)) {
        FormCard {
            val stored = existing
            when {
                stored != null -> {
                    VoiceoverRow(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        stringResource(if (playing) R.string.pause else R.string.play_in_my_voice), accent) {
                        if (playing) { player.stop(); playing = false }
                        else scope.launch { playing = true; runCatching { player.play(stored.file) }; playing = false }
                    }
                    FormDivider()
                    VoiceoverRow(Icons.Filled.GraphicEq, stringResource(R.string.shadow_it), accent) {
                        player.stop(); playing = false; shadowing = stored
                    }
                }
                job is ScriptVoiceoverCenter.Job.Making -> Row(Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.making_it_in_your_voice), Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyLarge)
                    Text("${job.done}/${job.total}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                else -> {
                    val enabled = quote <= ScriptVoiceover.MAX_MINUTES
                    VoiceoverRow(Icons.Outlined.RecordVoiceOver,
                        stringResource(R.string.hear_it_in_my_voice_lld_min, quote),
                        if (enabled) accent else MaterialTheme.colorScheme.onSurfaceVariant,
                        enabled = enabled) { start() }
                }
            }
        }
        val footer: @Composable () -> Unit = {
            when {
                existing != null -> FooterText(stringResource(R.string.yours_to_replay_and_shadow_free))
                quote > ScriptVoiceover.MAX_MINUTES ->
                    FooterText(stringResource(R.string.this_script_is_too_long_to_make_in_your_voice))
                else -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    FooterText(voiceoverPriceLine(quote, account))
                    (job as? ScriptVoiceoverCenter.Job.Failed)?.let {
                        FooterText(it.message, Color(0xFFFF3B30))
                    }
                }
            }
        }
        Box(Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp)) { footer() }
    }

    VoiceoverWallHost(wall) { wall = null }
    error?.let { msg ->
        AlertDialog(onDismissRequest = { error = null },
            confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) } },
            title = { Text(stringResource(R.string.couldn_t_make_it_in_your_voice)) },
            text = { Text(msg) })
    }
    shadowing?.let { stored ->
        Dialog(onDismissRequest = { shadowing = null },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
                ShadowScreen(line = script.body, voiceId = voiceId, targetLanguage = script.language,
                    onBack = { shadowing = null },
                    turnId = ScriptVoiceover.shadowTurnId(stored.file.name),
                    presetAudio = stored.file, presetTimings = stored.meta.timings)
            }
        }
    }
}

@Composable
private fun VoiceoverRow(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tint: Color,
                         enabled: Boolean = true, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick)
        .padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(16.dp))
        Text(label, color = tint, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun FooterText(text: String, color: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = color)
}

/** Study loading / failed, under the plain text while Study is on. */
@Composable
internal fun ScriptStudyStatus(failed: Boolean, onRetry: () -> Unit) {
    if (failed) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
            Text(stringResource(R.string.the_study_notes_couldn_t_be_prepared_try_again),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            com.roro.futurevoice.ui.brand.IosTonalButton(onClick = onRetry) { Text(stringResource(R.string.try_again)) }
        }
    } else {
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.preparing_study_notes), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    Spacer(Modifier.height(0.dp))
}

/** The learner's voice, as the app holds it (iOS `appState.voiceCloneId`).
 *  The ACTIVITY's AppViewModel, named explicitly — a sheet resolving its own
 *  owner could build a second, empty one, and then "make it in my voice"
 *  vanished from every Speech sheet. If the app's copy is still empty, the
 *  server is asked directly (the word card's once-per-process lookup). */
@Composable
internal fun rememberCloneVoiceId(): String? {
    val captured = com.roro.futurevoice.capture.flags.SpeechCaptureFlags.voiceId
    val context = LocalContext.current
    val activity = remember(context) {
        var c: android.content.Context? = context
        while (c is android.content.ContextWrapper && c !is androidx.activity.ComponentActivity) c = c.baseContext
        c as? androidx.activity.ComponentActivity
    }
    val fromApp = if (activity != null) {
        val app: com.roro.futurevoice.ui.AppViewModel = androidx.lifecycle.viewmodel.compose.viewModel(
            viewModelStoreOwner = activity,
            factory = androidx.lifecycle.viewmodel.viewModelFactory {
                initializer { com.roro.futurevoice.ui.AppViewModel(context.applicationContext) }
            })
        val state by app.state.collectAsStateWithLifecycle()
        state.voiceId
    } else null
    val fromServer = com.roro.futurevoice.ui.rememberCloneVoiceId()
    return captured ?: fromApp ?: fromServer
}

/** The learner's level for the active language (iOS `appState.proficiency`). */
@Composable
internal fun rememberLevel(): com.roro.futurevoice.data.CefrLevel {
    val context = LocalContext.current
    val app: com.roro.futurevoice.ui.AppViewModel = androidx.lifecycle.viewmodel.compose.viewModel(
        factory = androidx.lifecycle.viewmodel.viewModelFactory {
            initializer { com.roro.futurevoice.ui.AppViewModel(context.applicationContext) }
        })
    val state by app.state.collectAsStateWithLifecycle()
    return state.level
}
