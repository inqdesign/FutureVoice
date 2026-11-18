package com.roro.futurevoice.sync

import com.roro.futurevoice.data.ActivityEventLog
import com.roro.futurevoice.data.PromiseLedger
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.StudyPlan
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.time.Instant

/**
 * The routine, its promise days and when each rep happened, carried in the
 * exact bytes iOS writes (iOS `StudyPlanKind`, the `promiseDay` DictKind,
 * `ActivityEventKind`). Without them a Mac or iPhone and this phone judged
 * the streak by two different routines with two different views of what was
 * done, and showed two different flames (learner report, 2026-11-18).
 *
 * The bytes matter as much as the values: a payload this side writes in
 * another shape than iOS reads back looks edited on the next pass, and the
 * two devices push the same record to each other forever. So dates are
 * ISO-8601 to the second (iOS `.iso8601`), nil fields are left out (Swift's
 * synthesized `Codable`), and the routine's set fields go up sorted (Swift
 * encodes a `Set` in no fixed order; iOS sorts them in its payload too).
 */
object RoutineSync {

    /** Encodes every field, leaves nulls out: what Swift writes. */
    private val json = Json(StoreJson.json) {
        encodeDefaults = true
        explicitNulls = false
    }

    fun iso(ms: Long): String = Instant.ofEpochSecond(Math.floorDiv(ms, 1000L)).toString()

    private fun millis(e: JsonElement?): Long? {
        val p = e as? JsonPrimitive ?: return null
        p.longOrNull?.let { return it }
        val s = p.contentOrNull ?: return null
        return runCatching { Instant.parse(s).toEpochMilli() }.getOrNull()
    }

    private fun JsonObject.mapDates(keys: Set<String>, f: (JsonElement) -> JsonElement?): JsonObject =
        JsonObject(mapNotNull { (k, v) -> if (k in keys) f(v)?.let { k to it } else k to v }.toMap())

    // ── The routine ─────────────────────────────────────────────────────

    private val planDates = setOf("streakSince", "editedAt")
    private val setKeys = setOf("weekdays", "restDays", "offWeekdays")

