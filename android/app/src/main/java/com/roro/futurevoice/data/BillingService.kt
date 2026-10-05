package com.roro.futurevoice.data

import android.app.Activity
import android.content.Context
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Play Billing — the `StoreKitService` twin, DORMANT until the owner's Play
 * Console setup (roadmap §4.4). Plans come from `subscription_plans` (the
 * same catalog iOS reads); a plan sells here only once its
 * `google_product_id` exists AND Play returns its ProductDetails. Until then
 * [products] stays empty and every purchase surface hides itself — the
 * client must never be one deploy-ordering mistake away from a broken
 * paywall (CLAUDE.md).
 *
 * Entitlement is written ONLY by `google-webhook` (the row IS the
 * entitlement); the client's whole job is the flow + acknowledge.
 * `obfuscatedAccountId` carries the Supabase user id — the appAccountToken
 * twin the webhook maps back.
 */
class BillingService private constructor(context: Context) : PurchasesUpdatedListener {

    companion object {
        private const val TAG = "BillingService"
        @Volatile private var instance: BillingService? = null
        fun shared(context: Context): BillingService =
            instance ?: synchronized(this) {
                instance ?: BillingService(context.applicationContext).also { instance = it }
            }
    }

    @Serializable
    data class Plan(
        val id: String,
        val tier: String = "",
        val period: String = "",
        val is_active: Boolean = true,
        val monthly_seconds: Long? = null,
        val monthly_scenes: Long? = null,
        val talk_unlimited: Boolean = false,
        /** Absent until the scaffold migration is pushed — decode leniently. */
        val google_product_id: String? = null,
    )

    data class Offer(val plan: Plan, val details: ProductDetails)

    /**
     * The one talk-minute pack on sale (iOS `TalkTopUpService.Pack`, master
     * plan 4.0). Same split as the plans: the catalog (`talk_topups`) says what
     * it GRANTS, Play says what it COSTS. [details] null = not buyable here (no
     * Play product, or a capture build's seeded row); [formattedPrice] null =
     * not priced, and then nothing is drawn for it.
     */
    data class Pack(
        val productId: String,
        val seconds: Int,
        val formattedPrice: String? = null,
        val priceMicros: Long = 0,
        val currency: String = "",
        val details: ProductDetails? = null,
    ) {
        val minutes: Int get() = seconds / 60
    }

    /** Where a pack purchase stands — one flow for every surface that sells it. */
    sealed class PackState {
        object Idle : PackState()
        object Purchasing : PackState()
        data class Purchased(val minutes: Int) : PackState()
        /** [message] is a string resource; the surface shows it under "Purchase failed". */
        data class Failed(val message: Int) : PackState()
    }

    @Serializable
    private data class TopUpRow(val google_product_id: String? = null, val seconds: Int = 0)

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val auth = AuthRepository()

    private val _offers = MutableStateFlow<List<Offer>>(emptyList())
    /** Plans Play has priced. Empty = no products yet, or Play unreachable. */
    val offers: StateFlow<List<Offer>> = _offers

    private val _plans = MutableStateFlow<List<Plan>>(emptyList())
    /**
     * The CATALOG, straight from Supabase and independent of Play.
     *
     * The paywall renders its sizes from this and attaches a price only where
     * a Play product matched, because the two can be missing for entirely
     * different reasons: Play may be unreachable on a device that can still
     * read the catalog perfectly well. Rendering the cards from `offers`
     * alone meant that device saw two plans whose only visible rows were the
     * free ones — an offer that reads as "both are unlimited everything".
     */
    val plans: StateFlow<List<Plan>> = _plans

    private val _settled = MutableStateFlow(false)
    /**
     * Play has been asked and has answered — with products or without.
     *
     * The paywall needs this to stop spinning: "no offers yet" and "still
     * loading" look identical from the outside, and a spinner that never
     * resolves says the app is broken when the truth is only that this device
     * cannot reach Play.
     */
    val settled: StateFlow<Boolean> = _settled

    private val _pack = MutableStateFlow<Pack?>(null)
    /** The pack, once both the catalog row and Play's price have answered. */
    val pack: StateFlow<Pack?> = _pack

    /**
     * A subscription bought through this app's flow just landed — what the
     * paywall answers with "You're in" (iOS `purchaseState == .purchased`).
     * [trialDays] is the free phase it was bought on, 0 for none: a trialer
     * is told the trial's own size, not the plan's.
     */
    data class Subscribed(val trialDays: Int)

    private val _subscribed = MutableStateFlow<Subscribed?>(null)
    val subscribed: StateFlow<Subscribed?> = _subscribed

    /** The paywall said it; the next purchase starts clean. */
    fun resetSubscribed() { _subscribed.value = null }

