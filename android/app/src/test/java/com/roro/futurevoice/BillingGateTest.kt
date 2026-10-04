package com.roro.futurevoice

import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.BillingGate
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `BillingGate.blocks` (plan 5.13): a "yes" from cache, a "no" never from
 * cache — and never from a failure or a signed-out read.
 */
class BillingGateTest {
    private val paid = AccountStatus(subscriptionStatus = "active")
    private val nothing = AccountStatus()

    private fun decide(cached: AccountStatus?, signedIn: Boolean = true, scene: Boolean = false,
                       fresh: AccountStatus?): Pair<Boolean, Int> = runBlocking {
        var loads = 0
        val (go, _) = BillingGate.decide(cached, signedIn, scene) { loads++; fresh }
        go to loads
    }

    /** A free account with a minute or more to talk on, two scenes had. */
    private val freeScenesGone = AccountStatus(secondsBalance = 600, freeScenesUsed = 2, freeScenesCap = 2)
    private val freeSceneLeft = freeScenesGone.copy(freeScenesUsed = 1)

    @Test fun aCachedYesNeverWaitsOnTheNetwork() {
        assertEquals(true to 0, decide(paid, fresh = nothing))
    }

    /** A purchase that landed a minute ago must not be paywalled again. */
    @Test fun aCachedNoIsReadAgain() {
        assertEquals(true to 1, decide(nothing, fresh = paid))
        assertEquals(false to 1, decide(nothing, fresh = nothing))
        assertEquals(false to 1, decide(null, fresh = nothing))
    }

    @Test fun aFailedReadLetsTheTapThrough() {
        assertEquals(true to 1, decide(null, fresh = null))
    }

    @Test fun aSignedOutReadIsNotNoPlan() {
        assertEquals(true to 0, decide(null, signedIn = false, fresh = nothing))
    }

    /** Under a minute is nothing left: a greeting and a wall is not a call. */
    @Test fun theFloorIsAMinuteNotZero() {
        assertTrue(AccountStatus(secondsBalance = 30).needsSubscription)
        assertTrue(AccountStatus(secondsBalance = 59).needsSubscription)
        assertFalse(AccountStatus(secondsBalance = 60).needsSubscription)
        assertFalse(AccountStatus(subscriptionStatus = "trialing").needsSubscription)
        assertFalse(AccountStatus(unlimited = true).needsSubscription)
        assertTrue(AccountStatus(subscriptionStatus = "expired").needsSubscription)
    }

    /** iOS `blocksScene`: a free account that has had its scenes is sent to
     *  the plans at the tap — before a scene is written for nothing. */
    @Test fun aFreeAccountsSpentScenesStopTheSceneTap() {
        assertEquals(false to 1, decide(freeScenesGone, scene = true, fresh = freeScenesGone))
        assertEquals(true to 0, decide(freeSceneLeft, scene = true, fresh = freeScenesGone))
        // A purchase since: the cached no is read again and lets it through.
        assertEquals(true to 1, decide(freeScenesGone, scene = true, fresh = paid))
    }

    /** It can still TALK off its balance — the call tap is untouched. */
    @Test fun spentFreeScenesDoNotStopACall() {
        assertEquals(true to 0, decide(freeScenesGone, fresh = nothing))
    }

    @Test fun onlyAFreeAccountHasFreeScenesToSpend() {
        assertTrue(freeScenesGone.freeScenesSpent)
        assertFalse(freeSceneLeft.freeScenesSpent)
        assertFalse(freeScenesGone.copy(subscriptionStatus = "active").freeScenesSpent)
        assertFalse(freeScenesGone.copy(unlimited = true).freeScenesSpent)
        // A server from before the field says nothing — never a refusal.
        assertFalse(freeScenesGone.copy(freeScenesCap = null).freeScenesSpent)
    }

    /** iOS `refreshIfStale`: a cached yes is re-read BEHIND the tap after
     *  60 s; a fresh one is not, and a cached no never is (it is re-read in
     *  front of the tap). */
    @Test fun aStaleCachedYesIsRefreshedBehindTheTap() {
        val t = 1_000_000L
        assertFalse(BillingGate.refreshBehind(paid, false, t, t + 59_999))
        assertTrue(BillingGate.refreshBehind(paid, false, t, t + 60_000))
        assertTrue(BillingGate.refreshBehind(paid, false, null, t))
        assertFalse(BillingGate.refreshBehind(nothing, false, t, t + 120_000))
        assertFalse(BillingGate.refreshBehind(null, false, null, t))
        assertFalse(BillingGate.refreshBehind(freeScenesGone, true, t, t + 120_000))
        assertTrue(BillingGate.refreshBehind(freeScenesGone, false, t, t + 120_000))
    }
}
