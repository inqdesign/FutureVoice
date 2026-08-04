package com.roro.futurevoice.talk

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.roro.futurevoice.audio.LiveTranscriber
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.PcmStreamPlayer
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.GeminiClient
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
)

enum class TalkPhase { IDLE, CONNECTING, LISTENING, THINKING, SPEAKING, ENDED }

data class TalkUiState(
    val phase: TalkPhase = TalkPhase.IDLE,
    val turns: List<Turn> = emptyList(),
    val partial: String = "",
    val level: Float = 0f,
    val error: String? = null,
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
    private val pcm = PcmStreamPlayer(ElevenLabsClient.STREAM_SAMPLE_RATE)
    private val mp3 = Mp3Player(appContext.cacheDir)

    private val _state = MutableStateFlow(TalkUiState())
    val state: StateFlow<TalkUiState> = _state.asStateFlow()

    private var config: TalkConfig? = null
    private var systemPrompt: String = ""
    private var endpointJob: Job? = null
    private var callJob: Job? = null

    private var lastTranscriptChangeAt: Long? = null
    private var didPreconnectThisTurn = false
    private var turnStartedAt: Long = 0L
    private var turnEndedSpeakingAt: Long = 0L
    private var turnTiming = mutableMapOf<String, String>()

    // MARK: - Lifecycle

    fun start(config: TalkConfig) {
        if (_state.value.phase != TalkPhase.IDLE && _state.value.phase != TalkPhase.ENDED) return
        this.config = config
        this.systemPrompt = ConversationEngine.conversationSystemPrompt(
            targetLanguage = config.targetLanguage,
            nativeLanguage = config.nativeLanguage,
            level = config.level,
            topic = config.topic,
            persona = config.persona,
        ) + ConversationEngine.turnOutputInstruction(config.targetLanguage)

        _state.value = TalkUiState(phase = TalkPhase.CONNECTING)
        callJob = viewModelScope.launch {
            try {
                openConversation()
            } catch (e: Exception) {
                fail(e)
            }
        }
    }

    fun end() {
        endpointJob?.cancel(); endpointJob = null
        callJob?.cancel(); callJob = null
        runCatching { live.stop() }
        pcm.stop()
        mp3.stop()
        _state.update { it.copy(phase = TalkPhase.ENDED, partial = "") }
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
            sendTurn()
            return
        }
    }

    private suspend fun sendTurn() {
        endpointJob?.cancel()
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
                purpose = null,
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
        } catch (e: Exception) {
            gemini.sendJson(
                system = systemPrompt,
                messages = messages,
                serializer = ConversationTurnPayload.serializer(),
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
        endpointJob?.cancel()
        runCatching { live.stop() }
        pcm.stop()
        _state.update { it.copy(phase = TalkPhase.ENDED, error = humanMessage(e)) }
    }

    private fun humanMessage(e: Exception): String = when (e) {
        is EdgeError.InsufficientCredits -> e.message ?: "Out of credits"
        is EdgeError.Http -> "Server error ${e.status}"
        else -> e.message ?: e::class.java.simpleName
    }
}
