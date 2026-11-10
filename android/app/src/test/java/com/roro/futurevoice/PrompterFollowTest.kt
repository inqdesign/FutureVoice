package com.roro.futurevoice

import com.roro.futurevoice.talk.SpeechPrompterTrack
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `PrompterFollowTests` — the three tests 8a753a84 added for Say it again. */
class PrompterFollowTest {
    /** Say it again ends a take early on "the last word was heard", so the
     *  cursor must get there on the last word and not one word sooner. */
    @Test fun aLineReachesItsEndOnItsLastWordOnly() {
        val lines = listOf(
            "en" to "I went to the store and then I went to the store.",
            "en" to "I've been working here for two years, and I really like it.",
            "en" to "So what did you end up doing last weekend?",
            "ko" to "어제 친구랑 저녁을 먹었는데 정말 맛있었어.",
            "ko" to "그래서 나는 회사에 다시 돌아가기로 했어.",
            "de" to "Ich habe gestern mit meinem Bruder telefoniert.",
        )
        for ((language, line) in lines) {
            val track = SpeechPrompterTrack(line, language)
            val spoken = line.split(Regex("\\s+")).filter { it.isNotEmpty() }
            var cursor = 0
            var heard = ""
            spoken.forEachIndexed { i, word ->
                heard += (if (heard.isEmpty()) "" else " ") + word
                cursor = maxOf(cursor, track.advance(cursor, heard))
                if (i < spoken.size - 1) {
                    assertTrue("$line after $heard", cursor < track.words.size)
                }
            }
            assertEquals(line, track.words.size, cursor)
        }
    }

    @Test fun theFirstWordIsHeardOnItsOwn() {
        val en = SpeechPrompterTrack("So what did you do?", "en")
        assertTrue(en.opensWithFirstWord("So"))
        assertTrue(en.opensWithFirstWord("so what"))
        assertFalse(en.opensWithFirstWord(""))
        assertFalse(en.opensWithFirstWord("Um so"))
        val ko = SpeechPrompterTrack("어제 친구랑 만났어.", "ko")
        assertTrue(ko.opensWithFirstWord("어제"))
        assertTrue(ko.opensWithFirstWord("어제친구랑"))
        assertFalse(ko.opensWithFirstWord("어"))
    }

    @Test fun litCharactersFollowTheLineAsDrawn() {
        val track = SpeechPrompterTrack("Thank you so much.", "en")
        assertEquals(0, track.characterCount(0, "Thank you so much."))
        assertEquals(9, track.characterCount(2, "Thank you so much."))
        assertEquals(18, track.characterCount(4, "Thank you so much."))
        assertEquals(10, track.characterCount(2, "Thank  you so much."))
        // Past the end, or a line that doesn't carry the word: no crash, no overrun.
        assertEquals(18, track.characterCount(9, "Thank you so much."))
        assertEquals(5, track.characterCount(2, "Thank them."))
    }
}
