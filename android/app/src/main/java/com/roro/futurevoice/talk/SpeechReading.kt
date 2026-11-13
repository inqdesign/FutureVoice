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
    const val VERSION = 8
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
              coverage: Double, gender: String, weakSounds: Int? = null): SpeechReadingScore? {
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
            weakSounds = weakSounds, scriptWords = scriptTokens,
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

    /** A sound Azure scored under the price list's bar, where it was said. */
    data class WeakSound(val phoneme: String, val score: Int)

    /**
     * Every weak sound, laid on the script token it was said in (iOS
     * 2026-11-13, founder: 35 sounds cost points and none showed on the
     * script). Pieces overlap by two words at their starts, so a word assessed
     * twice counts ONCE, its first reading: the count the price list charges
     * and the marks on the script are the same set.
     */
    fun weakSounds(pieces: List<PronunciationResult>, script: String,
                   fluent: List<SpeechReference.Word>? = null): Map<Int, List<WeakSound>> {
        val bar = SpeechReadingScore.Price.WEAK_SOUND_BELOW
        val spared = fluentLowSounds(fluent, script)
        val out = LinkedHashMap<Int, List<WeakSound>>()
        for ((t, word) in judgedWords(pieces, script)) {
            val weak = word.phonemes.mapNotNull { p ->
                val a = p.accuracy ?: return@mapNotNull null
                if (a >= bar || spared[t]?.contains(p.phoneme) == true) null else WeakSound(p.phoneme, a)
            }
            if (weak.isNotEmpty()) out[t] = weak
        }
        return out
    }

    /** The fluent reading's sounds that the same assessment scores under this,
     *  by script token (iOS 2026-11-13: the reading says "nyu" in newspapers,
     *  and the dictionary wants "noo"). A learner who says such a sound like
     *  the reading is never charged for it. 60 is a choice, not a measurement. */
    const val FLUENT_SOUND_BAR = 60

    fun fluentLowSounds(fluent: List<SpeechReference.Word>?, script: String): Map<Int, Set<String>> {
        if (fluent == null || fluent.none { it.ph != null }) return emptyMap()
        val tokens = SpeechDelivery.referenceTokens(script).map { it.core }
        val match = SpeechDelivery.align(fluent.map { SpeechDelivery.core(it.w) }, tokens)
        val out = HashMap<Int, MutableSet<String>>()
        fluent.forEachIndexed { i, word ->
            val t = match[i] ?: return@forEachIndexed
            val ph = word.ph ?: return@forEachIndexed
            val low = ph.filter { it.a < FLUENT_SOUND_BAR }.map { it.p }.toSet()
            if (low.isNotEmpty()) out.getOrPut(t) { mutableSetOf() }.addAll(low)
        }
        return out
    }

    /** Each script token's assessed word, its FIRST reading where pieces
     *  overlap: what [weakSounds] counts from, and what the sounds sheet shows
     *  a tapped word with. */
    fun judgedWords(pieces: List<PronunciationResult>, script: String): Map<Int, PronunciationResult.Word> {
        val tokens = SpeechDelivery.referenceTokens(script).map { it.core }
        val words = pieces.flatMap { p -> p.words.filter { it.isJudged } }
        val match = SpeechDelivery.align(words.map { SpeechDelivery.core(it.word) }, tokens)
        val out = LinkedHashMap<Int, PronunciationResult.Word>()
        words.forEachIndexed { i, word ->
            val t = match[i] ?: return@forEachIndexed
            if (out[t] == null) out[t] = word
        }
        return out
    }

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
    /** Sounds Azure scored under [Price.WEAK_SOUND_BELOW] (scoring 8). Null on
     *  earlier takes, or when nothing was assessed. */
    val weakSounds: Int? = null,
    /** The script's words, for the words left unread (scoring 8). */
    val scriptWords: Int? = null,
    /** "listen": measured against the one listening reading (iOS 2026-11-13).
     *  Null: the male/female pair, which a challenge take is re-judged off
     *  when its result is opened ([SpeechReadingRejudge]). */
    val reference: String? = null,
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

    // MARK: The price list (scoring 8, iOS 2026-11-13)
    //
    // Founder: "start at 100, and every mistake counts". The relative prices
    // come from 138 human readings; `submit_speech_reading_take_v8` recomputes
    // the same total from the same counts: change a price here and there
    // together.
    object Price {
        const val STOP = 1.0              // a stop inside a sentence the native reading doesn't make
        const val WORD = 1.0              // a word changed, missed or added, or left unread at the end
        // A sound Azure scores under WEAK_SOUND_BELOW: 0.4, the calibration's
        // own ratio to a word.
        const val SOUND = 0.4
        const val WEAK_SOUND_BELOW = 40
        const val RHYTHM_PER_POINT = 0.5  // per 0.01 of rhythm below RHYTHM_BAR
        const val RHYTHM_BAR = 90         // r × 100: natives sit around 93
        const val SPEED_PER_POINT = 1.0   // per point of pace below SPEED_BAR
        const val SPEED_BAR = 85          // % of the native reading's pace: natives median 91
    }

    /** [count]: how many (stops, words, sounds) or how far below the bar
     *  (rhythm, pace). */
    data class Deduction(val part: Part, val count: Int, val points: Double)

    /** The rhythm and pace as the price list reads them: whole points. */
    val rhythmPoint: Int get() = SpeechReading.round(rhythm * 100).toInt()
    val speedPoint: Int get() = if (speed > 0) SpeechReading.round(100 * min(speed, 1 / speed)).toInt() else 0
    /** Words the reading never reached (it stopped early). */
    val unreadWords: Int get() {
        val w = scriptWords ?: return 0
        return max(0, SpeechReading.round((1 - min(1.0, coverage)) * w).toInt())
    }

    /** Every line of the receipt, in the order the page lists them: from the
     *  whole reading down to a single sound. Empty before scoring 8. */
    val deductions: List<Deduction> get() {
        if (version < 8) return emptyList()
        val words = slips + unreadWords
        val sounds = weakSounds ?: 0
        val r = max(0, Price.RHYTHM_BAR - rhythmPoint)
        val s = max(0, Price.SPEED_BAR - speedPoint)
        return listOf(
            Deduction(Part.SPEED, s, s * Price.SPEED_PER_POINT),
            Deduction(Part.RHYTHM, r, r * Price.RHYTHM_PER_POINT),
            Deduction(Part.PAUSES, extraPauses.size, extraPauses.size * Price.STOP),
            Deduction(Part.ACCURACY, words, words * Price.WORD),
            Deduction(Part.PRONUNCIATION, sounds, sounds * Price.SOUND),
        )
    }

    val lost: Double get() = deductions.sumOf { it.points }

    fun areaLeft(d: Deduction): Double = max(0.0, AREA_SHARE - d.points)

    /** An area's score out of 100. */
    fun areaScore(d: Deduction): Int = SpeechReading.round(areaLeft(d) * 100 / AREA_SHARE).toInt()

    val isPerfect: Boolean get() =
        if (version >= 8) lost == 0.0 else parts.all.all { it.second == 100 } && coverage >= 0.999

    val total: Int get() {
        if (isPerfect) return 100
        if (version >= 8) {
            val left = deductions.sumOf { areaLeft(it) }
            return min(99, max(0, SpeechReading.round(left).toInt()))
        }
        val mean = parts.all.sumOf { it.second } / 5.0
        // Stopping early scales everything but accuracy — as the older scoring did.
        val scaled = mean * (0.2 + 0.8 * min(1.0, coverage))
        return min(99, max(0, SpeechReading.round(scaled).toInt()))
    }

    /** The part that cost the most, to work on next; null on a perfect take. */
    val focus: Part? get() = when {
        isPerfect -> null
        version >= 8 -> deductions.minByOrNull { areaLeft(it) }?.part
        else -> parts.all.minByOrNull { it.second }?.first
    }

    val level: SpeechReadingLevel get() = SpeechReadingLevel.of(total)

    companion object {
        /** A narrator's level, part by part. */
        const val BAR = 95
        /** Each area holds 20 of the 100 points (iOS 2026-11-13, founder: "each
         *  area scored, so what's weak shows at a glance"). An area's score is
         *  what is left of its 20, out of 100; it stops at 0, so the total is
         *  always the five areas' average. `submit_speech_reading_take_v8`
         *  adds the same shares. */
        const val AREA_SHARE = 20.0
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
    @Serializable data class Word(
        val w: String, val s: Int, val e: Int,
        /** The fluent reading's own sounds with their scores (the listening
         *  reading only, iOS 2026-11-13). Null on scoring references. */
        val ph: List<Sound>? = null,
    ) {
        @Serializable data class Sound(val p: String, val a: Int)
    }

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

/**
 * Re-judges a challenge take scored against the old male/female pair against
 * the one listening reading (iOS `SpeechReadingRejudge`, 2026-11-13, founder:
 * "re-judge the earlier attempts if we can"). Everything it needs is on the
 * take: the assessed pieces with their word timings, the transcript, the
 * recording.
 */
object SpeechReadingRejudge {
    fun needs(take: com.roro.futurevoice.data.SpeechTake): Boolean {
        val r = take.metrics.reading ?: return false
        return r.version >= 8 && r.reference == null && !take.assessments.isNullOrEmpty()
    }

    /** The re-judged take, saved; null when it didn't need it or couldn't be. */
    suspend fun run(context: Context, take: com.roro.futurevoice.data.SpeechTake,
                    script: com.roro.futurevoice.data.SpeechScript): com.roro.futurevoice.data.SpeechTake? {
        if (!needs(take) || !SpeechListenService.available(script)) return null
        val fluent = SpeechListenService.reading(context, script) ?: return null
        val starts = take.assessmentStartsMs
        val pieces = take.assessments.orEmpty().mapIndexed { i, result ->
            SpeechDelivery.Piece("", result, starts?.getOrNull(i) ?: 0)
        }
        val audio = com.roro.futurevoice.data.SpeechStore.mediaFile(context, take.audioFilename)
        var metrics = take.metrics
        val (delivered, scored) = withContext(Dispatchers.Default) {
            SpeechDelivery.measure(pieces, script.language, audio) to
                SpeechAnalyzer.analyze(script.body, take.transcript, script.language, null, metrics.pronunciation)
        }
        metrics = metrics.copy(slips = scored.slips, scriptTokens = scored.scriptTokens)
        val reference = SpeechReference(2, fluent.words, fluent.words)
        val reading = com.roro.futurevoice.ui.speech.SpeechTakeSession.reading(
            pieces, reference, script.body, metrics, delivered, fluent.words)
            ?.copy(gender = fluent.gender, reference = "listen") ?: return null
        val store = com.roro.futurevoice.data.SpeechStore.shared(context)
        val saved = withContext(Dispatchers.Main) {
            store.update(take.id) { it.copy(metrics = metrics.copy(reading = reading, overall = reading.total)) }
        } ?: return null
        com.roro.futurevoice.core.Analytics.capture("speech_take_rejudged", mapOf("overall" to reading.total))
        return saved
    }
}
