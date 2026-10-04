package com.roro.futurevoice.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.LevelBands
import com.roro.futurevoice.data.WeeklyReport
import com.roro.futurevoice.talk.ScorecardMetrics
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.ui.brand.DisplayFace
import java.util.Locale

// ─────────────────────────────────────────────────────────────────────────────
// The numbers
//
// Every figure on this tab is computed HERE, in code, from the talks
// themselves — an LLM only ever writes the qualitative note beside one.
// Port of `ProgressTab.compute` (iOS), field for field; a number that differs
// from iOS on the same sessions is a bug on whichever side is newer.
// ─────────────────────────────────────────────────────────────────────────────

/** One measured value at one point in time — the per-skill trend series. */
data class TrendPoint(val at: Long, val value: Double)

/** One assessment's level — the Growth line, which only assessments move. */
data class LevelPoint(val at: Long, val rank: Int)

/**
 * A CEFR band over a measurement. The edges live in ONE table per skill and
 * are used BOTH by the ≈level mapping and by a trend chart's background
 * zones, so a chart can never show a different band than the mapping assigns.
 *
 * `LevelBands` (data layer) owns the fluency and expression mappings and
 * keeps the same edges privately; these are the same numbers, exposed so the
 * zones can be drawn. Change one and change the other.
 */
class BandSpec(val level: CefrLevel, val from: Double, val to: Double)

object ProgressBands {

    /** Articulation pace, words per minute — mirrors `LevelBands.fluency`. */
    val fluency = listOf(
        BandSpec(CefrLevel.A1, 0.0, 60.0), BandSpec(CefrLevel.A2, 60.0, 85.0),
        BandSpec(CefrLevel.B1, 85.0, 105.0), BandSpec(CefrLevel.B2, 105.0, 125.0),
        BandSpec(CefrLevel.C1, 125.0, 145.0), BandSpec(CefrLevel.C2, 145.0, 200.0))

    /** Words per turn — mirrors `LevelBands.expression`. */
    val expression = listOf(
        BandSpec(CefrLevel.A1, 0.0, 6.0), BandSpec(CefrLevel.A2, 6.0, 10.0),
        BandSpec(CefrLevel.B1, 10.0, 16.0), BandSpec(CefrLevel.B2, 16.0, 24.0),
        BandSpec(CefrLevel.C1, 24.0, 34.0), BandSpec(CefrLevel.C2, 34.0, 60.0))

    /**
     * Verified grammar slips per 100 spoken words, ordered BEST first (fewer
     * reads higher). This is the same evidence family the assessment cites
     * for grammatical control, normalized by words rather than by turn — a
     * per-turn density would punish long turns. The 0–100 grammar score is
     * only the fallback (`LevelBands.grammarBand`), because it is calibrated
     * to the learner's own level setting and so can read 70+ for a speaker
     * who slips constantly.
     */
    val grammarDensity = listOf(
        BandSpec(CefrLevel.C2, 0.0, 0.5), BandSpec(CefrLevel.C1, 0.5, 1.0),
        BandSpec(CefrLevel.B2, 1.0, 2.0), BandSpec(CefrLevel.B1, 2.0, 4.0),
        BandSpec(CefrLevel.A2, 4.0, 7.0), BandSpec(CefrLevel.A1, 7.0, 15.0))

    /** Half-open lookup; a value past the table's end takes the LAST entry,
     *  so an off-scale measurement never goes unbanded. */
    fun band(value: Double, specs: List<BandSpec>): CefrLevel =
        specs.firstOrNull { value >= it.from && value < it.to }?.level ?: specs.last().level

    fun next(level: CefrLevel): CefrLevel? =
        CefrLevel.entries.getOrNull(CefrLevel.entries.indexOf(level) + 1)
}

/**
 * Everything the Progress pages draw, in one value so a pass lands in a
 * single state update instead of twenty.
 */
