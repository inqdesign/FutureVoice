package com.roro.futurevoice.sync

import android.content.Context
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.sync.SyncJson.bool
import com.roro.futurevoice.sync.SyncJson.num
import com.roro.futurevoice.sync.SyncJson.str
import com.roro.futurevoice.sync.SyncJson.time
import com.roro.futurevoice.sync.SyncJson.with
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File

/**
 * iOS `SyncKindRegistry`: every kind the sync carries, with its rule. The
 * rules are iOS's, word for word, because they ARE the feature:
 * - a talk is a talk: union by id, the newer edit wins, a deletion wins
 *   outright and takes its cards and audio with it;
 * - a card's progress is monotone: box, times seen, "used in a talk" all take
 *   the higher side;
 * - a word's state only ever climbs (used > known), counts take the max;
 * - notebook membership and hand-removals are last-writer-wins;
 * - per-day counters take the max per day, never the sum.
 *
 * Where Android's files differ from iOS's they are read as Android writes
 * them: saved lines live at the root, shadow takes are `shadow_attempts.json`
 * with an absolute recording path, turn audio is `turn-audio/`, the voice
 * recording is `voice/clone-take.wav`, and the per-day seconds are packed
 * strings in preferences. There is no dismissed-expressions or dialogue file
 * on Android, so those kinds don't exist here.
 */
class SyncKindRegistry(private val context: Context) : SyncRegistry {
    private val root: File get() = context.filesDir
    private val prefs get() = context.getSharedPreferences("futurevoice", 0)

    private val paths = SyncPaths { name, lang ->
        if (lang == null) File(root, name) else File(File(File(root, "lang"), lang), name)
    }

    private fun isActive(lang: String?) = lang == null || lang == LanguageScope.active(context)

    /** Every write ends here: anything on screen re-reads. */
    private fun touched(lang: String?) { if (isActive(lang)) StoreEvents.bump(fromSync = true) }

    override fun enrolledLanguages(): List<String> = LanguageScope.enrolled(context)

    private val handlers: List<SyncKindHandler> by lazy { listOf(
        sessionKind(),
        drillKind(),
        DictKind(SyncKind.VOCAB_RECORD, "vocab_pool.json", paths, ::mergeRecordRule, ::touched),
        DictKind(SyncKind.VOCAB_EXPRESSION, "vocab_expressions.json", paths, ::mergeRecordRule, ::touched),
        StringListKind(SyncKind.VOCAB_STUDYING, "vocab_studying.json", paths, true, SyncMerge::lww, ::touched),
        StringListKind(SyncKind.VOCAB_STUDYING_EXPRESSION, "vocab_studying_expressions.json", paths, true,
            SyncMerge::lww, ::touched),
        StringListKind(SyncKind.VOCAB_REMOVED_BY_HAND, "vocab_removed_by_hand.json", paths, false,
            SyncMerge::lww, ::touched),
        StringListKind(SyncKind.VOCAB_AUTO_KEPT, "vocab_auto_kept.json", paths, false, SyncMerge::lww, ::touched),
        DictKind(SyncKind.VOCAB_INGESTED, "vocab_ingested.json", paths, { l, r ->
            SyncMerge.union(l, r, SyncMerge.typed { a, b ->
                val x = (a as? JsonPrimitive)?.content?.toDoubleOrNull() ?: 0.0
                val y = (b as? JsonPrimitive)?.content?.toDoubleOrNull() ?: 0.0
                if (x >= y) a else b
            })
        }, ::touched),
        ExpressionIngestedKind(paths, ::touched),
        DictKind(SyncKind.SCHEDULE, "study-schedule.json", paths, SyncMerge::lww, ::touched),
        shadowKind(),
        ArrayKind(SyncKind.SAVED_LINE, "saved_lines.json", paths, mergeRule = SyncMerge::lww,
            afterWrite = ::touched),
        ArrayKind(SyncKind.WEEKLY, "weekly-reports.json", paths, mergeRule = SyncMerge::lww,
            sortForFile = newestFirst("generatedAt"), afterWrite = ::touched),
        ArrayKind(SyncKind.WEEKLY_TEST, "weekly-tests.json", paths, mergeRule = SyncMerge::lww,
            sortForFile = newestFirst("createdAt"), afterWrite = ::touched),
        scenarioKind(),
        ArrayKind(SyncKind.SPEECH_SCRIPT, "speech_scripts.json", paths, mergeRule = SyncMerge::lww,
            sortForFile = newestFirst("createdAt"), afterWrite = ::reloadSpeech),
        speechTakeKind(),
        DictKind(SyncKind.PRACTICE_DAY, "practice-log.json", paths, { l, r ->
            SyncMerge.union(l, r, SyncMerge.typed { a, b -> maxFields(a as JsonObject, b as JsonObject) })
        }, ::touched),
        PrefsCountKind(SyncKind.TALK_DAY, { packed("futurevoice.talkSecondsByDay") },
            { putPacked("futurevoice.talkSecondsByDay", it); StoreEvents.bump(fromSync = true) }),
        PrefsCountKind(SyncKind.USAGE_DAY, { packed("futurevoice.appSecondsByDay") },
            { putPacked("futurevoice.appSecondsByDay", it); StoreEvents.bump(fromSync = true) }),
        PersonaKind(paths, ::touched),
        PersonaNoteKind(paths, ::touched),
        ProfileKind(paths, ::touched),
        counterpartKind(),
        DefaultsKind(context),
        BlobKind(SyncKind.BLOB_TURN, { File(root, "turn-audio") }, { it.endsWith(".wav") }),
        BlobKind(SyncKind.BLOB_RECORDING, { File(root, "shadow-takes") }, { it.endsWith(".wav") }),
        BlobKind(SyncKind.BLOB_VOICE_SAMPLE, { File(root, "voice") }, { it == "clone-take.wav" }),
        // Only the voice: a camera take's video never travels.
        BlobKind(SyncKind.BLOB_SPEECH_AUDIO, { File(root, "Speech") }, { it.endsWith(".wav") }),
    ) }

