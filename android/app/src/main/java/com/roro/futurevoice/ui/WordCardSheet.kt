package com.roro.futurevoice.ui

import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.foundation.layout.Spacer
import androidx.compose.material.icons.filled.PlayCircleOutline
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Check
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CheckCircle
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.luminance
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.core.InstallSalt
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.VoiceCloneRepository
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch

/**
 * One term's card — what a Library row opens.
 *
 * The library was a list you could only read: every number in the app points
 * at these rows, and tapping one did nothing. This is the other half — the
 * dictionary entry ([WordLore], generated once and shared by everyone with
 * the same native/target pair, so it is free and usually warm from the row's
 * own gloss), the learner's own sentences with the term in them, and the two
 * verdicts that actually move it (keep studying / I know it).
 *
 * It is NOT [TalkGoalSheet]. That one is thin on purpose — a call is running
 * underneath it and the second sense is noise. Here there is nothing else
 * happening, so the whole entry belongs on screen.
 */

/**
 * The clone's id, resolved once per process. The speak button is the only
 * thing that needs it and the row lives on the server, so re-reading it every
 * time a card opens would put a network round trip in front of a local list.
 */
@Volatile private var cachedVoiceId: String? = null

/** A sheet is not a page: past a handful, the learner's own lines bury the
 *  entry they came here to read. */
