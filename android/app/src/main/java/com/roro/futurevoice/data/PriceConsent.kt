package com.roro.futurevoice.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.Request
import java.time.LocalDate
import java.time.OffsetDateTime

/**
 * The store is waiting on the learner's consent before it charges (iOS
 * `PriceConsent`, 2026-10-18).
 *
 * Korean law asks for a SECOND consent before a free trial or a discounted
 * offer turns into the regular price; on Play it has been collected in the
 * Play Store since 2026-02-03, and a subscription without it is cancelled
 * before the charge. Play cannot tell the app this on the device, so the fact
 * comes from the server: `google-webhook` reads
 * `priceStepUpConsentDetails` on every notification and keeps
 * `user_subscriptions.price_consent_*`.
 *
 * Only a Play subscription is ours to send to Play; an Apple one on this
 * phone is answered on the iPhone.
 */
object PriceConsent {
    data class Pending(val isTrial: Boolean, val dueOn: LocalDate?)

    private val _pending = MutableStateFlow<Pending?>(null)
    val pending: StateFlow<Pending?> = _pending

    /** The explanation sheet, raised by [offerIfDue] or a tap. */
    private val _showing = MutableStateFlow(false)
    val showing: StateFlow<Boolean> = _showing
    fun open() { _showing.value = true }
    fun dismiss() { _showing.value = false }

    private const val LAST_OFFERED = "futurevoice.priceConsent.lastOffered"

    @Serializable
    private data class Row(
        val source: String? = null,
        val status: String? = null,
        val price_consent_pending_since: String? = null,
        val price_consent_due_at: String? = null,
    )

    /** Reads the server's copy; on every resume. A query of its own, so a
     *  database without the columns costs this and nothing else. */
    suspend fun refresh(auth: AuthRepository = AuthRepository()) = withContext(Dispatchers.IO) {
        val uid = auth.userId ?: return@withContext
        val token = runCatching { auth.accessToken() }.getOrNull() ?: return@withContext
        val row = runCatching {
            val req = Request.Builder()
                .url(Config.supabaseUrl.trimEnd('/') + "/rest/v1/user_subscriptions" +
                    "?select=source,status,price_consent_pending_since,price_consent_due_at" +
                    "&user_id=eq.$uid&limit=1")
                .header("Authorization", "Bearer $token").header("apikey", Config.supabaseAnonKey).build()
            Edge.client.newCall(req).execute().use { r ->
                if (r.code !in 200..299) return@use null
                Edge.json.decodeFromString(ListSerializer(Row.serializer()), r.body.string()).firstOrNull()
            }
        }.getOrNull()
        _pending.value = row?.takeIf { it.source == "google" && it.price_consent_pending_since != null }
            ?.let { Pending(isTrial = it.status == "trialing", dueOn = day(it.price_consent_due_at)) }
        if (_pending.value == null) _showing.value = false
    }

    /** Raises the explanation by itself, at most once a day and never over a
     *  live call. The Me row opens it any time. */
    fun offerIfDue(context: Context) {
        if (_pending.value == null || _showing.value || DailyCallScheduler.isLiveCall) return
        val prefs = context.getSharedPreferences("futurevoice", 0)
        val today = LocalDate.now().toString()
        if (prefs.getString(LAST_OFFERED, null) == today) return
        prefs.edit().putString(LAST_OFFERED, today).apply()
        _showing.value = true
        Analytics.capture("price_consent_offered", mapOf("held" to "0"))
    }

    /** Play's subscription page, where the consent is waiting. */
    fun confirm(context: Context) {
        Analytics.capture("price_consent_confirm", mapOf("held" to "0"))
        val uri = Uri.parse("https://play.google.com/store/account/subscriptions?package=${context.packageName}")
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    private fun day(raw: String?): LocalDate? {
        val text = raw ?: return null
        return runCatching { OffsetDateTime.parse(text).toLocalDate() }
            .recoverCatching { LocalDate.parse(text.take(10)) }
            .getOrNull()
    }
}
