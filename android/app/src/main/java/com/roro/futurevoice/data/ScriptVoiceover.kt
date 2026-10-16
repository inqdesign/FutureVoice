package com.roro.futurevoice.data

import android.content.Context
import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaMuxer
import com.roro.futurevoice.audio.AacEncoder
import com.roro.futurevoice.audio.AudioDecode
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.core.Telemetry
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.VoiceClient
import com.roro.futurevoice.talk.PacedSpeech
import com.roro.futurevoice.talk.WordTiming
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * "Hear it in my voice" (iOS `ScriptVoiceover`, 3ebadf10, 2026-10-14): a
 * Speech script read whole in the learner's own cloned voice, which they can
 * then shadow from. There is deliberately NO native or preset voice option.
 *
 * PRICE — talk minutes, by the CHARACTERS the voice will say (iOS, 2026-10-16;
 * founder: "1분에 3분" was wrong). A talk minute carries ~300 characters of
 * fluent-self speech and a voiceover is sold at 3x that rate:
 *     minutes = ceil(characters / 100)
 * (an English one-minute script, ~800 characters → 8 min; Korean ~430 → 5).
 * The characters are known once the script is written, so the price on the
 * button is the price charged — the server charges
 *     min(price(characters), minutes shown)
 * (`charge_script_voiceover`, 20261016150000). Charged once per (account,
 * script text, voice); every replay after is free, and a failed synthesis is
 * never charged.
 *
 * Every place a price appears reads it from HERE, so two screens can never
 * quote two numbers.
 */
object ScriptVoiceover {
    /** Characters of fluent-self speech one talk minute carries, and the
     *  premium on it: 300 / 3 = one talk minute per 100 characters. Keep in
     *  step with `script_voiceover_char_price` (server) and iOS. */
    const val CHARACTERS_PER_TALK_MINUTE = 300
    const val MULTIPLIER = 3
    const val CHARACTERS_PER_MINUTE = CHARACTERS_PER_TALK_MINUTE / MULTIPLIER
    /** The longest voiceover sold: the server meters at most an hour of talk
     *  time per charge (6,000 characters). */
    const val MAX_MINUTES = 60
    const val PARAGRAPH_GAP_SECONDS = 0.8

    /** The characters a script is charged for: its text as synthesized. */
    fun chargeableCharacters(body: String): Int = body.trim().length

    /** Talk minutes for [characters] of voiceover, never less than one. */
    fun chargeMinutes(characters: Int): Int {
        if (characters <= 0) return 1
        return (characters + CHARACTERS_PER_MINUTE - 1) / CHARACTERS_PER_MINUTE
    }

    /** The price shown for a text — and charged. */
    @Suppress("UNUSED_PARAMETER")
    fun quoteMinutes(text: String, language: String): Int = chargeMinutes(chargeableCharacters(text))

    /** The price shown for a length not yet written (the composer): the
     *  characters a script of that length is written to. */
    fun quoteMinutes(targetSeconds: Int, language: String): Int {
        val units = SpeechLibrary.plannedUnits(targetSeconds, language)
        return chargeMinutes(Math.round(units * charactersPerUnit(language)).toInt())
    }

    /** Characters per rate unit, spaces and punctuation included — measured
     *  on the bundled scripts (en 5.6, ko 1.5, ja 1.1, de 6.0, es 5.5). */
    fun charactersPerUnit(language: String): Double = when (language.substringBefore('-').lowercase()) {
        "ko" -> 1.5
        "ja", "zh" -> 1.15
        "de" -> 6.0
        "fr", "es", "it", "pt" -> 5.5
        else -> 5.6
    }

    /** Talk minutes this account could put toward a voiceover now: the plan's
     *  pool plus invite minutes, or the balance with no plan. Null where
     *  nothing is counted (an uncapped plan) or the account isn't known. */
    fun remainingMinutes(account: AccountStatus?): Int? {
        account ?: return null
        if (account.unlimited || (account.isEntitled && account.monthlyCapSeconds == null)) return null
        val seconds = if (account.isEntitled) {
            maxOf(0, (account.monthlyCapSeconds ?: 0) - account.secondsUsedPeriod) + account.bonusSeconds
        } else maxOf(0, account.secondsBalance)
        return seconds / 60
    }

    // MARK: Keys

    /** The script's text, hashed — an edited script is a new voiceover and
     *  the old file stays where it is. */
    fun scriptHash(body: String) = sha(body.trim())

