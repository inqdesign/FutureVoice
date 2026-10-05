package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.AudioOnset
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechMetrics
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

    fun analyze(script: String, transcript: String, language: String, envelope: Envelope?): SpeechMetrics {
        val fillerCount = countFillers(transcript, script, language)
        val spoken = removingFillers(transcript, language)

        // Accuracy: the shadow diff (CJK by syllable, digits, contractions).
        val diff = ShadowScore.analyze(script, spoken, language)
        val missed = missedRuns(diff.steps, language)

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
        val choppy = maxOf(0, pauses - (breaks + clauses) - 2)
        var pauseScore = if (breaks > 0) 100 * pausesAtBreaks / breaks else 100
        pauseScore -= 5 * choppy + 8 * hesitations
        pauseScore = clamp(pauseScore)

        val perMinute = if (minutes > 0.05) fillerCount / minutes else fillerCount.toDouble()
        val fillerScore = clamp(100 - (perMinute * 12).roundToInt())

        val steadiness = steadinessScore(envelope?.phrases.orEmpty())

        val overall = clamp((
            0.40 * diff.score + 0.20 * paceScore + 0.15 * pauseScore + 0.10 * fillerScore + 0.15 * steadiness
        ).roundToInt())

        return SpeechMetrics(
            accuracy = diff.score, rate = rate, rateLow = band.first, rateHigh = band.last,
            paceScore = paceScore, pausesAtBreaks = pausesAtBreaks, breaks = breaks,
            hesitations = hesitations, pauseScore = pauseScore, fillers = fillerCount,
            fillerScore = fillerScore, steadiness = steadiness, missed = missed, overall = overall,
        )
    }

    /** 100 inside the band; 2 points per percent outside it. */
    fun paceScore(rate: Int, band: IntRange): Int {
        if (rate <= 0) return 0
        if (rate in band) return 100
        val edge = (if (rate < band.first) band.first else band.last).toDouble()
        val percentOff = kotlin.math.abs(rate - edge) / edge * 100
        return clamp(100 - (percentOff * 2).roundToInt())
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

    fun removingFillers(text: String, language: String): String {
        val fillers = SpeechLibrary.fillers(language)
        if (LanguageCatalog.writesSpaces(language)) {
            return text.split(Regex("\\s+")).filter { it.isNotEmpty() && normalizedToken(it) !in fillers }
                .joinToString(" ")
        }
        var out = text
        for (f in fillers.sortedByDescending { it.length }) out = out.replace(f, "")
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

    /** Runs of script tokens skipped or changed, in script order, at most 12. */
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
