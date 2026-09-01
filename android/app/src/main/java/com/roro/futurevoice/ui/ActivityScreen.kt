package com.roro.futurevoice.ui

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AppUsageLog
import com.roro.futurevoice.data.DayCardStore
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DayCardData
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * The record: a month at a time, and what each day was.
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
    var month by remember { mutableStateOf(startOfMonth(System.currentTimeMillis())) }
    var selected by remember { mutableStateOf(startOfDay(System.currentTimeMillis())) }
    // SECONDS, not minutes. A talk under a minute rounds to zero, and that
    // day would then be indistinguishable from one nobody opened the app on —
    // which is exactly the day the wall exists to show.
    var secondsByDay by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var sessions by remember { mutableStateOf<List<Session>>(emptyList()) }
    var photos by remember { mutableStateOf<Map<String, ImageBitmap>>(emptyMap()) }
    var showCard by remember { mutableStateOf(false) }

    LaunchedEffect(language, month) {
        secondsByDay = TalkTimeLog.recentSeconds(context, 45)
            .associate { (at, secs) -> dayKey(at) to secs }
        sessions = SessionStore.shared(context).load(language)
        // Only the days on screen: loading a photo is a decode, and a year of
        // them to draw one month would be paid on every arrow tap.
        photos = daysIn(month).filterNotNull().mapNotNull { day ->
            DayCardStore.photo(context, day)?.let { dayKey(day) to it.asImageBitmap() }
        }.toMap()
    }

    val daySessions = sessions.filter {
        dayKey(it.endedAt ?: it.startedAt) == dayKey(selected)
    }

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
            item {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { month = shiftMonth(month, -1) }) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = null)
                    }
                    Text(monthLabel(month), style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f))
                    IconButton(
                        onClick = { month = shiftMonth(month, 1) },
                        enabled = shiftMonth(month, 1) <= startOfMonth(System.currentTimeMillis()),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
                    }
                }
            }

            item {
                MonthWall(
                    month = month,
                    secondsByDay = secondsByDay,
                    photos = photos,
                    selected = selected,
                    onSelect = { selected = it },
                )
            }

            item {
                DaySummary(
                    day = selected,
                    minutes = (secondsByDay[dayKey(selected)] ?: 0) / 60,
                    talks = daySessions,
                    log = PracticeLog.day(context, selected),
                    photo = photos[dayKey(selected)],
                    onShare = { showCard = true },
                    onOpenTalk = onOpenTalk,
                )
            }
        }
    }

    if (showCard) {
        val data = remember(selected, secondsByDay, daySessions) {
            DayCardStore.snapshot(context, selected) ?: DayCardData(
                date = selected,
                talkMinutes = (secondsByDay[dayKey(selected)] ?: 0) / 60,
                // Never less than the talk figure: a call in a pocket is
                // metered but not foregrounded.
                studyMinutes = maxOf(AppUsageLog.secondsOn(context, selected) / 60,
                    (secondsByDay[dayKey(selected)] ?: 0) / 60),
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

/**
 * The month as a photo wall. Six rows of seven full-width square tiles: a
 * photo day shows its photo, an active day its heat blue, an empty day a
 * faint fill — so the month reads as one surface rather than a field of dots.
 */
@Composable
private fun MonthWall(
    month: Long,
    secondsByDay: Map<String, Int>,
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
                        val heat = heatAlpha(seconds)
                        Box(
                            Modifier.weight(1f).aspectRatio(1f)
                                .clip(RoundedCornerShape(9.dp))
                                .background(
                                    if (seconds > 0) accent.copy(alpha = heat)
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
                                color = if (photo != null || heat >= 0.6f) Color.White
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
 * What the selected day was, with its card at the top. The card already
 * prints the day's minutes, so the facts beside it fill the half of the row
 * a thumbnail would otherwise leave empty rather than repeating the number.
 */
@Composable
private fun DaySummary(
    day: Long,
    minutes: Int,
    talks: List<Session>,
    log: PracticeLog.Day?,
    photo: ImageBitmap?,
    onShare: () -> Unit,
    onOpenTalk: (String) -> Unit,
) {
    val shadowed = log?.shadowReps ?: 0
    val reviewed = log?.drillReps ?: 0
    val notebookReps = (log?.wordReps ?: 0) + (log?.expressionReps ?: 0)
    val empty = minutes == 0 && talks.isEmpty() && shadowed == 0 && reviewed == 0 &&
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
                Fact(stringResource(R.string.talk_time), "$minutes min")
                if (shadowed > 0) Fact(stringResource(R.string.shadowing), "$shadowed")
                if (reviewed > 0) Fact(stringResource(R.string.sentences), "$reviewed")
                // The same three kinds the Progress strip stacks, so a day
                // reads the same in both places.
                val notebook = (log?.wordReps ?: 0) + (log?.expressionReps ?: 0)
                if (notebook > 0) Fact(stringResource(R.string.notebook), "$notebook")
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

// MARK: - Calendar arithmetic

private fun cal(at: Long) = Calendar.getInstance().apply { timeInMillis = at }

private fun startOfDay(at: Long): Long = cal(at).apply {
    set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
    set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
}.timeInMillis

private fun startOfMonth(at: Long): Long =
    cal(startOfDay(at)).apply { set(Calendar.DAY_OF_MONTH, 1) }.timeInMillis

private fun shiftMonth(month: Long, by: Int): Long =
    cal(month).apply { add(Calendar.MONTH, by) }.timeInMillis

/** The month's grid, leading blanks included so weekdays line up. */
private fun daysIn(month: Long): List<Long?> {
    val c = cal(month)
    val lead = c.get(Calendar.DAY_OF_WEEK) - c.firstDayOfWeek
    val leading = if (lead < 0) lead + 7 else lead
    val count = c.getActualMaximum(Calendar.DAY_OF_MONTH)
    val days = (0 until count).map { cal(month).apply { add(Calendar.DAY_OF_MONTH, it) }.timeInMillis }
    val cells: List<Long?> = List(leading) { null } + days
    val tail = (7 - cells.size % 7) % 7
    return cells + List(tail) { null }
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
private fun dayTitle(at: Long) =
    SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(Date(at))

/**
 * Seconds → heat bucket, anchored to the ~10-minute daily-goal scale. Takes
 * SECONDS so the first bucket can exist at all: a 40-second talk is a day the
 * learner showed up, and dividing to minutes first erases it.
 */
private fun heatAlpha(seconds: Int): Float = when {
    seconds < 60 -> 0.25f        // talked, but under a minute
    seconds < 5 * 60 -> 0.4f
    seconds < 10 * 60 -> 0.65f
    seconds < 20 * 60 -> 0.85f
    else -> 1.0f
}
