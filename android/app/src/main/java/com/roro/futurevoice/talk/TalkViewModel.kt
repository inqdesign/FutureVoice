package com.roro.futurevoice.talk

import android.content.Context
import android.util.Log
import com.roro.futurevoice.BuildConfig
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.roro.futurevoice.audio.LiveTranscriber
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.PcmStreamPlayer
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.ProfileStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

data class TalkConfig(
    val voiceId: String,
    val targetLanguage: String = "en",
    val nativeLanguage: String = "ko",
    val level: CefrLevel = CefrLevel.B1,
    val topic: String = "",
    val persona: UserPersona? = null,
    /** Pool-grounded facts for a news talk — the model's only ground truth. */
    val newsFacts: List<String> = emptyList(),
    /** Set when launched from a saved scenario — the session's provenance. */
    val scenarioId: String? = null,
)

/**
 * [PAUSED] is the call put DOWN, not away: the mic is closed and nothing
 * bills, but the transcript stays and [TalkViewModel.resume] picks the same
 * session up. Only [ENDED] has consequences (a summary, a book).
 */
enum class TalkPhase { IDLE, CONNECTING, LISTENING, THINKING, SPEAKING, PAUSED, ENDED }

/**
 * Which wall ended the call. A FREE account's spent pool leads to the
 * paywall; a SUBSCRIBER's spent allowance never does — they already paid,
 * the pool refills on its own. Neither is an error, so neither lands in
 * [TalkUiState.error].
 */
enum class TalkWall { OUT_OF_MINUTES, ALLOWANCE_SPENT }

data class TalkUiState(
    val phase: TalkPhase = TalkPhase.IDLE,
    val turns: List<Turn> = emptyList(),
    val partial: String = "",
    val level: Float = 0f,
    val error: String? = null,
    val wall: TalkWall? = null,
    /** Null until the first tick lands, and null throughout on a plan that doesn't count down. */
    val minutesRemaining: Int? = null,
    /**
     * True when the idle watchdog was what paused the call — the only
     * difference it makes is the hint, so a learner coming back to a quiet
     * screen reads "paused" instead of wondering what broke.
     */
    val pausedForIdle: Boolean = false,
    /** Set when the call ended with something said — the wrap-up's subject. */
    val endedSessionId: String? = null,
    val lastTiming: Map<String, String> = emptyMap(),
)

/**
 * The Talk vertical slice: live STT → structured Gemini turn → cloned-voice TTS
 * → auto VAD turn-taking. This is the make-or-break loop of the whole port
 * (`docs/android-plan.md` Phase C).
 */
class TalkViewModel(context: Context) : ViewModel() {

    private val appContext = context.applicationContext
    private val auth = AuthRepository()
    private val gemini = GeminiClient(auth)
    private val eleven = ElevenLabsClient(auth)
    private val live = LiveTranscriber(context)
    private val meter = TalkMeter(auth, viewModelScope, appContext)
    private val pcm = PcmStreamPlayer(ElevenLabsClient.STREAM_SAMPLE_RATE)
    private val mp3 = Mp3Player(appContext.cacheDir)
    private val sessions = SessionStore.shared(appContext)

    private val _state = MutableStateFlow(TalkUiState())
    val state: StateFlow<TalkUiState> = _state.asStateFlow()

    private var config: TalkConfig? = null
    private var sessionId: String = ""
    private var startedAt: Long = 0L
    private var systemPrompt: String = ""
    private var endpointJob: Job? = null
    private var callJob: Job? = null
    private var idleWatchJob: Job? = null

    /**
     * The last moment anything real happened. Deliberately OUTSIDE the watch
     * job: the job is re-armed every time the mic opens, and a clock living
     * inside it would be reset by every restart. Only real activity moves it.
     */
    private var lastActivityAt: Long = 0L

    private var lastTranscriptChangeAt: Long? = null
    private var didPreconnectThisTurn = false
    private var turnStartedAt: Long = 0L
    private var turnEndedSpeakingAt: Long = 0L
    private var turnTiming = mutableMapOf<String, String>()