private const val MAX_SOURCE_LINES = 6

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WordCardSheet(
    /** The visible list, in list order — what previous/next walks. */
    terms: List<String>,
    initialTerm: String,
    kind: LibraryKind,
    language: String,
    /** Say it after the fluent self — the same screen the book pages open. */
    onShadow: (String) -> Unit = {},
    onDismiss: () -> Unit,
    /** The header when the card walks the NOTEBOOK ("My words · 10", iOS
     *  `WordCard`'s title off a dealt list): the count is the notebook's,
     *  not a position. Null titles by position — "3 / 10". */
    notebookTitle: String? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val vocab = remember { VocabStore.shared(context) }
    val lore = remember { WordLore(AuthRepository()) }
    val mp3 = remember { Mp3Player(context.cacheDir, source = "library") }
    // The learner's own language, straight off the same key the widgets read
    // — the card is reached from a top-level screen that is handed only the
    // target language.
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
    }
    val isWord = kind == LibraryKind.WORDS

    var index by remember { mutableIntStateOf(terms.indexOf(initialTerm).coerceAtLeast(0)) }
    val term = terms.getOrNull(index) ?: initialTerm

    var entry by remember { mutableStateOf<WordLore.Entry?>(null) }
    var loading by remember { mutableStateOf(true) }
    /** The lookup came back empty. [WordLore] generates on demand, so this is
     *  a failed round trip rather than "no entry" — it has a retry attached. */
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    var sentences by remember { mutableStateOf<List<SourceLine>>(emptyList()) }
    var kept by remember { mutableStateOf(false) }
    var known by remember { mutableStateOf(false) }
    var voiceId by remember { mutableStateOf(com.roro.futurevoice.capture.flags.PracticeCaptureFlags.voiceId ?: cachedVoiceId) }
    var speaking by remember { mutableStateOf(false) }
    /** Sentences already on file, read once — an example's long-press says
     *  "Saved" instead of offering it again (iOS 71c5e2da). */
    var savedSentences by remember { mutableStateOf<Set<String>>(emptySet()) }
    LaunchedEffect(Unit) {
        savedSentences = com.roro.futurevoice.data.DrillStore.shared(context).sentenceKeys(language)
    }
    val exampleReason = stringResource(R.string.example_for, term)

    DisposableEffect(Unit) { onDispose { mp3.stop() } }

    LaunchedEffect(Unit) {
        if (voiceId != null) return@LaunchedEffect
        val uid = AuthRepository().userId ?: return@LaunchedEffect
        voiceId = runCatching { VoiceCloneRepository().activeVoiceId(uid) }
            .getOrNull()?.also { cachedVoiceId = it }
    }

    // Local reads: the two verdicts and the learner's own lines. Separate from
    // the lookup below so a slow generation never holds up the state the card
    // can answer from disk.
    LaunchedEffect(term, attempt) {
        val bookmarked = if (isWord) vocab.isStudying(term, language)
        else vocab.isStudyingExpression(term, language)
        kept = bookmarked
        known = if (isWord) {
            // A word the learner has SAID counts as known too — using it in a
            // real talk is stronger evidence than a self-check. Except while
            // it is bookmarked: Keep and I-know are opposite verdicts on one
            // row, so the bookmark wins and the `used` record is untouched.
            val state = vocab.state(term.lowercase(), language)
            state == "known" || (state != null && !bookmarked)
        } else vocab.isKnownExpression(term, language)
        sentences = ownLines(context, language, term, isWord)
    }

    LaunchedEffect(term, attempt) {
        // `loading` first: clearing the entry before flipping it shows the
        // no-entry state for a frame every time the card walks to the next
        // term. A term swap cancels this effect, so no stale write can land.
        loading = true
        failed = false
        entry = null
        val fetched = com.roro.futurevoice.capture.flags.PracticeCaptureFlags.lookup {
            lore.entry(term, nativeLanguage, language,
                if (isWord) WordLore.Kind.WORD else WordLore.Kind.EXPRESSION)
        }
        entry = fetched
        failed = fetched == null
        loading = false
    }

    fun speak() {
        val id = voiceId ?: return
        speaking = true
        scope.launch {
            runCatching {
                // Deterministic key = the server dedupes a re-tap of the same
                // term against the first synthesis, so replays are free.
                // Cache first: the same word must never be billed twice.
                val audio = com.roro.futurevoice.data.cachedSynthesis(
                    context, voiceId = id, text = term,
                    idempotencyKey = InstallSalt.ttsKey(term, id, timestamps = false),
                    purpose = "library")
                mp3.play(audio)
            }.onFailure { e ->
                // Nothing to spend (a spent free pool, or a PARKED voice —
                // both answer as the spent pool): the plans, not silence
                // (iOS `parkedPaywall`).
                if (e === com.roro.futurevoice.net.EdgeError.InsufficientCredits)
                    com.roro.futurevoice.data.BillingGate.showPaywall.value = true
            }
            speaking = false
        }
    }

    fun toggleKeep() {
        val next = !kept
        kept = next
        scope.launch {
            if (isWord) {
                if (next) vocab.addStudying(term, language)
                else vocab.removeStudying(term, language)
            } else vocab.setStudyingExpression(term, next, language)
            StoreEvents.bump()
        }
    }

    fun toggleKnown() {
        val next = !known
        known = next
        if (next) kept = false   // marking known retires it out of the notebook
        scope.launch {
            if (isWord) {
                // Records are keyed lowercase; the notebook keeps the display
                // form, so the studying entry is cleared against BOTH or a
                // capitalized word stays bookmarked after being retired.
                if (next) {
                    vocab.markKnown(term.lowercase(), language)
                    vocab.removeStudying(term, language)
                } else vocab.unmark(term.lowercase(), language)
            } else vocab.setKnownExpression(term, next, language)
            StoreEvents.bump()
        }
    }

    // Full height from the start: the entry is the page, and a half sheet
    // opens on the meanings with the verdicts below the fold.
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        // iOS's `.large` detent stops under the status bar with the page
        // behind it peeking above — a sheet, not a new screen.
        modifier = Modifier.statusBarsPadding().padding(top = 10.dp),
    ) {
      // The card is the page (iOS's `.large` detent): it fills the sheet,
      // the entry scrolls and the action bar stays pinned at the foot.
      Column(Modifier.fillMaxWidth().fillMaxHeight().bottomBarInsets()) {
        // Where you are in the list you came from. A dealt hand titles by
        // POSITION — that list isn't the notebook, so its count would be a
        // lie there; browsing the notebook keeps the count.
        val title = notebookTitle ?: stringResource(R.string.lld_of_lld, index + 1, terms.size)
        // iOS draws it as the sheet's inline nav title, which wears the
        // pixel display face (`RootView.roundedNavFont`).
        Text(
            title,
            style = com.roro.futurevoice.ui.brand.DisplayFace.style(title,
                androidx.compose.ui.text.TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold)),
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 14.dp))
        Column(
            // Bounded, so the pinned bar below always has room. A bottom
            // sheet measures its content with an UNBOUNDED height, where a
            // weight buys nothing and the bar is pushed off the screen.
            Modifier.fillMaxWidth()
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 22.dp).padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(26.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(term, fontSize = 34.sp, fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface)
                    // A kanji headword has to print its reading, or the card
                    // teaches a word nobody can say out loud. Several where
                    // the word has several (からい・つらい).
                    CoreVocabulary.reading(term, language)?.let { reading ->
                        Text(reading, style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    val band = if (isWord) CoreVocabulary.level(term, language)?.code?.uppercase()
                    else null
                    val caption = listOfNotNull(
                        entry?.pos?.takeIf { it.isNotBlank() }, band,
                    ).joinToString(" · ")
                    if (caption.isNotEmpty()) {
                        Text(caption, fontSize = 15.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                // Hearing it is the point of a cloned voice; without one there
                // is nothing to play, so the button is absent rather than dead.
                if (voiceId != null) PronounceCircle(speaking) { speak() }
            }

            CardSection(stringResource(R.string.meaning)) {
                val senses = entry?.senses.orEmpty().filter { it.meaning.isNotBlank() }
                if (senses.isEmpty()) {
                    LookupState(loading, failed) { attempt += 1 }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        senses.forEachIndexed { i, s -> SenseRow(i + 1, s) }
                    }
                }
            }

            // One failed lookup is one failure: the examples never carry their
            // own retry, the button belongs with the first message.
            if (!failed) {
                val examples = entry?.examples.orEmpty().filter { it.text.isNotBlank() }
                CardSection(stringResource(
                    if (examples.size == 1) R.string.example else R.string.examples)) {
                    if (examples.isEmpty()) {
                        LookupState(loading, failed = false) { attempt += 1 }
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            examples.forEach { e ->
                                ExampleMenu(e.text, language, exampleReason, savedSentences,
                                    onSavedSentence = { savedSentences = savedSentences + it },
                                    onShadow = onShadow) {
                                    ExampleRow(e.text, e.meaning)
                                }
                            }
                        }
                    }
                }
            }

            val phrases = entry?.phrases.orEmpty().filter { it.phrase.isNotBlank() }
            if (phrases.isNotEmpty()) {
                // A word gets collocations; a phrase gets near-variants — the
                // same move said another way, for when this phrasing doesn't fit.
                CardSection(stringResource(
                    if (isWord) R.string.common_phrases else R.string.another_way_to_say_it)) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        // A word's common phrase is not a sentence; an
                        // expression's other wording is (iOS).
                        phrases.forEach { p ->
                            ExampleMenu(p.phrase, language, if (isWord) null else exampleReason,
                                savedSentences, onSavedSentence = { savedSentences = savedSentences + it },
                                onShadow = onShadow) {
                                PhraseRow(p.phrase, p.meaning)
                            }
                        }
                    }
                }
            }

            entry?.properNoun?.takeIf { it.isNotBlank() }?.let { note ->
                CardSection(stringResource(R.string.as_a_name)) {
                    Text(note, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            if (sentences.isNotEmpty()) {
                CardSection(stringResource(R.string.from_your_talks)) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        sentences.forEach { line ->
                            SourceRow(line,
                                onListen = line.audio?.let { f -> { scope.launch { mp3.play(f) } } },
                                onShadow = { onShadow(line.text) })
                        }
                    }
                }
            }
        }

        // The action bar is PINNED, as on iOS: the verdicts are why the card
        // was opened, and a long entry must never scroll them out of reach.
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp)
                .padding(top = 10.dp, bottom = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // iOS `CardActionButton`: a glass capsule, ink when off, the
            // verdict's colour when on.
            VerdictButton(
                label = stringResource(R.string.keep),
                icon = if (kept) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                on = kept, onColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f), onClick = { toggleKeep() })
            VerdictButton(
                label = stringResource(R.string.i_know),
                icon = if (known) Icons.Filled.CheckCircle else Icons.Outlined.CheckCircle,
                on = known, onColor = Color(0xFF34C759),
                modifier = Modifier.weight(1f), onClick = { toggleKnown() })
            // iOS's bar is Keep · I know · ↑ · ↓ and nothing else. Shadowing
            // lives on the lines (an example's long-press, a talk line's
            // Shadow button); a waveform here read as the listen button.
            StepButton(Icons.Filled.KeyboardArrowUp, stringResource(R.string.previous_item),
                index > 0) { index -= 1 }
            StepButton(Icons.Filled.KeyboardArrowDown, stringResource(R.string.next_item),
                index + 1 < terms.size) { index += 1 }
        }
      }
    }
}

