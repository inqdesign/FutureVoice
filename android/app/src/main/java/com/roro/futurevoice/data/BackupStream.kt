package com.roro.futurevoice.data

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.io.PushbackReader
import java.io.Reader
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Base64

/**
 * The backup envelope, written and read ONE FILE AT A TIME.
 *
 * Both directions used to hold the whole backup in memory — every file as a
 * Base64 string, then the envelope as one string around them — and a
 * learner's library with its recordings is tens of megabytes, so export died
 * with "Failed to allocate a 80984624 byte allocation" (2026-10-18). The
 * format is unchanged, byte for byte what `Envelope` serialized, so a backup
 * from an iPhone still opens here and the other way round:
 *
 *     {"version":2,"createdAt":"…","files":[{"path":"…","data":"<base64>"},…],
 *      "defaults":{"futurevoice.x":"Type:value",…}}
 *
 * A file's bytes go straight from disk through a Base64 stream into the
 * output, and on the way back from the JSON string through a Base64 stream
 * onto disk; nothing larger than a buffer is ever held.
 */
object BackupStream {

    // ── Writing ─────────────────────────────────────────────────────────

    fun write(root: File, files: List<File>, defaults: Map<String, String>, out: OutputStream,
              onFile: (Int) -> Unit = {}) {
        fun text(s: String) = out.write(s.toByteArray(Charsets.UTF_8))
        val created = DateTimeFormatter.ISO_INSTANT.format(Instant.now().truncatedTo(ChronoUnit.SECONDS))
        text("{\"version\":2,\"createdAt\":${quote(created)},\"files\":[")
        files.forEachIndexed { i, f ->
            if (i > 0) text(",")
            text("{\"path\":${quote(f.relativeTo(root).path)},\"data\":\"")
            // Base64's alphabet needs no JSON escaping, so the bytes go in raw.
            val b64 = Base64.getEncoder().wrap(NonClosing(out))
            f.inputStream().use { it.copyTo(b64) }
            b64.close() // writes the padding; the wrapper keeps `out` open
            text("\"}")
            onFile(i + 1)
        }
        text("],\"defaults\":{")
        defaults.entries.forEachIndexed { i, (k, v) ->
            if (i > 0) text(",")
            text("${quote(k)}:${quote(v)}")
        }
        text("}}")
        out.flush()
    }

    private class NonClosing(private val o: OutputStream) : OutputStream() {
        override fun write(b: Int) = o.write(b)
        override fun write(b: ByteArray, off: Int, len: Int) = o.write(b, off, len)
        override fun flush() = o.flush()
        override fun close() = o.flush()
    }

