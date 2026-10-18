package com.roro.futurevoice.sync

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.File
import java.time.Instant

/**
 * iOS `SyncKindHandler`: how to read a kind's items off the disk, how to
 * combine one item with the cloud's copy, and how to lay the merged set back
 * down. Reads and writes go to the FILES by path, never through the store
 * singletons — those are pinned to the active language, and a pull for a
 * language the learner isn't in still has to land. A write then pokes the
 * store (`afterWrite`) so what's in memory matches.
 *
 * Unlike iOS these work on JSON, not on each store's Kotlin class: the merge
 * rules only ever touch a handful of named fields, and decoding through the
 * classes would drop a field a newer build added — then push it back without.
 */
interface SyncKindHandler {
    val kind: SyncKind
    /** Items for [lang], keyed by sync key, as canonical payloads. `null` =
     *  the file exists but can't be read; the pass skips the kind rather
     *  than tombstoning everything in it. */
    fun read(lang: String?): Map<String, String>?
    fun merge(local: SyncSide?, remote: SyncSide): String?
    fun write(items: Map<String, SyncItem>, lang: String?)
    fun cascade(deletedKey: String, lang: String?, previous: String?): List<SyncCascade> = emptyList()
}

sealed interface SyncCascade {
    /** A talk is gone: its cards go, its audio goes. */
    data class SessionDeleted(val sessionId: String, val turnIds: List<String>, val lang: String) : SyncCascade
    data class DeleteFile(val kind: SyncKind, val key: String) : SyncCascade
}

/** The kinds, and the few store facts the engine needs beyond them (which
 *  languages exist, how a deleted talk's cards and audio are found). The app
 *  wires [SyncKindRegistry]; the tests wire a scratch tree. */
interface SyncRegistry {
    fun all(): List<SyncKindHandler>
    fun handler(kind: SyncKind): SyncKindHandler?
    fun enrolledLanguages(): List<String>
    fun cardSessionId(payload: String): String?
    fun deleteTurnAudio(turnIds: List<String>)
    fun newestVoiceSample(): File?
}

/** Where a kind's file lives — root, or the language's folder. */
fun interface SyncPaths { fun file(name: String, lang: String?): File }

// ── JSON helpers ────────────────────────────────────────────────────────

object SyncJson {
    fun readFile(f: File): JsonElement? {
        if (!f.exists()) return null
        return runCatching { SyncCanonical.json.parseToJsonElement(f.readText()) }.getOrNull()
    }

    /** Whole-file write, atomically, so a store reading mid-write never sees
     *  half a file. */
    fun writeFile(f: File, e: JsonElement) {
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, f.name + ".sync.tmp")
        tmp.writeText(SyncCanonical.json.encodeToString(JsonElement.serializer(), e))
        if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
    }

    fun obj(s: String): JsonObject? = SyncCanonical.parse(s) as? JsonObject

    fun JsonObject.str(k: String): String? = (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
    fun JsonObject.num(k: String): Double? = (this[k] as? JsonPrimitive)?.doubleOrNull
    fun JsonObject.bool(k: String): Boolean? = (this[k] as? JsonPrimitive)?.booleanOrNull

    /** A date field as a comparable number, whatever the store wrote: an
     *  ISO-8601 string, or a number (both sides of one file use one form). */
    fun JsonObject.time(k: String): Double? {
        val p = this[k] as? JsonPrimitive ?: return null
        if (p is JsonNull) return null
        if (p.isString) return runCatching { Instant.parse(p.content).toEpochMilli() / 1000.0 }.getOrNull()
        return p.doubleOrNull
    }

    /** Whichever side's value is later, field-wise. */
    fun later(a: JsonObject, b: JsonObject, k: String): JsonElement? {
        val x = a.time(k); val y = b.time(k)
        return when {
            x == null -> b[k]
            y == null -> a[k]
            else -> if (x >= y) a[k] else b[k]
        }
    }

    fun earlier(a: JsonObject, b: JsonObject, k: String): JsonElement? {
        val x = a.time(k); val y = b.time(k)
        return when {
            x == null -> b[k]
            y == null -> a[k]
            else -> if (x <= y) a[k] else b[k]
        }
    }

    fun maxNum(a: JsonObject, b: JsonObject, k: String): JsonElement? {
        val x = a.num(k); val y = b.num(k)
        return when {
            x == null -> b[k]
            y == null -> a[k]
            else -> if (x >= y) a[k] else b[k]
        }
    }

    fun JsonObject.with(vararg pairs: Pair<String, JsonElement?>): JsonObject {
        val m = LinkedHashMap(this)
        for ((k, v) in pairs) if (v == null) m.remove(k) else m[k] = v
        return JsonObject(m)
    }
}

// ── Generic handlers ────────────────────────────────────────────────────

/** A file holding `[T]` where each item has a stable `id`. */
class ArrayKind(
    override val kind: SyncKind,
    private val filename: String,
    private val paths: SyncPaths,
    /** Strip device-local fields before an item becomes a payload. */
    private val outbound: (JsonObject) -> JsonObject = { it },
    private val mergeRule: (SyncSide?, SyncSide) -> String?,
    /** Order the file is written in (the store's own order). */
    private val sortForFile: (List<JsonObject>) -> List<JsonObject> = { it },
    private val collapse: (List<JsonObject>) -> List<JsonObject> = { it },
    private val cascadeRule: (String, String?, JsonObject?) -> List<SyncCascade> = { _, _, _ -> emptyList() },
    private val afterWrite: (String?) -> Unit = {},
) : SyncKindHandler {
    override fun read(lang: String?): Map<String, String>? {
        val f = paths.file(filename, lang)
        if (!f.exists()) return emptyMap()
        val arr = SyncJson.readFile(f) as? JsonArray ?: return null
        val out = HashMap<String, String>()
        for (e in arr) {
            val o = e as? JsonObject ?: continue
            val id = (o["id"] as? JsonPrimitive)?.content ?: continue
            out[id.uppercase()] = SyncCanonical.canonical(outbound(o))
        }
        return out
    }

    override fun merge(local: SyncSide?, remote: SyncSide) = mergeRule(local, remote)

    override fun write(items: Map<String, SyncItem>, lang: String?) {
        val list = items.values.mapNotNull { SyncJson.obj(it.payload) }
        SyncJson.writeFile(paths.file(filename, lang), JsonArray(sortForFile(collapse(list))))
        afterWrite(lang)
    }

    override fun cascade(deletedKey: String, lang: String?, previous: String?) =
        cascadeRule(deletedKey, lang, previous?.let(SyncJson::obj))
}