    override fun all(): List<SyncKindHandler> = handlers
    override fun handler(kind: SyncKind): SyncKindHandler? = handlers.firstOrNull { it.kind == kind }

    // ── Sessions ────────────────────────────────────────────────────────

    private fun sessionKind() = ArrayKind(
        SyncKind.SESSION, "sessions.json", paths,
        // `audioURL` is an absolute path inside THIS install; every reader
        // falls back to `turn-audio/<id>.wav`, which is where synced audio lands.
        outbound = { s ->
            val turns = s["turns"] as? JsonArray ?: return@ArrayKind s
            s.with("turns" to JsonArray(turns.map { t -> (t as? JsonObject)?.with("audioURL" to null) ?: t }))
        },
        mergeRule = { l, r -> if (r.deleted) null else SyncMerge.lww(l, r) },
        sortForFile = { list -> list.sortedByDescending { it.time("endedAt") ?: it.time("startedAt") ?: 0.0 } },
        cascadeRule = { key, lang, previous ->
            if (lang == null) emptyList() else listOf(SyncCascade.SessionDeleted(key,
                (previous?.get("turns") as? JsonArray)?.mapNotNull { (it as? JsonObject)?.str("id") }.orEmpty(), lang))
        },
        afterWrite = { lang ->
            if (isActive(lang)) SessionStore.shared(context).invalidateCache()
            touched(lang)
        })

    /** The sentence card a deleted talk's cards are matched by. */
    override fun cardSessionId(payload: String): String? = SyncJson.obj(payload)?.str("sourceSessionId")?.uppercase()

    override fun deleteTurnAudio(turnIds: List<String>) {
        val dir = File(root, "turn-audio")
        turnIds.forEach { File(dir, "$it.wav").delete() }
    }

    override fun newestVoiceSample(): File? = File(File(root, "voice"), "clone-take.wav").takeIf { it.exists() }

    // ── Drill cards ─────────────────────────────────────────────────────

    private fun drillKind() = ArrayKind(
        SyncKind.DRILL, "drills.json", paths,
        mergeRule = { l, r -> SyncMerge.tombstoneWins(l, r, SyncMerge.typed { a, b ->
            mergeCards(a as JsonObject, b as JsonObject) }) },
        afterWrite = ::touched)