data class ProgressMetrics(
    /** Talks that carry a scorecard and were not archived — the evidence. */
    val scoredCount: Int = 0,
    /** Speaking time across every analyzed talk; gates the level estimate. */
    val totalSpeakingMinutes: Int = 0,
    val wpm: Int = 0,
    val articulationWpm: Int = 0,
    val pausesPerMin: Double = 0.0,
    val talkMinutes: Int = 0,
    val wordsPerTurn: Int = 0,
    val grammarScore: Int = 0,
    val slipsPer100Words: Double = 0.0,
    /** Median structural range over the same window (null: no talk has one). */
    val grammarRange: CefrLevel? = null,
    val perLevel: Map<CefrLevel, Int> = emptyMap(),
    val usedTotal: Int = 0,
    val vocabLevel: CefrLevel? = null,
    val expressionCount: Int = 0,
    val fluencyTrend: List<TrendPoint> = emptyList(),
    val grammarTrend: List<TrendPoint> = emptyList(),
    val expressionTrend: List<TrendPoint> = emptyList(),
    val levelHistory: List<LevelPoint> = emptyList(),
    /** The coach's own note per axis, newest first — the only LLM text here. */
    val notes: Map<Dim, List<String>> = emptyMap(),
) {
    /** Articulation rate (voiced speech only); wall-clock is the fallback for
     *  old talks recorded before mic-energy stats existed. */
    val effectivePace: Int get() = if (articulationWpm > 0) articulationWpm else wpm

    val fluencyLevel: CefrLevel?
        get() = LevelBands.fluencyBand(effectivePace.toDouble(), articulationWpm > 0)

    /** Slip density first, the 0–100 score only when no slips were ever
     *  captured — absent data must not read as perfect grammar. */
    val grammarLevel: CefrLevel? get() = grammarRead?.first

    /** Non-null when range, not accuracy, decided the band. */
    val grammarCeiling: GrammarCeiling? get() = grammarRead?.second

    private val grammarRead: Pair<CefrLevel, GrammarCeiling?>?
        get() = GrammarCeiling.band(scoredCount, slipsPer100Words, grammarScore, grammarRange, vocabLevel)

    val expressionLevel: CefrLevel?
        get() = LevelBands.expressionBand(wordsPerTurn.toDouble())

    /** Upper density bound of the next band up — the trend chart's finish
     *  line, derived from the same table as the mapping. */
    val grammarNextThreshold: Double?
        get() {
            // A ceiling decided the band: fewer slips would move nothing.
            if (slipsPer100Words <= 0 || grammarCeiling != null) return null
            val lv = grammarLevel ?: return null
            val i = ProgressBands.grammarDensity.indexOfFirst { it.level == lv }
            return if (i > 0) ProgressBands.grammarDensity[i - 1].to else null
        }
}

/**
 * What held the ≈Grammar band below its accuracy read (iOS `GrammarCeiling`).
 * A CEFR grammar level is the structures you COMMAND and how cleanly: slip
 * density alone read a beginner in short present-tense clauses as C2 — no
 * slips because nothing was attempted. Two reads, the LOWER wins.
 */
sealed class GrammarCeiling {
    abstract val level: CefrLevel
    /** The measured structural range of the assessed talks. */
    data class Range(override val level: CefrLevel) : GrammarCeiling()
    /** No talk has a range yet: graded vocabulary + one band stands in. */
    data class Vocabulary(override val level: CefrLevel) : GrammarCeiling()

    companion object {
        fun band(scoredCount: Int, slipsPer100Words: Double, grammarScore: Int,
                 range: CefrLevel?, vocabLevel: CefrLevel?): Pair<CefrLevel, GrammarCeiling?>? {
            if (scoredCount == 0) return null
            val accuracy = when {
                slipsPer100Words > 0 -> ProgressBands.band(slipsPer100Words, ProgressBands.grammarDensity)
                else -> LevelBands.grammarBand(grammarScore)
            } ?: return null
            val all = CefrLevel.entries
            val ceiling: GrammarCeiling = when {
                range != null -> Range(range)
                vocabLevel != null -> Vocabulary(all[minOf(all.indexOf(vocabLevel) + 1, all.size - 1)])
                else -> return accuracy to null
            }
            return if (all.indexOf(ceiling.level) < all.indexOf(accuracy)) ceiling.level to ceiling
            else accuracy to null
        }
    }
}

object ProgressMath {

    /** Only a talk with a scorecard, still on the shelf, counts as evidence:
     *  archiving one is the learner saying it should stop counting. */
    fun scoredSessions(sessions: List<Session>): List<Session> =
        sessions.filter { it.endedAt != null && it.archivedAt == null && it.summary?.scorecard != null }
            .sortedByDescending { it.rank }

