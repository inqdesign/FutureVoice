package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.IdempotencyKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.ConnectionPool
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign
import kotlin.math.sqrt
import kotlin.math.truncate

/**
 * Season 2's speech score: a take compared word for word with a NATIVE reading
 * of the same script, in the reader's gender — iOS `SpeechReading`. Every part
 * is the measurement itself on a 0-100 scale, and the total is their plain
 * average; 100 needs every part at 100 (version 7, 2026-11-09). A stop after
 * punctuation is not a fault, only a mid-sentence stop the reference lacks
 * counts.
 */
object SpeechReading {
    const val VERSION = 7
    /** A take with `scoring` at or above this was scored against a reference
     *  (iOS compares with `SpeechScoreV4.version`). */
    const val READING_SCORING_FROM = 4

    const val PAUSE_SECONDS = 0.15
    /** A take's median pitch above this is read against the female reference. */
    const val FEMALE_ABOVE_HZ = 165.0

    /** The averages the result page quotes, from the validation set. */
    const val NATIVE_AVERAGE = 96
    const val NARRATOR_AVERAGE = 97
    const val LEARNER_AVERAGE = 81

    private const val PREFS = "futurevoice"
    private const val DEV_KEY = "speech.scoring4"
    private fun seasonKey(language: String) = "speech.readingSeason.${language.take(2)}"

    fun applies(language: String): Boolean = language.startsWith("en")

    /** Whether a take in this language is scored this way: the language's
     *  Season 2 is open (the server says, `speech_season_status`), or this is
     *  a debug build with iOS's developer switch left on. */
    fun isActive(context: Context, language: String): Boolean {
        if (!applies(language)) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return (BuildConfig.DEBUG && prefs.getBoolean(DEV_KEY, true)) || prefs.getBoolean(seasonKey(language), false)
    }

    fun setSeasonOpen(context: Context, open: Boolean, language: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(seasonKey(language), open).apply()
    }

    /** Swift's `.rounded()`: halves away from zero (Kotlin's `round` goes to even). */
    fun round(x: Double): Double {
        val whole = truncate(x)
        return if (abs(x - whole) >= 0.5) whole + sign(x) else whole
    }

    // MARK: - Lining words up with the script

    /** A word's duration and the silence after it, in seconds; the silence is
     *  null where the next word wasn't timed in the same stretch of audio. */
    data class Timed(val duration: Double, val gapAfter: Double?)

    /** [breakAfter] marks where one stretch of audio ends (a take's piece), so
     *  no gap is measured across it. */
    data class TimedWord(val word: String, val startMs: Int, val endMs: Int, val breakAfter: Boolean)

    /** Script token index → its timing, from words in reading order. */
    fun timeline(words: List<TimedWord>, script: List<String>): Map<Int, Timed> {
        val match = SpeechDelivery.align(words.map { SpeechDelivery.core(it.word) }, script)
        val out = HashMap<Int, Timed>()
        words.forEachIndexed { i, w ->
            val t = match[i] ?: return@forEachIndexed
            var gap: Double? = null
            if (!w.breakAfter && i + 1 < words.size && match[i + 1] == t + 1) {
                gap = (words[i + 1].startMs - w.endMs) / 1000.0
            }
            out[t] = Timed(max(0.02, (w.endMs - w.startMs) / 1000.0), gap)
        }
        return out
    }

    // MARK: - Scoring

