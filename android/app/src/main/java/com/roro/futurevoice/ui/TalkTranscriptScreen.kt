package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.JapaneseMorph
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.MisheardExclusion
import com.roro.futurevoice.data.PhraseAudioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.WeeklyTestEngine
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.net.Translator
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TurnSuggestion
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DialogueLine
import com.roro.futurevoice.ui.brand.DialogueScale
import com.roro.futurevoice.ui.brand.DialogueSpeaker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The talk book's Replay destination (iOS `TalkTranscriptView`): the whole
 * conversation through the app's ONE dialogue surface, the stored turn audio
 * replayed in order, and Replay / Continue pinned at the bottom over a
 * dissolving edge — the way a Watch book's scene sits behind its Watch button.
 *
 * Replay is always free: it plays what the call already recorded (the
 * learner's mic, the fluent self's synthesized lines) and a turn whose audio
 * didn't survive is skipped, never re-synthesized.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TalkTranscriptScreen(
    session: Session,
    language: String,
    level: CefrLevel,
    onBack: () -> Unit,
    /** Pick the talk back up — the book page's own (gated) Continue. Null
     *  when the host has nowhere to start a call from. */
    onContinue: (() -> Unit)?,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val revision by StoreEvents.revision.collectAsState()
    // What this page draws: the host's copy, replaced the moment a line is
    // marked misheard so the dimmed row doesn't wait on the host's reload.
    var shown by remember(session) { mutableStateOf(session) }
    val session = shown
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
    }
    val player = remember { Mp3Player(context.cacheDir) }
    var playJob by remember { mutableStateOf<Job?>(null) }
    var isPlaying by remember { mutableStateOf(false) }
    var currentIndex by remember { mutableStateOf<Int?>(null) }
    // Gate before stopping — a stop that lets the sequence carry on would
    // chain into the next turn after the screen is gone.
    DisposableEffect(Unit) { onDispose { playJob?.cancel(); player.stop() } }

    // Which turns still have their recording — read once, off the main thread.
    var audioFiles by remember(session.id) { mutableStateOf<Map<String, java.io.File>>(emptyMap()) }
    LaunchedEffect(session.id) {
        audioFiles = withContext(Dispatchers.IO) {
            session.turns.mapNotNull { t -> WeeklyTestEngine.turnAudio(context, t)?.let { t.id to it } }.toMap()
        }
    }

    // Per fluent-self line: the notebook key of every display piece and the
    // pieces worth picking up — pickup words untouched, plus words being
    // studied (iOS `turnTokenKeys` / `highlightIndices`).
    var pickupWords by remember(session.id) { mutableStateOf<List<String>>(emptyList()) }
    var tokenKeys by remember(session.id) { mutableStateOf<Map<String, List<String>>>(emptyMap()) }
    var highlights by remember(session.id) { mutableStateOf<Map<String, Set<Int>>>(emptyMap()) }
    LaunchedEffect(session.id, revision, level) {
        val vocab = VocabStore.shared(context)
        val fluent = session.turns.filter { it.role == TurnRole.FLUENT_SELF }
        val pickup = vocab.pickupWords(fluent.map { it.transcript }, level, language)
        val studying = vocab.studying(language).toSet()
        val keys = withContext(Dispatchers.Default) {
            fluent.associate { t -> t.id to pieceKeys(t.transcript, language) }
        }
        val pickupSet = pickup.toSet()
        pickupWords = pickup
        tokenKeys = keys
        highlights = keys.mapValues { (_, ks) ->
            ks.indices.filter { i ->
                val k = ks[i]
                k.isNotEmpty() && (k in studying || k in pickupSet)
            }.toSet()
        }
    }

    var wordCard by remember { mutableStateOf<Pair<String, List<String>>?>(null) }
    // Shadow opens over this page (iOS sheets it), so returning lands back
    // on the same line rather than on the book's cover.
    var shadow by remember { mutableStateOf<Pair<String, String?>?>(null) }
    shadow?.let { (line, turnId) ->
        ShadowScreen(line = line,
            voiceId = PhraseAudioStore.shared(context).ownVoiceLineage.firstOrNull().orEmpty(),
            targetLanguage = language, turnId = turnId,
            onBack = { shadow = null; StoreEvents.bump() })
        return
    }
    wordCard?.let { (term, list) ->
        WordCardSheet(terms = list, initialTerm = term, kind = LibraryKind.WORDS,
            language = language, onShadow = { shadow = it to null },
            onDismiss = { wordCard = null })
    }

    fun stopPlayback() {
        isPlaying = false
        playJob?.cancel(); playJob = null
        player.stop()
    }

    /** Sequential replay of the stored per-turn audio, from [from]. */
    fun playFrom(from: Int) {
        stopPlayback()
        isPlaying = true
        playJob = scope.launch {
            var i = from
            while (i < session.turns.size) {
                val file = audioFiles[session.turns[i].id]
                if (file != null) {
                    currentIndex = i
                    val ok = runCatching { player.play(file) }.isSuccess
                    if (!ok) break
                }
                i += 1
            }
            isPlaying = false
            currentIndex = null
        }
    }

    fun playOne(turn: Turn) {
        val file = audioFiles[turn.id] ?: return
        stopPlayback()
        playJob = scope.launch { runCatching { player.play(file) } }
    }

    val listState = rememberLazyListState()
    LaunchedEffect(currentIndex) {
        // +1: the caption above the first line is item 0.
        currentIndex?.let { listState.animateScrollToItem(it + 1, scrollOffset = -200) }
    }

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Text(session.displayTitle ?: stringResource(R.string.conversation),
                        style = MaterialTheme.typography.titleMedium, maxLines = 1,
                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
    ) { padding ->
        var barHeight by remember { mutableIntStateOf(0) }
        Box(Modifier.padding(padding).fillMaxSize()) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp,
                    bottom = 20.dp + with(LocalDensity.current) { barHeight.toDp() }),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item(key = "caption") {
                    Text(stringResource(R.string.highlighted_words_are_worth_picking_up_tap_one_to_check_it_o_7964d7),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                itemsIndexed(session.turns, key = { _, t -> t.id }) { idx, turn ->
                    // iOS `.contextMenu` on the row: the learner's own line,
                    // not yet flagged, can be marked misheard. No undo — iOS
                    // has none (the cards it minted are already gone).
                    var menu by remember(turn.id) { mutableStateOf(false) }
                    val canExclude = turn.role == TurnRole.USER && !turn.excludedFromScoring
                    Box {
                    Column(
                        Modifier.then(if (canExclude) Modifier.pointerInput(turn.id) {
                            detectTapGestures(onLongPress = { menu = true })
                        } else Modifier),
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        TranscriptRow(
                            turn = turn,
                            language = language,
                            nativeLanguage = nativeLanguage,
                            isCurrent = currentIndex == idx,
                            hasAudio = turn.id in audioFiles,
                            keys = tokenKeys[turn.id].orEmpty(),
                            highlighted = highlights[turn.id].orEmpty(),
                            onWordTap = { key ->
                                wordCard = key to (if (key in pickupWords) pickupWords else listOf(key))
                            },
                            onListen = { playOne(turn) },
                            onShadow = { line, id -> stopPlayback(); shadow = line to id },
                            modifier = Modifier.alpha(if (turn.excludedFromScoring) 0.45f else 1f),
                        )
                        if (turn.excludedFromScoring) {
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(Icons.Filled.MicOff, contentDescription = null,
                                    modifier = Modifier.size(12.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                                Text(stringResource(R.string.excluded_from_scoring_marked_as_misheard),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                            }
                        }
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.misheard_exclude_from_scoring),
                                color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Filled.MicOff, contentDescription = null,
                                tint = MaterialTheme.colorScheme.error) },
                            onClick = {
                                menu = false
                                scope.launch {
                                    MisheardExclusion.excludeTurn(context, session.id, turn.id,
                                        language)?.let { shown = it }
                                }
                            })
                    }
                    }
                }
            }

            // The controls FLOAT (iOS `fadingBottomBar`, as the live call
            // does): the transcript runs on underneath and dissolves into a
            // wash of the page colour instead of stopping at a solid strip.
            val page = AppSurfaces.ground
            Row(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .onSizeChanged { barHeight = it.height }
                    .drawBehind {
                        val fade = 64.dp.toPx()
                        drawRect(Brush.verticalGradient(listOf(page.copy(alpha = 0f), page),
                            startY = -fade, endY = 0f),
                            topLeft = Offset(0f, -fade), size = Size(size.width, fade))
                        drawRect(page)
                    }
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                FilledTonalButton(
                    onClick = { if (isPlaying) stopPlayback() else playFrom(currentIndex ?: 0) },
                    modifier = Modifier.weight(1f).height(52.dp),
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                        contentColor = MaterialTheme.colorScheme.primary),
                ) {
                    Icon(if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(if (isPlaying) R.string.pause else R.string.replay),
                        style = MaterialTheme.typography.titleMedium, maxLines = 1)
                }
                if (onContinue != null) {
                    Button(
                        onClick = { stopPlayback(); onContinue() },
                        modifier = Modifier.weight(1f).height(52.dp),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Chat, contentDescription = null,
                            modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.continue_),
                            style = MaterialTheme.typography.titleMedium, maxLines = 1)
                    }
                }
            }
        }
    }
}