    /** Two copies of one card: progress is monotone, and the schedule follows
     *  the box that won (a box-5 card's date is already the retired one). */
    fun mergeCards(a: JsonObject, b: JsonObject): JsonObject {
        val boxA = a.num("box") ?: 0.0; val boxB = b.num("box") ?: 0.0
        val win = if (boxA >= boxB) a else b
        val other = if (boxA >= boxB) b else a
        var next = win["nextReviewAt"]
        if (boxA == boxB) {
            val ra = a.time("lastReviewedAt") ?: 0.0; val rb = b.time("lastReviewedAt") ?: 0.0
            next = if (ra >= rb) a["nextReviewAt"] else b["nextReviewAt"]
        }
        return win.with(
            "timesSeen" to SyncJson.maxNum(a, b, "timesSeen"),
            "timesCorrect" to SyncJson.maxNum(a, b, "timesCorrect"),
            "lastReviewedAt" to SyncJson.later(a, b, "lastReviewedAt"),
            "usedInTalkAt" to SyncJson.later(a, b, "usedInTalkAt"),
            "enrichment" to (win["enrichment"]?.takeIf { it !is JsonNull } ?: other["enrichment"]),
            "nextReviewAt" to next,
        )
    }

    // ── Vocabulary ──────────────────────────────────────────────────────

    private fun mergeRecordRule(l: SyncSide?, r: SyncSide) =
        SyncMerge.combineOrNewerDelete(l, r, SyncMerge.typed { a, b -> mergeRecords(a as JsonObject, b as JsonObject) })

    /** used > known; the count is the max, not the sum. */
    fun mergeRecords(a: JsonObject, b: JsonObject): JsonObject {
        val used = a.str("state") == "used" || b.str("state") == "used"
        val fromStudying = a.bool("fromStudying") == true || b.bool("fromStudying") == true
        return a.with(
            "state" to JsonPrimitive(if (used) "used" else "known"),
            "firstAt" to SyncJson.earlier(a, b, "firstAt"),
            "lastAt" to SyncJson.later(a, b, "lastAt"),
            "count" to SyncJson.maxNum(a, b, "count"),
            "fromStudying" to if (fromStudying) JsonPrimitive(true) else null,
        )
    }

    // ── Shadow takes ────────────────────────────────────────────────────

    private val shadowDir get() = File(root, "shadow-takes")

    private fun shadowKind() = ArrayKind(
        SyncKind.SHADOW, "shadow_attempts.json", paths,
        // The recording's path is absolute and this install's; the payload
        // carries the file NAME, and the file rides as `blobRecording`.
        outbound = { o -> o.str("recordingFilename")?.let { o.with("recordingFilename" to JsonPrimitive(File(it).name)) } ?: o },
        mergeRule = SyncMerge::lww,
        sortForFile = { list ->
            newestFirst("createdAt")(list.map { o ->
                val name = o.str("recordingFilename")
                if (name == null || name.startsWith("/")) o
                else o.with("recordingFilename" to JsonPrimitive(File(shadowDir, name).absolutePath))
            })
        },
        cascadeRule = { _, _, previous ->
            previous?.str("recordingFilename")?.let { listOf(SyncCascade.DeleteFile(SyncKind.BLOB_RECORDING, File(it).name)) }
                .orEmpty()
        },
        afterWrite = ::touched)

    // ── Speech ──────────────────────────────────────────────────────────

    private fun reloadSpeech(lang: String?) {
        if (isActive(lang)) SpeechStore.shared(context).reload()
        touched(lang)
    }

    private fun speechTakeKind() = ArrayKind(
        SyncKind.SPEECH_TAKE, "speech_takes.json", paths,
        mergeRule = SyncMerge::lww,
        sortForFile = newestFirst("createdAt"),
        cascadeRule = { _, _, previous ->
            listOfNotNull(previous?.str("audioFilename"), previous?.str("videoFilename"))
                .map { SyncCascade.DeleteFile(SyncKind.BLOB_SPEECH_AUDIO, it) }
        },
        afterWrite = ::reloadSpeech)

    // ── Scenarios ───────────────────────────────────────────────────────

    private fun scenarioKind() = ArrayKind(
        SyncKind.SCENARIO, "scenarios.json", paths,
        // The newer edit is the scenario; the book's study items are the
        // union of both, keeping the earliest mastery.
        mergeRule = { l, r ->
            val lp = l?.payload; val rp = r.payload
            val a = lp?.let(SyncJson::obj); val b = rp?.let(SyncJson::obj)
            if (l == null || l.deleted || r.deleted || a == null || b == null || lp == rp) SyncMerge.lww(l, r)
            else {
                val remoteWins = r.at >= l.at
                val win = if (remoteWins) b else a
                val lose = if (remoteWins) a else b
                SyncCanonical.canonical(win.with(
                    "curriculum" to mergeCurricula(win["curriculum"] as? JsonObject, lose["curriculum"] as? JsonObject),
                    "lastUsedAt" to SyncJson.later(a, b, "lastUsedAt")))
            }
        },
        afterWrite = ::touched)