    fun quote(s: String): String = buildString {
        append('"')
        for (c in s) when (c) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (c < ' ') append("\\u%04x".format(c.code)) else append(c)
        }
        append('"')
    }

    // ── Reading ─────────────────────────────────────────────────────────

    data class Parsed(
        val version: Int,
        /** Relative paths written under the staging folder, in order. */
        val files: List<String>,
        val defaults: Map<String, String>?,
        /** Entries refused (a path outside the folder, a bad entry). */
        val skipped: Int,
    )

    /** How many files an envelope holds — counts `"path"` keys without
     *  decoding anything, for the progress bar. */
    fun countFiles(input: InputStream): Int {
        val needle = "\"path\"".toByteArray()
        var matched = 0; var count = 0
        val buf = ByteArray(64 * 1024)
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            for (i in 0 until n) {
                matched = if (buf[i] == needle[matched]) matched + 1 else if (buf[i] == needle[0]) 1 else 0
                if (matched == needle.size) { count++; matched = 0 }
            }
        }
        return count
    }

    /** Streams [input] and lays every file under [staging]. Keys may come in
     *  any order (an iPhone's encoder doesn't promise one). */
    fun read(input: InputStream, staging: File, onFile: (Int) -> Unit = {}): Parsed {
        val r = Lexer(input.bufferedReader(Charsets.UTF_8))
        var version = 1
        var defaults: Map<String, String>? = null
        val files = ArrayList<String>()
        var skipped = 0
        r.expect('{')
        r.members { key ->
            when (key) {
                "version" -> version = r.number().toInt()
                "files" -> {
                    r.expect('[')
                    r.elements {
                        var path: String? = null
                        var stagedTemp: File? = null
                        r.expect('{')
                        r.members { k ->
                            when (k) {
                                "path" -> path = r.string()
                                // The data usually follows the path, but not
                                // necessarily: decode to a temp file either
                                // way and move it once the path is known.
                                "data" -> {
                                    val tmp = File.createTempFile("entry", null, staging)
                                    tmp.outputStream().buffered().use { o ->
                                        Base64.getDecoder().wrap(r.stringStream()).use { it.copyTo(o) }
                                    }
                                    stagedTemp = tmp
                                }
                                else -> r.skipValue()
                            }
                        }
                        val p = path; val tmp = stagedTemp
                        val target = p?.let { File(staging, it) }
                        if (p == null || tmp == null || target == null ||
                            !target.canonicalPath.startsWith(staging.canonicalPath + File.separator)) {
                            tmp?.delete(); skipped++
                        } else {
                            target.parentFile?.mkdirs()
                            if (!tmp.renameTo(target)) { tmp.copyTo(target, overwrite = true); tmp.delete() }
                            files.add(p)
                            onFile(files.size)
                        }
                    }
                }
                "defaults" -> {
                    if (r.peekNull()) { r.skipValue() } else {
                        val m = LinkedHashMap<String, String>()
                        r.expect('{')
                        r.members { k -> if (r.peekString()) m[k] = r.string() else r.skipValue() }
                        defaults = m
                    }
                }
                else -> r.skipValue()
            }
        }
        return Parsed(version, files, defaults, skipped)
    }

    /** Just enough JSON for the envelope, with a string value that can be
     *  read as a stream (the file data) instead of materialized. */
    private class Lexer(reader: Reader) {
        private val r = PushbackReader(reader, 2)

        private fun read(): Int = r.read()
        private fun peek(): Int { val c = r.read(); if (c >= 0) r.unread(c); return c }
        private fun skipWs() { while (true) { val c = peek(); if (c == ' '.code || c == '\n'.code || c == '\r'.code || c == '\t'.code) read() else return } }

        fun expect(ch: Char) {
            skipWs()
            val c = read()
            if (c != ch.code) throw IllegalStateException("Not a nawana backup (expected '$ch')")
        }

        fun peekString(): Boolean { skipWs(); return peek() == '"'.code }
        fun peekNull(): Boolean { skipWs(); return peek() == 'n'.code }

        /** Calls [each] with every key of an object whose `{` was consumed. */
        fun members(each: (String) -> Unit) {
            skipWs()
            if (peek() == '}'.code) { read(); return }
            while (true) {
                val key = string()
                expect(':')
                each(key)
                skipWs()
                when (read()) {
                    ','.code -> continue
                    '}'.code -> return
                    else -> throw IllegalStateException("Broken backup file")
                }
            }
        }

        /** Calls [each] for every element of an array whose `[` was consumed. */
        fun elements(each: () -> Unit) {
            skipWs()
            if (peek() == ']'.code) { read(); return }
            while (true) {
                each()
                skipWs()
                when (read()) {
                    ','.code -> continue
                    ']'.code -> return
                    else -> throw IllegalStateException("Broken backup file")
                }
            }
        }

        fun string(): String {
            expect('"')
            val sb = StringBuilder()
            while (true) {
                val c = read()
                if (c < 0) throw IllegalStateException("Broken backup file")
                when (c) {
                    '"'.code -> return sb.toString()
                    '\\'.code -> sb.append(escape())
                    else -> sb.append(c.toChar())
                }
            }
        }

        private fun escape(): Char = when (val e = read()) {
            'n'.code -> '\n'; 't'.code -> '\t'; 'r'.code -> '\r'; 'b'.code -> '\b'; 'f'.code -> '\u000c'
            'u'.code -> String(CharArray(4) { read().toChar() }).toInt(16).toChar()
            else -> e.toChar() // \" \\ \/ — an iPhone escapes every slash
        }

        /** The current string value as bytes, unescaped, without holding it.
         *  Base64 is ASCII, so each char is one byte. */
        fun stringStream(): InputStream {
            expect('"')
            return object : InputStream() {
                var done = false
                override fun read(): Int {
                    if (done) return -1
                    val c = this@Lexer.read()
                    return when (c) {
                        -1 -> throw IllegalStateException("Broken backup file")
                        '"'.code -> { done = true; -1 }
                        '\\'.code -> escape().code
                        else -> c
                    }
                }
                override fun close() { while (!done) read() }
            }
        }

        fun number(): Double {
            skipWs()
            val sb = StringBuilder()
            while (true) {
                val c = peek()
                if (c < 0 || !(c.toChar().isDigit() || c.toChar() in "+-.eE")) break
                sb.append(read().toChar())
            }
            return sb.toString().toDouble()
        }

        fun skipValue() {
            skipWs()
            when (peek()) {
                '"'.code -> stringStream().use { while (it.read() >= 0) {} }
                '{'.code -> { read(); members { skipValue() } }
                '['.code -> { read(); elements { skipValue() } }
                else -> while (true) {
                    val c = peek()
                    if (c < 0 || c == ','.code || c == '}'.code || c == ']'.code) break
                    read()
                }
            }
        }
    }
}
