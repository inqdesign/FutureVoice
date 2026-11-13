package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.ScriptStudy
import com.roro.futurevoice.data.SpeechScript
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
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * A challenge's fluent reading to LISTEN to (iOS `SpeechListenAudio`,
 * 2026-11-13): one audio file per challenge, in the one voice it was published
 * with. Since iOS cddddcc0 it is also THE reference a Season 2 take is scored
 * against (karaoke: its tempo, rhythm and pauses are the target).
 */
@Serializable
data class SpeechListenAudio(
    val version: Int,
    val gender: String,
    val url: String,
    val words: List<SpeechReference.Word>,
)

object SpeechListenService {
    /** Only challenges have one, and only in a language the reference is made for. */
    fun available(script: SpeechScript): Boolean =
        script.isChallenge && SpeechReading.applies(script.language)

    private val client by lazy {
        Edge.client.newBuilder().connectionPool(ConnectionPool())
            .readTimeout(120, TimeUnit.SECONDS).build()
    }

    private fun directory(context: Context): File =
        File(context.cacheDir, "speech_listen").apply { mkdirs() }

    private fun digest(script: SpeechScript): String =
        MessageDigest.getInstance("SHA-256").digest("${script.language}|${script.body}".toByteArray())
            .joinToString("") { "%02x".format(it) }.take(32)

    /** The reading's words and its audio on this phone (the cache: Android may
     *  clear it, and the next open fetches it again). Null when there is none. */
    suspend fun load(context: Context, script: SpeechScript): Pair<SpeechListenAudio, File>? = withContext(Dispatchers.IO) {
        if (!available(script)) return@withContext null
        val key = digest(script)
        val meta = File(directory(context), "$key.json")
        val file = File(directory(context), "$key.wav")
        var audio = readMeta(meta)
        if (audio == null) {
            audio = fetch(script)
            audio?.let { writeMeta(meta, it) }
        }
        val got = audio ?: return@withContext null
        if (!file.exists()) {
            val ok = runCatching {
                client.newCall(Request.Builder().url(got.url).build()).execute().use { response ->
                    if (response.code != 200) return@use false
                    val tmp = File(directory(context), "$key.part")
                    response.body?.byteStream()?.use { input -> tmp.outputStream().use { input.copyTo(it) } }
                    tmp.renameTo(file)
                }
            }.getOrDefault(false)
            if (!ok) return@withContext null
        }
        got to file
    }

    /** The fluent reading's words, with its sounds, for scoring: from the phone
     *  when it has them with sounds, else the server (which re-times an older
     *  reading to add them). No audio is downloaded. */
    suspend fun words(context: Context, script: SpeechScript): List<SpeechReference.Word>? =
        reading(context, script)?.words

    /** The reading itself (words, sounds and its voice's gender), without its
     *  audio: what a take is scored against (iOS 2026-11-13, founder: the one
     *  reading the learner hears is THE reference, karaoke-style). */
    suspend fun reading(context: Context, script: SpeechScript): SpeechListenAudio? = withContext(Dispatchers.IO) {
        if (!available(script)) return@withContext null
        val meta = File(directory(context), "${digest(script)}.json")
        readMeta(meta)?.takeIf { cached -> cached.words.any { it.ph != null } }?.let { return@withContext it }
        val fresh = fetch(script) ?: return@withContext null
        writeMeta(meta, fresh)
        fresh
    }

    private fun readMeta(file: File): SpeechListenAudio? =
        runCatching { Edge.json.decodeFromString(SpeechListenAudio.serializer(), file.readText()) }.getOrNull()

    private fun writeMeta(file: File, audio: SpeechListenAudio) {
        runCatching { file.writeText(Edge.json.encodeToString(SpeechListenAudio.serializer(), audio)) }
    }

    @Serializable
    private data class Body(val text: String, val language: String, val listen: Boolean = true, val challenge: String)

    private suspend fun fetch(script: SpeechScript): SpeechListenAudio? = runCatching {
        val token = AuthRepository().accessToken()
        val challenge = (script.challengeId ?: script.id).lowercase()
        val body = Edge.json.encodeToString(Body.serializer(),
            Body(script.body, script.language.take(2), true, challenge))
        val request = Request.Builder()
            .url(Config.functionUrl("speech-reference"))
            .header("Authorization", "Bearer $token")
            .header("X-Idempotency-Key", IdempotencyKey.headerSafe(UUID.randomUUID().toString().uppercase()))
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()
        client.newCall(request).execute().use { response ->
            if (response.code != 200) return@runCatching null
            val audio = Edge.json.decodeFromString(SpeechListenAudio.serializer(), response.body?.string().orEmpty())
            audio.takeIf { it.words.isNotEmpty() }
        }
    }.getOrNull()
}

/**
 * The script as the read-along draws it (iOS `SpeechListenText`): paragraphs
 * of the words as written (punctuation kept), each with when the fluent reader
 * said it and what follows it.
 */
