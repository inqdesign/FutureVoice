package com.roro.futurevoice.data

import android.content.Context
import java.io.InputStream

/**
 * Spanish word → headword, from a bundled table rather than a tagger
 * (port of iOS `SpanishMorph.swift`, 2026-10-15).
 *
 * iOS ships no Spanish lemma model, and Android has none at all, so both read
 * `es_forms.tsv`: form TAB lemma (empty = the form is its own) TAB class,
 * written by `scripts/build-es-wordlist.swift` from the Mac's tagger run over
 * Tatoeba in context. The headwords in `cefr_words_es.tsv` are those same
 * lemmas, so the two can't disagree.
 *
 * Only content words are in the table. A form that isn't is its own lemma
 * with no class — a function word, a name, or a word neither corpus used —
 * which is the conservative answer on every path that reads it.
 */
object SpanishMorph {
    data class Entry(val lemma: String, val wordClass: String)

    @Volatile private var appContext: Context? = null

    /** Where the table's bytes come from. The app reads its assets; a JVM
     *  test points this at `src/main/assets` instead. */
    @Volatile var opener: ((String) -> InputStream?)? = null

    fun init(context: Context) { appContext = context.applicationContext }

    fun entry(form: String): Entry? = table()[form.lowercase()]

    /** The headword [form] belongs to, or the form itself (lowercased). */
    fun lemma(form: String): String {
        val w = form.lowercase()
        return table()[w]?.lemma ?: w
    }

    /** Each word of [text] with where it starts, letters only (accents
     *  included), so callers can ask about capitals the way the tagger path does. */
    fun words(text: String): List<Pair<String, Int>> =
        WORD.findAll(text).map { it.value to it.range.first }.toList()

    private val WORD = Regex("\\p{L}+")

    @Volatile private var cached: Map<String, Entry>? = null

    internal fun resetForTest() { cached = null }

    private fun table(): Map<String, Entry> {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val stream = opener?.invoke("es_forms.tsv")
                ?: appContext?.let { c -> runCatching { c.assets.open("wordlists/es_forms.tsv") }.getOrNull() }
                ?: return emptyMap()   // no context yet: not cached, asked again later
            val out = HashMap<String, Entry>(80_000)
            stream.bufferedReader().useLines { lines ->
                for (line in lines) {
                    val parts = line.split('\t')
                    if (parts.size != 3) continue   // the credit line has no tab
                    val form = parts[0]
                    out[form] = Entry(lemma = parts[1].ifEmpty { form }, wordClass = parts[2])
                }
            }
            cached = out
            return out
        }
    }
}
