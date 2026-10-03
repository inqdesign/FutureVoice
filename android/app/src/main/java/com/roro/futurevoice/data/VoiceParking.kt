package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * A voice nobody is paying for is PARKED (iOS `VoiceParking`, 2026-09-28):
 * the server deletes it from ElevenLabs after 7 days without a plan and
 * without the app being opened (`park-idle-voices`) and stamps `parked_at`
 * on its `voice_clones` row — which stays `is_active = true`, so an old build
 * that finds no active row doesn't re-record a free clone and take the slot
 * straight back.
 *
 * What the phone does about it, in three rules:
 * - **Nothing already made stops playing.** The id stays the app's voiceId:
 *   every cache lookup ([PhraseAudioStore], the voicemail, a scene line) is
 *   keyed by it, and null would hide audio on disk and walk the learner into
 *   onboarding.
 * - **Nothing new is synthesized.** [com.roro.futurevoice.net.ElevenLabsClient]
 *   refuses a parked id before the network with
 *   [com.roro.futurevoice.net.EdgeError.InsufficientCredits], the error every
 *   surface already answers with its paywall.
 * - **It comes back at the TAP** ([VoiceRevival], run from [BillingGate]):
 *   allowed to spend → rebuilt from the recording on the phone in front of
 *   the learner. This object only LEARNS the state.
 *
 * Prefs-backed and context-free so the TTS client (no context) can ask.
 */
object VoiceParking {
    private const val KEY = "futurevoice.parkedVoiceId"
    /** A parked voice dropped because the phone holds no recording: the
     *  server row is still active, so the restore must not bring it back. */
    private const val DROPPED_KEY = "futurevoice.parkedVoiceDropped"
    /** Throttle for the server check (iOS: at most every 10 minutes). */
    const val CHECK_INTERVAL_MS = 10L * 60 * 1000

    @Volatile private var appContext: Context? = null
    private val _parkedId = MutableStateFlow<String?>(null)
    /** The parked voice id, or null. Observable for the UI. */
    val parkedId: StateFlow<String?> = _parkedId.asStateFlow()

    /** Asks the app to re-read the state: `true` = force (sign-in, purchase). */
    val recheck = MutableSharedFlow<Boolean>(extraBufferCapacity = 4)

    fun init(context: Context) {
        appContext = context.applicationContext
        _parkedId.value = prefs(context)?.getString(KEY, null)
    }

    private fun prefs(c: Context? = appContext) =
        c?.applicationContext?.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    fun isParked(voiceId: String?): Boolean =
        voiceId != null && _parkedId.value == voiceId

    fun set(voiceId: String?) {
        _parkedId.value = voiceId
        prefs()?.edit()?.apply {
            if (voiceId == null) remove(KEY) else putString(KEY, voiceId)
        }?.apply()
    }

    fun requestRecheck(force: Boolean = false) { recheck.tryEmit(force) }

    /** The id dropped for want of a recording (see [DROPPED_KEY]). */
    fun droppedId(): String? = prefs()?.getString(DROPPED_KEY, null)

    fun markDropped(voiceId: String?) {
        prefs()?.edit()?.apply {
            if (voiceId == null) remove(DROPPED_KEY) else putString(DROPPED_KEY, voiceId)
        }?.apply()
    }

    // MARK: - Pure rules (JVM-tested)

    /** Should the server be asked now? A parked voice is always re-read on a
     *  forced check; an un-parked one at most every [CHECK_INTERVAL_MS]. */
    fun shouldCheck(alreadyParked: Boolean, force: Boolean, lastCheckedAt: Long?, now: Long): Boolean {
        if (force) return true
        if (alreadyParked) return false
        return lastCheckedAt == null || now - lastCheckedAt >= CHECK_INTERVAL_MS
    }

    /** What the row's `parked_at` means for the phone: the new parked id. */
    fun nextParkedId(voiceId: String, parkedAt: String?): String? =
        if (parkedAt.isNullOrBlank()) null else voiceId

    /** The restore must not hand back a voice dropped for want of a sample. */
    fun restoredVoiceId(serverId: String?, dropped: String?): String? =
        if (serverId != null && serverId == dropped) null else serverId
}

/**
 * What a metered tap does with a parked voice (iOS `VoiceRevival`). Asked by
 * [BillingGate] only AFTER it decided the account may spend — nothing to
 * spend is the paywall, as always.
 */
object VoiceRevival {
    enum class Purpose { CALL, SCENE }

    enum class Decision {
        /** Not parked: start what was tapped. */
        PROCEED,
        /** Parked, recording on the phone: rebuild it in front of the learner. */
        REBUILD,
        /** Parked, no recording here (a reinstall, another device): record again. */
        RECORD_AGAIN,
    }

    fun decide(voiceId: String?, parkedId: String?, hasSample: Boolean): Decision = when {
        voiceId == null || parkedId == null || voiceId != parkedId -> Decision.PROCEED
        hasSample -> Decision.REBUILD
        else -> Decision.RECORD_AGAIN
    }

    /** One revival on screen; the root hosts it as a full-screen dialog. */
    class Request(val purpose: Purpose) {
        val result = kotlinx.coroutines.CompletableDeferred<Boolean>()
    }

    val request = MutableStateFlow<Request?>(null)

    /**
     * True when whatever was tapped may start now. A parked voice puts up the
     * revival screen and waits for it: Start → true, closed → false.
     */
    suspend fun ensureVoice(purpose: Purpose): Boolean {
        if (VoiceParking.parkedId.value == null) return true
        // A second tap while one is up is swallowed, never stacked.
        if (request.value != null) return false
        val r = Request(purpose)
        request.value = r
        com.roro.futurevoice.core.Analytics.capture(
            "voice_revival_shown", mapOf("purpose" to purpose.name.lowercase()))
        return try { r.result.await() } finally { if (request.value === r) request.value = null }
    }
}
