package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.AudioOnset
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechMetrics
import com.roro.futurevoice.data.WordSplitter
import java.io.File
import kotlin.math.log10
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Every number on a Speech result, computed in code — from the transcript
 * against the script, and from the recording's own loudness envelope (iOS
 * `SpeechAnalyzer`). No model decides a score here; `SpeechCoach` only writes
 * notes about them.
 */
object SpeechAnalyzer {

    /** A silence this long between two sounds counts as a pause. */
    const val PAUSE_SECONDS = 0.25
    /** A silence this long is a stall: the reader lost the line. */
    const val HESITATION_SECONDS = 1.5

    data class Phrase(val head: Float, val tail: Float)

    data class Envelope(
        val firstVoice: Double,
        val lastVoice: Double,
        val silences: List<Double>,
        val phrases: List<Phrase>,
    ) {
        val speakingSeconds: Double get() = maxOf(0.0, lastVoice - firstVoice)
    }

    /** `pronunciation` is the take's sound score (`PronunciationAssessor`), null
     *  when nothing assessed it — the take is then scored by the rules before
     *  sounds were measured (iOS 2026-11-04). */
    fun analyze(script: String, transcript: String, language: String, envelope: Envelope?,
                pronunciation: Int? = null): SpeechMetrics {
        val fillerCount = countFillers(transcript, script, language)
        val spoken = removingFillers(transcript, language, script)

        // Accuracy: the shadow diff (CJK by syllable, digits, contractions).
        // The PLAIN share, not the sqrt-curved shadow score (iOS 2026-10-14).
        val diff = ShadowScore.analyze(script, spoken, language)
        val accuracy = accuracy(diff)
        val missed = missedRuns(diff.steps, script, language)

        val band = SpeechLibrary.rateBand(language)
        val units = SpeechLibrary.units(spoken, language)
        val minutes = (envelope?.speakingSeconds ?: 0.0) / 60
        val rate = if (minutes > 0.05) (units / minutes).roundToInt() else 0
        val paceScore = paceScore(rate, band)

        // Pauses: compared, not matched — no word timings to place them.
        val breaks = sentenceBreaks(script)
        val clauses = clauseBreaks(script)
        val silences = envelope?.silences.orEmpty()
        val pauses = silences.count { it >= PAUSE_SECONDS }
        val hesitations = silences.count { it >= HESITATION_SECONDS }
        val pausesAtBreaks = minOf(pauses, breaks)
        val choppy = maxOf(0, pauses - (breaks + clauses) - 1)
        var pauseScore = if (breaks > 0) 100 * pausesAtBreaks / breaks else 100
        pauseScore -= 6 * choppy + 10 * hesitations
        pauseScore = clamp(pauseScore)

        val perMinute = if (minutes > 0.05) fillerCount / minutes else fillerCount.toDouble()
        val fillerScore = clamp(100 - (perMinute * 12).roundToInt())

        val steadiness = steadinessScore(envelope?.phrases.orEmpty())

        val coverage = coverage(diff.steps)
        val overall = overall(accuracy, paceScore, pauseScore, fillerScore, steadiness, coverage, pronunciation)

        return SpeechMetrics(
            accuracy = accuracy, rate = rate, rateLow = band.first, rateHigh = band.last,
            paceScore = paceScore, pausesAtBreaks = pausesAtBreaks, breaks = breaks,
            hesitations = hesitations, pauseScore = pauseScore, fillers = fillerCount,
            fillerScore = fillerScore, steadiness = steadiness, missed = missed, overall = overall,
            coverage = coverage,
            scoring = if (pronunciation == null) SCORING_WITHOUT_PRONUNCIATION else SCORING_VERSION,
            pronunciation = pronunciation,
            slips = slips(diff.steps, language, properNames(script)),
            scriptTokens = diff.targetTokenCount,
        )
    }

