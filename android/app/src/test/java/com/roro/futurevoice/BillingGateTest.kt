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
    private val freeMinutes = AccountStatus(secondsBalance = 600)

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

    /** 2026-11-16: no free sample scene. A free account's scene costs five
     *  minutes of its balance like a subscriber's, so the scene tap passes
     *  the gate whenever a call would, and [AccountStatus.sceneTalkShort]
     *  decides whether five minutes are there. */
    @Test fun aFreeAccountsSceneIsPaidFromItsMinutes() {
        assertEquals(true to 0, decide(freeMinutes, scene = true, fresh = nothing))
        val scene = freeMinutes.copy(sceneTalkSeconds = 300)
        assertFalse(scene.sceneTalkShort)
        assertTrue(scene.copy(secondsBalance = 299).sceneTalkShort)
        assertTrue(scene.copy(secondsBalance = 120).sceneTalkShort)
        assertFalse(scene.copy(unlimited = true).sceneTalkShort)
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
        assertTrue(BillingGate.refreshBehind(freeMinutes, true, t, t + 120_000))
        assertTrue(BillingGate.refreshBehind(freeMinutes, false, t, t + 120_000))
    }
}
