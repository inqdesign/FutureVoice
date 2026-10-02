package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * Every shadow attempt the learner has made, in the iOS on-disk shape — an
 * attempt saved here reads on an iPhone and vice versa.
 *
 * It exists for two things the shadow feature cannot work without: knowing
 * which lines have already been attempted (so today's hand is fresh material
 * rather than the same four lines forever), and knowing which came back LOW
 * (so they can be offered again). Without it every deal is the same deal.
 */
@Serializable
data class ShadowAttempt(
    val id: String = StoreJson.newId(),
    /** The target line (Turn.id) this attempt was for. */
    val turnId: String,
    /** Captured at attempt time, so a display survives the turn being pruned. */
    val targetText: String,
    val learnerTranscript: String = "",
    val recordingFilename: String? = null,
    /** 0–100. */
    val matchScore: Int = 0,
    /**
     * The words this take covered, when it was a PHRASE rather than the whole
     * line — null means the whole line. Old records decode as whole-line,
     * which is what they were.
     *
     * Tapping two words and saying "the bank" used to save an attempt under
     * the line's own id with nothing to mark it partial, so a two-word take
     * checked the sentence off. A phrase take is still listed, replayable and
     * counted as a rep; it is excluded from everything that judges the LINE
     * (iOS `17d0b56`).
     */
    val phraseFirst: Int? = null,
    val phraseLast: Int? = null,
    /** 0–100 word-onset timing; null = not measurable. */
    val rhythmScore: Int? = null,
    val pronunciation: String = "",
    val pacing: String = "",
    val fix: String = "",
    @Serializable(with = IsoDateMillisSerializer::class)
    val createdAt: Long = System.currentTimeMillis(),
) {
    /** A take of PART of the line — never a verdict on the line itself. */
    val isPartial: Boolean get() = phraseFirst != null && phraseLast != null

    /**
     * The ONE number a take is judged by — history, mastery, retry picks
     * (iOS `ShadowAttempt.overallScore`). Words and beat when the beat was
     * measured; words alone otherwise, so every attempt saved before rhythm
     * existed keeps its score.
     */
    val overallScore: Int
        get() = com.roro.futurevoice.talk.ShadowScore.overallScore(matchScore, rhythmScore)
}

class ShadowAttemptStore private constructor(private val context: Context) {

    companion object {
        @Volatile private var instance: ShadowAttemptStore? = null
        fun shared(context: Context): ShadowAttemptStore =
            instance ?: synchronized(this) {
                instance ?: ShadowAttemptStore(context.applicationContext).also { instance = it }
            }
        /** Enough to know what has been tried without growing without bound. */
        private const val MAX = 500
    }

    private val mutex = Mutex()

    private fun file(language: String) =
        File(LanguageScope.directory(context, language), "shadow_attempts.json")

    suspend fun load(language: String): List<ShadowAttempt> = withContext(Dispatchers.IO) {
        mutex.withLock { read(language) }
    }

    private fun read(language: String): List<ShadowAttempt> = runCatching {
        val f = file(language)
        if (!f.exists()) return emptyList()
        StoreJson.json.decodeFromString(ListSerializer(ShadowAttempt.serializer()), f.readText())
    }.getOrDefault(emptyList())

    suspend fun add(attempt: ShadowAttempt, language: String) = withContext(Dispatchers.IO) {
        mutex.withLock {
            val all = (read(language) + attempt).takeLast(MAX)
            file(language).writeText(
                StoreJson.json.encodeToString(ListSerializer(ShadowAttempt.serializer()), all))
        }
        StoreEvents.bump()
    }

    /**
     * Replace an attempt already on file — the coach's bullets land on the
     * record the take saved, never as a second attempt (a second `add` would
     * count the take twice).
     */
    suspend fun update(attempt: ShadowAttempt, language: String) = withContext(Dispatchers.IO) {
        mutex.withLock {
            val all = read(language)
            if (all.none { it.id == attempt.id }) return@withLock
            file(language).writeText(StoreJson.json.encodeToString(
                ListSerializer(ShadowAttempt.serializer()), all.map { if (it.id == attempt.id) attempt else it }))
        }
        StoreEvents.bump()
    }

    /** Remove one attempt (the past-attempt row's Delete) and its recording. */
    suspend fun delete(id: String, language: String) = withContext(Dispatchers.IO) {
        mutex.withLock {
            val all = read(language)
            all.firstOrNull { it.id == id }?.recordingFilename?.let { runCatching { File(it).delete() } }
            file(language).writeText(StoreJson.json.encodeToString(
                ListSerializer(ShadowAttempt.serializer()), all.filterNot { it.id == id }))
        }
        StoreEvents.bump()
    }
}