    fun score(take: Map<Int, Timed>, reference: Map<Int, Timed>, script: List<String>,
              stops: List<SpeechDelivery.Stop>, slips: Int?, scriptTokens: Int?, missed: List<String>,
              soundAccuracy: Int?, weakest: List<SpeechDelivery.Sound>,
              coverage: Double, gender: String): SpeechReadingScore? {
        val both = take.keys.filter { reference[it] != null }.sorted()
        if (both.size < 20) return null
        val refSum = both.sumOf { reference.getValue(it).duration }
        val takeSum = both.sumOf { take.getValue(it).duration }
        val speed = refSum / takeSum
        val rhythm = pearson(both.map { ln(reference.getValue(it).duration) },
            both.map { ln(take.getValue(it).duration) }) ?: 0.0

        // Stops inside a sentence that the native reading doesn't make. A
        // stop after punctuation is the script asking for one.
        val extra = mutableListOf<SpeechReadingScore.Pause>()
        for (i in both) {
            if (i >= stops.size || stops[i] != SpeechDelivery.Stop.NONE) continue
            val gap = take.getValue(i).gapAfter ?: continue
            if (gap < PAUSE_SECONDS) continue
            val r = reference[i]?.gapAfter
            if (r != null && r >= PAUSE_SECONDS) continue
            extra += SpeechReadingScore.Pause(script[i], round(gap * 10) / 10, i)
        }
        val pausesPer100 = 100.0 * extra.size / both.size

        // Words held far longer than the native reading holds them, once the
        // reader's own pace is taken out.
        val ratios = both.map { ln(take.getValue(it).duration / reference.getValue(it).duration) }
        val tempo = ratios.sorted()[ratios.size / 2]
        val held = both.zip(ratios).map { (i, r) ->
            SpeechReadingScore.Held(script[i], round(exp(r - tempo) * 10) / 10,
                round(take.getValue(i).duration * 10) / 10,
                round(reference.getValue(i).duration * 10) / 10, i)
        }.filter { h ->
            // A tenth of a second is not worth naming; this doesn't touch the score.
            val over = (h.seconds ?: 0.0) - (h.nativeSeconds ?: 0.0)
            h.times >= 2 && over >= 0.15
        }.sortedByDescending { it.times }

        val slipsPer100 = if (slips != null && (scriptTokens ?: 0) > 0) 100.0 * slips / scriptTokens!! else 0.0

        val parts = parts(speed, rhythm, pausesPer100, slipsPer100, soundAccuracy?.toDouble())
        return SpeechReadingScore(
            version = VERSION, gender = gender, parts = parts, coverage = coverage,
            speed = round(speed * 100) / 100, rhythm = round(rhythm * 100) / 100,
            pausesPer100 = round(pausesPer100 * 10) / 10, slipsPer100 = round(slipsPer100 * 10) / 10,
            soundAccuracy = soundAccuracy, slips = slips ?: 0,
            // All of them: the script on the result page marks every one.
            extraPauses = extra.sortedByDescending { it.seconds },
            held = held, missed = missed.take(5),
            weakest = if (parts.pronunciation < 100) weakest.filter { it.score < 80 }.take(3) else emptyList(),
        )
    }

    /** The five parts from the five measures — what the calibration fixture drives. */
    fun parts(speed: Double, rhythm: Double, pausesPer100: Double, slipsPer100: Double,
              soundAccuracy: Double?): SpeechReadingScore.Parts =
        SpeechReadingScore.Parts(
            // The share of the native reading's pace, too slow or too fast.
            speed = if (speed > 0) percent(100 * min(speed, 1 / speed)) else 0,
            rhythm = percent(100 * rhythm),
            pauses = percent(100 - pausesPer100),
            accuracy = percent(100 - slipsPer100),
            pronunciation = soundAccuracy?.let(::percent) ?: 100,
        )

    private fun percent(value: Double): Int = round(min(100.0, max(0.0, value))).toInt()

    fun pearson(x: List<Double>, y: List<Double>): Double? {
        if (x.size != y.size || x.size < 4) return null
        val mx = x.sum() / x.size
        val my = y.sum() / y.size
        var num = 0.0; var dx = 0.0; var dy = 0.0
        for (i in x.indices) {
            num += (x[i] - mx) * (y[i] - my)
            dx += (x[i] - mx) * (x[i] - mx)
            dy += (y[i] - my) * (y[i] - my)
        }
        if (dx <= 0 || dy <= 0) return null
        return num / sqrt(dx * dy)
    }
}

/** A Season 2 take's score, stored on its metrics. Same JSON keys as iOS's
 *  Codable: takes sync between devices. */
