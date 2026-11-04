package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.PronunciationResult
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

// MARK: - The ledger

/**
 * Every assessed take, per target language, written through ONE door by
 * every surface that measures pronunciation (shadow, say it again, the weekly
 * test's speak item, the speech take) — so pronunciation is read as a
 * TENDENCY across takes. Port of iOS `PronunciationLedger.swift` (14706881).
 *
 * A single take's word marks are noise (a piece boundary moved by half a
 * second changes WHICH words are marked); what holds across takes is the
 * SOUND. So the take screen says what this take's sounds were, the scorecard
 * axis is the mean over a month, and the week's coach is told the sounds
 * that stay low — all read from here.
 *
 * Device-local (`files/lang/<code>/pronunciation.json`), in iOS's shape.
 */
@Serializable
data class PronunciationEntry(
    /** The take's own id (`SpeechTake.id` / `ShadowAttempt.id`). */
    val id: String,
    @Serializable(with = IsoDateMillisSerializer::class)
    val date: Long,
    /** "shadow" · "speech" (say it again and the test save as shadow attempts). */
    val surface: String,
    val locale: String,
    /** `PronunciationResult.soundScore` — Azure's accuracy, the sounds. */
    val accuracy: Int,
    /** Azure's PronScore, for the record. */
    val score: Int,
    val prosody: Int? = null,
    /** Every JUDGED word with its score. */
    val words: List<WordScore> = emptyList(),
    /** Every NAMED phoneme occurrence (en-US only; empty elsewhere). */
    val phonemes: List<PhonemeScore> = emptyList(),
) {
    @Serializable data class WordScore(val w: String, val a: Int)
    @Serializable data class PhonemeScore(val p: String, val a: Int)

    companion object {
        /** One entry from one or more results (a speech take is several pieces). */
        fun of(id: String, date: Long, surface: String, results: List<PronunciationResult>): PronunciationEntry? {
            val first = results.firstOrNull() ?: return null
            val judged = results.flatMap { it.judgedWords }
            val weight = results.map { maxOf(1, it.judgedWords.size) }
            val total = weight.sum()
            val prosodies = results.mapNotNull { it.prosody }
            return PronunciationEntry(
                id = id, date = date, surface = surface, locale = first.locale,
                accuracy = results.zip(weight).sumOf { (r, w) -> r.soundScore * w } / total,
                score = results.zip(weight).sumOf { (r, w) -> r.score * w } / total,
                prosody = if (prosodies.isEmpty()) null else prosodies.sum() / prosodies.size,
                words = judged.mapNotNull { w -> w.accuracy?.let { WordScore(w.word.lowercase(), it) } },
                phonemes = results.flatMap { it.namedPhonemes }.mapNotNull { p ->
                    p.accuracy?.let { PhonemeScore(p.phoneme, it) } },
            )
        }
    }
}

class PronunciationLedger private constructor(private val context: Context) {

    companion object {
        const val KEEP_DAYS = 90
        const val MAX_ENTRIES = 400

        @Volatile private var instance: PronunciationLedger? = null
        fun shared(context: Context): PronunciationLedger =
            instance ?: synchronized(this) {
                instance ?: PronunciationLedger(context.applicationContext).also { instance = it }
            }
    }

    private val cache = HashMap<String, List<PronunciationEntry>>()
    private val lock = Any()

    private fun file(language: String) =
        File(LanguageScope.directory(context, language), "pronunciation.json")

    fun entries(language: String): List<PronunciationEntry> = synchronized(lock) {
        cache[language]?.let { return it }
        val loaded = runCatching {
            val f = file(language)
            if (!f.exists()) emptyList()
            else StoreJson.json.decodeFromString(ListSerializer(PronunciationEntry.serializer()), f.readText())
        }.getOrDefault(emptyList())
        cache[language] = loaded
        loaded
    }

    fun entry(id: String, language: String): PronunciationEntry? = entries(language).firstOrNull { it.id == id }

    /**
     * Records one take. Nothing is written for a take with no result, and a
     * take recorded twice replaces its own row.
     */
    fun record(results: List<PronunciationResult>, id: String, surface: String,
               language: String, date: Long = System.currentTimeMillis()): PronunciationEntry? {
        val entry = PronunciationEntry.of(id, date, surface, results) ?: return null
        synchronized(lock) {
            var all = entries(language).filter { it.id != id } + entry
            val cutoff = date - KEEP_DAYS * 86_400_000L
            all = all.filter { it.date >= cutoff }.sortedBy { it.date }
            if (all.size > MAX_ENTRIES) all = all.takeLast(MAX_ENTRIES)
            cache[language] = all
            runCatching {
                file(language).writeText(
                    StoreJson.json.encodeToString(ListSerializer(PronunciationEntry.serializer()), all))
            }
        }
        return entry
    }

    /** Test hook. */
    fun reset(language: String) = synchronized(lock) {
        cache.remove(language)
        file(language).delete()
    }
}

// MARK: - The learner's standing

/**
 * What the ledger says about a learner's pronunciation over a window: the
 * mean, the sounds (en-US) with how they average, and the words that keep
 * coming back low (every language). Pure over entries, so it is testable.
 */
