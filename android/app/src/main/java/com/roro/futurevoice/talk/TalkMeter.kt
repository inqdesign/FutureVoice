package com.roro.futurevoice.talk

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.EdgeError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Talk metering — the in-call timer IS the price, but only while the call is
 * actually a call. Port of `TalkMeter.swift`; the contract is
 * `docs/contracts/edge-api.md` § `/talk-tick` and `behavior.md` § 8.
 *
 * While a call is active this ticks the `talk-tick` Edge Function every
 * [TICK_SECONDS] of LIVE time; the server pools the seconds per period and
 * consumes them from the plan's allowance, or a free account's one-time
 * balance — 1 s of talking = 1 s. A 1-second preflight tick fires at call
 * start so a spent allowance surfaces BEFORE the greeting speaks (otherwise
 * every fresh session would carry a free first minute).
 *
 * **Idle time is not charged.** The meter polls [isBillable] once a second
 * and only accumulates the seconds it answers yes to; the predicate lives in
 * the caller because only the call screen knows what "something is
 * happening" means (`TalkViewModel.isBillableMoment`). Unset → everything
 * counts, the safe default for a surface that hasn't been taught the
 * difference. This is also what keeps Plus's uncapped talking honest: the
 * ceiling there is the learner's effort, and effort is only a limiter while
 * the meter charges for SPEECH.
 *
 * Failure policy is asymmetric on purpose:
 * - 402 → [onWallHit] with which wall it was — a free account's spent pool
 *   (paywall) or a subscriber's finished allowance (never a paywall).
 * - Anything else → skip the tick and keep talking. A call must never drop
 *   over billing plumbing; the server's chars-per-minute floor on turn TTS
 *   bounds what unbilled seconds can cost.
 */
class TalkMeter(
    private val auth: AuthRepository,
    private val scope: CoroutineScope,
) {
    /** Polled once a second: is this second part of the conversation? */
    var isBillable: (() -> Boolean)? = null

    /** Fired once when the server says the talking is over (402). */
    var onWallHit: ((EdgeError) -> Unit)? = null

    private val _minutesRemaining = MutableStateFlow<Int?>(null)
    /**
     * Whole minutes this account can still speak (floor) — the allowance
     * remainder for subscribers, the balance for free accounts. Null until the
     * first tick lands; null stays null on Plus, where nothing counts down.
     */
    val minutesRemaining: StateFlow<Int?> = _minutesRemaining.asStateFlow()

    private var job: Job? = null
    private var sessionKey = ""
    private var language = "en"

    fun start(sessionId: String, language: String) {
        stop()
        sessionKey = sessionId
        this.language = language.lowercase()
        job = scope.launch {
            // Preflight before the first sleep — see class comment.
            tick(seconds = 1, label = "pre")
            var live = 0.0            // billable seconds not yet sent
            var i = 0
            var lastPoll = System.currentTimeMillis()
            while (isActive) {
                delay((POLL_SECONDS * 1000).toLong())
                if (!isActive) break
                val now = System.currentTimeMillis()
                val elapsed = minOf((now - lastPoll) / 1000.0, MAX_SECONDS_PER_POLL)
                lastPoll = now
                if (!(isBillable?.invoke() ?: true)) continue
                live += elapsed
                if (live < TICK_SECONDS) continue
                live -= TICK_SECONDS
                tick(seconds = TICK_SECONDS, label = i.toString())
                i += 1
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    @Serializable
    private data class TickBody(
        val seconds: Int,
        @SerialName("session_id") val sessionId: String,
        /**
         * Which language was SPOKEN. Billing ignores it — the allowance is per
         * account — but the Core is one club per language and this is the only
         * place the server ever learns which one a call belongs to.
         */
        val language: String,
    )

    @Serializable
    private data class TickResponse(
        val balance: Int = 0,
        val charged: Int = 0,
        @SerialName("seconds_today") val secondsToday: Int = 0,
        @SerialName("daily_cap") val dailyCap: Int? = null,
    )

    private suspend fun tick(seconds: Int, label: String) {
        val request = try {
            Request.Builder()
                .url(Config.functionUrl("talk-tick"))
                .header("Authorization", "Bearer ${auth.accessToken()}")
                // One key per tick: a retried request can't double-bill.
                .header("X-Idempotency-Key", "tick:$sessionKey:$label")
                .post(
                    Edge.json.encodeToString(
                        TickBody.serializer(),
                        TickBody(seconds, sessionKey, language),
                    ).toRequestBody("application/json".toMediaType())
                )
                .build()
        } catch (_: Exception) {
            return // no session yet — the next tick will have one
        }

        val outcome = withContext(Dispatchers.IO) {
            runCatching {
                Edge.client.newCall(request).execute().use { resp ->
                    val body = resp.body.string()
                    when {
                        resp.isSuccessful -> Edge.json.decodeFromString(TickResponse.serializer(), body)
                        resp.code == 402 -> throw EdgeError.wall(body)
                        else -> throw EdgeError.Http(resp.code, body.take(512))
                    }
                }
            }
        }

        outcome.onSuccess { res ->
            // Subscriber: what's left of the allowance. Free account: the
            // seconds balance. Both already in seconds.
            //
            // A plan with NO ceiling (Plus) answers with no cap AND nothing
            // charged — covered by the plan, not the balance. Nothing counts
            // down there, so the figure stays null (see the property doc);
            // falling through to `balance` showed the leftover free pool as
            // "0 min left" in the call title.
            _minutesRemaining.value =
                if (res.dailyCap == null && res.charged == 0) null
                else {
                    val secondsLeft = res.dailyCap?.let { maxOf(0, it - res.secondsToday) }
                        ?: maxOf(0, res.balance)
                    secondsLeft / 60
                }
        }.onFailure { e ->
            if (e is EdgeError.InsufficientCredits || e is EdgeError.DailyCapReached) {
                stop()
                _minutesRemaining.value = 0
                onWallHit?.invoke(e)
            }
            // Transient failure: skip this tick. The idempotency key was unique
            // to it, so nothing double-bills when the next one lands.
        }
    }

    companion object {
        const val TICK_SECONDS = 30

        /**
         * How long after the learner's last voiced frame still counts as them
         * talking. Must cover the longest end-of-turn wait (`VAD_LONG_SECONDS`
         * + the STT settle) or the meter would stop mid-turn while the app is
         * still deciding the learner finished.
         */
        const val VOICE_GRACE_SECONDS = 6.0

        /**
         * Poll cadence, and the ceiling on what one poll may contribute. The
         * clamp matters because a suspended app resumes with a huge gap on the
         * clock — without it, a phone that sat in a pocket for ten minutes
         * would bill all ten on its first poll back.
         */
        private const val POLL_SECONDS = 1.0
        private const val MAX_SECONDS_PER_POLL = 2.0
    }
}
