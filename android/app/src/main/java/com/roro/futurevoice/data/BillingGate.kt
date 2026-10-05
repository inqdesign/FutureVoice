package com.roro.futurevoice.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

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
 * - **It gates on [AccountStatus.needsSubscription] ONLY** — plus, for a
 *   tap that writes a scene, a FREE account's spent free scenes
 *   ([AccountStatus.freeScenesSpent]). A spent PLAN allowance is not this — that learner already paid, and the client's copy of the
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

    /** The tier the next paywall opens on, when its opener named one — the
     *  spent sheet's "Move to Max" must not land on the plan already held
     *  (iOS `PaywallView(preselectTier:)`). The paywall consumes it. */
    val paywallTier = MutableStateFlow<String?>(null)

    @Volatile private var cached: AccountStatus? = null
    @Volatile private var fetchedAt: Long? = null
    @Volatile private var refreshing = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** How long a cached answer is FRESH (iOS `freshFor`). Short — it decides
     *  whether someone gets to talk. Past it, a yes is still answered from
     *  cache, and re-read behind the tap. */
    internal const val FRESH_FOR_MS = 60_000L

    /** The cached account, for gates that read the TIER (iOS `account`). */
    val account: AccountStatus? get() = cached

    /** Fold in a status someone else just loaded (Me, a purchase result). */
    fun remember(status: AccountStatus) {
        cached = status
        fetchedAt = System.currentTimeMillis()
    }

    fun invalidate() {
        cached = null
        fetchedAt = null
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
        val scene = purpose == VoiceRevival.Purpose.SCENE
        val now = System.currentTimeMillis()
        if (refreshBehind(cached, scene, fetchedAt, now)) refreshInBackground(auth)
        val (go, fresh) = decide(cached, signedIn = auth.userId != null, scene = scene) {
            runCatching { AccountStatus.load(auth) }.getOrNull()
        }
        if (fresh != null) remember(fresh)
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
     *
     * [scene] is iOS `blocksScene`: a tap about to WRITE a Watch scene is
     * also refused for a free account that has had its free scenes
     * ([AccountStatus.freeScenesSpent]) — it can still talk off its balance,
     * but the server would refuse the scene after it was written. Same cache
     * rule.
     */
    internal suspend fun decide(
        cached: AccountStatus?, signedIn: Boolean, scene: Boolean = false,
        load: suspend () -> AccountStatus?,
    ): Pair<Boolean, AccountStatus?> {
        if (cached != null && allows(cached, scene)) return true to null
        if (!signedIn) return true to null
        val fresh = load() ?: return true to null
        return allows(fresh, scene) to fresh
    }

    private fun allows(status: AccountStatus, scene: Boolean): Boolean =
        !status.needsSubscription && !(scene && status.freeScenesSpent)

    /**
     * iOS `blocks` → `refreshIfStale`: a cached YES is still the instant
     * answer, but once it is older than [FRESH_FOR_MS] it is re-read behind
     * the tap, so a pool spent on another device reaches the next tap
     * instead of waiting for an [invalidate]. Never for a cached no — that is
     * re-read in front of the tap anyway.
     */
    internal fun refreshBehind(cached: AccountStatus?, scene: Boolean,
                               fetchedAt: Long?, now: Long): Boolean {
        if (cached == null || !allows(cached, scene)) return false
        return fetchedAt == null || now - fetchedAt >= FRESH_FOR_MS
    }

    private fun refreshInBackground(auth: AuthRepository) {
        if (refreshing || auth.userId == null) return
        refreshing = true
        scope.launch {
            try {
                runCatching { AccountStatus.load(auth) }.getOrNull()?.let { remember(it) }
            } finally { refreshing = false }
        }
    }

    private suspend fun proceed(purpose: VoiceRevival.Purpose, action: () -> Unit): Boolean {
        if (!VoiceRevival.ensureVoice(purpose)) return false
        action()
        return true
    }
}
