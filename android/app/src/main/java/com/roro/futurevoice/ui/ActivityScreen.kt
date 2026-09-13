package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AppUsageLog
import com.roro.futurevoice.data.DayCardStore
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.TalkTime
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DayCardData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * How far back the meter keeps a day. `TalkTimeLog` PRUNES at 45 days, so
 * asking it for more returns zeros rather than history — 45 is the data, not
 * a window this screen chose. Older days are still drawn where something
 * unpruned remembers them (a saved talk, a practice rep, the day's own frozen
 * card), and the grid says out loud that the minutes themselves are gone.
 */
private const val TALK_LOG_DAYS = 45

/**
 * A scan has to stop somewhere: the record is walked day by day to read each
 * day's frozen card, and an account with a three-year-old first talk should
 * not pay for a decade of file probes to draw this month.
 */
private const val RECORD_SCAN_DAYS = 1100

private enum class Period(val labelRes: Int) {
    MONTH(R.string.month_082bc3),
    YEAR(R.string.year_879e32),
}

/** The record as a whole — it does not change when you page to another month. */
private data class Headline(
    val streak: Int = 0,
    val longest: Int = 0,
    val totalSeconds: Int = 0,
    val activeDays: Int = 0,
)

private data class Record(
    val seconds: Map<String, Int> = emptyMap(),
    val active: Set<String> = emptySet(),
    val headline: Headline = Headline(),
)

