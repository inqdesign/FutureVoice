package com.roro.futurevoice

import com.roro.futurevoice.talk.RealtimeTalkClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayOutputStream
import kotlin.math.PI
import kotlin.math.sin

/**
 * Port of iOS `RealtimeFluencyTests` (`55088c28`): `fluencyStats` is the
 * realtime path's only source of articulation rate — the number Progress
 * bands fluency from and the level assessment reads as hard evidence.
 */
class RealtimeFluencyTest {
    private val rate = 16_000

    /** Spans of (seconds, amplitude) as 16-bit PCM; amplitude 0 is silence. */
    private fun pcm(vararg spans: Pair<Double, Double>): ByteArray {
        val out = ByteArrayOutputStream()
        for ((seconds, amplitude) in spans) {
            for (i in 0 until (seconds * rate).toInt()) {
                val v = (amplitude * 32_000 * sin(2 * PI * 220 * i / rate)).toInt().toShort().toInt()
                out.write(v and 0xFF); out.write((v shr 8) and 0xFF)
            }
        }
        return out.toByteArray()
    }

    @Test fun voicedTimeAndOnePause() {
        val stats = RealtimeTalkClient.fluencyStats(pcm(1.0 to 0.5, 0.6 to 0.0, 1.0 to 0.5), rate)
        assertNotNull(stats)
        assertEquals(2.0, stats!!.speakingSeconds, 0.05)
        assertEquals(1, stats.pauseCount)
        assertEquals(0.6, stats.pauseSeconds, 0.05)
    }

    /** A breath between words is not a pause. */
    @Test fun shortGapIsNotAPause() {
        val stats = RealtimeTalkClient.fluencyStats(pcm(1.0 to 0.5, 0.2 to 0.0, 1.0 to 0.5), rate)
        assertEquals(0, stats!!.pauseCount)
    }

    /** A room 20 dB under the voice is not speech, in the gap or around it. */
    @Test fun roomNoiseUnderTheVoiceIsNotVoiced() {
        val stats = RealtimeTalkClient.fluencyStats(
            pcm(0.5 to 0.05, 1.0 to 0.5, 0.8 to 0.05, 1.0 to 0.5, 0.5 to 0.05), rate)
        assertEquals(2.0, stats!!.speakingSeconds, 0.05)
        assertEquals(1, stats.pauseCount)
    }

    @Test fun silenceHasNoStats() {
        assertNull(RealtimeTalkClient.fluencyStats(pcm(1.0 to 0.0), rate))
    }
}
