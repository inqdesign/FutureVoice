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

    private fun decide(cached: AccountStatus?, signedIn: Boolean = true,
                       fresh: AccountStatus?): Pair<Boolean, Int> = runBlocking {
        var loads = 0
        val (go, _) = BillingGate.decide(cached, signedIn) { loads++; fresh }
        go to loads
    }

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
}