    /** Sorts the arrays that are sets, wherever they sit (the plan, its
     *  blocks, a date's own blocks). */
    internal fun sortingSets(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.mapValues { (k, v) ->
            if (k in setKeys && v is JsonArray) JsonArray(v.sortedWith(compareBy(
                { (it as? JsonPrimitive)?.longOrNull ?: Long.MIN_VALUE },
                { (it as? JsonPrimitive)?.contentOrNull ?: "" })))
            else sortingSets(v)
        })
        is JsonArray -> JsonArray(e.map(::sortingSets))
        else -> e
    }

    fun planPayload(plan: StudyPlan): String {
        val o = json.encodeToJsonElement(StudyPlan.serializer(), plan) as JsonObject
        val dated = o.mapDates(planDates) { v -> millis(v)?.let { JsonPrimitive(iso(it)) } }
        return SyncCanonical.canonical(sortingSets(dated))
    }

    fun plan(payload: String): StudyPlan? {
        val o = SyncCanonical.parse(payload) as? JsonObject ?: return null
        val local = o.mapDates(planDates) { v -> millis(v)?.let { JsonPrimitive(it) } }
        return runCatching { StoreJson.json.decodeFromJsonElement(StudyPlan.serializer(), local) }.getOrNull()
    }

    /** iOS `StudyPlanKind.merge`: a real routine over a seed, then the later
     *  edit; a routine is never deleted (an emptied one is still a routine). */
    fun mergePlan(local: SyncSide?, remote: SyncSide): String? {
        val lp = local?.takeIf { !it.deleted }?.payload
        val rp = remote.takeIf { !it.deleted }?.payload
        if (lp != null && rp != null && lp != rp) {
            val a = plan(lp)
            val b = plan(rp)
            if (a != null && b != null) {
                StudyPlan.later(a, b)?.let { return if (it == a) lp else rp }
            }
        }
        return SyncMerge.lww(local, remote) ?: lp
    }

    class PlanKind(
        private val current: () -> StudyPlan,
        private val adopt: (StudyPlan) -> Unit,
    ) : SyncKindHandler {
        override val kind = SyncKind.STUDY_PLAN
        override fun read(lang: String?): Map<String, String> = mapOf(KEY to planPayload(current()))
        override fun merge(local: SyncSide?, remote: SyncSide) = mergePlan(local, remote)
        override fun write(items: Map<String, SyncItem>, lang: String?) {
            val p = items[KEY]?.payload?.let(::plan) ?: return
            adopt(p)
        }
        override fun accepts(payload: String): Boolean = plan(payload) != null
        companion object { const val KEY = "plan" }
    }

    // ── Promise days ────────────────────────────────────────────────────

    private val entryDates = setOf("keptAt")

    fun entryPayload(e: PromiseLedger.Entry): String {
        val o = json.encodeToJsonElement(PromiseLedger.Entry.serializer(), e) as JsonObject
        return SyncCanonical.canonical(o.mapDates(entryDates) { v -> millis(v)?.let { JsonPrimitive(iso(it)) } })
    }

    fun entry(payload: String): PromiseLedger.Entry? {
        val o = SyncCanonical.parse(payload) as? JsonObject ?: return null
        val local = o.mapDates(entryDates) { v -> millis(v)?.let { JsonPrimitive(it) } }
        return runCatching { StoreJson.json.decodeFromJsonElement(PromiseLedger.Entry.serializer(), local) }.getOrNull()
    }

    /** iOS `fullerDay`: kept beats not kept (the earlier keep standing),
     *  then more blocks started, more finished, settled over provisional. */
    fun fullerDay(a: PromiseLedger.Entry, b: PromiseLedger.Entry): PromiseLedger.Entry {
        val x = a.keptAt
        val y = b.keptAt
        if (x != null && y != null) return if (x <= y) a else b
        if (x != null) return a
        if (y != null) return b
        val ta = a.touched ?: a.done
        val tb = b.touched ?: b.done
        if (ta != tb) return if (ta > tb) a else b
        if (a.done != b.done) return if (a.done > b.done) a else b
        if (a.settled != b.settled) return if (a.settled) a else b
        return a
    }

    class PromiseKind(
        private val current: () -> Map<String, PromiseLedger.Entry>,
        private val replace: (Map<String, PromiseLedger.Entry>) -> Unit,
    ) : SyncKindHandler {
        override val kind = SyncKind.PROMISE_DAY
        override fun read(lang: String?): Map<String, String> = current().mapValues { entryPayload(it.value) }
        override fun merge(local: SyncSide?, remote: SyncSide) = SyncMerge.union(local, remote) { l, r ->
            val a = entry(l) ?: return@union r
            val b = entry(r) ?: return@union l
            if (fullerDay(a, b) == a) l else r
        }
        override fun write(items: Map<String, SyncItem>, lang: String?) {
            replace(items.mapNotNull { (k, v) -> entry(v.payload)?.let { k to it } }.toMap())
        }
        override fun accepts(payload: String): Boolean = entry(payload) != null
    }

    // ── When each rep happened ──────────────────────────────────────────

    /** iOS `ActivityEventLog.syncKeys`: kind, the second it happened, and
     *  which of that second's events of that kind it was, in file order. */
    fun eventKeys(list: List<ActivityEventLog.Event>): List<Pair<String, ActivityEventLog.Event>> {
        val seen = HashMap<String, Int>()
        return list.map { e ->
            val base = "${raw(e.kind)}|${Math.floorDiv(e.at, 1000L)}"
            val n = seen[base] ?: 0
            seen[base] = n + 1
            "$base|$n" to e
        }
    }

    private fun raw(k: ActivityEventLog.Kind): String =
        (json.encodeToJsonElement(ActivityEventLog.Kind.serializer(), k) as JsonPrimitive).content

    fun eventPayload(e: ActivityEventLog.Event): String =
        SyncCanonical.canonical(JsonObject(mapOf("at" to JsonPrimitive(iso(e.at)), "kind" to JsonPrimitive(raw(e.kind)))))

    fun event(payload: String): ActivityEventLog.Event? {
        val o = SyncCanonical.parse(payload) as? JsonObject ?: return null
        val at = millis(o["at"]) ?: return null
        val kind = runCatching {
            json.decodeFromJsonElement(ActivityEventLog.Kind.serializer(), o["kind"] ?: return null)
        }.getOrNull() ?: return null
        return ActivityEventLog.Event(kind, at)
    }

    class EventKind(
        private val current: () -> List<ActivityEventLog.Event>,
        private val replace: (List<ActivityEventLog.Event>) -> Unit,
    ) : SyncKindHandler {
        override val kind = SyncKind.ACTIVITY_EVENT
        override fun read(lang: String?): Map<String, String> =
            eventKeys(current()).associate { (k, e) -> k to eventPayload(e) }
        // Reps are facts: the union of both devices', never a deletion (each
        // device prunes its own past 60 days).
        override fun merge(local: SyncSide?, remote: SyncSide) = SyncMerge.union(local, remote) { l, _ -> l }
        override fun write(items: Map<String, SyncItem>, lang: String?) {
            replace(items.values.mapNotNull { event(it.payload) }.sortedBy { it.at })
        }
        override fun accepts(payload: String): Boolean = event(payload) != null
    }
}