    /**
     * Words read differently from the script WITHIN the reading (iOS
     * `SpeechAnalyzer.slips`): a word changed, left out or added (a filler is
     * the filler count's), between the first and the last word read as
     * written. Stopping early is coverage's.
     */
    /**
     * Names in the script (a capital letter not at a sentence's start), in the
     * diff's lower case (iOS 2026-11-13). A transcriber spells a name its own
     * way (Wylder / Wilder) and the reader said it right, so a name read
     * "differently" is never a slip. Unspaced scripts have no capitals and get
     * none.
     */
    fun properNames(script: String): Set<String> {
        val out = mutableSetOf<String>()
        var sentenceStart = true
        for (token in script.split(Regex("\\s+")).filter { it.isNotEmpty() }) {
            val core = token.trim { isPunctuationOrSymbol(it) }
            val first = core.firstOrNull()
            if (!sentenceStart && first != null && first.isUpperCase() && core != "I" &&
                !core.startsWith("I'") && !core.startsWith("I’")) {
                core.lowercase().split(Regex("[^\\p{L}\\p{N}']+")).filter { it.isNotEmpty() }.forEach { out += it }
            }
            val tail = token.trimEnd { it in "\"'”’)]»" }
            sentenceStart = tail.lastOrNull()?.let { it in ".!?…:" } ?: false
        }
        return out
    }

    /** Swift's `.punctuationCharacters.union(.symbols)`. */
    private fun isPunctuationOrSymbol(c: Char): Boolean = when (Character.getType(c).toByte()) {
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION, Character.MATH_SYMBOL, Character.CURRENCY_SYMBOL,
        Character.MODIFIER_SYMBOL, Character.OTHER_SYMBOL -> true
        else -> false
    }

    fun slips(steps: List<ShadowScore.DiffStep>, language: String, names: Set<String> = emptySet()): Int {
        // Only inside what was read ([covered]): a stretch never read is
        // coverage's (iOS 2026-11-17).
        val read = covered(steps)
        val fillerWords = SpeechLibrary.fillers(language).map { it.lowercase() }.toSet()
        var index = -1
        var count = 0
        for (step in steps) {
            when (step.op) {
                ShadowScore.DiffOp.MATCH -> index++
                ShadowScore.DiffOp.SUB, ShadowScore.DiffOp.DEL -> {
                    index++
                    if (read[index] && (step.target ?: "").lowercase() !in names) count++
                }
                ShadowScore.DiffOp.INS ->
                    if (index >= 0 && index + 1 < read.size && read[index] && read[index + 1] &&
                        (step.learner ?: "").lowercase() !in fillerWords) count++
            }
        }
        return count
    }

    /**
     * The weighting (iOS `SpeechAnalyzer.overall`, 2026-11-04): with a
     * pronunciation score, accuracy 30%, pronunciation 25, pace 15, pauses 10,
     * fillers 10, steadiness 10 — everything but accuracy scaled by how far
     * into the script the reader got. Without one, the 2026-10-14 weighting:
     * accuracy 40%, pace 20, pauses 15, fillers 10, steadiness 15. The server
     * checks both.
     */
    fun overall(accuracy: Int, pace: Int, pause: Int, filler: Int, steadiness: Int, coverage: Double,
                pronunciation: Int? = null): Int {
        if (pronunciation == null) {
            val delivery = 0.20 * pace + 0.15 * pause + 0.10 * filler + 0.15 * steadiness
            return clamp((0.40 * accuracy + coverage * delivery).roundToInt())
        }
        val said = 0.25 * pronunciation + 0.15 * pace + 0.10 * pause + 0.10 * filler + 0.10 * steadiness
        return clamp((0.30 * accuracy + coverage * said).roundToInt())
    }

    /**
     * How far into the script the reader got, 0…1, over the diff's own script
     * tokens (iOS `SpeechAnalyzer.coverage`): the last script token MATCHED,
     * carried on through the substitutions right after it, plus one, over the
     * script's token count. A substitution with no match before it doesn't
     * count: the alignment pairs a word said after stopping with the script's
     * LAST token.
     */
    fun coverage(steps: List<ShadowScore.DiffStep>): Double {
        val read = covered(steps)
        if (read.isEmpty()) return 1.0
        return read.count { it }.toDouble() / read.size
    }