    fun compute(
        sessions: List<Session>,
        reports: List<WeeklyReport>,
        vocabByLevel: Map<CefrLevel, Int>,
        expressionCount: Int,
    ): ProgressMetrics {
        val scored = scoredSessions(sessions)
        val recent = scored.take(5)
        val mets = recent.map { ScorecardMetrics.compute(it.turns) }
        fun mean(xs: List<Double>): Double = if (xs.isEmpty()) 0.0 else xs.sum() / xs.size

        val speakSecs = scored.sumOf { s ->
            s.turns.filter { it.role == com.roro.futurevoice.talk.TurnRole.USER }
                .sumOf { it.durationMs / 1000.0 }
        }

        // Slip density over the SAME window the latest assessment judged, so
        // the ≈Grammar band and the verdict's rationale cite one number. A
        // recent-5 window can straddle a different set of talks and flip the
        // band one panel below the rationale that contradicts it.
        val assessments = reports.filter { it.cefrLevel != null }.sortedByDescending { it.generatedAt }
        val densitySessions = assessments.firstOrNull()?.let { latest ->
            val windowStart = assessments.getOrNull(1)?.periodEnd ?: Long.MIN_VALUE
            scored.filter { it.rank > windowStart && it.rank <= latest.periodEnd }
                .ifEmpty { recent }
        } ?: recent
        val densityMets = densitySessions.map { ScorecardMetrics.compute(it.turns) }
        val slips = densitySessions.sumOf { it.summary?.grammarIssues?.size ?: 0 }
        val densityWords = densityMets.sumOf { it.userWordCount }

        // One point per analyzed talk, oldest first — the same deterministic
        // measurements as the headline numbers, just not averaged away.
        val fluencyTrend = mutableListOf<TrendPoint>()
        val grammarTrend = mutableListOf<TrendPoint>()
        val expressionTrend = mutableListOf<TrendPoint>()
        scored.take(30).reversed().forEach { s ->
            val m = ScorecardMetrics.compute(s.turns)
            val pace = if (m.articulationRate > 0) m.articulationRate else m.wordsPerMinute
            if (pace > 0) fluencyTrend += TrendPoint(s.rank, pace)
            val summary = s.summary
            if (summary != null && m.userWordCount > 0) {
                // A legacy talk from before slips were captured decodes as
                // zero issues; a zero beside a mediocre score is missing
                // data, not clean speech, so only genuinely clean talks join.
                val n = summary.grammarIssues.size
                if (n > 0 || (summary.scorecard?.grammar?.score ?: 0) >= 90) {
                    grammarTrend += TrendPoint(s.rank, n.toDouble() / m.userWordCount * 100)
                }
            }
            if (m.avgWordsPerUserTurn > 0) expressionTrend += TrendPoint(s.rank, m.avgWordsPerUserTurn)
        }

        val cards = scored.mapNotNull { it.summary?.scorecard }
        fun notes(get: (com.roro.futurevoice.talk.SessionScorecard) -> String) =
            cards.take(3).map(get).filter { it.isNotBlank() }

        return ProgressMetrics(
            scoredCount = scored.size,
            totalSpeakingMinutes = (speakSecs / 60.0).toInt(),
            wpm = Math.round(mean(mets.map { it.wordsPerMinute }.filter { it > 0 })).toInt(),
            articulationWpm = Math.round(mean(mets.map { it.articulationRate }.filter { it > 0 })).toInt(),
            pausesPerMin = mean(mets.map { it.pausesPerMinute }.filter { it > 0 }),
            talkMinutes = Math.round(mean(mets.map { it.totalUserSpeakingSeconds }) / 60.0).toInt(),
            wordsPerTurn = Math.round(mean(mets.map { it.avgWordsPerUserTurn })).toInt(),
            grammarScore = Math.round(mean(
                recent.mapNotNull { it.summary?.scorecard?.grammar?.score }
                    .filter { it in 0..100 }.map { it.toDouble() })).toInt(),
            slipsPer100Words = if (densityWords > 0) slips.toDouble() / densityWords * 100 else 0.0,
            // The MEDIAN range over the window: one attempted conditional is
            // not a range you command.
            grammarRange = recent.mapNotNull { s -> s.summary?.scorecard?.grammarRange
                ?.let { r -> CefrLevel.entries.firstOrNull { it.code == r } } }
                .sortedBy { CefrLevel.entries.indexOf(it) }
                .let { l -> if (l.isEmpty()) null else l[(l.size - 1) / 2] },
            perLevel = vocabByLevel,
            usedTotal = vocabByLevel.values.sum(),
            vocabLevel = LevelBands.vocabularyLevel(vocabByLevel),
            expressionCount = expressionCount,
            fluencyTrend = fluencyTrend,
            grammarTrend = grammarTrend,
            expressionTrend = expressionTrend,
            levelHistory = reports.mapNotNull { r ->
                r.cefrLevel?.let { raw ->
                    CefrLevel.entries.firstOrNull { it.code.equals(raw, true) }
                        ?.let { LevelPoint(r.generatedAt, CoreVocabulary.levelRank(it)) }
                }
            }.sortedBy { it.at },
            notes = mapOf(
                Dim.GRAMMAR to notes { it.grammar.note },
                Dim.FLUENCY to notes { it.fluency.note },
                Dim.EXPRESSIVENESS to notes { it.expressiveness.note },
                Dim.VOCABULARY to notes { it.vocabulary.note },
            ),
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Charts
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A skill's trend: the SAME measurement as the page's headline number, one
 * point per analyzed talk, over its CEFR bands. The zones are clipped to the
 * visible y-domain, so they label the range the curve actually occupies
 * instead of squashing it to fit every band; a sliver too thin to hold a
 * caption loses its label rather than colliding with its neighbour's.
 */
@Composable
fun TrendChart(
    points: List<TrendPoint>,
    bands: List<BandSpec> = emptyList(),
    target: Double? = null,
    height: Dp = 130.dp,
    modifier: Modifier = Modifier,
) {
    if (points.size < 2) return
    val line = MaterialTheme.colorScheme.primary
    val zone = MaterialTheme.colorScheme.surfaceVariant
    val label = MaterialTheme.colorScheme.outline
    val rule = MaterialTheme.colorScheme.onSurfaceVariant
    val measurer = rememberTextMeasurer()
    val labelStyle = PT.caption2.copy(color = label)

    val values = points.map { it.value } + listOfNotNull(target)
    val vMin = values.minOrNull() ?: 0.0
    val vMax = values.maxOrNull() ?: 1.0
    val span = maxOf(vMax - vMin, 1.0)
    val lo = maxOf(0.0, vMin - span * 0.25)
    val hi = vMax + span * 0.25
    val first = points.first().at
    val last = points.last().at
    val timeSpan = (last - first).coerceAtLeast(1L)

    Canvas(modifier.fillMaxWidth().height(height)) {
        fun y(v: Double) = (size.height * (1 - ((v - lo) / (hi - lo))).toFloat())
        fun x(i: Int, at: Long) =
            if (last == first) size.width * i / (points.size - 1).coerceAtLeast(1)
            else size.width * ((at - first).toFloat() / timeSpan)

        bands.forEachIndexed { i, b ->
            val bLo = maxOf(b.from, lo)
            val bHi = minOf(b.to, hi)
            if (bLo >= bHi) return@forEachIndexed
            val top = y(bHi)
            drawRect(zone.copy(alpha = if (i % 2 == 0) 0.55f else 0.25f),
                topLeft = Offset(0f, top), size = Size(size.width, y(bLo) - top))
            if ((bHi - bLo) / (hi - lo) >= 0.14) {
                drawText(measurer, b.level.code.uppercase(),
                    topLeft = Offset(4.dp.toPx(), top + 1.dp.toPx()), style = labelStyle)
            }
        }

        val path = androidx.compose.ui.graphics.Path()
        points.forEachIndexed { i, p ->
            val px = x(i, p.at)
            val py = y(p.value)
            if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
        drawPath(path, line, style = Stroke(width = 2.dp.toPx()))
        points.forEachIndexed { i, p ->
            drawCircle(line, radius = 3.dp.toPx(), center = Offset(x(i, p.at), y(p.value)))
        }

        // The next-band goal — a curve with no finish line says nothing.
        if (target != null && target in lo..hi) {
            drawLine(rule.copy(alpha = 0.6f), Offset(0f, y(target)), Offset(size.width, y(target)),
                strokeWidth = 1.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx())))
        }
    }
}

/**
 * Growth: the level, one point per assessment. Only assessments move this
 * line, so it IS the honest "am I improving" answer — the 0–100 talk scores
 * can't be, since they are graded relative to the level you had at the time.
 * Stepped, because a level holds until the next read changes it.
 */
@Composable
fun LevelHistoryChart(points: List<LevelPoint>, height: Dp = 150.dp,
                      modifier: Modifier = Modifier) {
    if (points.size < 2) return
    val line = MaterialTheme.colorScheme.primary
    val grid = MaterialTheme.colorScheme.outlineVariant
    val measurer = rememberTextMeasurer()
    val labelStyle: TextStyle =
        PT.caption2.copy(color = MaterialTheme.colorScheme.outline)
    val first = points.first().at
    val timeSpan = (points.last().at - first).coerceAtLeast(1L)

    Canvas(modifier.fillMaxWidth().height(height)) {
        val gutter = 26.dp.toPx()
        val plot = size.width - gutter
        fun y(rank: Double) = (size.height * (1 - ((rank + 0.5) / 6.0))).toFloat()
        fun x(at: Long) = gutter + plot * ((at - first).toFloat() / timeSpan)

        CefrLevel.entries.forEachIndexed { i, lv ->
            val gy = y(i.toDouble())
            drawLine(grid, Offset(gutter, gy), Offset(size.width, gy), strokeWidth = 1f)
            val text = measurer.measure(lv.code.uppercase(), labelStyle)
            drawText(text, topLeft = Offset(0f, gy - text.size.height / 2f))
        }

        val path = androidx.compose.ui.graphics.Path()
        points.forEachIndexed { i, p ->
            val px = x(p.at)
            val py = y(p.rank.toDouble())
            if (i == 0) {
                path.moveTo(px, py)
            } else {
                // Stepped: a level HOLDS until the next read changes it, so
                // the line runs flat across and then jumps.
                path.lineTo(px, y(points[i - 1].rank.toDouble()))
                path.lineTo(px, py)
            }
        }
        drawPath(path, line, style = Stroke(width = 2.dp.toPx()))
        points.forEach { p ->
            drawCircle(line, radius = 3.5.dp.toPx(), center = Offset(x(p.at), y(p.rank.toDouble())))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The per-skill pages
//
// One measured number, the sentence that says what was measured, its trend
// over the band it sits in, the coach's note, and the way to improve it.
// Progress MEASURES — every action here leaves the tab, because the DOING
// lives in Talk and Practice.
// ─────────────────────────────────────────────────────────────────────────────

/** Where a page's advice is actually carried out. */
class ProgressAction(val title: String, val run: () -> Unit,
                     val icon: androidx.compose.ui.graphics.vector.ImageVector? = null)

@Composable
fun ProgressSkillPage(
    dim: Dim,
    m: ProgressMetrics,
    onSeeWords: (() -> Unit)? = null,
    onReviewSlips: (() -> Unit)? = null,
    onStartTalk: (() -> Unit)? = null,
    onBrowseExpressions: (() -> Unit)? = null,
) {
    when (dim) {
        Dim.VOCABULARY -> VocabularyPage(m, onSeeWords, onBrowseExpressions)
        Dim.FLUENCY -> MeasuredPage(
            dim = dim, m = m,
            big = if (m.effectivePace > 0) "${m.effectivePace}" else "—",
            unit = stringResource(
                if (m.articulationWpm > 0) R.string.unit_words_min_speaking
                else R.string.unit_words_min),
            band = fluencyBandLabel(m),
            measured = if (m.effectivePace > 0)
                stringResource(R.string.fluency_measured_line,
                    String.format(Locale.getDefault(), "%.1f", m.pausesPerMin),
                    m.talkMinutes, m.wordsPerTurn)
            else null,
            measures = stringResource(
                R.string.words_per_minute_of_voiced_speech_pauses_and_think_time_don_e12672),
            improve = stringResource(R.string.talk_more_often_and_a_little_longer),
            action = onStartTalk?.let { ProgressAction(stringResource(R.string.start_a_talk), it,
                androidx.compose.material.icons.Icons.Filled.GraphicEq) },
            trend = m.fluencyTrend,
            trendCaption = stringResource(
                R.string.one_point_per_talk_with_cefr_pace_bands_behind_the_curve),
            bands = ProgressBands.fluency,
        )
        Dim.GRAMMAR -> MeasuredPage(
            dim = dim, m = m,
            big = m.grammarLevel?.let { "≈" + it.code.uppercase() } ?: "—",
            unit = stringResource(R.string.grammatical_control),
            band = null,
            measured = if (m.grammarCeiling != null) when (val c = m.grammarCeiling!!) {
                is GrammarCeiling.Range -> stringResource(
                    R.string.accurate_within_structures_the_sentences_you_build_set_this_628af6, c.level.code.uppercase())
                is GrammarCeiling.Vocabulary -> stringResource(
                    R.string.capped_at_by_the_words_you_use_your_next_talk_will_be_read_f_13babf, c.level.code.uppercase())
            } else if (m.slipsPer100Words > 0)
                stringResource(R.string.grammar_measured_line,
                    String.format(Locale.getDefault(), "%.1f", m.slipsPer100Words),
                    grammarTargetHint(m))
            else stringResource(
                R.string.read_from_verified_grammar_slips_per_100_spoken_words_fewer_6d1e6b),
            measures = stringResource(R.string.counted_from_transcript_verified_slips_only),
            improve = stringResource(R.string.run_your_review_cards_built_from_your_own_slips),
            action = onReviewSlips?.let {
                ProgressAction(stringResource(R.string.review_your_slips), it,
                    androidx.compose.material.icons.Icons.Outlined.Verified)
            },
            trend = m.grammarTrend,
            trendCaption = stringResource(R.string.one_point_per_talk_down_is_progress),
            bands = ProgressBands.grammarDensity,
            trendTarget = m.grammarNextThreshold,
        )
        Dim.EXPRESSIVENESS -> MeasuredPage(
            dim = dim, m = m,
            big = if (m.wordsPerTurn > 0) "${m.wordsPerTurn}" else "—",
            unit = stringResource(R.string.words_per_turn),
            band = null,
            measured = stringResource(R.string.how_much_you_elaborate_longer_richer_turns_read_higher),
            measures = stringResource(R.string.how_vividly_and_naturally_you_get_your_meaning_across),
            improve = stringResource(R.string.tell_stories_react_and_add_detail),
            action = onStartTalk?.let { ProgressAction(stringResource(R.string.start_a_talk), it,
                androidx.compose.material.icons.Icons.Filled.GraphicEq) },
            trend = m.expressionTrend,
            trendCaption = stringResource(R.string.one_point_per_talk_with_cefr_bands_behind_the_curve),
            bands = ProgressBands.expression,
        )
        Dim.OVERALL -> Unit
    }
}

/** Pace in words, not a band letter — the one place this page speaks plainly. */
@Composable
private fun fluencyBandLabel(m: ProgressMetrics): String? {
    if (m.effectivePace <= 0) return null
    // Articulation rate runs 20–40% higher than wall-clock WPM (the pauses
    // are gone), so the thresholds shift up when it is available.
    val low = if (m.articulationWpm > 0) 90 else 70
    val mid = if (m.articulationWpm > 0) 130 else 110
    val high = if (m.articulationWpm > 0) 170 else 150
    return stringResource(when {
        m.effectivePace < low -> R.string.finding_your_flow
        m.effectivePace < mid -> R.string.pace_conversational
        m.effectivePace < high -> R.string.pace_fluent
        else -> R.string.pace_very_fluent
    })
}

/** "— get under 2.0 and this reads ≈B2": the concrete next-band goal. */
@Composable
private fun grammarTargetHint(m: ProgressMetrics): String {
    val t = m.grammarNextThreshold ?: return ""
    val next = m.grammarLevel?.let { ProgressBands.next(it) } ?: return ""
    return stringResource(R.string.get_under_1f_and_this_reads, t, next.code.uppercase())
}

@Composable
private fun MeasuredPage(
    dim: Dim,
    m: ProgressMetrics,
    big: String,
    unit: String,
    band: String?,
    measured: String?,
    measures: String,
    improve: String,
    action: ProgressAction?,
    trend: List<TrendPoint>,
    trendCaption: String,
    bands: List<BandSpec>,
    trendTarget: Double? = null,
) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        ProgressPanel {
            BigFigureRow(big, unit) {
                band?.let {
                    Text(it, style = PT.subheadline.copy(fontWeight = FontWeight.SemiBold))
                }
            }
            measured?.let { Text(it, style = PT.callout, color = secondary) }
            Text(measures, style = PT.footnote, color = MaterialTheme.colorScheme.outline)
        }

        if (trend.size >= 2) {
            ProgressPanel {
                Text(stringResource(R.string.trend), style = PT.headline)
                TrendChart(trend, bands = bands, target = trendTarget)
                Text(trendCaption, style = PT.caption, color = secondary)
            }
        }

        // The LLM's only contribution to this page, and it is anchored to the
        // numbers above rather than inventing one of its own.
        m.notes[dim].orEmpty().takeIf { it.isNotEmpty() }?.let { notes ->
            ProgressPanel {
                Text(stringResource(R.string.what_i_noticed_lately), style = PT.headline)
                Text(stringResource(R.string.from_your_recent_sessions),
                    style = PT.caption, color = secondary)
                Text(notes.first(), style = PT.callout)
                notes.drop(1).take(2).forEach {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("•", style = PT.body, color = MaterialTheme.colorScheme.outline)
                        Text(it, style = PT.subheadline, color = secondary)
                    }
                }
            }
        }

        ProgressPanel {
            Text(stringResource(R.string.how_to_improve), style = PT.headline)
            Text(improve, style = PT.callout)
            action?.let { ProgressActionButton(it) }
        }
    }
}

/** iOS: the big figure in the display face at 44, its unit in subheadline
 *  on the same baseline, and an optional trailing accessory. */
@Composable
private fun BigFigureRow(big: String, unit: String, trailing: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(big, style = DisplayFace.style(big, PT.pixel(44)),
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.alignByBaseline())
        Text(unit, style = PT.subheadline, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f).alignByBaseline())
        Box(Modifier.alignByBaseline()) { trailing() }
    }
}