@Serializable
data class SpeechReadingScore(
    val version: Int,
    /** Which reference it was read against ("male" / "female"). */
    val gender: String,
    val parts: Parts,
    val coverage: Double,
    /** The native reading's time over yours: 1 = same pace. */
    val speed: Double,
    /** Word-length pattern vs the native reading, -1…1. */
    val rhythm: Double,
    /** Pauses the native reading doesn't have, per 100 words. */
    val pausesPer100: Double,
    /** Words changed, left out or added, per 100 script words. */
    val slipsPer100: Double,
    val soundAccuracy: Int? = null,
    val slips: Int,
    val extraPauses: List<Pause>,
    val held: List<Held>,
    val missed: List<String>,
    val weakest: List<SpeechDelivery.Sound>,
) {
    @Serializable
    data class Parts(val speed: Int, val rhythm: Int, val pauses: Int, val accuracy: Int, val pronunciation: Int) {
        val all: List<Pair<Part, Int>> get() = listOf(
            Part.SPEED to speed, Part.RHYTHM to rhythm, Part.PAUSES to pauses,
            Part.ACCURACY to accuracy, Part.PRONUNCIATION to pronunciation,
        )
        fun score(part: Part): Int = all.first { it.first == part }.second
    }

    enum class Part(val raw: String) {
        SPEED("speed"), RHYTHM("rhythm"), PAUSES("pauses"), ACCURACY("accuracy"), PRONUNCIATION("pronunciation")
    }

    /** [index] is the script token it follows. */
    @Serializable
    data class Pause(val after: String, val seconds: Double, val index: Int? = null)

    /** A word held far longer than the native reading holds it. [times] is
     *  after the reader's own pace is taken out (what picks the word); the
     *  seconds are what the page shows. */
    @Serializable
    data class Held(
        val word: String,
        val times: Double,
        val seconds: Double? = null,
        val nativeSeconds: Double? = null,
        val index: Int? = null,
    )

    val isPerfect: Boolean get() = parts.all.all { it.second == 100 } && coverage >= 0.999

    val total: Int get() {
        if (isPerfect) return 100
        val mean = parts.all.sumOf { it.second } / 5.0
        // Stopping early scales everything but accuracy — as the older scoring did.
        val scaled = mean * (0.2 + 0.8 * min(1.0, coverage))
        return min(99, max(0, SpeechReading.round(scaled).toInt()))
    }

    /** The part that cost the most, to work on next; null on a perfect take. */
    val focus: Part? get() = if (isPerfect) null else parts.all.minByOrNull { it.second }?.first

    val level: SpeechReadingLevel get() = SpeechReadingLevel.of(total)

    companion object {
        /** A narrator's level, part by part. */
        const val BAR = 95
    }
}

/** The nickname a score earns: a comparison for fun, not a grade. Highest first. */
enum class SpeechReadingLevel(val floor: Int) {
    NEWS_ANCHOR(100), AUDIOBOOK(97), BORN_AND_RAISED(95), PASSES_AS_LOCAL(94), OFFICE_ACE(92), PRESENTER(90),
    THIRD_YEAR_ABROAD(89), FIRST_YEAR_ABROAD(86), LANGUAGE_SCHOOL(85), IMMIGRATION(83), RESTAURANT(80),
    GESTURES(72), WARMING_UP(0);

    /** The next one up; null at the top. */
    val next: SpeechReadingLevel? get() = if (ordinal > 0) entries[ordinal - 1] else null

    val range: IntRange get() = floor..((next?.floor ?: 101) - 1)

    companion object {
        fun of(total: Int): SpeechReadingLevel = entries.firstOrNull { total >= it.floor } ?: WARMING_UP
    }
}

/** The native reference reading of a script, both genders, word-timed
 *  (`speech-reference` edge function). */
@Serializable
data class SpeechReference(val version: Int, val male: List<Word>, val female: List<Word>) {
    @Serializable data class Word(val w: String, val s: Int, val e: Int)

    fun words(gender: String): List<Word> = if (gender == "female") female else male
}

/** Kept on the phone per script text, like iOS. */
object SpeechReferenceService {
    /** The server may have to make the reading first; its own connection pool
     *  keeps that off the take's other requests. */
    private val client by lazy {
        Edge.client.newBuilder().connectionPool(ConnectionPool())
            .readTimeout(120, TimeUnit.SECONDS).build()
    }

    @Serializable private data class Body(val text: String, val language: String)

    private fun cacheFile(context: Context, text: String, language: String): File {
        val digest = MessageDigest.getInstance("SHA-256").digest("$language|$text".toByteArray())
            .joinToString("") { "%02x".format(it) }
        val dir = File(LanguageScope.directory(context, language), "speech_references").apply { mkdirs() }
        return File(dir, "${digest.take(32)}.json")
    }

    /** From the phone, else the server (which makes it once per script). */
    suspend fun fetch(context: Context, text: String, language: String): SpeechReference? = withContext(Dispatchers.IO) {
        val file = cacheFile(context, text, language)
        runCatching { Edge.json.decodeFromString(SpeechReference.serializer(), file.readText()) }
            .getOrNull()?.let { return@withContext it }
        runCatching {
            val request = Request.Builder()
                .url(Config.functionUrl("speech-reference"))
                .header("Authorization", "Bearer ${AuthRepository().accessToken()}")
                .header("X-Idempotency-Key", IdempotencyKey.headerSafe(UUID.randomUUID().toString().uppercase()))
                .post(Edge.json.encodeToString(Body.serializer(), Body(text, language.take(2)))
                    .toRequestBody("application/json".toMediaType()))
                .build()
            client.newCall(request).execute().use { response ->
                if (response.code != 200) return@runCatching null
                val raw = response.body?.string().orEmpty()
                val reference = Edge.json.decodeFromString(SpeechReference.serializer(), raw)
                if (reference.male.isEmpty() || reference.female.isEmpty()) return@runCatching null
                runCatching { file.writeText(raw) }
                reference
            }
        }.getOrNull()
    }
}
