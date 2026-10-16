package com.roro.futurevoice

import com.roro.futurevoice.audio.VoiceDenoiser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The half of iOS `VoiceDenoiserTests` a JVM unit test can run: the take is
 * brought to the model's 48 kHz with its length and its signal intact. The
 * DeepFilterNet pass itself lives in `libfvdenoise.so`, built for Android
 * ABIs only — a host JVM cannot load it, so the noise-reduction half needs a
 * device or emulator (instrumented test), never a fake here.
 */
class VoiceDenoiserTest {
    private fun tone(rate: Int, seconds: Double, hz: Double) =
        FloatArray((rate * seconds).toInt()) { (0.3 * sin(2 * PI * hz * it / rate)).toFloat() }

    private fun rms(x: FloatArray, from: Int, to: Int): Double =
        sqrt((from until to).sumOf { x[it].toDouble() * x[it] } / (to - from))

    @Test fun upsamplesKeepingLengthAndLevel() {
        val input = tone(16_000, 2.0, 220.0)
        val out = VoiceDenoiser.resample(input, 16_000, VoiceDenoiser.SAMPLE_RATE)
        assertEquals(96_000, out.size)
        val a = rms(input, 1_600, 30_400)
        val b = rms(out, 4_800, 91_200)
        assertTrue("level moved: $a → $b", abs(a - b) / a < 0.02)
        // Phase lines up: sample i at 48 kHz is input i/3.
        for (i in listOf(3_000, 30_000, 60_000)) {
            assertEquals(input[i / 3].toDouble(), out[i].toDouble(), 0.01)
        }
    }

    @Test fun downsamplesAt441() {
        val out = VoiceDenoiser.resample(tone(44_100, 1.0, 440.0), 44_100, 48_000)
        assertEquals(48_000, out.size)
    }

    @Test fun sameRateIsUntouched() {
        val input = tone(48_000, 0.1, 440.0)
        assertTrue(VoiceDenoiser.resample(input, 48_000, 48_000) === input)
    }
}