    /**
     * Which script tokens lie in a stretch that was READ (iOS `covered`,
     * 2026-11-17, founder: coverage is what was read, not how far the reader
     * got — reading only a script's last line was 95% of it). A stretch is
     * read where at least half of ten script tokens in a row matched, from
     * the first of those matches to the last: a word changed or dropped
     * inside it is still inside it, and so is a run of up to ten the
     * transcriber got wrong. Not read: a sentence skipped, the script after
     * the reader stopped, a stray word the alignment placed somewhere. A
     * misread word at either edge of a stretch belongs to it.
     */
    fun covered(steps: List<ShadowScore.DiffStep>): BooleanArray {
        val ops = steps.filter { it.op != ShadowScore.DiffOp.INS }.map { it.op }
        val n = ops.size
        val read = BooleanArray(n)
        if (n == 0) return read
        val before = IntArray(n + 1)
        for (i in 0 until n) before[i + 1] = before[i] + (if (ops[i] == ShadowScore.DiffOp.MATCH) 1 else 0)
        fun mark(start: Int, end: Int) {
            if ((before[end + 1] - before[start]) * 2 < end - start + 1) return
            val first = (start..end).firstOrNull { ops[it] == ShadowScore.DiffOp.MATCH } ?: return
            val last = (start..end).last { ops[it] == ShadowScore.DiffOp.MATCH }
            for (index in first..last) read[index] = true
        }
        for (start in 0..maxOf(0, n - 10)) mark(start, minOf(n - 1, start + 9))
        // The script's two ends have no ten tokens on one side: a reading
        // that stops after four words read four.
        for (size in 1 until minOf(10, n)) {
            mark(0, size - 1)
            mark(n - size, n - 1)
        }
        for (index in 1 until n) if (read[index - 1] && !read[index] && ops[index] == ShadowScore.DiffOp.SUB) read[index] = true
        for (index in n - 2 downTo 0) if (read[index + 1] && !read[index] && ops[index] == ShadowScore.DiffOp.SUB) read[index] = true
        return read
    }

    /** Which rules a take was scored by (iOS `scoringVersion`): 3 = with
     *  pronunciation in `overall`; a take older than 2 never goes onto a board. */
    const val SCORING_VERSION = 3
    /** The 2026-10-14 rules, which a take with no pronunciation is still scored by. */
    const val SCORING_WITHOUT_PRONUNCIATION = 2

    /** The plain share of the script said as written, 0–100. */
    fun accuracy(diff: ShadowScore.Analysis): Int = clamp((diff.ratio * 100).roundToInt())

    /** 100 inside the band; outside it, 3 points per percent too slow and 2
     *  per percent too fast. */
    fun paceScore(rate: Int, band: IntRange): Int {
        if (rate <= 0) return 0
        if (rate in band) return 100
        val slow = rate < band.first
        val edge = (if (slow) band.first else band.last).toDouble()
        val percentOff = kotlin.math.abs(rate - edge) / edge * 100
        return clamp(100 - (percentOff * (if (slow) 3 else 2)).roundToInt())
    }

    /** Sentence ends inside the script — the last one ends the speech. */
    fun sentenceBreaks(script: String): Int {
        val enders = setOf('.', '!', '?', '。', '！', '？')
        var count = 0
        var previousWasEnder = false
        for (ch in script) {
            val isEnder = ch in enders
            if (isEnder && !previousWasEnder) count++
            previousWasEnder = isEnder
        }
        return maxOf(0, count - 1)
    }

    fun clauseBreaks(script: String): Int =
        script.count { it in setOf(',', ';', ':', '、', '，', '—') }

    /** Filler sounds in the transcript, minus any the script itself has. */
    fun countFillers(transcript: String, script: String, language: String): Int =
        maxOf(0, fillerHits(transcript, language) - fillerHits(script, language))

