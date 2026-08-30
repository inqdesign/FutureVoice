package com.roro.futurevoice.audio

import kotlin.math.max
import kotlin.math.min

/**
 * Measured delivery + the endpointing energy signal. Port of the iOS
 * `FluencyMeter` — the constants ARE the contract
 * (`docs/contracts/behavior.md` §2), not tuning knobs a port gets to re-pick.
 *
 * PLATFORM NOTE — the one honest deviation. iOS taps raw PCM and computes
 * dBFS, so `0.35` on its 0…1 curve is exactly −32.5 dBFS. Android's
 * `SpeechRecognizer.onRmsChanged` reports a vendor-defined "normalized RMS in
 * dB" (documented range ≈ −2…10) that is NOT dBFS, and the recognizer holds
 * the mic exclusively so raw PCM can't be tapped alongside it. [levelFromRmsDb]
 * maps that range onto the same 0…1 curve so every RELATIVE rule below —
 * adaptive floor, margin, rise rate — behaves identically. The absolute floor
 * is the part that needs per-device calibration; see the parity gap in
 * `docs/contracts/README.md`.
 */
class FluencyMeter {

    /** Absolute "this is speech" floor on the 0…1 curve (iOS: −32.5 dBFS). */
    private val baseVoicedThreshold = 0.35f

    /**
     * How far above the measured noise floor a frame must sit to count as
     * speech. 0.22 on the 0…1 curve ≈ 11 dB (`behavior.md` §2).
     *
     * Raised from 0.12 (≈ 6 dB) on iOS on 2026-08-18 after a café test where
     * the turn never ended: 6 dB over a decaying MINIMUM is a bar other
     * people's voices clear easily, so the room read as the learner. The
     * learner's mouth is ~20 cm from the mic and the next table metres away —
     * 15–20 dB — so 11 dB sits between the two. Quiet rooms are untouched by
     * construction: there the absolute 0.35 floor is the higher bar and
     * decides alone.
     */
    private val noiseMargin = 0.22f

    /** Decaying-minimum noise estimate rise rate (≈ 1.5 dB/s). */
    private val noiseRisePerSecond = 0.03f

    /** Silence run that counts as one pause/hesitation. */
    private val minPause = 0.35

    private var total = 0.0
    private var voiced = 0.0
    private var started = false
    private var silenceRun = 0.0
    private var pauseCount = 0
    private var pauseSeconds = 0.0
    private var longestPause = 0.0

    /**
     * Snaps DOWN instantly to a quieter level, rises SLOWLY. Without that
     * asymmetry a burst of the user's own speech would push the threshold above
     * their voice and read them as silent. Outdoors and in cafés ambient runs
     * −40…−25 dBFS, i.e. at or above the absolute floor — this is why turns
     * stopped firing outside before the 2026-08 retune.
     */
    private var noiseFloor = 0f
    private var hasNoiseFloor = false

    @Volatile
    private var lastVoicedAtMs: Long? = null

    private val voicedThreshold: Float
        get() = max(baseVoicedThreshold, noiseFloor + noiseMargin)

    fun reset() {
        total = 0.0; voiced = 0.0; started = false; silenceRun = 0.0
        pauseCount = 0; pauseSeconds = 0.0; longestPause = 0.0
        noiseFloor = 0f; hasNoiseFloor = false
        lastVoicedAtMs = null
    }

    /** Wall-clock moment the mic last heard VOICED audio. Null until first speech. */
    fun lastVoicedAt(): Long? = lastVoicedAtMs

    /** Ambient estimate on the 0…1 curve — telemetry only. */
    fun noiseFloorLevel(): Float = if (hasNoiseFloor) noiseFloor else 0f

    @Synchronized
    fun feed(level: Float, seconds: Double, nowMs: Long) {
        if (hasNoiseFloor) {
            noiseFloor = min(level, noiseFloor + noiseRisePerSecond * seconds.toFloat())
        } else {
            noiseFloor = min(level, baseVoicedThreshold)
            hasNoiseFloor = true
        }

        if (level >= voicedThreshold) {
            // Voiced again — close any qualifying mid-speech silence.
            if (started && silenceRun >= minPause) {
                pauseCount += 1
                pauseSeconds += silenceRun
                longestPause = max(longestPause, silenceRun)
            }
            silenceRun = 0.0
            started = true
            voiced += seconds
            total += seconds
            lastVoicedAtMs = nowMs
        } else if (started) {
            // Leading silence is ignored; trailing silence is the endpointer's job.
            silenceRun += seconds
            total += seconds
        }
    }

    @Synchronized
    fun snapshot(): FluencyStats = FluencyStats(
        speakingSeconds = voiced,
        totalSeconds = total,
        pauseCount = pauseCount,
        pauseSeconds = pauseSeconds,
        longestPauseSeconds = longestPause,
    )

    companion object {
        /**
         * Android `onRmsChanged` dB → the shared 0…1 level curve.
         * iOS equivalent: `clamp((dBFS + 50) / 50, 0, 1)`.
         */
        fun levelFromRmsDb(rmsDb: Float): Float =
            min(1f, max(0f, (rmsDb + 2f) / 12f))
    }
}

data class FluencyStats(
    val speakingSeconds: Double,
    val totalSeconds: Double,
    val pauseCount: Int,
    val pauseSeconds: Double,
    val longestPauseSeconds: Double,
)
