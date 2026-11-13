package com.roro.futurevoice.data

import android.content.Context
import java.io.InputStream
import java.text.Normalizer

/**
 * French word → headword, from a bundled table rather than a tagger (port of
 * iOS `FrenchMorph.swift`, 2026-11-13).
 *
 * Like Spanish ([SpanishMorph]), French can't go through a tagger: Apple's
 * French lemma is wrong in context where it matters most ("Je suis
 * fatiguée" → suis → suivre) and cuts grand-mère and aujourd'hui in two, and
 * Android has no lemmatizer at all. So both platforms read `fr_forms.tsv`,
 * written by `scripts/build-fr-wordlist.py` from Lexique 3.83, and the
 * headwords in `cefr_words_fr.tsv` come out of the same table with the same
 * rules, so speech and list can't disagree.
 *
 * A row is: form TAB lemma (empty = itself, "-" = a function word) TAB class
 * TAB noun lemma after a determiner TAB verb lemma after a form of avoir.
 * The two context readings are the whole of what the table can't decide
 * alone: "l'été" is summer and "j'ai été" is être; "je suis fatigué" is the
 * adjective and "j'ai aimé" is aimer. [analyze] applies them; every reader
 * that has the whole sentence goes through it.
 *
 * Elision: l', j', qu' and the rest are their own (function) words, so
 * "l'école" meets école; a word that keeps its apostrophe or hyphen as part
 * of itself (aujourd'hui, grand-mère, peut-être) is looked up whole first.
 */
object FrenchMorph {
    data class Entry(val lemma: String, val wordClass: String)

    /** A word of a text: as written, where it starts, where it ends (exclusive). */
    data class Word(val word: String, val start: Int, val end: Int)

    /** A word of a sentence and what it reads as there (null = a function
     *  word, or a word the table doesn't know). */
    data class Reading(val word: String, val start: Int, val end: Int, val entry: Entry?)

    private class Row(val lemma: String?, val wordClass: String, val noun: String?, val verb: String?)

    @Volatile private var appContext: Context? = null

    /** Where the table's bytes come from. The app reads its assets; a JVM
     *  test points this at `src/main/assets` instead. */
    @Volatile var opener: ((String) -> InputStream?)? = null

    fun init(context: Context) { appContext = context.applicationContext }

    /** Each word of [text] with what it reads as here. */
    fun analyze(text: String): List<Reading> {
        val out = ArrayList<Reading>()
        var previous: String? = null
        for (w in words(text)) {
            val key = normalized(w.word)
            out.add(Reading(w.word, w.start, w.end, reading(key, previous)))
            previous = key
        }
        return out
    }

    /** The headword a lone [form] belongs to, or the form itself (normalized).
     *  With no sentence around it a function word with a noun reading is the
     *  noun ("personne" on its own is the noun). */
    fun lemma(form: String): String {
        val key = normalized(form)
        val row = table()[key] ?: return key
        return row.lemma ?: row.noun ?: key
    }

    /** The reading of a lone form (no context), null for a function word. */
    fun entry(form: String): Entry? {
        val row = table()[normalized(form)] ?: return null
        row.lemma?.let { return Entry(it, row.wordClass) }
        row.noun?.let { return Entry(it, "noun") }
        return null
    }

    /** Lowercased, typographic apostrophe folded, and "oe" before u/i written
     *  as the ligature, which is how the table spells it (sœur, œil, cœur).
     *  NFC first: iOS compares strings canonically, so a decomposed é finds
     *  the table's é there. */
    fun normalized(word: String): String {
        var w = Normalizer.normalize(word, Normalizer.Form.NFC).lowercase().replace('’', '\'')
        if ("oe" in w) w = w.replace("oeu", "œu").replace("oei", "œi")
        return w
    }

