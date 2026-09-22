package com.roro.futurevoice.data

import android.content.Context

/**
 * The graded word pool per target language — port of `CoreVocabulary.swift`,
 * reading the SAME TSVs (bundled under `assets/wordlists/`). Languages
 * without a list get an empty pool: vocab tracking honestly shows nothing
 * rather than grading against English words.
 *
 * Parity note: iOS looks words up by LEMMA (NLTagger). Android has no
 * platform lemmatizer, so lookups here receive surface tokens
 * (`VocabLemmas`) — the lists carry many inflected forms, so most hits
 * still land, but the two platforms' counts are NOT comparable yet and
 * `ScorecardMetrics` deliberately keeps `distinct_words_by_cefr_level`
 * empty until they are.
 */
object CoreVocabulary {

    private val wordlistResource = mapOf(
        "en" to "cefr_words", "de" to "cefr_words_de", "ko" to "cefr_words_ko",
    )

    private class Pool(val levelByWord: Map<String, CefrLevel>) {
        val set: Set<String> get() = levelByWord.keys
    }

    @Volatile private var appContext: Context? = null
    private val pools = HashMap<String, Pool>()

    fun init(context: Context) { appContext = context.applicationContext }

    private fun pool(language: String): Pool = synchronized(pools) {
        pools.getOrPut(language) {
            val resource = wordlistResource[language] ?: return@getOrPut Pool(emptyMap())
            val ctx = appContext ?: return@getOrPut Pool(emptyMap())
            val map = HashMap<String, CefrLevel>()
            runCatching {
                ctx.assets.open("wordlists/$resource.tsv").bufferedReader().forEachLine { line ->
                    val parts = line.split('\t')
                    if (parts.size == 2) {
                        val level = CefrLevel.entries.firstOrNull { it.code.equals(parts[1], true) }
                        if (level != null) map.putIfAbsent(parts[0].lowercase(), level)
                    }
                }
            }
            Pool(map)
        }
    }

    fun set(language: String): Set<String> = pool(language).set

