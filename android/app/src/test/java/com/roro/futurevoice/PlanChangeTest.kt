package com.roro.futurevoice

import com.roro.futurevoice.data.PlanChange
import com.roro.futurevoice.data.PlanChange.Replacement
import com.roro.futurevoice.data.PlanChange.Route
import org.junit.Assert.assertEquals
import org.junit.Test

/** The paywall's primary button: buy, change a Play plan, or send elsewhere. */
class PlanChangeTest {

    private fun route(entitled: Boolean, source: String?, held: String?, tier: String, period: String = "monthly") =
        PlanChange.route(entitled, source, held, tier, period)

    @Test fun notASubscriberBuys() {
        assertEquals(Route.NewPurchase, route(false, null, null, "plus"))
        // A lapsed row still names a plan; not entitled = a fresh purchase.
        assertEquals(Route.NewPurchase, route(false, "google", "light_monthly", "plus"))
    }

    @Test fun theHeldPlanIsManagedNotBought() {
        assertEquals(Route.ManageCurrent, route(true, "google", "plus_monthly", "plus"))
        assertEquals(Route.ManageCurrent, route(true, "apple", "plus_monthly", "plus"))
    }

    @Test fun playUpgradeIsImmediateAndChargedNow() {
        assertEquals(Route.PlayChange(Replacement.CHARGE_PRORATED_PRICE, true),
            route(true, "google", "light_monthly", "plus"))
        assertEquals(Route.PlayChange(Replacement.CHARGE_PRORATED_PRICE, true),
            route(true, "google", "plus_monthly", "max"))
    }

    @Test fun playDowngradeWaitsForTheRenewal() {
        assertEquals(Route.PlayChange(Replacement.DEFERRED, false),
            route(true, "google", "max_monthly", "light"))
        assertEquals(Route.PlayChange(Replacement.DEFERRED, false),
            route(true, "google", "plus_monthly", "light"))
    }

    @Test fun sameTierOtherPeriodIsDeferredLikeAppleCrossgrade() {
        assertEquals(Route.PlayChange(Replacement.DEFERRED, false),
            route(true, "google", "light_monthly", "light", "annual"))
    }

    @Test fun anotherStoreNeverGetsAPlayChange() {
        assertEquals(Route.ManageElsewhere("apple"), route(true, "apple", "light_monthly", "plus"))
        assertEquals(Route.ManageElsewhere("stripe"), route(true, "stripe", "light_monthly", "plus"))
        // Unknown store (receipt unreadable): never guessed at.
        assertEquals(Route.ManageElsewhere(null), route(true, null, "light_monthly", "plus"))
    }

    @Test fun aCompHoldsNoStoreSubscriptionSoBuyingIsANewPurchase() {
        assertEquals(Route.NewPurchase, route(true, "comp", "plus_monthly", "max"))
        assertEquals(Route.ManageCurrent, route(true, "comp", "plus_monthly", "plus"))
    }
}
