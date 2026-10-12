package com.roro.futurevoice.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.TrendingDown
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MicExternalOn
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.SmartDisplay
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.EffortCategory
import com.roro.futurevoice.data.EffortDay
import com.roro.futurevoice.data.EffortHistory
import com.roro.futurevoice.data.ShadowAttemptStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.core.UILanguage
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.EffortCharts
import com.roro.futurevoice.ui.brand.IosSegmented
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// MARK: - The kinds' look (iOS `EffortCategory.label/symbol/color`)

/** The routine's colours where the routine has the kind (talk blue, say it
 *  again teal, words purple, expressions pink, shadowing yellow, review green
 *  for sentence cards); the two it has no block for take colours nothing else
 *  here uses. Never indigo — that is the Core's. */
internal val EffortCategory.color: Color get() = when (this) {
    EffortCategory.TALK -> Color(0xFF007AFF)
    EffortCategory.WORDS -> Color(0xFFAF52DE)
    EffortCategory.EXPRESSIONS -> Color(0xFFFF2D55)
    EffortCategory.SENTENCES -> Color(0xFF34C759)
    EffortCategory.SHADOWING -> Color(0xFFFFCC00)
    EffortCategory.SAY_IT_AGAIN -> Color(0xFF30B0C7)
    EffortCategory.SPEECH -> Color(0xFFA2845E)
    EffortCategory.SCENES -> Color(0xFF8E8E93)
}

internal val EffortCategory.icon: ImageVector get() = when (this) {
    EffortCategory.TALK -> Icons.Filled.Phone
    EffortCategory.WORDS -> Icons.Filled.TextFields
    EffortCategory.EXPRESSIONS -> Icons.Filled.FormatQuote
    EffortCategory.SENTENCES -> Icons.Filled.ViewAgenda
    EffortCategory.SHADOWING -> Icons.Filled.GraphicEq
    EffortCategory.SAY_IT_AGAIN -> Icons.Filled.Replay
    EffortCategory.SPEECH -> Icons.Filled.MicExternalOn
    EffortCategory.SCENES -> Icons.Filled.SmartDisplay
}

@Composable
internal fun EffortCategory.label(): String = stringResource(when (this) {
    EffortCategory.TALK -> R.string.talk
    EffortCategory.WORDS -> R.string.words_d26d55
    EffortCategory.EXPRESSIONS -> R.string.expressions
    EffortCategory.SENTENCES -> R.string.sentences
    EffortCategory.SHADOWING -> R.string.shadowing
    EffortCategory.SAY_IT_AGAIN -> R.string.say_it_again
    EffortCategory.SPEECH -> R.string.speech_d00d85
    EffortCategory.SCENES -> R.string.scenes
})

/** "47 min", "32 cards". */
@Composable
internal fun EffortCategory.amountText(value: Double): String {
    val n = kotlin.math.floor(value).toInt()
    return when (this) {
        EffortCategory.TALK -> stringResource(R.string.lld_min_b61908, n)
        EffortCategory.WORDS -> if (n == 1) stringResource(R.string.s_1_word) else stringResource(R.string.lld_words, n)
        EffortCategory.EXPRESSIONS -> if (n == 1) stringResource(R.string.s_1_expression)
            else stringResource(R.string.lld_expressions, n)
        EffortCategory.SENTENCES -> if (n == 1) stringResource(R.string.s_1_card) else stringResource(R.string.lld_cards, n)
        EffortCategory.SHADOWING -> if (n == 1) stringResource(R.string.s_1_take) else stringResource(R.string.lld_takes, n)
        EffortCategory.SAY_IT_AGAIN, EffortCategory.SPEECH ->
            if (n == 1) stringResource(R.string.s_1_run) else stringResource(R.string.lld_runs, n)
        EffortCategory.SCENES -> if (n == 1) stringResource(R.string.s_1_scene) else stringResource(R.string.lld_scenes, n)
    }
}

/** iOS `Color(.systemGray3)` — "Other practice" beside talking. */
private val OtherPractice = Color(0xFFC7C7CC)
private val Green = Color(0xFF34C759)
private val Orange = Color(0xFFFF9500)

