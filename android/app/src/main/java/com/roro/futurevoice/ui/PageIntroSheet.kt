package com.roro.futurevoice.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.SubdirectoryArrowRight
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.PageIntroStore
import com.roro.futurevoice.data.PageIntroStore.Page
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme
import com.roro.futurevoice.ui.brand.IosButton
import com.roro.futurevoice.ui.brand.IosOutlinedButton
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * "What is this page for, and how do I use it?" — iOS `PageIntroSheet`
 * (`e4bcd83` · `0d11490` · `e864003`, end state at `ebf848e`). One guide per
 * tab, raised the FIRST time the learner opens that tab and never again, plus
 * one for My routine. The order is the point (founder: the first cut listed
 * feature names and said nothing about WHY any of it exists):
 *   1. the PROBLEM the tab answers, then how this tab answers it;
 *   2. the SCREEN, drawn as a wireframe with numbered callouts — the real tab
 *      is often still empty for a new learner, so a screenshot would show
 *      nothing;
 *   3. what happens NEXT.
 *
 * The wireframes ([PageIntroMocks]) are illustrations, not UI: grey bars
 * stand in for text so they read the same in every language.
 */
object PageIntro {
    fun icon(page: Page): ImageVector = when (page) {
        Page.TALK -> Icons.Filled.GraphicEq
        Page.WATCH -> Icons.Filled.PlayCircle
        Page.REVIEW -> Icons.AutoMirrored.Filled.MenuBook
        Page.PROGRESS -> Icons.Filled.BarChart
        Page.ROUTINE -> Icons.Filled.LocalFireDepartment
    }

    fun nameRes(page: Page): Int = when (page) {
        Page.TALK -> R.string.guide_talk
        Page.WATCH -> R.string.guide_watch
        Page.REVIEW -> R.string.guide_review
        Page.PROGRESS -> R.string.guide_progress
        Page.ROUTINE -> R.string.guide_my_routine
    }

    /** The guide's opening line, and the row's subtitle in Me → App guide. */
    fun problemRes(page: Page): Int = when (page) {
        Page.TALK -> R.string.guide_you_know_the_words_you_just
        Page.WATCH -> R.string.guide_in_a_new_situation_you_dont
        Page.REVIEW -> R.string.guide_what_you_learn_today_is_gone
        Page.PROGRESS -> R.string.guide_am_i_actually_getting_better
        Page.ROUTINE -> R.string.guide_studying_every_day_is_easy_to
    }

    /** Talk walks the home, its header, the call, its settings and coach
     *  mode; Watch adds people and "making it yours". */
    fun stepCount(page: Page): Int = when (page) {
        Page.TALK -> 6
        Page.WATCH -> 5
        Page.REVIEW -> 4
        Page.PROGRESS, Page.ROUTINE -> 3
    }

    class Callout(val title: Int, val detail: Int)
}

// MARK: - Hosts (the first-visit triggers)

/** iOS `RootTabView.introPage`: the third tab is still Practice in code. */
internal fun HomeTab.guidePage(): Page = when (this) {
    HomeTab.TALK -> Page.TALK
    HomeTab.WATCH -> Page.WATCH
    HomeTab.PRACTICE -> Page.REVIEW
    HomeTab.PROGRESS -> Page.PROGRESS
}

/**
 * Raises [page]'s guide if this install hasn't seen it — iOS
 * `RootTabView.offerPageIntro`. A beat late (450 ms) so the page draws first
 * and the sheet rises over it, and never over another sheet ([blocked]).
 * Marked seen the moment it shows. Skipped in the capture build, where every
 * screen must render as itself.
 */
