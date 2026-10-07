package com.roro.futurevoice.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircleOutline
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Spellcheck
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.ViewAgenda
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.UILanguage
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DeepLinkInbox
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.WeekInProgress
import com.roro.futurevoice.data.WeekRecap
import com.roro.futurevoice.data.WeekRecapBuilder
import com.roro.futurevoice.data.WeekRecapInbox
import com.roro.futurevoice.data.WeekRecapStore
import com.roro.futurevoice.data.WeeklyTestInbox
import com.roro.futurevoice.data.WeeklyTestSchedule
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.data.WeeklyTestStore
import com.roro.futurevoice.net.WeekRecapCoach
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.ContinuousShape
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

/**
 * "Your week" — the closed week as a deck of cards, swiped through like
 * stories, ending on the week's test (iOS `WeekRecapSheet`, `633418f`).
 *
 * Cards: the week at a glance → talk → what you studied and then SAID →
 * review work → new phrases from the fluent self → what tripped you up →
 * grammar → words → the coach → the test. A card with nothing to say is not
 * dealt, so a quiet week is a short deck, never a row of zeros.
 */
enum class WeekRecapAction { TEST, TALK }

private enum class RecapCard { COVER, TALK, USED, REVIEW, FRESH, STUMBLES, GRAMMAR, WORDS, COACH, TEST }

private val Green = Color(0xFF34C759)
private val Orange = Color(0xFFFF9500)

/** Where the deck's last-card choice goes: the test (Practice opens it) or a
 *  free talk through the same gate the Talk ring uses. */
fun performWeekRecapAction(action: WeekRecapAction) {
    when (action) {
        WeekRecapAction.TEST -> {
            WeeklyTestInbox.pending.value = true
            DeepLinkInbox.pending.value = DeepLinkInbox.Destination.PRACTICE
        }
        WeekRecapAction.TALK -> DeepLinkInbox.widgetRoute.value = DeepLinkInbox.WidgetRoute.FreeTalk
    }
}

private fun nativeLanguage(c: Context): String =
    c.getSharedPreferences("futurevoice", 0).getString("futurevoice.nativeLanguage", null)
        ?: Locale.getDefault().language

