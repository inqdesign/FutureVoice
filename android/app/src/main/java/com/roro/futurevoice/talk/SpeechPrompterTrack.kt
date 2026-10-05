package com.roro.futurevoice.talk

import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechLibrary
import kotlin.math.abs

/**
 * The script as the prompter draws it, and where the reader is in it — iOS
 * `SpeechPrompterTrack`.
 *
 * The prompter FOLLOWS THE VOICE: the live recognizer's text is matched
 * against the script and the cursor moves to the last word both agree on.
 * Matching runs on keys (case, punctuation stripped) — words in a spaced
 * language, syllables/characters in Korean and Japanese, because the
 * recognizer's spacing there is its own. It only moves FORWARD, a little back
 * at most, and never jumps further than a window ahead.
 */
class SpeechPrompterTrack(script: String, language: String) {
    data class Word(val id: Int, val text: String, val paragraph: Int)

    val words: List<Word>
    val paragraphs: List<List<Word>>
    /** The text this was built from, hashed. */
    val signature: Int = script.hashCode()
    private val keys: List<String>
    private val keyWord: List<Int>
    private val perChar = LanguageCatalog.tokenStyle(language) == LanguageCatalog.TokenStyle.SYLLABLE

    init {
        val ws = mutableListOf<Word>()
        val ps = mutableListOf<List<Word>>()
        val blocks = script.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
        blocks.forEachIndexed { p, block ->
            val line = mutableListOf<Word>()
            for (piece in displayWords(block, language)) {
                val w = Word(ws.size, piece, p)
                ws += w; line += w
            }
            ps += line
        }
        val k = mutableListOf<String>()
        val kw = mutableListOf<Int>()
        for (w in ws) for (key in keys(w.text, perChar)) { k += key; kw += w.id }
        words = ws; paragraphs = ps; keys = k; keyWord = kw
    }

    /**
     * The display word the reader has reached (everything before it is read),
     * given what the recognizer has heard so far and the previous position.
     * Returns [current] when nothing new agrees.
     */
    fun advance(current: Int, heard: String): Int {
        // Only the tail is read: the transcript grows to the whole take.
        val heardKeys = keys(heard.takeLast(160), perChar)
        if (heardKeys.isEmpty() || keys.isEmpty()) return current
        val currentKey = keyWord.indexOfFirst { it >= current }.let { if (it < 0) keys.size else it }
        val back = if (perChar) 8 else 3
        // Halved after a Korean test where a repeated phrase matched further
        // down and the text jumped ahead of the voice.
        val ahead = if (perChar) 30 else 12
        val lo = maxOf(0, currentKey - back)
        val hi = minOf(keys.size - 1, currentKey + ahead)
        if (lo > hi) return current

        // A run of the heard tail, looked for as a CONTIGUOUS run of the
        // script near the reader. Longest run first; the last key or two may
        // be dropped (the newest partial is the least sure — Korean
        // especially, iOS `2fd5df6d`).
        val lengths = if (perChar) listOf(5, 4, 3) else listOf(3, 2)
        for (length in lengths) {
            for (drop in 0..2) {
                if (heardKeys.size < length + drop) continue
                val needle = heardKeys.subList(heardKeys.size - drop - length, heardKeys.size - drop)
                // Short runs are common words; only trust them close by.
                val reach = if (length >= (if (perChar) 4 else 3)) hi
                    else minOf(hi, currentKey + (if (perChar) 20 else 8))
                if (lo + length - 1 > reach) continue
                var best: Int? = null
                for (end in (lo + length - 1)..reach) {
                    var same = true
                    for (i in 0 until length) if (keys[end - length + 1 + i] != needle[i]) { same = false; break }
                    if (!same) continue
                    if (best == null || abs(end - currentKey) < abs(best - currentKey)) best = end
                }
                if (best != null) {
                    val next = keyWord[best] + 1
                    // Small steps back are allowed (a re-read), big ones are not.
                    return if (next >= current - 2) next else current
                }
            }
        }
        // Catching up past the window: only the longest run, only where it
        // occurs ONCE, so a repeated phrase can't throw the text ahead.
        val longest = if (perChar) 5 else 3
        val far = minOf(keys.size - 1, currentKey + (if (perChar) 120 else 45))
        if (heardKeys.size >= longest && hi < far) {
            val needle = heardKeys.takeLast(longest)
            val hits = mutableListOf<Int>()
            for (end in (hi + 1)..far) {
                if (end - longest + 1 < 0) continue
                if ((0 until longest).all { keys[end - longest + 1 + it] == needle[it] }) hits += end
            }
            if (hits.size == 1) return keyWord[hits[0]] + 1
        }
        // A single long word right where we are is enough on its own.
        if (!perChar) {
            val last = heardKeys.last()
            if (last.length >= 5) {
                for (end in lo..minOf(hi, currentKey + 3)) {
                    if (keys[end] == last) return maxOf(current, keyWord[end] + 1)
                }
            }
        }
        return current
    }