    /** The transcript without its filler sounds — except those the SCRIPT
     *  itself says, kept where they sit as in the script (same word after or
     *  before). iOS `removingFillers(_:language:keepingThoseIn:)`: the Korean
     *  sample quotes 음 and 어, and a perfect read lost both. */
    fun removingFillers(text: String, language: String, script: String = ""): String {
        val fillers = SpeechLibrary.fillers(language)
        if (LanguageCatalog.writesSpaces(language)) {
            val scriptTokens = script.split(Regex("\\s+")).filter { it.isNotEmpty() }.map(::normalizedToken)
            val allowance = mutableMapOf<String, Int>()
            val after = mutableSetOf<String>()
            val before = mutableSetOf<String>()
            scriptTokens.forEachIndexed { i, t ->
                if (t !in fillers) return@forEachIndexed
                allowance[t] = (allowance[t] ?: 0) + 1
                if (i + 1 < scriptTokens.size) after += t + "|" + scriptTokens[i + 1]
                if (i > 0) before += scriptTokens[i - 1] + "|" + t
            }
            val tokens = text.split(Regex("\\s+")).filter { it.isNotEmpty() }
            val normal = tokens.map(::normalizedToken)
            val kept = mutableListOf<String>()
            tokens.forEachIndexed { i, token ->
                val t = normal[i]
                if (t !in fillers) { kept += token; return@forEachIndexed }
                val next = normal.getOrNull(i + 1).orEmpty()
                val prev = normal.getOrNull(i - 1).orEmpty()
                val left = allowance[t] ?: 0
                if (left > 0 && ((t + "|" + next) in after || (prev + "|" + t) in before)) {
                    allowance[t] = left - 1
                    kept += token
                }
            }
            return kept.joinToString(" ")
        }
        var out = text
        for (f in fillers.sortedByDescending { it.length }) {
            val scriptParts = script.split(f)
            var allowance = scriptParts.size - 1
            val after = (0 until allowance).mapNotNull { scriptParts[it + 1].firstOrNull() }.toSet()
            val before = (0 until allowance).mapNotNull { scriptParts[it].lastOrNull() }.toSet()
            val parts = out.split(f)
            if (parts.size < 2) continue
            val rebuilt = StringBuilder(parts[0])
            for (part in parts.drop(1)) {
                val fits = (part.firstOrNull()?.let { it in after } ?: false) ||
                    (rebuilt.lastOrNull()?.let { it in before } ?: false)
                if (allowance > 0 && fits) { rebuilt.append(f); allowance-- }
                rebuilt.append(part)
            }
            out = rebuilt.toString()
        }
        return out
    }

    private fun fillerHits(text: String, language: String): Int {
        val fillers = SpeechLibrary.fillers(language)
        if (LanguageCatalog.writesSpaces(language)) {
            return text.split(Regex("\\s+")).count { it.isNotEmpty() && normalizedToken(it) in fillers }
        }
        var rest = text
        var hits = 0
        for (f in fillers.sortedByDescending { it.length }) {
            val parts = rest.split(f)
            hits += parts.size - 1
            rest = parts.joinToString(" ")
        }
        return hits
    }

    private fun normalizedToken(token: String): String =
        token.lowercase().trim { SpeechPrompterTrack.isPunctuation(it) || isSymbol(it) }

    private fun isSymbol(ch: Char): Boolean = when (Character.getType(ch).toByte()) {
        Character.MATH_SYMBOL, Character.CURRENCY_SYMBOL, Character.MODIFIER_SYMBOL, Character.OTHER_SYMBOL -> true
        else -> false
    }

    /** One script word as the take read it — iOS `ScriptMark`. [heard] is
     *  what the mic wrote for a word read differently, null otherwise;
     *  [added] are words said after this one that the script doesn't have. */
    data class ScriptMark(val word: String, val op: ShadowScore.DiffOp, val heard: String?,
                          val added: List<String> = emptyList())

