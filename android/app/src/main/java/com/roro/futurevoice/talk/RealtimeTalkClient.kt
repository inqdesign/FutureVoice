package com.roro.futurevoice.talk

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.util.Log
import com.roro.futurevoice.audio.PcmStreamPlayer
import com.roro.futurevoice.core.Config
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Client for the realtime Talk gateway (`gateway/` in this repo — a
 * Cloudflare Worker + Durable Object). ONE WebSocket per call: mic PCM goes
 * up continuously, reply PCM comes down, and every turn decision — when the
 * learner stopped talking, when they spoke over the reply — is made
 * server-side. There is no client-side turn logic in this path at all.
 *
 * This is the ONLY call path (iOS `RealtimeMode`, 2026-09-05). The classic
 * per-turn HTTP machine still exists in [TalkViewModel]; its whole complexity
 * exists to shave a wait this path doesn't have.
 *
 * ## The one thing that makes this feel like a phone call
 *
 * The reply plays on the speaker while the mic is open. Without echo
 * cancellation the gateway hears the fluent self's own voice, calls it a
 * barge-in, and cuts the line mid-sentence. iOS gets this from VPIO on a
 * shared engine; here the mic is opened as `VOICE_COMMUNICATION`, which puts
 * the platform AEC in the capture path, and the hardware canceller is
 * attached on top when the device offers one. It is the same decision as
 * iOS made from the opposite side: the player deliberately stays on the
 * MEDIA stream so the OS headphone-safety cap still applies to it.
 *
 * ## Metering
 *
 * The gateway meters the call itself through `talk-tick` with the caller's
 * own JWT (`gateway/src/billing.ts`). Nothing here ticks. When a wall ends
 * the call the gateway says WHICH one, and [onWall] carries the code so the
 * view raises the same sheet the classic meter's 402 would have.
 */
class RealtimeTalkClient(private val context: Context) {

    companion object {
        private const val TAG = "RealtimeTalk"
        /** What the gateway expects on the way up: 16 kHz mono s16le. */
        const val MIC_RATE = 16_000
        /** What the gateway announces if it says nothing else. */
        private const val DEFAULT_REPLY_RATE = 22_050
        /** Mic frames per socket message — ~128 ms, the same size iOS taps. */
        private const val MIC_FRAMES = 2048
    }

    enum class State { IDLE, CONNECTING, LISTENING, HEARING, THINKING, SPEAKING, FAILED }

    // What the view model consumes. All callbacks land on the caller's
    // coroutine context via the dispatcher below; none touch UI directly.
    @Volatile var onState: ((State) -> Unit)? = null
    @Volatile var onPartial: ((String) -> Unit)? = null
    /** A committed learner turn: the audio-grounded text, the trimmed WAV
     *  (or null if nothing was captured), and its length in ms. */
    @Volatile var onUserTurn: ((text: String, wav: File?, ms: Int) -> Unit)? = null
    /** A reply began: [context] identifies it across deltas and audio. */
    @Volatile var onReplyBegan: ((context: String) -> Unit)? = null
    /** Reply text as it is written. A delta prefixed with NUL is the
     *  authoritative full text, sent when the reply closes. */
    @Volatile var onReplyDelta: ((context: String, delta: String) -> Unit)? = null
    /** The learner spoke over the reply; playback was cut. */
    @Volatile var onInterrupted: ((context: String) -> Unit)? = null
    /** The gateway ended the call on a wall — "insufficient_credits",
     *  "daily_cap_reached" or "fair_use_limit". */
    @Volatile var onWall: ((code: String) -> Unit)? = null
    @Volatile var onFailed: ((message: String) -> Unit)? = null

    /** 0…1 mic level for the waveform. */
    @Volatile var level: Float = 0f
        private set

