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
        val (go, fresh) = decide(cached, signedIn = auth.userId != null) {
            runCatching { AccountStatus.load(auth) }.getOrNull()
        }
        if (fresh != null) cached = fresh
        if (go) return proceed(purpose, action)
        showPaywall.value = true
        return false
    }

    /**
     * The gate's answer, pure (plan 5.13, iOS `BillingGate.blocks`): true =
     * go. [load] is consulted only when the answer could be NO.
     *
     * - A cached YES is answered instantly — the common case, and the one
     *   the primary button must never wait on.
     * - A "no" is never given from cache: a refusal always re-reads first.
     * - Nor from a FAILURE: if the account can't be read, run the action and
     *   let the metered call's own 402 raise the wall if there is one.
     * - Nor for someone we couldn't identify. No session is "couldn't ask",
     *   NOT "no plan": `AccountStatus.load` answers a signed-out read with
     *   its empty snapshot, which reads as an account holding nothing and
     *   paywalled the tap (found by 5.13; iOS returns nil there).
     */
    internal suspend fun decide(
        cached: AccountStatus?, signedIn: Boolean,
        load: suspend () -> AccountStatus?,
    ): Pair<Boolean, AccountStatus?> {
        if (cached?.needsSubscription == false) return true to null
        if (!signedIn) return true to null
        val fresh = load() ?: return true to null
        return !fresh.needsSubscription to fresh
    }

    private suspend fun proceed(purpose: VoiceRevival.Purpose, action: () -> Unit): Boolean {
        if (!VoiceRevival.ensureVoice(purpose)) return false
        action()
        return true
    }
}