    init {
        viewModelScope.launch {
            meter.minutesRemaining.collect { m -> _state.update { it.copy(minutesRemaining = m) } }
        }
    }

    // MARK: - Lifecycle

    fun start(config: TalkConfig) {
        if (_state.value.phase != TalkPhase.IDLE && _state.value.phase != TalkPhase.ENDED) return
        this.config = config
        _state.value = TalkUiState(phase = TalkPhase.CONNECTING)
        sessionId = StoreJson.newId()
        startedAt = System.currentTimeMillis()

        // Metering starts with the call, not with the first turn. Silence isn't
        // billed — see `isBillableMoment`; set before start(), the ticker polls
        // it from its first second.
        meter.isBillable = { isBillableMoment() }
        meter.onWallHit = { wall -> hitWall(wall) }
        meter.start(sessionId = sessionId, language = config.targetLanguage)
        lastActivityAt = System.currentTimeMillis()   // the call starts occupied
        startIdleWatch()

        callJob = viewModelScope.launch {
            try {
                // What past sessions taught rides into this one — the same
                // recurring patterns and weak areas iOS injects
                // (ConversationView.conversationSystemPrompt). Built here, not
                // in the caller: the profile read is a disk hop.
                val profile = ProfileStore.shared(appContext)
                    .load(config.targetLanguage, config.level.code)
                systemPrompt = ConversationEngine.conversationSystemPrompt(
                    targetLanguage = config.targetLanguage,
                    nativeLanguage = config.nativeLanguage,
                    level = config.level,
                    topPatterns = profile.recurringMistakes,
                    weakVocabAreas = profile.weakVocabAreas,
                    topic = config.topic,
                    persona = config.persona,
                    newsFacts = config.newsFacts,
                ) + ConversationEngine.turnOutputInstruction(config.targetLanguage)
                if (BuildConfig.DEBUG) Log.d(TAG, "prompt: patterns=${profile.recurringMistakes.size}" +
                    " weak=${profile.weakVocabAreas} first='${profile.recurringMistakes.firstOrNull()?.mistake}'")
                openConversation()
            } catch (e: Exception) {
                fail(e)
            }
        }
    }

    fun end() {
        if (_state.value.phase == TalkPhase.ENDED || _state.value.phase == TalkPhase.IDLE) return
        meter.stop()
        cancelIdleWatch()
        endpointJob?.cancel(); endpointJob = null
        callJob?.cancel(); callJob = null
        runCatching { live.stop() }
        pcm.stop()
        mp3.stop()
        _state.update { it.copy(phase = TalkPhase.ENDED, partial = "") }
        persist()
    }

    /**
     * Every way a call stops lands here once: End, a wall, a failure. Saved
     * as long as anything was said (iOS: `guard !turns.isEmpty`) — the
     * summary comes later and is written onto the same row.
     */
    private fun persist() {
        val cfg = config ?: return
        val turns = _state.value.turns
        if (turns.isEmpty()) return
        // Uppercased like every other id: iOS encodes a Swift UUID uppercase,
        // and a backup crossing platforms should not differ by case alone.
        val userId = auth.userId?.uppercase() ?: return
        val session = Session(
            id = sessionId,
            userId = userId,
            targetLanguage = cfg.targetLanguage,
            topic = cfg.topic.takeIf { it.isNotBlank() },
            startedAt = startedAt,
            endedAt = System.currentTimeMillis(),
            turns = turns,
            origin = when {
                cfg.scenarioId != null -> SessionOrigin.SCENARIO
                cfg.newsFacts.isNotEmpty() -> SessionOrigin.NEWS
                cfg.topic.isBlank() -> SessionOrigin.FREE
                else -> null
            },
            originScenarioId = cfg.scenarioId,
        )
        // Saved from the app scope on purpose: the ViewModel may be cleared
        // (screen left) before a viewModelScope job gets to run. The summary
        // follows on the same scope and writes onto the same row.
        _state.update { it.copy(endedSessionId = session.id) }
        CoroutineScope(Dispatchers.Main).launch {
            runCatching { sessions.save(session) }
            StoreEvents.bump()
            SessionSummarizer.summarizeInBackground(appContext, session, cfg.nativeLanguage, cfg.level)
        }
    }

