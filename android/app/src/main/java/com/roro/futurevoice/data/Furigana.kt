package com.roro.futurevoice.data

import android.content.Context
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf

/**
 * Readings over the kanji of a Japanese line (振り仮名), for drawing above
 * it (`FuriganaText`) — port of iOS `Furigana.swift`. A learner who can't
 * read 駅 can't say the line out loud, and every surface that hands them a
 * Japanese line is asking them to say it (2026-10-17, learner feedback).
 *
 * **Where the readings come from.** iOS reads them off `CFStringTokenizer`
 * (`JapaneseMorph.words`, the Latin transcription as hiragana). Here they are
 * Sudachi's (`JapaneseDictionary.morphs`, mode B, `readingForm`) — the same
 * tokenizer `JapaneseMorph.words` already cuts with, whose readings matched
 * iOS's on all 228 kanji tokens measured (`JapaneseSudachiTest`). While the
 * dictionary isn't loaded (the asset pack still downloading, or an install
 * with none) there is NO reading to give — ICU's word breaker carries none —
 * so every line draws plain, exactly as with the setting off. Such a result
 * is not memoized, so the readings appear once the dictionary lands.
 *
 * The readings are cut so only the kanji carry one: 食べた reads た over 食,
 * nothing over べた. They are a machine's reading and can be wrong — 何
 * before で is なん, a split compound reads per piece — so the few common
 * misses are fixed by hand below. Nothing here is a grade: a wrong reading is
 * a display slip.
 */
object Furigana {

    /** Same key name as iOS's defaults key. */
    const val KEY = "futurevoice.furigana"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    // Snapshot state so every surface redraws the moment the call-settings
    // toggle flips (iOS: one `@AppStorage` key read by each view).
    @Volatile private var state: MutableState<Boolean>? = null

    private fun state(context: Context): MutableState<Boolean> =
        state ?: synchronized(this) {
            state ?: mutableStateOf(prefs(context).getBoolean(KEY, true)).also { state = it }
        }

    /** The learner's switch, default on. */
    fun enabled(context: Context): Boolean = state(context).value

