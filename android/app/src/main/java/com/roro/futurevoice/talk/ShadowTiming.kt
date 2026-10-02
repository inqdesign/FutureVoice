package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.AudioDecode
import com.roro.futurevoice.audio.AudioOnset
import com.roro.futurevoice.audio.Mfcc
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.WordSplitter

/**
 * The learner's word timeline for one scored take — what the rhythm grade
 * and the pace figure read. The take is aligned to the model line
 * ([TakeAligner]); a PHRASE take is aligned to that phrase's slice of the
 * line only, so the warp cannot wander into words that were never said.
 */
object ShadowTiming {

    /** Margin kept around a phrase's slice of the model line. */
    private const val SLICE_LEAD_MS = 150
    private const val SLICE_TAIL_MS = 250

    data class Learner(
        /** One window per word of the scored text; [] = not measurable. */
        val timings: List<WordTiming>,
        /** First voice → last voice in the take, ms (0 = silent). */
        val voicedSpanMs: Int,
    )

    fun learner(
        target: WavPcm?,
        targetSlice: List<WordTiming>,
        take: WavPcm,
        learnerText: String,
        steps: List<ShadowScore.DiffStep>,
        language: String,
    ): Learner {
        val take16 = AudioDecode.resample(take, Mfcc.SAMPLE_RATE)
        val first = AudioOnset.firstVoiceOnset(take16.samples, take16.sampleRate)
        val last = AudioOnset.lastVoiceOffset(take16.samples, take16.sampleRate)
        val span = if (first != null && last != null) ((last - first) * 1000).toInt().coerceAtLeast(0) else 0
        if (target == null || targetSlice.none { it.isMeasured }) return Learner(emptyList(), span)

        val t16 = AudioDecode.resample(target, Mfcc.SAMPLE_RATE)
        val from = maxOf(0, targetSlice.first().startMs - SLICE_LEAD_MS)
        val to = minOf(t16.durationMs, targetSlice.last().endMs + SLICE_TAIL_MS)
        val a = (from.toLong() * t16.sampleRate / 1000).toInt().coerceIn(0, t16.samples.size)
        val b = (to.toLong() * t16.sampleRate / 1000).toInt().coerceIn(a, t16.samples.size)
        val cut = WavPcm(t16.sampleRate, t16.samples.copyOfRange(a, b))
        val shifted = targetSlice.map { it.copy(startMs = it.startMs - from, endMs = it.endMs - from) }

        val mapped = TakeAligner.map(cut, shifted, take16) ?: return Learner(emptyList(), span)
        val timings = TakeAligner.learnerTimings(
            learnerWords = WordSplitter.timingWords(learnerText, language),
            targetTimings = shifted,
            steps = steps,
            mapped = mapped,
            lastVoiceMs = ((last ?: 0.0) * 1000).toInt(),
            language = language,
        )
        return Learner(timings, span)
    }
}
