package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.CoreClubColor
import com.roro.futurevoice.ui.brand.CoreSeal
import com.roro.futurevoice.ui.brand.FutureselfTheme
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

/**
 * iOS `CoreClubView`, pushed from Me — the Core, from wherever the learner
 * stands.
 *
 * It opens on the ROOM (a hundred seats, filled ones in their member's own
 * colour), then the learner's own standing, then the rules as points, then
 * what a seat gets you. One order for everyone, because the person opening
 * this — member or not — opens it to find out where they are.
 *
 * NUMBERS, NOT A PICTURE of the days: a thirty-day grid was retired on iOS
 * (it scored a month already spent and couldn't say which absence was
 * forgiven). The room is the only picture; the progress is the number.
 *
 * Never add a perk row, and never a line explaining why there isn't one.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CoreClubPage(language: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var progress by remember { mutableStateOf<CoreClubClient.Progress?>(null) }
    var seatMap by remember { mutableStateOf<CoreClubClient.SeatMap?>(null) }
    var loading by remember { mutableStateOf(true) }
    var refreshing by remember { mutableStateOf(false) }

    suspend fun load() {
        val client = CoreClubClient(AuthRepository())
        // Two calls, one screen, concurrent so the grid isn't waiting behind
        // a month of activity.
        kotlinx.coroutines.coroutineScope {
            val p = async { client.progress(language) }
            val m = async { client.seatMap(language) }
            progress = p.await(); seatMap = m.await()
        }
        loading = false
    }
    LaunchedEffect(language) {
        // So this member's seat wears the palette they picked (iOS publishes
        // it on every foreground).
        CoreClubClient(AuthRepository()).publishTheme(FutureselfTheme.stored(context).ordinal)
        load()
    }

    Scaffold(
        contentWindowInsets = fieldScaffoldInsets,
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { com.roro.futurevoice.ui.brand.IosNavTitle(stringResource(R.string.the_core)) },
                navigationIcon = { com.roro.futurevoice.ui.brand.IosBackButton(onBack) },
            )
        }
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { scope.launch { refreshing = true; load(); refreshing = false } },
            modifier = Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground),
        ) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 32.dp),
            ) {
                val p = progress
                when {
                    p != null -> {
                        RoomSection(seatMap)
                        StandingSection(p)
                        HowItWorksSection(p)
                        WhatYouGetSection()
                    }
                    loading -> GroupedCard {
                        Box(Modifier.fillMaxWidth().heightIn(min = 48.dp),
                            contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        }
                    }
                    else -> GroupedCard {
                        Text(stringResource(R.string.the_core_is_unavailable_right_now),
                            Modifier.padding(horizontal = 16.dp, vertical = 13.dp),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

// ── The room ───────────────────────────────────────────────────────────────

/** A hundred cells, drawn before a single number is spoken. */
@Composable
private fun RoomSection(map: CoreClubClient.SeatMap?) {
    GroupedCard {
        CoreSeatGrid(map, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
    }
    if (map != null) {
        Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
            GroupedFooter(stringResource(R.string.lld_of_lld_seats_taken, map.taken, map.seats))
            GroupedFooter(stringResource(
                if (map.mine != null) R.string.the_outlined_cell_is_you
                else R.string.each_filled_cell_is_a_member_in_the_colour_they_chose))
        }
    }
}

/**
 * The hundred seats as a hundred PIXELS — one square block, ten by ten,
 * butted 2 dp apart so they read as one surface made of people, oldest
 * first from the top-left. A filled pixel wears its member's own palette
 * (the one screen exempt from "system colours only"), empty ones are drawn,
 * and your own is outlined in place, never recoloured or pulled out.
 */
@Composable
fun CoreSeatGrid(map: CoreClubClient.SeatMap?, modifier: Modifier = Modifier) {
    val seats = map?.seats ?: 100
    val columns = 10
    val empty = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.14f)
    val ink = MaterialTheme.colorScheme.onSurface
    val neutral = MaterialTheme.colorScheme.onSurfaceVariant
    // Resolved here: `tint()` is composable, the cells below are plain draws.
    val tints = FutureselfTheme.entries.map { it.tint() }
    val shape = RoundedCornerShape(2.dp)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        for (row in 0 until (seats + columns - 1) / columns) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                for (col in 0 until columns) {
                    val i = row * columns + col
                    if (i >= seats) { Box(Modifier.weight(1f)); continue }
                    val theme = map?.themes?.getOrNull(i)
                    // A palette shipped after this build is drawn as taken,
                    // in a neutral tone, never as empty.
                    val color: Color = when {
                        theme == null -> empty
                        else -> tints.getOrNull(theme) ?: neutral
                    }
                    Box(
                        Modifier.weight(1f).aspectRatio(1f).background(color, shape)
                            .then(if (map?.mine == i) Modifier.border(2.dp, ink, shape) else Modifier)
                    )
                }
            }
        }
    }
}

// ── Where you stand ────────────────────────────────────────────────────────

/** The learner's own standing, whole, in one section: one lead that varies
 *  by state, then the same handful of named numbers for everybody. */