    /**
     * Words of [text], cut the way the build cut Tatoeba
     * (`scripts/build-fr-wordlist.py` `words`): a run of letters joined by
     * apostrophes or hyphens is one word if the table knows it whole,
     * otherwise it splits after each apostrophe (l' + école), then at
     * hyphens the table doesn't know whole (dis-moi → dis + moi).
     */
    fun words(text: String): List<Word> {
        val t = table()
        val out = ArrayList<Word>()
        for (run in runs(text)) {
            val whole = text.substring(run.first, run.last + 1)
            if (t[normalized(whole)] != null) {
                out.add(Word(whole, run.first, run.last + 1))
                continue
            }
            for (piece in split(text, run, keep = true) { it == '\'' || it == '’' }) {
                val w = text.substring(piece.first, piece.last + 1)
                if (t[normalized(w)] != null || '-' !in w) {
                    out.add(Word(w, piece.first, piece.last + 1))
                } else {
                    for (part in split(text, piece, keep = false) { it == '-' }) {
                        out.add(Word(text.substring(part.first, part.last + 1), part.first, part.last + 1))
                    }
                }
            }
        }
        return out
    }

    // ── Context ──

    private val determiners = setOf(
        "le", "la", "l'", "les", "un", "une", "des", "du", "au", "aux", "ce", "cet",
        "cette", "ces", "mon", "ton", "son", "ma", "ta", "sa", "mes", "tes", "ses",
        "notre", "votre", "nos", "vos", "leur", "leurs", "chaque", "quel", "quelle",
        "quels", "quelles", "d'", "de",
    )
    private val avoir = setOf(
        "ai", "as", "a", "avons", "avez", "ont", "avais", "avait", "avions", "aviez",
        "avaient", "aurai", "auras", "aura", "aurons", "aurez", "auront", "aurais",
        "aurait", "aurions", "auriez", "auraient", "eu", "ayant", "avoir", "aie", "ait",
        "ayons", "ayez", "aient", "eus", "eut", "eûmes", "eurent",
    )

    private fun reading(key: String, previous: String?): Entry? {
        val row = table()[key] ?: return null
        if (row.noun != null && previous != null && previous in determiners) return Entry(row.noun, "noun")
        if (row.verb != null && previous != null && previous in avoir) return Entry(row.verb, "verb")
        return row.lemma?.let { Entry(it, row.wordClass) }
    }

    // ── Cutting ──

    /** A letter, or a combining mark riding on one (a decomposed é is one
     *  letter to iOS, two chars here). */
    private fun isLetter(c: Char) = c.isLetter() || Character.getType(c) == Character.NON_SPACING_MARK.toInt()

    private fun runs(text: String): List<IntRange> {
        val out = ArrayList<IntRange>()
        var start = -1
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (isLetter(c)) {
                if (start < 0) start = i
            } else if (start >= 0 && (c == '\'' || c == '’' || c == '-') &&
                i + 1 < text.length && isLetter(text[i + 1])) {
                // joiner between two letters: stays in the run
            } else if (start >= 0) {
                out.add(start until i)
                start = -1
            }
            i++
        }
        if (start >= 0) out.add(start until text.length)
        return out
    }

    /** Cuts [range] at every character [isCut] accepts: after it when [keep]
     *  (the apostrophe stays on l'), dropping it otherwise (the hyphen). */
    private fun split(text: String, range: IntRange, keep: Boolean, isCut: (Char) -> Boolean): List<IntRange> {
        val out = ArrayList<IntRange>()
        var start = range.first
        val upper = range.last + 1
        var i = range.first
        while (i < upper) {
            if (isCut(text[i])) {
                val next = i + 1
                val end = if (keep) next else i
                if (start < end) out.add(start until end)
                start = next
            }
            i++
        }
        if (start < upper) out.add(start until upper)
        return out
    }

    // ── Table ──

    @Volatile private var cached: Map<String, Row>? = null

    internal fun resetForTest() { cached = null }

    private fun table(): Map<String, Row> {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val stream = opener?.invoke("fr_forms.tsv")
                ?: appContext?.let { c -> runCatching { c.assets.open("wordlists/fr_forms.tsv") }.getOrNull() }
                ?: return emptyMap()   // no context yet: not cached, asked again later
            val out = HashMap<String, Row>(120_000)
            stream.bufferedReader().useLines { lines ->
                for (line in lines) {
                    val p = line.split('\t')
                    if (p.size != 5) continue   // the credit line has no tab
                    val form = p[0]
                    val lemma = if (p[1] == "-") null else p[1].ifEmpty { form }
                    out[form] = Row(lemma, p[2], p[3].ifEmpty { null }, p[4].ifEmpty { null })
                }
            }
            cached = out
            return out
        }
    }
}