    private fun mergeCurricula(a: JsonObject?, b: JsonObject?): JsonElement? {
        if (a == null) return b
        if (b == null) return a
        fun merged(k: String): JsonArray {
            val mine = (a[k] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty().toMutableList()
            for (item in (b[k] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()) {
                val i = mine.indexOfFirst { it.str("text")?.lowercase() == item.str("text")?.lowercase() }
                if (i >= 0) mine[i] = mine[i].with("masteredAt" to SyncJson.earlier(mine[i], item, "masteredAt"))
                else mine.add(item)
            }
            return JsonArray(mine)
        }
        return a.with("words" to merged("words"), "expressions" to merged("expressions"),
            "shadowLines" to merged("shadowLines"))
    }

    // ── People ──────────────────────────────────────────────────────────

    private fun counterpartKind() = ArrayKind(
        SyncKind.COUNTERPART, "counterparts.json", paths,
        mergeRule = { l, r -> SyncMerge.combineOrNewerDelete(l, r, SyncMerge.typed { a, b ->
            val x = a as JsonObject; val y = b as JsonObject
            if ((x.time("updatedAt") ?: 0.0) >= (y.time("updatedAt") ?: 0.0)) x else y }) },
        sortForFile = newestFirst("updatedAt"),
        // One row per Find-people persona, like `CounterpartStore.save`.
        collapse = { list ->
            val seen = HashSet<String>()
            newestFirst("updatedAt")(list).filter { c -> c.str("remoteId")?.let(seen::add) ?: true }
        },
        afterWrite = ::touched)

    // ── Helpers ─────────────────────────────────────────────────────────

    private fun newestFirst(field: String): (List<JsonObject>) -> List<JsonObject> =
        { list -> list.sortedByDescending { it.time(field) ?: 0.0 } }

    private fun maxFields(a: JsonObject, b: JsonObject): JsonObject {
        val keys = a.keys + b.keys
        return JsonObject(keys.associateWith { k -> SyncJson.maxNum(a, b, k) ?: JsonPrimitive(0) })
    }

    private fun packed(key: String): Map<String, Int> =
        prefs.getString(key, null)?.split(',')?.filter { '=' in it }?.mapNotNull {
            it.substringAfterLast('=').toIntOrNull()?.let { v -> it.substringBeforeLast('=') to v }
        }?.toMap().orEmpty()

    private fun putPacked(key: String, map: Map<String, Int>) {
        prefs.edit().putString(key, map.entries.sortedBy { it.key }.joinToString(",") { "${it.key}=${it.value}" }).apply()
    }
}

// ── Special kinds ───────────────────────────────────────────────────────

/** `vocab_expressions_ingested.json`: which expression keys each talk has
 *  already been counted for. Union of keys; "legacy" is sticky. */
private class ExpressionIngestedKind(private val paths: SyncPaths, private val after: (String?) -> Unit) : SyncKindHandler {
    override val kind = SyncKind.VOCAB_EXPRESSION_INGESTED
    private val name = "vocab_expressions_ingested.json"

    override fun read(lang: String?): Map<String, String>? {
        val f = paths.file(name, lang)
        if (!f.exists()) return emptyMap()
        val o = SyncJson.readFile(f) as? JsonObject ?: return null
        val out = HashMap<String, Pair<List<String>, Boolean>>()
        (o["keysBySession"] as? JsonObject)?.forEach { (s, keys) ->
            out[s] = (keys as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }.orEmpty().sorted() to false
        }
        (o["legacySessions"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }?.forEach { s ->
            out[s] = (out[s]?.first ?: emptyList()) to true
        }
        return out.mapValues { (_, v) -> entry(v.first, v.second) }
    }

    private fun entry(keys: List<String>, legacy: Boolean) = SyncCanonical.canonical(JsonObject(mapOf(
        "keys" to JsonArray(keys.map(::JsonPrimitive)), "legacy" to JsonPrimitive(legacy))))

    private fun parse(s: String): Pair<List<String>, Boolean> {
        val o = SyncJson.obj(s) ?: return emptyList<String>() to false
        return (o["keys"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }.orEmpty() to (o.bool("legacy") == true)
    }

    override fun merge(local: SyncSide?, remote: SyncSide) = SyncMerge.union(local, remote) { a, b ->
        val x = parse(a); val y = parse(b)
        entry((x.first + y.first).toSortedSet().toList(), x.second || y.second)
    }

    override fun write(items: Map<String, SyncItem>, lang: String?) {
        val keys = LinkedHashMap<String, JsonElement>()
        val legacy = ArrayList<JsonElement>()
        for ((s, item) in items) {
            val (k, l) = parse(item.payload)
            if (k.isNotEmpty()) keys[s] = JsonArray(k.map(::JsonPrimitive))
            if (l) legacy.add(JsonPrimitive(s))
        }
        SyncJson.writeFile(paths.file(name, lang), JsonObject(mapOf(
            "keysBySession" to JsonObject(keys), "legacySessions" to JsonArray(legacy))))
        after(lang)
    }
}

/** The profile the learner typed: one item, newer `updatedAt` wins. The
 *  notes ride separately ([PersonaNoteKind]) so a note added on the tablet
 *  and a city edited on the phone both survive. */
private class PersonaKind(private val paths: SyncPaths, private val after: (String?) -> Unit) : SyncKindHandler {
    override val kind = SyncKind.PERSONA
    private val file get() = paths.file("persona.json", null)

    override fun read(lang: String?): Map<String, String>? {
        if (!file.exists()) return emptyMap()
        val o = SyncJson.readFile(file) as? JsonObject ?: return null
        return mapOf(KEY to SyncCanonical.canonical(o.with("learnedNotes" to null)))
    }

    override fun merge(local: SyncSide?, remote: SyncSide) = SyncMerge.combineOrNewerDelete(local, remote,
        SyncMerge.typed { a, b ->
            val x = a as JsonObject; val y = b as JsonObject
            if ((x.time("updatedAt") ?: 0.0) >= (y.time("updatedAt") ?: 0.0)) x else y
        })

    override fun write(items: Map<String, SyncItem>, lang: String?) {
        val incoming = items[KEY]?.payload?.let(SyncJson::obj)
        if (incoming == null) { if (items.isEmpty()) file.delete(); return }
        val current = SyncJson.readFile(file) as? JsonObject
        SyncJson.writeFile(file, incoming.with("learnedNotes" to (current?.get("learnedNotes") ?: JsonArray(emptyList()))))
        after(null)
    }

    companion object { const val KEY = "persona" }
}

private class PersonaNoteKind(private val paths: SyncPaths, private val after: (String?) -> Unit) : SyncKindHandler {
    override val kind = SyncKind.PERSONA_NOTE
    private val file get() = paths.file("persona.json", null)

    override fun read(lang: String?): Map<String, String>? {
        if (!file.exists()) return emptyMap()
        val o = SyncJson.readFile(file) as? JsonObject ?: return null
        return (o["learnedNotes"] as? JsonArray)?.mapNotNull { it as? JsonObject }
            ?.mapNotNull { n -> n.str("id")?.let { it.uppercase() to SyncCanonical.canonical(n) } }?.toMap().orEmpty()
    }

    override fun merge(local: SyncSide?, remote: SyncSide) = SyncMerge.lww(local, remote)

    override fun write(items: Map<String, SyncItem>, lang: String?) {
        val persona = SyncJson.readFile(file) as? JsonObject ?: return
        // The model re-tells a fact in other words; keep one per dedupe key,
        // the most recently learned (`PersonaNote.dedupeKey`).
        fun key(n: JsonObject) = (n.str("text") ?: "").lowercase().split(Regex("[^\\p{L}\\p{N}]+"))
            .filter { it.isNotEmpty() }.joinToString(" ")
        val byKey = LinkedHashMap<String, JsonObject>()
        for (n in items.values.mapNotNull { SyncJson.obj(it.payload) }) {
            val k = key(n)
            val existing = byKey[k]
            if (existing != null && (existing.time("learnedAt") ?: 0.0) >= (n.time("learnedAt") ?: 0.0)) continue
            byKey[k] = n
        }
        val notes = byKey.values.sortedBy { it.time("learnedAt") ?: 0.0 }
        SyncJson.writeFile(file, persona.with("learnedNotes" to JsonArray(notes)))
        after(null)
    }
}

/** One learner profile per target language. */
private class ProfileKind(private val paths: SyncPaths, private val after: (String?) -> Unit) : SyncKindHandler {
    override val kind = SyncKind.PROFILE
    private val file get() = paths.file("profile.json", null)

    override fun read(lang: String?): Map<String, String>? {
        if (!file.exists()) return emptyMap()
        val arr = SyncJson.readFile(file) as? JsonArray ?: return null
        return arr.mapNotNull { it as? JsonObject }
            .mapNotNull { p -> p.str("targetLanguage")?.let { it to SyncCanonical.canonical(p) } }.toMap()
    }

    /** The profile that has seen more talks is the fuller memory. */
    override fun merge(local: SyncSide?, remote: SyncSide) = SyncMerge.combineOrNewerDelete(local, remote,
        SyncMerge.typed { a, b ->
            val x = a as JsonObject; val y = b as JsonObject
            if ((x.time("lastSessionAt") ?: 0.0) >= (y.time("lastSessionAt") ?: 0.0)) x else y
        })

    override fun write(items: Map<String, SyncItem>, lang: String?) {
        SyncJson.writeFile(file, JsonArray(items.values.mapNotNull { SyncJson.obj(it.payload) }))
        after(null)
    }
}

/**
 * The `futurevoice.*` preferences that describe HOW the learner practises —
 * languages, levels, goals. Account and per-install keys (the voice, consent,
 * the daily call) never go here. Enrolled languages are a union: un-enrolling
 * is rare and the safer failure is a language still listed.
 */
private class DefaultsKind(private val context: Context) : SyncKindHandler {
    override val kind = SyncKind.DEFAULTS
    private val prefs get() = context.getSharedPreferences("futurevoice", 0)
    private val fixed = listOf(
        "futurevoice.nativeLanguage", "futurevoice.targetLanguage", "futurevoice.enrolledLanguages",
        "futurevoice.proficiency", "futurevoice.dailyGoalMinutes", "futurevoice.goal.sentencesPerDay",
        "futurevoice.goal.wordsPerDay", "futurevoice.goal.expressionsPerDay", "futurevoice.goal.shadowsPerDay",
        "futurevoice.vocab.hideKnown")
    private fun keys() = fixed + prefs.all.keys.filter { it.startsWith("futurevoice.level.") }

    private val enrolledKey = "futurevoice.enrolledLanguages"

    private fun encode(key: String, v: Any?): String? = when {
        // The one list: tagged so the merge knows to take the union.
        key == enrolledKey && v is String -> tagged("langs", JsonPrimitive(v))
        v is String -> tagged("s", JsonPrimitive(v))
        v is Int -> tagged("i", JsonPrimitive(v))
        v is Long -> tagged("l", JsonPrimitive(v))
        v is Boolean -> tagged("b", JsonPrimitive(v))
        v is Float -> tagged("f", JsonPrimitive(v))
        else -> null
    }
    private fun tagged(t: String, v: JsonPrimitive) =
        SyncCanonical.canonical(JsonObject(mapOf("t" to JsonPrimitive(t), "v" to v)))

    override fun read(lang: String?): Map<String, String> {
        val all = prefs.all
        return keys().mapNotNull { k -> encode(k, all[k])?.let { k to it } }.toMap()
    }

    override fun merge(local: SyncSide?, remote: SyncSide): String? {
        val a = local?.payload?.let(SyncJson::obj)
        val b = remote.payload?.let(SyncJson::obj)
        if (a != null && b != null && !remote.deleted && a.str("t") == "langs" && b.str("t") == "langs") {
            val merged = (a.str("v").orEmpty().split(',') + b.str("v").orEmpty().split(','))
                .map { it.trim() }.filter { it.isNotEmpty() }.distinct()
            return tagged("langs", JsonPrimitive(merged.joinToString(",")))
        }
        return SyncMerge.lww(local, remote)
    }

    override fun write(items: Map<String, SyncItem>, lang: String?) {
        val e = prefs.edit()
        for ((k, item) in items) {
            val o = SyncJson.obj(item.payload) ?: continue
            val v = o["v"] as? JsonPrimitive ?: continue
            when (o.str("t")) {
                "s", "langs" -> e.putString(k, v.content)
                "i" -> v.content.toIntOrNull()?.let { e.putInt(k, it) }
                "l" -> v.content.toLongOrNull()?.let { e.putLong(k, it) }
                "b" -> e.putBoolean(k, v.content == "true")
                "f" -> v.content.toFloatOrNull()?.let { e.putFloat(k, it) }
            }
        }
        e.apply()
        StoreEvents.bump(fromSync = true)
    }
}
