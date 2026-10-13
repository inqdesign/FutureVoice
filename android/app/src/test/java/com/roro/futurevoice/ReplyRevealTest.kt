package com.roro.futurevoice

import com.roro.futurevoice.talk.ReplyReveal
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `ReplyRevealTests`. */
class ReplyRevealTest {
    private val text = "Oh nice, that sounds fun. What did you eat there? I'd love to know."

    @Test fun onlyTheFirstWordsAtVoiceStart() {
        assertEquals("Oh nice,", ReplyReveal.visible(text, true, 0.0, 14.0))
    }

    @Test fun wordsFollowThePace() {
        // "Oh nice that" = 10 letters → "sounds" starts at ~0.71 s.
        assertEquals("Oh nice, that", ReplyReveal.visible(text, true, 0.5, 14.0))
        assertEquals("Oh nice, that sounds", ReplyReveal.visible(text, true, 0.6, 14.0))
        assertEquals(text, ReplyReveal.visible(text, true, 10.0, 14.0))
    }

    @Test fun sentenceGapHoldsTheNextWord() {
        // "What" starts after 20 letters (1.43 s) plus one sentence gap (0.4 s).
        assertEquals("Oh nice, that sounds fun.", ReplyReveal.visible(text, true, 1.5, 14.0))
        assertEquals("Oh nice, that sounds fun. What", ReplyReveal.visible(text, true, 1.7, 14.0))
    }

    @Test fun unfinishedTailWaitsForFinal() {
        val t = "Sure thing. And then we"
        assertEquals("Sure thing.", ReplyReveal.visible(t, false, 10.0, 14.0))
        assertEquals(t, ReplyReveal.visible(t, true, 10.0, 14.0))
    }

    @Test fun nothingBeforeTheFirstSentenceEnds() {
        assertEquals("", ReplyReveal.visible("Well I think", false, 5.0, 14.0))
    }

    @Test fun japaneseGoesByCharacter() {
        val t = "いいね。何を食べたの？"
        assertEquals("いい", ReplyReveal.visible(t, true, 0.0, 7.0))
        assertEquals("いいね。", ReplyReveal.visible(t, true, 0.3, 7.0))
        assertEquals(t, ReplyReveal.visible(t, true, 5.0, 7.0))
    }

    @Test fun koreanGoesByWord() {
        assertEquals("좋아.", ReplyReveal.visible("좋아. 뭐 먹었어?", true, 0.0, 7.0))
    }

    @Test fun ownRateLeavesTheGapsOut() {
        // 49 letters, 3 sentences → 0.8 s of gaps in 4.3 s of audio.
        assertEquals(14.0, ReplyReveal.charactersPerSecond(text, 4.3)!!, 0.01)
    }

    @Test fun koreanDefaultIsSyllabic() {
        assertEquals(7.0, ReplyReveal.defaultCharactersPerSecond("좋아. 뭐 먹었어?", 1.0), 0.0)
        assertEquals(14.0, ReplyReveal.defaultCharactersPerSecond("Nice.", 1.0), 0.0)
    }
}
