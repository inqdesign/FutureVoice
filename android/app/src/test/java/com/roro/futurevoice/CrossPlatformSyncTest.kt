package com.roro.futurevoice

import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.sync.ArrayKind
import com.roro.futurevoice.sync.BlobKind
import com.roro.futurevoice.sync.CrossPlatform
import com.roro.futurevoice.sync.InMemorySyncTransport
import com.roro.futurevoice.sync.SyncEngine
import com.roro.futurevoice.sync.SyncJson
import com.roro.futurevoice.sync.SyncKind
import com.roro.futurevoice.sync.SyncKindHandler
import com.roro.futurevoice.sync.SyncMerge
import com.roro.futurevoice.sync.SyncPaths
import com.roro.futurevoice.sync.SyncRegistry
import com.roro.futurevoice.sync.SyncSettings
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * What an iPhone or Mac syncing over the same Google Drive folder needs from
 * Android (iOS 8b82321e, the 2026-11-05 audit): nothing iOS writes may be
 * deleted because Android can't read it, and what Android writes must be
 * readable on iOS.
 */
class CrossPlatformSyncTest {

    // ── Payload shapes ──────────────────────────────────────────────────

    @Test
    fun aRetiredCardIsWrittenWithTheDateIosCanRead() {
        assertEquals(64_092_211_200_000L, DrillIngest.RETIRED_REVIEW_AT)
        val s = StoreJson.json.encodeToString(IsoDateMillisSerializer, DrillIngest.RETIRED_REVIEW_AT)
        assertEquals("\"4001-01-01T00:00:00Z\"", s)
        // An in-memory Long.MAX_VALUE from an older path is clamped too.
        assertEquals(s, StoreJson.json.encodeToString(IsoDateMillisSerializer, Long.MAX_VALUE))
    }

    @Test
    fun anOldRetiredDateGoesUpAsIosWritesIt() {
        val old = card("""{"id":"C1","box":5,"nextReviewAt":"+292278994-08-17T07:12:55Z"}""")
        assertEquals("4001-01-01T00:00:00Z", CrossPlatform.retiredDate(old)["nextReviewAt"]!!.jsonPrimitive.content)
        val normal = card("""{"id":"C2","box":2,"nextReviewAt":"2026-11-09T10:00:00Z"}""")
        assertEquals(normal, CrossPlatform.retiredDate(normal))
        val ios = card("""{"id":"C3","box":5,"nextReviewAt":"4001-01-01T00:00:00Z"}""")
        assertEquals(ios, CrossPlatform.retiredDate(ios))
    }

    @Test
    fun anOldRetiredDateIsRepairedOnRead() {
        val c = StoreJson.json.decodeFromString(ListSerializer(com.roro.futurevoice.talk.DrillCard.serializer()),
            """[{"id":"C1","sourcePhrase":"a","targetPhrase":"b","reason":"","createdAt":"2026-10-01T00:00:00Z",
               "lastReviewedAt":"2026-10-02T00:00:00Z","nextReviewAt":"+292278994-08-17T07:12:55Z","box":5}]""")
            .single()
        assertEquals(DrillIngest.RETIRED_REVIEW_AT, DrillIngest.retired(c).nextReviewAt)
    }

    @Test
    fun aPhraseTakeCarriesBothShapes() {
        val android = card("""{"id":"A","phraseFirst":2,"phraseLast":4}""")
        assertEquals(listOf(2, 4), CrossPlatform.phraseBothWays(android)["phraseRange"]!!.jsonArray.map { it.jsonPrimitive.int })
        val ios = card("""{"id":"B","phraseRange":[1,3]}""")
        val out = CrossPlatform.phraseBothWays(ios)
        assertEquals(1, out["phraseFirst"]!!.jsonPrimitive.int)
        assertEquals(3, out["phraseLast"]!!.jsonPrimitive.int)
        val whole = card("""{"id":"C"}""")
        assertEquals(whole, CrossPlatform.phraseBothWays(whole))
    }

    @Test
    fun anIosPhraseTakeIsAPhraseTakeHere() {
        val a = StoreJson.json.decodeFromString(ShadowAttempt.serializer(),
            """{"id":"X","turnId":"T","targetText":"the bank is closed","phraseRange":[1,2],
               "createdAt":"2026-11-01T00:00:00Z"}""")
        assertTrue(a.isPartial)
        assertEquals(1..2, a.phrase)
        // And one made here writes the iOS shape as well as its own.
        val mine = ShadowAttempt(turnId = "T", targetText = "x", phraseFirst = 0, phraseLast = 1)
        val json = StoreJson.json.encodeToString(ShadowAttempt.serializer(), mine)
        assertTrue(json.contains("\"phraseRange\""))
        assertTrue(json.contains("\"phraseFirst\""))
        val whole = ShadowAttempt(turnId = "T", targetText = "x")
        assertFalse(whole.isPartial)
        assertNull(whole.phraseRange)
    }

