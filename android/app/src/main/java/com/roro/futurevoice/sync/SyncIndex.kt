package com.roro.futurevoice.sync

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File
import java.util.concurrent.Executors

/**
 * iOS `SyncIndex`: what this device knows about every synced item — its
 * last-seen fingerprint, whether the server has that version, the server's
 * handle, and the timestamps the LWW rules read. One per app account under
 * `filesDir/sync/<userId>/`, and excluded from the backup file: a restored
 * install must re-derive its own relationship with the cloud.
 *
 * The index is what turns whole-file stores into per-item sync without
 * instrumenting every mutation: a pass reads a store, fingerprints each item,
 * and compares. A key here and not in the store was deleted; a fingerprint
 * that moved was edited.
 */
class SyncIndex(private val directory: File) {

    @Serializable
    data class Entry(
        val kind: String,
        val lang: String? = null,
        val key: String,
        /** Payload hash, or `blobFingerprint` for a blob. */
        var hash: String,
        /** When the diff first saw this fingerprint (epoch ms). */
        var observedAt: Long,
        /** The server holds exactly this version. */
        var pushedAt: Long? = null,
        /** A pull's merge produced something the server lacks. */
        var needsPush: Boolean = false,
        var deletedAt: Long? = null,
        /** Drive file id — what an update writes to. */
        var serverId: String? = null,
        /** From a NEWER build: never pushed back or tombstoned here. */
        var frozen: Boolean = false,
        /** A blob the server has and this device hasn't downloaded yet. */
        var wanted: Boolean = false,
        var size: Long = 0,
    ) {
        val isDeleted: Boolean get() = deletedAt != null
        val syncKind: SyncKind? get() = SyncKind.of(kind)
        val recordName: String get() = SyncRecord.recordName(SyncKind.of(kind)!!, lang, key)
    }

    private val entriesFile = File(directory, "index.json")
    private val stateFile = File(directory, "state.json")

    private val map = HashMap<String, Entry>()
    var state = SyncIndexState()

    init {
        writer.submit {}.get()
        directory.mkdirs()
        runCatching {
            if (entriesFile.exists()) map.putAll(SyncCanonical.json.decodeFromString(
                MapSerializer(String.serializer(), Entry.serializer()), entriesFile.readText()))
        }
        runCatching {
            if (stateFile.exists()) state = SyncCanonical.json.decodeFromString(
                SyncIndexState.serializer(), stateFile.readText())
        }
        thawIfUpgraded()
    }

    private fun thawIfUpgraded() {
        if (state.schema >= SyncSchema.VERSION) return
        map.values.forEach { it.frozen = false }
        state = state.copy(changeToken = null, schema = SyncSchema.VERSION)
        save()
    }

    @Synchronized operator fun get(name: String): Entry? = map[name]
    @Synchronized operator fun set(name: String, e: Entry) { map[name] = e }
    @Synchronized fun entry(kind: SyncKind, lang: String?, key: String): Entry? =
        map[SyncRecord.recordName(kind, lang, key)]
    @Synchronized fun put(e: Entry) { map[e.recordName] = e }
    @Synchronized fun entries(kind: SyncKind, lang: String?): List<Entry> =
        map.values.filter { it.kind == kind.raw && it.lang == lang }
    @Synchronized fun all(): List<Entry> = map.values.toList()
    val pendingPush: List<Entry> get() = all().filter { it.needsPush && !it.frozen }
    val wantedBlobs: List<Entry> get() = all().filter { it.wanted && !it.isDeleted }
    /** Every language this index has seen for a scoped kind — a language the
     *  learner un-enrolled still has tombstones to send. */
    fun languages(kind: SyncKind): Set<String> = all().filter { it.kind == kind.raw }.mapNotNull { it.lang }.toSet()

    /** Saves on one serial thread, so saves land in order. */
    fun save() {
        val entries: Map<String, Entry>
        synchronized(this) { entries = map.mapValues { it.value.copy() } }
        val st = state
        writer.submit {
            runCatching {
                directory.mkdirs()
                writeAtomic(entriesFile, SyncCanonical.json.encodeToString(
                    MapSerializer(String.serializer(), Entry.serializer()), entries))
                writeAtomic(stateFile, SyncCanonical.json.encodeToString(SyncIndexState.serializer(), st))
            }
        }
    }

    /** Forgets the server (handles, token) and keeps every fingerprint —
     *  what "the folder is gone" needs. */
    fun forgetServer() {
        synchronized(this) {
            map.values.forEach {
                it.serverId = null; it.pushedAt = null; it.needsPush = !it.isDeleted; it.wanted = false
            }
        }
        state = state.copy(changeToken = null, lastPullAt = null)
        save()
    }

    fun removeAll() {
        synchronized(this) { map.clear() }
        state = SyncIndexState()
        val dir = directory
        writer.submit { dir.deleteRecursively() }
    }

    companion object {
        private val writer = Executors.newSingleThreadExecutor { r -> Thread(r, "sync-index") }

        fun directory(filesDir: File, userId: String) = File(File(filesDir, "sync"), userId)

        /** Blocks until every queued save is on disk. */
        fun flush() { writer.submit {}.get() }

        private fun writeAtomic(f: File, text: String) {
            val tmp = File(f.parentFile, f.name + ".tmp")
            tmp.writeText(text)
            if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
        }
    }
}
