package com.roro.futurevoice.ui

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings

/**
 * The app's haptic vocabulary — iOS `HapticEngine`, one method for one
 * method, so a beat feels the same on every surface that fires it.
 *
 * Not `View.performHapticFeedback`: One UI maps nearly every feedback
 * constant (CLOCK_TICK, TEXT_HANDLE_MOVE, SEGMENT_TICK, LONG_PRESS,
 * VIRTUAL_KEY) to its own ~215 ms "SemHaptic" buzz — measured on a Galaxy
 * A34 — which is several times what iOS's selection tick or light impact is,
 * and a run of tile taps read as the phone ringing. The predefined effects
 * (TICK / CLICK / HEAVY_CLICK, 23–27 ms there) and short waveforms are what
 * the hardware actually plays as a tap, so this drives the vibrator directly.
 *
 * Respects the system the way iOS does: the Touch feedback switch
 * (`haptic_feedback_enabled`) silences everything, and on API 33+ the
 * vibration rides the TOUCH usage, so the touch-intensity slider scales it
 * and "off" there means off.
 */
object HapticEngine {

    // ── Primitives (iOS UIImpactFeedbackGenerator / UINotification / UISelection)

    fun light(context: Context) = play(context, Beat.LIGHT)
    fun medium(context: Context) = play(context, Beat.MEDIUM)
    fun soft(context: Context) = play(context, Beat.SOFT)
    fun rigid(context: Context) = play(context, Beat.RIGID)
    fun success(context: Context) = play(context, Beat.SUCCESS)
    fun warning(context: Context) = play(context, Beat.WARNING)
    fun error(context: Context) = play(context, Beat.ERROR)

    /** The "a picker moved to a new value" tick — quieter than an impact. */
    fun selection(context: Context) = play(context, Beat.SELECTION)

    // ── Semantic events (use these from screens)

    fun drillCorrect(context: Context) = success(context)
    fun drillIncorrect(context: Context) = warning(context)
    fun drillBinChanged(context: Context) = selection(context)
    fun drillBinned(context: Context, mastered: Boolean) =
        if (mastered) success(context) else rigid(context)

    /** Shadow countdown 3 / 2 / 1. */
    fun countdownTick(context: Context) = light(context)

    /** Countdown "GO" — recording starts now. */
    fun countdownGo(context: Context) = medium(context)

    /** A shadow take finished — strength scales with the score. */
    fun shadowComplete(context: Context, score: Int) = when {
        score >= 80 -> success(context)
        score >= 50 -> soft(context)
        else -> warning(context)
    }

    // ── Playback

    private enum class Beat { SELECTION, LIGHT, SOFT, MEDIUM, RIGID, SUCCESS, WARNING, ERROR }

    private fun play(context: Context, beat: Beat) {
        val cr = context.contentResolver
        if (Settings.System.getInt(cr, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0) return
        val vibrator = vibrator(context) ?: return
        if (!vibrator.hasVibrator()) return
        val effect = effect(vibrator, beat)
        runCatching {
            if (Build.VERSION.SDK_INT >= 33) {
                vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(effect, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            }
        }
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= 31)
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        else @Suppress("DEPRECATION") (context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)

    private fun effect(vibrator: Vibrator, beat: Beat): VibrationEffect {
        // Phones with composition primitives (Pixels and up) get the shaped
        // version: the primitives are tuned per actuator.
        if (Build.VERSION.SDK_INT >= 30 && vibrator.areAllPrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_CLICK, VibrationEffect.Composition.PRIMITIVE_TICK)) {
            val c = VibrationEffect.startComposition()
            val click = VibrationEffect.Composition.PRIMITIVE_CLICK
            val tick = VibrationEffect.Composition.PRIMITIVE_TICK
            when (beat) {
                Beat.SELECTION -> c.addPrimitive(tick, 0.6f)
                Beat.LIGHT -> c.addPrimitive(click, 0.45f)
                Beat.SOFT -> c.addPrimitive(tick, 1f)
                Beat.MEDIUM -> c.addPrimitive(click, 0.75f)
                Beat.RIGID -> c.addPrimitive(click, 1f)
                // iOS success rises (tap-TAP), warning falls (TAP-tap),
                // error is a run of taps.
                Beat.SUCCESS -> c.addPrimitive(click, 0.5f).addPrimitive(click, 1f, 70)
                Beat.WARNING -> c.addPrimitive(click, 1f).addPrimitive(click, 0.5f, 110)
                Beat.ERROR -> c.addPrimitive(click, 0.8f).addPrimitive(click, 0.8f, 60)
                    .addPrimitive(click, 1f, 60)
            }
            return c.compose()
        }
        // The rest: the vendor's predefined taps for single beats, and short
        // waveforms for the two-beat notifications so success and warning
        // stay distinct where the hardware can shape amplitude.
        val amp = vibrator.hasAmplitudeControl()
        return when (beat) {
            Beat.SELECTION, Beat.LIGHT, Beat.SOFT -> predefined(PRE_TICK, 10, 90)
            Beat.MEDIUM -> predefined(PRE_CLICK, 14, 170)
            Beat.RIGID -> predefined(PRE_HEAVY_CLICK, 18, 255)
            Beat.SUCCESS -> if (amp) VibrationEffect.createWaveform(
                longArrayOf(0, 14, 70, 20), intArrayOf(0, 120, 0, 255), -1)
                else predefined(PRE_DOUBLE_CLICK, 20, VibrationEffect.DEFAULT_AMPLITUDE)
            Beat.WARNING -> if (amp) VibrationEffect.createWaveform(
                longArrayOf(0, 20, 110, 14), intArrayOf(0, 255, 0, 120), -1)
                else predefined(PRE_HEAVY_CLICK, 20, VibrationEffect.DEFAULT_AMPLITUDE)
            Beat.ERROR -> if (amp) VibrationEffect.createWaveform(
                longArrayOf(0, 16, 60, 16, 60, 22), intArrayOf(0, 200, 0, 200, 0, 255), -1)
                else predefined(PRE_DOUBLE_CLICK, 20, VibrationEffect.DEFAULT_AMPLITUDE)
        }
    }

    // VibrationEffect.EFFECT_* (API 29); a one-shot stands in below that.
    private const val PRE_CLICK = 0
    private const val PRE_DOUBLE_CLICK = 1
    private const val PRE_TICK = 2
    private const val PRE_HEAVY_CLICK = 5

    private fun predefined(id: Int, fallbackMs: Long, fallbackAmp: Int): VibrationEffect =
        if (Build.VERSION.SDK_INT >= 29) VibrationEffect.createPredefined(id)
        else VibrationEffect.createOneShot(fallbackMs, fallbackAmp)
}
