package com.roro.futurevoice.data

import com.roro.futurevoice.ui.isUncappedTalk

/**
 * Where the talk-minute pack is offered, and when it LEADS — the rules iOS
 * spreads over `DailyAllowanceSheet` (`canTopUp` / `packOffered` /
 * `packLeads`), `PlanPageView` and `PaywallView.showsPack`, in one place so
 * the three Android surfaces can't drift apart (master plan 4.0).
 *
 * Every clause is a way the button would otherwise be a lie:
 *  · an uncapped plan never spends the balance, so minutes bought there are
 *    granted and never used;
 *  · a trial's pool is the trial's own and converts on its date — the sheet
 *    and Usage stay out of it (the paywall, open to anyone, does not);
 *  · a scene wall can't be answered with talk minutes at all.
 */
object TopUpOffer {

    /** The spent-pool sheet ASKS for the pack: a talk wall on a counted,
     *  non-trial subscription. Asking is not selling — see [leads]. */
    fun onSpentSheet(account: AccountStatus?, talkWall: Boolean): Boolean =
        talkWall && account != null && subscriberCanBuy(account)

    /**
     * The pack takes the sheet's lead slot only once it has a PRICE. Until
     * then it draws nothing, and a lead slot reserved for it left iOS's Plus
     * subscriber with no primary button at all (2026-09-27).
     */
    fun leads(offered: Boolean, priced: Boolean): Boolean = offered && priced

    /** Usage lists the pack under the pool — subscribers on a counted pool. */
    fun onUsage(account: AccountStatus?): Boolean =
        account != null && subscriberCanBuy(account)

    /** The paywall's "Extra minutes" rung is for anyone — before a plan or on
     *  top of one — except an uncapped plan. Drawn only with a live price. */
    fun onPaywall(account: AccountStatus?, priced: Boolean): Boolean =
        priced && account?.isUncappedTalk != true

    private fun subscriberCanBuy(a: AccountStatus): Boolean =
        a.isEntitled && !a.isUncappedTalk && !a.isTrialing
}