/** The notebook key of every display piece of a fluent-self line, aligned
 *  with [displayPieces] — "" where nothing can be looked up. */
private fun pieceKeys(text: String, language: String): List<String> =
    if (WordSplitter.spaced(language)) {
        text.split(" ").filter { it.isNotEmpty() }.map { token ->
            val bare = token.trim { !it.isLetterOrDigit() && it != '\'' && it != '’' }
            if (bare.isEmpty()) "" else VocabLemmas.lemma(bare, language)
        }
    } else {
        JapaneseMorph.pieceKeys(text, CoreVocabulary.set(language), CoreVocabulary.forms(language))
    }

/** The line cut where words are — a spaced language's tokens (punctuation
 *  attached), or the segmenter's words and the 、。 between them. */
private fun displayPieces(text: String, language: String): List<JapaneseMorph.Piece> =
    if (WordSplitter.spaced(language)) {
        text.split(" ").filter { it.isNotEmpty() }.map { JapaneseMorph.Piece(it, true) }
    } else JapaneseMorph.displayPieces(text)

/**
 * One transcript line — the shared [DialogueLine] chrome, with this page's
 * accessories under it: Listen / Shadow / Meaning, the meaning itself, and
 * the correction box under the learner's lines (iOS `TranscriptRow`).
 */