    /** Words a reader covers per second at the planned pace. */
    fun wordsPerSecond(language: String): Double {
        val rate = SpeechLibrary.plannedRate(language).toDouble() / 60
        if (words.isEmpty()) return rate
        val unitsPerWord = maxOf(1, SpeechLibrary.units(words.joinToString(" ") { it.text }, language))
            .toDouble() / words.size
        return rate / maxOf(0.5, unitsPerWord)
    }

    companion object {
        private val breakers = setOf('、', '。', '！', '？', '，', ',', '.', '!', '?')

        /** Display pieces: whitespace words, or for an unspaced language short
         *  runs cut at punctuation so the line can still wrap. */
        fun displayWords(text: String, language: String): List<String> {
            if (LanguageCatalog.writesSpaces(language)) {
                return text.split(Regex("\\s+")).filter { it.isNotEmpty() }
            }
            val out = mutableListOf<String>()
            val current = StringBuilder()
            for (ch in text) {
                current.append(ch)
                if (ch in breakers || current.length >= 5) { out += current.toString(); current.clear() }
            }
            if (current.isNotEmpty()) out += current.toString()
            // Glue a lone punctuation piece back onto the one before.
            val glued = mutableListOf<String>()
            for (piece in out) {
                if (piece.all(::isPunctuation) && glued.isNotEmpty()) glued[glued.size - 1] = glued.last() + piece
                else glued += piece
            }
            return glued
        }

        fun keys(text: String, perChar: Boolean): List<String> {
            val cleaned = text.lowercase().filter { it.isLetterOrDigit() || it.isWhitespace() }
            if (perChar) return cleaned.filter { !it.isWhitespace() }.map { it.toString() }
            return cleaned.split(Regex("\\s+")).filter { it.isNotEmpty() }
        }

        fun isPunctuation(ch: Char): Boolean = when (Character.getType(ch).toByte()) {
            Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
            Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION,
            Character.FINAL_QUOTE_PUNCTUATION, Character.OTHER_PUNCTUATION -> true
            else -> false
        }
    }
}

/**
 * How the prompter column moves, frame by frame — iOS `PrompterMotion`,
 * pure so a test can drive it.
 *
 * FOLLOWING THE VOICE moves at the reader's SPEED, not to the reader's last
 * known spot (iOS `8c6b8ea4`): the reader's pace is a running average of how
 * fast their reported spot advances; while they speak the text moves at that
 * pace, a little faster when it has fallen behind and a little slower when it
 * is ahead; when they stop speaking it eases to a stop. The report steers the
 * speed and never moves the text by itself.
 */
class PrompterMotion {
    data class Input(
        val recording: Boolean,
        val follow: Boolean,
        val speed: Float,
        val speaking: Boolean,
        val held: Boolean,
    )

    var position = 0f; private set
    var velocity = 0f; private set
    /** The reader's pace, in column points per second. */
    var pace = 0f; private set
    /** The language's ordinary reading pace in column points per second. */
    var plannedPace = 0f

    var target = 0f; private set
    private var lastTarget = 0f
    private var lineTop = Float.MAX_VALUE
    var lineAdvance = 40f; private set

    fun setTarget(y: Float, lineTop: Float, lineAdvance: Float) {
        if (lineAdvance > 0) this.lineAdvance = lineAdvance
        this.lineTop = lineTop
        target = y
    }

    /** Back onto the reader's spot, at rest. */
    fun snap() {
        position = target
        lastTarget = target
        velocity = 0f
        pace = 0f
    }

    fun step(dt: Float, input: Input) {
        if (dt <= 0) return
        val planned = if (plannedPace > 0) plannedPace else lineAdvance / 2
        var wanted: Float
        if (!input.recording) {
            wanted = 0f
        } else if (!input.follow) {
            // Steady speed, eased, so a press-and-hold stops it gently.
            wanted = if (input.held) 0f else planned * input.speed
        } else {
            if (pace == 0f) pace = planned
            val advance = maxOf(0f, target - lastTarget)
            if (input.speaking) {
                pace += (advance / dt - pace) * minOf(1f, dt / PACE_WINDOW)
                pace = pace.coerceIn(planned * 0.5f, planned * 2f)
            }
            val linesBehind = (target - position) / maxOf(1f, lineAdvance)
            val factor = (1 + PULL_PER_LINE * linesBehind).coerceIn(0f, MAX_FACTOR)
            wanted = if (input.speaking) pace * factor else 0f
        }
        lastTarget = target
        velocity += (wanted - velocity) * minOf(1f, dt / SPEED_WINDOW)
        var next = position + maxOf(0f, velocity) * dt
        // Safety: the line being read never goes above the top of the
        // prompter (its top may rise at most one line over its rest place).
        if (input.recording && input.follow) next = minOf(next, maxOf(position, lineTop + lineAdvance))
        position = next
    }

    companion object {
        const val PACE_WINDOW = 3f
        const val SPEED_WINDOW = 0.35f
        const val PULL_PER_LINE = 0.8f
        const val MAX_FACTOR = 2.2f
    }
}