@Composable
private fun VocabularyPage(
    m: ProgressMetrics,
    onSeeWords: (() -> Unit)?,
    onBrowseExpressions: (() -> Unit)?,
) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        ProgressPanel {
            BigFigureRow(m.vocabLevel?.code?.uppercase() ?: "—",
                stringResource(R.string.vocabulary_level_9f6896))
            // The count is lifetime, not a window: `VocabStore` exposes the
            // per-band totals and not the dates behind them, so the sentence
            // claims no window it cannot back up.
            Text(stringResource(R.string.estimated_from_lld_distinct_words_graded_by_cefr, m.usedTotal),
                style = PT.callout, color = secondary)
        }

        ProgressPanel {
            Text(stringResource(R.string.words_you_use_by_level), style = PT.headline)
            Text(stringResource(R.string.distinct_words_from_your_talks),
                style = PT.caption, color = secondary)
            val peak = (m.perLevel.values.maxOrNull() ?: 1).coerceAtLeast(1)
            CefrLevel.entries.forEach { lv ->
                VocabLevelBar(lv, m.perLevel[lv] ?: 0, peak, lv == m.vocabLevel)
            }
        }

        ProgressPanel {
            Text(stringResource(R.string.how_to_level_up), style = PT.headline)
            Text(stringResource(R.string.discover_and_use_words_you_don_t_reach_for_yet_the_ones_at_a_d0a120),
                style = PT.callout)
            onSeeWords?.let {
                val nextBand = m.vocabLevel?.let { lv -> ProgressBands.next(lv) ?: lv } ?: CefrLevel.A1
                ProgressActionButton(ProgressAction(
                    stringResource(R.string.see_words, nextBand.code.uppercase()), it,
                    androidx.compose.material.icons.Icons.AutoMirrored.Outlined.MenuBook))
            }
        }

        ProgressPanel {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.expressions_you_ve_used),
                    style = PT.headline, modifier = Modifier.weight(1f))
                Text("${m.expressionCount}", style = PT.headline,
                    color = MaterialTheme.colorScheme.primary)
            }
            Text(stringResource(R.string.multi_word_phrases_you_actually_said_in_your_talks_collected_5b8524),
                style = PT.callout, color = secondary)
            if (m.expressionCount > 0) onBrowseExpressions?.let {
                ProgressActionLink(ProgressAction(stringResource(R.string.browse_expressions), it,
                    androidx.compose.material.icons.Icons.Filled.FormatQuote))
            }
        }
    }
}