@Composable
private fun chromeLocale(): Locale {
    val context = LocalContext.current
    return Locale.forLanguageTag(UILanguage.current(context) ?: Locale.getDefault().toLanguageTag())
}

private fun monthDay(at: Long, locale: Locale): String =
    SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd"), locale)
        .format(Date(at))

/**
 * Effort in depth — behind the Growth tab's "Your effort" card (iOS
 * `EffortDetailView`, ce099149 + ceefaeac). A week or a month: the whole of
 * it first, the picked kind's day-by-day trend with every kind as a thin row
 * under it, and what each day was made of. The card on Growth stays small;
 * this page is where the numbers live.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EffortDetailScreen(
    language: String,
    goalMinutes: Int,
    onOpenActivity: () -> Unit,
    onBack: () -> Unit,
) {
    NavPageBackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    /** 0 = week, 1 = month. */
    var range by remember { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf(EffortCategory.TALK) }
    /** Two periods back to back, oldest first — the second half is the
     *  period on screen, the first half what it is compared with. */
    var history by remember { mutableStateOf<List<EffortDay>>(emptyList()) }
    var shadowDelta by remember { mutableStateOf<Int?>(null) }
    var takesThisWeek by remember { mutableIntStateOf(0) }
    var avgShadowScore by remember { mutableIntStateOf(0) }

    LaunchedEffect(language, revision) {
        history = withContext(Dispatchers.IO) { EffortHistory.days(context, 60, language) }
        val attempts = ShadowAttemptStore.shared(context).load(language)
        // iOS `PracticeStats.shadowTrend`: this week against the one before.
        val now = System.currentTimeMillis()
        val weekAgo = now - 7 * 86_400_000L
        val twoWeeksAgo = now - 14 * 86_400_000L
        val thisWeek = attempts.filter { it.createdAt > weekAgo }
        val prevWeek = attempts.filter { it.createdAt in (twoWeeksAgo + 1)..weekAgo }
        fun avg(l: List<com.roro.futurevoice.data.ShadowAttempt>) =
            if (l.isEmpty()) 0 else Math.round(l.sumOf { it.overallScore }.toDouble() / l.size).toInt()
        takesThisWeek = thisWeek.size
        shadowDelta = if (thisWeek.isNotEmpty() && avg(prevWeek) > 0) avg(thisWeek) - avg(prevWeek) else null
        val recent = attempts.sortedByDescending { it.createdAt }.take(10).map { it.overallScore }
        avgShadowScore = if (recent.isEmpty()) 0 else recent.sum() / recent.size
    }

    val days = if (range == 0) 7 else 30
    val current = history.takeLast(days)
    val previous = history.dropLast(days).takeLast(days)
    /** Categories with anything in either period; talk always, so the page
     *  is never empty of its main number. */
    val shown = EffortCategory.entries.filter { c ->
        c == EffortCategory.TALK || EffortHistory.total(c, current) > 0 || EffortHistory.total(c, previous) > 0
    }
    LaunchedEffect(range, history) { if (selected !in shown) selected = EffortCategory.TALK }
    val previousLabel = stringResource(if (range == 0) R.string.vs_last_week else R.string.vs_previous_30_days)

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.your_effort)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            IosSegmented(
                options = listOf(stringResource(R.string.week_f82be6), stringResource(R.string.month_082bc3)),
                selected = range,
                onSelect = { range = it },
                modifier = Modifier.fillMaxWidth(),
            )
            if (history.isEmpty()) return@Column

            Summary(current, previous, days, previousLabel)
            TrendPanel(current, previous, days, selected, shown, previousLabel, goalMinutes,
                onSelect = { selected = it })
            MixPanel(current, days)
            if (avgShadowScore > 0) ShadowPanel(avgShadowScore, shadowDelta, takesThisWeek)

            TintLink(stringResource(R.string.calendar_and_routine), Icons.Filled.CalendarMonth,
                modifier = Modifier.padding(horizontal = 4.dp),
                style = PT.body, onClick = onOpenActivity)
        }
    }
}

// MARK: - Summary

/** The whole of it first: every minute spent studying, split into talking
 *  and everything else, before any one kind is picked apart. */