@Composable
private fun StandingSection(p: CoreClubClient.Progress) {
    GroupedSectionHeader(stringResource(R.string.where_you_stand))
    GroupedCard {
        val lead = standingLead(p)
        if (lead) TextRowDivider()
        // The one number that answers "what do I do today", in every state.
        LabeledRow(stringResource(R.string.current_streak), "${p.streak}")
        val m = p.member
        if (m != null) {
            if (m.seated) {
                TextRowDivider()
                LabeledRow(stringResource(R.string.days_in_the_core), "${m.days_total}")
                TextRowDivider()
                // A cushion, not a threat: "0 / 1".
                LabeledRow(stringResource(R.string.missed_this_month),
                    "${p.missed_recent} / ${p.keep_grace}")
            } else p.queue_ahead?.let { ahead ->
                TextRowDivider()
                LabeledRow(stringResource(R.string.people_ahead_of_you), "$ahead")
            }
        }
    }
    // No footer: naming Watch here is what plants the idea that it might count.
}

/** The line that differs by state. Returns whether anything was drawn. */
@Composable
private fun standingLead(p: CoreClubClient.Progress): Boolean {
    val m = p.member
    when {
        m != null && m.seated -> { CoreSealRow(); return true }
        m != null -> {
            // No seal for the seatless: what they need is the way back.
            if (p.waiting_for_seat) {
                Footnote(stringResource(
                    if (p.club_size < p.seats) R.string.you_re_in_line_and_there_s_room_you_take_a_seat_tonight
                    else R.string.you_re_in_line_a_seat_opens_when_someone_stops))
                return true
            }
            val back = p.days_to_return ?: return false
            BigNumber(back, stringResource(R.string.days_to_return))
            if (p.requalifying) {
                // Its own row under the number, as in iOS's List.
                TextRowDivider()
                Footnote(stringResource(
                    R.string.you_ve_been_away_a_while_so_the_full_streak_counts_again))
            }
            return true
        }
        else -> {
            val togo = p.days_to_entry ?: return false
            if (togo == 0) {
                // Streak complete, settlement not yet run — the one moment
                // this screen gets to be pleased.
                Footnote(stringResource(R.string.you_ve_done_the_lld_days_you_join_the_line_tonight,
                    p.entry_streak))
            } else BigNumber(togo, stringResource(R.string.days_to_go))
            return true
        }
    }
}

/** The seal with the word for it — only ever for a member who is in. */
@Composable
private fun CoreSealRow() {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        CoreSeal(size = 18.dp)
        Text(stringResource(R.string.in_the_core), style = MaterialTheme.typography.bodyLarge,
            color = CoreClubColor)
    }
}

@Composable
private fun BigNumber(value: Int, label: String) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)) {
        // iOS `.largeTitle`, rounded design, semibold.
        Text("$value", style = MaterialTheme.typography.headlineLarge.copy(
            fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.SansSerif, fontSize = 34.sp),
            color = CoreClubColor)
        Text(label, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Footnote(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** iOS `LabeledContent`: the name in ink, the number trailing in grey. */
@Composable
private fun LabeledRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(value, style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Between text-only rows: inset to the text, as iOS insets past content. */
@Composable
private fun TextRowDivider() {
    HorizontalDivider(Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outlineVariant)
}

// ── The rules, as points ───────────────────────────────────────────────────

/** Every rule, once each — a point can't hedge. */
@Composable
private fun HowItWorksSection(p: CoreClubClient.Progress) {
    GroupedSectionHeader(stringResource(R.string.how_it_works))
    GroupedCard {
        listOf(
            stringResource(R.string.talk_lld_minutes_a_day_lld_days_in_a_row,
                p.bar_seconds / 60, p.entry_streak),
            stringResource(R.string.miss_a_day_and_the_count_starts_again_at_zero),
            stringResource(R.string.finishing_puts_you_in_line_it_doesn_t_seat_you),
            stringResource(
                R.string.lld_seats_one_opens_only_when_the_person_in_it_stops_never_b_60a60d,
                p.seats),
            stringResource(R.string.whoever_qualified_first_takes_it),
            stringResource(R.string.once_you_re_in_one_missed_day_a_month_is_forgiven),
        ).forEachIndexed { i, rule ->
            if (i > 0) TextRowDivider()
            Text(rule, Modifier.fillMaxWidth().heightIn(min = 48.dp)
                .padding(horizontal = 16.dp, vertical = 11.dp),
                style = MaterialTheme.typography.bodyLarge)
        }
    }
}

/** What being in it gets you — the badge, where strangers see it. */
@Composable
private fun WhatYouGetSection() {
    GroupedSectionHeader(stringResource(R.string.what_you_get))
    GroupedCard {
        MeRow(icon = null,
            title = stringResource(R.string.a_badge_next_to_your_name_where_you_meet_people),
            kind = MeRowKind.PLAIN, leading = { CoreSeal(size = 18.dp) })
    }
    GroupedFooter(stringResource(
        R.string.it_s_there_while_you_re_in_the_core_and_it_s_a_promise_to_yo_970f83))
}
