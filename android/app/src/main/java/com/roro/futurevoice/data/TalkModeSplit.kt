package com.roro.futurevoice.data

import okhttp3.Request

/**
 * This billing period's talk time by kind of call — free talk, tutor,
 * pronunciation, and the calls from before the kind was recorded (iOS
 * `UsageBreakdown.talkModes`, ffaf0c58, founder 2026-11-04). The gateway
 * puts the kind on every `talk_time` tick (`start.mode` →
 * `talk-tick` `metadata.mode`). Everything else paid from the talk pool is a
 * part of its figure too — talk-paid scenes (`scene_play`) and voiceovers
 * (`script_voiceover`) — so the rows under "Talk time" add up to it (iOS
 * c380df8b).
 *
 * From the ledger, so it is the SPLIT and never the headline: the figure
 * above it stays the pool's own, and a clipped ledger costs the split some
 * seconds, never the number the learner is held to.
 */
object TalkModeSplit {
    /**
     * [callSeconds] is the time practiced behind [seconds] — what it cost.
     * They differ only on a pronunciation call, which costs half (iOS
     * cb50cc3e); a row charged whole adds its own seconds (iOS 15d3d851), so
     * a month mixing calls from before the discount still shows it.
     */
    data class Part(val key: String, val seconds: Int, val callSeconds: Int? = null)

    /** The order the page lists them in. */
    val ORDER = listOf("free", "tutor", "pron", "scene", "voiceover", "earlier")

    /** The ledger actions paid from the talk pool. */
    private val ACTIONS = listOf("talk_time", "script_voiceover", "scene_play")

    private const val PAGE_SIZE = 1000
    private const val MAX_ROWS = 8000

    @kotlinx.serialization.Serializable
    internal data class Row(
        val created_at: String,
        val idempotency_key: String? = null,
        val action: String = "talk_time",
        val metadata: Meta? = null,
    ) {
        @kotlinx.serialization.Serializable
        data class Meta(
            val seconds: Int? = null, val mode: String? = null, val preflight: Boolean? = null,
            /** The call time a tick paid for, where it was charged less. */
            val call_seconds: Int? = null,
        )
    }

    /** The kind a tick's mode is filed under; anything unknown is "earlier". */
    fun keyFor(mode: String?): String = if (mode in listOf("free", "tutor", "pron")) mode!! else "earlier"

    /** The row's kind: a voiceover, a talk-paid scene, or a call by its mode. */
    fun keyFor(action: String, mode: String?): String = when (action) {
        "script_voiceover" -> "voiceover"
        "scene_play" -> "scene"
        else -> keyFor(mode)
    }

    /** Seconds per kind since [periodStart] (`yyyy-MM-dd`); null on failure. */
    suspend fun load(auth: AuthRepository, periodStart: String?): List<Part>? =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            val uid = auth.userId ?: return@withContext null
            val token = runCatching { auth.accessToken() }.getOrNull() ?: return@withContext null
            // Rounded up to whole days like iOS (14–32), then cut at the
            // period's first day so the previous period's tail isn't counted.
            val start = periodStart?.let { runCatching { java.time.LocalDate.parse(it.take(10)) }.getOrNull() }
            val days = start?.let {
                (java.time.temporal.ChronoUnit.DAYS.between(it, java.time.LocalDate.now()) + 1).toInt().coerceIn(14, 32)
            } ?: 14
            val since = java.time.Instant.now().minus(java.time.Duration.ofDays(days.toLong())).toString()
            val base = "${com.roro.futurevoice.core.Config.supabaseUrl.trimEnd('/')}/rest/v1/usage_ledger" +
                "?select=created_at,idempotency_key,action,metadata&user_id=eq.$uid" +
                "&action=in.(${ACTIONS.joinToString(",")})" +
                "&created_at=gte.${java.net.URLEncoder.encode(since, "UTF-8")}&order=created_at.desc,id.desc"
            val rows = mutableListOf<Row>()
            while (rows.size < MAX_ROWS) {
                val page = runCatching {
                    val req = Request.Builder()
                        .url("$base&offset=${rows.size}&limit=$PAGE_SIZE")
                        .header("Authorization", "Bearer $token")
                        .header("apikey", com.roro.futurevoice.core.Config.supabaseAnonKey).build()
                    com.roro.futurevoice.net.Edge.client.newCall(req).execute().use { resp ->
                        if (!resp.isSuccessful) null
                        else com.roro.futurevoice.net.Edge.json.decodeFromString(
                            kotlinx.serialization.builtins.ListSerializer(Row.serializer()), resp.body.string())
                    }
                }.getOrNull() ?: return@withContext null
                rows += page
                if (page.size < PAGE_SIZE) break
            }
            aggregate(rows, periodStart?.take(10))
        }

    /** The ledger rows of the period (from [periodKey], `yyyy-MM-dd`) summed per kind. */
    internal fun aggregate(rows: List<Row>, periodKey: String?): List<Part> {
        val seen = HashSet<String>()
        val sums = mutableMapOf<String, Int>()
        val calls = mutableMapOf<String, Int>()
        for (r in rows) {
            if (r.idempotency_key != null && !seen.add(r.idempotency_key)) continue
            val sec = r.metadata?.seconds ?: continue
            if (sec <= 0) continue
            if (periodKey != null && r.created_at.take(10) < periodKey) continue
            val k = keyFor(r.action, r.metadata.mode)
            sums[k] = (sums[k] ?: 0) + sec
            // The time practiced: a row charged whole ran as long as it
            // cost, so it adds its own seconds (iOS 15d3d851) — otherwise a
            // month mixing calls from before the discount with calls after it
            // reads LESS practiced than charged, and shows no discount.
            calls[k] = (calls[k] ?: 0) + (r.metadata.call_seconds ?: sec)
        }
        return ORDER.mapNotNull { k -> sums[k]?.let { Part(k, it, calls[k]) } }
    }
}