@Composable
private fun Summary(current: List<EffortDay>, previous: List<EffortDay>, days: Int, previousLabel: String) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val locale = chromeLocale()
    val activeDays = current.count { it.isActive }
    val talks = current.sumOf { it.talks }
    val study = EffortHistory.studyMinutes(current)
    val before = EffortHistory.studyMinutes(previous)
    // App time is kept 45 days like the talk meter, so only a week has a
    // whole period before it to compare with.
    val comparable = days * 2 <= EffortHistory.TALK_REACH_DAYS
    val talking = stringResource(R.string.talking)
    val other = stringResource(R.string.other_practice)
    ProgressPanel {
        PanelHeader(stringResource(R.string.all_activity)) {
            val first = current.firstOrNull()?.day
            val last = current.lastOrNull()?.day
            if (first != null && last != null) {
                Text("${monthDay(first, locale)} – ${monthDay(last, locale)}",
                    style = PT.caption, color = secondary)
            }
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("$study", style = PT.largeTitle)
            Text(stringResource(R.string.min_studied), style = PT.subheadline, color = secondary,
                modifier = Modifier.padding(bottom = 6.dp))
            Spacer(Modifier.weight(1f))
            if (comparable && study != before) {
                val d = study - before
                Text((if (d > 0) "+$d" else "$d") + " " + previousLabel,
                    style = PT.caption.copy(fontWeight = FontWeight.SemiBold),
                    color = if (d > 0) Green else secondary,
                    modifier = Modifier.padding(bottom = 6.dp))
            }
        }
        EffortCharts.Bars(
            days = current.map { d ->
                EffortCharts.DayBar(dayLabel(d.day, days, locale), listOf(
                    EffortCategory.TALK.color to d.talkSeconds / 60f,
                    OtherPractice to d.otherSeconds / 60f))
            },
            height = 150.dp,
            labelEvery = if (days == 7) 1 else 5,
        )
        FlowLegend(listOf(talking to EffortCategory.TALK.color, other to OtherPractice))
        PanelDivider()
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            EffortStat("${EffortHistory.total(EffortCategory.TALK, current).toInt()}",
                stringResource(R.string.min_talking), Modifier.weight(1f))
            EffortStat("${EffortHistory.otherMinutes(current)}",
                stringResource(R.string.min_other_practice), Modifier.weight(1f))
            EffortStat("$talks", stringResource(if (talks == 1) R.string.talk_e55e91 else R.string.talks_b1cc1f),
                Modifier.weight(1f))
            EffortStat("$activeDays/$days", stringResource(R.string.days_active), Modifier.weight(1f))
        }
        Text(stringResource(R.string.time_in_the_app_every_day_you_opened_it_talking_and_everythi_c65ddc),
            style = PT.caption, color = secondary)
    }
}

// MARK: - Trend (the picked kind, day by day, every kind as a row under it)

