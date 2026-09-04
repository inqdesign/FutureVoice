package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import java.io.File

/**
 * Deleting a voice, and deleting an account.
 *
 * Both are one-way, so the ORDER is the whole design: the server side goes
 * first and the device is only erased once it succeeded. A local wipe that ran
 * first on a failed request would leave a learner with an account they can
 * still be billed for and no way left to reach it.
 *
 * Google Play requires an in-app path to account deletion for any app that
 * creates accounts, and GDPR Art. 7(3) requires withdrawing consent to be as
 * easy as giving it. Both land here.
 */
object AccountEraser {

    /**
     * Delete the voice model here and at ElevenLabs.
     *
     * A 403 ("not owned") or 404 means it is already gone upstream — that is a
     * success, not a failure, and retrying it forever would strand the
     * withdrawal on an error the learner cannot act on.
     */
    suspend fun deleteVoice(voiceId: String): Boolean = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(Config.functionUrl("elevenlabs-voice-delete"))
            .header("Authorization", "Bearer ${AuthRepository().accessToken()}")
            .post("""{"voice_id":"$voiceId"}""".toRequestBody("application/json".toMediaType()))
            .build()
        runCatching {
            Edge.client.newCall(req).execute().use { it.code in 200..299 || it.code == 403 || it.code == 404 }
        }.getOrDefault(false)
    }

    /**
     * Delete the account: the clone, the talk time, the auth user — then the
     * device. Throws if the server refused, in which case NOTHING local was
     * touched and the learner still has a working account.
     */
    suspend fun deleteAccount(context: Context) {
        withContext(Dispatchers.IO) {
            val req = Request.Builder()
                .url(Config.functionUrl("account-delete"))
                .header("Authorization", "Bearer ${AuthRepository().accessToken()}")
                .post("{}".toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(req).execute().use {
                require(it.code in 200..299) { "account-delete ${it.code}" }
            }
        }
        AuthRepository().signOut()
        wipeLocalData(context)
    }

    /**
     * Post-deletion local wipe — the device should look factory-fresh to
     * whoever signs in next. Every store file, every recording, and every
     * `futurevoice.*` preference, including the consent record: a warm age
     * flag would wave the next person straight past the gate.
     */
    fun wipeLocalData(context: Context) {
        context.filesDir.listFiles()?.forEach { it.deleteRecursively() }
        context.cacheDir.listFiles()?.forEach { it.deleteRecursively() }
        val p = context.getSharedPreferences("futurevoice", 0)
        val e = p.edit()
        p.all.keys.filter { it.startsWith("futurevoice.") }.forEach { e.remove(it) }
        e.apply()
        ConsentStore.reset(context)
        // Every store caches its own file handle, and the widgets are drawn
        // from a snapshot in the App Group that outlives the wipe.
        StoreEvents.bump()
        runCatching { File(context.filesDir, "lang").mkdirs() }
    }
}
