package com.roro.futurevoice.data

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.util.Base64

/**
 * One-file backup of everything the learner has built on this device — every
 * store under `filesDir` (all languages: sessions, drills, vocab, scenarios,
 * shadow attempts, the practice log, recordings), minus the regenerable TTS
 * cache.
 *
 * Same envelope as iOS `BackupService`: a versioned map of relative path →
 * file bytes, plus the `futurevoice.*` preferences. That is deliberate and
 * load-bearing — a backup written on an iPhone opens here and vice versa,
 * because both sides lay the same files down and their stores read them as
 * their own.
 *
 * **Files alone are NOT a backup.** Which files the stores even look at is
 * decided by preferences: `LanguageScope.active` reads
 * `futurevoice.targetLanguage` to resolve `lang/<code>/`, so an envelope
 * restored without them lays every file down correctly and then shows
 * nothing, because the install is pointed at a different language. Levels,
 * goals, enrolled languages and the daily call live there too.
 */
object BackupService {

    /** iOS writes 2 and reads 1; anything newer is refused rather than guessed at. */
    private const val VERSION = 2

    @Serializable data class Entry(val path: String, val data: String)

    @Serializable
    data class Envelope(
        val version: Int = VERSION,
        @Serializable(with = IsoDateMillisSerializer::class)
        val createdAt: Long = System.currentTimeMillis(),
        val files: List<Entry> = emptyList(),
        /** Preference key → the value, tagged so a restore can put it back. */
        val defaults: Map<String, String>? = null,
    )

    /** What a restore actually did — as opposed to what was in the file. */
    data class Report(val files: Int = 0, val defaults: Int = 0, val skipped: Int = 0)

    sealed interface Step {
        data object Scanning : Step
        data class Packing(val done: Int, val total: Int) : Step
        data object Encoding : Step
        data object Decoding : Step
        data class Writing(val done: Int, val total: Int) : Step
    }

    /**
     * Regenerable audio is skipped. It is the bulk of the bytes and every one
     * of them can be fetched again, so carrying it would turn a backup into a
     * transfer nobody finishes.
     */
    private val skipDirs = setOf("PhraseAudio", "TurnAudio", "tts-cache",
        // Drive sync's own index: a restored install must re-derive its
        // relationship with the cloud (iOS `excludedFolders`).
        "sync")

    suspend fun export(
        context: Context,
        onStep: (Step) -> Unit = {},
    ): File = withContext(Dispatchers.IO) {
        onStep(Step.Scanning)
        val root = context.filesDir
        val all = root.walkTopDown()
            .filter { it.isFile }
            .filterNot { f -> f.relativeTo(root).path.split(File.separator).any { it in skipDirs } }
            .toList()
        val prefs = context.getSharedPreferences("futurevoice", 0).all
            .filterKeys { it.startsWith("futurevoice.") }
            .mapValues { (_, v) -> "${v!!::class.simpleName}:$v" }
        val out = File(context.cacheDir, "nawana-backup.json")
        out.outputStream().buffered().use { stream ->
            BackupStream.write(root, all, prefs, stream) { i -> onStep(Step.Packing(i, all.size)) }
        }
        out
    }

    suspend fun import(
        context: Context,
        uri: Uri,
        onStep: (Step) -> Unit = {},
    ): Report = withContext(Dispatchers.IO) {
        onStep(Step.Decoding)
        // How many files, for the bar — a second cheap read, because the
        // envelope is streamed and its length isn't known until the end.
        val total = context.contentResolver.openInputStream(uri)?.use { BackupStream.countFiles(it) }
            ?: return@withContext Report()
        // Files land in a staging folder first: the version can come AFTER
        // the files in an iPhone's envelope, and a newer envelope must be
        // refused before anything is laid down.
        val staging = File(context.filesDir, ".restore-staging").apply { deleteRecursively(); mkdirs() }
        val parsed = try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                BackupStream.read(input, staging) { i -> onStep(Step.Writing(i, total)) }
            } ?: return@withContext Report()
        } catch (e: Exception) {
            staging.deleteRecursively()
            throw e
        }
        // A newer envelope is REFUSED, not guessed at: laying down files
        // whose shape this build does not know is how a restore silently
        // corrupts a library it was meant to save.
        if (parsed.version > VERSION) { staging.deleteRecursively(); return@withContext Report() }

        val root = context.filesDir
        var written = 0; var skipped = parsed.skipped
        for (path in parsed.files) {
            val target = File(root, path)
            // Never outside filesDir, whatever the envelope claims.
            if (!target.canonicalPath.startsWith(root.canonicalPath + File.separator)) { skipped++; continue }
            runCatching {
                target.parentFile?.mkdirs()
                val staged = File(staging, path)
                if (!staged.renameTo(target)) { staged.copyTo(target, overwrite = true) }
                written++
            }.onFailure { skipped++ }
        }
        staging.deleteRecursively()
        val env = Envelope(version = parsed.version, defaults = parsed.defaults)

        var restored = 0
        env.defaults?.let { d ->
            val edit = context.getSharedPreferences("futurevoice", 0).edit()
            for ((k, tagged) in d) {
                val type = tagged.substringBefore(':')
                val raw = tagged.substringAfter(':')
                when (type) {
                    "String" -> edit.putString(k, raw)
                    "Integer" -> raw.toIntOrNull()?.let { edit.putInt(k, it) }
                    "Long" -> raw.toLongOrNull()?.let { edit.putLong(k, it) }
                    "Float", "Double" -> raw.toFloatOrNull()?.let { edit.putFloat(k, it) }
                    "Boolean" -> edit.putBoolean(k, raw.toBoolean())
                    else -> continue
                }
                restored++
            }
            edit.apply()
        }
        // Every store reads from disk on its next query, so the app has to be
        // told the world changed — otherwise the restore is invisible until
        // a relaunch and reads as having done nothing.
        StoreEvents.bump()
        Report(files = written, defaults = restored, skipped = skipped)
    }
}
