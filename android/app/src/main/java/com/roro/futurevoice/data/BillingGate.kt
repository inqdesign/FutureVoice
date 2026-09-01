package com.roro.futurevoice.data

import kotlinx.coroutines.flow.MutableStateFlow

/**
 * The paywall is asked BEFORE the spending, at the tap.
 *
 * Met only as a 402, a hard paywall arrives too late to be an answer: the call
 * screen is already up, and on Watch a whole scene has been written — and
 * watched being written — before the learner is told it isn't theirs to play.
 * So every metered launcher runs its action through here.
 *
 * Two rules keep it honest, and both matter:
 *
 * - **It gates on [AccountStatus.needsSubscription] ONLY.** A spent allowance
 *   is not this — that learner already paid, and the client's copy of the
 *   period's usage is stale often enough to refuse a call the server would
 *   allow.
 * - **A "no" is never given from cache.** A purchase that landed a minute ago
 *   must not be paywalled again, so a refusal always re-reads first. A "yes"
 *   always comes from cache, so the app's primary button never waits on the
 *   network.
 */
object BillingGate {

    /** Set when a gate refuses; the root presents the paywall from it. */
    val showPaywall = MutableStateFlow(false)

    @Volatile private var cached: AccountStatus? = null

    /** Fold in a status someone else just loaded (Me, a purchase result). */
    fun remember(status: AccountStatus) { cached = status }

    fun invalidate() { cached = null }

    /**
     * Run [action] if the account can spend; otherwise raise the paywall and
     * return false.
     */
    suspend fun start(auth: AuthRepository, action: () -> Unit): Boolean {
        // A cached YES is answered instantly — that is the common case and the
        // one the primary button must never wait on.
        if (cached?.needsSubscription == false) { action(); return true }

        val fresh = AccountStatus.load(auth)
        cached = fresh
        if (!fresh.needsSubscription) { action(); return true }
        showPaywall.value = true
        return false
    }
}