/**
 * Lines from the learner's own history that used this term.
 *
 * Which mouth said it depends on what the term IS, exactly as on iOS: a word
 * is worth seeing in the fluent self's sentences (that is where a word to
 * pick up came from), while an expression is evidence — the learner's own
 * turns are what put it in the library in the first place.
 */
/** One line from a talk, with that turn's own recording when it is on disk
 *  (iOS `VocabStore.SourceSentence`). */
private class SourceLine(val text: String, val audio: java.io.File?)

private suspend fun ownLines(
    context: android.content.Context,
    language: String,
    term: String,
    isWord: Boolean,
): List<SourceLine> {
    val needle = term.trim().lowercase()
    if (needle.isEmpty()) return emptyList()
    val out = ArrayList<SourceLine>()
    for (session in SessionStore.shared(context).load(language)) {
        for (turn in session.turns) {
            if (turn.transcript.isBlank()) continue
            if (isWord) {
                if (turn.role != TurnRole.FLUENT_SELF) continue
                if (!VocabLemmas.lemmas(listOf(turn.transcript)).contains(needle)) continue
                out.add(SourceLine(turn.transcript.trim(),
                    com.roro.futurevoice.data.WeeklyTestEngine.turnAudio(context, turn)))
            } else {
                if (turn.role != TurnRole.USER) continue
                if (!turn.transcript.lowercase().contains(needle)) continue
                out.add(SourceLine(snippet(needle, turn.transcript),
                    com.roro.futurevoice.data.WeeklyTestEngine.turnAudio(context, turn)))
            }
            if (out.size >= MAX_SOURCE_LINES) return out
        }
    }
    return out
}

