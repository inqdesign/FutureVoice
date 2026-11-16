package com.roro.futurevoice

import com.roro.futurevoice.sync.DictKind
import com.roro.futurevoice.sync.InMemorySyncTransport
import com.roro.futurevoice.sync.SyncAccountState
import com.roro.futurevoice.sync.SyncChangeBatch
import com.roro.futurevoice.sync.SyncEngine
import com.roro.futurevoice.sync.SyncIndex
import com.roro.futurevoice.sync.SyncJson
import com.roro.futurevoice.sync.SyncJson.with
import com.roro.futurevoice.sync.SyncKind
import com.roro.futurevoice.sync.SyncKindHandler
import com.roro.futurevoice.sync.SyncMerge
import com.roro.futurevoice.sync.SyncPaths
import com.roro.futurevoice.sync.SyncRecord
import com.roro.futurevoice.sync.SyncRegistry
import com.roro.futurevoice.sync.SyncSaveOutcome
import com.roro.futurevoice.sync.SyncSettings
import com.roro.futurevoice.sync.SyncTransport
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * One phone, Drive's shape: the change feed hands back this device's own
 * writes. Reproduces a learner's sync after a call (2026-11-16): ~150 word
 * records change, are pushed, and the next pull brings all of them back.
 */
class SyncEchoTest {

    /** Counts what each pull hands the engine. */
    private class CountingTransport(val inner: InMemorySyncTransport = InMemorySyncTransport()) : SyncTransport by inner {
        var pulled = 0
        override suspend fun changes(zone: String, token: String?): SyncChangeBatch =
            inner.changes(zone, token).also { pulled += it.changed.size }
        override suspend fun accountAvailable() = SyncAccountState.AVAILABLE
        override suspend fun save(records: List<SyncRecord>, zone: String): Map<String, SyncSaveOutcome> =
            inner.save(records, zone)
        override suspend fun fetch(records: List<SyncIndex.Entry>, zone: String) = inner.fetch(records, zone)
    }

    private class Settings : SyncSettings {
        val enabled = HashSet<String>()
        override fun isEnabled(userId: String) = userId in enabled
        override fun setEnabled(userId: String, on: Boolean) { if (on) enabled.add(userId) else enabled.remove(userId) }
        override fun lastUser(): String? = null
        override fun setLastUser(id: String?) {}
        override fun setLastSyncAt(userId: String, at: Long) {}
        override fun quotaHitAt(userId: String): Long? = null
        override fun setQuotaHitAt(userId: String, at: Long?) {}
    }

    /** The app's vocab merge (`SyncKindRegistry.mergeRecords`). */
    private fun mergeRecords(a: JsonObject, b: JsonObject): JsonObject {
        fun s(o: JsonObject, k: String) = (o[k] as? JsonPrimitive)?.content
        val used = s(a, "state") == "used" || s(b, "state") == "used"
        val fromStudying = s(a, "fromStudying") == "true" || s(b, "fromStudying") == "true"
        return a.with(
            "state" to JsonPrimitive(if (used) "used" else "known"),
            "firstAt" to SyncJson.earlier(a, b, "firstAt"),
            "lastAt" to SyncJson.later(a, b, "lastAt"),
            "count" to SyncJson.maxNum(a, b, "count"),
            "fromStudying" to if (fromStudying) JsonPrimitive(true) else null,
        )
    }

    private class Device(val root: File, merge: (JsonObject, JsonObject) -> JsonObject) : SyncRegistry {
        private val paths = SyncPaths { name, lang ->
            if (lang == null) File(root, name) else File(File(File(root, "lang"), lang), name)
        }
        val vocab = DictKind(SyncKind.VOCAB_RECORD, "vocab_pool.json", paths, { l, r ->
            SyncMerge.combineOrNewerDelete(l, r, SyncMerge.typed { a, b -> merge(a as JsonObject, b as JsonObject) })
        })
        private val list: List<SyncKindHandler> = listOf(vocab)
        override fun all() = list
        override fun handler(kind: SyncKind) = list.firstOrNull { it.kind == kind }
        override fun enrolledLanguages() = listOf("en")
        override fun cardSessionId(payload: String): String? = null
        override fun deleteTurnAudio(turnIds: List<String>) {}
        override fun newestVoiceSample(): File? = null
        fun file() = File(File(File(root, "lang"), "en"), "vocab_pool.json")
    }

    /** What VocabStore writes: kotlinx, encodeDefaults, no nulls. */
    private fun pool(words: Int, count: Int, at: String) = (0 until words).joinToString(",", "{", "}") {
        "\"w$it\":{\"state\":\"used\",\"firstAt\":\"2026-11-01T10:00:00.000Z\",\"lastAt\":\"$at\",\"count\":$count}"
    }

    @Test
    fun aPushedRecordIsNotPulledBackOrPushedAgain() = runBlocking {
        val cloud = CountingTransport()
        val root = Files.createTempDirectory("echo").toFile()
        val d = Device(root, ::mergeRecords)
        val e = SyncEngine(Settings(), cloud, d, root, deliver = { it() })
        e.setUser("user-1")
        d.file().apply { parentFile.mkdirs(); writeText(pool(150, 1, "2026-11-01T10:00:00.000Z")) }
        e.enable()
        e.syncAndWait(null)

        // A call: every word said once more.
        d.file().writeText(pool(150, 2, "2026-11-15T14:00:00.000Z"))
        val saved0 = cloud.inner.saved
        val pulled0 = cloud.pulled
        e.syncAndWait(null)   // pushes the 150
        val pushedByCall = cloud.inner.saved - saved0
        val modified = d.file().lastModified()
        Thread.sleep(20)
        e.syncAndWait(null)   // the next pass
        e.syncAndWait(null)

        println("pushed by the call: $pushedByCall, pulled back after: ${cloud.pulled - pulled0}, " +
            "pushed again: ${cloud.inner.saved - saved0 - pushedByCall}, file rewritten: ${d.file().lastModified() != modified}")
        assertEquals(150, pushedByCall)
        assertEquals("nothing pushed twice", 0, cloud.inner.saved - saved0 - pushedByCall)
    }
}
