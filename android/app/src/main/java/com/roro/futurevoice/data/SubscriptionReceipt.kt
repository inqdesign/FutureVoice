package com.roro.futurevoice.data

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.Request
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Currency
import java.util.Locale

/**
 * The subscription as the STORE bills it — since when, the last charge, and
 * whether a launch code is still pricing it.
 *
 * It is deliberately its OWN read rather than more columns on
 * [AccountStatus]: everything here is a nicety, and a nicety must never be
 * able to cost the page the numbers it exists for. `user_subscriptions`
 * gained `started_at` after the allowance work, and naming a column the
 * database hasn't got fails the WHOLE query — folded into the account read,
 * one missing column would have left a subscriber looking like they had no
 * plan at all. Split like this, every failure degrades to "the section has
 * less to say".
 *
 * READ only. Changing or cancelling a live subscription happens in the store's
 * own screen; an in-app copy of it could only disagree with the store.
 */
data class SubscriptionReceipt(
    /** 'google' | 'apple' | 'stripe' | 'comp'. Null when there is no row. */
    val source: String? = null,
    /** When they first became a subscriber — survives renewals. */
    val startedAt: LocalDate? = null,
    /** The last amount actually charged, in the storefront's currency
     *  (milliunits: 9990 == 9.99). Null before the first charge lands, on a
     *  comp, and on any store whose webhook does not file transactions. */
    val lastChargeMilliunits: Long? = null,
    val lastChargeCurrency: String? = null,
    val lastChargeDate: LocalDate? = null,
    /** Apple's `offerType` on the LATEST transaction: 1 intro, 2 promotional,
     *  3 offer code. Null at full price. */
    val currentOfferType: Int? = null,
    /** First transaction priced by an offer code. The launch codes run
     *  [offerCodeMonths] from here. */
    val offerCodeSince: LocalDate? = null,
    /**
     * What will be charged NEXT, from the store's renewal information — a
     * different fact from what was charged last, and the only one that can
     * answer a trial ("nothing has been charged yet") or a price about to
     * change. Null until the store tells us: Google Play's notifications are
     * not wired yet (master plan 7.3), so a Play subscriber sees no such row
     * rather than a guess.
     */
    val renewalMilliunits: Long? = null,
    val renewalCurrency: String? = null,
) {
    /** The day the launch code's discount ends, when one is running. */
    val offerCodeUntil: LocalDate?
        get() = if (currentOfferType == 3) offerCodeSince?.plusMonths(offerCodeMonths) else null

    /** What the next charge will be, as money. */
    fun renewalLabel(locale: Locale): String? =
        money(renewalMilliunits, renewalCurrency, locale)

    /**
     * True when the next charge is NEWS: a trial (nothing has been charged,
     * so there is no last-charge row at all) or an amount about to change —
     * a launch code running out, a price rise — which nobody should meet on
     * their statement. On a steady subscription the figure is already on
     * screen as the last charge.
     */
    fun nextChargeIsNews(isTrialing: Boolean): Boolean {
        if (renewalMilliunits == null || renewalMilliunits <= 0) return false
        return isTrialing || renewalMilliunits != lastChargeMilliunits ||
            renewalCurrency != lastChargeCurrency
    }

    /** The last charge as money, in the language the app is drawing in. */
    fun lastChargeLabel(locale: Locale): String? =
        money(lastChargeMilliunits, lastChargeCurrency, locale)

    private fun money(milliunits: Long?, currencyCode: String?, locale: Locale): String? {
        val milli = milliunits?.takeIf { it > 0 } ?: return null
        val code = currencyCode ?: return null
        return runCatching {
            java.text.NumberFormat.getCurrencyInstance(locale).apply {
                currency = Currency.getInstance(code)
                // Stores charge whole units in most storefronts; the fraction
                // is only interesting where the currency actually has one.
                if (milli % 1000L == 0L) maximumFractionDigits = 0
            }.format(milli / 1000.0)
        }.getOrNull()
    }

    companion object {
        /**
         * How long the launch offer codes discount (docs/launch-billing.md §7:
         * 12 months on both `Beta50 … v2` offers). A store's transaction says
         * WHICH offer priced a period, not how many periods the offer runs,
         * so the length is ours to know.
         */
        const val offerCodeMonths = 12L

        @Serializable
        private data class SubRow(
            val source: String? = null,
            val started_at: String? = null,
        )

        @Serializable
        private data class RenewalRow(
            val renewal_price_milliunits: Long? = null,
            val renewal_currency: String? = null,
        )

        @Serializable
        private data class TxRow(
            val purchase_date: String? = null,
            val price_milliunits: Long? = null,
            val currency: String? = null,
            val offer_type: Int? = null,
        )

        /**
         * Best effort, three independent reads. Only called for an account the
         * server already said is entitled — there is no receipt otherwise.
         */
        suspend fun load(auth: AuthRepository): SubscriptionReceipt =
            withContext(Dispatchers.IO) {
                val userId = auth.userId ?: return@withContext SubscriptionReceipt()
                var out = SubscriptionReceipt()

                get<SubRow>(auth, "user_subscriptions", "source,started_at",
                    "user_id=eq.$userId&limit=1")?.firstOrNull()?.let {
                    out = out.copy(source = it.source, startedAt = day(it.started_at))
                }

                val tx = "purchase_date,price_milliunits,currency,offer_type"
                get<TxRow>(auth, "subscription_transactions", tx,
                    "user_id=eq.$userId&order=purchase_date.desc&limit=1")
                    ?.firstOrNull()?.let {
                        out = out.copy(
                            lastChargeMilliunits = it.price_milliunits,
                            lastChargeCurrency = it.currency,
                            lastChargeDate = day(it.purchase_date),
                            currentOfferType = it.offer_type,
                        )
                    }

                // A query of its OWN: a select naming a column the database
                // has not got fails the WHOLE query, and folding these in
                // beside the others would blank the section for anyone on a
                // build that shipped ahead of the migration.
                get<RenewalRow>(auth, "user_subscriptions",
                    "renewal_price_milliunits,renewal_currency",
                    "user_id=eq.$userId&limit=1")?.firstOrNull()?.let {
                        out = out.copy(renewalMilliunits = it.renewal_price_milliunits,
                            renewalCurrency = it.renewal_currency)
                    }

                if (out.currentOfferType == 3) {
                    get<TxRow>(auth, "subscription_transactions", tx,
                        "user_id=eq.$userId&offer_type=eq.3&order=purchase_date.asc&limit=1")
                        ?.firstOrNull()?.let { out = out.copy(offerCodeSince = day(it.purchase_date)) }
                }
                out
            }

        private suspend inline fun <reified T> get(
            auth: AuthRepository, table: String, columns: String, filter: String,
        ): List<T>? = runCatching {
            val url = "${Config.supabaseUrl.trimEnd('/')}/rest/v1/$table?select=$columns&$filter"
            val request = Request.Builder().url(url)
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                if (resp.code !in 200..299) return@use null
                Edge.json.decodeFromString(
                    ListSerializer(kotlinx.serialization.serializer<T>()), resp.body.string())
            }
        }.getOrNull()

        /** A `timestamptz` as PostgREST writes it, with or without a
         *  fractional second, reduced to the day it names. */
        private fun day(raw: String?): LocalDate? {
            val text = raw ?: return null
            return runCatching { OffsetDateTime.parse(text).toLocalDate() }
                .recoverCatching { LocalDate.parse(text.take(10)) }
                .getOrNull()
        }
    }
}

/**
 * A date with its YEAR, for facts that outlive the month — a refill date drops
 * the year because a refill is always within one, but "since" and "until"
 * do not. Written in the language the app is drawing in, never the device's.
 */
fun LocalDate.dayLabel(locale: Locale): String = runCatching {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "yMMMd")
    format(DateTimeFormatter.ofPattern(pattern, locale))
}.getOrDefault(toString())