    /** The key the server charges once per account: "sv1:" + 32 hex of
     *  (script hash, voice). Speed is deliberately NOT in it. The same string
     *  iOS sends, so a voiceover is one purchase across the learner's phones. */
    fun chargeKey(scriptHash: String, voiceId: String) = "sv1:" + sha("$scriptHash|$voiceId").take(32)

    /** The file on disk: one per (script, voice, speed). */
    fun fileKey(scriptHash: String, voiceId: String, speedTag: String) =
        sha("voiceover|$scriptHash|$voiceId|$speedTag")

    fun sha(s: String): String =
        MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    // MARK: Lines

    /** What is synthesized, one request each, in order: every sentence of
     *  every paragraph ([PacedSpeech] — a whole paragraph comes back with
     *  almost no breath between sentences), or every paragraph whole for a
     *  Cartesia voice, which already breathes. */
    data class Line(val text: String, val endsParagraph: Boolean)

    fun lines(body: String, wholeParagraphs: Boolean): List<Line> {
        val out = mutableListOf<Line>()
        for (para in ScriptStudy.paragraphs(body)) {
            val parts = if (wholeParagraphs) listOf(para) else PacedSpeech.sentences(para)
            parts.forEachIndexed { i, p -> out.add(Line(p, i == parts.size - 1)) }
        }
        return out
    }

    /** A stable turn id per voiceover file, so its shadow takes are listed
     *  together every time it is opened — iOS's UUID built from the file
     *  name's hash, byte for byte. */
    fun shadowTurnId(fileName: String): String {
        val hex = sha(fileName)
        return ("${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}" +
            "-8${hex.substring(17, 20)}-${hex.substring(20, 32)}").uppercase()
    }
}

/** `files/ScriptVoiceover/<fileKey>.m4a` + `<fileKey>.json`. Never deleted
 *  (produced audio is the learner's): an edited script or a new voice is a new
 *  file beside the old one. */
object ScriptVoiceoverStore {
    @Serializable
    data class Meta(
        val scriptHash: String,
        val voiceId: String,
        val speedTag: String,
        val seconds: Double,
        val timings: List<WordTiming>,
        val chargeKey: String,
        /** Charged and confirmed. False = made, the charge didn't go through
         *  yet; the next tap charges it without making it again. */
        val paid: Boolean,
        val quotedMinutes: Int,
        val createdAt: Long,
    )

    data class Stored(val file: File, val meta: Meta)

    fun dir(context: Context) = File(context.filesDir, "ScriptVoiceover").apply { mkdirs() }
    fun audioFile(context: Context, key: String) = File(dir(context), "$key.m4a")
    private fun metaFile(context: Context, key: String) = File(dir(context), "$key.json")

    private fun allMetas(context: Context): List<Pair<String, Meta>> =
        dir(context).listFiles { f -> f.extension == "json" }.orEmpty().mapNotNull { f ->
            val meta = runCatching { StoreJson.json.decodeFromString(Meta.serializer(), f.readText()) }.getOrNull()
                ?: return@mapNotNull null
            val key = f.nameWithoutExtension
            if (!audioFile(context, key).exists()) null else key to meta
        }

    /** The voiceover to play: the current voice at the current speed first,
     *  then any speed, then the learner's earlier clones — cache first. */
    fun find(context: Context, scriptHash: String, voiceId: String, paid: Boolean = true): Stored? {
        val metas = allMetas(context).filter { it.second.scriptHash == scriptHash && it.second.paid == paid }
        if (metas.isEmpty()) return null
        val voices = listOf(voiceId) + PhraseAudioStore.shared(context).ownVoiceLineage.filter { it != voiceId }
        val tag = SpeechSpeed.currentCacheTag()
        for (v in if (paid) voices else listOf(voiceId)) {
            val mine = metas.filter { it.second.voiceId == v }
            val hit = mine.firstOrNull { it.second.speedTag == tag } ?: mine.maxByOrNull { it.second.createdAt }
            if (hit != null) return Stored(audioFile(context, hit.first), hit.second)
        }
        return null
    }

    fun save(context: Context, audio: File, meta: Meta): Stored {
        val key = ScriptVoiceover.fileKey(meta.scriptHash, meta.voiceId, meta.speedTag)
        val dest = audioFile(context, key)
        if (dest.exists()) dest.delete()
        if (!audio.renameTo(dest)) { audio.copyTo(dest, overwrite = true); audio.delete() }
        writeMeta(context, key, meta)
        return Stored(dest, meta)
    }

