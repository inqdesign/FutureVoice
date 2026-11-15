package com.roro.futurevoice.net

import android.annotation.SuppressLint
import android.content.Context
import android.provider.Settings
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.MessageDigest

/**
 * The free minutes are once per PERSON (2026-11-15, founder decision,
 * `20261115180000_free_minutes_once_per_person`). Seen that day: a learner
 * deleted their account and signed up six more times in half an hour from one
 * phone, each time with a fresh 20 minutes.
 *
 * Once an account owns the session this sends a hash of ANDROID_ID — per app
 * signing key, survives a reinstall, changes on a factory reset — to
 * `report_signup_device`. The first account on a phone keeps its minutes; a
 * new account on a phone another account already used gets none. The raw id
 * never leaves the phone, and the server hashes the hash again.
 *
 * Once per account per install, remembered only after the server answered,
 * so an offline sign-in reports on the next launch.
 */
object SignupDevice {
    private const val PREFS = "signup_device"

    @SuppressLint("HardwareIds")
    private fun deviceHash(context: Context): String? {
        val id = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            ?.takeIf { it.isNotBlank() } ?: return null
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("nawana-device:$id".toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    suspend fun reportIfNeeded(context: Context, auth: AuthRepository) {
        if (auth.isAnonymous) return
        val uid = auth.userId ?: return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean(uid, false)) return
        val hash = deviceHash(context) ?: return
        runCatching {
            withContext(Dispatchers.IO) {
                val body = buildJsonObject { put("p_device", hash) }.toString()
                val request = Request.Builder()
                    .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/report_signup_device")
                    .header("Authorization", "Bearer ${auth.accessToken()}")
                    .header("apikey", Config.supabaseAnonKey)
                    .post(body.toRequestBody("application/json".toMediaType()))
                    .build()
                Edge.client.newCall(request).execute().use { resp ->
                    // 404 = the server doesn't have the function yet: ask again
                    // next launch rather than remembering a report never made.
                    if (resp.code in 200..299) prefs.edit().putBoolean(uid, true).apply()
                }
            }
        }
    }
}
