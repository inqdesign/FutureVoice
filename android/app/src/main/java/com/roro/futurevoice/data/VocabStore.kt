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

        /**
         * Content words in [texts] the graded pool doesn't carry, with how many
         * of those turns each appeared in.
         *
         * TURNS, not occurrences: the question asked of this number is whether
         * the fluent self kept coming back to the word, and a word said three
         * times inside one sentence is a verbal tic, not a thread.
         *
         * Safe on the FLUENT SELF's turns and nowhere else: that text is
         * model-written, so no transcriber sits between the word and the check —
         * the same argument `expressions_offered` rests on. The learner's own
         * speech keeps the pool gate, where a mishearing would otherwise mint a
         * word.
         *
         * Four things have to hold. iOS asks a part-of-speech tagger for the
         * first of them; Android has none, so [CoreVocabulary.isUngraded] carries
         * the closed classes instead:
         *
         *  - the pool did not leave it out on purpose (what separates "have"
         *    from "chore");
         *  - it isn't a name — a capital letter anywhere but the start of a
         *    sentence is a name, a language or a brand, not vocabulary;
         *  - three letters or more, letters only;
         *  - the graded pool doesn't already carry it.
         *
         * Empty for Korean and Japanese by construction: a dictionary form the
         * wordlist can't confirm is a guess, not a word to track.
         */
        fun offListContentWords(texts: List<String>, language: String): Map<String, Int> {
            if (language == "ko" || language == "ja") return emptyMap()
            val pool = CoreVocabulary.set(language)
            val out = HashMap<String, Int>()
            for (text in texts) {
                val seenHere = HashSet<String>()
                for (m in WORD.findAll(text)) {
                    val surface = m.value
                    val word = VocabLemmas.lemma(surface, language)
                    if (word.length < 3 || word in pool || CoreVocabulary.isUngraded(word, language)) continue
                    if (isCapitalizedMidSentence(text, m.range.first, surface)) continue
                    if (seenHere.add(word)) out[word] = (out[word] ?: 0) + 1
                }
            }
            return out
        }

        /** Capitalized, and not because it opens a sentence. */
        private fun isCapitalizedMidSentence(text: String, start: Int, surface: String): Boolean {
            if (!surface.first().isUpperCase()) return false
            var i = start - 1
            while (i >= 0) {
                val c = text[i]
                if (c.isWhitespace()) { i -= 1; continue }
                // Straight after a sentence end (or an opening quote after one)
                // capitals are grammar, not a name.
                return c !in ".!?\n\"\u201C\u2018'("
            }
            return false   // first word of the text
        }

        /** A word as written: letters only, so contractions split at the
         *  apostrophe and digits never reach the notebook. */
        private val WORD = Regex("\\p{L}+")
    }

    @Serializable
    data class Record(
        val state: String,   // "used" | "known"
        @Serializable(with = IsoDateMillisSerializer::class) val firstAt: Long,
        @Serializable(with = IsoDateMillisSerializer::class) val lastAt: Long,
        val count: Int,
        /**
         * A `known` verdict given while the item was IN the notebook — the
         * learner studied it and then said "I know it". Only those are a
         * claim worth checking in a call: a word ticked while browsing a
         * level list, or a top-up waved off the first time it was dealt, was
         * never studied. Null on every record written before this existed,
         * which reads as "not from the notebook" — the conservative answer.
         */
        val fromStudying: Boolean? = null,
    )

    private val appContext = context.applicationContext
    private val mutex = Mutex()

    private fun file(language: String, name: String): File =
        File(LanguageScope.directory(appContext, language), name)

    // ── Reads the summarizer needs ──

    suspend fun studying(language: String): List<String> = mutex.withLock {
        readList(file(language, "vocab_studying.json"))
    }

    /**
     * The notebook words the learner actually PRACTICED — every studying word
     * except those a talk kept by itself and nobody has touched since
     * ([autoKept], iOS `practicedStudyingWords`). This is what the call's chip
     * row and the wrap-up's "you used what you practiced" read: a word the app
     * filed on its own is not something they studied, and offering it as
     * their goal reads as the app inventing homework.
     */
    suspend fun practicedStudying(language: String): List<String> = mutex.withLock {
        repairSurfaceKeysLocked(language)
        val studying = readList(file(language, "vocab_studying.json"))
        val auto = autoKeptLocked(language, studying)
        studying.filterNot { it in auto }
    }

    /**
     * PROVENANCE: studying words a talk kept by itself ([keepFromTalk]) that
     * the learner has not touched since. A hand bookmark, a deck snooze, a
     * removal or graduation clears the mark.
     *
     * First run (no file yet) treats every notebook word WITHOUT a schedule
     * entry as auto-kept — the conservative reading, since the only thing it
     * costs is a chip that must never lie — and repairs the words the
     * surface-form era filed: an inflected form becomes its headword, and a
     * closed-class word or interjection ("that", "wow") leaves the notebook.
     */
    private suspend fun autoKeptLocked(language: String, studying: List<String>): Set<String> {
        val f = file(language, "vocab_auto_kept.json")
        if (f.exists()) return readList(f).toSet()
        val schedule = StudyScheduleStore.shared(appContext).snapshot(language)
        val untouched = studying.filter { schedule.nextReview(StudyScheduleStore.Kind.WORD, it) == null }
        val sf = file(language, "vocab_studying.json")
        val repaired = LinkedHashSet<String>()
        val auto = LinkedHashSet<String>()
        for (w in studying) {
            if (w !in untouched) { repaired.add(w); continue }
            val head = VocabLemmas.lemma(w, language)
            if (CoreVocabulary.isUngraded(head, language)) continue
            if (repaired.add(head)) auto.add(head)
        }
        if (repaired.toList() != studying) writeList(sf, repaired.toList())
        writeList(f, auto.toList())
        return auto
    }

    /**
     * Once per language: word records and notebook entries written before the
     * forms table keyed a word by its SURFACE ("gets", "hours"). Each moves to
     * its headword; two spellings of one word merge, keeping the stronger
     * state (used over known), the larger count and both ends of its dates.
     * The learner's own name leaves an auto-kept notebook slot.
     */
    private suspend fun repairSurfaceKeysLocked(language: String) {
        if (language != "en") return
        val flag = file(language, "vocab_lemmatized.v2.flag")
        if (flag.exists()) return
        val poolFile = file(language, "vocab_pool.json")
        val merged = LinkedHashMap<String, Record>()
        for ((key, r) in readRecords(poolFile)) {
            val head = VocabLemmas.lemma(key, language)
            val prev = merged[head]
            merged[head] = if (prev == null) r else Record(
                state = if (prev.state == "used" || r.state == "used") "used" else prev.state,
                firstAt = minOf(prev.firstAt, r.firstAt), lastAt = maxOf(prev.lastAt, r.lastAt),
                count = maxOf(prev.count, r.count),
                fromStudying = if (prev.fromStudying == true || r.fromStudying == true) true else prev.fromStudying,
            )
        }
        writeRecords(poolFile, merged)
        val sf = file(language, "vocab_studying.json")
        val studying = readList(sf)
        val auto = autoKeptLocked(language, studying)
        val names = learnerNameTokens()
        val learnerLevel = CefrLevel.from(LanguageScope.level(appContext, language, "B1"))
        val fixed = LinkedHashSet<String>()
        for (w in readList(sf)) {
            val head = VocabLemmas.lemma(w, language)
            if (CoreVocabulary.isUngraded(head, language)) continue
            val isAuto = w in auto || head in auto
            if (isAuto && head in names) continue
            // An auto-kept graded word below the learner's level is one the
            // graded path never admits ("get", "day") — it got in as a
            // surface form through the off-list door. A hand-kept one stays.
            val level = CoreVocabulary.level(head, language)
            if (isAuto && level != null &&
                CoreVocabulary.levelRank(level) < CoreVocabulary.levelRank(learnerLevel)) continue
            fixed.add(head)
        }
        writeList(sf, fixed.toList())
        writeList(file(language, "vocab_auto_kept.json"),
            auto.map { VocabLemmas.lemma(it, language) }.filter { it in fixed })
        flag.writeText("1")
    }

    private suspend fun setAutoKept(language: String, add: Collection<String> = emptyList(),
                                    remove: Collection<String> = emptyList()) {
        val studying = readList(file(language, "vocab_studying.json"))
        val current = autoKeptLocked(language, studying)
        val next = (current + add.map { it.lowercase() }) - remove.map { it.trim().lowercase() }.toSet()
        if (next != current) writeList(file(language, "vocab_auto_kept.json"), next.toList())
    }

    /** A deck snooze is the learner working the word — it stops being auto-kept. */
    suspend fun markPracticed(word: String, language: String) = mutex.withLock {
        setAutoKept(language, remove = listOf(word))
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

    /** [hasUsedExpression]'s own test, read for its DATE — the talk book
     *  orders its shelf by when the phrase was mastered, not when it looked. */
    suspend fun expressionMasteredAt(phrase: String, language: String): Long? = mutex.withLock {
        val r = readRecords(file(language, "vocab_expressions.json"))[exprKey(phrase)]
        if (r != null && (r.state == "known" || r.count > 0)) r.lastAt else null
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
        // Producing a word live outranks every other state: a claimed word
        // becomes CONFIRMED (known → used), and a studying one leaves the
        // notebook and its schedule. Evidence beats an opinion about it.
        val studyingFile = file(language, "vocab_studying.json")
        val studying = readList(studyingFile).toMutableList()
        var leftNotebook = false
        for (lemma in VocabLemmas.lemmas(userTexts.drop(already))) {
            if (lemma !in coreSet) continue
            val r = records[lemma]
            if (r != null) records[lemma] = r.copy(state = "used", count = r.count + 1, lastAt = now)
            else { records[lemma] = Record("used", now, now, 1); newWords.add(lemma) }
            if (studying.remove(lemma)) leftNotebook = true
        }
        if (leftNotebook) {
            writeList(studyingFile, studying)
            setAutoKept(language, remove = newWords + records.keys.filter { it !in studying })
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
        com.roro.futurevoice.core.Analytics.capture("word_saved")
        // Bookmarking it again is how the learner takes back a removal.
        val rf = file(language, "vocab_removed_by_hand.json")
        val removed = readList(rf)
        val key = word.trim().lowercase()
        if (removed.contains(key)) writeList(rf, removed.filterNot { it == key })
        val f = file(language, "vocab_studying.json")
        val list = readList(f)
        // A hand bookmark is the learner choosing the word — whoever filed it.
        if (list.contains(word)) { setAutoKept(language, remove = listOf(word)); return }
        writeList(f, listOf(word) + list)   // newest first
        setAutoKept(language, remove = listOf(word))
        PracticeLog.record(appContext, PracticeLog.Kind.WORD)
    }

    /**
     * Take a word out of the notebook. A removal BY HAND is remembered
     * ([removedByHand]): a talk that puts an unbookmarked word straight back
     * every time is the app overruling a decision the learner made. Nothing
     * about it is permanent — bookmarking the word again clears the mark.
     * Graduation passes `byHand = false`; that is the ladder, not a verdict.
     */
    suspend fun removeStudying(word: String, language: String, byHand: Boolean = true) = mutex.withLock {
        val f = file(language, "vocab_studying.json")
        val list = readList(f)
        if (list.contains(word)) writeList(f, list.filterNot { it == word })
        setAutoKept(language, remove = listOf(word))
        val key = word.trim().lowercase()
        if (byHand && key.isNotEmpty()) {
            val rf = file(language, "vocab_removed_by_hand.json")
            val removed = readList(rf)
            if (!removed.contains(key)) writeList(rf, removed + key)
        }
    }

    /** Words the learner took out of the notebook by hand. */
    suspend fun removedByHand(language: String): List<String> = mutex.withLock {
        readList(file(language, "vocab_removed_by_hand.json"))
    }

    /** Clear the "they threw this out" mark — the learner's own way is to
     *  bookmark the word again, which goes through [addStudying]. */
    suspend fun forgetRemovedByHand(word: String, language: String) = mutex.withLock {
        val f = file(language, "vocab_removed_by_hand.json")
        val list = readList(f)
        val key = word.trim().lowercase()
        if (list.contains(key)) writeList(f, list.filterNot { it == key })
    }

    /**
     * The words a finished talk TAUGHT, into the notebook — the set the
     * book's word chapter shows, so the page and the notebook can never
     * disagree about what a talk taught. Returns what was actually added.
     *
     * Not [addStudying] in a loop, for one reason: that call logs a practice
     * rep and fires `word_saved`, because keeping a word by hand IS effort.
     * Nothing here was chosen by the learner, so counting it as their effort
     * would inflate the daily goal with work nobody did.
     *
     * Three kinds of word are skipped, all meaning "not new to them": one
     * they have already said or marked known, one already in the notebook,
     * and one they took out of it by hand.
     */
    suspend fun keepFromTalk(words: List<String>, language: String): List<String> = mutex.withLock {
        val f = file(language, "vocab_studying.json")
        val list = readList(f).toMutableList()
        val records = readRecords(file(language, "vocab_pool.json"))
        val removed = readList(file(language, "vocab_removed_by_hand.json")).toSet()
        val added = ArrayList<String>()
        for (word in words) {
            val key = word.trim().lowercase()
            if (key.isEmpty() || records[key] != null || list.contains(key) || key in removed) continue
            list.add(0, key)   // newest first
            added.add(key)
        }
        if (added.isEmpty()) return emptyList()
        writeList(f, list)
        setAutoKept(language, add = added)
        com.roro.futurevoice.core.Analytics.capture("words_kept_from_talk",
            mapOf("count" to added.size))
        added
    }

    /** "used" | "known" | null — null means the pool has never met the word. */
    /**
     * Distinct words the learner has actually PRODUCED, counted per CEFR
     * band. "used" only — a word marked known was recognized, not spoken,
     * and the vocabulary level is a claim about production.
     */
    suspend fun usedWordsByLevel(language: String): Map<CefrLevel, Int> = mutex.withLock {
        val counts = mutableMapOf<CefrLevel, Int>()
        readRecords(file(language, "vocab_pool.json")).forEach { (lemma, r) ->
            if (r.state != "used") return@forEach
            CoreVocabulary.level(lemma, language)?.let { counts[it] = (counts[it] ?: 0) + 1 }
        }
        counts
    }

    /** Words PRODUCED within [days], most recent first (iOS
     *  `usedWords(withinDays:)`) — the weekly test's last meaning source. */
    suspend fun usedWords(withinDays: Int, language: String,
                          now: Long = System.currentTimeMillis()): List<String> = mutex.withLock {
        val cutoff = now - withinDays * 86_400_000L
        readRecords(file(language, "vocab_pool.json"))
            .filter { it.value.state == "used" && it.value.lastAt >= cutoff }
            .entries.sortedByDescending { it.value.lastAt }.map { it.key }
    }

    /** Every word with a record at all — known or used (iOS `records.keys`). */
    suspend fun recordedWords(language: String): List<String> = mutex.withLock {
        readRecords(file(language, "vocab_pool.json")).keys.toList()
    }

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
        com.roro.futurevoice.core.Analytics.capture("word_known")
        mutex.withLock {
            val f = file(language, "vocab_pool.json")
            val records = readRecords(f)
            if (records[lemma] == null) {
                // Was it a word they were STUDYING? That is what makes the
                // claim worth checking in a call.
                val studying = readList(file(language, "vocab_studying.json")).contains(lemma)
                writeRecords(f, records + (lemma to
                    Record("known", now, now, 0, fromStudying = if (studying) true else null)))
            }
        }
        removeStudying(lemma, language, byHand = false)
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
        if (studying) com.roro.futurevoice.core.Analytics.capture("expression_bookmarked")
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
        val studying = known &&
            readList(file(language, "vocab_studying_expressions.json")).contains(k)
        val fromStudying = if (studying) true else null
        val updated = when {
            r != null -> r.copy(state = if (known) "known" else "used", lastAt = now,
                fromStudying = r.fromStudying ?: fromStudying)
            known -> Record("known", now, now, 0, fromStudying = fromStudying)
            else -> return
        }
        writeRecords(f, records + (k to updated))
        if (known) PracticeLog.record(appContext, PracticeLog.Kind.EXPRESSION, finished = true)
    }

    /**
     * Words the learner SAID they know and no call has confirmed yet — the
     * claim a call is there to check. Only verdicts given on something they
     * were studying count: a word ticked in a level list was never studied.
     */
    suspend fun unconfirmedKnownWords(language: String): List<String> = mutex.withLock {
        repairSurfaceKeysLocked(language)
        readRecords(file(language, "vocab_pool.json"))
            .filter { it.value.state == "known" && it.value.fromStudying == true }
            .keys.toList()
    }

    /** The same for expressions: claimed, never yet produced in a talk. */
    suspend fun unconfirmedKnownExpressions(language: String): List<String> = mutex.withLock {
        readRecords(file(language, "vocab_expressions.json"))
            .filter { it.value.state == "known" && it.value.count == 0 &&
                it.value.fromStudying == true }
            .keys.toList()
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
                         language: String,
                         excludingLemmas: Set<String> = emptySet()): List<String> {
        val minRank = atOrAbove?.let { CoreVocabulary.levelRank(it) }
        // The learner's own name is not vocabulary. The fluent self greets
        // them by it, often at the head of a sentence where the capital-letter
        // name rule can't see it — "toi" was kept as a word to study.
        val excludingLemmas = excludingLemmas + learnerNameTokens()
        val graded = VocabLemmas.lemmas(fluentTexts, language)
            .mapNotNull { w ->
                if (w in excludingLemmas) return@mapNotNull null
                val rank = CoreVocabulary.levelRank(CoreVocabulary.level(w, language) ?: return@mapNotNull null)
                if (minRank != null && rank < minRank) null else w to rank
            }
            .sortedWith(compareBy({ it.second }, { it.first }))
            .map { it.first }
            .distinct()

        // Words the graded pool doesn't carry. The pool is ~8k content words,
        // so an ordinary noun like "chore" isn't in it — and being absent
        // used to mean being invisible, even when the whole call was about
        // the word.
        //
        // They are NOT capped: a cap has to decide which ones die, and with
        // most said once there is nothing to decide it by. What orders them
        // is evidence, in two grades — a word the fluent self came back to
        // across several TURNS is what the call was about and leads outright;
        // a word said once is a weaker claim than a curated level match, so
        // those fill whatever the graded words left.
        val offList = offListContentWords(fluentTexts, language)
            .filterKeys { it !in excludingLemmas && it !in graded }
        val recurring = offList.filterValues { it > 1 }.entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { it.key }
        val saidOnce = offList.filterValues { it == 1 }.keys.sorted()
        return recurring + graded + saidOnce
    }


    @Volatile private var nameCache: Pair<Long, Set<String>> = -1L to emptySet()

    /** The persona's display name, as lowercase word tokens (cached per file write). */
    private fun learnerNameTokens(): Set<String> {
        val f = File(appContext.filesDir, "persona.json")
        val stamp = if (f.exists()) f.lastModified() else 0L
        nameCache.takeIf { it.first == stamp }?.let { return it.second }
        val tokens = runCatching {
            StoreJson.json.decodeFromString(com.roro.futurevoice.talk.UserPersona.serializer(), f.readText())
                .displayName.lowercase().split(Regex("[^\\p{L}]+")).filter { it.length > 1 }.toSet()
        }.getOrElse { emptySet() }
        nameCache = stamp to tokens
        return tokens
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
