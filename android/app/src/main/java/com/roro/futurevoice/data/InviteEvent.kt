package com.roro.futurevoice.data

import android.app.Activity
import android.content.Context
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The friend-invite event (iOS `InviteEvent.swift`, 2026-11-19): a friend who
 * subscribes makes the next month half price for both.
 *
 * Nothing about it is compiled in. The size (percent, months), whether it is
 * on, which store offer carries it and EVERY WORD on its banner, sheets and
 * share message come from the server (`invite_event_state`), so the founder
 * changes any of it without a build. A fetch that fails, or an event that is
 * off, draws nothing at all.
 */
data class InviteEventState(
    val enabled: Boolean = false,
    val percent: Int = 50,
    val months: Int = 1,
    val announceVersion: Int = 0,
    /** language -> key -> text. */
    val texts: Map<String, Map<String, String>> = emptyMap(),
    val canInvite: Boolean = false,
    val code: String? = null,
    val invited: Boolean = false,
    val store: String? = null,
    val googleProductId: String? = null,
    val googleOfferId: String? = null,
    val renewsAt: Instant? = null,
    /** The reward that can be taken now (its uuid), if any. */
    val claimable: String? = null,
    val rewards: List<Reward> = emptyList(),
) {
    data class Reward(val id: String, val role: String, val status: String,
                      val percent: Int, val months: Int)

    companion object {
        val off = InviteEventState()

        /**
         * Lenient on purpose: an event that is off answers `{enabled: false}`
         * and nothing else, and a field added later (or one of the wrong
         * type) must not blank the banner. Every field is read on its own.
         */
        fun decode(raw: String): InviteEventState {
            val o = runCatching { Edge.json.parseToJsonElement(raw) as? JsonObject }.getOrNull()
                ?: return off
            return InviteEventState(
                enabled = o.bool("enabled") ?: false,
                percent = o.int("percent") ?: 50,
                months = o.int("months") ?: 1,
                announceVersion = o.int("announce_version") ?: 0,
                texts = texts(o["texts"]),
                canInvite = o.bool("can_invite") ?: false,
                code = o.string("code"),
                invited = o.bool("invited") ?: false,
                store = o.string("store"),
                googleProductId = o.string("google_product_id"),
                googleOfferId = o.string("google_offer_id"),
                renewsAt = o.string("renews_at")?.let(::date),
                claimable = o.string("claimable"),
                rewards = (o["rewards"] as? JsonArray).orEmpty().mapNotNull { r ->
                    val row = r as? JsonObject ?: return@mapNotNull null
                    Reward(
                        id = row.string("id") ?: return@mapNotNull null,
                        role = row.string("role") ?: return@mapNotNull null,
                        status = row.string("status") ?: return@mapNotNull null,
                        percent = row.int("percent") ?: return@mapNotNull null,
                        months = row.int("months") ?: return@mapNotNull null,
                    )
                },
            )
        }

        fun texts(element: JsonElement?): Map<String, Map<String, String>> =
            (element as? JsonObject).orEmpty().mapNotNull { (language, lines) ->
                val table = (lines as? JsonObject ?: return@mapNotNull null).mapNotNull { (key, value) ->
                    (value as? JsonPrimitive)?.takeIf { it.isString }?.let { key to it.content }
                }.toMap()
                language to table
            }.toMap()

        private fun JsonObject.string(key: String): String? =
            (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content
        private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
        private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull

        private fun date(raw: String): Instant? =
            runCatching { OffsetDateTime.parse(raw).toInstant() }.getOrNull()
                ?: runCatching { Instant.parse(raw) }.getOrNull()
    }
}

object InviteEvent {

    /** Where this account stands, which decides what the banner says. */
    sealed interface Phase {
        /** Nothing to draw: the event is off or could not be read. */
        data object Off : Phase
        /** A half-price month is waiting for the subscriber's own yes (Play
         *  asks them, in its own sheet). */
        data object Claim : Phase
        /** A half-price month is on its way: taken here, or applied by the
         *  web store with no tap. */
        data class Applied(val auto: Boolean) : Phase
        /** Came through a friend's invite, not subscribed yet. */
        data object Invited : Phase
        /** A subscriber who can invite. */
        data object Invite : Phase
        /** No plan yet: the offer is read first, subscribing is the button. */
        data object NeedsPlan : Phase
    }

    private val _state = MutableStateFlow(InviteEventState.off)
    val state: StateFlow<InviteEventState> = _state

    /** The discounted and the regular price of the claimable month, as Play
     *  prints them. Null where the store has not answered. */
    private val _offerPrice = MutableStateFlow<String?>(null)
    val offerPrice: StateFlow<String?> = _offerPrice
    private val _fullPrice = MutableStateFlow<String?>(null)
    val fullPrice: StateFlow<String?> = _fullPrice

    private val _claiming = MutableStateFlow(false)
    val claiming: StateFlow<Boolean> = _claiming
    private val _claimError = MutableStateFlow<String?>(null)
    val claimError: StateFlow<String?> = _claimError

    /** Bumped by `futurevoice://invite`: a tap that always opens a sheet
     *  (iOS `offerInviteEvent(asked: true)`). */
    val asked = MutableStateFlow(0)

    private const val SEEN_ANNOUNCE = "futurevoice.inviteEvent.seenAnnounce"
    private const val OFFERED_CLAIM = "futurevoice.inviteEvent.offeredClaim"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var priceWatch: Job? = null

    fun phase(state: InviteEventState): Phase {
        if (!state.enabled) return Phase.Off
        if (state.claimable != null) {
            // Only a Play subscription can be taken from here. A web
            // subscriber's month is applied by the server; one bought on
            // another store is taken in that store's app.
            if (state.store == "google" && state.googleOfferId != null) return Phase.Claim
        }
        if (state.rewards.any { it.status == "claimed" }) {
            return Phase.Applied(auto = state.store == "stripe")
        }
        if (state.invited && !state.canInvite) return Phase.Invited
        return if (state.canInvite) Phase.Invite else Phase.NeedsPlan
    }

    val phase: Phase get() = phase(_state.value)

    /** How many half-price months are still waiting behind the current one. */
    fun monthsWaiting(state: InviteEventState): Int = state.rewards.count { it.status == "ready" }

    /** The debug preview: a state made up on the spot, never fetched. A
     *  release build never gets here ([InviteEventDemo] checks first). */
    internal fun seedDemo(state: InviteEventState, offerPrice: String?, fullPrice: String?) {
        if (!BuildConfig.DEBUG) return
        _state.value = state
        _offerPrice.value = offerPrice
        _fullPrice.value = fullPrice
    }

    // ── Reading ──────────────────────────────────────────────────────────

    suspend fun refresh(context: Context) {
        // Developer → Preview invite event: the made-up state stays until it
        // is switched off, whatever the server says.
        if (InviteEventDemo.reseedIfHeld(context)) return
        val auth = AuthRepository()
        if (auth.userId == null) {
            _state.value = InviteEventState.off
            return
        }
        // A database without the event (an older server) or no network:
        // nothing is drawn, which is the same as the event being off.
        _state.value = withContext(Dispatchers.IO) {
            runCatching {
                val req = Request.Builder()
                    .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/invite_event_state")
                    .header("Authorization", "Bearer ${auth.accessToken()}")
                    .header("apikey", Config.supabaseAnonKey)
                    .post("{}".toRequestBody("application/json".toMediaType()))
                    .build()
                Edge.client.newCall(req).execute().use { resp ->
                    val raw = resp.body.string()
                    if (resp.code !in 200..299) InviteEventState.off else InviteEventState.decode(raw)
                }
            }.getOrDefault(InviteEventState.off)
        }
        loadPrices(context)
    }

    /** Before there is an account (the Welcome screen's code field): the
     *  event's size and words alone, which anyone may read. */
    suspend fun loadPublicIfNeeded(context: Context) {
        if (_state.value.enabled) return
        if (InviteEventDemo.reseedIfHeld(context)) return
        val row = withContext(Dispatchers.IO) {
            runCatching {
                val req = Request.Builder()
                    .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/invite_event" +
                        "?select=enabled,percent,months,texts&limit=1")
                    .header("Authorization", "Bearer ${Config.supabaseAnonKey}")
                    .header("apikey", Config.supabaseAnonKey)
                    .build()
                Edge.client.newCall(req).execute().use { resp ->
                    val raw = resp.body.string()
                    if (resp.code !in 200..299) null
                    else (Edge.json.parseToJsonElement(raw) as? JsonArray)?.firstOrNull() as? JsonObject
                }
            }.getOrNull()
        } ?: return
        // Strict where iOS's `Row` is: a row missing a field is no row.
        val enabled = (row["enabled"] as? JsonPrimitive)?.booleanOrNull ?: return
        val percent = (row["percent"] as? JsonPrimitive)?.intOrNull ?: return
        val months = (row["months"] as? JsonPrimitive)?.intOrNull ?: return
        if (row["texts"] !is JsonObject) return
        if (!enabled || _state.value.enabled) return
        // Announcing is the signed-in state's business.
        _state.value = InviteEventState(enabled = true, percent = percent, months = months,
            texts = InviteEventState.texts(row["texts"]), announceVersion = 0)
    }

    /**
     * {full} is the subscription's base plan as Play prices it; {price} is
     * the event offer's first pricing phase, when Play lists that offer on
     * the product. Either is null where Play has not answered, and then the
     * claim sheet draws no price row.
     */
    private fun loadPrices(context: Context) {
        if (InviteEventDemo.isHeld(context)) return
        val state = _state.value
        val productId = state.googleProductId
        if (productId == null) {
            _offerPrice.value = null
            _fullPrice.value = null
            return
        }
        val billing = BillingService.shared(context)
        // Play answers after the state does: price again whenever it has.
        if (priceWatch == null) {
            val app = context.applicationContext
            priceWatch = scope.launch { billing.offers.collect { loadPrices(app) } }
            return
        }
        val prices = billing.inviteOfferPrices(productId, state.googleOfferId)
        _fullPrice.value = prices.first
        _offerPrice.value = prices.second
    }

    // ── Words ────────────────────────────────────────────────────────────

    /** The app language: the one picked in setup, else the device's. */
    private fun language(context: Context): String =
        context.getSharedPreferences("futurevoice", 0).getString("futurevoice.nativeLanguage", null)
            ?: LanguageCatalog.defaultNative()

    /**
     * One of the event's lines in the app language, falling back to its base
     * language and then English, with its numbers filled in. Empty when the
     * server has no such line, and an empty line is not drawn.
     */
    fun text(context: Context, key: String, state: InviteEventState = _state.value,
             offerPrice: String? = _offerPrice.value, fullPrice: String? = _fullPrice.value): String {
        val language = language(context)
        val base = language.substringBefore('-').ifEmpty { "en" }
        // A line that names the store has a Play wording beside it
        // (`claim_body_google`); every other key has none and reads as is.
        fun line(k: String) = state.texts[language]?.get(k) ?: state.texts[base]?.get(k)
            ?: state.texts["en"]?.get(k)
        val raw = line(key + "_google") ?: line(key) ?: ""
        return raw
            .replace("{percent}", state.percent.toString())
            .replace("{months}", state.months.toString())
            .replace("{code}", state.code ?: "")
            .replace("{waiting}", monthsWaiting(state).toString())
            .replace("{price}", offerPrice ?: "")
            .replace("{full}", fullPrice ?: "")
            // Month and day only: the year is never in doubt a month ahead.
            .replace("{date}", state.renewsAt?.let { monthDay(it, language) } ?: "")
    }

    private fun monthDay(at: Instant, language: String): String {
        val locale = when (language) {
            "zh-Hant" -> Locale.forLanguageTag("zh-TW")
            else -> Locale.forLanguageTag(language)
        }
        val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd")
        return DateTimeFormatter.ofPattern(pattern, locale).format(at.atZone(ZoneId.systemDefault()))
    }

    fun shareMessage(context: Context): String = text(context, "share_message")

    // ── Shown once ───────────────────────────────────────────────────────

    private fun prefs(context: Context) = context.getSharedPreferences("futurevoice", 0)

    /** The announcement sheet is owed once per `announce_version`. */
    fun owesAnnouncement(context: Context): Boolean {
        val s = _state.value
        return s.enabled && s.announceVersion > prefs(context).getInt(SEEN_ANNOUNCE, 0)
    }

    fun markAnnounced(context: Context) {
        prefs(context).edit().putInt(SEEN_ANNOUNCE, _state.value.announceVersion).apply()
    }

    /** The claim sheet raises itself once per reward; after that the banner
     *  is the door. */
    fun owesClaimOffer(context: Context): Boolean {
        val id = _state.value.claimable ?: return false
        if (phase != Phase.Claim) return false
        return prefs(context).getString(OFFERED_CLAIM, null) != id
    }

    fun markClaimOffered(context: Context) {
        prefs(context).edit().putString(OFFERED_CLAIM, _state.value.claimable).apply()
    }

    // ── Taking the month (Play) ──────────────────────────────────────────

    /**
     * Play's own sheet asks for the yes: the billing flow for the
     * subscription the learner already holds, on the event's offer, with the
     * current period left alone. When the purchase lands, the server is told
     * (`invite_reward_claimed`) and the state is read again.
     *
     * NOT YET TRIED AGAINST PLAY: the server lists no Play offer today, so
     * [Phase.Claim] cannot be reached on a real account. [onTaken] runs once
     * the month is taken; a cancelled sheet changes nothing, and anything
     * else shows the server's `claim_failed` line.
     */
    fun claim(activity: Activity, onTaken: () -> Unit = {}) {
        if (_claiming.value) return
        val context = activity.applicationContext
        val state = _state.value
        val reward = state.claimable
        val productId = state.googleProductId
        val offerId = state.googleOfferId
        if (InviteEventDemo.isHeld(context)) return   // a made-up reward is never sent anywhere
        if (reward == null || productId == null || offerId == null) {
            _claimError.value = text(context, "claim_failed")
            return
        }
        _claiming.value = true
        _claimError.value = null
        BillingService.shared(context).claimInviteOffer(activity, productId, offerId) { outcome ->
            when (outcome) {
                BillingService.InviteClaimOutcome.OPENED ->
                    Analytics.capture("invite_reward_claim_opened", mapOf("store" to "google"))
                BillingService.InviteClaimOutcome.CANCELLED -> _claiming.value = false
                BillingService.InviteClaimOutcome.PURCHASED -> scope.launch {
                    val told = reportClaimed(reward)
                    refresh(context)
                    _claiming.value = false
                    if (told || phase != Phase.Claim) {
                        Analytics.capture("invite_reward_claimed", mapOf("store" to "google"))
                        onTaken()
                    } else {
                        _claimError.value = text(context, "claim_failed")
                        Analytics.capture("invite_reward_claim_failed", mapOf("error" to "not_recorded"))
                    }
                }
                else -> {
                    _claiming.value = false
                    _claimError.value = text(context, "claim_failed")
                    Analytics.capture("invite_reward_claim_failed",
                        mapOf("error" to outcome.name.lowercase()))
                }
            }
        }
    }

    fun clearClaimError() { _claimError.value = null }

    /** `invite_reward_claimed(p_id, p_store)`: true once the reward is marked. */
    private suspend fun reportClaimed(rewardId: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val auth = AuthRepository()
            val body = buildJsonObject {
                put("p_id", rewardId)
                put("p_store", "google")
            }.toString()
            val req = Request.Builder()
                .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/invite_reward_claimed")
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .post(body.toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(req).execute().use { resp ->
                resp.code in 200..299 && resp.body.string().trim() == "true"
            }
        }.getOrDefault(false)
    }
}
