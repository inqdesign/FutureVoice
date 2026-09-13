package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
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
    onDismiss: () -> Unit,
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
    var sentences by remember { mutableStateOf<List<String>>(emptyList()) }
    var kept by remember { mutableStateOf(false) }
    var known by remember { mutableStateOf(false) }
    var voiceId by remember { mutableStateOf(cachedVoiceId) }
    var speaking by remember { mutableStateOf(false) }

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
        val fetched = lore.entry(term, nativeLanguage, language,
            if (isWord) WordLore.Kind.WORD else WordLore.Kind.EXPRESSION)
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
                val audio = ElevenLabsClient(AuthRepository()).synthesize(
                    voiceId = id, text = term,
                    idempotencyKey = InstallSalt.ttsKey(term, id, timestamps = false),
                    purpose = "library")
                mp3.play(audio)
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

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 28.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(term, style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold)
                    val band = if (isWord) CoreVocabulary.level(term, language)?.code?.uppercase()
                    else null
                    val caption = listOfNotNull(
                        entry?.pos?.takeIf { it.isNotBlank() }, band,
                    ).joinToString(" · ")
                    if (caption.isNotEmpty()) {
                        Text(caption, style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                // Hearing it is the point of a cloned voice; without one there
                // is nothing to play, so the button is absent rather than dead.
                if (voiceId != null) {
                    IconButton(onClick = { speak() }, enabled = !speaking) {
                        if (speaking) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.AutoMirrored.Filled.VolumeUp,
                                contentDescription = stringResource(R.string.play))
                        }
                    }
                }
            }

            // The two verdicts, then walking the list — you decide, then move
            // on, and both halves stay under the same thumb.
            Row(
                Modifier.fillMaxWidth().padding(top = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
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
                IconButton(onClick = { index -= 1 }, enabled = index > 0) {
                    Icon(Icons.Filled.KeyboardArrowUp,
                        contentDescription = stringResource(R.string.previous_item))
                }
                IconButton(onClick = { index += 1 }, enabled = index + 1 < terms.size) {
                    Icon(Icons.Filled.KeyboardArrowDown,
                        contentDescription = stringResource(R.string.next_item))
                }
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
                            examples.forEach { ExampleRow(it.text, it.meaning) }
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
                        phrases.forEach { PhraseRow(it.phrase, it.meaning) }
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
                        sentences.forEach { SourceRow(it) }
                    }
                }
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
private suspend fun ownLines(
    context: android.content.Context,
    language: String,
    term: String,
    isWord: Boolean,
): List<String> {
    val needle = term.trim().lowercase()
    if (needle.isEmpty()) return emptyList()
    val out = ArrayList<String>()
    for (session in SessionStore.shared(context).load(language)) {
        for (turn in session.turns) {
            if (turn.transcript.isBlank()) continue
            if (isWord) {
                if (turn.role != TurnRole.FLUENT_SELF) continue
                if (!VocabLemmas.lemmas(listOf(turn.transcript)).contains(needle)) continue
                out.add(turn.transcript.trim())
            } else {
                if (turn.role != TurnRole.USER) continue
                if (!turn.transcript.lowercase().contains(needle)) continue
                out.add(snippet(needle, turn.transcript))
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
    Column(Modifier.fillMaxWidth()) {
        GroupedSectionHeader(title)
        content()
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
            .background(AppSurfaces.card, RoundedCornerShape(12.dp))
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

@Composable
private fun SourceRow(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp))
            .padding(10.dp),
    )
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
    Button(
        onClick = onClick,
        modifier = modifier,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (on) onColor.copy(alpha = 0.16f)
            else MaterialTheme.colorScheme.surfaceVariant,
            contentColor = if (on) onColor else MaterialTheme.colorScheme.onSurfaceVariant,
        ),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp))
        Text(label, style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(start = 6.dp))
    }
}