    /** The one tap: put the call down, or pick it back up. */
    fun togglePause() {
        when (_state.value.phase) {
            TalkPhase.PAUSED -> resume()
            TalkPhase.LISTENING, TalkPhase.THINKING, TalkPhase.SPEAKING -> pauseCall(forIdle = false)
            else -> Unit
        }
    }

    /**
     * Put the call DOWN — not away. The mic closes and the meter goes quiet,
     * but the transcript stays and [resume] picks the same session up where
     * it stopped. Nothing is saved or summarized here; only [end] does that.
     * Every "stop" lands here: the tap and the idle watchdog.
     */
    private fun pauseCall(forIdle: Boolean) {
        cancelIdleWatch()
        endpointJob?.cancel(); endpointJob = null
        // Whatever the partial held is discarded, as on iOS — a half-sentence
        // from before a pause is not something to answer later.
        runCatching { live.stop() }
        pcm.stop()
        mp3.stop()
        _state.update { it.copy(phase = TalkPhase.PAUSED, partial = "", level = 0f, pausedForIdle = forIdle) }
    }

    fun resume() {
        if (_state.value.phase != TalkPhase.PAUSED) return
        lastActivityAt = System.currentTimeMillis()   // a tap is someone being here
        _state.update { it.copy(phase = TalkPhase.LISTENING, pausedForIdle = false) }
        beginListening()
        startIdleWatch()
    }

    // MARK: - Nobody's there

    /**
     * Watch for a call with nobody in it. Not a billing rule — idle seconds
     * already cost nothing. This is about the open mic: a call the learner
     * walked away from keeps listening, and the first voice it hears — a TV,
     * someone else in the room — would be billed AND answered as the learner.
     * The predicate is the one the meter bills on, so the call pauses on
     * exactly the silence it charges nothing for (`behavior.md` §8).
     */
    private fun startIdleWatch() {
        cancelIdleWatch()
        idleWatchJob = viewModelScope.launch {
            while (true) {
                delay(IDLE_WATCH_TICK_SECONDS * 1000L)
                val phase = _state.value.phase
                if (phase == TalkPhase.ENDED || phase == TalkPhase.PAUSED) return@launch
                if (isBillableMoment()) { lastActivityAt = System.currentTimeMillis(); continue }
                if (System.currentTimeMillis() - lastActivityAt < IDLE_PAUSE_SECONDS * 1000L) continue
                pauseCall(forIdle = true)
                return@launch
            }
        }
    }

    private fun cancelIdleWatch() {
        idleWatchJob?.cancel(); idleWatchJob = null
    }

    override fun onCleared() {
        end()
        super.onCleared()
    }

    // MARK: - Call flow

    /**
     * The fluent self speaks first. The opener is GENERATED rather than canned
     * so it lands in the right language and in-scene for a scenario topic —
     * iOS pre-synthesizes its greeting in the launcher for latency, which is
     * the obvious next optimization here.
     */
    private suspend fun openConversation() {
        val cfg = config ?: return
        val opener = requestTurn(
            messages = listOf(
                GeminiClient.Message(
                    GeminiClient.Message.Role.USER,
                    "(the call just connected — say your opening line, nothing else)",
                )
            ),
            idempotencyKey = "open:${UUID.randomUUID()}",
            speakEagerly = true,
        )
        appendFluentSelf(opener.reply)
        beginListening()
    }

    private fun beginListening() {
        val cfg = config ?: return
        val phase = _state.value.phase
        if (phase == TalkPhase.PAUSED || phase == TalkPhase.ENDED) return
        didPreconnectThisTurn = false
        lastTranscriptChangeAt = null
        turnStartedAt = System.currentTimeMillis()
        _state.update { it.copy(phase = TalkPhase.LISTENING, partial = "") }
        try {
            live.start(LanguageCatalog.sttLocale(cfg.targetLanguage)) { text ->
                lastTranscriptChangeAt = System.currentTimeMillis()
                _state.update { it.copy(partial = text, level = live.level) }
            }
        } catch (e: Exception) {
            fail(e)
            return
        }
        endpointJob?.cancel()
        endpointJob = viewModelScope.launch { endpointMonitor() }
    }