    @Volatile var state: State = State.IDLE
        private set(value) { field = value; onState?.invoke(value) }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true }
    private val http = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)   // a call has no read deadline
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    private var socket: WebSocket? = null
    private var record: AudioRecord? = null
    private var canceller: AcousticEchoCanceler? = null
    private var micJob: Job? = null
    @Volatile private var micRunning = false
    @Volatile private var tornDown = false

    private var player: PcmStreamPlayer? = null
    private var replyRate = DEFAULT_REPLY_RATE
    private var replyContext: String? = null
    /** Audio for the reply in flight, kept so a Replay has the closing line
     *  even when End lands mid-playback and `audio_end` never arrives. */
    private val replyPCM = ByteArrayOutputStream()
    private val userPCM = ByteArrayOutputStream()

    /** Set when the gateway named a wall; read by the view after failure. */
    @Volatile var wallCode: String? = null
        private set

    // ------------------------------------------------------------------
    // Lifecycle

    /**
     * Open the call. [system] is the full conversation prompt; the gateway
     * passes it to Gemini Live verbatim. [opener] is spoken by the fluent
     * self before the learner says anything — spoken THERE rather than by the
     * app, because two audio engines fighting over one session is how a call
     * goes silent. [history] resumes a talk with what was already said.
     */
    fun connect(
        token: String,
        voiceId: String,
        language: String,
        system: String,
        opener: String?,
        history: List<Pair<String, String>>,
    ) {
        if (state != State.IDLE && state != State.FAILED) return
        tornDown = false
        wallCode = null
        replyPCM.reset(); userPCM.reset()
        state = State.CONNECTING

        val start = buildJsonObject {
            put("type", "start")
            put("token", token)
            put("voiceId", voiceId)
            put("language", language)
            put("system", system)
            opener?.takeIf { it.isNotBlank() }?.let { put("opener", it) }
            if (history.isNotEmpty()) {
                put("history", buildJsonArray {
                    history.forEach { (role, text) ->
                        add(buildJsonObject { put("role", role); put("text", text) })
                    }
                })
            }
        }

        val req = Request.Builder().url(Config.gatewayUrl).build()
        socket = http.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send(start.toString())
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handle(runCatching { json.parseToJsonElement(text) as JsonObject }.getOrNull() ?: return)
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                // Binary frames are reply PCM at the announced rate.
                val chunk = bytes.toByteArray()
                replyPCM.write(chunk)
                val p = player ?: return
                scope.launch { p.write(chunk) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (tornDown) return
                Log.w(TAG, "socket failed", t)
                fail(t.message ?: "connection failed")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (tornDown) return
                // A socket the gateway closed on its own, without an error
                // event first, is a dropped call — say so rather than leaving
                // a listening screen that hears nothing.
                if (state != State.FAILED) fail(reason.ifBlank { "call ended" })
            }
        })
    }

    /** Polite hang-up: the gateway closes upstream sessions, then the socket. */
    fun hangUp() {
        if (tornDown) return
        tornDown = true
        runCatching { socket?.send("""{"type":"end"}""") }
        teardown()
        state = State.IDLE
    }

    /** The audio of the reply still in flight — see [replyPCM]. */
    fun takeReplyAudio(): Pair<ByteArray, Int> {
        val bytes = replyPCM.toByteArray(); replyPCM.reset()
        return bytes to replyRate
    }

    private fun fail(message: String) {
        teardown()
        state = State.FAILED
        onFailed?.invoke(message)
    }

    private fun teardown() {
        stopMic()
        runCatching { player?.stop() }; player = null
        runCatching { socket?.close(1000, null) }; socket = null
    }

    // ------------------------------------------------------------------
    // Events

    private fun handle(msg: JsonObject) {
        val type = msg["type"]?.jsonPrimitive?.content ?: return
        when (type) {
            "ready" -> {
                // Auth + upstream sessions are up: open the mic and stream.
                startMic()
                state = State.LISTENING
            }
            "user_partial" -> {
                val text = msg["text"]?.jsonPrimitive?.content.orEmpty()
                onPartial?.invoke(text)
                if (state != State.SPEAKING) state = if (text.isEmpty()) State.LISTENING else State.HEARING
            }
            "user_turn" -> {
                val said = msg["text"]?.jsonPrimitive?.content.orEmpty()
                val pcm = userPCM.toByteArray(); userPCM.reset()
                if (said.isNotEmpty()) {
                    val trimmed = trimSilence(pcm, MIC_RATE)
                    val wav = saveWav(trimmed, MIC_RATE)
                    val ms = (trimmed.size / 2 * 1000L / MIC_RATE).toInt()
                    onUserTurn?.invoke(said, wav, ms)
                }
                onPartial?.invoke("")
                state = if (said.isEmpty()) State.LISTENING else State.THINKING
            }
            "audio_start" -> {
                val ctx = msg["context"]?.jsonPrimitive?.content
                replyContext = ctx
                replyRate = msg["sampleRate"]?.jsonPrimitive?.content?.toIntOrNull() ?: DEFAULT_REPLY_RATE
                replyPCM.reset()
                // The rate can change between replies; a player is bound to
                // one rate, so it is rebuilt when the announced one differs.
                val p = player?.takeIf { it.sampleRate == replyRate }
                    ?: PcmStreamPlayer(replyRate).also { player?.stop(); player = it }
                p.volume = com.roro.futurevoice.data.AudioPrefs.talkVoiceVolume(context)
                p.start()
                ctx?.let { onReplyBegan?.invoke(it) }
                state = State.SPEAKING
            }
            "reply_delta" -> {
                val ctx = replyContext ?: return
                onReplyDelta?.invoke(ctx, msg["text"]?.jsonPrimitive?.content.orEmpty())
            }
            "reply" -> {
                val ctx = replyContext ?: return
                msg["text"]?.jsonPrimitive?.content?.let { onReplyDelta?.invoke(ctx, " $it") }
            }
            "audio_end" -> {
                // Let the track drain what it holds, then hand the mic back.
                val p = player
                scope.launch {
                    runCatching { p?.drain() }
                    if (state == State.SPEAKING) state = State.LISTENING
                }
            }
            "interrupted" -> {
                // Stop local playback NOW and drop what was buffered.
                runCatching { player?.stop() }
                player = null
                replyContext?.let { onInterrupted?.invoke(it) }
                state = State.HEARING
            }
            "stats", "rotating" -> Unit   // the gateway reconnects upstream itself
            "error" -> {
                val code = msg["code"]?.jsonPrimitive?.content.orEmpty()
                val message = msg["message"]?.jsonPrimitive?.content ?: "gateway error"
                if (code == "insufficient_credits" || code == "daily_cap_reached" || code == "fair_use_limit") {
                    wallCode = code
                    onWall?.invoke(code)
                }
                fail(message)
            }
        }
    }

    // ------------------------------------------------------------------
    // Mic

    @SuppressLint("MissingPermission")   // RECORD_AUDIO is granted before a call opens
    private fun startMic() {
        if (micRunning) return
        val minBuf = AudioRecord.getMinBufferSize(MIC_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        // VOICE_COMMUNICATION puts the platform echo canceller and noise
        // suppressor in the capture path — the reply on the speaker must not
        // come back as a barge-in.
        val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, MIC_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, max(minBuf, MIC_FRAMES * 4))
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            fail("microphone unavailable"); return
        }
        if (AcousticEchoCanceler.isAvailable()) {
            canceller = runCatching { AcousticEchoCanceler.create(rec.audioSessionId)?.apply { enabled = true } }.getOrNull()
        }
        record = rec
        micRunning = true
        rec.startRecording()
        micJob = scope.launch {
            val buf = ShortArray(MIC_FRAMES)
            val bytes = ByteBuffer.allocate(MIC_FRAMES * 2).order(ByteOrder.LITTLE_ENDIAN)
            while (micRunning) {
                val n = rec.read(buf, 0, buf.size)
                if (n <= 0) continue
                var peak = 0f
                bytes.clear()
                for (i in 0 until n) {
                    val v = buf[i]
                    bytes.putShort(v)
                    val a = abs(v.toInt()) / 32768f
                    if (a > peak) peak = a
                }
                level = peak
                val frame = bytes.array().copyOf(n * 2)
                userPCM.write(frame)
                // Continuous, paced by the read itself — roughly realtime,
                // which is what Gemini Live's own VAD wants.
                socket?.send(frame.toByteString())
            }
        }
    }

    private fun stopMic() {
        micRunning = false
        micJob?.cancel(); micJob = null
        runCatching { canceller?.release() }; canceller = null
        record?.let { r ->
            runCatching { r.stop() }
            runCatching { r.release() }
        }
        record = null
        level = 0f
    }

    // ------------------------------------------------------------------
    // Turn audio

    /**
     * Cut the silence off both ends of a captured turn, keeping a little
     * lead-in. Same shape as iOS: 20 ms windows against the take's own peak,
     * so a quiet room and a loud one trim the same way.
     */
    private fun trimSilence(pcm: ByteArray, rate: Int): ByteArray {
        val samples = pcm.size / 2
        if (samples == 0) return pcm
        val window = max(1, rate / 50)          // 20 ms
        val lead = (rate * 0.35).toInt()
        val sb = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        var peak = 0f
        val energies = ArrayList<Float>()
        var i = 0
        while (i < samples) {
            val end = min(i + window, samples)
            var sum = 0f
            for (k in i until end) sum += abs(sb.get(k).toInt()) / 32768f
            val e = sum / (end - i)
            energies.add(e); if (e > peak) peak = e
            i += window
        }
        if (peak <= 0f) return pcm
        val gate = peak * 0.08f
        val first = energies.indexOfFirst { it >= gate }
        val last = energies.indexOfLast { it >= gate }
        if (first < 0 || last < 0) return pcm
        val startS = max(0, first * window - lead)
        val endS = min(samples, (last + 1) * window + lead)
        return pcm.copyOfRange(startS * 2, endS * 2)
    }

    /** A temp WAV the view model moves into its own store — one copy. */
    private fun saveWav(pcm: ByteArray, rate: Int): File? = runCatching {
        val f = File.createTempFile("turn-", ".wav", context.cacheDir)
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray()).putInt(36 + pcm.size).put("WAVE".toByteArray())
            .put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
            .putInt(rate).putInt(rate * 2).putShort(2).putShort(16)
            .put("data".toByteArray()).putInt(pcm.size)
        f.outputStream().use { it.write(header.array()); it.write(pcm) }
        f
    }.getOrNull()

    fun close() {
        hangUp()
        scope.cancel()
    }
}