    private val _packState = MutableStateFlow<PackState>(PackState.Idle)
    val packState: StateFlow<PackState> = _packState

    /** Every pack id the catalog names — how a landed purchase is told from a
     *  subscription, since a [Purchase] does not carry its product type. */
    @Volatile private var packIds: Set<String> = emptySet()

    private val client: BillingClient = BillingClient.newBuilder(appContext)
        .setListener(this)
        .enablePendingPurchases()
        .build()

    fun refresh() {
        // The catalog does not need Play at all, and a device that cannot
        // reach Play must still be able to see what is on offer.
        scope.launch { _plans.value = fetchPlans().filter { it.is_active } }
        if (client.isReady) { scope.launch { query() }; scope.launch { queryPack() }; return }
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    scope.launch { query() }
                    scope.launch { queryPack() }
                    redeemUnconsumedPacks()
                } else {
                    Log.d(TAG, "billing unavailable: ${result.responseCode}")
                    _settled.value = true
                }
            }
            override fun onBillingServiceDisconnected() { /* refresh() reconnects */ }
        })
    }

    private suspend fun query() {
        val catalog = fetchPlans().filter { it.is_active }
        _plans.value = catalog
        val plans = catalog.filter { !it.google_product_id.isNullOrBlank() }
        if (plans.isEmpty()) {
            Log.d(TAG, "no google products in catalog yet")
            _settled.value = true
            return
        }
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(plans.map {
                QueryProductDetailsParams.Product.newBuilder()
                    .setProductId(it.google_product_id!!)
                    .setProductType(BillingClient.ProductType.SUBS)
                    .build()
            })
            .build()
        client.queryProductDetailsAsync(params) { result, details ->
            _settled.value = true
            if (result.responseCode != BillingClient.BillingResponseCode.OK) return@queryProductDetailsAsync
            _offers.value = details.mapNotNull { d ->
                plans.firstOrNull { it.google_product_id == d.productId }?.let { Offer(it, d) }
            }
            Log.d(TAG, "offers: ${_offers.value.size}")
        }
    }

    /** The same catalog iOS reads; `select=*` so a not-yet-pushed column can't fail the query. */
    private suspend fun fetchPlans(): List<Plan> = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/subscription_plans?select=*&is_active=eq.true")
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                if (resp.code !in 200..299) return@use emptyList()
                Edge.json.decodeFromString(ListSerializer(Plan.serializer()), resp.body.string())
            }
        }.getOrElse { emptyList() }
    }

    /** How many free days the chosen offer carries, 0 if none. A trial is a
     *  pricing phase priced at zero; Play states its length as ISO-8601. */
    private fun trialDays(offer: Offer): Int {
        val phase = offer.details.subscriptionOfferDetails?.firstOrNull()
            ?.pricingPhases?.pricingPhaseList?.firstOrNull { it.priceAmountMicros == 0L } ?: return 0
        val p = phase.billingPeriod
        val n = p.filter { it.isDigit() }.toIntOrNull() ?: return 0
        return when {
            p.endsWith("D") -> n
            p.endsWith("W") -> n * 7
            p.endsWith("M") -> n * 30
            p.endsWith("Y") -> n * 365
            else -> 0
        }
    }

    /** Set at the flow, read when the purchase lands — the callback carries
     *  the purchase, never the offer it was bought on. */
    private var pendingTrialDays = 0

    fun purchase(activity: Activity, offer: Offer) {
        val userId = auth.userId ?: return
        val offerToken = offer.details.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: return
        pendingTrialDays = trialDays(offer)
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(
                BillingFlowParams.ProductDetailsParams.newBuilder()
                    .setProductDetails(offer.details)
                    .setOfferToken(offerToken)
                    .build()))
            // The webhook's user mapping — the appAccountToken twin.
            .setObfuscatedAccountId(userId)
            .build()
        client.launchBillingFlow(activity, params)
    }

    /**
     * Move an existing PLAY subscriber to [offer] — never a second purchase
     * ([PlanChange] says why, and which [replacement] matches Apple).
     *
     * The old purchase token is read from Play itself (`queryPurchasesAsync`),
     * not from our row: it is the token THIS Google account holds, and Play
     * refuses a change that names any other. Preference goes to the purchase
     * whose product is the held plan's; with exactly one live subscription it
     * is that one. When the device holds none (a different Google account on
     * this phone, or Play unreachable) [onNoPurchase] runs — the caller opens
     * Play's subscriptions page rather than starting a fresh purchase, which
     * is the duplicate this path exists to prevent.
     */
    fun changePlan(
        activity: Activity,
        offer: Offer,
        currentPlanId: String?,
        replacement: PlanChange.Replacement,
        onNoPurchase: () -> Unit,
    ) {
        val userId = auth.userId ?: return
        val offerToken = offer.details.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: return
        if (!client.isReady) { onNoPurchase(); return }
        val heldProduct = _plans.value.firstOrNull { it.id == currentPlanId }?.google_product_id
        client.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.SUBS).build()
        ) { result, purchases ->
            val live = if (result.responseCode == BillingClient.BillingResponseCode.OK)
                purchases.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            else emptyList()
            val old = live.firstOrNull { heldProduct != null && heldProduct in it.products }
                ?: live.singleOrNull()
            scope.launch {
                if (old == null) { onNoPurchase(); return@launch }
                // A deferred downgrade has no trial phase to promise.
                pendingTrialDays = 0
                val mode = when (replacement) {
                    PlanChange.Replacement.CHARGE_PRORATED_PRICE ->
                        BillingFlowParams.SubscriptionUpdateParams.ReplacementMode.CHARGE_PRORATED_PRICE
                    PlanChange.Replacement.DEFERRED ->
                        BillingFlowParams.SubscriptionUpdateParams.ReplacementMode.DEFERRED
                }
                val params = BillingFlowParams.newBuilder()
                    .setProductDetailsParamsList(listOf(
                        BillingFlowParams.ProductDetailsParams.newBuilder()
                            .setProductDetails(offer.details)
                            .setOfferToken(offerToken)
                            .build()))
                    .setSubscriptionUpdateParams(
                        BillingFlowParams.SubscriptionUpdateParams.newBuilder()
                            .setOldPurchaseToken(old.purchaseToken)
                            .setSubscriptionReplacementMode(mode)
                            .build())
                    // Same account mapping as a purchase: the new token's
                    // notification must land on the same user row.
                    .setObfuscatedAccountId(userId)
                    .build()
                client.launchBillingFlow(activity, params)
            }
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        if (result.responseCode != BillingClient.BillingResponseCode.OK || purchases == null) {
            // The flow ended without a purchase. Only a pack flow has a state
            // to settle; a cancelled subscription flow changes nothing.
            if (_packState.value == PackState.Purchasing) {
                _packState.value =
                    if (result.responseCode == BillingClient.BillingResponseCode.USER_CANCELED) PackState.Idle
                    else PackState.Failed(com.roro.futurevoice.R.string.purchase_could_not_be_verified)
            }
            return
        }
        for (purchase in purchases) {
            if (purchase.products.any(::isPack)) {
                landPack(purchase, fromFlow = true)
                continue
            }
            if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) continue
            // What the account may spend just changed: the gate's cached
            // answer is stale, and a PARKED voice is re-read (iOS invalidate).
            BillingGate.invalidate()
            VoiceParking.requestRecheck(force = true)
            _subscribed.value = Subscribed(pendingTrialDays)
            // The promise the paywall makes about a trial is kept here.
            if (pendingTrialDays > 0) {
                TrialReminder.schedule(appContext, pendingTrialDays)
                pendingTrialDays = 0
            }
            // Entitlement arrives via google-webhook; the client only
            // acknowledges (unacknowledged purchases refund in 3 days).
            if (!purchase.isAcknowledged) {
                client.acknowledgePurchase(
                    AcknowledgePurchaseParams.newBuilder()
                        .setPurchaseToken(purchase.purchaseToken).build()) { ack ->
                    Log.d(TAG, "acknowledge: ${ack.responseCode}")
                }
            }
        }
    }

    // ── Talk-minute packs (consumables) ──────────────────────────────────

    private fun isPack(productId: String): Boolean =
        productId in packIds || productId.startsWith("talk_")

    /** The smallest active pack with a Google id, priced by Play — the iOS
     *  `TalkTopUpService.load` order, so both stores sell the same pack. */
    private suspend fun queryPack() {
        val rows = fetchTopUps()
        packIds = rows.mapNotNull { it.google_product_id }.toSet()
        val row = rows.firstOrNull { !it.google_product_id.isNullOrBlank() } ?: return
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(listOf(
                QueryProductDetailsParams.Product.newBuilder()
                    .setProductId(row.google_product_id!!)
                    .setProductType(BillingClient.ProductType.INAPP)
                    .build()))
            .build()
        client.queryProductDetailsAsync(params) { result, details ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) return@queryProductDetailsAsync
            val d = details.firstOrNull() ?: return@queryProductDetailsAsync
            val price = d.oneTimePurchaseOfferDetails ?: return@queryProductDetailsAsync
            _pack.value = Pack(row.google_product_id, row.seconds, price.formattedPrice,
                price.priceAmountMicros, price.priceCurrencyCode, d)
        }
    }

    private suspend fun fetchTopUps(): List<TopUpRow> = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/talk_topups" +
                    "?select=google_product_id,seconds&is_active=eq.true&order=seconds")
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                if (resp.code !in 200..299) return@use emptyList()
                Edge.json.decodeFromString(ListSerializer(TopUpRow.serializer()), resp.body.string())
            }
        }.getOrElse { emptyList() }
    }

    /** Buy the pack. The minutes land through [landPack] when Play answers. */
    fun buyPack(activity: Activity) {
        val pack = _pack.value
        val details = pack?.details
        if (details == null) {
            _packState.value = PackState.Failed(com.roro.futurevoice.R.string.purchase_could_not_be_verified)
            return
        }
        val userId = auth.userId ?: run {
            _packState.value = PackState.Failed(com.roro.futurevoice.R.string.you_need_to_be_signed_in_to_buy_minutes)
            return
        }
        _packState.value = PackState.Purchasing
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(
                BillingFlowParams.ProductDetailsParams.newBuilder()
                    .setProductDetails(details)
                    .build()))
            // `google-topup` refuses a token bought for another account.
            .setObfuscatedAccountId(userId)
            .build()
        client.launchBillingFlow(activity, params)
    }

    /** A surface showed the outcome; the next tap starts clean. */
    fun resetPackState() { _packState.value = PackState.Idle }

    /**
     * The `Transaction.updates` twin: a pack bought while the server was
     * unreachable is still unconsumed, and Play hands it back here on the next
     * launch. Landing it then is the whole retry — nothing else remembers it.
     */
    private fun redeemUnconsumedPacks() {
        client.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.INAPP).build()
        ) { result, purchases ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) return@queryPurchasesAsync
            purchases.filter { it.products.any(::isPack) }
                .forEach { landPack(it, fromFlow = false) }
        }
    }

    /**
     * Hands a pack purchase to `google-topup` and CONSUMES it only once the
     * server has it (`applied`, or already applied — a retry of a landed
     * purchase). A purchase the server could not take stays unconsumed: Play
     * re-offers it on the next launch, and if it can never land (refunded,
     * another account's), Play refunds an unacknowledged purchase on its own
     * after three days — the learner is never charged for minutes that did
     * not arrive.
     */
    private fun landPack(purchase: Purchase, fromFlow: Boolean) {
        when (purchase.purchaseState) {
            Purchase.PurchaseState.PENDING -> {
                if (fromFlow) _packState.value =
                    PackState.Failed(com.roro.futurevoice.R.string.purchase_is_pending_approval)
                return
            }
            Purchase.PurchaseState.PURCHASED -> Unit
            else -> return
        }
        val productId = purchase.products.first(::isPack)
        scope.launch {
            val seconds = redeem(purchase.purchaseToken, productId)
            if (seconds == null) {
                if (fromFlow) _packState.value = PackState.Failed(
                    com.roro.futurevoice.R.string.couldn_t_reach_the_server_your_minutes_will_be_added_the_nex_82ad46)
                return@launch
            }
            client.consumeAsync(
                ConsumeParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
            ) { r, _ -> Log.d(TAG, "consume: ${r.responseCode}") }
            // Minutes that just landed must be spendable on the next tap.
            BillingGate.invalidate()
            VoiceParking.requestRecheck(force = true)
            if (fromFlow) _packState.value = PackState.Purchased(seconds / 60)
        }
    }

    /** The seconds granted, or null when the server has not acknowledged it. */
    private suspend fun redeem(purchaseToken: String, productId: String): Int? = withContext(Dispatchers.IO) {
        runCatching {
            val body = buildJsonObject {
                put("purchaseToken", purchaseToken)
                put("productId", productId)
            }.toString()
            val request = Request.Builder()
                .url("${Config.supabaseUrl.trimEnd('/')}/functions/v1/google-topup")
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .post(body.toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                val raw = resp.body.string()
                if (resp.code !in 200..299) {
                    Log.d(TAG, "google-topup ${resp.code}: ${raw.take(200)}")
                    return@use null
                }
                val reply = Edge.json.decodeFromString(TopUpReply.serializer(), raw)
                val props = mapOf("applied" to if (reply.applied) "1" else "0",
                    "seconds" to reply.seconds.toString(), "product" to productId)
                com.roro.futurevoice.core.Telemetry.log("topup_landed", props)
                com.roro.futurevoice.core.Analytics.capture("topup_landed", props)
                reply.seconds
            }
        }.getOrNull()
    }

    @Serializable
    private data class TopUpReply(val applied: Boolean = false, val seconds: Int = 0, val balance: Int = 0)
}