    /**
     * Words whose absence from the pool is a DECISION, not a gap — what
     * separates "have" from "chore" when [VocabStore.offListContentWords]
     * decides whether an ungraded word is vocabulary.
     *
     * Longer than the iOS list on purpose. There the part-of-speech tagger
     * throws out articles, pronouns, prepositions and conjunctions before
     * this set is consulted, and Android has no tagger — so the closed
     * classes are named here instead. It stays hand-checked and finite:
     * a closed class does not grow, and every open-class word the pool
     * merely lacks must still get through.
     */
    private val ungradedByLanguage: Map<String, Set<String>> = mapOf(
        "en" to setOf(
            // Determiners, pronouns, prepositions, conjunctions — the classes
            // iOS drops with the tagger.
            "the", "a", "an", "this", "that", "these", "those", "some", "any",
            "each", "every", "both", "either", "neither", "all", "most",
            "another", "such", "other", "many", "much", "lot", "lots", "few",
            "little", "more", "less", "own",
            "i", "you", "he", "she", "it", "we", "they", "me", "him", "her",
            "us", "them", "my", "your", "his", "its", "our", "their", "mine",
            "yours", "hers", "ours", "theirs", "myself", "yourself", "himself",
            "herself", "itself", "ourselves", "yourselves", "themselves",
            "who", "whom", "whose", "which", "what", "where", "when", "why",
            "how", "there", "here",
            "of", "in", "on", "at", "to", "for", "with", "without", "from",
            "by", "about", "into", "onto", "over", "under", "between", "among",
            "through", "during", "before", "after", "above", "below", "off",
            "out", "up", "down", "than", "as", "like", "per", "via",
            "and", "or", "but", "so", "because", "if", "though", "although",
            "while", "unless", "until", "whether", "since", "yet", "nor",
            // Auxiliaries and modals, with the spoken forms a transcript
            // writes them in.
            "be", "am", "are", "is", "was", "were", "been", "being",
            "have", "has", "had", "having", "do", "does", "did", "done",
            "go", "will", "would", "shall", "should", "can", "could", "may",
            "might", "must", "not", "don", "doesn", "didn", "won", "can",
            "couldn", "wouldn", "shouldn", "isn", "aren", "wasn", "weren",
            "haven", "hasn", "hadn",
            // Indefinite pronouns — a tagger calls every one of these a noun,
            // so nothing else keeps them out.
            "everything", "something", "anything", "nothing",
            "everyone", "someone", "anyone", "none",
            "everybody", "somebody", "anybody", "nobody",
            // Spoken filler and contractions a transcript spells out.
            "gonna", "wanna", "gotta", "kinda", "sorta", "dunno",
            "lemme", "gimme", "yeah", "yep", "yup", "nope", "nah",
            "hmm", "mmm", "uh", "um", "umm", "ah", "oh", "ooh", "huh",
            "hey", "ok", "okay", "alright", "well", "just", "really", "very",
            "too", "also", "even", "still", "only", "again", "always",
            "never", "sometimes", "maybe", "please", "thanks", "thank",
            "yes", "no", "now", "then", "today", "one", "two", "three"),
        "de" to setOf(
            "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen",
            "einem", "einer", "eines", "kein", "keine", "dieser", "diese",
            "dieses", "jeder", "jede", "jedes", "alle", "alles", "etwas",
            "nichts", "jemand", "niemand", "man",
            "ich", "du", "er", "sie", "es", "wir", "ihr", "mich", "dich",
            "sich", "uns", "euch", "mein", "dein", "sein", "ihre", "unser",
            "und", "oder", "aber", "denn", "weil", "dass", "wenn", "als",
            "wie", "was", "wer", "wo", "warum", "ob", "damit", "obwohl",
            "in", "an", "auf", "aus", "bei", "mit", "nach", "seit", "von",
            "zu", "für", "um", "durch", "gegen", "ohne", "über", "unter",
            "vor", "hinter", "neben", "zwischen",
            "bin", "bist", "ist", "sind", "seid", "war", "waren", "sein",
            "habe", "hast", "hat", "haben", "hatte", "hatten",
            "werde", "wirst", "wird", "werden", "wurde", "wurden",
            "können", "kann", "müssen", "muss", "sollen", "soll", "dürfen",
            "darf", "mögen", "möchte", "nicht", "auch", "noch", "schon",
            "sehr", "mal", "halt", "eben", "ja", "nee", "naja", "ähm",
            "hmm", "okay", "danke", "bitte"),
    )

    /** True when the word's absence from the pool is a decision rather than a
     *  gap — see [ungradedByLanguage]. */
    fun isUngraded(word: String, language: String): Boolean =
        ungradedByLanguage[language]?.contains(word.lowercase()) == true
    fun level(word: String, language: String): CefrLevel? = pool(language).levelByWord[word.lowercase()]
    fun levelRank(level: CefrLevel): Int = CefrLevel.entries.indexOf(level)

    /**
     * Every core word at or above [level], easiest first — the top-up a daily
     * word deck falls back on so the hand is never short, even on day one.
     * Ordered inside a band too (alphabetically), so the same day deals the
     * same hand however the map happened to iterate.
     */
    fun wordsAtOrAbove(level: CefrLevel, language: String): List<String> {
        val min = levelRank(level)
        return pool(language).levelByWord.entries
            .filter { levelRank(it.value) >= min }
            .sortedWith(compareBy({ levelRank(it.value) }, { it.key }))
            .map { it.key }
    }
}

/**
 * Headwords spoken across texts — the Android stand-in for
 * `VocabStore.lemmas`. iOS lemmatizes (NLTagger / KoreanMorph); this returns
 * lowercase SURFACE tokens (length > 1), the same fallback iOS uses for a
 * language its tagger doesn't cover. Centralized so a real lemmatizer later
 * is a one-file change.
 */
object VocabLemmas {
    fun lemmas(texts: List<String>): Set<String> {
        val out = HashSet<String>()
        for (text in texts) {
            for (token in text.split(Regex("[^\\p{L}\\p{N}]+"))) {
                val t = token.lowercase()
                if (t.length > 1) out.add(t)
            }
        }
        return out
    }
}