/**
 * The record: a month or a year at a time, and what each day was.
 *
 * The calendar IS the collection — every day is a full-width rounded TILE, and
 * a day with a photo shows it. A separate grid of cards was built on iOS and
 * folded back the same week: a second grid of the same days is a parallel
 * calendar. So the month reads as the places you studied (circles showed a
 * photo as a smudge), and selecting a day puts that day's card at the top of
 * its summary.
 *
 * This is the day card's ONLY home. The day summary already says what the day
 * was, and the card is that summary as a picture.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityScreen(language: String, onOpenTalk: (String) -> Unit, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    var period by remember { mutableStateOf(Period.MONTH) }
    var anchor by remember { mutableStateOf(startOfMonth(System.currentTimeMillis())) }
    var selected by remember { mutableStateOf(startOfDay(System.currentTimeMillis())) }
    // SECONDS, not minutes. A talk under a minute rounds to zero, and that
    // day would then be indistinguishable from one nobody opened the app on —
    // which is exactly the day the wall exists to show.
    var record by remember { mutableStateOf(Record()) }
    var sessions by remember { mutableStateOf<List<Session>>(emptyList()) }
    var photos by remember { mutableStateOf<Map<String, ImageBitmap>>(emptyMap()) }
    var selectedPhoto by remember { mutableStateOf<ImageBitmap?>(null) }
    var showCard by remember { mutableStateOf(false) }

    // Keyed on the language ALONE: the record is the same whichever period is
    // on screen, and re-walking it on every arrow tap is the one thing that
    // would make paging feel slow.
    LaunchedEffect(language) {
        val talks = SessionStore.shared(context).load(language)
        sessions = talks
        record = withContext(Dispatchers.IO) { readRecord(context, talks) }
    }

    LaunchedEffect(anchor, period) {
        // Only the days on screen, and only in month view: loading a photo is
        // a decode, and a year cell is too small to show one anyway.
        photos = if (period == Period.MONTH) {
            withContext(Dispatchers.IO) {
                daysIn(anchor).filterNotNull().mapNotNull { day ->
                    DayCardStore.photo(context, day)?.let { dayKey(day) to it.asImageBitmap() }
                }.toMap()
            }
        } else emptyMap()
    }

    LaunchedEffect(selected) {
        selectedPhoto = withContext(Dispatchers.IO) {
            DayCardStore.photo(context, selected)?.asImageBitmap()
        }
    }

    val daySessions = sessions.filter {
        dayKey(it.endedAt ?: it.startedAt) == dayKey(selected)
    }
    val selectedSeconds = record.seconds[dayKey(selected)] ?: 0

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.activity)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item { HeadlineStats(record.headline) }

            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    Period.entries.forEachIndexed { index, p ->
                        SegmentedButton(
                            selected = p == period,
                            onClick = { period = p },
                            shape = SegmentedButtonDefaults.itemShape(index, Period.entries.size),
                            label = { Text(stringResource(p.labelRes)) },
                        )
                    }
                }
            }

            item {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { anchor = shift(anchor, period, -1) }) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = null)
                    }
                    Text(periodTitle(anchor, period), style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f))
                    IconButton(
                        onClick = { anchor = shift(anchor, period, 1) },
                        enabled = canGoNext(anchor, period),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
                    }
                }
            }

            item {
                when (period) {
                    Period.MONTH -> MonthWall(
                        month = anchor,
                        secondsByDay = record.seconds,
                        activeDays = record.active,
                        photos = photos,
                        selected = selected,
                        onSelect = { selected = it },
                    )
                    Period.YEAR -> YearWall(
                        year = anchor,
                        secondsByDay = record.seconds,
                        activeDays = record.active,
                        selected = selected,
                        onSelect = { selected = it },
                    )
                }
            }

            item { PeriodFooter(anchor, period, record) }

            item {
                DaySummary(
                    day = selected,
                    seconds = selectedSeconds,
                    talks = daySessions,
                    log = PracticeLog.day(context, selected),
                    photo = selectedPhoto,
                    onShare = { showCard = true },
                    onOpenTalk = onOpenTalk,
                )
            }
        }
    }

    if (showCard) {
        val data = remember(selected, selectedSeconds, daySessions) {
            DayCardStore.snapshot(context, selected) ?: DayCardData(
                date = selected,
                talkMinutes = selectedSeconds / 60,
                // Never less than the talk figure: a call in a pocket is
                // metered but not foregrounded.
                studyMinutes = maxOf(AppUsageLog.secondsOn(context, selected) / 60,
                    selectedSeconds / 60),
                streakDays = TalkTimeLog.streakDays(context, selected),
                talks = daySessions.size,
                reviews = PracticeLog.day(context, selected)?.drillReps ?: 0,
                shadowTakes = PracticeLog.day(context, selected)?.shadowReps ?: 0,
                topics = daySessions.sortedByDescending { s ->
                    s.turns.filter { it.role == TurnRole.USER }.sumOf { it.durationMs }
                }.mapNotNull { it.displayTitle }.distinct().take(4),
            )
        }
        DayCardSheet(data) { showCard = false }
    }
}

// MARK: - Headline stats

/**
 * Four numbers above the calendar: the streak that is running, the best one
 * ever, everything talked, and how many days the learner showed up on.
 *
 * They share the row by CONTENT, not as four equal columns — equal columns
 * hand "3h 12m" exactly the width of "3", so the one stat with something to
 * say sits pressed against its dividers while three single digits waste
 * theirs.
 */
@Composable
private fun HeadlineStats(headline: Headline) {
    val stats = listOf(
        Stat(Icons.Filled.LocalFireDepartment, "${headline.streak}",
            stringResource(R.string.day_streak),
            if (headline.streak > 0) Color(0xFFFF9500) else null),
        Stat(Icons.Filled.EmojiEvents, "${headline.longest}", stringResource(R.string.longest)),
        Stat(Icons.Filled.GraphicEq, talkTotal(headline.totalSeconds),
            stringResource(R.string.total)),
        Stat(Icons.Filled.CalendarMonth, "${headline.activeDays}", stringResource(R.string.days)),
    )
    Row(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, RoundedCornerShape(16.dp))
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        stats.forEachIndexed { index, stat ->
            if (index > 0) {
                VerticalDivider(Modifier.height(26.dp),
                    color = MaterialTheme.colorScheme.outlineVariant)
            }
            Column(
                Modifier.weight(1f).padding(horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(stat.icon, contentDescription = null,
                        tint = stat.tint ?: MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(14.dp))
                    Text(stat.value, style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold, maxLines = 1)
                }
                Text(stat.label, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, textAlign = TextAlign.Center)
            }
        }
    }
}

