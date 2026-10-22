package com.roro.futurevoice.ui

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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddToListSheet(
    kind: AddToListKind,
    language: String,
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
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    val trimmed = text.trim()
    val needsConverting = language != nativeLanguage &&
        !TextScript.isInTargetScript(trimmed, language)

    fun finish(entry: String) {
        Analytics.capture("own_item_added", mapOf("kind" to kind.raw, "converted" to (converted != null)))
        onDismiss()
        onAdded(entry)
    }

    fun commit(entry: String) {
        working = true
        scope.launch {
            val vocab = VocabStore.shared(context)
            when (kind) {
                AddToListKind.WORD -> {
                    val key = VocabLemmas.lemma(bareEntry(entry), language)
                    working = false
                    if (key.isEmpty()) return@launch
                    vocab.addStudying(key, language)
                    finish(key)
                }
                AddToListKind.EXPRESSION -> {
                    val phrase = bareEntry(entry)
                    vocab.addExpression(phrase, language)
                    working = false
                    finish(phrase)
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
                onValueChange = { text = it; converted = null; failed = false; refused = false },
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
                else R.string.add_own_term_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            converted?.let {
                Text(it, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
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