/** The deck as a sheet. The chosen action runs once the sheet is gone, so
 *  nothing opens underneath a closing sheet. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeekRecapSheet(recap: WeekRecap, level: CefrLevel, onDismiss: (WeekRecapAction?) -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    ModalBottomSheet(onDismissRequest = { onDismiss(null) }, sheetState = sheet,
        containerColor = AppSurfaces.ground) {
        Box(Modifier.fillMaxHeight(0.94f)) {
            WeekRecapDeck(recap = recap, level = level) { action ->
                scope.launch { sheet.hide() }.invokeOnCompletion { onDismiss(action) }
            }
        }
    }
}

@Composable
fun WeekRecapDeck(
    recap: WeekRecap,
    level: CefrLevel,
    startPage: Int = 0,
    /** Don't call the coach (the capture run's recap is pre-written). */
    writeCoach: Boolean = true,
    onClose: (WeekRecapAction?) -> Unit,
) {
    val context = LocalContext.current
    var current by remember(recap.end) { mutableStateOf(recap) }
    var coachFailed by remember { mutableStateOf(false) }
    var coachAttempt by remember { mutableStateOf(0) }
    var testState by remember { mutableStateOf<WeeklyTestSchedule.State>(WeeklyTestSchedule.State.Ready) }
    val language = remember { LanguageScope.active(context) }

    val cards = buildList {
        val r = current
        add(RecapCard.COVER)
        if (r.talkSeconds > 0 || r.talks.isNotEmpty()) add(RecapCard.TALK)
        if (r.usedCount > 0) add(RecapCard.USED)
        if (r.nowYours.isNotEmpty() || r.sentencesGot.isNotEmpty() || r.shadowTakes + r.scenes > 0) add(RecapCard.REVIEW)
        if (r.newExpressionCount > 0 || r.newCards > 0) add(RecapCard.FRESH)
        if (r.stumbles.isNotEmpty() || r.shakyLines.isNotEmpty() || testMissed(r) > 0) add(RecapCard.STUMBLES)
        // The coach's cards are dealt whether or not its read has landed —
        // they show their own loading state — so the deck never reshuffles.
        if (r.hasActivity) { add(RecapCard.GRAMMAR); add(RecapCard.WORDS) }
        add(RecapCard.COACH)
        add(RecapCard.TEST)
    }
    val pager = rememberPagerState(initialPage = startPage.coerceIn(0, cards.size - 1)) { cards.size }
    val revealed = remember { mutableStateListOf(startPage) }
    LaunchedEffect(pager) {
        snapshotFlow { pager.currentPage }.collect { if (it !in revealed) revealed.add(it) }
    }

    LaunchedEffect(recap.end) {
        // Shown means SEEN: marked here, not where it was raised.
        WeekRecapStore.markShown(context, recap)
        testState = WeeklyTestSettings.schedule(context).state(
            WeeklyTestStore.shared(context).load(language), { WeeklyTestSettings.isThin(context, it) })
        Analytics.capture("week_recap_opened", mapOf("days" to recap.daysActive,
            "talk_min" to recap.talkMinutes, "cards" to cards.size))
    }
    LaunchedEffect(recap.end, coachAttempt) {
        if (!writeCoach || current.coach != null || !current.hasActivity) return@LaunchedEffect
        runCatching {
            WeekRecapCoach.write(context, current, language, level, nativeLanguage(context))
        }.onSuccess { coach ->
            current = current.copy(coach = coach)
            WeekRecapStore.save(context, current)
        }.onFailure { e ->
            coachFailed = true
            Analytics.capture("week_recap_coach_error", mapOf("error" to e.toString().take(160)))
        }
    }
    // One row per viewing, never one per swipe.
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose {
            Analytics.capture("week_recap_closed", mapOf("reached" to ((revealed.maxOrNull() ?: 0) + 1),
                "cards" to cards.size))
        }
    }

    fun finish(action: WeekRecapAction?) {
        if (action != null) Analytics.capture("week_recap_action",
            mapOf("action" to if (action == WeekRecapAction.TEST) "test" else "talk"))
        onClose(action)
    }

    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
        TopBar(current, cards.size, pager.currentPage,
            onSelect = { scope.launch { pager.animateScrollToPage(it) } },
            onClose = { finish(null) })
        HorizontalPager(state = pager, modifier = Modifier.weight(1f)) { index ->
            val shown = index in revealed
            val alpha by animateFloatAsState(if (shown) 1f else 0f, tween(400), label = "recapReveal")
            Box(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 8.dp)
                .background(AppSurfaces.card, ContinuousShape(24.dp))) {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp)
                    .alpha(alpha).offset(y = ((1f - alpha) * 14).dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    val pending: @Composable () -> Unit = {
                        CoachPending(coachFailed) { coachFailed = false; coachAttempt++ }
                    }
                    when (cards[index]) {
                        RecapCard.COVER -> Cover(current)
                        RecapCard.TALK -> TalkCard(current)
                        RecapCard.USED -> UsedCard(current)
                        RecapCard.REVIEW -> ReviewCard(current)
                        RecapCard.FRESH -> FreshCard(current)
                        RecapCard.STUMBLES -> StumblesCard(current)
                        RecapCard.GRAMMAR -> GrammarCard(current, pending)
                        RecapCard.WORDS -> WordsCard(current, pending)
                        RecapCard.COACH -> CoachCard(current, pending)
                        RecapCard.TEST -> { TestCard(testState); ReminderOffer() }
                    }
                }
            }
        }
        // The deck's one button clears the navigation bar wherever the deck is
        // drawn (a sheet, or the capture's full page, where Next sat under it).
        Box(Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 20.dp).padding(bottom = 12.dp, top = 4.dp)) {
            if (cards.getOrNull(pager.currentPage) == RecapCard.TEST) {
                when (testState) {
                    WeeklyTestSchedule.State.Ready ->
                        Primary(stringResource(R.string.wr_start_test)) { finish(WeekRecapAction.TEST) }
                    is WeeklyTestSchedule.State.InProgress ->
                        Primary(stringResource(R.string.wr_continue_test)) { finish(WeekRecapAction.TEST) }
                    is WeeklyTestSchedule.State.Done ->
                        Primary(stringResource(R.string.wr_see_results)) { finish(WeekRecapAction.TEST) }
                    is WeeklyTestSchedule.State.Thin ->
                        Primary(stringResource(R.string.start_a_talk)) { finish(WeekRecapAction.TALK) }
                }
            } else {
                Primary(stringResource(R.string.next)) {
                    scope.launch { pager.animateScrollToPage(minOf(pager.currentPage + 1, cards.size - 1)) }
                }
            }
        }
    }
}

