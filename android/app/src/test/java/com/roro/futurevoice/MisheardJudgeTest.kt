package com.roro.futurevoice

import com.roro.futurevoice.talk.MisheardJudge
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `MisheardJudgeTests`, case for case (2026-11-17). */
class MisheardJudgeTest {
    @Test fun `the word check catches how learners say it`() {
        listOf(
            "Excuse me, the six month is that you misheard because I was walking outside",
            "That was not me, that was someone on the street.",
            "그거 내가 한 말 아니야, 옆에 지나가던 사람 목소리야.",
            "三匹なんて言ってないよ。聞き間違いだよ。",
            "Das habe ich nicht gesagt, das war der Fernseher.",
            "Yo no dije eso, fue otra persona.",
            "Je n'ai pas dit ça.",
            "我没说这个，你听错了。",
        ).forEach { assertTrue(it, MisheardJudge.mayRetract(it)) }
    }

    @Test fun `an ordinary line is never asked about`() {
        listOf("I had lunch with my partner at a new restaurant.", "주말에 부산에 갔다 왔어.", "Ich war gestern im Kino.")
            .forEach { assertFalse(it, MisheardJudge.mayRetract(it)) }
    }

    @Test fun `the judge sees each line with its reply`() {
        val c = MisheardJudge.Candidate("t", "s", "She is here for six month.", "Oh, your friend is here for six months?")
        val text = MisheardJudge.content(listOf(c), "That was not me.")
        assertTrue(text.contains("1. learner: \"She is here for six month.\""))
        assertTrue(text.contains("reply: \"Oh, your friend is here for six months?\""))
        assertTrue(text.contains("Newest line from the learner: \"That was not me.\""))
    }

    @Test fun `a disowned line is labelled for the summary`() {
        assertEquals("[USER] I'm on my way home.",
            SessionSummarizer.formatTranscript(listOf(Turn(role = TurnRole.USER, transcript = "I'm on my way home."))))
        assertEquals("[NOT_THE_USER] She is here for six month.",
            SessionSummarizer.formatTranscript(listOf(
                Turn(role = TurnRole.USER, transcript = "She is here for six month.", excludedFromScoring = true))))
    }
}