/**
 * A readable window around the term instead of the WHOLE turn — a live STT
 * turn can be minutes of unpunctuated speech, which buries the thing the
 * learner opened the card to see.
 */
private fun snippet(needle: String, transcript: String, window: Int = 90): String {
    val at = transcript.lowercase().indexOf(needle)
    if (at < 0) return transcript.trim()
    val start = (at - window).coerceAtLeast(0)
    val end = (at + needle.length + window).coerceAtMost(transcript.length)
    val body = transcript.substring(start, end).trim()
    return (if (start > 0) "… " else "") + body + (if (end < transcript.length) " …" else "")
}

@Composable
private fun CardSection(title: String, content: @Composable () -> Unit) {
    // iOS `WordCard.section`: a small bold caption, uppercased and tracked,
    // in the tertiary label grey, flush with the text below it.
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold,
            letterSpacing = 0.6.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
        content()
    }
}

/** iOS `pronounceButton`: a 46 pt accent-tinted circle with the speaker glyph. */
@Composable
internal fun PronounceCircle(speaking: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(46.dp)
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), CircleShape)
            .clip(CircleShape)
            .clickable(enabled = !speaking, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (speaking) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
        else Icon(Icons.AutoMirrored.Filled.VolumeUp,
            contentDescription = stringResource(R.string.play),
            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
    }
}

/** The glass capsule iOS 26 draws for `.buttonStyle(.glass)` (`CardButtons`). */
@Composable
internal fun Modifier.glassCapsule(): Modifier {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    return this
        .shadow(if (dark) 0.dp else 10.dp, CircleShape,
            ambientColor = Color.Black.copy(alpha = 0.14f), spotColor = Color.Black.copy(alpha = 0.14f))
        .background(if (dark) Color(0xFF2C2C2E) else Color.White, CircleShape)
        .border(0.5.dp, Color.Black.copy(alpha = if (dark) 0f else 0.06f), CircleShape)
        .clip(CircleShape)
}

