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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.Request

/**
 * Someone took a seat in the Core — `CoreClubService.announceArrivals`.
 *
 * There is no push infrastructure, so this is the honest version: the app
 * notices on FOREGROUND and posts a quiet local notification. It arrives
 * late by design — when the learner next opens the app — which is fine while
 * the entry bar (30 consecutive days) keeps arrivals to a handful a week.
 * Wire push before that stops being true.
 *
 * Two rules the server already enforces and this must not undo: **arrivals
 * are public, departures are NOT** — the read policy filters `kind = 'left'`,
 * so nobody can work out whose seat they took — and the club's membership
 * LIST is never readable, only its events.
 */
object CoreArrivals {

    private const val PREFS = "futurevoice"
    private const val LAST_SEEN_KEY = "futurevoice.core.lastSeenEvent"
    private const val CHANNEL_ID = "core"

    @Serializable
    private data class Event(
        val id: Int = 0,
        val kind: String = "",
        val user_id: String? = null,
        val club_size: Int = 0,
        val first_time: Boolean = false,
    )

    /**
     * Poll once. Safe to call on every foreground: it reads a high-water mark
     * and announces nothing when there is nothing new.
     */
    suspend fun poll(context: Context, accessToken: String?, myUserId: String?) {
        val token = accessToken ?: return
        val prefs = context.getSharedPreferences(PREFS, 0)
        val lastSeen = prefs.getInt(LAST_SEEN_KEY, -1).takeIf { it >= 0 }

        val rows = fetch(token, lastSeen ?: 0)
        val newest = rows.maxOfOrNull { it.id } ?: return
        prefs.edit().putInt(LAST_SEEN_KEY, newest).apply()
        // First run records the mark WITHOUT announcing: a fresh install must
        // not dump the club's whole history onto the lock screen.
        if (lastSeen == null) return

        val me = myUserId?.lowercase()
        // A returning member slipping back into a seat is not an arrival, and
        // nobody gets told about their own.
        val arrivals = rows.filter {
            it.kind == "seated" && it.first_time && it.user_id?.lowercase() != me
        }
        rows.lastOrNull { it.kind == "club_full" }?.let {
            post(context, context.getString(R.string.the_core_is_full_all_lld_seats_taken, it.club_size),
                "core.full")
        }
        if (arrivals.isEmpty()) return

        // Coalesced: several arrivals in one poll are one line, not a pile.
        if (arrivals.size > 1) {
            val last = arrivals.last()
            post(context, context.getString(
                R.string.lld_new_members_joined_lld_seats_taken, arrivals.size, last.club_size),
                "core.arrivals.${last.id}")
            return
        }
        val one = arrivals.first()
        val name = displayName(token, one.user_id)
        val body = if (name != null) {
            context.getString(R.string.joined_the_core_lld_seats_taken, name, one.club_size)
        } else {
            context.getString(R.string.someone_joined_the_core_lld_seats_taken, one.club_size)
        }
        post(context, body, "core.arrival.${one.id}")
    }

    private suspend fun fetch(token: String, after: Int): List<Event> = withContext(Dispatchers.IO) {
        get(token, "core_events?select=id,kind,user_id,club_size,first_time" +
            "&kind=in.(seated,club_full)&id=gt.$after&order=id.asc&limit=200",
            Event.serializer())
    }

    /** The public pool is the only place a name may be read from — a member
     *  who never published an intro stays "someone". */
    @Serializable
    private data class Persona(val display_name: String = "")

    private suspend fun displayName(token: String, userId: String?): String? {
        val id = userId?.takeIf { it.isNotBlank() } ?: return null
        return withContext(Dispatchers.IO) {
            get(token, "public_personas?select=display_name&owner_user_id=eq.$id&limit=1",
                Persona.serializer())
                .firstOrNull()?.display_name?.takeIf { it.isNotBlank() }
        }
    }

    /** Quiet by construction: no sound. The daily call is the habit anchor
     *  and must not be competed with. */
    private fun post(context: Context, body: String, id: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "nawana", NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { setSound(null, null) })
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, com.roro.futurevoice.MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        runCatching {
            nm.notify(id.hashCode(), NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(context.getString(R.string.the_core))
                .setContentText(body)
                .setContentIntent(open)
                .setSilent(true)
                .setAutoCancel(true)
                .build())
        }
    }

    private fun <T> get(
        token: String,
        path: String,
        ser: kotlinx.serialization.KSerializer<T>,
    ): List<T> = runCatching {
        val req = Request.Builder()
            .url(Config.supabaseUrl.trimEnd('/') + "/rest/v1/" + path)
            .header("Authorization", "Bearer $token")
            .header("apikey", Config.supabaseAnonKey)
            .build()
        Edge.client.newCall(req).execute().use { r ->
            val raw = r.body.string()
            if (r.code !in 200..299) emptyList() else Edge.json.decodeFromString(ListSerializer(ser), raw)
        }
    }.getOrDefault(emptyList())
}
