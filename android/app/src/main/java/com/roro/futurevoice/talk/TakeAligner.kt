package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.Mfcc
import com.roro.futurevoice.audio.WavPcm
import kotlin.math.sqrt

/**
 * WHEN the learner said each word of a shadowing take — Android's answer to
 * the word times iOS reads off Apple's recognizer
 * (`ShadowTranscriber.realigned`).
 *
 * No recognizer this app can reach on Android returns word times for a file:
 * `SpeechRecognizer` accepts a recording since Android 13
 * (`EXTRA_AUDIO_SOURCE`) and returns its WORDS, but the `RecognitionPart`s
 * that should carry times come back empty (measured 2026-10-02, plan 2.9).
 * What the app does have is the line the learner was copying, with its word
 * onsets MEASURED by ElevenLabs at synthesis. A shadow take is the same
 * sentence said again, so the take is aligned to the model line ACOUSTICALLY
 * — dynamic time warping over cepstral features of the speech frames of
 * both — and each target word's measured onset is carried through the warp
 * into the take. The onset that comes out is a measurement of the learner's
 * own audio: a word they came in late on is found late.
 *
 * The warp is only trusted where it behaved like an alignment: a word whose
 * stretch of the path is pathologically steep or flat (one side swallowed
 * the other) or matched far worse than the utterance's median is placed but
 * marked UNMEASURED, and under half the words passing returns nothing — the
 * same `minAnchorRatio` iOS holds its realignment to. The rhythm grade reads
 * only measured words ([ShadowScore.analyzeRhythm]), so a doubtful warp costs
 * a dot, never a wrong verdict.
 */
object TakeAligner {

    /** A frame is speech when it is within 26 dB of the file's loudest. */
    private const val VOICE_RATIO = 0.05
    /** Speech must clear the room's own floor (10th-percentile frame) by
     *  this factor — 6 dB. */
    private const val NOISE_MARGIN = 2.0
    /** A word's stretch of the path, relative to the whole take's pace. */
    private const val MIN_SLOPE = 1.0 / 3
    private const val MAX_SLOPE = 3.0
    /** A word's mean frame distance, relative to the path's median. */
    private const val MAX_COST = 1.45
    /** iOS `ShadowTranscriber.minAnchorRatio`. */
    const val MIN_ANCHOR_RATIO = 0.5
    /** Target frames looked ahead for a pause the onset should follow. */
    private const val LOOKAHEAD = 3
    private const val MAX_LOOKAHEAD = 12
    /** 50 ms of silence counts as a pause. */
    private const val MIN_GAP_FRAMES = 5
    /** DTW cells; ~40 s of take against ~20 s of line. */
    private const val MAX_CELLS = 8_000_000L

    /** One target word carried into the take. */
    data class Mapped(
        /** ms into the TAKE where this target word begins. */
        val onsetMs: Int,
        /** The warp behaved like an alignment at this word. */
        val confident: Boolean,
        val slope: Double,
        val cost: Double,
    )

    /**
     * For every word of [targetTimings], where it begins in [take] — or null
     * when the two recordings can't be aligned at all. Both recordings are
     * resampled to 16 kHz by the caller.
     */
    fun map(target: WavPcm, targetTimings: List<WordTiming>, take: WavPcm): List<Mapped>? {
        if (targetTimings.isEmpty()) return null
        if (target.sampleRate != Mfcc.SAMPLE_RATE || take.sampleRate != Mfcc.SAMPLE_RATE) return null
        val ia = voicedFrames(target.samples)
        val ib = voicedFrames(take.samples)
        if (ia.size < 10 || ib.size < 10) return null
        if (ia.size.toLong() * ib.size > MAX_CELLS) return null
        val a = Mfcc.normalizedWithDeltas(Mfcc.features(target.samples), ia)
        val b = Mfcc.normalizedWithDeltas(Mfcc.features(take.samples), ib)
        val path = dtw(a, b) ?: return null

        // First / last take frame the path visits for each target frame,
        // and the distance at each step.
        val n = a.size
        val firstJ = IntArray(n) { -1 }
        val lastJ = IntArray(n) { -1 }
        val costs = DoubleArray(path.size)
        path.forEachIndexed { k, (i, j) ->
            if (firstJ[i] < 0) firstJ[i] = j
            lastJ[i] = j
            costs[k] = dist(a[i], b[j])
        }
        val median = costs.sorted()[costs.size / 2].coerceAtLeast(1e-6)
        val pace = b.size.toDouble() / n

        return targetTimings.mapIndexed { w, t ->
            val start = searchVoiced(ia, t.startMs / 10)
            val nextStart = targetTimings.getOrNull(w + 1)?.startMs ?: t.endMs
            val end = maxOf(start + 1, minOf(n, searchVoiced(ia, maxOf(t.endMs, nextStart) / 10)))
            val j0 = firstJ[start.coerceIn(0, n - 1)]
            var jMin = Int.MAX_VALUE; var jMax = Int.MIN_VALUE
            var sum = 0.0; var count = 0
            path.forEachIndexed { k, (i, j) ->
                if (i in start until end) {
                    jMin = minOf(jMin, j); jMax = maxOf(jMax, j)
                    sum += costs[k]; count += 1
                }
            }
            val slope = if (count == 0) 0.0 else (jMax - jMin + 1).toDouble() / (end - start) / pace
            val cost = if (count == 0) Double.MAX_VALUE else sum / count / median
            // A word never starts just BEFORE a pause. Silence is cut out
            // of the warp, so the take's last frame before a pause and its
            // first after it are neighbours there, and a word's first frame
            // can be matched to either; speech after a gap begins after it.
            var onsetFrame = ib[maxOf(0, j0)]
            val ahead = maxOf(LOOKAHEAD, minOf(MAX_LOOKAHEAD, (end - start) / 2))
            val jAhead = firstJ[minOf(start + ahead, n - 1)].coerceAtLeast(j0)
            for (q in maxOf(0, j0) until minOf(jAhead, ib.size - 1)) {
                if (ib[q + 1] - ib[q] >= MIN_GAP_FRAMES) onsetFrame = ib[q + 1]
            }
            Mapped(
                onsetMs = Mfcc.HOP * 1000 / Mfcc.SAMPLE_RATE * onsetFrame,
                confident = (end - start) >= 2 && slope in MIN_SLOPE..MAX_SLOPE && cost <= MAX_COST,
                slope = slope, cost = cost,
            )
        }
    }

