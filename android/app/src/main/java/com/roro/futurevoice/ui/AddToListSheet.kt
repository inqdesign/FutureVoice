package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.SharedLibrary
import com.roro.futurevoice.data.TextScript
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.net.Translator
import kotlinx.coroutines.launch

/**
 * A word, an expression or a sentence the learner wants on a list that no
 * talk or scene handed them (iOS `AddToListSheet`). They type it; the list
 * does the rest as it does for anything else on it: a word gets its card's
 * meanings, an expression its gloss, a sentence a translation under it.
 *
 * Typed in the native language instead, it is turned into the target
 * language first and shown before it is added. Only a different SCRIPT can
 * tell the two apart.
 */
enum class AddToListKind(val raw: String) { WORD("word"), EXPRESSION("expression"), SENTENCE("sentence") }

/** What the list already holds (plus, for words, the graded pool), searched as
 *  the learner types. [status] is a string resource for where it already
 *  sits, or null for a pool word on no list; [level] tags the latter. */
data class AddToListCandidate(val text: String, val key: String, val status: Int?, val level: String? = null)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddToListSheet(
    kind: AddToListKind,
    language: String,
    candidates: List<AddToListCandidate> = emptyList(),
    /** What went on the list (the word's key, the phrase, the sentence). */
    onAdded: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
    }
    var text by remember { mutableStateOf("") }
    /** The target-language version of a native-language entry, waiting to be confirmed. */
    var converted by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var refused by remember { mutableStateOf(false) }
    /** The library's "did you mean": what was typed is misspelt. */
    var suggestion by remember { mutableStateOf<String?>(null) }
    /** Why the library refused what was typed (`library-add`'s reason). */
    var rejection by remember { mutableStateOf<String?>(null) }
    val focus = remember { FocusRequester() }
    val lore = remember { com.roro.futurevoice.net.WordLore(com.roro.futurevoice.data.AuthRepository()) }
    val meanings = remember { androidx.compose.runtime.mutableStateMapOf<String, String>() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    val trimmed = text.trim()
    val needsConverting = language != nativeLanguage &&
        !TextScript.isInTargetScript(trimmed, language)

    // Prefix matches first ("par" → parse before spare), then anything that
    // contains it; a handful, since this is a check, not a browser.
    val q = trimmed.lowercase()
    val matches = if (q.length < (if (kind == AddToListKind.SENTENCE) 3 else 1) || converted != null) emptyList()
    else {
        val prefix = candidates.filter { it.key.startsWith(q) }.sortedBy { it.key.length }
        val rest = if (kind == AddToListKind.WORD) emptyList()
        else candidates.filter { !it.key.startsWith(q) && it.key.contains(q) }
        (prefix + rest).take(6)
    }

    fun openExisting(match: AddToListCandidate) {
        scope.launch {
            if (match.status == null) {
                if (kind == AddToListKind.WORD) VocabStore.shared(context).addStudying(match.key, language)
                if (kind == AddToListKind.EXPRESSION) VocabStore.shared(context).addExpression(match.text, language)
            }
            Analytics.capture("own_item_matched", mapOf("kind" to kind.raw, "added" to (match.status == null)))
            onDismiss()
            onAdded(if (kind == AddToListKind.WORD) match.key else match.text)
        }
    }

    fun finish(entry: String) {
        Analytics.capture("own_item_added", mapOf("kind" to kind.raw, "converted" to (converted != null)))
        onDismiss()
        onAdded(entry)
    }

    /**
     * Something the library doesn't carry: `library-add` reads it once (a
     * typo, a made-up word or a name never goes in) and, if it passes, it
     * joins the shared library with a level and lands on this list.
     */
    suspend fun checkWithLibrary(entry: String) {
        val vocab = VocabStore.shared(context)
        when (val r = SharedLibrary.add(com.roro.futurevoice.data.AuthRepository(), entry,
            kind.raw, language, nativeLanguage)) {
            is SharedLibrary.AddResult.Added -> {
                working = false
                if (kind == AddToListKind.WORD) {
                    vocab.addStudying(r.term.key, language)
                } else {
                    vocab.addExpression(r.term.term, language)
                }
                finish(r.term.key)
            }
            is SharedLibrary.AddResult.Typo -> {
                working = false; suggestion = r.suggestion
                Analytics.capture("own_item_refused", mapOf("kind" to kind.raw, "reason" to "typo"))
            }
            is SharedLibrary.AddResult.Rejected -> {
                working = false; rejection = r.reason
                Analytics.capture("own_item_refused", mapOf("kind" to kind.raw, "reason" to r.reason))
            }
            SharedLibrary.AddResult.Failed -> { working = false; failed = true }
        }
    }

    fun commit(entry: String) {
        working = true
        scope.launch {
            val vocab = VocabStore.shared(context)
            when (kind) {
                AddToListKind.WORD -> {
                    val key = VocabLemmas.lemma(bareEntry(entry), language)
                    if (key.isEmpty()) { working = false; return@launch }
                    // Already in the library (bundled or shared): nothing to check.
                    if (key in com.roro.futurevoice.data.CoreVocabulary.set(language)) {
                        vocab.addStudying(key, language)
                        working = false
                        finish(key)
                    } else checkWithLibrary(bareEntry(entry))
                }
                AddToListKind.EXPRESSION -> {
                    val phrase = bareEntry(entry)
                    val listed = candidates.any { it.key == phrase && it.status != null }
                    if (listed || SharedLibrary.expressionLevel(phrase, language) != null) {
                        vocab.addExpression(phrase, language)
                        working = false
                        finish(phrase)
                    } else checkWithLibrary(phrase)
                }
                AddToListKind.SENTENCE -> {
                    // The translation is the card's gloss, the line a sentence
                    // card shows under itself on the list and in the deck.
                    val gloss = Translator.translate(context, entry, nativeLanguage).orEmpty()
                    val card = DrillStore.shared(context).bookmarkSentence(entry, gloss, language)
                    working = false
                    if (card == null) { refused = true; return@launch }
                    finish(entry)
                }
            }
        }
    }

    fun add() {
        if (trimmed.isEmpty() || working) return
        converted?.let { commit(it); return }
        if (!needsConverting) { commit(trimmed); return }
        working = true
        scope.launch {
            val result = Translator.translate(context, trimmed, language)
            working = false
            if (result == null) { failed = true; return@launch }
            converted = if (kind == AddToListKind.SENTENCE) result else bareEntry(result)
        }
    }

    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
    ) {
        Column(
            Modifier.sheetBody().padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // Cancel · title · Add — iOS's inline navigation bar.
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                Text(
                    stringResource(when (kind) {
                        AddToListKind.WORD -> R.string.add_own_word_title
                        AddToListKind.EXPRESSION -> R.string.add_own_expression_title
                        AddToListKind.SENTENCE -> R.string.add_own_sentence_title
                    }),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                Box(contentAlignment = Alignment.Center) {
                    if (working) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else TextButton(onClick = { add() }, enabled = trimmed.isNotEmpty()) {
                        Text(stringResource(R.string.add), fontWeight = FontWeight.SemiBold)
                    }
                }
            }

            OutlinedTextField(
                value = text,
                onValueChange = {
                    text = it; converted = null; failed = false; refused = false
                    suggestion = null; rejection = null
                },
                placeholder = {
                    Text(stringResource(when (kind) {
                        AddToListKind.WORD -> R.string.add_own_word_placeholder
                        AddToListKind.EXPRESSION -> R.string.add_own_expression_placeholder
                        AddToListKind.SENTENCE -> R.string.add_own_sentence_placeholder
                    }))
                },
                textStyle = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold),
                minLines = if (kind == AddToListKind.SENTENCE) 2 else 1,
                maxLines = if (kind == AddToListKind.SENTENCE) 5 else 3,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { add() }),
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
            )
            Text(
                stringResource(if (kind == AddToListKind.SENTENCE) R.string.add_own_sentence_footer
                else R.string.add_own_term_footer_library),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // What's already there, as they type: tapping one opens it (or,
            // for a pool word, keeps it) instead of making a copy.
            if (matches.isNotEmpty()) {
                Text(stringResource(R.string.add_own_already_there),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Column(Modifier.fillMaxWidth()) {
                    matches.forEach { match ->
                        Row(
                            Modifier.fillMaxWidth()
                                .then(if (kind == AddToListKind.SENTENCE) Modifier
                                else Modifier.clickable { openExisting(match) })
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(if (kind == AddToListKind.SENTENCE) match.text
                                    else match.text.replaceFirstChar { it.uppercase() },
                                    style = MaterialTheme.typography.bodyLarge,
                                    fontWeight = if (kind == AddToListKind.SENTENCE) null else FontWeight.SemiBold,
                                    maxLines = 2)
                                meanings[match.key]?.takeIf { it.isNotEmpty() }?.let {
                                    Text(it, style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                                }
                            }
                            val tag = match.status?.let { stringResource(it) } ?: match.level
                            if (tag != null) Text(tag, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (kind != AddToListKind.SENTENCE) androidx.compose.material3.Icon(
                                if (match.status == null) Icons.Filled.AddCircleOutline
                                else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                contentDescription = null,
                                tint = if (match.status == null) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(20.dp))
                        }
                        if (kind != AddToListKind.SENTENCE) LaunchedEffect(match.key) {
                            if (meanings.containsKey(match.key)) return@LaunchedEffect
                            // Let a fast typist get past a match before it is looked up.
                            kotlinx.coroutines.delay(300)
                            meanings[match.key] = ""
                            val entry = runCatching {
                                lore.entry(match.text, nativeLanguage, language,
                                    if (kind == AddToListKind.WORD) com.roro.futurevoice.net.WordLore.Kind.WORD
                                    else com.roro.futurevoice.net.WordLore.Kind.EXPRESSION)
                            }.getOrNull()
                            meanings[match.key] = entry?.senses?.firstOrNull()?.meaning?.trim().orEmpty()
                        }
                    }
                }
            }

            converted?.let {
                Text(it, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            }
            suggestion?.let { s ->
                Text(stringResource(R.string.add_own_did_you_mean),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = { text = s; suggestion = null; add() }) {
                    Text(s.replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                }
            }
            rejection?.let { reason ->
                Text(stringResource(when (reason) {
                    "proper_name" -> R.string.add_own_no_names
                    "not_target" -> R.string.add_own_not_target
                    "wrong_kind" -> if (kind == AddToListKind.WORD) R.string.add_own_more_than_one_word
                        else R.string.add_own_single_word
                    "offensive" -> R.string.add_own_cannot_go
                    else -> if (kind == AddToListKind.WORD) R.string.add_own_word_not_found
                        else R.string.add_own_expression_not_found
                }), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (failed) {
                Text(stringResource(R.string.add_own_lookup_failed),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else if (refused) {
                Text(stringResource(R.string.add_own_reads_like_rule),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** A word or phrase as a list keeps it: no sentence punctuation around it (a
 *  translator answers "Apple." for 사과), lowercased like every key. */
private fun bareEntry(s: String): String =
    s.trim().trim('.', '。', '!', '！', '?', '？', '"', '“', '”', '\'', '‘', '’').trim().lowercase()