    fun markPaid(context: Context, stored: Stored): Stored {
        val meta = stored.meta.copy(paid = true)
        writeMeta(context, ScriptVoiceover.fileKey(meta.scriptHash, meta.voiceId, meta.speedTag), meta)
        return Stored(stored.file, meta)
    }

    private fun writeMeta(context: Context, key: String, meta: Meta) {
        val f = metaFile(context, key)
        val tmp = File(f.path + ".tmp")
        tmp.writeText(StoreJson.json.encodeToString(Meta.serializer(), meta))
        if (!tmp.renameTo(f)) { f.writeText(tmp.readText()); tmp.delete() }
    }
}

/** Making one (iOS `ScriptVoiceoverCenter`). A job outlives the sheet that
 *  started it — the composer starts one and closes. */
object ScriptVoiceoverCenter {
    sealed class Job {
        data class Making(val done: Int, val total: Int) : Job()
        data class Failed(val message: String) : Job()
    }

    /** By charge key. */
    private val _jobs = MutableStateFlow<Map<String, Job>>(emptyMap())
    val jobs: StateFlow<Map<String, Job>> = _jobs
    /** Bumped whenever a voiceover lands, so open sheets look again. */
    private val _revision = MutableStateFlow(0)
    val revision: StateFlow<Int> = _revision

