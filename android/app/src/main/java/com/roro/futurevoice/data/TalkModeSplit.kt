package com.roro.futurevoice.data

import okhttp3.Request

/**
 * This billing period's talk time by kind of call — free talk, tutor,
 * pronunciation, and the calls from before the kind was recorded (iOS
 * `UsageBreakdown.talkModes`, ffaf0c58, founder 2026-11-04). The gateway
 * puts the kind on every `talk_time` tick (`start.mode` →
 * `talk-tick` `metadata.mode`).
 *
 * From the ledger, so it is the SPLIT and never the headline: the figure
 * above it stays the pool's own, and a clipped ledger costs the split some
 * seconds, never the number the learner is held to.
 */
object TalkModeSplit {
    data class Part(val key: String, val seconds: Int)

    /** The order the page lists them in. */
    val ORDER = listOf("free", "tutor", "pron", "earlier")

    private const val PAGE_SIZE = 1000
    private const val MAX_ROWS = 8000

    @kotlinx.serialization.Serializable
    private data class Row(
        val created_at: String,
        val idempotency_key: String? = null,
        val metadata: Meta? = null,
    ) {
        @kotlinx.serialization.Serializable
        data class Meta(val seconds: Int? = null, val mode: String? = null, val preflight: Boolean? = null)
    }

    /** The kind a tick's mode is filed under; anything unknown is "earlier". */
    fun keyFor(mode: String?): String = if (mode in listOf("free", "tutor", "pron")) mode!! else "earlier"

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
                "?select=created_at,idempotency_key,metadata&user_id=eq.$uid&action=eq.talk_time" +
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
            val periodKey = periodStart?.take(10)
            val seen = HashSet<String>()
            val sums = mutableMapOf<String, Int>()
            for (r in rows) {
                if (r.idempotency_key != null && !seen.add(r.idempotency_key)) continue
                val sec = r.metadata?.seconds ?: continue
                if (sec <= 0) continue
                if (periodKey != null && r.created_at.take(10) < periodKey) continue
                val k = keyFor(r.metadata.mode)
                sums[k] = (sums[k] ?: 0) + sec
            }
            ORDER.mapNotNull { k -> sums[k]?.let { Part(k, it) } }
        }
}