class SpeechListenText(body: String, words: List<SpeechReference.Word>) {
    data class Token(
        val text: String,
        /** When the reader starts and ends it, in seconds. A word the timing
         *  missed takes the end of the word before it. */
        val start: Double,
        val end: Double,
        /** The reader takes a breath after it, where the script has no sentence end. */
        val breath: Boolean = false,
        /** It runs into the next word with no break. */
        val runsOn: Boolean = false,
    )

    /** A word as written in the script (whitespace to whitespace), with when it was said. */
    data class Display(val para: Int, val text: String, val time: Pair<Double, Double>?)

    val paragraphs: List<List<Token>>

    init {
        val paragraphTexts = ScriptStudy.paragraphs(body)
        val tokens = mutableListOf<Pair<Int, Token>>()
        var lastEnd = 0.0
        for (d in display(body, words)) {
            val start = d.time?.first ?: lastEnd
            val end = d.time?.second ?: start
            lastEnd = end
            tokens += d.para to Token(d.text, start, end)
        }
        for (i in 0 until max(0, tokens.size - 1)) {
            if (tokens[i].first != tokens[i + 1].first) continue
            val t = tokens[i].second
            val gap = tokens[i + 1].second.start - t.end
            val tail = t.text.trim { it in TRAIL }
            val endsSentence = tail.lastOrNull()?.let { it in ".!?…" } ?: false
            val endsClause = tail.lastOrNull()?.let { it in ",;:—–" } ?: false
            if (gap >= BREATH_SECONDS && !endsSentence) {
                tokens[i] = tokens[i].first to t.copy(breath = true)
            } else if (gap < RUN_ON_SECONDS && !endsSentence && !endsClause && links(t.text, tokens[i + 1].second.text)) {
                tokens[i] = tokens[i].first to t.copy(runsOn = true)
            }
        }
        val out = List(paragraphTexts.size) { mutableListOf<Token>() }
        for ((p, t) in tokens) out[p] += t
        paragraphs = out
    }

    val duration: Double get() = paragraphs.lastOrNull()?.lastOrNull()?.end ?: 0.0

    /** The end of the first sentence that finishes at or after [seconds]:
     *  where the challenge page's intro fades out. */
    fun sentenceEnd(after: Double): Double? {
        for (t in paragraphs.flatten()) {
            if (t.end < after) continue
            val tail = t.text.trim { it in TRAIL }
            val c = tail.lastOrNull()
            if (c != null && c in ".!?…") return t.end
        }
        return null
    }

    companion object {
        /** A stop this long or more is a breath (0.25 s: the calibration's own
         *  cut for a silence worth cutting at). */
        const val BREATH_SECONDS = 0.25
        /** Words this close are said as one (no measurable gap). */
        const val RUN_ON_SECONDS = 0.03
        internal const val TRAIL = "\"'”’)]»"

        private fun parts(text: String): List<String> =
            text.lowercase().replace("’", "'")
                .split(Regex("[^\\p{L}\\p{N}']+"))
                .map { it.trim('\'') }
                .filter { it.isNotEmpty() }

        /** Lines timed words (Azure's, in ms) up with the script's written words. */
        fun display(body: String, words: List<SpeechReference.Word>): List<Display> {
            val paragraphTexts = ScriptStudy.paragraphs(body)
            data class Written(val para: Int, val text: String, val parts: List<String>)
            val written = mutableListOf<Written>()
            paragraphTexts.forEachIndexed { p, para ->
                for (raw in para.split(Regex("\\s+")).filter { it.isNotEmpty() }) {
                    written += Written(p, raw, parts(raw))
                }
            }
            val flat = written.flatMap { it.parts }
            val said = words.map { SpeechDelivery.core(it.w) }
            val match = SpeechDelivery.align(said, flat)
            val times = arrayOfNulls<Pair<Double, Double>>(flat.size)
            match.forEachIndexed { i, m ->
                if (m != null) times[m] = words[i].s / 1000.0 to words[i].e / 1000.0
            }
            val out = mutableListOf<Display>()
            var cursor = 0
            for (w in written) {
                val timed = (cursor until cursor + w.parts.size).mapNotNull { times[it] }
                cursor += w.parts.size
                val first = timed.firstOrNull()
                val last = timed.lastOrNull()
                out += Display(w.para, w.text, if (first != null && last != null) first.first to last.second else null)
            }
            return out
        }

        /** Words a fluent reader joins: a word ending in a consonant sound
         *  carried into one that starts with a vowel ("come‿a", "room‿at").
         *  Spelling stands in for sound, so it is a rule of thumb. */
        fun links(word: String, next: String): Boolean {
            val a = SpeechDelivery.core(word)
            val b = SpeechDelivery.core(next)
            val last = a.lastOrNull() ?: return false
            val first = b.firstOrNull() ?: return false
            val vowels = setOf('a', 'e', 'i', 'o', 'u')
            if (first !in vowels) return false
            if (last !in vowels && last != 'y' && last != 'w') return true
            return last == 'e' && a.length >= 3 && a[a.length - 2] !in vowels
        }
    }
}