    // ── The engine ──────────────────────────────────────────────────────

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

    /** [strict] = this build's Android: its store only reads a card whose box
     *  is a number, and only `.wav` turn audio. Not strict = the other
     *  platform, which reads (and writes) more. */
    private class Device(val root: File, strict: Boolean) : SyncRegistry {
        private val paths = SyncPaths { name, lang ->
            if (lang == null) File(root, name) else File(File(File(root, "lang"), lang), name)
        }
        val drills = ArrayKind(SyncKind.DRILL, "drills.json", paths,
            mergeRule = { l, r -> SyncMerge.tombstoneWins(l, r, SyncMerge.typed { a, _ -> a }) },
            validate = if (strict) { o -> o["box"]!!.jsonPrimitive.int } else null)
        val turns = BlobKind(SyncKind.BLOB_TURN, { File(root, "turn-audio") },
            if (strict) { n -> n.endsWith(".wav") } else { _ -> true })
        private val list: List<SyncKindHandler> = listOf(drills, turns)
        override fun all() = list
        override fun handler(kind: SyncKind) = list.firstOrNull { it.kind == kind }
        override fun enrolledLanguages() = listOf("en")
        override fun cardSessionId(payload: String): String? = null
        override fun deleteTurnAudio(turnIds: List<String>) {}
        override fun newestVoiceSample(): File? = null

        fun file(name: String) = File(File(File(root, "lang"), "en"), name)
        fun write(name: String, json: String) = file(name).apply { parentFile.mkdirs(); writeText(json) }
        fun ids(name: String) = if (!file(name).exists()) emptySet() else
            SyncJson.readFile(file(name))!!.jsonArray.map { it.jsonObject["id"]!!.jsonPrimitive.content }.toSet()
        fun audio(name: String) = File(File(root, "turn-audio"), name)
    }

    private val cloud = InMemorySyncTransport()

    private fun device(strict: Boolean): Pair<Device, SyncEngine> {
        val root = Files.createTempDirectory("device").toFile()
        val d = Device(root, strict)
        val e = SyncEngine(Settings(), cloud, d, root, deliver = { it() })
        e.setUser("user-1")
        return d to e
    }

    @Test
    fun aCardThisStoreCantReadIsSetAsideNeverDeleted() = runBlocking {
        val (mac, a) = device(strict = false)
        mac.write("drills.json", """[{"id":"C1","box":"five"},{"id":"C2","box":2}]""")
        a.enable()

        val (phone, b) = device(strict = true)
        b.enable()
        // The readable card lands; the other never enters the file, where it
        // would make the store read the whole file as empty.
        assertEquals(setOf("C2"), phone.ids("drills.json"))

        // A few passes later nothing was tombstoned: the Mac still has both.
        b.syncAndWait(null); a.syncAndWait(null); b.syncAndWait(null); a.syncAndWait(null)
        assertEquals(setOf("C1", "C2"), mac.ids("drills.json"))
        assertEquals(setOf("C2"), phone.ids("drills.json"))
    }

    @Test
    fun audioThisDeviceDoesntPlayIsNeverFetchedOrDeleted() = runBlocking {
        val (mac, a) = device(strict = false)
        mac.audio("T1.mp3").apply { parentFile.mkdirs(); writeBytes(ByteArray(64) { 1 }) }
        mac.audio("T1.timings.json").writeBytes(ByteArray(16) { 2 })
        mac.audio("T2.wav").writeBytes(ByteArray(64) { 3 })
        a.enable(); a.syncAndWait(null)

        val (phone, b) = device(strict = true)
        b.enable(); b.syncAndWait(null)
        assertTrue(phone.audio("T2.wav").exists())
        assertFalse(phone.audio("T1.mp3").exists())

        b.syncAndWait(null); a.syncAndWait(null); b.syncAndWait(null); a.syncAndWait(null)
        assertTrue(mac.audio("T1.mp3").exists())
        assertTrue(mac.audio("T1.timings.json").exists())
        assertTrue(mac.audio("T2.wav").exists())
    }

    private fun card(s: String) = SyncJson.obj(s) as JsonObject
}
