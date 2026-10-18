package com.roro.futurevoice

import com.roro.futurevoice.data.BackupStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.util.Base64
import kotlin.random.Random

/** The envelope is streamed both ways (an 80 MB export died allocating one
 *  string, 2026-10-18) and must stay the format iOS reads and writes. */
class BackupStreamTest {

    private fun dir() = Files.createTempDirectory("bk").toFile()

    @Test
    fun aLibraryComesBackByteForByte() {
        val root = dir()
        val big = Random(1).nextBytes(3 * 1024 * 1024 + 7)
        File(root, "lang/ko").mkdirs()
        File(root, "lang/ko/sessions.json").writeText("""[{"id":"A","title":"카페 \"주문\""}]""")
        File(root, "turn-audio").mkdirs()
        File(root, "turn-audio/T1.wav").writeBytes(big)
        File(root, "empty.json").writeBytes(ByteArray(0))
        val files = root.walkTopDown().filter { it.isFile }.toList()

        val out = ByteArrayOutputStream()
        BackupStream.write(root, files, mapOf("futurevoice.targetLanguage" to "String:ko"), out)

        assertEquals(3, BackupStream.countFiles(out.toByteArray().inputStream()))
        val staging = dir()
        val parsed = BackupStream.read(out.toByteArray().inputStream(), staging)
        assertEquals(2, parsed.version)
        assertEquals(3, parsed.files.size)
        assertEquals(mapOf("futurevoice.targetLanguage" to "String:ko"), parsed.defaults)
        assertArrayEquals(big, File(staging, "turn-audio/T1.wav").readBytes())
        assertEquals("""[{"id":"A","title":"카페 \"주문\""}]""", File(staging, "lang/ko/sessions.json").readText())
        assertEquals(0, File(staging, "empty.json").length())

        // An older build reads it with the old in-memory decoder.
        val old = com.roro.futurevoice.data.StoreJson.json.decodeFromString(
            com.roro.futurevoice.data.BackupService.Envelope.serializer(), out.toString(Charsets.UTF_8))
        assertEquals(3, old.files.size)
        assertArrayEquals(big, Base64.getDecoder().decode(old.files.first { it.path.endsWith("T1.wav") }.data))
    }

    @Test
    fun anIphoneEnvelopeOpens() {
        // JSONEncoder: keys in its own order, every "/" escaped — in the path
        // AND inside the Base64 data.
        val bytes = byteArrayOf(-1, -2, -3, 0x3f, 0x7e, 0x10)
        val b64 = Base64.getEncoder().encodeToString(bytes).replace("/", "\\/")
        val env = """
            {
              "files" : [ { "data" : "$b64", "path" : "lang\/en\/drills.json" } ],
              "defaults" : { "futurevoice.proficiency" : "String:b1" },
              "createdAt" : "2026-10-01T10:00:00Z",
              "version" : 2
            }
        """.trimIndent()
        val staging = dir()
        val parsed = BackupStream.read(env.byteInputStream(), staging)
        assertEquals(listOf("lang/en/drills.json"), parsed.files)
        assertArrayEquals(bytes, File(staging, "lang/en/drills.json").readBytes())
        assertEquals("String:b1", parsed.defaults?.get("futurevoice.proficiency"))
    }

    @Test
    fun aPathOutsideTheFolderIsRefused() {
        val data = Base64.getEncoder().encodeToString("x".toByteArray())
        val env = """{"version":2,"files":[{"path":"../../evil","data":"$data"}],"defaults":null}"""
        val staging = dir()
        val parsed = BackupStream.read(env.byteInputStream(), staging)
        assertEquals(0, parsed.files.size)
        assertEquals(1, parsed.skipped)
        assertFalse(File(staging.parentFile.parentFile, "evil").exists())
    }
}
