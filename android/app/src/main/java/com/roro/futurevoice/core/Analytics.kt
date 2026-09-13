package com.roro.futurevoice.core

import android.content.Context
import com.roro.futurevoice.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * Product analytics — the same PostHog project and the same event names as
 * iOS, so one funnel reads across both stores. Spoken to over the plain
 * capture API rather than an SDK: the app has nothing to autocapture.
 *
 * Privacy stance (keep it this way; it is what the store listings promise):
 *  - No ad identifiers, no session replay, no screen-view autocapture.
 *  - `distinct_id` is the Supabase user UUID — UPPERCASED, because iOS sends
 *    `uuidString` and a lowercase id would split one person into two.
 *    Anonymous (a per-install random id) until [identify] runs on sign-in.
 *  - DEBUG builds opt out, so local dev never pollutes the funnel.
 *
 * Fire-and-forget: a dropped event is never worth a wait or an error.
 */
object Analytics {
    /** PUBLIC, write-only client key — the same one iOS ships with. */
    private const val API_KEY = "phc_QFR0wEkAigOahZAlzW9wsYzAUGQEyuurF7PueVdsDoA"
    private const val HOST = "https://eu.i.posthog.com"
    private const val PREFS = "futurevoice"
    private const val ANON_KEY = "futurevoice.analytics.anonId"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val http = OkHttpClient.Builder().callTimeout(10, TimeUnit.SECONDS).build()
    @Volatile private var distinctId: String? = null
    private lateinit var appContext: Context

    fun start(context: Context) {
        appContext = context.applicationContext
        val p = appContext.getSharedPreferences(PREFS, 0)
        distinctId = p.getString(ANON_KEY, null) ?: UUID.randomUUID().toString().uppercase()
            .also { p.edit().putString(ANON_KEY, it).apply() }
    }

    private val enabled: Boolean get() = !BuildConfig.DEBUG && ::appContext.isInitialized

    fun identify(userId: String) {
        val id = userId.uppercase()
        val previous = distinctId
        distinctId = id
        if (!enabled || previous == id) return
        // The anonymous events before sign-in belong to this person.
        send("\$identify", buildJsonObject {
            put("\$anon_distinct_id", previous ?: id)
            put("\$set", buildJsonObject { put("product", "nawana"); put("platform", "android") })
        })
    }

    /** Drop identity so the next person on this phone isn't merged in. */
    fun reset() {
        val fresh = UUID.randomUUID().toString().uppercase()
        distinctId = fresh
        if (::appContext.isInitialized) {
            appContext.getSharedPreferences(PREFS, 0).edit().putString(ANON_KEY, fresh).apply()
        }
    }

    fun capture(event: String, props: Map<String, Any?> = emptyMap()) {
        if (!enabled) return
        send(event, buildJsonObject {
            put("product", "nawana"); put("platform", "android")
            put("app_version", BuildConfig.VERSION_NAME)
            for ((k, v) in props) when (v) {
                null -> Unit
                is Boolean -> put(k, v)
                is Number -> put(k, v)
                else -> put(k, v.toString())
            }
        })
    }

    private fun send(event: String, properties: kotlinx.serialization.json.JsonObject) {
        val id = distinctId ?: return
        val body = buildJsonObject {
            put("api_key", API_KEY)
            put("event", event)
            put("distinct_id", id)
            put("timestamp", Instant.now().toString())
            put("properties", properties)
        }.toString()
        scope.launch {
            runCatching {
                http.newCall(Request.Builder().url("$HOST/capture/")
                    .post(body.toRequestBody("application/json".toMediaType())).build())
                    .execute().close()
            }
        }
    }
}