    /**
     * The script, paragraph by paragraph, every word marked against the take
     * — iOS `SpeechAnalyzer.marks`. Null when the diff's tokens can't be laid
     * back onto the script's words; the page shows the old list then.
     */
    fun marks(script: String, transcript: String, language: String): List<List<ScriptMark>>? {
        val spoken = removingFillers(transcript, language, script)
        val steps = ShadowScore.analyze(script, spoken, language).steps
        val paragraphs = script.split('\n').map { WordSplitter.timingWords(it, language) }
        val words = paragraphs.flatten()
        val spans = ShadowScore.tokenSpans(words, language)
        val ops = ShadowScore.targetOps(steps)
        if (words.isEmpty() || (spans.lastOrNull()?.let { it.last + 1 } ?: 0) != ops.size) return null

        val wordOfSlot = ArrayList<Int>()
        spans.forEachIndexed { i, span -> repeat(span.count()) { wordOfSlot.add(i) } }
        val heard = List(words.size) { mutableListOf<String>() }
        val added = List(words.size) { mutableListOf<String>() }
        var next = 0
        for (step in steps) {
            if (step.op == ShadowScore.DiffOp.INS) {
                if (next > 0 && next < wordOfSlot.size && wordOfSlot[next - 1] == wordOfSlot[next]) {
                    step.learner?.let { heard[wordOfSlot[next]].add(it) }
                } else if (next > 0 && next - 1 < wordOfSlot.size) {
                    step.learner?.let { added[wordOfSlot[next - 1]].add(it) }
                }
                continue
            }
            if (step.op != ShadowScore.DiffOp.DEL) step.learner?.let { heard[wordOfSlot[next]].add(it) }
            next++
        }
        val joiner = if (LanguageCatalog.tokenStyle(language) == LanguageCatalog.TokenStyle.WORD) " " else ""
        var w = 0
        return paragraphs.map { paragraph ->
            paragraph.map { word ->
                val slice = spans[w].map { ops[it] }
                val op = when {
                    slice.all { it == ShadowScore.DiffOp.MATCH } -> ShadowScore.DiffOp.MATCH
                    slice.all { it == ShadowScore.DiffOp.DEL } -> ShadowScore.DiffOp.DEL
                    else -> ShadowScore.DiffOp.SUB
                }
                ScriptMark(word, op, if (op == ShadowScore.DiffOp.SUB) heard[w].joinToString(joiner) else null, added[w])
                    .also { w++ }
            }
        }
    }

    /** Runs of script tokens skipped or changed, in script order, at most 12. */
    fun missedRuns(steps: List<ShadowScore.DiffStep>, script: String, language: String): List<String> {
        if (LanguageCatalog.tokenStyle(language) == LanguageCatalog.TokenStyle.SYLLABLE &&
            LanguageCatalog.writesSpaces(language)) {
            missedWords(steps, script)?.let { return it }
        }
        return missedRuns(steps, language)
    }

    /** Korean is compared by syllable, but a run of missed syllables is no
     *  place to look in the script ("으시" is a piece of 있으시죠). The missed
     *  syllables are walked back onto the script's words and a word with any
     *  missing is shown whole — iOS `missedWords`. Null when they can't be
     *  lined up (a digit spelled out for the diff). */
    fun missedWords(steps: List<ShadowScore.DiffStep>, script: String): List<String>? {
        val words = script.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val chars = mutableListOf<Pair<Char, Int>>()
        words.forEachIndexed { i, w -> w.lowercase().forEach { if (it.isLetterOrDigit()) chars += it to i } }
        var cursor = 0
        val missed = sortedSetOf<Int>()
        for (step in steps) {
            if (step.op == ShadowScore.DiffOp.INS) continue
            val t = step.target ?: return null
            if (t.length != 1) return null
            var j = cursor
            while (j < chars.size && chars[j].first != t[0]) j++
            if (j >= chars.size || j - cursor > 2) return null
            if (step.op != ShadowScore.DiffOp.MATCH) missed += chars[j].second
            cursor = j + 1
        }
        val runs = mutableListOf<String>()
        val current = mutableListOf<String>()
        var last: Int? = null
        for (i in missed) {
            if (last != null && i != last + 1 && current.isNotEmpty()) { runs += current.joinToString(" "); current.clear() }
            current += words[i].trim { !it.isLetterOrDigit() }
            last = i
        }
        if (current.isNotEmpty()) runs += current.joinToString(" ")
        return runs.filter { it.isNotEmpty() }.take(12)
    }

