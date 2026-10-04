package com.roro.futurevoice

import com.roro.futurevoice.talk.PacedSpeech
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.sin

/** iOS `PacedSpeechTests`: the sentence split (identical to the gateway's
 *  `CallSession.sentenceEnd`) and the join — inner edges trimmed, one gap. */
class PacedSpeechTest {
    @Test fun splitsEverySpacedAndCjkSentence() {
        assertEquals(listOf("그거 힘들었겠다.", "나도 그랬거든.", "어떻게 했어?"),
            PacedSpeech.sentences("그거 힘들었겠다. 나도 그랬거든. 어떻게 했어?"))
        assertEquals(listOf("それは大変だったね。", "私も去年、似たことがあった。", "それで？"),
            PacedSpeech.sentences("それは大変だったね。私も去年、似たことがあった。それで？"))
    }

    @Test fun doesNotCutAbbreviationsOrQuotedJapanese() {
        assertEquals(listOf("Mr. Kim said hi!", "Ok"), PacedSpeech.sentences("Mr. Kim said hi! Ok"))
        assertEquals(listOf("Wir gehen z.B. morgen.", "Gut?"), PacedSpeech.sentences("Wir gehen z.B. morgen. Gut?"))
        assertEquals(listOf("彼は「行く。」と言った。", "次"), PacedSpeech.sentences("彼は「行く。」と言った。次"))
    }

    @Test fun oneSentenceIsOne() {
        assertEquals(listOf("Hey, how's it going?"), PacedSpeech.sentences("Hey, how's it going?"))
    }

    /** silence(lead) + tone(voice) + silence(trail), 16 kHz. */
    private fun take(lead: Double, voice: Double, trail: Double): ByteArray {
        val sr = 16000.0
        val samples = ShortArray((lead * sr).toInt()) +
            ShortArray((voice * sr).toInt()) { (12000 * sin(it * 2 * PI * 220 / sr)).toInt().toShort() } +
            ShortArray((trail * sr).toInt())
        val b = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        samples.forEach { b.putShort(it) }
        return b.array()
    }

    @Test fun joinPutsOneFixedGapBetweenVoices() {
        val sr = 16000.0
        val a = take(0.10, 0.5, 0.40)
        val b = take(0.15, 0.5, 0.30)
        val joined = PacedSpeech.joined(listOf(a, b), sr)
        val seconds = (joined.size / 2) / sr
        assertEquals(0.10 + 0.5 + PacedSpeech.SENTENCE_GAP_SECONDS + 0.5 + 0.30, seconds, 0.03)
        val span = PacedSpeech.voicedSpan(
            joined.copyOfRange((0.7 * sr).toInt() * 2, (1.3 * sr).toInt() * 2), sr)
        assertNotNull(span)
    }
}
