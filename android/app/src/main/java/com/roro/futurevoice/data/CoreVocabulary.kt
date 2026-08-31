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
    fun level(word: String, language: String): CefrLevel? = pool(language).levelByWord[word.lowercase()]
    fun levelRank(level: CefrLevel): Int = CefrLevel.entries.indexOf(level)
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
