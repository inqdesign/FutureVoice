package com.roro.futurevoice.capture.flags

import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.BillingService
import com.roro.futurevoice.data.SubscriptionReceipt

/**
 * Screenshot-harness hooks for the Me / billing screens (capture build only
 * ever sets them). Every field is null in a normal build, so the screens load
 * their live data exactly as before.
 *
 * The capture app isn't signed in, so a billing page that loads its account
 * on open would render an empty free account. iOS hands those pages a sample
 * account as a parameter (`PlanPageView(account:)`); these are that parameter.
 */
object MeCaptureFlags {
    /** Rendered by Usage, the credit guide and the spent-allowance sheet
     *  instead of `AccountStatus.load`. */
    @JvmField var previewAccount: AccountStatus? = null

    /** Rendered by Usage's subscription section instead of `SubscriptionReceipt.load`. */
    @JvmField var previewReceipt: SubscriptionReceipt? = null

    /** The paywall opens straight on its PLANS step over this catalog, without
     *  asking Play or the server. */
    @JvmField var previewPlans: List<BillingService.Plan>? = null

    /** Store prices for [previewPlans], plan id → micros, in [previewCurrency]
     *  (iOS seeds the same table: a capture build is never priced by a store). */
    @JvmField var previewPrices: Map<String, Long>? = null
    @JvmField var previewCurrency: String? = null

    /** The invite offer the spent-pool sheet and Usage show instead of asking
     *  the referral server (iOS `previewInvite` / `DaySpentCaptureHost(invite:)`). */
    @JvmField var previewInvite: com.roro.futurevoice.ui.InviteOffer? = null

    /** The talk-minute pack with a seeded price, so the sheet, Usage and the
     *  paywall can draw it without Play (iOS seeds `Pack(… product: nil)`). */
    @JvmField var previewPack: BillingService.Pack? = null

    /** Voice changes left (iOS `-voiceChangesLeft`): 0 draws every voice
     *  control locked, without asking the server. */
    @JvmField var voiceChangesLeft: Int? = null
}
