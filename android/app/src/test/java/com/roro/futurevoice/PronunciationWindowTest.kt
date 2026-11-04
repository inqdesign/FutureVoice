package com.roro.futurevoice

import com.roro.futurevoice.talk.PronunciationAssessor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.sin

/** iOS `PronunciationWindowTests` (247383e9): a long take read as one file is
 *  cut into windows the assessment endpoint can take (≤30 s), at a pause,
 *  with nothing lost and no stub at the end. */
class PronunciationWindowTest {

    /** [seconds] of a 220 Hz tone with a 300 ms silence every 4 s. */
    private fun wav(seconds: Double): ByteArray {
        val rate = 16_000
        val count = (seconds * rate).toInt()
        val pcm = ByteBuffer.allocate(count * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until count) {
            val t = i.toDouble() / rate
            val silent = t % 4 > 3.7
            val v: Short = if (silent) 0 else (8000 * sin(2 * PI * 220 * t)).toInt().toShort()
            pcm.putShort(v)
        }
        return PronunciationAssessor.wavData(pcm.array(), rate)
    }

    private fun seconds(w: ByteArray) = (w.size - 44) / 32_000.0

    @Test fun longTakeIsCutIntoAssessableWindowsAtPauses() {
        val take = wav(67.0)
        val windows = PronunciationAssessor.windows(take)
        assertTrue(windows.size > 2)
        for (w in windows) {
            assertTrue(seconds(w) <= 28.01)
            assertTrue(seconds(w) > 5)
        }
        // Nothing dropped or doubled.
        assertEquals(take.size - 44, windows.sumOf { it.size - 44 })
        // Every cut but the last lands in a silence.
        for (w in windows.dropLast(1)) {
            val v = ByteBuffer.wrap(w, w.size - 2, 2).order(ByteOrder.LITTLE_ENDIAN).short
            assertEquals(0.toShort(), v)
        }
    }

    @Test fun shortRemainderStaysWhole() {
        assertEquals(1, PronunciationAssessor.windows(wav(25.0)).size)
    }
}
