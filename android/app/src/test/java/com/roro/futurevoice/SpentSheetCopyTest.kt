package com.roro.futurevoice

import com.roro.futurevoice.ui.SpentPool
import com.roro.futurevoice.ui.SpentSheetCopy
import com.roro.futurevoice.ui.SpentSheetCopy.Next
import com.roro.futurevoice.ui.SpentSheetCopy.Renewal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The spent-pool sheet's branching (iOS `DailyAllowanceSheet`, the trial half 2026-09-25). */
class SpentSheetCopyTest {

    @Test fun aTrialIsNeverOfferedABiggerPlan() {
        assertTrue(SpentSheetCopy.showsUpgrade(canUpgrade = true, isTrial = false))
        assertFalse(SpentSheetCopy.showsUpgrade(canUpgrade = true, isTrial = true))
        assertFalse(SpentSheetCopy.showsUpgrade(canUpgrade = false, isTrial = false))
    }

    @Test fun aTrialTitleNamesTheTrialNotTheMonth() {
        assertEquals(R.string.that_s_your_trial_s_talk_time, SpentSheetCopy.title(SpentPool.TALK, true))
        assertEquals(R.string.that_s_your_trial_s_scenes, SpentSheetCopy.title(SpentPool.SCENES, true))
        assertEquals(R.string.that_s_this_month_s_talk_time, SpentSheetCopy.title(SpentPool.TALK, false))
        assertEquals(R.string.that_s_this_month_s_scenes, SpentSheetCopy.title(SpentPool.SCENES, false))
    }

    @Test fun aTrialSaysWhenThePlanStartsAndWithHowMuch() {
        assertEquals(Next.TRIAL_STARTS_WITH_MINUTES, next(isTrial = true, knowsPlanMinutes = true))
        assertEquals(Next.TRIAL_STARTS, next(isTrial = true, knowsPlanMinutes = false))
        // A cancelled trial has nothing starting; neither does an undated one.
        assertEquals(Next.REVIEW_FREE, next(isTrial = true, knowsPlanMinutes = true, endsInstead = true))
        assertEquals(Next.REVIEW_FREE, next(isTrial = true, knowsPlanMinutes = true, hasDate = false))
        // The pack and the plan move never reach a trial's line.
        assertEquals(Next.TRIAL_STARTS,
            next(isTrial = true, knowsPlanMinutes = false, packLeads = true, showsUpgrade = true))
    }

    @Test fun aSubscriberLineNamesOnlyButtonsTheSheetHas() {
        assertEquals(Next.ADD_MOVE_OR_REVIEW, next(packLeads = true, showsUpgrade = true))
        assertEquals(Next.ADD_OR_REVIEW, next(packLeads = true))
        assertEquals(Next.REVIEW_OR_MOVE, next(showsUpgrade = true))
        assertEquals(Next.REVIEW_FREE, next())
    }

    @Test fun aTrialDateIsNotARefill() {
        assertEquals(Renewal.NONE, SpentSheetCopy.renewal(isTrial = true, endsInstead = false, hasDate = true))
        assertEquals(Renewal.TRIAL_ENDS, SpentSheetCopy.renewal(isTrial = true, endsInstead = true, hasDate = true))
        assertEquals(Renewal.PLAN_ENDS, SpentSheetCopy.renewal(isTrial = false, endsInstead = true, hasDate = true))
        assertEquals(Renewal.REFILLS, SpentSheetCopy.renewal(isTrial = false, endsInstead = false, hasDate = true))
        assertEquals(Renewal.NONE, SpentSheetCopy.renewal(isTrial = false, endsInstead = false, hasDate = false))
    }

    private fun next(
        isTrial: Boolean = false, endsInstead: Boolean = false, hasDate: Boolean = true,
        knowsPlanMinutes: Boolean = false, packLeads: Boolean = false, showsUpgrade: Boolean = false,
    ) = SpentSheetCopy.next(isTrial, endsInstead, hasDate, knowsPlanMinutes, packLeads, showsUpgrade)
}
