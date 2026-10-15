package com.roro.futurevoice.core

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * A message to the OWNER, on Telegram, while it is still happening — the
 * iOS `OwnerPing` twin, through the same `paywall-notify` function. The tap
 * that never becomes a charge is the one worth hearing about at the time.
 *
 * Same rules as iOS: never waited on (a detached job, the caller is a buy
 * button), never throws, a signed-out phone simply doesn't ping, and it
 * sends FACTS from a fixed vocabulary — the server writes the sentence and
 * caps how many it sends per account per day.
 *
 * `build` carries the platform ("android-7"): the server prints it as is in
 * the message's build line, so a ping says which store it came from with no
 * server change.
 */
object OwnerPing {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun paywall(
        phase: String,
        outcome: String? = null,
        plan: String,
        price: String? = null,
        trial: Boolean,
        source: String,
        step: String,
    ) {
        scope.launch {
            runCatching {
                val auth = AuthRepository()
                if (auth.userId == null) return@launch
                val body = buildJsonObject {
                    put("phase", phase)
                    outcome?.let { put("outcome", it) }
                    put("plan", plan)
                    put("source", source)
                    put("step", step)
                    put("trial", trial)
                    price?.let { put("price", it) }
                    put("build", "android-${com.roro.futurevoice.BuildConfig.VERSION_CODE}")
                    put("version", com.roro.futurevoice.BuildConfig.VERSION_NAME)
                }.toString()
                val request = Request.Builder()
                    .url("${Config.supabaseUrl.trimEnd('/')}/functions/v1/paywall-notify")
                    .header("Authorization", "Bearer ${auth.accessToken()}")
                    .header("apikey", Config.supabaseAnonKey)
                    .post(body.toRequestBody("application/json".toMediaType()))
                    .build()
                Edge.client.newCall(request).execute().close()
            }
        }
    }
}
