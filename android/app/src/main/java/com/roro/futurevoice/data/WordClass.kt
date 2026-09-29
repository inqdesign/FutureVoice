package com.roro.futurevoice.data

import android.content.Context
import java.io.InputStream

/**
 * The coarse part of speech of ONE headword, per target language — port of
 * `WordClass.swift` (iOS `a761b28`).
 *
 * Its one consumer is the weekly test's meaning item: a verb's gloss must not
 * be answerable by ruling out three nouns, and in Korean a predicate's 다
 * gives the answer away against nouns before the gloss is even read.
 *
 * **The class comes from a TABLE first** (`assets/wordlists/word_classes_<code>.tsv`,
 * the same four files iOS ships, built by `scripts/build-word-classes.py`
 * from the sources the wordlists came from). A headword can carry several
 * classes (run: noun,verb), so the question the engine asks is [sameClass],
 * never equality.
 *
 * **Rules are the fallback** for a word that is not on the list. iOS asks
 * `NLTagger` for a spaced language off the list; Android has no lexical-class
 * tagger, so such a word is UNKNOWN here — which the engine reads as "may sit
 * beside anything", the pre-table rule. German, Korean and Japanese read the
 * headword's shape exactly as iOS does.
 */
enum class WordClass(val raw: String) {
    NOUN("noun"), VERB("verb"), ADJECTIVE("adjective"), ADVERB("adverb"),
    /** Japanese な-adjective (静か): its own shape, neither noun nor い. */
    NA_ADJECTIVE("na-adjective"),
    /** Korean 다-form: verb or adjective, which the headword alone can't tell apart. */
    PREDICATE("predicate"),
    /** Placed by a rule as none of the above. */
    OTHER("other");

    companion object {
        private fun from(raw: String) = entries.firstOrNull { it.raw == raw }

        @Volatile private var appContext: Context? = null
        private val tables = HashMap<String, Map<String, Set<WordClass>>>()

        /** Where a table's bytes come from. The app reads its assets; a JVM
         *  test points this at `src/main/assets` instead. */
        @Volatile var opener: ((String) -> InputStream?)? = null

        fun init(context: Context) { appContext = context.applicationContext }

        private fun base(code: String) = code.substringBefore('-').lowercase()

        /** The classes of [word] as a headword of [language]. Empty = unknown. */
        fun classes(word: String, language: String): Set<WordClass> {
            val b = base(language)
            val trimmed = word.trim()
            if (trimmed.isEmpty()) return emptySet()
            table(b)[trimmed.lowercase()]?.let { return it }
            return when (b) {
                "ko" -> korean(trimmed)
                "ja" -> japanese(trimmed)
                "de" -> german(trimmed)
                else -> emptySet()
            }
        }

        /** Whether [a] and [b] share a class — or [a]'s class is unknown, in
         *  which case anything is allowed beside it. */
        fun sameClass(a: String, b: String, language: String): Boolean {
            val ca = classes(a, language)
            if (ca.isEmpty()) return true
            return ca.intersect(classes(b, language)).isNotEmpty()
        }

        private fun table(base: String): Map<String, Set<WordClass>> = synchronized(tables) {
            tables.getOrPut(base) {
                val name = "word_classes_$base.tsv"
                val stream = opener?.invoke(name)
                    ?: appContext?.let { c -> runCatching { c.assets.open("wordlists/$name") }.getOrNull() }
                    ?: return@getOrPut emptyMap()
                val out = HashMap<String, Set<WordClass>>()
                stream.bufferedReader().useLines { lines ->
                    for (line in lines) {
                        val parts = line.split('\t')
                        // The credit sits on the first line with no tab.
                        if (parts.size != 2) continue
                        val cls = parts[1].split(',').mapNotNull { from(it.trim()) }.toSet()
                        if (cls.isNotEmpty()) out[parts[0].lowercase()] = cls
                    }
                }
                out
            }
        }

        // ── Shape rules ──

        /** German orthography, exact for a headword: a capital is a noun, an
         *  infinitive ends in -en/-eln/-ern (or is tun/sein), the rest is an
         *  adjective — which is also the adverb. */
        private fun german(word: String): Set<WordClass> {
            if (word.first().isUpperCase()) return setOf(NOUN)
            // No verb begins with the negating un-; only unter- verbs do.
            if (word.startsWith("un") && !word.startsWith("unter")) return setOf(ADJECTIVE)
            if (word.endsWith("en") || word.endsWith("eln") || word.endsWith("ern") ||
                word.endsWith("tun") || word.endsWith("sein")) return setOf(VERB)
            return setOf(ADJECTIVE)
        }

        /** A dictionary form in 다 is a predicate; everything else is not. */
        private fun korean(word: String): Set<WordClass> {
            val cps = word.codePoints().toArray()
            if (cps.size < 2 || cps.last() != 0xB2E4) return setOf(OTHER)
            return setOf(PREDICATE)
        }

        private fun isHiragana(c: Int) = c in 0x3041..0x309F
        private fun isKatakana(c: Int) = c in 0x30A0..0x30FF

        /** Verbs end on an う-row kana, i-adjectives on い; a katakana word is
         *  a loanword and therefore a noun. Same exclusions iOS audited. */
        private fun japanese(word: String): Set<WordClass> {
            val s = word.codePoints().toArray()
            if (s.isEmpty()) return emptySet()
            val last = s.last()
            if (s.all { isKatakana(it) || it == 0x30FC }) return setOf(NOUN)
            if (s.size < 2) return setOf(OTHER)
            for (ending in listOf("ます", "です", "ください", "なさい", "いらっしゃい")) {
                if (word.endsWith(ending)) return setOf(OTHER)
            }
            if (s.size >= 4 && s.size % 2 == 0 &&
                s.copyOfRange(0, s.size / 2).contentEquals(s.copyOfRange(s.size / 2, s.size))) {
                return setOf(ADVERB)
            }
            val uRow = "うくぐすつぬふぶむる".codePoints().toArray().toSet()
            val before = s[s.size - 2]
            if (last in uRow) {
                val numerals = "一二三四五六七八九十幾".codePoints().toArray().toSet()
                if (last == 'つ'.code && (before in numerals || s.all { isHiragana(it) })) return setOf(NOUN)
                if (last == 'う'.code && isHiragana(before)) {
                    val oRow = "おこそとのほもよろをごぞどぼぽょ".codePoints().toArray().toSet()
                    if (before in oRow) return setOf(OTHER)
                }
                return setOf(VERB)
            }
            if (last == 'い'.code) return setOf(ADJECTIVE)
            return setOf(OTHER)
        }
    }
}