/** iOS `CardStepButton`: the icon-only sibling, sized to the glyph. */
@Composable
private fun StepButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        Modifier.height(48.dp).width(46.dp).glassCapsule()
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurface.copy(alpha = if (enabled) 1f else 0.3f))
    }
}

@Composable
private fun SenseRow(number: Int, sense: WordLore.Sense) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            Modifier.size(22.dp)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("$number", style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary)
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (sense.pos.isNotBlank()) {
                Text(sense.pos.uppercase(), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(sense.meaning, style = MaterialTheme.typography.titleMedium)
            sense.note?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/**
 * The long-press menu on a card's example or phrase (iOS `saveActions`,
 * 71c5e2da): "Save to sentences" (a sentence card of its own through
 * `DrillStore.bookmarkSentence` → `saveIfNew`; only when [sentenceReason] is
 * set — a word's common phrase is not a sentence), "Save to expressions" (a
 * BOOKMARK, `VocabStore.addExpression`), then "Shadow this". Without
 * [onShadow] (a sentence card's example sheet) the menu is the sentence item
 * alone. [savedSentences] is the caller's one read of `DrillStore.sentenceKeys`.
 */
@Composable
internal fun ExampleMenu(
    text: String,
    language: String,
    sentenceReason: String?,
    savedSentences: Set<String>,
    onSavedSentence: (String) -> Unit,
    onShadow: ((String) -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
    var open by remember { mutableStateOf(false) }
    // Read as the menu opens, like iOS's context menu reads the store.
    var savedExpression by remember { mutableStateOf(false) }
    val key = remember(text) { com.roro.futurevoice.data.DrillStore.sentenceKey(text) }
    fun tick() = haptic.performHapticFeedback(
        androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove)
    Box(Modifier.fillMaxWidth().pointerInput(text) {
        detectTapGestures(onLongPress = {
            haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
            scope.launch {
                if (onShadow != null) savedExpression =
                    com.roro.futurevoice.data.VocabStore.shared(context).isStudyingExpression(text, language)
                open = true
            }
        })
    }) {
        content()
        com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (sentenceReason != null) {
                if (key in savedSentences) {
                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                        text = { Text(stringResource(R.string.saved_to_sentences)) },
                        leadingIcon = { Icon(Icons.Filled.Check, null) },
                        enabled = false, onClick = {})
                } else {
                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                        text = { Text(stringResource(R.string.save_to_sentences)) },
                        leadingIcon = { Icon(Icons.AutoMirrored.Outlined.Chat, null) },
                        onClick = {
                            open = false
                            scope.launch {
                                val card = com.roro.futurevoice.data.DrillStore.shared(context)
                                    .bookmarkSentence(text, sentenceReason, language)
                                if (card != null) { onSavedSentence(key); tick(); StoreEvents.bump() }
                            }
                        })
                }
            }
            if (onShadow != null) {
                if (savedExpression) {
                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                        text = { Text(stringResource(R.string.saved_to_expressions)) },
                        leadingIcon = { Icon(Icons.Filled.Check, null) },
                        enabled = false, onClick = {})
                } else {
                    com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                        text = { Text(stringResource(R.string.save_to_expressions)) },
                        leadingIcon = { Icon(Icons.Filled.Bookmark, null) },
                        onClick = {
                            open = false
                            scope.launch {
                                com.roro.futurevoice.data.VocabStore.shared(context).addExpression(text, language)
                                tick(); StoreEvents.bump()
                            }
                        })
                }
                com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                    text = { Text(stringResource(R.string.shadow_this)) },
                    leadingIcon = { Icon(Icons.Filled.GraphicEq, null) },
                    onClick = { open = false; onShadow(text) })
            }
        }
    }
}

