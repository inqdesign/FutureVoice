package com.roro.futurevoice.data

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * The server's account/billing snapshot. The edge functions meter against
 * `user_credits` / `user_subscriptions`; the client only READS them for
 * display — **entitlement is never computed on-device**, and nothing here may
 * become the reason a call is allowed.
 */
data class AccountStatus(
    /** SECONDS of talk left in the one-time free pool. Not what entitles. */
    val secondsBalance: Int = 0,
    val planId: String? = null,
    /** 'trialing' | 'active' | 'grace' | 'expired' | 'inactive' */
    val subscriptionStatus: String = "inactive",
    /** Admin/test accounts: charged for real, auto-reset server-side. */
    val unlimited: Boolean = false,
    val secondsUsedPeriod: Int = 0,
    /**
     * The period's whole talk pool. **Null means one of two things**, and
     * [isEntitled] tells them apart: no plan at all, or an entitled plan with
     * NO talk ceiling (Plus — talking is bounded by the effort of speaking,
     * so a ceiling was doing no work). Watch is unaffected; the scene cap is
     * always set on a plan.
     */
    val monthlyCapSeconds: Int? = null,
    val scenesUsedPeriod: Int = 0,
    val monthlyScenesCap: Int? = null,
    /** When this billing period ends, `yyyy-MM-dd` from `talk_allowance`. */
    val periodEnd: String? = null,
    /** The plan is set to STOP at [periodEnd] rather than renew. A date on a
     *  billing surface says what will happen to the pool, and this decides
     *  which — "Refills on…" to someone who cancelled is the same date with
     *  the opposite promise. */
    val cancelAtPeriodEnd: Boolean = false,
) {
    val isEntitled: Boolean
        get() = subscriptionStatus in setOf("trialing", "active", "grace")

    val isTrialing: Boolean get() = subscriptionStatus == "trialing"

    /**
     * Signed up, no subscription, nothing left in the pool. Since the hard
     * paywall there is no free tier, so this account simply cannot talk yet.
     * (Cloning the voice and hearing it say hello stay free — they are the
     * entry ticket, not usage.)
     *
     * This is the ONLY thing the pre-tap gate may ask. A spent allowance is
     * NOT this: that learner already paid, and the client's copy of the
     * period's usage is stale often enough to refuse a call the server would
     * allow.
     */
    val needsSubscription: Boolean
        get() = !isEntitled && secondsBalance <= 0 && !unlimited

    /** Entitled on Light — the only tier with anything left to sell them. */
    val isLightPlan: Boolean
        get() = isEntitled && planId?.startsWith("light") == true

    val isPlusPlan: Boolean
        get() = isEntitled && planId?.startsWith("plus") == true

    companion object {
        @Serializable
        private data class CreditRow(val balance: Int = 0, val unlimited: Boolean = false)

        @Serializable
        private data class SubRow(
            val plan_id: String? = null,
            val status: String = "inactive",
            val cancel_at_period_end: Boolean? = null,
        )

        @Serializable
        private data class AllowanceRow(
            val used: Int = 0,
            val cap: Int? = null,
            val period_end: String? = null,
        )

        /**
         * Three reads, none of them decisive on their own. The pools come from
         * the same RPCs the METERS use rather than being recomputed from the
         * plan row: two implementations of the number the learner is shown can
         * only drift.
         */
        suspend fun load(auth: AuthRepository): AccountStatus = withContext(Dispatchers.IO) {
            val userId = auth.userId ?: return@withContext AccountStatus()
            var out = AccountStatus()

            table<CreditRow>(auth, "user_credits", "balance,unlimited", userId)
                ?.firstOrNull()?.let {
                    out = out.copy(secondsBalance = it.balance, unlimited = it.unlimited)
                }
            // Both columns have existed since the original subscriptions
            // migration, so naming them here can't fail the whole query.
            table<SubRow>(auth, "user_subscriptions",
                "plan_id,status,cancel_at_period_end", userId)
                ?.firstOrNull()?.let {
                    out = out.copy(planId = it.plan_id, subscriptionStatus = it.status,
                        cancelAtPeriodEnd = it.cancel_at_period_end == true)
                }
            rpc(auth, "talk_allowance")?.let {
                // A null cap on an entitled plan is "uncapped", not "no plan";
                // `used` is real either way.
                out = out.copy(secondsUsedPeriod = it.used, monthlyCapSeconds = it.cap,
                    periodEnd = it.period_end)
            }
            rpc(auth, "scene_allowance")?.let {
                out = out.copy(scenesUsedPeriod = it.used, monthlyScenesCap = it.cap)
            }
            out
        }

        private suspend inline fun <reified T> table(
            auth: AuthRepository, name: String, columns: String, userId: String,
        ): List<T>? = runCatching {
            val url = "${Config.supabaseUrl.trimEnd('/')}/rest/v1/$name" +
                "?select=$columns&user_id=eq.$userId&limit=1"
            val request = Request.Builder().url(url)
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                if (resp.code !in 200..299) return@use null
                Edge.json.decodeFromString(
                    ListSerializer(serializer<T>()), resp.body.string())
            }
        }.getOrNull()

        private suspend fun rpc(auth: AuthRepository, name: String): AllowanceRow? = runCatching {
            val request = Request.Builder()
                .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/$name")
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .post("{}".toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                if (resp.code !in 200..299) return@use null
                val raw = resp.body.string()
                // The RPC returns a single row; PostgREST may wrap it in an array.
                if (raw.trimStart().startsWith("[")) {
                    Edge.json.decodeFromString(
                        ListSerializer(AllowanceRow.serializer()), raw).firstOrNull()
                } else {
                    Edge.json.decodeFromString(AllowanceRow.serializer(), raw)
                }
            }
        }.getOrNull()

        @PublishedApi
        internal inline fun <reified T> serializer() =
            kotlinx.serialization.serializer<T>()
    }
}

/**
 * The period-end date, written in the language the APP is drawing in — the
 * caller passes the composition's locale rather than letting this reach for
 * the system's, which would print "Sep 14" inside an otherwise Korean
 * sentence.
 */
fun AccountStatus.renewalLabel(locale: java.util.Locale): String {
    val raw = periodEnd ?: return ""
    return runCatching {
        java.time.LocalDate.parse(raw.take(10))
            .format(java.time.format.DateTimeFormatter.ofPattern("MMM d", locale))
    }.getOrDefault("")
}
