package com.roro.futurevoice.data

import android.content.Context
import android.util.Log
import com.google.android.play.core.assetpacks.AssetPackManager
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import com.google.android.play.core.assetpacks.AssetPackState
import com.google.android.play.core.assetpacks.AssetPackStateUpdateListener
import com.google.android.play.core.assetpacks.model.AssetPackStatus
import com.worksap.nlp.sudachi.Config
import com.worksap.nlp.sudachi.DictionaryFactory
import com.worksap.nlp.sudachi.Tokenizer
import java.io.File
import java.util.concurrent.Executors

/**
 * Sudachi (mode B, SudachiDict SMALL) — how Android cuts Japanese the way
 * iOS's `CFStringTokenizer` does, and where a token's READING comes from.
 *
 * ICU's `BreakIterator` agreed with iOS's cuts on 6 of 40 sentences; Sudachi
 * mode B agrees on 86 of 88, and the headwords `JapaneseMorph.headwords`
 * reads off them on 87 of 88. Its readings match iOS's on all 228 kanji
 * tokens measured (`JapaneseSudachiTest` pins all three).
 *
 * The dictionary is 123 MB, so it is NOT in the app: it is the on-demand Play
 * asset pack `ja_dict`, fetched only when Japanese becomes a target
 * ([ensure], from `LanguageScope.setActive` and at launch). Play installs an
 * on-demand pack as plain files, so the dictionary is memory-mapped where it
 * lies. Until it is loaded — or forever, on an install that didn't come from
 * Play (a sideloaded APK has no packs) — everything falls back to ICU and the
 * forms table, exactly as before.
 */
object JapaneseDictionary {

    const val PACK = "ja_dict"
    /** Where `:ja_dict:fetchSudachiDict` puts it inside the pack's assets. */
    const val DICTIONARY_PATH = "sudachi/system_small.dic"

    private const val TAG = "JapaneseDictionary"

    /** One token: its surface, where it sat in the text, and its reading in
     *  hiragana ("" when the dictionary has none — an unknown word). */
    data class Morph(val surface: String, val start: Int, val end: Int, val reading: String)

    /** A loaded dictionary. Sudachi's `Dictionary` is read-only and shared;
     *  its `Tokenizer` keeps per-call lattice state and is NOT thread-safe,
     *  so each thread gets its own (they are cheap — a view on the dictionary). */
    private class Loaded(val dictionary: com.worksap.nlp.sudachi.Dictionary) {
        val tokenizer: ThreadLocal<Tokenizer> = ThreadLocal.withInitial { dictionary.create() }
    }

    @Volatile private var loaded: Loaded? = null