data class PronunciationProfile(
    val takes: Int,
    val meanAccuracy: Int?,
    /** Every sound heard [MIN_SAMPLES] or more times, worst first. */
    val sounds: List<Sound>,
    /** Words judged in [MIN_WORD_TAKES]+ takes, worst first. */
    val words: List<WordTrend>,
) {
    data class Sound(val phoneme: String, val mean: Int, val count: Int)
    /** [takes] = distinct takes the word was judged in. */
    data class WordTrend(val word: String, val mean: Int, val takes: Int)

    val weakSounds: List<Sound> get() = sounds.filter { it.mean < WEAK_BAR }
    val weakWords: List<WordTrend> get() = words.filter { it.mean < WEAK_BAR }

    companion object {
        /** A sound under this, on average, is one to work on — the bar the
         *  word marks use for "shaky". */
        const val WEAK_BAR = 70
        /** Fewer occurrences than this and one word decides the sound. */
        const val MIN_SAMPLES = 4
        const val MIN_WORD_TAKES = 2
        const val WINDOW_DAYS = 30

        fun current(context: Context, language: String = LanguageScope.active(context),
                    now: Long = System.currentTimeMillis()): PronunciationProfile {
            val since = now - WINDOW_DAYS * 86_400_000L
            return build(PronunciationLedger.shared(context).entries(language).filter { it.date >= since })
        }

        fun build(entries: List<PronunciationEntry>): PronunciationProfile {
            val sounds = LinkedHashMap<String, MutableList<Int>>()
            data class Acc(var sum: Int = 0, var n: Int = 0, val takes: HashSet<String> = HashSet())
            val words = LinkedHashMap<String, Acc>()
            for (e in entries) {
                for (p in e.phonemes) sounds.getOrPut(p.p) { mutableListOf() }.add(p.a)
                for (w in e.words) {
                    val t = words.getOrPut(w.w) { Acc() }
                    t.sum += w.a; t.n += 1; t.takes.add(e.id)
                }
            }
            val soundRows = sounds.mapNotNull { (p, v) ->
                if (v.size < MIN_SAMPLES) null else Sound(p, v.sum() / v.size, v.size)
            }.sortedWith(compareBy<Sound>({ it.mean }, { it.phoneme }))
            val wordRows = words.mapNotNull { (w, t) ->
                if (t.takes.size < MIN_WORD_TAKES) null else WordTrend(w, t.sum / t.n, t.takes.size)
            }.sortedWith(compareBy<WordTrend>({ it.mean }, { it.word }))
            val mean = if (entries.isEmpty()) null else entries.sumOf { it.accuracy } / entries.size
            return PronunciationProfile(entries.size, mean, soundRows, wordRows)
        }

        // MARK: What to say about ONE take

        /** This take's own low sounds (en-US): each phoneme's mean within the
         *  take, under [WEAK_BAR], heard at least twice in it, worst first. */
        fun lowSounds(entry: PronunciationEntry, limit: Int = 3): List<Sound> {
            val by = LinkedHashMap<String, MutableList<Int>>()
            for (p in entry.phonemes) by.getOrPut(p.p) { mutableListOf() }.add(p.a)
            return by.mapNotNull { (p, v) ->
                if (v.size < 2) return@mapNotNull null
                val mean = v.sum() / v.size
                if (mean < WEAK_BAR) Sound(p, mean, v.size) else null
            }.sortedWith(compareBy<Sound>({ it.mean }, { it.phoneme })).take(limit)
        }
    }

    /** Words low in this take that were ALSO low across the profile — the
     *  only word-level claim worth making where no sound is named. */
    fun repeatedLowWords(entry: PronunciationEntry, limit: Int = 3): List<WordTrend> {
        val lowHere = entry.words.filter { it.a < WEAK_BAR }.map { it.w }.toSet()
        return weakWords.filter { it.word in lowHere }.take(limit)
    }

    /** One line for a take's row: sounds (en-US) or repeated words, or null
     *  when nothing stood out. */
    fun noteLine(context: Context, entry: PronunciationEntry): String? {
        val sounds = lowSounds(entry)
        if (sounds.isNotEmpty()) {
            return context.getString(R.string.sounds_to_work_on,
                sounds.joinToString(" · ") { "${it.phoneme} ${it.mean}" })
        }
        if (entry.phonemes.isNotEmpty()) return null
        val words = repeatedLowWords(entry)
        if (words.isEmpty()) return null
        return context.getString(R.string.keeps_coming_out_low, words.joinToString(" · ") { it.word })
    }

    /** The profile for a prompt (null when thin), in English, numbers only. */
    val promptLine: String? get() {
        val mean = meanAccuracy
        if (takes < 3 || mean == null) return null
        val parts = mutableListOf("mean accuracy $mean over $takes takes")
        if (weakSounds.isNotEmpty()) {
            parts += "weak sounds: " + weakSounds.take(4).joinToString(", ") { "${it.phoneme} ${it.mean} (×${it.count})" }
        } else if (sounds.isNotEmpty()) {
            parts += "no sound under $WEAK_BAR"
        }
        if (weakWords.isNotEmpty()) {
            parts += "words low in several takes: " + weakWords.take(4).joinToString(", ") { "${it.word} ${it.mean}" }
        }
        return parts.joinToString("; ")
    }
}
