package com.roro.futurevoice

import com.roro.futurevoice.ui.TabArrival
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `RootTabView.onAppear`'s order: age check, else Talk guide → welcome, else welcome. */
class TabArrivalTest {
    @Test fun ageCheckTakesTheWholeArrival() {
        assertEquals(TabArrival.AGE_CHECK, TabArrival.decide(hasVoice = true, ageOnRecord = false, onTalk = true, talkGuideDue = true))
        assertEquals(TabArrival.AGE_CHECK, TabArrival.decide(hasVoice = true, ageOnRecord = false, onTalk = false, talkGuideDue = false))
    }

    @Test fun noVoiceNeverAsksAge() {
        assertEquals(TabArrival.GUIDE_THEN_WELCOME, TabArrival.decide(hasVoice = false, ageOnRecord = false, onTalk = true, talkGuideDue = true))
    }

    @Test fun talkGuideHoldsTheWelcome() {
        assertEquals(TabArrival.GUIDE_THEN_WELCOME, TabArrival.decide(hasVoice = true, ageOnRecord = true, onTalk = true, talkGuideDue = true))
    }

    @Test fun otherwiseTheWelcomeIsCheckedAtOnce() {
        assertEquals(TabArrival.WELCOME, TabArrival.decide(hasVoice = true, ageOnRecord = true, onTalk = true, talkGuideDue = false))
        assertEquals(TabArrival.WELCOME, TabArrival.decide(hasVoice = true, ageOnRecord = true, onTalk = false, talkGuideDue = true))
    }
}