@Composable
fun PageIntroHost(page: Page, blocked: Boolean) {
    val context = LocalContext.current
    val revision by PageIntroStore.revision.collectAsState()
    var showing by remember { mutableStateOf<Page?>(null) }
    LaunchedEffect(page, blocked, revision) {
        if (com.roro.futurevoice.BuildConfig.BUILD_TYPE == "capture") return@LaunchedEffect
        if (blocked || showing != null || !PageIntroStore.isDue(context, page)) return@LaunchedEffect
        delay(450)
        if (blocked || showing != null || !PageIntroStore.isDue(context, page)) return@LaunchedEffect
        PageIntroStore.markSeen(context, page)
        Analytics.capture("page_intro_shown", mapOf("page" to page.raw))
        PageIntroStore.showing.value = true
        showing = page
    }
    // A host that leaves the screen (an overlay replaced it) takes its sheet
    // with it, and must not leave the root believing a guide is still up.
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { if (showing != null) PageIntroStore.showing.value = false }
    }
    showing?.let { p ->
        PageIntroSheet(p, onDismiss = {
            showing = null
            PageIntroStore.showing.value = false
        })
    }
}

/**
 * My routine's first-visit guide (iOS `ActivityView.offerIntro`). The marks
 * on that page (a green day, a grey ring, a bare number) carry a rule nobody
 * can guess, so it explains itself once. THE HOOK: the routine page calls
 * this with `blocked` = any of its own sheets / the plan editor up.
 */
@Composable
fun RoutineGuideHost(blocked: Boolean = false) = PageIntroHost(Page.ROUTINE, blocked)

// MARK: - The sheet

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PageIntroSheet(page: Page, initialStep: Int = 0, onDismiss: () -> Unit) {
    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
        containerColor = AppSurfaces.card,
    ) {
        PageIntroContent(page, initialStep, onDismiss)
    }
}