private fun testMissed(r: WeekRecap): Int {
    val score = r.testScore ?: return 0
    val total = r.testTotal ?: return 0
    return total - score
}

// MARK: - Chrome

@Composable
private fun chromeLocale(): Locale {
    val context = LocalContext.current
    return Locale.forLanguageTag(UILanguage.current(context) ?: Locale.getDefault().toLanguageTag())
}

@Composable
private fun TopBar(recap: WeekRecap, count: Int, page: Int, onSelect: (Int) -> Unit, onClose: () -> Unit) {
    val locale = chromeLocale()
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 4.dp, bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Stories-style segments: where you are in the deck, tappable.
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            repeat(count) { i ->
                Box(Modifier.weight(1f).height(3.dp)
                    .background(if (i <= page) MaterialTheme.colorScheme.primary else tertiaryFill(), CircleShape)
                    .clickable { onSelect(i) })
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.wr_your_week), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            // The date gives way, never the close button (at a 1.3 font it
            // pushed the ✕ off the row).
            Text(dateRange(recap, locale), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f))
            Box(Modifier.size(32.dp).background(tertiaryFill(), CircleShape).clickable(onClick = onClose),
                contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun Primary(label: String, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.fillMaxWidth().height(52.dp)) {
        Text(label, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun tertiaryFill() = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f)

@Composable
private fun Kicker(title: String, icon: ImageVector, tint: Color = MaterialTheme.colorScheme.primary) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = tint)
    }
}

@Composable
private fun BigNumber(value: Int, unit: String? = null) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("$value", fontSize = 64.sp, fontWeight = FontWeight.Bold, lineHeight = 64.sp)
        if (unit != null) Text(unit, style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 8.dp))
    }
}

@Composable
private fun Lead(text: String) = Text(text, style = MaterialTheme.typography.titleMedium)

@Composable
private fun Secondary(text: String) =
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)

@Composable
private fun Tile(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(tertiaryFill(), RoundedCornerShape(14.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
}

@Composable
private fun LabelRow(icon: ImageVector, tint: Color = MaterialTheme.colorScheme.primary, content: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp).width(22.dp))
        content()
    }
}

private fun quoted(s: String) = "“$s”"

// MARK: - Cards

@Composable
private fun Cover(r: WeekRecap) {
    val locale = chromeLocale()
    Kicker(stringResource(R.string.wr_last_week), Icons.Filled.CalendarMonth)
    if (r.hasActivity) {
        BigNumber(r.daysActive, stringResource(R.string.wr_of_7_days))
        Lead(stringResource(when (r.daysActive) {
            7 -> R.string.wr_every_day
            5, 6 -> R.string.wr_most_of_week
            3, 4 -> R.string.wr_few_days_in
            else -> R.string.wr_showed_up
        }))
    } else {
        Text(stringResource(R.string.wr_quiet_week), fontSize = 40.sp, fontWeight = FontWeight.Bold, lineHeight = 44.sp)
        Lead(stringResource(R.string.wr_quiet_body))
    }
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        for (i in 0 until 7) {
            val on = r.activeDays.getOrNull(i) == true
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(30.dp).background(if (on) MaterialTheme.colorScheme.primary else tertiaryFill(), CircleShape),
                    contentAlignment = Alignment.Center) {
                    if (on) Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White,
                        modifier = Modifier.size(16.dp))
                }
                Text(weekdayLetter(r.start, i, locale), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    if (r.streak > 1) {
        LabelRow(Icons.Filled.LocalFireDepartment, Orange) {
            Text(stringResource(R.string.lld_day_streak, r.streak), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold, color = Orange)
        }
    }
    if (r.hasActivity) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (r.talkSeconds > 0) LabelRow(Icons.Filled.GraphicEq) {
                Text(pluralStringResource(R.plurals.wr_min_of_talk_talks, r.talks.size, r.talkMinutes, r.talks.size))
            }
            if (r.usedCount > 0) LabelRow(Icons.Filled.Verified) {
                Text(pluralStringResource(R.plurals.wr_things_said, r.usedCount, r.usedCount))
            }
            if (r.nowYours.isNotEmpty()) LabelRow(Icons.Filled.ViewAgenda) {
                Text(pluralStringResource(R.plurals.wr_became_yours, r.nowYours.size, r.nowYours.size))
            }
            if (r.newExpressionCount > 0) LabelRow(Icons.Filled.AutoAwesome) {
                Text(pluralStringResource(R.plurals.wr_new_phrases, r.newExpressionCount, r.newExpressionCount))
            }
        }
    }
}