    /** Jobs started by a sheet that closes right after (the composer, the
     *  own-script editor) run here; the Script sheet shows their progress. */
    private val background = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.SupervisorJob() + Dispatchers.Main)

    fun makeInBackground(context: Context, script: SpeechScript, voiceId: String, quotedMinutes: Int) {
        val app = context.applicationContext
        background.launch { runCatching { make(app, script, voiceId, quotedMinutes) } }
    }

    class VoiceoverFailed : Exception("voiceover failed")
    class TooLong : Exception("too long")
    class AlreadyMaking : Exception("already making")

    private fun setJob(key: String, job: Job?) {
        _jobs.value = if (job == null) _jobs.value - key else _jobs.value + (key to job)
    }

    fun keyFor(script: SpeechScript, voiceId: String) =
        ScriptVoiceover.chargeKey(ScriptVoiceover.scriptHash(script.body), voiceId)

    fun job(script: SpeechScript, voiceId: String): Job? = _jobs.value[keyFor(script, voiceId)]

    fun existing(context: Context, script: SpeechScript, voiceId: String): ScriptVoiceoverStore.Stored? =
        ScriptVoiceoverStore.find(context, ScriptVoiceover.scriptHash(script.body), voiceId)

    fun clearFailure(script: SpeechScript, voiceId: String) {
        val key = keyFor(script, voiceId)
        if (_jobs.value[key] is Job.Failed) setJob(key, null)
    }

    /** Could this account pay [minutes] right now? Null = yes, else the wall.
     *  A failure to ask is a yes — the reservation asks again first. */
    suspend fun wall(minutes: Int): EdgeError? {
        val result = runCatching {
            rpc("script_voiceover_can_pay", buildJsonObject { put("p_quoted_seconds", minutes * 60) })
        }.getOrNull() ?: return null
        val error = result["error"]?.jsonPrimitive?.content ?: return null
        return EdgeError.wall(error)
    }

    /**
     * Make (or finish paying for) the voiceover. Throws an [EdgeError] wall
     * when the account can't pay — before anything is synthesized.
     */
    suspend fun make(context: Context, script: SpeechScript, voiceId: String,
                     quotedMinutes: Int): ScriptVoiceoverStore.Stored {
        val app = context.applicationContext
        val hash = ScriptVoiceover.scriptHash(script.body)
        withContext(Dispatchers.IO) { ScriptVoiceoverStore.find(app, hash, voiceId) }?.let { return it }
        if (quotedMinutes > ScriptVoiceover.MAX_MINUTES) throw TooLong()
        val key = ScriptVoiceover.chargeKey(hash, voiceId)
        if (_jobs.value[key] is Job.Making) throw AlreadyMaking()

        // Made before, not paid for yet: charge only.
        withContext(Dispatchers.IO) { ScriptVoiceoverStore.find(app, hash, voiceId, paid = false) }?.let { pending ->
            charge(key, pending.meta.seconds)
            val paid = withContext(Dispatchers.IO) { ScriptVoiceoverStore.markPaid(app, pending) }
            _revision.value += 1
            return paid
        }

        val lines = ScriptVoiceover.lines(script.body, wholeParagraphs = com.roro.futurevoice.net.VoiceClient.isCartesiaVoice(voiceId))
        if (lines.isEmpty()) throw VoiceoverFailed()
        setJob(key, Job.Making(0, lines.size))
        try {
            reserve(key, quotedMinutes, ScriptVoiceover.chargeableCharacters(script.body))
            val assembled = synthesize(app, lines, voiceId, script.language, key)
            val meta = ScriptVoiceoverStore.Meta(
                scriptHash = hash, voiceId = voiceId, speedTag = SpeechSpeed.currentCacheTag(),
                seconds = assembled.seconds, timings = assembled.timings, chargeKey = key,
                paid = false, quotedMinutes = quotedMinutes, createdAt = System.currentTimeMillis())
            val stored = withContext(Dispatchers.IO) { ScriptVoiceoverStore.save(app, assembled.file, meta) }
            charge(key, assembled.seconds)
            val paid = withContext(Dispatchers.IO) { ScriptVoiceoverStore.markPaid(app, stored) }
            setJob(key, null)
            _revision.value += 1
            BillingGate.invalidate()
            Analytics.capture("speech_voiceover_made", mapOf(
                "seconds" to assembled.seconds.toInt(), "quoted_min" to quotedMinutes,
                "charged_min" to minOf(ScriptVoiceover.quoteMinutes(script.body, script.language), quotedMinutes)))
            return paid
        } catch (e: Exception) {
            if (e is EdgeError && (e === EdgeError.InsufficientCredits || e === EdgeError.DailyCapReached ||
                    e === EdgeError.FairUseLimit)) {
                setJob(key, null)
                throw e
            }
            setJob(key, Job.Failed(app.getString(com.roro.futurevoice.R.string.couldn_t_make_it_in_your_voice_nothing_was_charged)))
            Telemetry.log("speech_voiceover_failed", mapOf("error" to e.toString().take(160)))
            throw e
        }
    }

    // MARK: Server

    private suspend fun rpc(name: String, params: JsonObject): JsonObject = withContext(Dispatchers.IO) {
        val auth = AuthRepository()
        val request = Request.Builder()
            .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/$name")
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .post(params.toString().toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            Edge.json.parseToJsonElement(raw) as? JsonObject ?: throw EdgeError.InvalidResponse
        }
    }

    private suspend fun reserve(key: String, minutes: Int, chars: Int) {
        check(rpc("reserve_script_voiceover", buildJsonObject {
            put("p_key", key); put("p_quoted_seconds", minutes * 60); put("p_chars", minOf(chars, 20000))
        }))
    }

    private suspend fun charge(key: String, seconds: Double) {
        check(rpc("charge_script_voiceover", buildJsonObject {
            put("p_key", key); put("p_audio_seconds", minOf(3600, ceil(seconds).toInt()))
        }))
    }

    private fun check(result: JsonObject) {
        val error = result["error"]?.jsonPrimitive?.content ?: return
        when (error) {
            "insufficient_credits", "daily_cap_reached", "fair_use_limit" -> throw EdgeError.wall(error)
            else -> throw VoiceoverFailed()
        }
    }

    // MARK: Synthesis

    private class Assembled(val file: File, val seconds: Double, val timings: List<WordTiming>)

    private suspend fun synthesize(context: Context, lines: List<ScriptVoiceover.Line>, voiceId: String,
                                   language: String, key: String): Assembled {
        val client = VoiceClient(AuthRepository())
        val gate = Semaphore(3)
        var done = 0
        val takes = coroutineScope {
            lines.mapIndexed { i, line ->
                async(Dispatchers.IO) {
                    gate.withPermit {
                        val (data, timings) = client.synthesizeVoiceoverLine(voiceId, line.text, language, key, i)
                        val pcm = AudioDecode.decode(data) ?: throw VoiceoverFailed()
                        synchronized(this@ScriptVoiceoverCenter) { done += 1 }
                        setJob(key, Job.Making(done, lines.size))
                        Triple(pcm.samples, pcm.sampleRate, timings)
                    }
                }
            }.awaitAll()
        }
        if (takes.size != lines.size || takes.map { it.second }.toSet().size != 1) throw VoiceoverFailed()
        val rate = takes[0].second
        val joined = ScriptVoiceoverAudio.join(takes.map { it.first to it.third }, rate.toDouble(),
            lines.map { it.endsParagraph })
        val tmp = File(context.cacheDir, "voiceover-${System.nanoTime()}.m4a")
        if (!withContext(Dispatchers.IO) { ScriptVoiceoverAudio.writeM4a(joined.first, rate, tmp) }) throw VoiceoverFailed()
        return Assembled(tmp, joined.first.size.toDouble() / rate, joined.second)
    }
}

