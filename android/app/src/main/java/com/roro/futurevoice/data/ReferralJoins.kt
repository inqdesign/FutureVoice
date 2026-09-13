package com.roro.futurevoice.data

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.ReferralClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.Request

/**
 * Friends joining with my code — the inviter's side.
 *
 * There is no push infrastructure, so the app notices on foreground and
 * posts a LOCAL notification plus an in-app sheet. The learner gave someone a
 * code and then heard nothing back; the grant landed silently in a balance
 * they had no reason to look at.
 *
 * First run records the high-water mark WITHOUT announcing: a fresh install
 * must not replay every friend who ever joined.
 */
object ReferralJoins {
    data class Join(val id: String, val friendName: String?, val friendsJoined: Int, val totalJoined: Int, val minutesEarned: Int)

    private const val LAST_SEEN = "futurevoice.referral.lastSeenJoinAt"
    private const val CHANNEL_ID = "referral"

    private val _pending = MutableStateFlow<Join?>(null)
    val pending: StateFlow<Join?> = _pending
    fun dismiss() { _pending.value = null }

    @Serializable private data class JoinRow(val invitee_id: String = "", val created_at: String = "")
    @Serializable private data class NameRow(val display_name: String = "")

    suspend fun announce(context: Context) = withContext(Dispatchers.IO) {
        val auth = AuthRepository()
        val uid = auth.userId ?: return@withContext
        val token = runCatching { auth.accessToken() }.getOrNull() ?: return@withContext
        // The whole list, oldest first: a row's RANK decides whether it paid
        // (the server rewards the first N), and that can't be read off the
        // new rows alone.
        val rows = get(token, "referral_redemptions?select=invitee_id,created_at&inviter_id=eq.$uid&order=created_at.asc&limit=200", JoinRow.serializer())
        val newest = rows.lastOrNull()?.created_at ?: return@withContext
        val prefs = context.getSharedPreferences("futurevoice", 0)
        val lastSeen = prefs.getString(LAST_SEEN, null)
        prefs.edit().putString(LAST_SEEN, newest).apply()
        if (lastSeen == null) return@withContext   // first run: catch up silently
        // One source, one timestamp format — a string compare is a date compare.
        val fresh = rows.withIndex().filter { it.value.created_at > lastSeen }
        if (fresh.isEmpty()) return@withContext
        val paid = fresh.count { it.index < ReferralClient.REWARDED_INVITE_CAP }
        val minutes = paid * ReferralClient.bonusMinutes
        val name = if (fresh.size == 1) {
            get(token, "public_personas?select=display_name&owner_user_id=eq." + fresh[0].value.invitee_id.lowercase() + "&limit=1", NameRow.serializer())
                .firstOrNull()?.display_name?.takeIf { it.isNotBlank() }
        } else null
        val join = Join(fresh.last().value.invitee_id, name, fresh.size, rows.size, minutes)
        _pending.value = join
        post(context, body(context, join), join.id)
    }

    private fun body(c: Context, j: Join): String = when {
        j.minutesEarned == 0 && j.friendsJoined == 1 -> c.getString(R.string.a_friend_joined_with_your_code_b4caa9)
        j.minutesEarned == 0 -> c.getString(R.string.lld_friends_joined_with_your_code_636994, j.friendsJoined)
        j.friendName != null -> c.getString(R.string.joined_with_your_code_lld_minutes_are_yours, j.friendName, j.minutesEarned)
        j.friendsJoined == 1 -> c.getString(R.string.a_friend_joined_with_your_code_lld_minutes_are_yours, j.minutesEarned)
        else -> c.getString(R.string.lld_friends_joined_with_your_code_lld_minutes_are_yours, j.friendsJoined, j.minutesEarned)
    }

    /** Quiet by construction: no sound. The daily call is the habit anchor
     *  and must not be competed with. */
    private fun post(context: Context, body: String, id: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "nawana", NotificationManager.IMPORTANCE_DEFAULT).apply { setSound(null, null) })
        }
        val open = PendingIntent.getActivity(context, 0, Intent(context, com.roro.futurevoice.MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        runCatching {
            nm.notify(id.hashCode(), NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("nawana")
                .setContentText(body).setContentIntent(open).setSilent(true).setAutoCancel(true).build())
        }
    }

    private fun <T> get(token: String, path: String, ser: kotlinx.serialization.KSerializer<T>): List<T> = runCatching {
        val req = Request.Builder().url(Config.supabaseUrl.trimEnd('/') + "/rest/v1/" + path)
            .header("Authorization", "Bearer $token").header("apikey", Config.supabaseAnonKey).build()
        Edge.client.newCall(req).execute().use { r ->
            val raw = r.body.string()
            if (r.code !in 200..299) emptyList() else Edge.json.decodeFromString(ListSerializer(ser), raw)
        }
    }.getOrDefault(emptyList())
}