    /**
     * Energy-based endpointing. Every tick: how long has the mic ACTUALLY been
     * silent (last voiced audio, not last transcript change) against the
     * text-completeness tier. See `docs/contracts/behavior.md` §2.
     */
    private suspend fun endpointMonitor() {
        while (_state.value.phase == TalkPhase.LISTENING) {
            delay((TurnTaking.ENDPOINT_TICK_SECONDS * 1000).toLong())
            if (_state.value.phase != TalkPhase.LISTENING) return

            val transcript = live.transcript
            // Never send an empty turn.
            if (transcript.isBlank()) continue
            val lastVoiced = live.lastVoicedAtMs ?: continue

            val now = System.currentTimeMillis()
            val audioSilence = (now - lastVoiced) / 1000.0
            val sinceTextChange =
                lastTranscriptChangeAt?.let { (now - it) / 1000.0 } ?: Double.MAX_VALUE

            // The user has plausibly finished — spend the rest of the VAD wait
            // warming the network path so the turn fires onto a hot connection.
            if (audioSilence >= TurnTaking.PRECONNECT_AFTER_SILENCE_SECONDS && !didPreconnectThisTurn) {
                didPreconnectThisTurn = true
                viewModelScope.launch { gemini.preconnect() }
            }

            val audioSettled = audioSilence >= TurnTaking.vadWaitSeconds(transcript) &&
                sinceTextChange >= TurnTaking.STT_SETTLE_SECONDS
            val transcriptSettled = sinceTextChange >= TurnTaking.NOISY_ROOM_FALLBACK_SECONDS
            if (!audioSettled && !transcriptSettled) continue

            // `vad_wait_ms` alone hides the worst case: on the noisy fallback the
            // energy meter never saw silence, so it logs a TINY audio gap for a
            // turn that actually sat out the 6s transcript wait.
            turnTiming = mutableMapOf(
                "vad_wait_ms" to (audioSilence * 1000).toInt().toString(),
                "vad_path" to if (audioSettled) "audio" else "noisy",
                "text_quiet_ms" to (minOf(sinceTextChange, 60.0) * 1000).toInt().toString(),
                "noise" to "%.2f".format(live.ambientNoiseLevel),
            )
            turnEndedSpeakingAt = now
            // Hand the turn to its own job: the monitor is done, and a pause
            // cancelling it must not take the in-flight reply down with it.
            callJob = viewModelScope.launch { sendTurn() }
            return
        }
    }

    private suspend fun sendTurn() {
        _state.update { it.copy(phase = TalkPhase.THINKING) }

        val finalizeStart = System.currentTimeMillis()
        val spoken = live.stop().trim()
        val fluency = live.fluencyStats()
        turnTiming["finalize_ms"] = (System.currentTimeMillis() - finalizeStart).toString()

        if (spoken.isBlank()) {
            beginListening()
            return
        }

        val userTurn = Turn(
            role = TurnRole.USER,
            transcript = spoken,
            durationMs = (System.currentTimeMillis() - turnStartedAt).toInt(),
            fluency = fluency,
        )
        _state.update { it.copy(turns = it.turns + userTurn, partial = "") }

        try {
            val payload = requestTurn(
                messages = ConversationEngine.geminiMessages(_state.value.turns),
                idempotencyKey = "turn:${userTurn.id}",
                speakEagerly = true,
            )
            attachSuggestion(userTurn.id, payload)
            appendFluentSelf(payload.reply)
            beginListening()
        } catch (e: Exception) {
            fail(e)
        }
    }

