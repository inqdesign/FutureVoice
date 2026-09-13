package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.net.WordLore
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The glossary at the back of an exported book: every word and expression it
 * teaches, with its part of speech, meanings, and one example.
 *
 * The entries are NOT generated for the export. They come from [WordLore],
 * which reads the shared dictionary the Vocabulary screen shows — already
 * written for most terms because some learner (often this one) tapped them.
 *
 * Failure is silent by design: a book that exports without a glossary is
 * still the book. Nothing here may block the file from being written, which
 * is why the whole lookup runs under one timeout.
 */
object BookGlossary {
    /** Never look up more than this many terms for one book. A long Talk
     *  book can list dozens, and an export that fans out to all of them turns
     *  a share into an unbounded network operation. */
    const val MAX_TERMS = 40
    /** Give up after this long in total — a slow dictionary can cost the
     *  glossary, never the book. */
    const val BUDGET_MS = 8_000L

    suspend fun section(context: Context, doc: BookDocument, native: String, target: String): BookDocument.Section? {
        // De-duplicate case-insensitively but keep the first spelling: the
        // book should gloss the word as the learner met it.
        val seen = HashSet<String>()
        val terms = doc.terms.filter { seen.add(it.text.trim().lowercase()) && it.text.isNotBlank() }.take(MAX_TERMS)
        if (terms.isEmpty()) return null
        val lore = WordLore(AuthRepository())
        val entries = withTimeoutOrNull(BUDGET_MS) {
            coroutineScope {
                terms.map { term ->
                    async {
                        runCatching {
                            lore.entry(term.text, native, target,
                                if (term.isExpression) WordLore.Kind.EXPRESSION else WordLore.Kind.WORD)
                        }.getOrNull()?.let { render(term.text, it) }
                    }
                }.awaitAll().filterNotNull()   // the book's order, not the network's
            }
        }.orEmpty()
        if (entries.isEmpty()) return null
        return BookDocument.Section(context.getString(R.string.glossary), entries = entries)
    }

    /** One dictionary entry flattened into the book's two-field shape: the
     *  senses become the note, the first example becomes the example line. */
    private fun render(term: String, e: WordLore.Entry): BookDocument.Entry {
        val parts = e.senses.mapNotNull { s ->
            val meaning = s.meaning.trim()
            if (meaning.isEmpty()) null
            else if (s.pos.isBlank()) meaning else "${s.pos.trim()} $meaning"
        }.toMutableList()
        // No senses is a malformed entry — gloss it with the headline part of
        // speech rather than emitting a bare word with an empty note.
        if (parts.isEmpty()) e.pos?.takeIf { it.isNotBlank() }?.let { parts.add(it) }
        val example = e.examples.firstOrNull()?.let { ex ->
            val meaning = ex.meaning?.trim().orEmpty()
            if (meaning.isEmpty()) ex.text else "${ex.text} — $meaning"
        } ?: e.phrases.firstOrNull()?.let { "${it.phrase} — ${it.meaning}" } ?: ""
        return BookDocument.Entry(term, note = parts.joinToString(" · "), example = example)
    }
}