private data class Stat(
    val icon: ImageVector,
    val value: String,
    val label: String,
    val tint: Color? = null,
)

/**
 * A lifetime total is a SPAN, so it is read in minutes (`TalkTime`) — never a
 * clock, which is the day's register. Past an hour it is humanized the way
 * iOS humanizes it ("47m" → "3h 12m"), because four digits of minutes is a
 * figure nobody converts in their head.
 */
@Composable
private fun talkTotal(seconds: Int): String {
    val minutes = maxOf(0, seconds) / 60
    return if (minutes < 60) stringResource(R.string.lld_m, minutes)
    else stringResource(R.string.lld_h_lld_m, minutes / 60, minutes % 60)
}

// MARK: - The grids

/**
 * The month as a photo wall. Six rows of seven full-width square tiles: a
 * photo day shows its photo, an active day its heat blue, an empty day a
 * faint fill — so the month reads as one surface rather than a field of dots.
 */
@Composable
private fun MonthWall(
    month: Long,
    secondsByDay: Map<String, Int>,
    activeDays: Set<String>,
    photos: Map<String, ImageBitmap>,
    selected: Long,
    onSelect: (Long) -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    val today = startOfDay(System.currentTimeMillis())
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            weekdayLabels().forEach { label ->
                Text(label, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f))
            }
        }
        daysIn(month).chunked(7).forEach { week ->
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                week.forEach { day ->
                    if (day == null) {
                        Box(Modifier.weight(1f).aspectRatio(1f))
                    } else {
                        val key = dayKey(day)
                        val seconds = secondsByDay[key] ?: 0
                        val photo = photos[key]
                        val future = day > today
                        val active = key in activeDays
                        val heat = heatAlpha(seconds)
                        Box(
                            Modifier.weight(1f).aspectRatio(1f)
                                .clip(RoundedCornerShape(9.dp))
                                .background(
                                    if (active) accent.copy(alpha = heat)
                                    else MaterialTheme.colorScheme.surfaceVariant
                                        .copy(alpha = if (future) 0.3f else 0.55f))
                                .border(
                                    width = if (day == selected) 2.5.dp else 1.5.dp,
                                    color = when {
                                        day == selected -> accent
                                        day == today -> accent.copy(alpha = 0.45f)
                                        else -> Color.Transparent
                                    },
                                    shape = RoundedCornerShape(9.dp))
                                .clickable(enabled = !future) { onSelect(day) },
                        ) {
                            if (photo != null) {
                                Image(photo, contentDescription = null,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize())
                            }
                            Text(
                                dayOfMonth(day),
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = if (photo != null || (active && heat >= 0.6f)) Color.White
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(4.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * The year as twelve mini months, three across — the whole year on one screen
 * with no horizontal scroll. Same heat, no photos: a cell this size shows a
 * photo as a smudge, which is the mistake the month wall exists to avoid.
 */
@Composable
private fun YearWall(
    year: Long,
    secondsByDay: Map<String, Int>,
    activeDays: Set<String>,
    selected: Long,
    onSelect: (Long) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        monthsOfYear(year).chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                row.forEach { month ->
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(monthShortLabel(month), style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        MiniMonth(month, secondsByDay, activeDays, selected, onSelect)
                    }
                }
                // A short last row keeps its months the same width as the rest.
                repeat(3 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun MiniMonth(
    month: Long,
    secondsByDay: Map<String, Int>,
    activeDays: Set<String>,
    selected: Long,
    onSelect: (Long) -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    val today = startOfDay(System.currentTimeMillis())
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        daysIn(month).chunked(7).forEach { week ->
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                week.forEach { day ->
                    if (day == null) {
                        Box(Modifier.weight(1f).aspectRatio(1f))
                    } else {
                        val key = dayKey(day)
                        val future = day > today
                        val active = key in activeDays
                        Box(
                            Modifier.weight(1f).aspectRatio(1f)
                                .clip(RoundedCornerShape(2.dp))
                                .background(
                                    if (active) accent.copy(alpha = heatAlpha(secondsByDay[key] ?: 0))
                                    else MaterialTheme.colorScheme.surfaceVariant
                                        .copy(alpha = if (future) 0.4f else 1f))
                                .border(
                                    width = if (day == selected) 1.5.dp
                                    else if (day == today) 1.dp else 0.dp,
                                    color = if (day == selected || day == today) accent
                                    else Color.Transparent,
                                    shape = RoundedCornerShape(2.dp))
                                .clickable(enabled = !future) { onSelect(day) },
                        )
                    }
                }
            }
        }
    }
}

/**
 * ONE line under the grid: how much of the period was used — and, where the
 * period reaches past what the meter keeps, that the minutes for those days
 * are simply gone. A faint older month has to say why it is faint; without
 * this it reads as "you did nothing", which is a lie about a month whose
 * record was pruned.
 */
@Composable
private fun PeriodFooter(anchor: Long, period: Period, record: Record) {
    val days = periodDays(anchor, period)
    val active = days.count { dayKey(it) in record.active }
    // Floored per day, like the home ring and the day card — never seconds
    // summed across the period and floored once.
    val minutes = days.sumOf { (record.seconds[dayKey(it)] ?: 0) / 60 }
    val cutoff = dayBefore(startOfDay(System.currentTimeMillis()), TALK_LOG_DAYS - 1)
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            when (period) {
                Period.MONTH -> stringResource(R.string.lld_active_days_lld_min, active, minutes)
                Period.YEAR ->
                    stringResource(R.string.lld_active_days_lld_min_this_year, active, minutes)
            },
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (days.firstOrNull() != null && days.first() < cutoff) {
            Text(stringResource(R.string.talk_time_is_kept_for_lld_days, TALK_LOG_DAYS),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// MARK: - The day

/**
 * What the selected day was, with its card at the top. The card already
 * prints the day's minutes, so the facts beside it fill the half of the row
 * a thumbnail would otherwise leave empty rather than repeating the number.
 */
@Composable
private fun DaySummary(
    day: Long,
    seconds: Int,
    talks: List<Session>,
    log: PracticeLog.Day?,
    photo: ImageBitmap?,
    onShare: () -> Unit,
    onOpenTalk: (String) -> Unit,
) {
    val shadowed = log?.shadowReps ?: 0
    val reviewed = log?.drillReps ?: 0
    val notebookReps = (log?.wordReps ?: 0) + (log?.expressionReps ?: 0)
    val empty = seconds == 0 && talks.isEmpty() && shadowed == 0 && reviewed == 0 &&
        notebookReps == 0

    Column(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(dayTitle(day), style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f))
            // Only for a day that has something on it — an empty day has
            // nothing to put on a card.
            if (!empty) {
                OutlinedButton(onClick = onShare) {
                    Text(stringResource(R.string.share_card))
                }
            }
        }

        if (empty) {
            Text(stringResource(R.string.no_practice_this_day),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@Column
        }

        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if (photo != null) {
                Image(photo, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(96.dp).clip(RoundedCornerShape(12.dp)))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Fact(stringResource(R.string.talks), "${talks.size}")
                // A DAY is a clock (`TalkTime`): 40 seconds of talk must not
                // be reported as "0 min".
                Fact(stringResource(R.string.talk_time), TalkTime.clock(seconds))
                if (shadowed > 0) Fact(stringResource(R.string.shadowing), "$shadowed")
                if (reviewed > 0) Fact(stringResource(R.string.sentences), "$reviewed")
                // The same three kinds the Progress strip stacks, so a day
                // reads the same in both places.
                if (notebookReps > 0) Fact(stringResource(R.string.notebook), "$notebookReps")
            }
        }

        // The day's talks link straight back to each book for review.
        talks.forEach { session ->
            Row(
                Modifier.fillMaxWidth().clickable { onOpenTalk(session.id) }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(session.displayTitle ?: stringResource(R.string.conversation),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f), maxLines = 1)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun Fact(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
    }
}

// MARK: - The record

/**
 * Everything the calendar draws, read once.
 *
 * Three sources, in the order iOS reads them: the METER (`TalkTimeLog`) while
 * it still holds the day, then that day's own frozen card once the meter has
 * pruned it — there is no third definition of a day's talk time. A day with
 * neither can still be ACTIVE: a saved talk or a practice rep says the
 * learner showed up even after the minutes are gone.
 */
private fun readRecord(context: Context, talks: List<Session>): Record {
    val now = System.currentTimeMillis()
    val today = startOfDay(now)
    val metered = TalkTimeLog.recentSeconds(context, TALK_LOG_DAYS, now)
        .associate { (at, secs) -> dayKey(at) to secs }
    val talkDays = talks.map { dayKey(it.endedAt ?: it.startedAt) }.toSet()

    val windowStart = dayBefore(today, TALK_LOG_DAYS - 1)
    val firstTalk = talks.minOfOrNull { it.endedAt ?: it.startedAt }?.let { startOfDay(it) }
    val start = maxOf(minOf(firstTalk ?: windowStart, windowStart),
        dayBefore(today, RECORD_SCAN_DAYS))
    val days = daysFrom(start, today)
    val practice = PracticeLog.recent(context, days.size, now).toMap()

    val seconds = HashMap<String, Int>()
    val active = HashSet<String>()
    var run = 0
    var longest = 0
    days.forEach { day ->
        val key = dayKey(day)
        val secs = metered[key]?.takeIf { it > 0 }
            ?: ((DayCardStore.snapshot(context, day)?.talkMinutes ?: 0) * 60)
        if (secs > 0) {
            seconds[key] = secs
            run += 1
            longest = maxOf(longest, run)
        } else {
            run = 0
        }
        if (secs > 0 || key in talkDays || (practice[key]?.total ?: 0) > 0) active += key
    }

    return Record(
        seconds = seconds,
        active = active,
        // The running streak is read where every other surface reads it, so
        // the flame here and the flame on Practice can never disagree. The
        // longest one can only be as long as the record goes back.
        headline = Headline(
            streak = TalkTimeLog.streakDays(context, now),
            longest = longest,
            totalSeconds = seconds.values.sum(),
            activeDays = active.size,
        ),
    )
}

// MARK: - Calendar arithmetic

private fun cal(at: Long) = Calendar.getInstance().apply { timeInMillis = at }

private fun startOfDay(at: Long): Long = cal(at).apply {
    set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
    set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
}.timeInMillis

private fun startOfMonth(at: Long): Long =
    cal(startOfDay(at)).apply { set(Calendar.DAY_OF_MONTH, 1) }.timeInMillis

private fun startOfYear(at: Long): Long =
    cal(startOfMonth(at)).apply { set(Calendar.DAY_OF_YEAR, 1) }.timeInMillis

private fun shiftMonth(month: Long, by: Int): Long =
    cal(month).apply { add(Calendar.MONTH, by) }.timeInMillis

private fun shift(anchor: Long, period: Period, by: Int): Long = when (period) {
    Period.MONTH -> shiftMonth(anchor, by)
    Period.YEAR -> cal(anchor).apply { add(Calendar.YEAR, by) }.timeInMillis
}

private fun canGoNext(anchor: Long, period: Period): Boolean {
    val now = System.currentTimeMillis()
    return when (period) {
        Period.MONTH -> shiftMonth(anchor, 1) <= startOfMonth(now)
        Period.YEAR -> startOfYear(anchor) < startOfYear(now)
    }
}

/** Whole days back, through the calendar rather than by subtracting millis: an
 * hour is not always an hour on a day the clocks change. */
private fun dayBefore(day: Long, back: Int): Long =
    startOfDay(cal(day).apply { add(Calendar.DAY_OF_YEAR, -back) }.timeInMillis)

private fun daysFrom(start: Long, end: Long): List<Long> {
    val out = ArrayList<Long>()
    var day = startOfDay(start)
    val last = startOfDay(end)
    while (day <= last) {
        out += day
        day = startOfDay(cal(day).apply { add(Calendar.DAY_OF_YEAR, 1) }.timeInMillis)
    }
    return out
}

/** The month's grid, leading blanks included so weekdays line up. */
private fun daysIn(month: Long): List<Long?> {
    val c = cal(startOfMonth(month))
    val lead = c.get(Calendar.DAY_OF_WEEK) - c.firstDayOfWeek
    val leading = if (lead < 0) lead + 7 else lead
    val count = c.getActualMaximum(Calendar.DAY_OF_MONTH)
    val first = startOfMonth(month)
    val days = (0 until count).map {
        startOfDay(cal(first).apply { add(Calendar.DAY_OF_MONTH, it) }.timeInMillis)
    }
    val cells: List<Long?> = List(leading) { null } + days
    val tail = (7 - cells.size % 7) % 7
    return cells + List(tail) { null }
}

private fun monthsOfYear(at: Long): List<Long> {
    val jan = startOfYear(at)
    return (0 until 12).map { shiftMonth(jan, it) }
}

/** Every day the displayed period covers — what the footer counts. */
private fun periodDays(anchor: Long, period: Period): List<Long> = when (period) {
    Period.MONTH -> daysIn(anchor).filterNotNull()
    Period.YEAR -> monthsOfYear(anchor).flatMap { daysIn(it).filterNotNull() }
}

private fun weekdayLabels(): List<String> {
    val fmt = SimpleDateFormat("EEEEE", Locale.getDefault())
    val c = Calendar.getInstance().apply { set(Calendar.DAY_OF_WEEK, firstDayOfWeek) }
    return (0 until 7).map {
        fmt.format(c.time).also { _ -> c.add(Calendar.DAY_OF_YEAR, 1) }
    }
}

private fun dayKey(at: Long) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(at))
private fun dayOfMonth(at: Long) = SimpleDateFormat("d", Locale.US).format(Date(at))
private fun monthLabel(at: Long) =
    SimpleDateFormat("MMMM yyyy", Locale.getDefault()).format(Date(at))
private fun monthShortLabel(at: Long) =
    SimpleDateFormat("MMM", Locale.getDefault()).format(Date(at))
private fun periodTitle(anchor: Long, period: Period) = when (period) {
    Period.MONTH -> monthLabel(anchor)
    Period.YEAR -> SimpleDateFormat("yyyy", Locale.getDefault()).format(Date(anchor))
}
/** A fixed pattern puts the pieces in ENGLISH order ("일요일, 13 9월"); the
 *  skeleton lets each language order them its own way. */
private fun dayTitle(at: Long): String {
    val locale = Locale.getDefault()
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "EEEEdMMMM")
    return SimpleDateFormat(pattern, locale).format(Date(at))
}

/**
 * Seconds → heat bucket, anchored to the ~10-minute daily-goal scale. Takes
 * SECONDS so the first bucket can exist at all: a 40-second talk is a day the
 * learner showed up, and dividing to minutes first erases it. A day that is
 * active with no minutes left to its name (the meter pruned it, but a talk or
 * a rep remembers it) lands in that same faintest bucket.
 */
private fun heatAlpha(seconds: Int): Float = when {
    seconds < 60 -> 0.25f        // talked, but under a minute
    seconds < 5 * 60 -> 0.4f
    seconds < 10 * 60 -> 0.65f
    seconds < 20 * 60 -> 0.85f
    else -> 1.0f
}