    /** Every pack call and the load itself run here, one at a time, off main. */
    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "ja-dict").apply { isDaemon = true } }

    private var listening = false
    /** Play is holding the download for the learner's OK — the status it
     *  is waiting in (a large pack on cellular, or an install Play didn't
     *  make). Shown once per process from the next resumed activity. */
    @Volatile private var awaitingConfirmation: Int? = null
    private var confirmationAsked = false

    val isReady: Boolean get() = loaded != null

    /**
     * Make sure a Japanese learner has the dictionary: load it if the pack is
     * installed, otherwise ask Play for it. Idempotent and non-blocking.
     */
    fun ensure(context: Context) {
        if (loaded != null) return
        val app = context.applicationContext
        worker.execute { runCatching { ensureNow(app) }.onFailure { warn("ensure failed", it) } }
    }

    private fun ensureNow(app: Context) {
        if (loaded != null) return
        val manager = AssetPackManagerFactory.getInstance(app)
        if (loadInstalled(manager)) return
        if (!listening) {
            manager.registerListener(listener(app))
            listening = true
        }
        // No Wi-Fi-only switch exists in this API: Play itself holds a large
        // download on cellular for the learner's OK (REQUIRES_USER_CONFIRMATION
        // below). A pack this size (~42 MB) normally downloads straight away.
        manager.fetch(listOf(PACK)).addOnFailureListener { e ->
            // A sideloaded or debug install has no packs (APP_UNAVAILABLE):
            // ICU keeps working, nothing to tell anyone.
            info("fetch refused: ${e.message}")
        }
    }

    private fun loadInstalled(manager: AssetPackManager): Boolean {
        val dir = manager.getPackLocation(PACK)?.assetsPath() ?: return false
        val file = File(dir, DICTIONARY_PATH)
        if (!file.isFile) return false
        load(file)
        return loaded != null
    }

    private fun listener(app: Context) = AssetPackStateUpdateListener { state: AssetPackState ->
        if (state.name() != PACK) return@AssetPackStateUpdateListener
        when (state.status()) {
            AssetPackStatus.COMPLETED -> worker.execute {
                runCatching { loadInstalled(AssetPackManagerFactory.getInstance(app)) }
                    .onFailure { warn("load after download failed", it) }
            }
            AssetPackStatus.REQUIRES_USER_CONFIRMATION, AssetPackStatus.WAITING_FOR_WIFI ->
                awaitingConfirmation = state.status()
            AssetPackStatus.FAILED -> {
                warn("download failed: ${state.errorCode()}")
                com.roro.futurevoice.core.Analytics.capture("ja_dict_failed",
                    mapOf("error" to state.errorCode()))
            }
            else -> Unit
        }
    }

    /**
     * Play's own cellular-data dialog, when it is holding the download for
     * one — its words, not ours. Called from `MainActivity.onResume`; asks
     * at most once per process, so a "no" is not repeated every resume.
     */
    fun confirmIfNeeded(activity: android.app.Activity) {
        val status = awaitingConfirmation ?: return
        if (confirmationAsked || loaded != null) return
        confirmationAsked = true
        runCatching {
            val manager = AssetPackManagerFactory.getInstance(activity)
            @Suppress("DEPRECATION")
            if (status == AssetPackStatus.WAITING_FOR_WIFI) manager.showCellularDataConfirmation(activity)
            else manager.showConfirmationDialog(activity)
        }.onFailure { warn("confirmation dialog failed", it) }
    }

    /** Memory-maps [file] and builds the tokenizer. Blocking — the worker's,
     *  or a test's. */
    @Synchronized
    fun load(file: File) {
        if (loaded != null) return
        val heap0 = usedHeapMb()
        val t0 = System.nanoTime()
        runCatching {
            // The classpath config (`sudachi.json` in the jar) names the
            // plugins and `char.def` / `unk.def` / `rewrite.def`, which load
            // from the jar too; only the system dictionary is the pack's.
            val config = Config.defaultConfig().systemDictionary(file.toPath())
            val dictionary = DictionaryFactory().create(config)
            val l = Loaded(dictionary)
            l.tokenizer.get()!!.tokenize(Tokenizer.SplitMode.B, "日本語")   // warm the first lattice
            loaded = l
        }.onSuccess {
            val ms = (System.nanoTime() - t0) / 1_000_000
            info("loaded in $ms ms (heap +${usedHeapMb() - heap0} MB, ${file.length() / (1024 * 1024)} MB mapped)")
        }.onFailure { warn("load failed", it) }
    }

    // android.util.Log is a throwing stub on a JVM test; a log line is never
    // worth a failure.
    private fun info(message: String) { runCatching { Log.i(TAG, message) } }
    private fun warn(message: String, error: Throwable? = null) {
        runCatching { Log.w(TAG, message, error) }
    }

    private fun usedHeapMb(): Long =
        Runtime.getRuntime().let { (it.totalMemory() - it.freeMemory()) / (1024 * 1024) }

    /** Mode-B tokens of [text] (punctuation included — callers filter), or
     *  null while no dictionary is loaded. */
    fun morphs(text: String): List<Morph>? {
        val l = loaded ?: return null
        if (text.isEmpty()) return emptyList()
        return runCatching {
            l.tokenizer.get()!!.tokenize(Tokenizer.SplitMode.B, text).map {
                Morph(it.surface(), it.begin(), it.end(), hiragana(it.readingForm()))
            }
        }.onFailure { warn("tokenize failed", it) }.getOrNull()
    }

    /** Katakana → hiragana, ー kept (iOS hands back hiragana readings). */
    fun hiragana(katakana: String): String {
        val out = StringBuilder(katakana.length)
        for (ch in katakana) out.append(if (ch.code in 0x30A1..0x30F6) (ch.code - 0x60).toChar() else ch)
        return out.toString()
    }

    /** Test seam: drops the loaded dictionary so no other JVM test sees it. */
    internal fun unloadForTest() { loaded = null }
}