/** The sheet's body, apart so a capture can draw it on a plain page. */
@Composable
fun PageIntroContent(page: Page, initialStep: Int = 0, onDismiss: () -> Unit) {
    val count = PageIntro.stepCount(page)
    val pager = rememberPagerState(initialPage = initialStep.coerceIn(0, count - 1)) { count }
    val scope = rememberCoroutineScope()
    val isLast = pager.currentPage == count - 1
    Column(Modifier.fillMaxWidth().fillMaxHeight(0.94f).navigationBarsPadding()) {
        HorizontalPager(state = pager, modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalAlignment = Alignment.Top) { i ->
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                Box(Modifier.widthIn(max = 560.dp).fillMaxSize()) { GuidePage(page, i) }
            }
        }
        // Footer: dots, then "Maybe later" · "Next" (the way out early sits
        // beside Next, where it can say what it does), then where to find it.
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 10.dp, bottom = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.semantics { contentDescription = "${pager.currentPage + 1} / $count" },
                horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                repeat(count) { i ->
                    val w by animateDpAsState(if (i == pager.currentPage) 18.dp else 7.dp, tween(200),
                        label = "guideDot")
                    Box(Modifier.size(width = w, height = 7.dp).background(
                        if (i == pager.currentPage) MaterialTheme.colorScheme.primary else tertiaryLabel(),
                        CircleShape))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!isLast) {
                    IosOutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.guide_maybe_later), fontWeight = FontWeight.SemiBold,
                            maxLines = 1)
                    }
                }
                IosButton(
                    onClick = {
                        if (isLast) onDismiss()
                        else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Text(stringResource(if (isLast) R.string.guide_lets_go else R.string.guide_next),
                        fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
            Text(stringResource(R.string.guide_you_can_see_these_again_anytime),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun GuidePage(page: Page, i: Int) {
    val c = PageIntro::Callout
    when (page) {
        Page.TALK -> when (i) {
            0 -> WhyPage(Hero.Futureself, R.string.guide_talk, PageIntro.problemRes(page),
                R.string.guide_grammar_and_vocabulary_dont_turn_into,
                R.string.guide_here_you_call_yourself_the_version)
            1 -> ScreenPage(R.string.guide_starting_a_call, R.string.guide_everything_on_the_talk_page_leads,
                listOf(c(R.string.guide_tap_the_circle, R.string.guide_a_free_talk_starts_right_away),
                    c(R.string.guide_the_ring_is_todays_goal, R.string.guide_the_whole_ring_is_the_daily),
                    c(R.string.guide_not_sure_what_to_say, R.string.guide_scroll_down_for_situations_like_ordering)),
            ) { TalkRingMock() }
            2 -> ScreenPage(R.string.guide_the_buttons_at_the_top, R.string.guide_three_things_youll_reach_for_often,
                listOf(c(R.string.guide_switch_language, R.string.guide_change_the_language_youre_practicing_or),
                    c(R.string.guide_your_streak, R.string.guide_the_days_you_studied_add_up),
                    c(R.string.guide_your_profile, R.string.guide_opens_me_your_profile_voice_daily)),
            ) { TalkHeaderMock() }
            3 -> ScreenPage(R.string.guide_during_the_call, R.string.guide_talk_the_way_you_would_on,
                listOf(c(R.string.guide_talk_then_pause, R.string.guide_when_you_stop_speaking_your_fluent),
                    c(R.string.guide_a_more_natural_way_to_say, R.string.guide_under_what_you_said_youll_see),
                    c(R.string.guide_why_words_show_up_at_the, R.string.guide_these_are_the_words_and_expressions)),
                note = R.string.guide_when_you_hang_up_the_words,
            ) { TalkCallMock() }
            4 -> ScreenPage(R.string.guide_call_settings, R.string.guide_set_the_call_up_the_way,
                listOf(c(R.string.guide_the_settings_button, R.string.guide_the_slider_button_next_to_the),
                    c(R.string.guide_speaking_speed, R.string.guide_normal_relaxed_or_slow_its_how),
                    c(R.string.guide_coach_mode, R.string.guide_extra_help_while_you_answer_the),
                    c(R.string.guide_whats_on_screen, R.string.guide_hide_the_subtitles_the_corrections_or)),
            ) { CallSettingsMock() }
            else -> ScreenPage(R.string.guide_coach_mode, R.string.guide_for_when_you_know_what_you,
                listOf(c(R.string.guide_try_saying, R.string.guide_each_time_your_fluent_self_speaks),
                    c(R.string.guide_try_using, R.string.guide_now_and_then_it_asks_something),
                    c(R.string.guide_this_calls_grammar_focus, R.string.guide_the_mistake_you_make_most_like)),
                note = R.string.guide_a_coached_call_counts_as_a,
            ) { CoachMock() }
        }
        Page.WATCH -> when (i) {
            0 -> WhyPage(Hero.Symbol(Icons.Filled.PlayCircle), R.string.guide_watch, PageIntro.problemRes(page),
                R.string.guide_a_job_interview_a_call_to,
                R.string.guide_watch_shows_that_situation_played_out)
            1 -> ConceptPage(R.string.guide_people_your_own_cast, listOf(
                GuideConcept(Icons.Filled.AccountCircle, R.string.guide_what_it_is,
                    R.string.guide_a_person_you_describe_once_someone),
                GuideConcept(Icons.Filled.HelpOutline, R.string.guide_why_it_matters,
                    R.string.guide_what_you_say_depends_on_who),
                GuideConcept(Icons.Filled.AutoAwesome, R.string.guide_how_you_use_it,
                    R.string.guide_the_more_you_save_about_them),
            )) { CastMock() }
            2 -> ScreenPage(R.string.guide_setting_up_a_scene, R.string.guide_decide_who_its_with_and_whats,
                listOf(c(R.string.guide_pick_a_person, R.string.guide_tap_someone_in_your_people_row),
                    c(R.string.guide_write_your_own_situation, R.string.guide_describe_whats_coming_up_in_as),
                    c(R.string.guide_pick_a_common_situation, R.string.guide_no_time_to_write_tap_your)),
            ) { WatchHomeMock() }
            3 -> ScreenPage(R.string.guide_watching_for_ideas, R.string.guide_notice_how_its_done_not_just,
                listOf(c(R.string.guide_your_fluent_self_in_your_voice, R.string.guide_the_lines_play_one_after_another),
                    c(R.string.guide_keep_what_youd_use, R.string.guide_under_every_line_shadow_it_right),
                    c(R.string.guide_watch_again_or_study_it, R.string.guide_the_left_button_plays_the_scene)),
            ) { WatchSceneMock() }
            else -> StepsPage(R.string.guide_making_it_yours, R.string.guide_an_idea_is_only_yours_once, listOf(
                GuideStep(Icons.Filled.Visibility, R.string.guide_get_the_idea, R.string.guide_watch_the_scene_and_notice_the),
                GuideStep(Icons.Filled.Bookmark, R.string.guide_keep_it, R.string.guide_save_the_expressions_you_want_and),
                GuideStep(Icons.AutoMirrored.Filled.MenuBook, R.string.guide_learn_it_in_review,
                    R.string.guide_the_scenes_book_brings_its_words),
                GuideStep(Icons.Filled.Phone, R.string.guide_say_it_yourself, R.string.guide_start_a_talk_from_the_scenes),
            ))
        }
        Page.REVIEW -> when (i) {
            0 -> WhyPage(Hero.Symbol(Icons.AutoMirrored.Filled.MenuBook), R.string.guide_review,
                PageIntro.problemRes(page), R.string.guide_a_phrase_you_heard_in_a,
                R.string.guide_review_fills_itself_after_every_talk)
            1 -> ScreenPage(R.string.guide_your_study_books, R.string.guide_one_talk_one_book_the_newest,
                listOf(c(R.string.guide_a_book, R.string.guide_every_talk_and_scene_you_finish),
                    c(R.string.guide_chapters, R.string.guide_words_expressions_shadowing_and_grammar_tap),
                    c(R.string.guide_your_library, R.string.guide_everything_youve_collected_from_every_book)),
            ) { ReviewHomeMock() }
            2 -> ScreenPage(R.string.guide_how_a_card_works, R.string.guide_you_decide_when_you_see_it,
                listOf(c(R.string.guide_say_it_then_check, R.string.guide_say_the_word_out_loud_first),
                    c(R.string.guide_not_sure_yet, R.string.guide_drag_the_card_onto_10_min),
                    c(R.string.guide_know_it, R.string.guide_drop_it_on_got_it_and)),
                note = R.string.guide_best_of_all_say_it_in,
            ) { ReviewCardMock() }
            else -> ScreenPage(R.string.guide_your_week_at_the_top, R.string.guide_the_three_buttons_in_the_header,
                listOf(c(R.string.guide_cards_you_put_off, R.string.guide_every_card_you_sent_to_10),
                    c(R.string.guide_your_week, R.string.guide_when_a_new_week_starts_a),
                    c(R.string.guide_weekly_test, R.string.guide_once_a_week_a_test_made)),
                note = R.string.what_you_get_wrong_comes_back_in_the_next_weeks_tests_until_3b41bd,
            ) { ReviewWeekMock() }
        }
        Page.PROGRESS -> when (i) {
            0 -> WhyPage(Hero.Symbol(Icons.Filled.BarChart), R.string.guide_progress, PageIntro.problemRes(page),
                R.string.guide_its_hard_to_keep_going_when, R.string.guide_progress_never_asks_you_to_sit)
            1 -> ScreenPage(R.string.guide_reading_your_level, R.string.guide_from_a1_to_c2_measured_from,
                listOf(c(R.string.guide_your_overall_level, R.string.guide_where_you_are_between_a1_and),
                    c(R.string.guide_skill_by_skill, R.string.guide_vocabulary_grammar_and_fluency_each_have),
                    c(R.string.guide_your_effort, R.string.guide_how_much_you_talked_and_reviewed)),
            ) { ProgressHomeMock() }
            else -> StepsPage(R.string.guide_when_does_my_level_appear, R.string.guide_it_needs_a_little_of_your,
                listOf(
                    GuideStep(Icons.Filled.Phone, R.string.guide_talk_for_about_10_minutes,
                        R.string.guide_thats_enough_of_your_speech_to),
                    GuideStep(Icons.Filled.BarChart, R.string.guide_your_first_level_appears,
                        R.string.guide_each_skill_gets_its_own_level),
                    GuideStep(Icons.AutoMirrored.Filled.TrendingUp, R.string.guide_it_moves_as_you_talk,
                        R.string.guide_every_call_measures_again_and_when),
                ))
        }
        Page.ROUTINE -> when (i) {
            0 -> WhyPage(Hero.Symbol(Icons.Filled.LocalFireDepartment), R.string.guide_my_routine,
                PageIntro.problemRes(page), R.string.guide_a_plan_in_your_head_slips,
                R.string.guide_plan_your_week_once_here_each,
                answerHeading = R.string.guide_heres_how_this_page_helps)
            1 -> ScreenPage(R.string.guide_plan_on_the_timeline, R.string.guide_tap_edit_at_the_top_right,
                listOf(c(R.string.guide_tap_an_empty_spot_to_add, R.string.guide_pick_what_to_do_there_talk),
                    c(R.string.guide_hold_and_drag_to_move, R.string.guide_up_and_down_changes_the_time),
                    c(R.string.guide_set_it_once_it_repeats, R.string.guide_the_same_plan_comes_back_every)),
            ) { RoutineTimelineMock() }
            else -> ScreenPage(R.string.guide_done_it_all_it_turns_green, R.string.guide_each_date_at_the_top_shows,
                listOf(c(R.string.guide_green_you_did_it_all, R.string.guide_everything_planned_for_that_day_is),
                    c(R.string.guide_today_fills_as_you_go, R.string.guide_any_time_that_day_counts_the)),
                note = R.string.guide_an_empty_day_is_a_rest,
            ) { RoutineDaysMock() }
        }
    }
}

// MARK: - Page 1: the problem, then the answer

private sealed interface Hero {
    data object Futureself : Hero
    data class Symbol(val icon: ImageVector) : Hero
}

@Composable
private fun WhyPage(hero: Hero, eyebrow: Int, problem: Int, detail: Int, answer: Int,
                    answerHeading: Int = R.string.guide_heres_how_this_tab_helps) {
    val accent = MaterialTheme.colorScheme.primary
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp).padding(top = 4.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        Box(Modifier.fillMaxWidth().padding(top = 8.dp).clearAndSetSemantics { },
            contentAlignment = Alignment.Center) {
            when (hero) {
                Hero.Futureself -> {
                    val context = LocalContext.current
                    Futureself(mode = FutureselfMode.SPEAKING, level = 0.35f,
                        theme = remember { FutureselfTheme.stored(context) }, virtualHeight = 64f,
                        modifier = Modifier.size(88.dp).clip(CircleShape))
                }
                is Hero.Symbol -> Box(
                    Modifier.size(88.dp).background(accent.copy(alpha = 0.14f), ContinuousShape(22.dp)),
                    contentAlignment = Alignment.Center,
                ) { Icon(hero.icon, null, Modifier.size(44.dp), tint = accent) }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(eyebrow), style = MaterialTheme.typography.titleSmall, color = accent)
            Text(stringResource(problem), style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold)
            Text(stringResource(detail), style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(
            Modifier.fillMaxWidth().background(accent.copy(alpha = 0.08f), ContinuousShape(16.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.Lightbulb, null, Modifier.size(16.dp), tint = accent)
                Text(stringResource(answerHeading), style = MaterialTheme.typography.titleSmall, color = accent)
            }
            Text(stringResource(answer), style = MaterialTheme.typography.bodyLarge)
        }
    }
}

// MARK: - Page 2/3: the screen, with numbered callouts

/** Which numbered spot is lit — read by [Callout] inside the wireframes. */
internal val LocalCalloutFocus = staticCompositionLocalOf { 0 }

/** The picture's frame: grouped ground, hairline rim, 24 dp corners. */
@Composable
private fun PictureFrame(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier.fillMaxWidth()
            .padding(horizontal = 24.dp).padding(top = 4.dp, bottom = 14.dp)
            .background(AppSurfaces.ground, ContinuousShape(24.dp))
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, ContinuousShape(24.dp))
            .padding(16.dp)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.TopCenter,
        content = content,
    )
}

@Composable
private fun ScreenPage(title: Int, subtitle: Int, callouts: List<PageIntro.Callout>, note: Int? = null,
                       mock: @Composable () -> Unit) {
    val context = LocalContext.current
    // Which numbered spot is lit. It walks 1 → 2 → 3 by itself so the eye is
    // led from the picture to its explanation, and stops for good the moment
    // the learner taps a row — after that they are steering.
    var focus by remember { mutableIntStateOf(1) }
    var steered by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val rowTops = remember { mutableStateMapOf<Int, Int>() }
    val reduceMotion = remember {
        android.provider.Settings.Global.getFloat(context.contentResolver,
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    LaunchedEffect(Unit) {
        if (reduceMotion) return@LaunchedEffect
        while (true) {
            delay(2600)
            if (steered) return@LaunchedEffect
            focus = focus % maxOf(callouts.size, 1) + 1
        }
    }
    LaunchedEffect(focus) { rowTops[focus]?.let { scroll.animateScrollTo(it) } }

    Column(Modifier.fillMaxSize()) {
        // The picture stays put; the explanations scroll under it, so the
        // lit spot and its row can always be seen together.
        PictureFrame {
            CompositionLocalProvider(LocalCalloutFocus provides focus) { mock() }
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(scroll)
                .padding(horizontal = 24.dp).padding(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Column(Modifier.padding(horizontal = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(title), style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold)
                Text(stringResource(subtitle), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                callouts.forEachIndexed { index, callout ->
                    val n = index + 1
                    Row(
                        Modifier.fillMaxWidth()
                            .onGloballyPositioned { rowTops[n] = it.positionInParent().y.toInt() }
                            .clickable(remember { MutableInteractionSource() }, indication = null) {
                                steered = true; focus = n
                            }
                            .padding(horizontal = 10.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        CalloutBadge(n, focus == n)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(stringResource(callout.title), style = MaterialTheme.typography.titleMedium)
                            Text(stringResource(callout.detail), style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            if (note != null) {
                Row(Modifier.padding(horizontal = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.SubdirectoryArrowRight, null, Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(note), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
internal fun CalloutBadge(number: Int, lit: Boolean, modifier: Modifier = Modifier) {
    val alpha by animateFloatAsState(if (lit) 1f else 0.5f, tween(250), label = "badgeAlpha")
    val grow by animateFloatAsState(if (lit) 1.08f else 1f, tween(250), label = "badgeScale")
    val accent = MaterialTheme.colorScheme.primary
    Box(
        modifier.size(22.dp).scale(grow).background(accent.copy(alpha = alpha), CircleShape)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Text("$number", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onPrimary)
    }
}

/**
 * Marks one spot on a wireframe: a numbered badge always, and a soft fill
 * while it is the lit one. No outline (founder: too much blue). The fill's
 * corner is CONCENTRIC with what it wraps — [corner] is the wrapped content's
 * own radius, and the fill adds its inset to it.
 *
 * The halo and the badge are drawn OUTSIDE the content's bounds and take no
 * layout space: a mark must never move what it marks, or the picture stops
 * matching the screen it was drawn from.
 */
@Composable
internal fun Callout(
    number: Int,
    corner: Dp = 12.dp,
    trailing: Boolean = false,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val lit = LocalCalloutFocus.current == number
    val accent = MaterialTheme.colorScheme.primary
    val fill by animateColorAsState(accent.copy(alpha = if (lit) 0.12f else 0f), tween(300), label = "calloutFill")
    val inset = 5.dp
    Box(modifier.drawBehind {
        val i = inset.toPx()
        drawRoundRect(fill, topLeft = Offset(-i, -i), size = Size(size.width + 2 * i, size.height + 2 * i),
            cornerRadius = CornerRadius((corner + inset).toPx()))
    }) {
        content()
        Box(Modifier.matchParentSize(), contentAlignment = if (trailing) Alignment.TopEnd else Alignment.TopStart) {
            CalloutBadge(number, lit,
                Modifier.offset(x = if (trailing) 9.dp + inset else -9.dp - inset, y = -9.dp - inset))
        }
    }
}

// MARK: - Steps (a short timeline) and Concept (an idea the screen can't show)

private class GuideStep(val icon: ImageVector, val title: Int, val detail: Int)

@Composable
private fun StepsPage(title: Int, subtitle: Int, steps: List<GuideStep>) {
    val accent = MaterialTheme.colorScheme.primary
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp).padding(top = 4.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(title), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(stringResource(subtitle), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column {
            steps.forEachIndexed { index, step ->
                Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(44.dp).background(accent.copy(alpha = 0.14f), CircleShape),
                            contentAlignment = Alignment.Center) {
                            Icon(step.icon, null, Modifier.size(20.dp), tint = accent)
                        }
                        if (index < steps.size - 1) {
                            Box(Modifier.width(2.dp).weight(1f).heightIn(min = 28.dp)
                                .background(accent.copy(alpha = 0.3f)))
                        }
                    }
                    Column(Modifier.weight(1f).padding(top = 10.dp, bottom = 22.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(stringResource(step.title), style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(step.detail), style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

private class GuideConcept(val icon: ImageVector, val title: Int, val body: Int)

@Composable
private fun ConceptPage(title: Int, sections: List<GuideConcept>, picture: @Composable () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Column(Modifier.fillMaxSize()) {
        PictureFrame { picture() }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 34.dp).padding(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text(stringResource(title), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            sections.forEach { s ->
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(s.icon, null, Modifier.size(20.dp), tint = accent)
                        Text(stringResource(s.title), style = MaterialTheme.typography.titleMedium)
                    }
                    Text(stringResource(s.body), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

// MARK: - Me → App guide

/**
 * Every guide in one place, for whenever the learner wants it again — iOS
 * `AppGuideView`, reached from Me, the one page that is always a tap away.
 */
@Composable
fun AppGuidePage(onBack: () -> Unit) {
    val context = LocalContext.current
    var open by remember { mutableStateOf<Page?>(null) }
    var willShowAgain by remember { mutableStateOf(false) }
    val accent = MaterialTheme.colorScheme.primary
    MeSubpage(stringResource(R.string.guide_app_guide), onBack) {
        Spacer(Modifier.padding(top = 12.dp))
        GroupedCard {
            Page.entries.forEachIndexed { i, page ->
                if (i > 0) GroupedRowDivider(inset = false)
                Row(
                    Modifier.fillMaxWidth().clickable { open = page }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Box(Modifier.size(44.dp).background(accent.copy(alpha = 0.14f), ContinuousShape(10.dp)),
                        contentAlignment = Alignment.Center) {
                        Icon(PageIntro.icon(page), null, Modifier.size(22.dp), tint = accent)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(stringResource(PageIntro.nameRes(page)), style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(PageIntro.problemRes(page)), style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                }
            }
        }
        GroupedFooter(stringResource(R.string.guide_each_guide_explains_what_the_tab))
        GroupedSectionSpacer()
        GroupedCard {
            Row(
                Modifier.fillMaxWidth()
                    .clickable(enabled = !willShowAgain) {
                        PageIntroStore.resetAll(context)
                        willShowAgain = true
                    }
                    .padding(horizontal = 16.dp, vertical = 13.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                val tint = if (willShowAgain) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f) else accent
                Icon(Icons.Filled.Replay, null, Modifier.size(18.dp), tint = tint)
                Text(stringResource(R.string.guide_show_each_guide_again_when_i),
                    style = MaterialTheme.typography.bodyLarge, color = tint)
            }
        }
        if (willShowAgain) GroupedFooter(stringResource(R.string.guide_done_each_tab_will_open_with))
    }
    open?.let { PageIntroSheet(it, onDismiss = { open = null }) }
}

/** iOS `tertiaryLabel`. */
@Composable
internal fun tertiaryLabel(): Color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