@Composable
private fun TrendPanel(
    current: List<EffortDay>,
    previous: List<EffortDay>,
    days: Int,
    selected: EffortCategory,
    shown: List<EffortCategory>,
    previousLabel: String,
    goalMinutes: Int,
    onSelect: (EffortCategory) -> Unit,
) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val locale = chromeLocale()
    val values = current.map { it.amount(selected) }
    val avg = if (values.isEmpty()) 0.0 else values.sum() / values.size
    val best = current.maxByOrNull { it.amount(selected) }
    val avgText = if (selected.isTimed) stringResource(R.string.lld_min_b61908, Math.round(avg).toInt())
        else if (avg < 10) String.format(Locale.US, "%.1f", avg) else "${Math.round(avg)}"
    ProgressPanel {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(selected.icon, contentDescription = null, tint = selected.color, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(selected.label(), style = PT.headline, color = selected.color, modifier = Modifier.weight(1f))
            Text(stringResource(R.string.avg_a_day, avgText),
                style = PT.caption.copy(fontWeight = FontWeight.SemiBold), color = secondary)
        }
        EffortCharts.Bars(
            days = current.map { d ->
                EffortCharts.DayBar(dayLabel(d.day, days, locale),
                    listOf(selected.color to d.amount(selected).toFloat()))
            },
            goal = if (selected == EffortCategory.TALK) goalMinutes.toFloat()
                else avg.toFloat().takeIf { it > 0f },
            height = 140.dp,
            labelEvery = if (days == 7) 1 else 5,
        )
        Text(
            when {
                selected == EffortCategory.TALK -> stringResource(
                    R.string.minutes_you_actually_talked_per_day_the_dashed_line_is_your_7e3d9a, goalMinutes)
                best != null && best.amount(selected) > 0 -> stringResource(
                    R.string.dashed_line_your_daily_average_best_day,
                    monthDay(best.day, locale), selected.amountText(best.amount(selected)))
                else -> stringResource(R.string.nothing_yet_in_this_period)
            },
            style = PT.caption, color = secondary)
        PanelDivider()
        Text(previousLabel, style = PT.caption2, color = secondary, textAlign = TextAlign.End,
            modifier = Modifier.fillMaxWidth().padding(end = 102.dp))
        // Every kind as a thin row under the chart it drives — tiles two by
        // two pushed the chart below the screen, so a tap changed something
        // nobody could see.
        Column {
            shown.forEachIndexed { i, c ->
                if (i > 0) androidx.compose.material3.HorizontalDivider(
                    Modifier.padding(start = 28.dp),
                    color = MaterialTheme.colorScheme.outlineVariant, thickness = 0.5.dp)
                KindRow(c, c == selected, days,
                    now = EffortHistory.total(c, current),
                    before = EffortHistory.total(c, previous),
                    onClick = { onSelect(c) })
            }
        }
    }
}

