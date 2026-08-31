package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * The Core — one club PER TARGET LANGUAGE, 100 seats, a BAR and never a rank.
 *
 * Everything the client sees comes from `core_my_progress()`; the club's
 * daily activity view is revoked from clients, so this RPC is the only door
 * and it reads nobody else's days. Badges go through `core_badges_for`, not
 * a table read: the badge is public but the membership LIST is not, so the
 * server only answers about ids the caller already names.
 */
class CoreClubClient(private val auth: AuthRepository) {

    @Serializable
    data class Progress(
        val bar_seconds: Int = 240,
        val seats: Int = 100,
        val club_size: Int = 0,
        val streak: Int = 0,
        val entry_streak: Int = 30,
        val days_to_entry: Int? = null,
        val queue_ahead: Int? = null,
        val waiting_for_seat: Boolean = false,
        val member: Member? = null,
    ) {
        @Serializable
        data class Member(val seated: Boolean = false, val days_total: Int = 0)

        /** The badge IS the seat: worn only by a member seated right now. */
        val seated: Boolean get() = member?.seated == true
    }

    @Serializable
    data class Badge(val user_id: String = "", val seated: Boolean = false)

    private suspend fun rpc(name: String, body: JsonObject): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/$name")
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            raw
        }
    }

    suspend fun progress(language: String): Progress? = runCatching {
        Edge.json.decodeFromString(Progress.serializer(),
            rpc("core_my_progress", buildJsonObject { put("p_language", language) }))
    }.getOrNull()

    /**
     * Seated members only, keyed by LOWERCASE user id — a lapsed member has
     * no badge to draw. `uuid` columns come back lowercase while a client id
     * may be uppercase, so both sides are folded here and a caller can't get
     * it wrong. `language` is the pool being BROWSED, not the learner's own:
     * a seal earned in another language says nothing about the person in
     * front of you.
     */
    suspend fun badges(ownerIds: List<String>, language: String): Map<String, Badge> {
        val ids = ownerIds.map { it.lowercase() }.distinct()
        if (ids.isEmpty()) return emptyMap()
        return runCatching {
            val raw = rpc("core_badges_for", buildJsonObject {
                putJsonArray("p_user_ids") { ids.forEach { add(it) } }
                put("p_language", language.lowercase())
            })
            Edge.json.decodeFromString(ListSerializer(Badge.serializer()), raw)
                .filter { it.seated }
                .associateBy { it.user_id.lowercase() }
        }.getOrElse { emptyMap() }
    }
}