@Composable
private fun ExampleRow(text: String, meaning: String?) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        // The accent rule is what says "this is the language, not the gloss"
        // without spending a label on it.
        Box(
            Modifier.width(3.dp).height(if (meaning.isNullOrBlank()) 20.dp else 40.dp)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.35f),
                    RoundedCornerShape(2.dp))
        )
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(text, style = MaterialTheme.typography.bodyLarge)
            meaning?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PhraseRow(phrase: String, meaning: String) {
    Column(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, ContinuousShape(12.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(phrase, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        if (meaning.isNotBlank()) {
            Text(meaning, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** iOS `sentenceRow`: the line, then where it came from on the left and
 *  Listen (when the turn's audio is on disk) · Shadow on the right. */
@Composable
private fun SourceRow(line: SourceLine, onListen: (() -> Unit)?, onShadow: () -> Unit) {
    Column(
        Modifier.fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant, ContinuousShape(12.dp))
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(line.text, style = MaterialTheme.typography.bodyMedium)
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.talk), fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            if (onListen != null) SourceAction(Icons.Filled.PlayCircleOutline,
                stringResource(R.string.listen), onListen)
            SourceAction(Icons.Filled.GraphicEq, stringResource(R.string.shadow), onShadow)
        }
    }
}

@Composable
private fun SourceAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    Row(Modifier.clip(CircleShape).clickable(onClick = onClick).padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(15.dp))
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary)
    }
}

/**
 * What a lookup shows while it is working, and when it couldn't.
 *
 * A generated entry can fail like any network call, and a failure used to be
 * indistinguishable from "there is no entry" — both a bare dash, leaving the
 * learner nothing to do. Failure is worth its own state precisely because it
 * has an action attached.
 */
@Composable
private fun LookupState(loading: Boolean, failed: Boolean, retry: () -> Unit) {
    when {
        loading -> Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
            Text(stringResource(R.string.looking_it_up),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        failed -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.couldn_t_load_this_one),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = retry) { Text(stringResource(R.string.try_again)) }
        }
        else -> Text("—", style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Both verdicts wear their state in the icon and its tint, never in a second
 *  label — a button whose text changes under the thumb reads as a new button. */
@Composable
private fun VerdictButton(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    on: Boolean,
    onColor: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val tint = if (on) onColor else MaterialTheme.colorScheme.onSurface
    Row(
        modifier.height(48.dp).glassCapsule().clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp), tint = tint)
        // One line. The verdict's name is the only thing that says which
        // button this is, so it never wraps and never gets cut — at a large
        // font it shrinks instead ("알아요" drew as "알아으" clipped at 1.3).
        androidx.compose.foundation.layout.Spacer(Modifier.size(6.dp))
        androidx.compose.runtime.CompositionLocalProvider(
            androidx.compose.material3.LocalContentColor provides tint) {
            com.roro.futurevoice.ui.brand.FitButtonLabel(label,
                MaterialTheme.typography.labelLarge.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold))
        }
    }
}

/**
 * The pronounce circle on its own, for a surface that isn't the card (the
 * cloud's notebook peek — iOS shows the same button at the resting height).
 * Absent without a cloned voice, as on the card. Cache first: a word is
 * never billed twice.
 */
@Composable
internal fun WordPronounceButton(term: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mp3 = remember { Mp3Player(context.cacheDir, source = "library") }
    var voiceId by remember { mutableStateOf(com.roro.futurevoice.capture.flags.PracticeCaptureFlags.voiceId ?: cachedVoiceId) }
    var speaking by remember { mutableStateOf(false) }
    DisposableEffect(Unit) { onDispose { mp3.stop() } }
    LaunchedEffect(Unit) {
        if (voiceId != null) return@LaunchedEffect
        val uid = AuthRepository().userId ?: return@LaunchedEffect
        voiceId = runCatching { VoiceCloneRepository().activeVoiceId(uid) }
            .getOrNull()?.also { cachedVoiceId = it }
    }
    val id = voiceId ?: return
    PronounceCircle(speaking) {
        speaking = true
        scope.launch {
            runCatching {
                val audio = com.roro.futurevoice.data.cachedSynthesis(
                    context, voiceId = id, text = term,
                    idempotencyKey = InstallSalt.ttsKey(term, id, timestamps = false),
                    purpose = "library")
                mp3.play(audio)
            }.onFailure { e ->
                if (e === com.roro.futurevoice.net.EdgeError.InsufficientCredits)
                    com.roro.futurevoice.data.BillingGate.showPaywall.value = true
            }
            speaking = false
        }
    }
}