@Composable
private fun TalkCard(r: WeekRecap) {
    val locale = chromeLocale()
    Kicker(stringResource(R.string.talks), Icons.Filled.GraphicEq)
    BigNumber(r.talkMinutes, stringResource(R.string.wr_min))
    val previous = r.previousTalkSeconds / 60
    if (r.talkMinutes > previous && previous > 0) {
        LabelRow(Icons.AutoMirrored.Filled.TrendingUp, Green) {
            Text(stringResource(R.string.wr_min_more_than_week_before, r.talkMinutes - previous),
                fontWeight = FontWeight.SemiBold, color = Green)
        }
    } else if (previous > 0) {
        Secondary(stringResource(R.string.wr_week_before_min, previous))
    }
    if (r.talks.isNotEmpty()) {
        Column(Modifier.fillMaxWidth().background(tertiaryFill(), RoundedCornerShape(14.dp))
            .padding(horizontal = 12.dp, vertical = 4.dp)) {
            r.talks.take(6).forEachIndexed { i, t ->
                if (i > 0) HorizontalDivider(Modifier.padding(start = 40.dp))
                Row(Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(talkIcon(t.kind), contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp).width(28.dp))
                    Column {
                        Text(t.title.ifBlank { stringResource(R.string.conversation) },
                            style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 2)
                        Text(stringResource(R.string.wr_talk_line_day_min, weekday(t.day, locale), t.minutes),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (r.talks.size > 6) {
                Text(stringResource(R.string.wr_and_more, r.talks.size - 6),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 40.dp, top = 4.dp, bottom = 8.dp))
            }
        }
    }
}

private fun talkIcon(kind: String): ImageVector = when (kind) {
    "person" -> Icons.Filled.Person
    "scenario" -> Icons.Filled.TheaterComedy
    "news" -> Icons.Filled.Newspaper
    else -> Icons.Filled.GraphicEq
}

@Composable
private fun UsedCard(r: WeekRecap) {
    Kicker(stringResource(R.string.you_used_what_you_practiced), Icons.Filled.Verified, Green)
    BigNumber(r.usedCount)
    Lead(stringResource(R.string.wr_studied_then_said))
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        r.used.forEach { e ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(e.item, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Secondary(quoted(e.quote))
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ReviewCard(r: WeekRecap) {
    // Like every card it leads with ONE number, and that number is the count
    // of the list right under it.
    Kicker(stringResource(R.string.practice), Icons.Filled.ViewAgenda)
    if (r.nowYours.isNotEmpty()) {
        BigNumber(r.nowYours.size)
        Lead(stringResource(R.string.wr_became_yours_body))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            r.nowYours.take(12).forEach {
                Text(it, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium,
                    modifier = Modifier.background(tertiaryFill(), CircleShape).padding(horizontal = 12.dp, vertical = 7.dp))
            }
        }
        if (r.nowYours.size > 12) Secondary(stringResource(R.string.wr_plus_more, r.nowYours.size - 12))
    }
    if (r.sentencesGot.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(pluralStringResource(R.plurals.wr_sentences_got, r.sentencesGot.size, r.sentencesGot.size),
                style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            r.sentencesGot.take(3).forEach { line ->
                LabelRow(Icons.Filled.Check, Green) { Text(line, style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
    if (r.shadowTakes > 0 || r.scenes > 0) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (r.shadowTakes > 0) LabelRow(Icons.Filled.RecordVoiceOver) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(pluralStringResource(R.plurals.wr_shadow_takes, r.shadowTakes, r.shadowTakes))
                    r.shadowAverage?.let { avg ->
                        Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.wr_average, avg))
                        val prev = r.previousShadowAverage
                        if (prev != null && avg != prev) {
                            Text(if (avg > prev) "+${avg - prev}" else "${avg - prev}",
                                color = if (avg > prev) Green else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            if (r.scenes > 0) LabelRow(Icons.Filled.PlayCircle) {
                Text(pluralStringResource(R.plurals.wr_scenes_watched, r.scenes, r.scenes))
            }
        }
    }
}

@Composable
private fun FreshCard(r: WeekRecap) {
    Kicker(stringResource(R.string.wr_new_from_fluent), Icons.Filled.AutoAwesome)
    if (r.newExpressionCount > 0) {
        BigNumber(r.newExpressionCount)
        Lead(stringResource(R.string.wr_things_fluent_said))
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            r.newExpressions.forEach { e ->
                Tile {
                    Text(e.item, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    if (e.quote.isNotEmpty()) Secondary(quoted(e.quote))
                }
            }
        }
        Secondary(stringResource(R.string.wr_waiting_in_expressions))
    }
    if (r.newCards > 0) LabelRow(Icons.Filled.LibraryAdd) {
        Text(pluralStringResource(R.plurals.wr_new_cards, r.newCards, r.newCards), fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun StumblesCard(r: WeekRecap) {
    Kicker(stringResource(R.string.wr_where_stuck), Icons.Filled.Autorenew, Orange)
    if (r.stumbles.isNotEmpty()) {
        Lead(stringResource(R.string.wr_same_fix_back))
        r.stumbles.forEach { s ->
            Tile {
                Text(s.was, textDecoration = TextDecoration.LineThrough, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(s.now, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f))
                    Text("×${s.count}", fontWeight = FontWeight.SemiBold, color = Orange)
                }
            }
        }
    } else if (r.shakyLines.isNotEmpty()) {
        Lead(stringResource(R.string.wr_shaky_lines))
        r.shakyLines.forEach { s ->
            Tile {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(s.now, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f))
                    Text("${s.count}", fontWeight = FontWeight.SemiBold, color = Orange)
                }
            }
        }
    }
    val missed = testMissed(r)
    if (missed > 0) LabelRow(Icons.Filled.Checklist, MaterialTheme.colorScheme.onSurfaceVariant) {
        Secondary(pluralStringResource(R.plurals.wr_last_test_missed, missed, r.testScore ?: 0, r.testTotal ?: 0, missed))
    }
}

@Composable
private fun GrammarCard(r: WeekRecap, pending: @Composable () -> Unit) {
    Kicker(stringResource(R.string.wr_grammar_title), Icons.Filled.Spellcheck, Orange)
    val c = r.coach ?: return pending()
    if (c.grammar.isEmpty()) { Lead(stringResource(R.string.wr_no_grammar)); return }
    Lead(stringResource(R.string.wr_same_point))
    c.grammar.forEach { p ->
        Tile {
            Text(p.rule, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            p.examples.forEach { e ->
                Column(Modifier.padding(top = 4.dp)) {
                    Text(e.was, textDecoration = TextDecoration.LineThrough,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                    Text(e.now, fontWeight = FontWeight.Medium, style = MaterialTheme.typography.bodyMedium)
                }
            }
            if (p.tip.isNotEmpty()) Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Lightbulb, contentDescription = null, tint = Orange, modifier = Modifier.size(18.dp))
                Text(p.tip, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun WordsCard(r: WeekRecap, pending: @Composable () -> Unit) {
    Kicker(stringResource(R.string.wr_words_level_up), Icons.Filled.ArrowCircleUp)
    val c = r.coach ?: return pending()
    if (c.upgrades.isEmpty()) { Lead(stringResource(R.string.wr_no_word)); return }
    Lead(stringResource(R.string.wr_words_leaned_on))
    c.upgrades.forEach { u ->
        Tile {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(u.instead, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("×${u.count}", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                Text(u.better, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
            if (u.rewritten.isNotEmpty()) {
                Secondary(quoted(u.original))
                Text(quoted(u.rewritten), style = MaterialTheme.typography.bodyMedium)
            }
            if (u.note.isNotEmpty()) Text(u.note, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun CoachCard(r: WeekRecap, pending: @Composable () -> Unit) {
    Kicker(stringResource(R.string.wr_from_coach), Icons.Filled.FormatQuote)
    val c = r.coach
    when {
        c != null -> {
            Text(c.headline, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            if (c.insight.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.wr_how_you_speak), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(c.insight, style = MaterialTheme.typography.bodyLarge)
                    if (c.insightQuote.isNotEmpty()) Secondary(quoted(c.insightQuote))
                }
            }
            if (c.plan.isNotEmpty()) PlanBox(c.plan)
        }
        r.hasActivity -> pending()
        else -> {
            Lead(stringResource(R.string.wr_new_week_start_small))
            PlanBox(listOf(fallbackFocus(r)))
        }
    }
}

/** Written in code when the coach can't be — from the same evidence. */
@Composable
private fun fallbackFocus(r: WeekRecap): String {
    r.stumbles.firstOrNull()?.let { return stringResource(R.string.wr_say_in_next_talk, it.now) }
    r.newExpressions.firstOrNull()?.let { return stringResource(R.string.wr_try_in_next_talk, it.item) }
    r.shakyLines.firstOrNull()?.let { return stringResource(R.string.wr_shadow_once_more, it.now) }
    return stringResource(R.string.wr_one_talk_plan)
}

@Composable
private fun PlanBox(items: List<String>) {
    val accent = MaterialTheme.colorScheme.primary
    Column(Modifier.fillMaxWidth().background(accent.copy(alpha = 0.12f), RoundedCornerShape(16.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.wr_this_week), style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold, color = accent)
        items.forEachIndexed { i, item ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("${i + 1}", fontWeight = FontWeight.Bold, color = accent)
                Text(item, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            }
        }
    }
}

/** The coach's read hasn't landed: waiting, or failed with a way back. */
@Composable
private fun CoachPending(failed: Boolean, onRetry: () -> Unit) {
    if (failed) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Lead(stringResource(R.string.wr_coach_failed))
            OutlinedButton(onClick = onRetry) {
                Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.try_again))
            }
        }
    } else {
        Row(Modifier.padding(vertical = 20.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            Secondary(stringResource(R.string.wr_reading))
        }
    }
}

@Composable
private fun TestCard(state: WeeklyTestSchedule.State) {
    Kicker(stringResource(R.string.wr_this_weeks_test), Icons.Filled.Checklist)
    Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.CheckCircleOutline, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(72.dp))
    }
    Lead(when (state) {
        WeeklyTestSchedule.State.Ready -> stringResource(R.string.wr_test_ready_body)
        is WeeklyTestSchedule.State.InProgress ->
            stringResource(R.string.wr_test_in_progress, state.test.answers.size, state.test.total)
        is WeeklyTestSchedule.State.Done -> stringResource(R.string.wr_test_done, state.test.score, state.test.total)
        is WeeklyTestSchedule.State.Thin -> stringResource(R.string.wr_test_thin)
    })
}

/**
 * The deck slides up by itself only when the app is opened; the notice is
 * what reaches someone who doesn't. Offered here, once the learner has seen
 * what the notice would bring — never as a cold permission prompt (iOS
 * `reminderOffer`). Only while the reminder is off and the phone could still
 * ring: a refusal the system won't ask about again leaves the offer gone.
 */
@Composable
private fun ReminderOffer() {
    val context = LocalContext.current
    fun canAsk(): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled() ||
            (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
    var offer by remember { mutableStateOf(!WeeklyTestSettings.reminderOn(context) && canAsk()) }
    var justOn by remember { mutableStateOf(false) }
    fun settle(granted: Boolean) {
        val on = granted && NotificationManagerCompat.from(context).areNotificationsEnabled()
        WeeklyTestSettings.setReminderOn(context, on)     // re-arms the alarm
        justOn = on
        offer = false
        Analytics.capture("week_recap_reminder", mapOf("on" to on))
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission(), ::settle)
    when {
        justOn -> Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.Notifications, contentDescription = null, modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Secondary(stringResource(R.string.wr_next_week_arrives,
                weekReadyDate(WeeklyTestSettings.schedule(context).nextOpening(), weekLocale(context))))
        }
        offer -> OutlinedButton(onClick = {
            val needsAsk = Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            if (needsAsk) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else settle(true)
        }) {
            Icon(Icons.Filled.NotificationsNone, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.wr_tell_me_next_week))
        }
    }
}

// MARK: - Helpers

private fun weekday(at: Long, locale: Locale): String =
    Instant.ofEpochMilli(at).atZone(ZoneId.systemDefault()).dayOfWeek.getDisplayName(TextStyle.SHORT, locale)

private fun weekdayLetter(start: Long, offset: Int, locale: Locale): String =
    Instant.ofEpochMilli(start).atZone(ZoneId.systemDefault()).plusDays(offset.toLong())
        .dayOfWeek.getDisplayName(TextStyle.NARROW_STANDALONE, locale)

private fun dateRange(r: WeekRecap, locale: Locale): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd")
    val f = java.time.format.DateTimeFormatter.ofPattern(pattern, locale)
    val zone = ZoneId.systemDefault()
    // Seven days, as in the archive.
    return "${f.format(Instant.ofEpochMilli(r.start).atZone(zone))} – ${f.format(Instant.ofEpochMilli(r.end - 86_400_000L).atZone(zone))}"
}

// MARK: - Practice row

/**
 * "Your week" on the Today card (iOS `weekRecapRow`, 2026-10-03): the week IN
 * PROGRESS ("ready Sat, Oct 10") — its deck arrives when it closes — and a tap
 * opens the archive of every closed week behind it. Drawn once the week has
 * something in it, or there is a past week to look back on.
 */
@Composable
fun WeekRecapRow(level: CefrLevel, reloadKey: Any?) {
    val context = LocalContext.current
    var week by remember { mutableStateOf<WeekInProgress?>(null) }
    var hasPastWeeks by remember { mutableStateOf(false) }
    var showing by remember { mutableStateOf(false) }
    var reload by remember { mutableStateOf(0) }
    val asked by WeekRecapInbox.archive.collectAsStateWithLifecycle()
    LaunchedEffect(reloadKey, reload) {
        WeekRecapStore.lastWeek(context)        // freezes the closed week
        week = WeekRecapBuilder.thisWeek(context)
        hasPastWeeks = WeekRecapStore.archive(context).isNotEmpty()
    }
    // A notice tapped for a week already seen lands here.
    LaunchedEffect(asked) {
        if (asked) { WeekRecapInbox.archive.value = false; showing = true }
    }
    val w = week
    if (w != null && (w.hasActivity || hasPastWeeks)) {
        Row(Modifier.fillMaxWidth().clickable { showing = true }.padding(horizontal = 14.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.ViewAgenda, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp))
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.wr_your_week), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium)
                Text(stringResource(R.string.wr_week_in_progress_ready, weekReadyDate(w.readyAt, weekLocale(context))),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
        }
    }
    if (showing) {
        WeekRecapArchiveSheet(level) { action ->
            showing = false
            reload++
            action?.let(::performWeekRecapAction)
        }
    }
}

// MARK: - Root host

/**
 * Raises the closed week's cards — softly, a beat after the app is up, and
 * never over a call or another sheet (iOS `RootTabView.offerWeekRecap`).
 * Unasked it appears once per week and only for a week that had something in
 * it. The notice shares that one showing: tapped after the deck was seen, it
 * opens the archive instead.
 */
@Composable
fun WeekRecapHost(ready: Boolean, blocked: Boolean, level: CefrLevel) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val asked by WeekRecapInbox.asked.collectAsStateWithLifecycle()
    val debug by WeekRecapInbox.debug.collectAsStateWithLifecycle()
    val reoffer by WeekRecapInbox.reoffer.collectAsStateWithLifecycle()
    var showing by remember { mutableStateOf<WeekRecap?>(null) }
    var resumes by remember { mutableStateOf(0) }
    val stillBlocked by androidx.compose.runtime.rememberUpdatedState(blocked)
    // Every return to the foreground is a chance the week has turned.
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { resumes++ }
    }
    LaunchedEffect(ready, asked, resumes, reoffer) {
        if (!ready || showing != null) return@LaunchedEffect
        val wasAsked = asked
        WeekRecapInbox.asked.value = false
        delay(if (wasAsked) 400 else 1_200)
        val recap = WeekRecapStore.lastWeek(context)
        // The notice and the automatic slide-up share ONE showing: a notice
        // tapped after the deck was already seen opens the archive on
        // Practice, not the same deck again (iOS `offerWeekRecap`).
        if (wasAsked && WeekRecapStore.wasShown(context, recap)) {
            WeekRecapInbox.archive.value = true
            DeepLinkInbox.pending.value = DeepLinkInbox.Destination.PRACTICE
            return@LaunchedEffect
        }
        if (!wasAsked && (!recap.hasActivity || WeekRecapStore.wasShown(context, recap))) return@LaunchedEffect
        if (showing != null || stillBlocked) return@LaunchedEffect
        showing = recap
    }
    LaunchedEffect(debug) {
        val recap = debug ?: return@LaunchedEffect
        WeekRecapInbox.debug.value = null
        showing = recap
    }
    showing?.let {
        WeekRecapSheet(it, level) { action ->
            showing = null
            action?.let(::performWeekRecapAction)
        }
    }
}
