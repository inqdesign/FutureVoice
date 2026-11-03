package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * The one free recharge after the free minutes (2026-11-03, founder: the
 * trial continues, without a store trial; iOS `FreeRecharge`). The trial
 * report's last card offers "Recharge N min free" beside "Subscribe"; one
 * tap, once per account, and the learner talks on. The second wall meets
 * the plans.
 *
 * Both answers come from the server (`20261103150000_free_recharge`): the
 * amount is `billing_config.free_recharge_seconds`, and whether THIS account
 * may take it is decided where the grant is made. The button is drawn only
 * on a fresh `available`.
 */
object FreeRecharge {
    @Serializable
    data class Offer(val seconds: Int = 0, val available: Boolean = false, val reason: String? = null)

    @Serializable
    data class Claim(val applied: Boolean = false, val reason: String? = null,
                     val seconds: Int = 0, val balance: Int = 0)

    private suspend fun rpc(name: String): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/$name")
            .header("Authorization", "Bearer ${AuthRepository().accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .post("{}".toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            raw
        }
    }

    /** Null = couldn't ask (offline, signed out): the card shows Subscribe alone. */
    suspend fun offer(): Offer? = runCatching {
        Edge.json.decodeFromString(Offer.serializer(), rpc("free_recharge_offer"))
    }.getOrNull()

    /** Grants the recharge, or says why not (`applied = false`, `reason`). */
    suspend fun claim(): Claim =
        Edge.json.decodeFromString(Claim.serializer(), rpc("claim_free_recharge"))
}
