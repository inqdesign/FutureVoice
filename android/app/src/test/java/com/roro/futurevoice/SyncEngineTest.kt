package com.roro.futurevoice

import com.roro.futurevoice.sync.ArrayKind
import com.roro.futurevoice.sync.BlobKind
import com.roro.futurevoice.sync.InMemorySyncTransport
import com.roro.futurevoice.sync.StringListKind
import com.roro.futurevoice.sync.SyncCascade
import com.roro.futurevoice.sync.SyncEngine
import com.roro.futurevoice.sync.SyncJson
import com.roro.futurevoice.sync.SyncJson.str
import com.roro.futurevoice.sync.SyncKind
import com.roro.futurevoice.sync.SyncKindHandler
import com.roro.futurevoice.sync.SyncMerge
import com.roro.futurevoice.sync.SyncPaths
import com.roro.futurevoice.sync.SyncRegistry
import com.roro.futurevoice.sync.SyncSettings
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * iOS `SyncTests`: two engines over one in-memory transport stand in for a
 * phone and a tablet — convergence, the deletion cascade, monotone card
 * progress, no ping-pong, audio as files.
 */
class SyncEngineTest {

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

    /** One device: its own files, the same kinds the app registers. */
    private class Device(val root: File) : SyncRegistry {
        private val paths = SyncPaths { name, lang ->
            if (lang == null) File(root, name) else File(File(File(root, "lang"), lang), name)
        }
        val sessions = ArrayKind(SyncKind.SESSION, "sessions.json", paths,
            mergeRule = { l, r -> if (r.deleted) null else SyncMerge.lww(l, r) },
            cascadeRule = { key, lang, previous ->
                listOf(SyncCascade.SessionDeleted(key,
                    (previous?.get("turns") as? JsonArray)?.mapNotNull { (it as? JsonObject)?.str("id") }.orEmpty(),
                    lang!!))
            })
        val drills = ArrayKind(SyncKind.DRILL, "drills.json", paths,
            mergeRule = { l, r -> SyncMerge.tombstoneWins(l, r, SyncMerge.typed { a, b ->
                val x = a as JsonObject; val y = b as JsonObject
                if (x["box"]!!.jsonPrimitive.int >= y["box"]!!.jsonPrimitive.int) x else y }) })
        val studying = StringListKind(SyncKind.VOCAB_STUDYING, "vocab_studying.json", paths, true, SyncMerge::lww)
        val turns = BlobKind(SyncKind.BLOB_TURN, { File(root, "turn-audio") })
        private val list: List<SyncKindHandler> = listOf(sessions, drills, studying, turns)
        override fun all() = list
        override fun handler(kind: SyncKind) = list.firstOrNull { it.kind == kind }
        override fun enrolledLanguages() = listOf("en")
        override fun cardSessionId(payload: String) = SyncJson.obj(payload)?.str("sourceSessionId")
        override fun deleteTurnAudio(turnIds: List<String>) =
            turnIds.forEach { File(File(root, "turn-audio"), "$it.wav").delete() }
        override fun newestVoiceSample(): File? = null

        fun file(name: String) = File(File(File(root, "lang"), "en"), name)
        fun write(name: String, json: String) = file(name).apply { parentFile.mkdirs(); writeText(json) }
        fun read(name: String) = if (file(name).exists())
            SyncJson.readFile(file(name))!!.jsonArray else JsonArray(emptyList())
    }

    private val cloud = InMemorySyncTransport()

    private fun device(): Pair<Device, SyncEngine> {
        val root = Files.createTempDirectory("device").toFile()
        val d = Device(root)
        val e = SyncEngine(Settings(), cloud, d, root, deliver = { it() })
        e.setUser("user-1")
        return d to e
    }

    private fun session(id: String, title: String, turnId: String = "T-$id") =
        """{"id":"$id","title":"$title","startedAt":"2026-10-01T10:00:00Z","turns":[{"id":"$turnId","text":"hi"}]}"""

    private fun card(id: String, session: String, box: Int) =
        """{"id":"$id","sourceSessionId":"$session","box":$box,"targetPhrase":"x"}"""

