package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.LanguageCatalog
import kotlinx.serialization.Serializable
import java.io.File
import kotlin.math.max

/**
 * How a take was DELIVERED, beyond the words and the sounds — iOS
 * `SpeechDelivery`: Azure's prosody and fluency, the weakest sounds, where the
 * reader paused, how fast they read and how much their pitch moved. Numbers
 * only; no audio leaves the phone. Season 2's score reads its sound accuracy,
 * weakest sounds and median pitch; the rest goes on `speech_take`.
 */
data class SpeechDelivery(
    /** Azure prosody (en-US only) and fluency, weighted by judged words. */
    val prosody: Int? = null,
    val fluency: Int? = null,
    /** The 5th percentile of every judged sound's score. */
    val weakSounds: Int? = null,
    /** Pauses of [PAUSE_SECONDS] or more between two words with no punctuation
     *  between them, and how many such boundaries were measured. Null when the
     *  words couldn't be lined up with the script. */
    val midPauses: Int? = null,
    val midBoundaries: Int? = null,
    /** Words per minute of reading, sentence-end pauses left out. */
    val wordsPerMinute: Int? = null,
    /** Words Azure flagged as monotone (en-US only). */
    val monotoneWords: Int = 0,
    /** Pitch movement, semitones ([PitchTracker]). */
    val pitchRange: Double? = null,
    val pitchSD: Double? = null,
    /** The voice's median pitch, Hz. */
    val pitchMedianHz: Double? = null,
    /** Azure's sound accuracy, weighted by judged words. */
    val soundAccuracy: Int? = null,
    /** Where the mid-phrase pauses were, in reading order. */
    val breaks: List<Break> = emptyList(),
    /** Mid-phrase pauses of a second or more: the reader lost the line. */
    val stalls: Int = 0,
    /** The weakest sounds, worst first, each with the word it was in. */
    val weakest: List<Sound> = emptyList(),
    /** Words heard between script words that the script doesn't have. */
    val stumbles: List<String> = emptyList(),
    /** A word said again, or started and said again whole. */
    val repeats: List<String> = emptyList(),
    /** Pauses at punctuation longer than a narrator takes there. */
    val longPauses: List<Break> = emptyList(),
    /** Words heard and timed, for rates. */
    val spokenWords: Int = 0,
) {
    data class Break(val before: String, val after: String, val seconds: Double)

    @Serializable
    data class Sound(
        /** IPA (en-US); empty where Azure names no phonemes. */
        val phoneme: String,
        val word: String,
        val score: Int,
    )

    /** One assessed piece and the text it was judged against. [startMs] is
     *  where it begins in the whole take; its words are timed from its start. */
    data class Piece(val reference: String, val result: PronunciationResult, val startMs: Int = 0)

    /** What the boundary after a script token is. */
    enum class Stop { NONE, CLAUSE, SENTENCE, PARAGRAPH }
    data class RefToken(val core: String, val stop: Stop)

    companion object {
        const val PAUSE_SECONDS = 0.15
        const val STALL_SECONDS = 1.0
        const val COMMA_PAUSE_MAX = 0.45
        const val SENTENCE_PAUSE_MAX = 1.0
        const val PARAGRAPH_PAUSE_MAX = 1.6

        /** Spoken fillers Azure files as Insertions; the take's filler count already has them. */
        val FILLERS = setOf("um", "uh", "er", "erm", "ah", "uhm", "hmm", "mm", "eh")

        fun measure(pieces: List<Piece>, language: String, audio: File): SpeechDelivery {
            val d = timing(pieces, language)
            val p = pitch(audio) ?: return d
            return d.copy(
                pitchRange = SpeechReading.round(p.rangeSemitones * 10) / 10,
                pitchSD = SpeechReading.round(p.sdSemitones * 10) / 10,
                pitchMedianHz = SpeechReading.round(p.medianHz),
            )
        }

        fun pitch(audio: File): PitchTracker.Stats? {
            val pcm = WavPcm.read(audio) ?: return null
            if (pcm.samples.isEmpty()) return null
            val x = FloatArray(pcm.samples.size) { pcm.samples[it] / 32768f }
            return PitchTracker.stats(x, pcm.sampleRate.toDouble())
        }

        /** The part that reads only the assessments — what the tests drive. */
        fun timing(pieces: List<Piece>, language: String): SpeechDelivery {
            fun weighted(value: (PronunciationResult) -> Int?): Int? {
                var sum = 0; var total = 0
                for (p in pieces) {
                    val v = value(p.result) ?: continue
                    val w = max(1, p.result.judgedWords.size)
                    sum += v * w
                    total += w
                }
                return if (total > 0) sum / total else null
            }
            val sounds = pieces.flatMap { p -> p.result.judgedWords.flatMap { w -> w.phonemes.mapNotNull { it.accuracy } } }.sorted()
            val weak = if (sounds.isEmpty()) null else sounds[((sounds.size - 1) * 0.05).toInt()]

            var mid = 0; var boundaries = 0; var aligned = false
            val breaks = mutableListOf<Break>(); var stalls = 0
            val repeats = mutableListOf<String>(); val longPauses = mutableListOf<Break>(); var spoken = 0
            val weakest = pieces.flatMap { p ->
                p.result.judgedWords.flatMap { word ->
                    word.phonemes.mapNotNull { ph -> ph.accuracy?.let { Sound(ph.phoneme, word.word, it) } }
                }
            }.sortedBy { it.score }
            var words = 0; var seconds = 0.0
            val stumbles = mutableListOf<String>()
            val spaced = LanguageCatalog.writesSpaces(language)
            for (piece in pieces) {
                val all = piece.result.words
                // A stumble: a word Azure heard that the script doesn't have,
                // BETWEEN two script words. At a piece's edges an Insertion is
                // the prompter's cut landing a word early or late.
                val f = all.indexOfFirst { !it.isInsertion && !it.isOmission && it.durationMs > 0 }
                val l = all.indexOfLast { !it.isInsertion && !it.isOmission && it.durationMs > 0 }
                // A run of Insertions that comes WITH an Omission is one word
                // heard differently, not a stumble. Only a run with nothing
                // left out of the script is a word added.
                if (f >= 0 && l >= 0 && f < l) {
                    var i = f + 1
                    while (i < l) {
                        if (!all[i].isInsertion && !all[i].isOmission) { i++; continue }
                        var j = i
                        while (j < l && (all[j].isInsertion || all[j].isOmission)) j++
                        val run = all.subList(i, j)
                        if (run.none { it.isOmission }) {
                            run.filter { core(it.word) !in FILLERS }.forEach { stumbles += it.word }
                        }
                        i = j
                    }
                }

                // Repeats and restarts, in what was heard. A word said twice
                // counts unless the script says it twice there; a restart is a
                // word of four letters or more followed by a longer word that
                // begins with it ("quiet quietly").
                val heard = all.filter { !it.isOmission && it.durationMs > 0 }
                val pieceTokens = referenceTokens(piece.reference)
                val scriptPairs = pieceTokens.zipWithNext { a, b -> "${a.core} ${b.core}" }.toSet()
                for ((a, b) in heard.zipWithNext()) {
                    val ca = core(a.word); val cb = core(b.word)
                    if (ca.isEmpty() || ca in FILLERS) continue
                    // An Insertion is the stumble rule's: counted there, or
                    // one word heard differently.
                    if (a.isInsertion || b.isInsertion) continue
                    if (ca == cb && "$ca $cb" !in scriptPairs) repeats += b.word
                    else if (ca.length >= 4 && cb.length > ca.length && cb.startsWith(ca)) repeats += a.word
                }

                // Azure's words and the script's tokens don't always split the
                // same way, so they are lined up by content: a boundary is
                // judged only where its word found its script token.
                val saidAt = all.indices.filter { !all[it].isInsertion }
                val said = saidAt.map { all[it] }
                val ref = if (spaced) pieceTokens else emptyList()
                val match = align(said.map { core(it.word) }, ref.map { it.core })
                val matched = match.count { it != null }
                val lined = spaced && said.isNotEmpty() && matched >= 0.6 * said.size
                val timed = said.withIndex().filter { !it.value.isOmission && it.value.durationMs > 0 }
                val first = timed.firstOrNull()?.value ?: continue
                val last = timed.last().value
                var sentenceGaps = 0.0
                for ((a, b) in timed.zipWithNext()) {
                    val gap = (b.value.offsetMs - (a.value.offsetMs + a.value.durationMs)) / 1000.0
                    val r = match[a.index]
                    if (!lined || r == null) continue
                    // Something was said or left out between the two: the
                    // silence between them is not one pause.
                    val between = (saidAt[a.index] + 1) until saidAt[b.index]
                    if (between.any { all[it].isInsertion || all[it].isOmission }) continue
                    fun longPause() = Break(a.value.word, b.value.word, SpeechReading.round(gap * 10) / 10)
                    when (ref[r].stop) {
                        Stop.SENTENCE, Stop.PARAGRAPH -> {
                            sentenceGaps += max(0.0, gap)
                            val limit = if (ref[r].stop == Stop.PARAGRAPH) PARAGRAPH_PAUSE_MAX else SENTENCE_PAUSE_MAX
                            if (gap > limit) longPauses += longPause()
                        }
                        Stop.CLAUSE -> if (gap > COMMA_PAUSE_MAX) longPauses += longPause()
                        Stop.NONE -> {
                            boundaries += 1
                            if (gap >= PAUSE_SECONDS) {
                                mid += 1
                                breaks += longPause()
                                if (gap >= STALL_SECONDS) stalls += 1
                            }
                        }
                    }
                }
                if (lined) aligned = true
                val span = (last.offsetMs + last.durationMs - first.offsetMs) / 1000.0
                words += timed.size
                spoken += timed.size
                seconds += max(0.0, span - sentenceGaps)
            }
            val monotone = pieces.sumOf { p -> p.result.words.count { it.error == "Monotone" } }
            val wpm = if (seconds > 3) SpeechReading.round(words / seconds * 60).toInt() else null
            return SpeechDelivery(
                prosody = weighted { it.prosody }, fluency = weighted { it.fluency }, weakSounds = weak,
                midPauses = if (aligned) mid else null, midBoundaries = if (aligned) boundaries else null,
                wordsPerMinute = wpm, monotoneWords = monotone,
                soundAccuracy = weighted { it.soundScore },
                breaks = breaks, stalls = stalls, weakest = weakest.take(12), stumbles = stumbles,
                repeats = repeats, longPauses = longPauses, spokenWords = spoken,
            )
        }

        private fun isNumber(c: Char): Boolean = when (Character.getType(c).toByte()) {
            Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
            else -> false
        }
        private fun isWordChar(c: Char) = c.isLetter() || isNumber(c) || c == '\''
        private fun isNewline(c: Char) = c in "\n\r\u000B\u000C\u0085  "

        /** A word as both sides can compare it: lower case, letters, digits
         *  and apostrophes only. */
        fun core(word: String): String =
            word.lowercase().replace('’', '\'').filter(::isWordChar).trim('\'')

        /**
         * The script cut into words with what follows each: a sentence end, a
         * clause break (comma, colon, dash), or nothing. A hyphenated word is
         * two words; a token that is only punctuation ("—") marks the word
         * before it. A line break after a token ends a paragraph.
         */
        fun referenceTokens(text: String): List<RefToken> {
            val tokens = mutableListOf<Pair<String, Boolean>>()
            val current = StringBuilder()
            for (ch in text) {
                if (ch.isWhitespace()) {
                    if (current.isNotEmpty()) { tokens += current.toString() to false; current.clear() }
                    if (isNewline(ch) && tokens.isNotEmpty()) tokens[tokens.lastIndex] = tokens.last().first to true
                } else current.append(ch)
            }
            if (current.isNotEmpty()) tokens += current.toString() to false

            val out = mutableListOf<RefToken>()
            for ((token, endsParagraph) in tokens) {
                val tail = token.trim { it in "\"'”’)]»" }
                val end = tail.lastOrNull()
                val stop = when {
                    end != null && end in ".!?。！？…" -> Stop.SENTENCE
                    end != null && end in ",;:—–-、，" -> Stop.CLAUSE
                    else -> Stop.NONE
                }
                val parts = splitWords(token.lowercase().replace('’', '\''))
                    .map { it.trim('\'') }.filter { it.isNotEmpty() }
                if (parts.isEmpty()) {
                    if (out.isNotEmpty()) {
                        var previous = out.removeAt(out.lastIndex)
                        if (previous.stop == Stop.NONE) {
                            previous = previous.copy(stop = if (stop == Stop.SENTENCE) Stop.SENTENCE else Stop.CLAUSE)
                        }
                        if (endsParagraph && previous.stop == Stop.SENTENCE) previous = previous.copy(stop = Stop.PARAGRAPH)
                        out += previous
                    }
                    continue
                }
                parts.forEachIndexed { i, part ->
                    val last = i == parts.lastIndex
                    out += RefToken(part, if (!last) Stop.NONE else if (endsParagraph && stop != Stop.NONE) Stop.PARAGRAPH else stop)
                }
            }
            return out
        }

        private fun splitWords(text: String): List<String> {
            val out = mutableListOf<String>()
            val current = StringBuilder()
            for (c in text) {
                if (isWordChar(c)) current.append(c)
                else if (current.isNotEmpty()) { out += current.toString(); current.clear() }
            }
            if (current.isNotEmpty()) out += current.toString()
            return out
        }

        /** For each of [said], the index in [ref] it lines up with (longest
         *  common subsequence of equal words), or null. */
        fun align(said: List<String>, ref: List<String>): List<Int?> {
            val n = said.size; val m = ref.size
            if (n == 0 || m == 0) return List(n) { null }
            val table = Array(n + 1) { IntArray(m + 1) }
            for (i in n - 1 downTo 0) {
                for (j in m - 1 downTo 0) {
                    table[i][j] = if (said[i].isNotEmpty() && said[i] == ref[j]) table[i + 1][j + 1] + 1
                    else max(table[i + 1][j], table[i][j + 1])
                }
            }
            val out = arrayOfNulls<Int>(n)
            var i = 0; var j = 0
            while (i < n && j < m) {
                if (said[i].isNotEmpty() && said[i] == ref[j]) {
                    out[i] = j; i++; j++
                } else if (table[i + 1][j] >= table[i][j + 1]) i++
                else j++
            }
            return out.toList()
        }
    }
}