/** A mark on the result page, by the script's written word (iOS `SpeechPhraseMark`). */
data class SpeechPhraseMark(val word: Int, val kind: Kind, val seconds: Double) {
    enum class Kind { STOP, HELD }
}

/** Fix one phrase (iOS `SpeechPhrase`, 2026-11-13). */
object SpeechPhrase {
    /** The phrase around a mark: back to the last punctuation and forward to
     *  the next, at most four words either side. A stop's phrase always holds
     *  the word after the stop. */
    fun around(mark: SpeechPhraseMark, written: List<String>): IntRange {
        val n = written.size
        if (n == 0) return 0..0
        val i = min(max(0, mark.word), n - 1)
        var start = i
        while (start > 0 && i - start < 4 && !endsPhrase(written[start - 1])) start -= 1
        var end = if (mark.kind == SpeechPhraseMark.Kind.STOP) min(n - 1, i + 1) else i
        while (end < n - 1 && end - i < 4 && !endsPhrase(written[end])) end += 1
        return start..end
    }

    fun endsPhrase(word: String): Boolean {
        val tail = word.trim { it in SpeechListenText.TRAIL }
        return tail.lastOrNull()?.let { it in ".!?…,;:—–" } ?: false
    }

    /** The take's words timed against its own audio file, in ms: each assessed
     *  piece's words moved by where the piece began. Null on takes that didn't
     *  keep where their pieces began. */
    fun takeWords(take: com.roro.futurevoice.data.SpeechTake): List<SpeechReference.Word>? {
        val pieces = take.assessments ?: return null
        val starts = take.assessmentStartsMs ?: return null
        if (starts.size != pieces.size) return null
        val out = mutableListOf<SpeechReference.Word>()
        pieces.zip(starts).forEach { (piece, start) ->
            for (w in piece.words) {
                if (w.isOmission || w.isInsertion || w.durationMs <= 0) continue
                val s = start + w.offsetMs
                out += SpeechReference.Word(w.word, s, s + w.durationMs)
            }
        }
        return out.ifEmpty { null }
    }

    /** One try at the phrase against the fluent reading's timing of it. */
    data class Judgement(
        val missing: Int,
        /** Stops inside the phrase where the fluent reader runs on. */
        val stops: List<String>,
        /** Words held more than twice as long as the fluent reader holds them,
         *  once the reader's own pace is taken out. */
        val held: List<String>,
        /** How closely the long-and-short pattern follows the fluent one
         *  (Pearson r of log word lengths); null under four words. */
        val rhythm: Double?,
    ) {
        val matched: Boolean get() = missing == 0 && stops.isEmpty() && held.isEmpty() && (rhythm ?: 1.0) >= RHYTHM_BAR

        companion object {
            /** 0.8 for one phrase; natives ~0.93 over a whole reading. */
            const val RHYTHM_BAR = 0.8
        }
    }

    fun judge(said: List<SpeechListenText.Display>, fluent: List<SpeechListenText.Display>): Judgement {
        val n = min(said.size, fluent.size)
        val missing = said.take(n).count { it.time == null }
        val stops = mutableListOf<String>()
        for (k in 0 until max(0, n - 1)) {
            if (endsPhrase(said[k].text)) continue
            val a = said[k].time ?: continue
            val b = said[k + 1].time ?: continue
            val gap = b.first - a.second
            val fluentGap = (fluent[k + 1].time?.first ?: 0.0) - (fluent[k].time?.second ?: 0.0)
            if (gap >= SpeechReading.PAUSE_SECONDS && fluentGap < SpeechReading.PAUSE_SECONDS) stops += said[k].text
        }
        data class P(val text: String, val said: Double, val fluent: Double)
        val pairs = mutableListOf<P>()
        for (k in 0 until n) {
            val a = said[k].time ?: continue
            val b = fluent[k].time ?: continue
            pairs += P(said[k].text, max(0.02, a.second - a.first), max(0.02, b.second - b.first))
        }
        val rhythm = if (pairs.size >= 4) SpeechReading.pearson(pairs.map { ln(it.fluent) }, pairs.map { ln(it.said) }) else null
        val held = mutableListOf<String>()
        if (pairs.size >= 2) {
            val ratios = pairs.map { ln(it.said / it.fluent) }
            val tempo = ratios.sorted()[ratios.size / 2]
            pairs.zip(ratios).forEach { (p, r) ->
                if (exp(r - tempo) >= 2 && p.said - p.fluent >= 0.15) held += p.text
            }
        }
        return Judgement(missing, stops, held, rhythm)
    }
}