@Composable
private fun VocabLevelBar(level: CefrLevel, count: Int, peak: Int, isCurrent: Boolean) {
    // iOS: the current band in the accent colour, every other band in
    // `tertiarySystemFill` — a grey capsule, not Material's surface variant.
    val fill = if (isCurrent) MaterialTheme.colorScheme.primary
    else com.roro.futurevoice.ui.brand.iosFill()
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        val code = level.code.uppercase()
        Text(code, style = DisplayFace.style(code, PT.pixel(15)),
            color = if (isCurrent) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(30.dp))
        Canvas(Modifier.weight(1f).height(12.dp)) {
            val w = if (count == 0) 0f
            else maxOf(6.dp.toPx(), size.width * count / peak.toFloat())
            if (w > 0) drawRoundRect(fill, size = Size(w, size.height),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(6.dp.toPx()))
        }
        Text("$count", style = PT.caption,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
            modifier = Modifier.width(38.dp))
    }
}

/**
 * The panel every Progress section sits in — iOS `panel`: 18 pt of padding,
 * 12 pt between lines, a 20 pt continuous-corner card. One shape for the
 * whole tab. With [onClick] the whole card is the tap target (the streak row).
 */
@Composable
fun ProgressPanel(onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val shape = com.roro.futurevoice.ui.brand.ContinuousShape(20.dp)
    Column(
        Modifier.fillMaxWidth()
            .clip(shape)
            .background(com.roro.futurevoice.ui.brand.AppSurfaces.card, shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) { content() }
}

/** iOS `.borderedProminent` at `.large`: full width, because in these panels
 *  the way out IS the subject. A filled capsule, the label in subheadline
 *  semibold with its glyph. */
@Composable
fun ProgressActionButton(action: ProgressAction) {
    val tint = MaterialTheme.colorScheme.primary
    Row(
        Modifier.fillMaxWidth().padding(top = 2.dp)
            .height(50.dp)
            .clip(CircleShape)
            .background(tint)
            .clickable(onClick = action.run),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        action.icon?.let {
            Icon(it, contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(action.title, style = PT.subheadline.copy(fontWeight = FontWeight.SemiBold),
            color = Color.White)
    }
}

/** iOS `.bordered` at `.small`: compact, under a tip whose subject is the
 *  measurement — a tinted-grey capsule with the accent label. */
@Composable
fun ProgressActionLink(action: ProgressAction) {
    val tint = MaterialTheme.colorScheme.primary
    Row(
        Modifier.clip(CircleShape)
            .background(com.roro.futurevoice.ui.brand.iosFill())
            .clickable(onClick = action.run)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        action.icon?.let {
            Icon(it, contentDescription = null, tint = tint, modifier = Modifier.size(15.dp))
        }
        Text(action.title, style = PT.subheadline.copy(fontWeight = FontWeight.Medium), color = tint)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// How this is assessed
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The recipe, with the learner's LIVE numbers: every ingredient names its
 * measurement and how that maps to a band, so the level never reads as a
 * black box (or as "just vocabulary"). iOS draws it as an inset-grouped List
 * under an inline title with Done — the same Form pieces here.
 *
 * `levelEvidence` is deliberately NOT drawn — it is the prompt block handed
 * to the judge, English snake_case field names written FOR a model, and the
 * rows below already state every one of those numbers in the learner's own
 * language.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun HowAssessedSheet(
    level: CefrLevel?,
    rationale: String?,
    firstReportMinutes: Int,
    m: ProgressMetrics,
    onDismiss: () -> Unit,
) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    androidx.compose.material3.ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
        containerColor = com.roro.futurevoice.ui.brand.AppSurfaces.ground,
    ) {
        Column(
            Modifier.fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
        ) {
            SheetHeader(stringResource(R.string.how_it_s_assessed),
                trailing = { com.roro.futurevoice.ui.brand.IosGlassTextButton(
                    stringResource(R.string.done), onDismiss, bold = true) })

            FormSection(header = stringResource(
                if (rationale.isNullOrBlank()) R.string.the_estimated_level else R.string.why_this_level)) {
                level?.let {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.assessed_level),
                            style = PT.subheadline.copy(fontWeight = FontWeight.Medium),
                            modifier = Modifier.weight(1f))
                        Text(it.code.uppercase(), style = PT.headline,
                            color = MaterialTheme.colorScheme.primary)
                    }
                    FormDivider()
                }
                rationale?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = PT.callout,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
                    FormDivider()
                }
                Text(stringResource(
                    R.string.your_level_comes_from_periodic_assessments_each_one_pools_ev_20fb6b,
                    firstReportMinutes),
                    style = PT.callout,
                    color = if (rationale.isNullOrBlank()) MaterialTheme.colorScheme.onSurface
                    else secondary,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
            }

            FormSection(header = stringResource(R.string.what_s_measured),
                footer = stringResource(
                    R.string.marks_a_deterministic_proxy_a_real_measurement_mapped_to_a_c_729797)) {
                AssessedRow(stringResource(R.string.vocabulary),
                    m.vocabLevel?.code?.uppercase(),
                    stringResource(R.string.assessed_detail_vocabulary, m.usedTotal))
                FormDivider()
                AssessedRow(stringResource(R.string.fluency),
                    m.fluencyLevel?.let { "≈" + it.code.uppercase() },
                    stringResource(R.string.assessed_detail_fluency, m.effectivePace))
                FormDivider()
                AssessedRow(stringResource(R.string.grammar),
                    m.grammarLevel?.let { "≈" + it.code.uppercase() },
                    if (m.slipsPer100Words > 0)
                        stringResource(R.string.assessed_detail_grammar_density,
                            String.format(Locale.getDefault(), "%.1f", m.slipsPer100Words))
                    else if (m.grammarScore > 0)
                        stringResource(R.string.assessed_detail_grammar_score, m.grammarScore)
                    else stringResource(
                        R.string.read_from_verified_grammar_slips_per_100_spoken_words_fewer_6d1e6b))
                FormDivider()
                AssessedRow(stringResource(R.string.expressiveness),
                    m.expressionLevel?.let { "≈" + it.code.uppercase() },
                    stringResource(R.string.assessed_detail_expression, m.wordsPerTurn))
            }

            FormSection(header = stringResource(R.string.what_never_moves_the_level)) {
                Text(stringResource(R.string.shadowing_scores_and_review_reps_measure_practice_not_level_4c91dc),
                    style = PT.callout,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
            }
        }
    }
}

@Composable
private fun AssessedRow(name: String, level: String?, detail: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(name, style = PT.subheadline.copy(fontWeight = FontWeight.Medium))
            Text(detail, style = PT.caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(level ?: "—", style = PT.headline, color = MaterialTheme.colorScheme.primary)
    }
}
