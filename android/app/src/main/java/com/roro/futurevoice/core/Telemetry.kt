package com.roro.futurevoice.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * Fire-and-forget breadcrumbs → `client_events` (write-only RLS), the same
 * table and the same event names iOS writes, so the admin console reads one
 * story across both stores.
 *
 * This is not analytics. [Analytics] is the funnel (PostHog, opted out in
 * debug); this is the record of what HAPPENED to a call, and the reason it
 * exists is that a talk can end for a dozen reasons without leaving a trace
 * anywhere: the reply and the voice go straight to their providers, so the
 * usage ledger sees only the meter's ticks. On 2026-09-12 that produced a
 * console reporting zero errors on a day when most sessions ended before the
 * learner finished a sentence.
 *
 * Never throws, never blocks the caller, silently drops when signed out — a
 * telemetry failure must not become a second user-facing failure. Debug
 * builds write too: these rows are how a device test is read afterwards.
 */
object Telemetry {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val http = OkHttpClient.Builder().callTimeout(10, TimeUnit.SECONDS).build()
    @Volatile private var appContext: Context? = null

    fun start(context: Context) { appContext = context.applicationContext }

    /**
     * How the learner has the call set up, stamped on every event (here and
     * on [Analytics.capture]) — iOS `Telemetry.callSettings`, `74585bf`.
     * Retention fell by self-reported level (A1 8% came back, B2+ 57%) and
     * nothing on the server could say whether the slower voice or coach mode
     * changed that. `speed` is the multiplier actually sent upstream,
     * `speed_picked` separates a learner who chose a rung from one who never
     * touched the default. Read per event, never registered once: both change
     * while the app runs. `coach` is coach mode as it resolves right now —
     * the learner's flip, else on for A1/A2 (`CoachMode.isOn`).
     */
    fun callSettings(context: Context): Map<String, String> = mapOf(
        "speed" to "%.2f".format(java.util.Locale.US,
            com.roro.futurevoice.data.SpeechSpeed.current(context).multiplier(context)),
        "speed_picked" to if (com.roro.futurevoice.data.SpeechSpeed.picked(context)) "1" else "0",
        "coach" to if (com.roro.futurevoice.talk.CoachMode.isOn(context)) "on" else "off",
    )

    fun log(event: String, properties: Map<String, String> = emptyMap()) {
        val context = appContext ?: return
        // Read now, not in the coroutine: the event describes the call as it
        // was set up at this moment.
        val settings = runCatching { callSettings(context) }.getOrDefault(emptyMap())
        scope.launch {
            runCatching {
                val auth = AuthRepository()
                val uid = auth.userId ?: return@runCatching
                val token = auth.accessToken()
                val row = buildJsonObject {
                    put("user_id", uid)
                    put("event", event)
                    put("properties", buildJsonObject {
                        // The caller's value wins over a setting of the same name.
                        settings.forEach { (k, v) -> put(k, v) }
                        properties.forEach { (k, v) -> put(k, v) }
                        put("network", network(context))
                        // Which build produced this. Without it every gap in
                        // server-side data is unfalsifiable: a missing meter
                        // row reads identically whether the meter is broken
                        // or the phone is on a build that predates it.
                        put("build", BuildConfig.VERSION_CODE.toString())
                        put("version", BuildConfig.VERSION_NAME)
                        put("platform", "android")
                    })
                }
                post(row, token)
            }
        }
    }

    private fun post(row: JsonObject, token: String) {
        val req = Request.Builder()
            .url(Config.supabaseUrl.trimEnd('/') + "/rest/v1/client_events")
            .header("Authorization", "Bearer $token")
            .header("apikey", Config.supabaseAnonKey)
            .header("Prefer", "return=minimal")
            .post(row.toString().toRequestBody("application/json".toMediaType()))
            .build()
        http.newCall(req).execute().close()
    }

    /** How the phone was connected when this happened — a dropped call on a
     *  train is a different story from one on Wi-Fi. */
    private fun network(context: Context): String {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return "unknown"
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "offline"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
    }
}