/** A file holding `{key: value}`. */
class DictKind(
    override val kind: SyncKind,
    private val filename: String,
    private val paths: SyncPaths,
    private val mergeRule: (SyncSide?, SyncSide) -> String?,
    private val afterWrite: (String?) -> Unit = {},
) : SyncKindHandler {
    override fun read(lang: String?): Map<String, String>? {
        val f = paths.file(filename, lang)
        if (!f.exists()) return emptyMap()
        val o = SyncJson.readFile(f) as? JsonObject ?: return null
        return o.mapValues { SyncCanonical.canonical(it.value) }
    }

    override fun merge(local: SyncSide?, remote: SyncSide) = mergeRule(local, remote)

    override fun write(items: Map<String, SyncItem>, lang: String?) {
        val m = LinkedHashMap<String, JsonElement>()
        for ((k, v) in items.entries.sortedBy { it.key }) SyncCanonical.parse(v.payload)?.let { m[k] = it }
        SyncJson.writeFile(paths.file(filename, lang), JsonObject(m))
        afterWrite(lang)
    }
}

/** A file holding `[String]` — a set, or an ordered notebook (newest
 *  first). The key is the string; the payload wraps it so it's never empty. */
class StringListKind(
    override val kind: SyncKind,
    private val filename: String,
    private val paths: SyncPaths,
    private val ordered: Boolean,
    private val mergeRule: (SyncSide?, SyncSide) -> String?,
    private val afterWrite: (String?) -> Unit = {},
) : SyncKindHandler {
    private fun wrap(s: String) = SyncCanonical.canonical(JsonObject(mapOf("text" to JsonPrimitive(s))))

    override fun read(lang: String?): Map<String, String>? {
        val f = paths.file(filename, lang)
        if (!f.exists()) return emptyMap()
        val arr = SyncJson.readFile(f) as? JsonArray ?: return null
        return arr.mapNotNull { (it as? JsonPrimitive)?.content }.associateWith(::wrap)
    }

    override fun merge(local: SyncSide?, remote: SyncSide) = mergeRule(local, remote)

    override fun write(items: Map<String, SyncItem>, lang: String?) {
        val f = paths.file(filename, lang)
        val position = (SyncJson.readFile(f) as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }
            ?.withIndex()?.associate { it.value to it.index }.orEmpty()
        val list = if (ordered) items.entries.sortedWith(
            compareByDescending<Map.Entry<String, SyncItem>> { it.value.at }
                .thenBy { position[it.key] ?: Int.MAX_VALUE }).map { it.key }
        else items.keys.sorted()
        SyncJson.writeFile(f, JsonArray(list.map(::JsonPrimitive)))
        afterWrite(lang)
    }
}

/** A `{day: seconds}` map in preferences (the per-day counters). The max
 *  per day, never the sum — both devices saw the same day. */
class PrefsCountKind(
    override val kind: SyncKind,
    private val readMap: () -> Map<String, Int>,
    private val writeMap: (Map<String, Int>) -> Unit,
) : SyncKindHandler {
    private fun wrap(n: Int) = SyncCanonical.canonical(JsonObject(mapOf("seconds" to JsonPrimitive(n))))
    private fun unwrap(s: String) = (SyncJson.obj(s)?.get("seconds") as? JsonPrimitive)?.longOrNull?.toInt()

    override fun read(lang: String?) = readMap().mapValues { wrap(it.value) }

    override fun merge(local: SyncSide?, remote: SyncSide) =
        SyncMerge.combineOrNewerDelete(local, remote) { a, b -> wrap(maxOf(unwrap(a) ?: 0, unwrap(b) ?: 0)) }

    override fun write(items: Map<String, SyncItem>, lang: String?) =
        writeMap(items.mapNotNull { (k, v) -> unwrap(v.payload)?.let { k to it } }.toMap())
}

/** A folder of files carried as file content. The "payload" on disk is only
 *  the fingerprint; the engine moves the bytes. */
class BlobKind(
    override val kind: SyncKind,
    private val directory: () -> File,
    private val accepts: (String) -> Boolean = { true },
) : SyncKindHandler {
    fun file(key: String) = File(directory(), key)

    override fun read(lang: String?): Map<String, String> {
        val dir = directory()
        val names = dir.list() ?: return emptyMap()
        val out = HashMap<String, String>()
        for (name in names) {
            if (name.startsWith(".") || !accepts(name)) continue
            val f = File(dir, name)
            if (!f.isFile) continue
            out[name] = SyncCanonical.blobFingerprint(f.length(), f.lastModified())
        }
        return out
    }

    /** Written once, so whichever side has bytes has THE bytes. */
    override fun merge(local: SyncSide?, remote: SyncSide): String? =
        if (remote.deleted) null else local?.payload ?: remote.payload

    override fun write(items: Map<String, SyncItem>, lang: String?) {}
}