@Composable
private fun TranscriptRow(
    turn: Turn,
    language: String,
    nativeLanguage: String,
    isCurrent: Boolean,
    hasAudio: Boolean,
    keys: List<String>,
    highlighted: Set<Int>,
    onWordTap: (String) -> Unit,
    onListen: () -> Unit,
    onShadow: (line: String, turnId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isUser = turn.role == TurnRole.USER
    val tint = MaterialTheme.colorScheme.primary
    var translation by remember(turn.id) {
        mutableStateOf(Translator.cached(context, turn.transcript, nativeLanguage))
    }
    var showingMeaning by remember(turn.id) { mutableStateOf(false) }
    var loadingMeaning by remember(turn.id) { mutableStateOf(false) }

    DialogueLine(
        speaker = if (isUser) DialogueSpeaker.USER else DialogueSpeaker.OTHER,
        name = stringResource(if (isUser) R.string.you else R.string.future_self_1384d5),
        scale = DialogueScale.STANDARD,
        isCurrent = isCurrent,
        modifier = modifier,
        accessory = {
            Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = if (isUser) Alignment.End else Alignment.Start) {
                val canMeaning = !isUser && !LanguageCatalog.sameLanguage(language, nativeLanguage)
                if (hasAudio || canMeaning) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (hasAudio) SmallTonal(Icons.Outlined.PlayCircle,
                            stringResource(R.string.listen), onClick = onListen)
                        if (!isUser && hasAudio) SmallTonal(Icons.Filled.GraphicEq,
                            stringResource(R.string.shadow)) { onShadow(turn.transcript, turn.id) }
                        if (canMeaning) SmallTonal(Icons.Outlined.Translate,
                            stringResource(if (showingMeaning) R.string.hide_meaning else R.string.meaning),
                            loading = loadingMeaning) {
                            if (showingMeaning) { showingMeaning = false; return@SmallTonal }
                            showingMeaning = true
                            if (translation == null && !loadingMeaning) {
                                loadingMeaning = true
                                scope.launch {
                                    val t = Translator.translate(context, turn.transcript, nativeLanguage)
                                    translation = t
                                    loadingMeaning = false
                                    if (t == null) showingMeaning = false
                                }
                            }
                        }
                    }
                }
                if (!isUser && showingMeaning) translation?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (isUser) turn.suggestion?.let { s ->
                    CorrectionBox(s, original = turn.transcript, language = language,
                        nativeLanguage = nativeLanguage,
                        onShadow = { onShadow(s.alternative, TalkCurriculum.correctionId(turn.id)) })
                }
            }
        },
    ) {
        if (isUser || highlighted.isEmpty()) {
            Text(turn.transcript)
        } else {
            // One Text with normal spacing — only the words worth picking up
            // are lit and tappable; the highlight IS the signal.
            val pieces = remember(turn.transcript, language) { displayPieces(turn.transcript, language) }
            val spaced = WordSplitter.spaced(language)
            val line = buildAnnotatedString {
                pieces.forEachIndexed { i, piece ->
                    val key = keys.getOrNull(i).orEmpty()
                    if (piece.isWord && i in highlighted && key.isNotEmpty()) {
                        withLink(LinkAnnotation.Clickable(tag = "w$i",
                            styles = TextLinkStyles(SpanStyle(color = tint, fontWeight = FontWeight.Medium,
                                textDecoration = TextDecoration.Underline)),
                            linkInteractionListener = { onWordTap(key) })) { append(piece.text) }
                    } else append(piece.text)
                    if (spaced && i < pieces.lastIndex) append(" ")
                }
            }
            Text(line)
        }
    }
}

