package com.roro.futurevoice.data

/**
 * What the paywall's primary button does for the selected plan — the one
 * decision between "buy", "change the plan you have" and "that plan is not
 * Play's to change". Pure, so it is tested on the JVM (`PlanChangeTest`).
 *
 * Why it exists: on iOS a purchase inside the subscription group IS the plan
 * change — StoreKit sees the group and swaps the plan. Play has no groups, so
 * an existing Play subscriber who bought another plan with a plain billing
 * flow would end up holding TWO subscriptions and paying for both. A change
 * has to name the purchase it replaces (`SubscriptionUpdateParams` with the
 * old purchase token) and say how the money moves.
 *
 * How the money moves is copied from Apple, which is what every iPhone
 * learner already gets:
 *  - **Upgrade** (to a bigger tier) applies IMMEDIATELY and is charged now —
 *    Apple bills the new plan at once and refunds the unused part of the old
 *    one. Play's nearest is [Replacement.CHARGE_PRORATED_PRICE]: the new plan
 *    starts now, the learner pays the price DIFFERENCE for the rest of the
 *    current period today, and the renewal date stays where it was. The
 *    alternative, `WITH_TIME_PRORATION`, charges nothing now and instead
 *    turns the old plan's remaining value into fewer days of the new one,
 *    moving the renewal date earlier — no charge at the moment of the
 *    upgrade, and a billing date the learner didn't pick, which is neither
 *    Apple's behaviour nor what "upgrade now" reads as. Keeping the date also
 *    keeps the server's billing period (`billing_period_start()`) intact.
 *  - **Downgrade** (to a smaller tier) and a **period change on the same
 *    tier** take effect at the NEXT RENEWAL — [Replacement.DEFERRED], as
 *    Apple does for a downgrade or a crossgrade between durations. Nothing is
 *    charged today, and the learner keeps what they paid for until it ends.
 *
 * Only a subscription Play bills (`user_subscriptions.source == "google"`)
 * may go through a Play change flow. An App Store or Stripe subscription is
 * changed where it was bought — a Play purchase on top of it would be the
 * second subscription this exists to prevent — and an unknown source (the
 * receipt could not be read) is treated the same, never guessed at. A comp
 * (provided by nawana) holds no store subscription at all, so buying a plan
 * is an ordinary NEW purchase, which then replaces the comp exactly as an
 * Apple purchase does on iOS (`google-webhook` upserts the row).
 */
object PlanChange {

    enum class Replacement { CHARGE_PRORATED_PRICE, DEFERRED }

    sealed interface Route {
        /** Not a subscriber (or on a comp): an ordinary purchase. */
        data object NewPurchase : Route
        /** The selection is the plan they hold: Play's own manage screen. */
        data object ManageCurrent : Route
        /** A Play subscriber moving plans: replace the old purchase. */
        data class PlayChange(val replacement: Replacement, val isUpgrade: Boolean) : Route
        /** Billed by another store (or unknown): changed there, not here.
         *  [source] is `apple` / `stripe` / null. */
        data class ManageElsewhere(val source: String?) : Route
    }

    /**
     * @param currentPlanId the held plan (`light_monthly`), only meaningful
     *   when [isEntitled]
     * @param source `user_subscriptions.source`: google / apple / stripe / comp
     */
    fun route(
        isEntitled: Boolean,
        source: String?,
        currentPlanId: String?,
        targetTier: String,
        targetPeriod: String,
    ): Route {
        if (!isEntitled || currentPlanId.isNullOrBlank()) return Route.NewPurchase
        if (currentPlanId == "${targetTier}_$targetPeriod") return Route.ManageCurrent
        return when (source) {
            "comp" -> Route.NewPurchase
            "google" -> {
                val upgrade = isUpgrade(currentPlanId, targetTier)
                Route.PlayChange(
                    if (upgrade) Replacement.CHARGE_PRORATED_PRICE else Replacement.DEFERRED,
                    upgrade)
            }
            else -> Route.ManageElsewhere(source)
        }
    }

    /** A bigger TIER is an upgrade; the same tier on another period is not
     *  (Apple defers a crossgrade between durations to the renewal). */
    fun isUpgrade(currentPlanId: String, targetTier: String): Boolean {
        val order = AccountStatus.TIER_ORDER
        val from = order.indexOf(currentPlanId.substringBefore('_'))
        val to = order.indexOf(targetTier)
        if (from < 0 || to < 0) return false
        return to > from
    }
}
