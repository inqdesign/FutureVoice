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
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MicExternalOn
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.School
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
 * sync with the server (talk-tick + tts routing): a mismatch
 * between what we show and what we meter is a trust-breaker.
 *
 * The model in one line: talk minutes are spent by calls (a pronunciation
 * lesson at half), voiceovers and — for anyone subscribing from 2026-10-19 —
 * new scenes; replays and everything else in the app are free (iOS
 * c380df8b, 4418b601, 2c2c008f).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreditGuideScreen(onBack: () -> Unit) {
    NavPageBackHandler(onBack = onBack)
    var account by remember { mutableStateOf<AccountStatus?>(null) }
    LaunchedEffect(Unit) {
        // Screenshot harness only: a sample account instead of the network.
        account = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewAccount
            ?: AccountStatus.load(AuthRepository())
    }
    val locale = LocalConfiguration.current.locales[0]
    val scroll = rememberScrollState()
    // Captures: `-capture plan-guide-free` shoots the free list (iOS 4418b601).
    LaunchedEffect(Unit) {
        if (!com.roro.futurevoice.capture.flags.MeCaptureFlags.guideScrollToFree) return@LaunchedEffect
        kotlinx.coroutines.delay(400)
        scroll.scrollTo(scroll.maxValue)
    }

    Scaffold(
        topBar = {
            androidx.compose.material3.CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { com.roro.futurevoice.ui.brand.IosNavTitle(stringResource(R.string.what_uses_talk_time)) },
                navigationIcon = { com.roro.futurevoice.ui.brand.IosBackButton(onBack) },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(scroll)
                .padding(horizontal = 16.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // This account's scenes (or a purchase's) are paid in talk minutes.
            val sceneTalk = account?.scenesCostTalk == true
            // The pool sits FIRST: it is the shape of the whole plan, and the
            // question that actually brings people here is "what am I allowed
            // to do?" before "what does it cost me?".
            //
            // The plan holds talk minutes and nothing else (iOS 2c2c008f,
            // founder 2026-11-05: a scene is paid from the minutes, so no
            // scene count belongs here — the accounts still on a count see it
            // on Usage and in the Watch section below, like the paywall).
            account?.takeIf { it.isEntitled }?.let { a ->
                GroupedSectionHeader(stringResource(R.string.what_your_plan_holds))
                GroupedCard {
                    val cap = a.monthlyCapSeconds
                    PlainRow(
                        icon = Icons.Filled.CalendarMonth,
                        title = cap?.let { stringResource(R.string.lld_minutes_a_month, it / 60) }
                            ?: stringResource(R.string.talk_as_much_as_you_want),
                        detail = if (cap == null)
                            stringResource(R.string.no_limit_and_no_rationing_talking_takes_real_effort_so_there_9058ba)
                        else stringResource(R.string.use_them_however_you_like_all_in_one_call_today_or_spread_ov_1df811),
                    )
                }
                // A cancelled plan refills nothing — the same date, the
                // opposite promise.
                val renews = a.renewalLabel(locale)
                GroupedFooter(when {
                    renews.isEmpty() -> stringResource(R.string.your_minutes_refill_at_the_start_of_each_billing_period)
                    a.cancelAtPeriodEnd -> stringResource(R.string.your_plan_ends_on_lld, renews)
                    else -> stringResource(R.string.your_minutes_refill_on, renews)
                })
            }

            GroupedSectionHeader(stringResource(R.string.uses_talk_time))
            GroupedCard {
                // The rules as metered (iOS c380df8b, 2026-11-05): a call is
                // billed by its clock while someone is speaking, stopping
                // after 30 s of quiet; a pronunciation call at half; a
                // voiceover by its characters.
                CostRow(Icons.Filled.Phone, stringResource(R.string.calls),
                    stringResource(R.string.clock_time),
                    stringResource(R.string.free_talk_tutor_lessons_the_daily_call_and_calls_with_people_ef5709))
                GroupedRowDivider()
                CostRow(Icons.Filled.RecordVoiceOver, stringResource(R.string.pronunciation),
                    stringResource(R.string.s_50_off),
                    stringResource(R.string.a_10_minute_lesson_uses_5_minutes))
                // Since 2026-10-19 a scene is paid for out of the same
                // minutes, for anyone subscribing from then on.
                if (sceneTalk) {
                    GroupedRowDivider()
                    CostRow(Icons.Filled.PlayCircle, stringResource(R.string.watching_a_new_scene),
                        stringResource(R.string.lld_min_b61908, account?.sceneTalkMinutes ?: 5),
                        stringResource(R.string.the_same_price_whichever_way_it_runs_a_long_scene_or_a_short_94d481))
                }
                GroupedRowDivider()
                CostRow(Icons.Filled.RecordVoiceOver, stringResource(R.string.hear_it_in_my_voice),
                    stringResource(R.string.s_1_min_per_100_characters),
                    stringResource(R.string.a_speech_script_or_what_your_tutor_prepared_for_a_goal_read_3ecda2))
            }
            GroupedFooter(if (sceneTalk)
                stringResource(R.string.calls_new_scenes_and_voiceovers_spend_your_talk_minutes_ever_9e25c5)
            else stringResource(R.string.only_calls_and_voiceovers_spend_your_talk_minutes_watching_a_95912c))

            if (!sceneTalk) {
                GroupedSectionHeader(stringResource(R.string.watch_scenes))
                GroupedCard {
                    CostRow(Icons.Filled.PlayCircle, stringResource(R.string.watching_a_scene),
                        stringResource(R.string.s_1_scene),
                        stringResource(R.string.watch_has_its_own_pool_separate_from_your_talk_minutes_a_sce_98932d))
                }
                GroupedFooter(stringResource(R.string.scenes_you_ve_already_watched_replay_free_forever_and_never_d6d2d2))
            }

            // Every feature that spends nothing, one row each (iOS 4418b601,
            // founder 2026-11-05: the page covers the whole app).
            GroupedSectionHeader(stringResource(R.string.always_free))
            GroupedCard {
                FreeRow(Icons.Filled.Layers, stringResource(R.string.all_reviewing),
                    stringResource(R.string.drills_shadowing_with_coach_feedback_and_pronunciation_score_f31e0e))
                GroupedRowDivider()
                FreeRow(Icons.Filled.Repeat, stringResource(R.string.replays),
                    stringResource(R.string.anything_already_synthesized_is_cached_loop_it_slow_it_down_fed756))
                GroupedRowDivider()
                FreeRow(Icons.Filled.School, stringResource(R.string.tutor),
                    stringResource(R.string.chat_today_s_plan_and_everything_it_prepares_for_your_goals_40fab4))
                GroupedRowDivider()
                FreeRow(Icons.Filled.MicExternalOn, stringResource(R.string.speech_d00d85),
                    stringResource(R.string.writing_and_studying_scripts_recording_takes_scores_and_chal_6f47b3))
                GroupedRowDivider()
                FreeRow(Icons.Filled.Headphones, stringResource(R.string.listening_dc3534),
                    stringResource(R.string.the_nawana_podcast_and_the_scenes_you_ve_watched_one_after_a_f225ad))
                GroupedRowDivider()
                FreeRow(Icons.Filled.AutoAwesome, stringResource(R.string.summaries_reports),
                    stringResource(R.string.talk_summaries_weekly_reports_the_weekly_test_and_quick_quiz_0b9f07))
                GroupedRowDivider()
                FreeRow(Icons.Filled.GridView, stringResource(R.string.exploring),
                    stringResource(R.string.building_situations_browsing_topics_translations_dictionarie_456d7f))
                GroupedRowDivider()
                FreeRow(Icons.AutoMirrored.Filled.MenuBook,
                    stringResource(R.string.vocabulary_progress),
                    stringResource(R.string.the_word_cloud_cefr_estimate_and_stats_never_cost_anything))
                GroupedRowDivider()
                FreeRow(Icons.Filled.GraphicEq, stringResource(R.string.making_your_voice),
                    stringResource(R.string.recording_it_and_making_it_again))
            }
            GroupedFooter(stringResource(R.string.in_short_minutes_buy_speaking_time_with_your_fluent_self_pra_828cac))
        }
    }
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
