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

    // ── File plumbing ──

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
