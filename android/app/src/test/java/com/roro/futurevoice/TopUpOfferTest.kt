package com.roro.futurevoice

import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.TopUpOffer
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Where the talk-minute pack is offered (iOS `DailyAllowanceSheet` / `PlanPageView` / `PaywallView`). */
class TopUpOfferTest {

    private val light = AccountStatus(planId = "light_monthly", subscriptionStatus = "active",
        monthlyCapSeconds = 9000, secondsUsedPeriod = 9000)
    private val uncappedPlus = AccountStatus(planId = "plus_monthly", subscriptionStatus = "active",
        monthlyCapSeconds = null)
    private val trial = AccountStatus(planId = "plus_monthly", subscriptionStatus = "trialing",
        monthlyCapSeconds = 2100)
    private val free = AccountStatus(secondsBalance = 0)

    @Test fun sheetOffersThePackToACountedSubscriberOnATalkWall() {
        assertTrue(TopUpOffer.onSpentSheet(light, talkWall = true))
        // A scene pool can't be topped up with talk minutes.
        assertFalse(TopUpOffer.onSpentSheet(light, talkWall = false))
    }

    @Test fun sheetNeverOffersItToUncappedTrialFreeOrLoading() {
        assertFalse(TopUpOffer.onSpentSheet(uncappedPlus, talkWall = true))
        assertFalse(TopUpOffer.onSpentSheet(trial, talkWall = true))
        assertFalse(TopUpOffer.onSpentSheet(free, talkWall = true))
        assertFalse(TopUpOffer.onSpentSheet(null, talkWall = true))
    }

    @Test fun thePackLeadsOnlyOnceItHasAPrice() {
        assertTrue(TopUpOffer.leads(offered = true, priced = true))
        assertFalse(TopUpOffer.leads(offered = true, priced = false))
        assertFalse(TopUpOffer.leads(offered = false, priced = true))
    }

    @Test fun usageListsItForCountedSubscribersOnly() {
        assertTrue(TopUpOffer.onUsage(light))
        assertFalse(TopUpOffer.onUsage(uncappedPlus))
        assertFalse(TopUpOffer.onUsage(trial))
        assertFalse(TopUpOffer.onUsage(free))
    }

    @Test fun paywallOffersItToAnyoneButAnUncappedPlanAndOnlyPriced() {
        assertTrue(TopUpOffer.onPaywall(free, priced = true))
        assertTrue(TopUpOffer.onPaywall(trial, priced = true))
        assertTrue(TopUpOffer.onPaywall(light, priced = true))
        assertTrue(TopUpOffer.onPaywall(null, priced = true))
        assertFalse(TopUpOffer.onPaywall(uncappedPlus, priced = true))
        assertFalse(TopUpOffer.onPaywall(free, priced = false))
    }
}