/**
 * The correction — the part of a talk that actually teaches (iOS
 * `suggestionBox`): "More natural" with the changed words lit, the reason,
 * the grammar slips, Shadow, and the reason in the learner's own language.
 */
@Composable
private fun CorrectionBox(
    s: TurnSuggestion,
    original: String,
    language: String,
    nativeLanguage: String,
    onShadow: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val tint = MaterialTheme.colorScheme.primary
    var showing by remember(s.alternative) { mutableStateOf(false) }
    var loading by remember(s.alternative) { mutableStateOf(false) }
    var reasonNative by remember(s.alternative) {
        mutableStateOf(Translator.cachedExplanation(context, original, s.alternative, nativeLanguage))
    }
    val line = remember(s.alternative, original, tint) {
        correctionLine(s.alternative, original, language,
            SpanStyle(color = tint, fontWeight = FontWeight.SemiBold))
    }
    Column(
        Modifier.fillMaxWidth()
            .background(tint.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null,
                modifier = Modifier.size(14.dp), tint = tint)
            Text(stringResource(R.string.more_natural), style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold, color = tint)
        }
        Text(line, style = MaterialTheme.typography.bodyMedium)
        if (s.reason.isNotBlank()) Text(s.reason, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        s.fixes?.takeIf { it.isNotEmpty() }?.let { fixes ->
            HorizontalDivider(Modifier.padding(vertical = 2.dp))
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Outlined.Verified, contentDescription = null, modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.grammar), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TurnFixRows(fixes)
        }
        SmallTonal(Icons.Filled.GraphicEq, stringResource(R.string.shadow), onClick = onShadow)
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.clickable {
                if (showing) { showing = false; return@clickable }
                showing = true
                if (reasonNative == null && !loading) {
                    loading = true
                    scope.launch {
                        val t = Translator.explainCorrection(context, original, s.alternative, nativeLanguage)
                        reasonNative = t
                        loading = false
                        if (t == null) showing = false
                    }
                }
            }) {
            if (loading) CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp)
            else Icon(Icons.Outlined.Translate, contentDescription = null,
                modifier = Modifier.size(14.dp), tint = tint)
            Text(stringResource(if (showing) R.string.hide else R.string.explain_in_my_language),
                style = MaterialTheme.typography.labelMedium, color = tint)
        }
        if (showing) reasonNative?.let {
            Text(it, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** iOS's small `.bordered` accent capsule — the row actions under a line. */
@Composable
private fun SmallTonal(icon: ImageVector, label: String, loading: Boolean = false, onClick: () -> Unit) {
    val tint = MaterialTheme.colorScheme.primary
    FilledTonalButton(
        onClick = onClick,
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
        modifier = Modifier.height(32.dp),
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = tint.copy(alpha = 0.15f), contentColor = tint),
    ) {
        if (loading) CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp)
        else Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        Text(label, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
    }
}