    @Test
    fun aTalkOnThePhoneArrivesOnTheTablet() = runBlocking {
        val (phone, a) = device()
        phone.write("sessions.json", "[${session("S1", "Coffee")}]")
        a.enable()

        val (tablet, b) = device()
        b.enable()
        val got = tablet.read("sessions.json")
        assertEquals(1, got.size)
        assertEquals("Coffee", got[0].jsonObject["title"]!!.jsonPrimitive.content)
    }

    @Test
    fun bothDevicesConvergeAndStopPushing() = runBlocking {
        val (phone, a) = device()
        val (tablet, b) = device()
        phone.write("sessions.json", "[${session("S1", "Coffee")}]")
        tablet.write("sessions.json", "[${session("S2", "Train")}]")
        a.enable(); b.enable(); a.syncAndWait(null)
        assertEquals(setOf("S1", "S2"), phone.read("sessions.json").map { it.jsonObject["id"]!!.jsonPrimitive.content }.toSet())
        assertEquals(setOf("S1", "S2"), tablet.read("sessions.json").map { it.jsonObject["id"]!!.jsonPrimitive.content }.toSet())

        // The loop guard: once in step, neither device pushes anything.
        val before = cloud.saved
        a.syncAndWait(null); b.syncAndWait(null); a.syncAndWait(null)
        assertEquals(before, cloud.saved)
    }

    @Test
    fun deletingATalkTakesItsCardsAndAudioEverywhere() = runBlocking {
        val (phone, a) = device()
        phone.write("sessions.json", "[${session("S1", "Coffee", "TURN1")}]")
        phone.write("drills.json", "[${card("C1", "S1", 1)},${card("C2", "OTHER", 1)}]")
        File(phone.root, "turn-audio").mkdirs(); File(phone.root, "turn-audio/TURN1.wav").writeBytes(ByteArray(64) { 1 })
        a.enable(); a.syncAndWait(null)

        val (tablet, b) = device()
        b.enable(); b.syncAndWait(null)
        assertTrue(File(tablet.root, "turn-audio/TURN1.wav").exists())
        assertEquals(2, tablet.read("drills.json").size)

        phone.write("sessions.json", "[]")
        a.syncAndWait(null)
        b.syncAndWait(null)
        assertEquals(0, tablet.read("sessions.json").size)
        assertEquals(listOf("C2"), tablet.read("drills.json").map { it.jsonObject["id"]!!.jsonPrimitive.content })
        assertFalse(File(tablet.root, "turn-audio/TURN1.wav").exists())
    }

    @Test
    fun cardProgressTakesTheHigherBox() = runBlocking {
        val (phone, a) = device()
        phone.write("drills.json", "[${card("C1", "S1", 1)}]")
        a.enable()
        val (tablet, b) = device()
        b.enable()
        // Reviewed on both, further on the tablet.
        phone.write("drills.json", "[${card("C1", "S1", 2)}]")
        tablet.write("drills.json", "[${card("C1", "S1", 4)}]")
        a.syncAndWait(null); b.syncAndWait(null); a.syncAndWait(null)
        assertEquals(4, phone.read("drills.json")[0].jsonObject["box"]!!.jsonPrimitive.int)
        assertEquals(4, tablet.read("drills.json")[0].jsonObject["box"]!!.jsonPrimitive.int)
    }

    @Test
    fun theNewestNotebookDecisionWins() = runBlocking {
        val (phone, a) = device()
        phone.write("vocab_studying.json", """["chore","boiler"]""")
        a.enable()
        val (tablet, b) = device()
        b.enable()
        assertEquals(setOf("chore", "boiler"), tablet.read("vocab_studying.json").map { it.jsonPrimitive.content }.toSet())
        // Removed on the tablet, later.
        tablet.write("vocab_studying.json", """["chore"]""")
        b.syncAndWait(null); a.syncAndWait(null)
        assertEquals(listOf("chore"), phone.read("vocab_studying.json").map { it.jsonPrimitive.content })
    }

    @Test
    fun anUnreadableFileIsNeverTombstoned() = runBlocking {
        val (phone, a) = device()
        phone.write("sessions.json", "[${session("S1", "Coffee")}]")
        a.enable()
        val (tablet, b) = device()
        b.enable()
        phone.write("sessions.json", "{ this is not json")
        a.syncAndWait(null); b.syncAndWait(null)
        assertEquals(1, tablet.read("sessions.json").size)
        assertTrue(JsonPrimitive(true).content == "true")
    }
}