@Composable
private fun KindRow(c: EffortCategory, isSelected: Boolean, days: Int, now: Double, before: Double,
                    onClick: () -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(if (isSelected) c.color.copy(alpha = 0.12f) else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp, horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(c.icon, contentDescription = null, tint = c.color, modifier = Modifier.size(18.dp))
        Text(c.label(),
            style = PT.subheadline.copy(fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal),
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        // Against the period before. Talk minutes only reach back
        // TALK_REACH_DAYS, so a month's talk has nothing honest to compare
        // with and says nothing rather than "+47 min" against an empty log.
        Box(Modifier.widthIn(min = 40.dp), contentAlignment = Alignment.CenterEnd) {
            if (!(c.isTimed && days * 2 > EffortHistory.TALK_REACH_DAYS)) {
                val d = kotlin.math.floor(now).toInt() - kotlin.math.floor(before).toInt()
                Text(if (d == 0) stringResource(R.string.same_as_before) else if (d > 0) "+$d" else "$d",
                    style = PT.caption2, color = if (d > 0) Green else secondary, maxLines = 1)
            }
        }
        Text(c.amountText(now), style = PT.subheadline.copy(fontWeight = FontWeight.SemiBold),
            textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.widthIn(min = 84.dp))
    }
}

// MARK: - Mix (what each day was made of)

/** Everything counted in things done, stacked. Talk stays out — minutes and
 *  counts on one axis would be one bar measured in two units. */
@Composable
private fun MixPanel(current: List<EffortDay>, days: Int) {
    val kinds = EffortCategory.entries.filter { !it.isTimed }
    val present = kinds.filter { c -> current.any { it.amount(c) > 0 } }
    if (present.isEmpty()) return
    val locale = chromeLocale()
    ProgressPanel {
        Text(stringResource(R.string.what_each_day_was_made_of), style = PT.headline)
        EffortCharts.Bars(
            days = current.map { d ->
                EffortCharts.DayBar(dayLabel(d.day, days, locale),
                    present.map { it.color to d.amount(it).toFloat() })
            },
            height = 150.dp,
            labelEvery = if (days == 7) 1 else 5,
        )
        FlowLegend(present.map { it.label() to it.color })
        Text(stringResource(R.string.every_word_expression_and_card_you_studied_shadow_take_run_a_66737b),
            style = PT.caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// MARK: - Shadowing quality

@Composable
private fun ShadowPanel(avgShadowScore: Int, delta: Int?, takesThisWeek: Int) {
    ProgressPanel {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.shadowing_score), style = PT.headline, modifier = Modifier.weight(1f))
            if (delta != null) {
                val tint = if (delta >= 0) Green else Orange
                Icon(if (delta >= 0) Icons.AutoMirrored.Filled.TrendingUp else Icons.AutoMirrored.Filled.TrendingDown,
                    contentDescription = null, tint = tint, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text(if (delta >= 0) "+$delta" else "$delta",
                    style = PT.caption.copy(fontWeight = FontWeight.SemiBold), color = tint)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            EffortStat("$avgShadowScore", stringResource(R.string.average_of_your_last_10_takes), Modifier.weight(1f))
            if (takesThisWeek > 0) {
                EffortStat("$takesThisWeek", stringResource(R.string.takes_this_week), Modifier.weight(1f))
            }
        }
    }
}

// MARK: - Building blocks

private fun dayLabel(at: Long, days: Int, locale: Locale): String =
    SimpleDateFormat(if (days == 7) "EEEEE" else "d", locale).format(Date(at))

@Composable
private fun EffortStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(value, style = PT.title3.copy(fontWeight = FontWeight.Bold))
        Text(label, style = PT.caption2, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FlowLegend(entries: List<Pair<String, Color>>) {
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        entries.forEach { (label, color) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Canvas(Modifier.size(8.dp)) { drawCircle(color) }
                Text(label, style = PT.caption2, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/**
 * The Growth tab's one effort card: this week at a glance, everything else
 * one tap away in [EffortDetailScreen] (iOS `EffortSummaryCard`).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EffortSummaryCard(week: List<EffortDay>, lastWeek: List<EffortDay>) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val locale = chromeLocale()
    val talkMinutes = EffortHistory.total(EffortCategory.TALK, week).toInt()
    val activeDays = week.count { it.isActive }
    /** The kinds done this week, in a fixed order so the row reads the same
     *  every week. */
    val kinds = EffortCategory.entries.filter { !it.isTimed && EffortHistory.total(it, week) > 0 }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.your_effort), style = PT.headline, modifier = Modifier.weight(1f))
            Text(stringResource(R.string.this_week), style = PT.caption, color = secondary)
            Chevron()
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${EffortHistory.studyMinutes(week)}", style = PT.largeTitle)
                    Text(stringResource(R.string.min_studied), style = PT.subheadline, color = secondary,
                        modifier = Modifier.padding(bottom = 6.dp))
                }
                LegendLine(EffortCategory.TALK.color, stringResource(R.string.lld_min_talking, talkMinutes))
                LegendLine(OtherPractice,
                    stringResource(R.string.lld_min_other_practice, EffortHistory.otherMinutes(week)))
                Text(stringResource(R.string.lld_of_7_days_active, activeDays), style = PT.caption, color = secondary)
            }
            // Talking over everything else, a day per bar — the whole week's
            // time at a glance.
            Box(Modifier.width(120.dp)) {
                EffortCharts.Bars(
                    days = week.map { d ->
                        EffortCharts.DayBar(SimpleDateFormat("EEEEE", locale).format(Date(d.day)), listOf(
                            EffortCategory.TALK.color to d.talkSeconds / 60f,
                            OtherPractice to d.otherSeconds / 60f))
                    },
                    height = 54.dp,
                    labelEvery = 1,
                )
            }
        }
        if (kinds.isNotEmpty()) {
            PanelDivider()
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                kinds.forEach { c ->
                    KindChip(c, EffortHistory.total(c, week).toInt(), EffortHistory.total(c, lastWeek).toInt())
                }
            }
        }
    }
}

@Composable
private fun LegendLine(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Canvas(Modifier.size(6.dp)) { drawCircle(color) }
        Text(text, style = PT.caption, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
    }
}

@Composable
private fun KindChip(c: EffortCategory, now: Int, before: Int) {
    Row(Modifier.widthIn(min = 96.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(c.icon, contentDescription = null, tint = c.color, modifier = Modifier.size(14.dp))
        Column {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("$now", style = PT.subheadline.copy(fontWeight = FontWeight.SemiBold))
                if (now > before) {
                    Icon(Icons.Filled.ArrowUpward, contentDescription = null, tint = Green,
                        modifier = Modifier.size(11.dp))
                }
            }
            Text(c.label(), style = PT.caption2, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
    }
}