    /**
     * The learner's timeline, one window per word of their SCORED text —
     * the contract [ShadowScore.analyzeRhythm] checks. A learner word takes
     * the onset of the target word the diff paired it with; a word the diff
     * paired with nothing (an insertion) shares the gap between its
     * neighbours and is never measured. Each word ends where the next one
     * starts, the last where the take's speech stops ([lastVoiceMs]).
     *
     * Returns [] when under [MIN_ANCHOR_RATIO] of the words are measured —
     * the grade then stays "words only", like an unanchored iOS pass.
     */
    fun learnerTimings(
        learnerWords: List<String>,
        targetTimings: List<WordTiming>,
        steps: List<ShadowScore.DiffStep>,
        mapped: List<Mapped>,
        lastVoiceMs: Int,
        language: String,
    ): List<WordTiming> {
        if (learnerWords.isEmpty() || mapped.size != targetTimings.size) return emptyList()
        val pairs = ShadowScore.wordPairs(steps, targetTimings.map { it.word }, learnerWords, language)
            ?: return emptyList()
        val starts = arrayOfNulls<Int>(learnerWords.size)
        val measured = BooleanArray(learnerWords.size)
        var previous = -1
        for ((tw, lw) in pairs) {
            val m = mapped[tw]
            // A warp is monotonic, but two target words can land on one
            // frame; a later word may never start before an earlier one.
            if (m.onsetMs < previous) continue
            starts[lw] = m.onsetMs
            measured[lw] = m.confident && targetTimings[tw].isMeasured
            previous = m.onsetMs
        }
        val anchoredCount = measured.count { it }
        if (anchoredCount.toDouble() / learnerWords.size < MIN_ANCHOR_RATIO) return emptyList()
        val pairing = starts.indices.map { if (starts[it] != null) it else null }
        val spans = starts.indices.map { k ->
            val s = (starts[k] ?: 0) / 1000.0
            val nextStart = (k + 1 until starts.size).firstNotNullOfOrNull { starts[it] }
            val e = (nextStart ?: maxOf(lastVoiceMs, (starts[k] ?: 0) + 10)) / 1000.0
            LocalAlignment.Span(s, maxOf(e, s + 0.01))
        }
        return LocalAlignment.fill(learnerWords, pairing, spans, maxOf(lastVoiceMs, 0))
            .mapIndexed { k, t -> t.copy(isMeasured = measured[k]) }
    }

    private fun voicedFrames(x: ShortArray): IntArray {
        val rms = Mfcc.frameRms(x)
        val peak = rms.maxOrNull() ?: return IntArray(0)
        if (peak <= 1e-5) return IntArray(0)
        // Relative to the peak AND above the room: in a noisy room the peak
        // gate alone counts the hiss between words as speech, and a pause
        // the learner took then vanishes from the warp.
        val floor = rms.sorted()[rms.size / 10]
        val gate = maxOf(peak * VOICE_RATIO, floor * NOISE_MARGIN)
        return rms.indices.filter { rms[it] > gate }.toIntArray()
    }

    /** Index of the first voiced frame at or after [frame] (clamped). */
    private fun searchVoiced(voiced: IntArray, frame: Int): Int {
        var lo = 0; var hi = voiced.size
        while (lo < hi) { val mid = (lo + hi) / 2; if (voiced[mid] < frame) lo = mid + 1 else hi = mid }
        return minOf(lo, voiced.size - 1)
    }

    private fun dist(p: DoubleArray, q: DoubleArray): Double {
        var s = 0.0
        for (k in p.indices) { val d = p[k] - q[k]; s += d * d }
        return sqrt(s)
    }

    /** Classic DTW, steps (1,1) (1,0) (0,1); the path as (target, take) pairs. */
    private fun dtw(a: Array<DoubleArray>, b: Array<DoubleArray>): List<kotlin.Pair<Int, Int>>? {
        val n = a.size; val m = b.size
        val c = Array(n) { FloatArray(m) }
        for (i in 0 until n) for (j in 0 until m) {
            val d = dist(a[i], b[j]).toFloat()
            c[i][j] = d + when {
                i == 0 && j == 0 -> 0f
                i == 0 -> c[0][j - 1]
                j == 0 -> c[i - 1][0]
                else -> minOf(c[i - 1][j - 1], c[i - 1][j], c[i][j - 1])
            }
        }
        val path = ArrayList<kotlin.Pair<Int, Int>>(n + m)
        var i = n - 1; var j = m - 1
        while (true) {
            path += i to j
            if (i == 0 && j == 0) break
            when {
                i == 0 -> j -= 1
                j == 0 -> i -= 1
                else -> {
                    val d = c[i - 1][j - 1]; val up = c[i - 1][j]; val left = c[i][j - 1]
                    if (d <= up && d <= left) { i -= 1; j -= 1 }
                    else if (up <= left) i -= 1
                    else j -= 1
                }
            }
        }
        path.reverse()
        return path
    }
}
