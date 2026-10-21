package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.Request

/**
 * The free offer as the server sets it (`public.billing_config`,
 * 20261021120000; iOS `BillingConfig`), so the founder can change it without
 * a build: how many free minutes a new account starts with (0 = none), and
 * where the store's free trial is offered when one is switched on
 * (`scripts/billing-switch.py`).
 *
 * Read on every resume and mirrored into prefs, so a launch with no network
 * is a launch behind rather than snapped back. The fallbacks ARE the offer as
 * it stood when this shipped.
 */
object BillingConfig {
    private const val PREFS = "futurevoice"
    private const val FREE_KEY = "futurevoice.billing.freeTalkSeconds"
    private const val OFFER_KEY = "futurevoice.billing.trialOfferAt"
    private const val OFFERED_KEY = "futurevoice.billing.onboardingTrialOffered"

    /** What a new account starts with: the ring's "full" for a free account
     *  and the trial report's "your first N minutes". */
    fun freeTalkSeconds(context: Context): Int =
        context.getSharedPreferences(PREFS, 0)
            .getInt(FREE_KEY, AccountStatus.FREE_GRANT_SECONDS)

    /** `after_free` (the plans when the free minutes run out) or `onboarding`
     *  (the trial once, right after onboarding). */
    fun trialOfferAt(context: Context): String =
        context.getSharedPreferences(PREFS, 0).getString(OFFER_KEY, null) ?: "after_free"

    @Serializable
    private data class Row(val free_talk_seconds: Int = 1200, val trial_offer_at: String = "after_free")

    /** Every resume. A failed read keeps what was mirrored last. */
    suspend fun refresh(context: Context) = withContext(Dispatchers.IO) {
        val row = runCatching {
            val req = Request.Builder()
                .url(Config.supabaseUrl.trimEnd('/') +
                    "/rest/v1/billing_config?select=free_talk_seconds,trial_offer_at&limit=1")
                .header("Authorization", "Bearer ${Config.supabaseAnonKey}")
                .header("apikey", Config.supabaseAnonKey).build()
            Edge.client.newCall(req).execute().use { r ->
                if (r.code !in 200..299) return@use null
                Edge.json.decodeFromString(ListSerializer(Row.serializer()), r.body.string()).firstOrNull()
            }
        }.getOrNull() ?: return@withContext
        val edit = context.getSharedPreferences(PREFS, 0).edit()
        if (row.free_talk_seconds in 0..36_000) edit.putInt(FREE_KEY, row.free_talk_seconds)
        // An unknown value from a newer server is dropped, not guessed at.
        if (row.trial_offer_at in setOf("after_free", "onboarding")) edit.putString(OFFER_KEY, row.trial_offer_at)
        edit.apply()
    }

    /**
     * Whether to offer the store's trial now, once, at the end of the
     * first-run sheets (iOS `onboardingTrialIsDue`): the setting says so, this
     * install hasn't been offered it, the account is under two days old and
     * has never subscribed, and Play really has a free phase on a plan.
     */
    suspend fun onboardingTrialIsDue(context: Context): Boolean {
        if (trialOfferAt(context) != "onboarding") return false
        val prefs = context.getSharedPreferences(PREFS, 0)
        if (prefs.getBoolean(OFFERED_KEY, false)) return false
        val auth = AuthRepository()
        if (auth.isAnonymous) return false
        val created = Supa.client.auth.currentUserOrNull()?.createdAt?.toEpochMilliseconds() ?: return false
        if (System.currentTimeMillis() - created > 2 * 86_400_000L) return false
        val account = runCatching { AccountStatus.load(auth) }.getOrNull() ?: return false
        if (!account.ownershipKnown || account.subscriptionStatus != "inactive" || account.unlimited) return false
        return BillingService.shared(context).offers.value.any { offer ->
            offer.details.subscriptionOfferDetails?.any { o ->
                o.pricingPhases.pricingPhaseList.any { it.priceAmountMicros == 0L }
            } == true
        }
    }

    fun markOnboardingTrialOffered(context: Context) {
        context.getSharedPreferences(PREFS, 0).edit().putBoolean(OFFERED_KEY, true).apply()
    }
}
