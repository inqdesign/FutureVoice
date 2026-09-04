package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Repeat
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.renewalLabel
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * "What uses talk time?" — the transparency page. The rules here MUST stay in
 * sync with the server (talk-tick + elevenlabs-tts routing): a mismatch
 * between what we show and what we meter is a trust-breaker.
 *
 * The model in one line: talk minutes are spent by the in-call clock and by
 * NOTHING else; Watch has its own separate pool of scenes; both are monthly
 * and neither has a daily limit. Everything else — review, browsing, tapping
 * around — is free.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreditGuideScreen(onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    var account by remember { mutableStateOf<AccountStatus?>(null) }
    LaunchedEffect(Unit) { account = AccountStatus.load(AuthRepository()) }
    val locale = LocalConfiguration.current.locales[0]

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.what_uses_talk_time)) },
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
                .padding(horizontal = 16.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // The pool sits FIRST: it is the shape of the whole plan, and the
            // question that actually brings people here is "what am I allowed
            // to do?" before "what does it cost me?".
            //
            // Gated on the SCENE cap, not the talk one: Plus has no talk cap,
            // and gating on it made this whole section vanish for the tier
            // whose shape most needs explaining.
            account?.takeIf { it.monthlyScenesCap != null }?.let { a ->
                SectionHeader(stringResource(R.string.what_your_plan_holds))
                GuideCard {
                    PlainRow(
                        icon = Icons.Filled.CalendarMonth,
                        title = a.monthlyCapSeconds?.let {
                            stringResource(R.string.lld_minutes_a_month, it / 60)
                        } ?: stringResource(R.string.talk_as_much_as_you_want),
                        // States the rule POSITIVELY and stops. Talking is
                        // genuinely uncapped on Plus, and the honest reason is
                        // worth saying out loud — speaking is its own limit,
                        // which is exactly what watching is not.
                        detail = if (a.monthlyCapSeconds == null)
                            stringResource(R.string.no_limit_and_no_rationing_talking_takes_real_effort_so_there_9058ba)
                        else stringResource(R.string.use_them_however_you_like_all_in_one_call_today_or_spread_ov_1df811),
                    )
                    a.monthlyScenesCap?.let { scenes ->
                        RowDivider()
                        PlainRow(
                            icon = Icons.Filled.PlayCircle,
                            title = stringResource(R.string.lld_watch_scenes_a_month, scenes),
                            detail = stringResource(R.string.a_separate_pool_watching_a_scene_never_takes_a_minute_off_yo_ed6523),
                        )
                    }
                }
                // A cancelled plan refills nothing — the same date, the
                // opposite promise.
                val renews = a.renewalLabel(locale)
                Footer(when {
                    renews.isEmpty() -> stringResource(R.string.scenes_refill_at_the_start_of_each_billing_period)
                    a.cancelAtPeriodEnd -> stringResource(R.string.your_plan_ends_on_lld, renews)
                    else -> stringResource(R.string.scenes_refill_on, renews)
                })
            }

            SectionHeader(stringResource(R.string.uses_talk_time))
            GuideCard {
                CostRow(Icons.Filled.Phone, stringResource(R.string.talking),
                    stringResource(R.string.clock_time),
                    stringResource(R.string.the_call_clock_is_the_meter_a_10_minute_call_uses_10_minutes_6bb450))
                RowDivider()
                CostRow(Icons.Filled.RecordVoiceOver,
                    stringResource(R.string.re_cloning_your_voice),
                    stringResource(R.string.s_1_min),
                    stringResource(R.string.setup_is_free_including_re_records_in_the_first_day_later_re_d175df))
            }
            Footer(stringResource(R.string.only_the_call_clock_spends_your_talk_minutes_watching_a_scen_d6c32d))

            SectionHeader(stringResource(R.string.watch_scenes))
            GuideCard {
                CostRow(Icons.Filled.PlayCircle, stringResource(R.string.watching_a_scene),
                    stringResource(R.string.s_1_scene),
                    stringResource(R.string.watch_has_its_own_pool_separate_from_your_talk_minutes_a_sce_98932d))
            }
            Footer(stringResource(R.string.scenes_you_ve_already_watched_replay_free_forever_and_never_d6d2d2))

            SectionHeader(stringResource(R.string.always_free))
            GuideCard {
                FreeRow(Icons.Filled.Layers, stringResource(R.string.all_reviewing),
                    stringResource(R.string.drills_shadowing_including_coach_feedback_word_and_expressio_1d0899))
                RowDivider()
                FreeRow(Icons.Filled.Repeat, stringResource(R.string.replays),
                    stringResource(R.string.anything_already_synthesized_is_cached_loop_it_slow_it_down_fed756))
                RowDivider()
                FreeRow(Icons.Filled.AutoAwesome, stringResource(R.string.summaries_reports),
                    stringResource(R.string.session_scorecards_weekly_reports_and_the_daily_call_are_on_1c6cf8))
                RowDivider()
                FreeRow(Icons.Filled.GridView, stringResource(R.string.exploring),
                    stringResource(R.string.building_situations_browsing_topics_translations_dictionarie_456d7f))
                RowDivider()
                FreeRow(Icons.AutoMirrored.Filled.MenuBook,
                    stringResource(R.string.vocabulary_progress),
                    stringResource(R.string.the_word_cloud_cefr_estimate_and_stats_never_cost_anything))
            }
            Footer(stringResource(R.string.in_short_minutes_buy_speaking_time_with_your_fluent_self_pra_828cac))
        }
    }
}

/** One grouped section's card — the inset-grouped list iOS draws. */
@Composable
private fun GuideCard(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, RoundedCornerShape(12.dp))
            .padding(vertical = 4.dp),
    ) { content() }
}

@Composable
private fun RowDivider() {
    androidx.compose.material3.HorizontalDivider(
        Modifier.padding(start = 52.dp), color = MaterialTheme.colorScheme.outlineVariant)
}

@Composable
private fun SectionHeader(text: String) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 4.dp, top = 20.dp, bottom = 6.dp))
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 4.dp, top = 6.dp))
}

@Composable
private fun CostRow(icon: ImageVector, title: String, cost: String, detail: String) {
    GuideRow(icon, MaterialTheme.colorScheme.primary, title, detail) {
        Text(cost, style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
    }
}

/** A rule with no price attached — no trailing tag, because there is no
 *  number to put there. */
@Composable
private fun PlainRow(icon: ImageVector, title: String, detail: String) {
    GuideRow(icon, MaterialTheme.colorScheme.primary, title, detail, trailing = null)
}

@Composable
private fun FreeRow(icon: ImageVector, title: String, detail: String) {
    val green = Color(0xFF34C759)
    GuideRow(icon, green, title, detail) {
        Text(stringResource(R.string.free), style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold, color = green)
    }
}

@Composable
private fun GuideRow(
    icon: ImageVector,
    tint: Color,
    title: String,
    detail: String,
    trailing: (@Composable () -> Unit)?,
) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(icon, contentDescription = null, tint = tint,
            modifier = Modifier.size(22.dp).padding(top = 2.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(detail, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        trailing?.let { Spacer(Modifier.width(10.dp)); it() }
    }
}
