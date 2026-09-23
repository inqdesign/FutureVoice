package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Config
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.Instant

/**
 * What the learner CHOSE in onboarding, mirrored to the server — port of
 * `LearnerSetupSync.swift`.
 *
 * `public.profiles` has carried `native_language` / `target_language` /
 * `proficiency` since the first migration and nothing has ever written them
 * from either platform: the row is inserted with `(id)` alone and the three
 * columns take their defaults. So every row read the same three values, and
 * the admin console could only say what somebody had SPOKEN, never what they
 * had picked — a learner who chose German and hadn't talked yet was
 * indistinguishable from an English learner.
 *
 * The choice happens before there is anywhere to put it (setup runs ahead of
 * the voice clone, and the session only opens at "use this voice"), so this
 * is written whenever a session and a completed setup exist at the same time
 * rather than at the moment of the tap.
 *
 * Silent on every failure: it is a reporting row, and nothing the learner
 * does may wait on it or fail because of it.
 */
object LearnerSetupSync {

    /** Skip the round trip when nothing has changed since the last push. */
    private const val LAST_KEY = "futurevoice.profileSync.last"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun push(context: Context, target: String, native: String, level: String, force: Boolean = false) {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences("futurevoice", 0)
        val stamp = "$target|$native|$level"
        if (!force && prefs.getString(LAST_KEY, null) == stamp) return
        scope.launch {
            runCatching {
                val auth = AuthRepository()
                val uid = auth.userId ?: return@runCatching
                val token = auth.accessToken()
                val now = Instant.now().toString()
                val row = buildJsonObject {
                    put("id", uid)
                    put("native_language", native)
                    put("target_language", target)
                    put("proficiency", level)
                    // What separates a real answer from the column default.
                    put("setup_at", now)
                    put("updated_at", now)
                }
                val req = Request.Builder()
                    .url(Config.supabaseUrl.trimEnd('/') + "/rest/v1/profiles?on_conflict=id")
                    .header("Authorization", "Bearer $token")
                    .header("apikey", Config.supabaseAnonKey)
                    // Upsert, not update: the trigger has already made the row
                    // for a signed-up account, but an anonymous session created
                    // before this shipped may not have one.
                    .header("Prefer", "resolution=merge-duplicates,return=minimal")
                    .post("[$row]".toRequestBody("application/json".toMediaType()))
                    .build()
                com.roro.futurevoice.net.Edge.client.newCall(req).execute().use { r ->
                    if (r.code in 200..299) prefs.edit().putString(LAST_KEY, stamp).apply()
                }
            }
        }
    }
}