    fun setEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY, value).apply()
        state(context).value = value
    }

    /** On for a Japanese target unless the learner turned it off. */
    fun isOn(context: Context): Boolean =
        LanguageScope.active(context) == "ja" && enabled(context)

    /** A stretch of the line: [reading] set only over kanji. The runs cover
     *  the text end to end, in order. Offsets are UTF-16 indices. */
    data class Run(val start: Int, val end: Int, val reading: String?)

    /** One segmented word with its reading (hiragana). */
    data class Token(val surface: String, val start: Int, val end: Int, val reading: String)

    /** Stands in for Sudachi in a JVM unit test. Never set in the app. */
    @Volatile internal var tokensOverride: ((String) -> List<Token>?)? = null

    /** The line's words with their readings, punctuation dropped (iOS
     *  `JapaneseMorph.words`), or null while no dictionary is loaded. */
    private fun tokens(text: String): List<Token>? {
        tokensOverride?.let { return it(text) }
        return JapaneseDictionary.morphs(text)
            ?.filter { m -> m.surface.any { it.isLetterOrDigit() } }
            // A word the dictionary can't read stands as written, like iOS's
            // token with no transcription — it then carries no ruby.
            ?.map { Token(it.surface, it.start, it.end, it.reading.ifEmpty { it.surface }) }
    }

    /** [text] cut into runs. Memoized: the call screen recomposes every line
     *  on each mic tick. */
    fun runs(text: String): List<Run> {
        synchronized(memo) { memo[text]?.let { return it } }
        if (text.none(::isKanji)) return if (text.isEmpty()) emptyList() else listOf(Run(0, text.length, null))
        val toks = tokens(text) ?: return listOf(Run(0, text.length, null))
        val out = compute(text, toks)
        synchronized(memo) {
            if (memo.size > 400) memo.clear()
            memo[text] = out
        }
        return out
    }

    fun hasRuby(text: String): Boolean = runs(text).any { it.reading != null }

    private val memo = HashMap<String, List<Run>>()

    internal fun clearMemoForTest() = synchronized(memo) { memo.clear() }

    private fun compute(text: String, tokens: List<Token>): List<Run> {
        val out = ArrayList<Run>()
        var cursor = 0
        fun plain(end: Int) {
            if (end > cursor) { out.add(Run(cursor, end, null)); cursor = end }
        }
        var i = 0
        while (i < tokens.size) {
            // A compound the tokenizer cuts in pieces, read as one.
            var surface = tokens[i].surface
            var reading = tokens[i].reading
            var last = i
            for ((joined, fixed) in COMPOUND_READINGS) {
                val s = StringBuilder()
                var j = i
                while (j < tokens.size && s.length < joined.length) { s.append(tokens[j].surface); j++ }
                if (s.toString() == joined && j - i > 1) {
                    surface = s.toString(); reading = fixed; last = j - 1; break
                }
            }
            WORD_READINGS[surface]?.let { reading = it }
            if (surface == "何" && i + 1 < tokens.size) {
                val next = tokens[i + 1].surface.firstOrNull()
                if (next != null && next in "をがもかにへと") reading = "なに"
            }
            plain(tokens[i].start)
            for ((base, r) in split(surface, reading)) {
                out.add(Run(cursor, cursor + base.length, r))
                cursor += base.length
            }
            i = last + 1
        }
        plain(text.length)
        return out
    }

    /** Readings the tokenizer gets wrong in everyday talk. */
    private val WORD_READINGS = mapOf(
        "明日" to "あした", "今日" to "きょう", "昨日" to "きのう", "一人" to "ひとり",
        "二人" to "ふたり", "大人" to "おとな", "上手" to "じょうず", "下手" to "へた",
    )

    /** Compounds the tokenizer cuts in two or three (一|日|中). */
    private val COMPOUND_READINGS = listOf(
        "一日中" to "いちにちじゅう", "今日中" to "きょうじゅう", "世界中" to "せかいじゅう",
    )

    // ── Okurigana ──

    /**
     * [surface] with its reading laid over the kanji only: 食べ/たべ →
     * [食:た][べ], 晩ご飯/ばんごはん → [晩:ばん][ご][飯:はん]. A word whose
     * kana can't be found in the reading keeps the whole reading over the
     * whole word, which is still right, only less precise.
     */
    fun split(surface: String, reading: String): List<Pair<String, String?>> {
        if (surface.none(::isKanji)) return listOf(surface to null)
        val runs = ArrayList<Pair<String, Boolean>>()
        for (ch in surface) {
            val k = isKanji(ch)
            val lastRun = runs.lastOrNull()
            if (lastRun != null && lastRun.second == k) runs[runs.size - 1] = (lastRun.first + ch) to k
            else runs.add(ch.toString() to k)
        }
        val read = hiragana(reading)
        match(runs, 0, read)?.let { return it }
        return if (read == hiragana(surface)) listOf(surface to null) else listOf(surface to read)
    }

    private fun match(runs: List<Pair<String, Boolean>>, at: Int, read: String): List<Pair<String, String?>>? {
        if (at >= runs.size) return if (read.isEmpty()) emptyList() else null
        val (text, kanji) = runs[at]
        if (!kanji) {
            val kana = hiragana(text)
            if (!read.startsWith(kana)) return null
            return match(runs, at + 1, read.substring(kana.length))?.let { listOf<Pair<String, String?>>(text to null) + it }
        }
        if (at + 1 == runs.size) return if (read.isEmpty()) null else listOf(text to read)
        // The kanji take at least one sound each; the kana after them must
        // start right where they end.
        for (take in 1..read.length) {
            match(runs, at + 1, read.substring(take))?.let {
                return listOf<Pair<String, String?>>(text to read.substring(0, take)) + it
            }
        }
        return null
    }

    fun isKanji(ch: Char): Boolean = ch.code in 0x4E00..0x9FFF || ch.code == 0x3005

    private fun hiragana(s: String): String = JapaneseMorph.soundSpelling(s)
}