    fun missedRuns(steps: List<ShadowScore.DiffStep>, language: String): List<String> {
        val joiner = if (LanguageCatalog.tokenStyle(language) == LanguageCatalog.TokenStyle.WORD) " " else ""
        val runs = mutableListOf<String>()
        val current = mutableListOf<String>()
        for (step in steps) {
            if (step.op == ShadowScore.DiffOp.INS) continue
            if (step.op == ShadowScore.DiffOp.MATCH) {
                if (current.isNotEmpty()) { runs += current.joinToString(joiner); current.clear() }
            } else step.target?.let { current += it }
        }
        if (current.isNotEmpty()) runs += current.joinToString(joiner)
        // A lone CJK syllable is noise to show.
        val readable = if (joiner.isEmpty()) runs.filter { it.length >= 2 } else runs
        return readable.take(12)
    }

    /** A phrase that fades at its end is the commonest presentation fault. */
    fun steadinessScore(phrases: List<Phrase>): Int {
        val usable = phrases.filter { it.head > -80 && it.tail > -80 }
        if (usable.size < 2) return 100
        val meanDrop = usable.map { it.head - it.tail }.average().toFloat()
        val heads = usable.map { it.head }
        val mean = heads.average().toFloat()
        val spread = sqrt(heads.map { (it - mean) * (it - mean) }.average().toFloat())
        val score = 100 - 6 * maxOf(0f, meanDrop - 3) - 4 * maxOf(0f, spread - 4)
        return clamp(score.roundToInt())
    }

    fun clamp(v: Int): Int = v.coerceIn(0, 100)

    // MARK: - Envelope

    /** The take's loudness envelope (10 ms block RMS). Null when the file
     *  can't be read or holds no voice. */
    fun envelope(file: File): Envelope? {
        val pcm = WavPcm.read(file) ?: return null
        val block = maxOf(1, (0.01 * pcm.sampleRate).toInt())
        val count = pcm.samples.size / block
        if (count <= 10) return null
        val levels = FloatArray(count)
        for (b in 0 until count) {
            var sum = 0.0
            val start = b * block
            for (i in start until start + block) { val v = pcm.samples[i] / 32768.0; sum += v * v }
            levels[b] = sqrt(sum / block).toFloat()
        }
        return envelope(levels.toList(), 0.01)
    }

    /** The pure half, over block RMS levels — what the tests drive. */
    fun envelope(levels: List<Float>, blockSeconds: Double): Envelope? {
        val peak = levels.maxOrNull() ?: return null
        if (peak <= 1e-5f) return null
        val gate = peak * AudioOnset.SPEECH_GATE_RATIO
        val voiced = levels.map { it > gate }
        val first = voiced.indexOf(true)
        val last = voiced.lastIndexOf(true)
        if (first < 0 || last < 0) return null
        val minPauseBlocks = (PAUSE_SECONDS / blockSeconds).toInt()
        val silences = mutableListOf<Double>()
        val phrases = mutableListOf<Phrase>()
        var phraseStart = first
        var i = first
        while (i <= last) {
            if (voiced[i]) { i++; continue }
            var j = i
            while (j <= last && !voiced[j]) j++
            val gap = j - i
            if (gap >= minPauseBlocks) {
                silences += gap * blockSeconds
                phrases += phraseLevels(levels, phraseStart, i)
                phraseStart = j
            }
            i = j
        }
        phrases += phraseLevels(levels, phraseStart, last + 1)
        return Envelope(first * blockSeconds, (last + 1) * blockSeconds, silences, phrases)
    }

    private fun phraseLevels(levels: List<Float>, from: Int, until: Int): Phrase {
        val count = until - from
        if (count < 20) return Phrase(-100f, -100f)   // under 0.2 s: a word, not a phrase
        val headEnd = from + (count * 0.6).toInt()
        val tailStart = until - maxOf(1, (count * 0.25).toInt())
        fun db(a: Int, b: Int): Float {
            val slice = levels.subList(a, b)
            val mean = slice.sumOf { (it * it).toDouble() } / maxOf(1, slice.size)
            return (10 * log10(maxOf(mean, 1e-12))).toFloat()
        }
        return Phrase(db(from, headEnd), db(tailStart, until))
    }
}
