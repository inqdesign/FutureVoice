package com.roro.futurevoice.data

import android.app.Activity
import android.content.Context
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
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
import okhttp3.Request

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

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val auth = AuthRepository()

    private val _offers = MutableStateFlow<List<Offer>>(emptyList())
    /** Empty = nothing to sell (no products yet, or Play unreachable). */
    val offers: StateFlow<List<Offer>> = _offers

    private val client: BillingClient = BillingClient.newBuilder(appContext)
        .setListener(this)
        .enablePendingPurchases()
        .build()

    fun refresh() {
        if (client.isReady) { scope.launch { query() }; return }
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    scope.launch { query() }
                } else {
                    Log.d(TAG, "billing unavailable: ${result.responseCode}")
                }
            }
            override fun onBillingServiceDisconnected() { /* refresh() reconnects */ }
        })
    }

    private suspend fun query() {
        val plans = fetchPlans().filter { it.is_active && !it.google_product_id.isNullOrBlank() }
        if (plans.isEmpty()) { Log.d(TAG, "no google products in catalog yet"); return }
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(plans.map {
                QueryProductDetailsParams.Product.newBuilder()
                    .setProductId(it.google_product_id!!)
                    .setProductType(BillingClient.ProductType.SUBS)
                    .build()
            })
            .build()
        client.queryProductDetailsAsync(params) { result, details ->
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

    fun purchase(activity: Activity, offer: Offer) {
        val userId = auth.userId ?: return
        val offerToken = offer.details.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: return
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

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        if (result.responseCode != BillingClient.BillingResponseCode.OK || purchases == null) return
        for (purchase in purchases) {
            if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) continue
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
}
