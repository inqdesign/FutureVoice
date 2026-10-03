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

    fun invalidate() {
        cached = null
        // A purchase changes what a PARKED voice may do; re-read it so the
        // next tap knows.
        if (VoiceParking.parkedId.value != null) VoiceParking.requestRecheck(force = true)
    }

    /**
     * Run [action] if the account can spend; otherwise raise the paywall and
     * return false.
     *
     * Allowed to spend but the voice is PARKED ([VoiceParking]): it is rebuilt
     * in front of the learner first ([VoiceRevival]), and [action] runs only
     * if they tap Start — false if they close it.
     */
    suspend fun start(
        auth: AuthRepository,
        purpose: VoiceRevival.Purpose = VoiceRevival.Purpose.CALL,
        action: () -> Unit,
    ): Boolean {
        // A cached YES is answered instantly — that is the common case and the
        // one the primary button must never wait on.
        if (cached?.needsSubscription == false) return proceed(purpose, action)

        // A "no" is never given from cache, and it is never given from a
        // FAILURE either: if the account can't be read right now, the primary
        // button must not die silently — run the action, and let the metered
        // call's own 402 raise the wall if there is one.
        val fresh = runCatching { AccountStatus.load(auth) }.getOrNull()
        if (fresh == null) return proceed(purpose, action)
        cached = fresh
        if (!fresh.needsSubscription) return proceed(purpose, action)
        showPaywall.value = true
        return false
    }

    private suspend fun proceed(purpose: VoiceRevival.Purpose, action: () -> Unit): Boolean {
        if (!VoiceRevival.ensureVoice(purpose)) return false
        action()
        return true
    }
}
