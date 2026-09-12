package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.SetSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File

/**
 * The user's active vocabulary pool — the session-ingestion half of
 * `VocabStore.swift` (records, expressions, the notebook lists), same files,
 * same shapes, under `lang/<code>/`. UI-facing queries arrive with the
 * Practice work.
 *
 * Parity gap, deliberate: iOS ingests LEMMAS (NLTagger/KoreanMorph); here
 * `VocabLemmas` yields surface tokens, so the pool grows a little slower
 * (only surface forms present in the word list are counted) until a real
 * lemmatizer lands. The on-disk contract is unchanged.
 */
class VocabStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: VocabStore? = null
        fun shared(context: Context): VocabStore =
            instance ?: synchronized(this) {
                instance ?: VocabStore(context.applicationContext).also { instance = it }
            }
    }

    @Serializable
    data class Record(
        val state: String,   // "used" | "known"
        @Serializable(with = IsoDateMillisSerializer::class) val firstAt: Long,
        @Serializable(with = IsoDateMillisSerializer::class) val lastAt: Long,
        val count: Int,
    )

    private val appContext = context.applicationContext
    private val mutex = Mutex()

    private fun file(language: String, name: String): File =
        File(LanguageScope.directory(appContext, language), name)

    // ── Reads the summarizer needs ──

    suspend fun studying(language: String): List<String> = mutex.withLock {
        readList(file(language, "vocab_studying.json"))
    }

    suspend fun studyingExpressions(language: String): List<String> = mutex.withLock {
        readList(file(language, "vocab_studying_expressions.json"))
    }

    /** Word mastered = a record exists (used in a talk, or self-marked known). */
    suspend fun isKnownWord(lemma: String, language: String): Boolean = mutex.withLock {
        readRecords(file(language, "vocab_pool.json")).containsKey(lemma.lowercase())
    }

    /**
     * Expression mastered = real evidence only: a use in a talk (count > 0)
     * or an explicit "I know it" — a bookmark row alone must not tick a book
     * (iOS `hasUsedExpression`).
     */
    suspend fun hasUsedExpression(phrase: String, language: String): Boolean = mutex.withLock {
        val r = readRecords(file(language, "vocab_expressions.json"))[exprKey(phrase)]
        r != null && (r.state == "known" || r.count > 0)
    }

    // ── Session ingestion (`VocabStore.ingest`) ──

    /**
     * Fold a finished session's USER turns into the pool; only texts beyond
     * what this session already contributed count, so a re-run after a
     * resume adds the new turns and nothing twice. Returns first-time words.
     */
    suspend fun ingest(sessionId: String, userTexts: List<String>, language: String,
                       now: Long = System.currentTimeMillis()): List<String> = mutex.withLock {
        val metaFile = file(language, "vocab_ingested.json")
        val counts = readMapInt(metaFile).toMutableMap()
        val already = counts[sessionId] ?: 0
        if (userTexts.size <= already) return emptyList()
        counts[sessionId] = userTexts.size

        val poolFile = file(language, "vocab_pool.json")
        val records = readRecords(poolFile).toMutableMap()
        val newWords = mutableListOf<String>()
        val coreSet = CoreVocabulary.set(language)
        for (lemma in VocabLemmas.lemmas(userTexts.drop(already))) {
            if (lemma !in coreSet) continue
            val r = records[lemma]
            if (r != null) records[lemma] = r.copy(count = r.count + 1, lastAt = now)
            else { records[lemma] = Record("used", now, now, 1); newWords.add(lemma) }
        }
        writeRecords(poolFile, records)
        writeJson(metaFile, StoreJson.json.encodeToString(
            MapSerializer(String.serializer(), Int.serializer()), counts))
        newWords
    }

    @Serializable
    private data class ExpressionMeta(
        val keysBySession: Map<String, Set<String>> = emptyMap(),
        val legacySessions: Set<String> = emptySet(),
    )

    /** Seed a session's counted-keys from its previous summary (no-op when tracked). */
    suspend fun notePriorExpressions(sessionId: String, phrases: List<String>, language: String) = mutex.withLock {
        if (phrases.isEmpty()) return
        val metaFile = file(language, "vocab_expressions_ingested.json")
        val meta = readExpressionMeta(metaFile)
        if (meta.keysBySession.containsKey(sessionId)) return
        writeJson(metaFile, StoreJson.json.encodeToString(ExpressionMeta.serializer(),
            meta.copy(keysBySession = meta.keysBySession + (sessionId to phrases.map { exprKey(it) }.toSet()))))
    }

    /** Fold verified expressions in; each counted at most once per session. */
    suspend fun ingestExpressions(sessionId: String, phrases: List<String>, language: String,
                                  now: Long = System.currentTimeMillis()): List<String> = mutex.withLock {
        val metaFile = file(language, "vocab_expressions_ingested.json")
        val exprFile = file(language, "vocab_expressions.json")
        val meta = readExpressionMeta(metaFile)
        val counted = (meta.keysBySession[sessionId] ?: emptySet()).toMutableSet()
        val records = readRecords(exprFile).toMutableMap()
        val added = mutableListOf<String>()
        for (raw in phrases) {
            val display = raw.trim()
            if (display.isEmpty()) continue
            val key = exprKey(display)
            if (!counted.add(key)) continue
            val r = records[key]
            if (r != null) records[key] = r.copy(count = r.count + 1, lastAt = now)
            else { records[key] = Record("used", now, now, 1); added.add(display) }
        }
        writeRecords(exprFile, records)
        writeJson(metaFile, StoreJson.json.encodeToString(ExpressionMeta.serializer(),
            meta.copy(keysBySession = meta.keysBySession + (sessionId to counted))))
        added
    }

    private fun exprKey(phrase: String) = phrase.trim().lowercase()

    // ── The notebook (what the decks write) ──

    suspend fun isStudying(word: String, language: String): Boolean = mutex.withLock {
        readList(file(language, "vocab_studying.json")).contains(word)
    }

    /**
     * Keep a word. Effort, not a finished word: the learner is still studying
     * it, so it logs a REP and must never tick the daily goal.
     */
    suspend fun addStudying(word: String, language: String) = mutex.withLock {
        val f = file(language, "vocab_studying.json")
        val list = readList(f)
        if (list.contains(word)) return
        writeList(f, listOf(word) + list)   // newest first
        PracticeLog.record(appContext, PracticeLog.Kind.WORD)
    }

    suspend fun removeStudying(word: String, language: String) = mutex.withLock {
        val f = file(language, "vocab_studying.json")
        val list = readList(f)
        if (!list.contains(word)) return
        writeList(f, list.filterNot { it == word })
    }

    /** "used" | "known" | null — null means the pool has never met the word. */
    suspend fun state(lemma: String, language: String): String? = mutex.withLock {
        readRecords(file(language, "vocab_pool.json"))[lemma]?.state
    }

    /**
     * When this word was last credited — the REAL study time, not a build
     * time. Book shelves order by it, so a snapshot built today must not make
     * a word look studied today.
     */
    suspend fun lastAt(lemma: String, language: String): Long? = mutex.withLock {
        readRecords(file(language, "vocab_pool.json"))[lemma.trim().lowercase()]?.lastAt
    }

    /**
     * The learner says they know it. A record is only MINTED here if none
     * existed: a word they have actually said carries a `used` record with its
     * own count, and that evidence outlives an opinion about it.
     */
    suspend fun markKnown(lemma: String, language: String, now: Long = System.currentTimeMillis()) {
        mutex.withLock {
            val f = file(language, "vocab_pool.json")
            val records = readRecords(f)
            if (records[lemma] == null) {
                writeRecords(f, records + (lemma to Record("known", now, now, 0)))
            }
        }
        removeStudying(lemma, language)
        PracticeLog.record(appContext, PracticeLog.Kind.WORD, finished = true)
    }

    /** Forget the pool's opinion entirely — used to take a "Got it" back. */
    suspend fun unmark(lemma: String, language: String) = mutex.withLock {
        val f = file(language, "vocab_pool.json")
        val records = readRecords(f)
        if (!records.containsKey(lemma)) return
        writeRecords(f, records - lemma)
    }

    suspend fun isStudyingExpression(phrase: String, language: String): Boolean = mutex.withLock {
        readList(file(language, "vocab_studying_expressions.json")).contains(exprKey(phrase))
    }

    /**
     * Bookmark / un-bookmark a phrase. Bookmarking ensures a record exists so
     * it shows up in the Expressions list even if it was added by hand rather
     * than picked up in a talk — with `count = 0`, because a bookmark is not
     * evidence that anyone has said it.
     */
    suspend fun setStudyingExpression(phrase: String, studying: Boolean, language: String,
                                      now: Long = System.currentTimeMillis()) = mutex.withLock {
        val k = exprKey(phrase)
        if (k.isEmpty()) return
        val f = file(language, "vocab_studying_expressions.json")
        val list = readList(f)
        if (studying) {
            if (list.contains(k)) return
            writeList(f, listOf(k) + list)
            PracticeLog.record(appContext, PracticeLog.Kind.EXPRESSION)
            val ef = file(language, "vocab_expressions.json")
            val records = readRecords(ef)
            if (records[k] == null) writeRecords(ef, records + (k to Record("used", now, now, 0)))
        } else {
            writeList(f, list.filterNot { it == k })
        }
    }

    suspend fun isKnownExpression(phrase: String, language: String): Boolean = mutex.withLock {
        readRecords(file(language, "vocab_expressions.json"))[exprKey(phrase)]?.state == "known"
    }

    /**
     * Mark / unmark a phrase as known. Unmarking falls back to `used` — it is
     * still a phrase the learner has met — and never deletes the record.
     */
    suspend fun setKnownExpression(phrase: String, known: Boolean, language: String,
                                   now: Long = System.currentTimeMillis()) = mutex.withLock {
        val k = exprKey(phrase)
        if (k.isEmpty()) return
        val f = file(language, "vocab_expressions.json")
        val records = readRecords(f)
        val r = records[k]
        val updated = when {
            r != null -> r.copy(state = if (known) "known" else "used", lastAt = now)
            known -> Record("known", now, now, 0)
            else -> return
        }
        writeRecords(f, records + (k to updated))
        if (known) PracticeLog.record(appContext, PracticeLog.Kind.EXPRESSION, finished = true)
    }

    /** Every phrase the pool has met, most recently touched first. */
    suspend fun expressionEntries(language: String): List<ExpressionEntry> = mutex.withLock {
        readRecords(file(language, "vocab_expressions.json"))
            .map { (k, r) -> ExpressionEntry(k, r.count, r.firstAt, r.lastAt) }
            .sortedByDescending { it.lastAt }
    }

    data class ExpressionEntry(val text: String, val count: Int,
                               val firstAt: Long, val lastAt: Long)

    /**
     * Core-list words the fluent self used at or above the learner's level and
     * the learner has NO record of — the "you could pick this up" list a deck
     * tops up from. Easiest first, so a hand never opens on the hardest word
     * in it.
     */
    suspend fun pickupWords(fluentTexts: List<String>, atOrAbove: CefrLevel?,
                            language: String): List<String> = mutex.withLock {
        val records = readRecords(file(language, "vocab_pool.json"))
        pickupCandidates(fluentTexts, atOrAbove, language).filter { records[it] == null }
    }

    /**
     * The same words WITHOUT the "you don't know it yet" filter — what a talk
     * BOOK's word chapter must be built from. Deriving that from [pickupWords]
     * meant the list dropped a word the moment the learner learned it: the
     * denominator shrank instead of the mastered count growing, so a book's
     * word progress could never leave 0. The list stays put; only the
     * checkmarks move.
     */
    fun pickupCandidates(fluentTexts: List<String>, atOrAbove: CefrLevel?,
                         language: String): List<String> {
        val minRank = atOrAbove?.let { CoreVocabulary.levelRank(it) }
        return VocabLemmas.lemmas(fluentTexts)
            .mapNotNull { w ->
                val rank = CoreVocabulary.levelRank(CoreVocabulary.level(w, language) ?: return@mapNotNull null)
                if (minRank != null && rank < minRank) null else w to rank
            }
            .sortedWith(compareBy({ it.second }, { it.first }))
            .map { it.first }
            .distinct()
    }

    // ── File plumbing ──

    private fun writeList(f: File, list: List<String>) =
        writeJson(f, StoreJson.json.encodeToString(ListSerializer(String.serializer()), list))

    private fun readList(f: File): List<String> =
        if (!f.exists()) emptyList()
        else runCatching {
            StoreJson.json.decodeFromString(ListSerializer(String.serializer()), f.readText())
        }.getOrElse { emptyList() }

    private fun readMapInt(f: File): Map<String, Int> =
        if (!f.exists()) emptyMap()
        else runCatching {
            StoreJson.json.decodeFromString(MapSerializer(String.serializer(), Int.serializer()), f.readText())
        }.getOrElse { emptyMap() }

    private fun readRecords(f: File): Map<String, Record> =
        if (!f.exists()) emptyMap()
        else runCatching {
            StoreJson.json.decodeFromString(MapSerializer(String.serializer(), Record.serializer()), f.readText())
        }.getOrElse { emptyMap() }

    private fun readExpressionMeta(f: File): ExpressionMeta =
        if (!f.exists()) ExpressionMeta()
        else runCatching {
            StoreJson.json.decodeFromString(ExpressionMeta.serializer(), f.readText())
        }.getOrElse { ExpressionMeta() }

    private fun writeRecords(f: File, records: Map<String, Record>) =
        writeJson(f, StoreJson.json.encodeToString(
            MapSerializer(String.serializer(), Record.serializer()), records))

    private fun writeJson(target: File, text: String) {
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        // Every write funnels through here — keep the home-screen widgets'
        // snapshots in sync (iOS: StudyWidgetRefresher.schedule()).
        com.roro.futurevoice.widget.StudyWidgetRefresher.schedule(appContext)
    }
}