    /**
     * One structured turn. Streams first so TTS can fire on `reply`'s closing
     * quote; on a stream failure BEFORE that field, retries buffered on the SAME
     * idempotency key — one logical request, one charge.
     */
    private suspend fun requestTurn(
        messages: List<GeminiClient.Message>,
        idempotencyKey: String,
        speakEagerly: Boolean,
    ): ConversationTurnPayload {
        val geminiStart = System.currentTimeMillis()
        var speakJob: Job? = null

        val payload = try {
            gemini.sendJsonStream(
                system = systemPrompt,
                messages = messages,
                serializer = ConversationTurnPayload.serializer(),
                purpose = "turn",
                idempotencyKey = idempotencyKey,
                earlyField = "reply",
                onEarlyField = { reply ->
                    if (speakEagerly && reply.isNotBlank()) {
                        turnTiming["gemini_ms"] =
                            (System.currentTimeMillis() - geminiStart).toString()
                        // Launched, not awaited: blocking here would stall the SSE
                        // read that is still delivering the suggestion + transcript.
                        speakJob = viewModelScope.launch { speak(reply) }
                    }
                },
                fallbackFromEarly = { reply -> ConversationTurnPayload(reply = reply) },
            )
        } catch (e: EdgeError.InsufficientCredits) {
            throw e
        } catch (e: EdgeError.DailyCapReached) {
            throw e
        } catch (e: Exception) {
            gemini.sendJson(
                system = systemPrompt,
                messages = messages,
                serializer = ConversationTurnPayload.serializer(),
                purpose = "turn",
                idempotencyKey = idempotencyKey,
            )
        }

        if (speakJob == null && speakEagerly && payload.reply.isNotBlank()) {
            speak(payload.reply)
        } else {
            speakJob?.join()
        }
        turnTiming["total_ms"] =
            (System.currentTimeMillis() - turnEndedSpeakingAt).toString()
        _state.update { it.copy(lastTiming = turnTiming.toMap()) }
        return payload
    }

    private suspend fun speak(text: String) {
        val cfg = config ?: return
        val phase = _state.value.phase
        if (phase == TalkPhase.PAUSED || phase == TalkPhase.ENDED) return
        _state.update { it.copy(phase = TalkPhase.SPEAKING) }
        val firstChunkAt = longArrayOf(0L)
        val startedAt = System.currentTimeMillis()
        try {
            pcm.start()
            val result = eleven.synthesizeStreaming(
                voiceId = cfg.voiceId,
                text = text,
                // Turbo, never flash: same price, better speaker similarity, and
                // this is the surface where the clone is heard most.
                modelId = ElevenLabsClient.CONVERSATION_MODEL_ID,
                purpose = "turn",
            ) { chunk ->
                if (firstChunkAt[0] == 0L) {
                    firstChunkAt[0] = System.currentTimeMillis()
                    turnTiming["tts_first_ms"] = (firstChunkAt[0] - startedAt).toString()
                }
                pcm.write(chunk)
            }
            when (result) {
                is ElevenLabsClient.StreamedAudio.Pcm22050 -> {
                    turnTiming["tts"] = "stream"
                    pcm.drain()
                    pcm.stop()
                }
                is ElevenLabsClient.StreamedAudio.Mp3 -> {
                    turnTiming["tts"] = "buffered"
                    pcm.stop()
                    mp3.play(result.data)
                }
            }
        } catch (e: Exception) {
            pcm.stop()
            // A failed synthesis must not kill the call — the user still has the
            // text of the turn; the conversation keeps going.
            _state.update { it.copy(error = humanMessage(e)) }
        }
    }

    // MARK: - State helpers

    private fun appendFluentSelf(reply: String) {
        if (reply.isBlank()) return
        _state.update {
            it.copy(turns = it.turns + Turn(role = TurnRole.FLUENT_SELF, transcript = reply))
        }
    }

    /** The suggestion belongs to the USER turn it corrects, not to the reply. */
    private fun attachSuggestion(userTurnId: String, payload: ConversationTurnPayload) {
        val suggestion = payload.turnSuggestion()
        val upgraded = payload.transcript?.takeIf { it.isNotBlank() }
        if (suggestion == null && upgraded == null) return
        _state.update { state ->
            state.copy(turns = state.turns.map { turn ->
                if (turn.id != userTurnId) turn
                else turn.copy(
                    suggestion = suggestion ?: turn.suggestion,
                    transcript = upgraded ?: turn.transcript,
                )
            })
        }
    }