/**
 * Trimming the takes' inner edges to the voice, laying them end to end with a
 * fixed breath between ([PacedSpeech]'s rule, a longer one between
 * paragraphs), and writing one AAC file (iOS `ScriptVoiceoverAudio`).
 */
object ScriptVoiceoverAudio {
    /** First and last sample of voice on a 10 ms RMS envelope, gated at 3% of
     *  the loudest block. */
    fun voicedSpan(s: ShortArray, rate: Double): Pair<Int, Int>? {
        val block = maxOf(1, (rate / 100).toInt())
        if (s.size < block) return null
        val rms = ArrayList<Float>(s.size / block)
        var i = 0
        while (i + block <= s.size) {
            var sum = 0f
            for (j in i until i + block) { val v = s[j] / 32768f; sum += v * v }
            rms.add(sqrt(sum / block))
            i += block
        }
        val loudest = rms.maxOrNull() ?: return null
        if (loudest <= 0f) return null
        val gate = loudest * 0.03f
        val first = rms.indexOfFirst { it > gate }
        val last = rms.indexOfLast { it > gate }
        if (first < 0 || last < 0) return null
        return first * block to minOf(s.size, (last + 1) * block)
    }

    /** Joins takes, each take's timings moved to where its audio now sits. */
    fun join(takes: List<Pair<ShortArray, List<WordTiming>>>, rate: Double,
             endsParagraph: List<Boolean>): Pair<ShortArray, List<WordTiming>> {
        val margin = (PacedSpeech.EDGE_MARGIN_SECONDS * rate).toInt()
        // (take index, from, to, silence before) — sized first, then copied
        // once: a three-minute script is millions of samples.
        val pieces = mutableListOf<IntArray>()
        var length = 0
        for ((i, take) in takes.withIndex()) {
            val s = take.first
            if (s.isEmpty()) continue
            val (on, off) = voicedSpan(s, rate) ?: (0 to s.size)
            val from = if (i == 0) 0 else maxOf(0, on - margin)
            val to = if (i == takes.size - 1) s.size else minOf(s.size, off + margin)
            if (to <= from) continue
            var silence = 0
            if (length > 0) {
                val gap = if (i > 0 && endsParagraph[i - 1]) ScriptVoiceover.PARAGRAPH_GAP_SECONDS
                else PacedSpeech.SENTENCE_GAP_SECONDS
                silence = maxOf(0, (gap * rate).toInt() - 2 * margin)
            }
            pieces.add(intArrayOf(i, from, to, silence))
            length += silence + (to - from)
        }
        val out = ShortArray(length)
        val timings = mutableListOf<WordTiming>()
        var at = 0
        for ((i, from, to, silence) in pieces) {
            at += silence
            val shiftMs = ((at - from).toDouble() / rate * 1000).roundToInt()
            takes[i].second.mapTo(timings) {
                WordTiming(it.word, maxOf(0, it.startMs + shiftMs), maxOf(0, it.endMs + shiftMs), it.isMeasured)
            }
            System.arraycopy(takes[i].first, from, out, at, to - from)
            at += to - from
        }
        return out to timings
    }

    /** One AAC track in an MP4 container, 96 kbps (iOS's bitrate). */
    fun writeM4a(samples: ShortArray, rate: Int, out: File): Boolean {
        var format: MediaFormat? = null
        val frames = ArrayList<Pair<ByteArray, MediaCodec.BufferInfo>>()
        val ok = AacEncoder.encode(samples, rate, 96_000, pollUs = 1_000, onFormat = { format = it }) { buf, info ->
            val bytes = ByteArray(info.size); buf.get(bytes)
            frames += bytes to MediaCodec.BufferInfo().apply { set(0, info.size, info.presentationTimeUs, info.flags) }
        }
        val f = format
        if (!ok || f == null || frames.isEmpty()) return false
        out.delete()
        val muxer = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        return try {
            val track = muxer.addTrack(f)
            muxer.start()
            for ((bytes, info) in frames) muxer.writeSampleData(track, ByteBuffer.wrap(bytes), info)
            muxer.stop()
            true
        } catch (_: Exception) {
            false
        } finally {
            runCatching { muxer.release() }
        }
    }
}
