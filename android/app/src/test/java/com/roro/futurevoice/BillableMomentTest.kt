package com.roro.futurevoice

import com.roro.futurevoice.talk.RealtimeTalkClient
import com.roro.futurevoice.talk.TalkMeter
import com.roro.futurevoice.talk.TalkMeter.Companion.Moment
import com.roro.futurevoice.talk.TalkPhase
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `ConversationView.isBillableMoment` / `someoneIsTalkingHere` (plan 5.10). */
class BillableMomentTest {
    private fun rt(st: RealtimeTalkClient.State, level: Float = 0f, spoke: Boolean = true) =
        TalkMeter.isBillable(Moment(spoke, TalkPhase.LISTENING, realtime = st, realtimeLevel = level))

    @Test fun nothingCountsBeforeTheLearnerSpeaks() {
        // The opener speaks whether or not it is answered.
        assertFalse(rt(RealtimeTalkClient.State.SPEAKING, spoke = false))
        assertFalse(TalkMeter.isBillable(Moment(false, TalkPhase.SPEAKING)))
    }

    @Test fun realtimeReadsTheGatewaysState() {
        assertTrue(rt(RealtimeTalkClient.State.SPEAKING))
        assertTrue(rt(RealtimeTalkClient.State.HEARING))
        assertTrue(rt(RealtimeTalkClient.State.THINKING))
        assertTrue(rt(RealtimeTalkClient.State.LISTENING, level = 0.3f))
        assertFalse(rt(RealtimeTalkClient.State.LISTENING, level = 0.2f))
        assertFalse(rt(RealtimeTalkClient.State.CONNECTING))
        assertFalse(rt(RealtimeTalkClient.State.IDLE))
    }

    @Test fun aPausedCallBillsNothing() {
        assertFalse(TalkMeter.isBillable(Moment(true, TalkPhase.PAUSED,
            realtime = RealtimeTalkClient.State.SPEAKING)))
    }

    @Test fun localPathTheFluentSelfWorking() {
        assertTrue(TalkMeter.isBillable(Moment(true, TalkPhase.THINKING)))
        assertTrue(TalkMeter.isBillable(Moment(true, TalkPhase.SPEAKING)))
        assertTrue(TalkMeter.isBillable(Moment(true, TalkPhase.LISTENING, audioPlaying = true)))
    }

    /** The café case: all three witnesses, or the second is free. */
    @Test fun localPathNeedsThreeWitnesses() {
        fun talk(voiced: Long?, heard: Long?, sec: Double) = TalkMeter.isBillable(
            Moment(true, TalkPhase.LISTENING, voicedAgoMs = voiced, heardAgoMs = heard, voicedSeconds = sec))
        assertTrue(talk(1_000, 2_000, 2.0))
        assertFalse(talk(6_000, 2_000, 2.0))   // energy older than the 6 s grace
        assertFalse(talk(1_000, 6_000, 2.0))   // recognizer stopped making words
        assertFalse(talk(1_000, null, 2.0))
        assertFalse(talk(null, 2_000, 2.0))
        assertFalse(talk(1_000, 2_000, 1.4))   // a clatter, not a person
        assertFalse(talk(null, null, 0.0))     // a quiet open screen
    }
}