    private fun fail(e: Exception) {
        if (e is CancellationException) return   // end() cancelling a job is not a failure
        // A 402 from a turn is the same wall the meter reports, and it is not
        // an error — route it to the same place.
        if (e is EdgeError.InsufficientCredits || e is EdgeError.DailyCapReached) {
            hitWall(e); return
        }
        meter.stop()
        cancelIdleWatch()
        endpointJob?.cancel()
        runCatching { live.stop() }
        pcm.stop()
        _state.update { it.copy(phase = TalkPhase.ENDED, error = humanMessage(e)) }
        persist()
    }

    // MARK: - Metering

    /**
     * Is this second part of the conversation? The fluent self thinking or
     * speaking counts; otherwise only a learner demonstrably talking into the
     * mic does. Silence — a phone put down, a room's babble — bills nothing.
     */
    private fun isBillableMoment(): Boolean {
        val phase = _state.value.phase
        if (phase == TalkPhase.PAUSED || phase == TalkPhase.ENDED) return false
        val billable = phase == TalkPhase.THINKING || phase == TalkPhase.SPEAKING ||
            pcm.isPlaying || mp3.isPlaying || someoneIsTalkingHere()
        if (BuildConfig.DEBUG) {
            val now = System.currentTimeMillis()
            Log.d(TAG, "billable=$billable phase=$phase pcm=${pcm.isPlaying} mp3=${mp3.isPlaying} " +
                "voicedAgo=${live.lastVoicedAtMs?.let { now - it }} heardAgo=${lastTranscriptChangeAt?.let { now - it }} " +
                "voicedSec=${"%.1f".format(live.fluencyStats().speakingSeconds)} level=${"%.2f".format(live.level)}")
        }
        return billable
    }

    /**
     * Three witnesses, all required: recent voiced energy, the recognizer
     * still making words of it, and enough voiced time this turn to be a
     * person rather than a clatter. Energy alone is permanently true in a
     * café, which is why one witness isn't enough (iOS, 2026-08-18).
     */
    private fun someoneIsTalkingHere(): Boolean {
        val now = System.currentTimeMillis()
        val graceMs = TalkMeter.VOICE_GRACE_SECONDS * 1000
        val voiced = live.lastVoicedAtMs ?: return false
        if (now - voiced >= graceMs) return false
        val heard = lastTranscriptChangeAt ?: return false
        if (now - heard >= graceMs) return false
        return live.fluencyStats().speakingSeconds >= MIN_VOICED_SECONDS_PER_TURN
    }

    /**
     * The server said the talking is over. The call ends gracefully: the
     * transcript stays, nothing is billed past this point, and the screen says
     * WHICH wall it was so a subscriber is never shown a paywall.
     */
    private fun hitWall(wall: EdgeError) {
        meter.stop()
        cancelIdleWatch()
        endpointJob?.cancel()
        runCatching { live.stop() }
        pcm.stop()
        mp3.stop()
        val kind = if (wall is EdgeError.DailyCapReached) TalkWall.ALLOWANCE_SPENT
                   else TalkWall.OUT_OF_MINUTES
        _state.update { it.copy(phase = TalkPhase.ENDED, partial = "", wall = kind) }
        persist()
    }

    private fun humanMessage(e: Exception): String = when (e) {
        is EdgeError.Http -> "Server error ${e.status}"
        else -> e.message ?: e::class.java.simpleName
    }

    companion object {
        private const val TAG = "TalkViewModel"
        /** Voiced seconds this turn before a segment counts as a person talking. */
        private const val MIN_VOICED_SECONDS_PER_TURN = 1.5

        /**
         * How long a call may hear nothing at all before it puts itself down.
         * 30 s of nothing — no close-mic voice, no reply in flight, no line
         * being spoken — is already a long silence in a conversation (iOS
         * started at three minutes, then one; both were a long time to sit
         * with an open mic). The floor is the learner who thinks a long while
         * and then speaks: the recovery is one tap on a screen that never
         * lost the conversation.
         */
        private const val IDLE_PAUSE_SECONDS = 30

        /** Coarse on purpose — the pause lands within a tick of the bar. */
        private const val IDLE_WATCH_TICK_SECONDS = 5
    }
}
