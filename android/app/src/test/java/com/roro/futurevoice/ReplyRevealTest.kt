package com.roro.futurevoice

import com.roro.futurevoice.talk.ReplyReveal
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `ReplyRevealTests`. */
class ReplyRevealTest {
    private val text = "Oh nice, that sounds fun. What did you eat there? I'd love to know."

    @Test fun firstSentenceOnlyAtVoiceStart() {
        assertEquals("Oh nice, that sounds fun.", ReplyReveal.visible(text, true, 0.0, 14.0))
    }

    @Test fun sentencesFollowThePace() {
        // "Oh nice that sounds fun" = 20 letters → second sentence at ~1.43 s.
        assertEquals("Oh nice, that sounds fun.", ReplyReveal.visible(text, true, 1.0, 14.0))
        assertEquals("Oh nice, that sounds fun. What did you eat there?", ReplyReveal.visible(text, true, 1.3, 14.0))
        assertEquals(text, ReplyReveal.visible(text, true, 10.0, 14.0))
    }

    @Test fun unfinishedTailWaitsForFinal() {
        val t = "Sure thing. And then we"
        assertEquals("Sure thing.", ReplyReveal.visible(t, false, 10.0, 14.0))
        assertEquals(t, ReplyReveal.visible(t, true, 10.0, 14.0))
    }

    @Test fun nothingBeforeTheFirstSentenceEnds() {
        assertEquals("", ReplyReveal.visible("Well I think", false, 5.0, 14.0))
    }

    @Test fun japaneseNeedsNoSpace() {
        val t = "いいね。何を食べたの？"
        assertEquals("いいね。", ReplyReveal.visible(t, true, 0.0, 7.0))
        assertEquals(t, ReplyReveal.visible(t, true, 5.0, 7.0))
    }

    @Test fun koreanDefaultIsSyllabic() {
        assertEquals(7.0, ReplyReveal.defaultCharactersPerSecond("좋아. 뭐 먹었어?", 1.0), 0.0)
        assertEquals(14.0, ReplyReveal.defaultCharactersPerSecond("Nice.", 1.0), 0.0)
    }
}
