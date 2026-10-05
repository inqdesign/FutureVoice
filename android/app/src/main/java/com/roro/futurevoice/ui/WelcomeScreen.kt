package com.roro.futurevoice.ui

import android.app.Activity
import android.content.Context
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.CenteredFlow
import com.roro.futurevoice.ui.brand.FutureselfDoor
import com.roro.futurevoice.ui.brand.Glimpse
import com.roro.futurevoice.ui.brand.RevealText
import com.roro.futurevoice.ui.brand.StoryBackdrop
import com.roro.futurevoice.ui.brand.StoryInk
import com.roro.futurevoice.ui.brand.arrive
import kotlinx.coroutines.delay

/**
 * First screen — a short film, not a tutorial (iOS `WelcomeView`, d4d1d566 +
 * 10f65de5; founder: "strip the tutorial, a quiet gradient and words that
 * animate in"). The fluent self tells the learner's own story back to them,
 * introduces itself and says what the two of them will do together; it ends
 * on the five things the app does, gathered, and the button.
 *
 * The narrator is the FLUENT SELF, so every line is informal wherever the
 * language marks it; the chips are the app speaking. The captions are the
 * whole film for now — a voice-over is planned ([StoryBeat.holdSeconds]).
 *
 * The old five-slide pager (`WelcomeHeroes.kt`) is no longer shown, as on iOS.
 *
 * Android differs in one place: sign-in is its own screen in the root router,
 * so "Already have an account? Sign in" goes there instead of swapping the
 * button for inline Apple/Google buttons.
 */
@Composable
fun WelcomeScreen(
    onGetStarted: () -> Unit,
    /** A returning learner: go straight to sign-in, so their voice and
     *  progress come back with them. */
    onSignIn: (() -> Unit)? = null,
    /** An invite is redeemed at the sign-in moment, so it is asked here. */
    onInviteCode: (() -> Unit)? = null,
    /** Capture only (iOS `-welcomePage <n>`): hold on one beat;
     *  `beats.size` is the closing frame. */
    initialBeat: Int = 0,
) {
    val context = LocalContext.current
    val still = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    val beats = welcomeBeats()
    val closingLine = stringResource(R.string.until_the_day_you_become_me_let_s_do_this_together)
    val startBeat = initialBeat.coerceIn(0, beats.size)
    var beat by remember { mutableIntStateOf(startBeat) }
    var autoplay by remember { mutableStateOf(startBeat == 0) }
    // Bumped on every manual step so the autoplay sleep restarts its clock.
    var tick by remember { mutableIntStateOf(0) }
    var doorOpen by remember { mutableStateOf(false) }
    // The closing frame was reached by Skip, not by watching.
    var skipped by remember { mutableStateOf(false) }
    val isClosing = beat >= beats.size

    fun step() { beat = minOf(beat + 1, beats.size) }
    fun finish() { skipped = true; autoplay = false; beat = beats.size }
    fun replay() { skipped = false; doorOpen = false; autoplay = true; beat = 0; tick++ }

    // The top of the film is near-black, the bottom cream: light status-bar
    // icons, dark navigation-bar icons, while this screen is up.
    val view = LocalView.current
    DisposableEffect(Unit) {
        val window = (view.context as? Activity)?.window
        val ctl = window?.let { WindowCompat.getInsetsController(it, view) }
        val oldStatus = ctl?.isAppearanceLightStatusBars
        val oldNav = ctl?.isAppearanceLightNavigationBars
        ctl?.isAppearanceLightStatusBars = false
        ctl?.isAppearanceLightNavigationBars = true
        onDispose {
            oldStatus?.let { ctl.isAppearanceLightStatusBars = it }
            oldNav?.let { ctl.isAppearanceLightNavigationBars = it }
        }
    }
    // A story told on a clock can't be read by TalkBack; give those learners
    // the closing frame, which says the same in a list.
    LaunchedEffect(Unit) {
        val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        if (am?.isTouchExplorationEnabled == true) finish()
    }
    LaunchedEffect(tick) {
        while (autoplay && beat < beats.size) {
            delay((beatDuration(beats[beat]) * 1000).toLong())
            if (!autoplay) return@LaunchedEffect
            step()
        }
    }
    LaunchedEffect(isClosing) {
        if (!isClosing) { doorOpen = false; return@LaunchedEffect }
        // The orb opens into the button once the last line has landed;
        // straight away for someone who skipped.
        delay(if (skipped || still) 300 else 1900)
        doorOpen = true
    }

    val shiftPx = with(LocalDensity.current) { 14.dp.roundToPx() }
    Box(Modifier.fillMaxSize()) {
        StoryBackdrop(Modifier.fillMaxSize(), still = still)
        Column(
            Modifier.fillMaxSize().systemBarsPadding()
                .clickable(remember { MutableInteractionSource() }, indication = null) {
                    // Tap anywhere to move on — the film is never a wall.
                    if (!isClosing) { autoplay = true; step(); tick++ }
                },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Top bar: Skip during the film, Watch again at the end.
            Row(Modifier.fillMaxWidth().height(44.dp), horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(if (isClosing) R.string.watch_again else R.string.skip),
                    color = Color.White.copy(alpha = 0.75f),
                    fontSize = if (isClosing) 13.sp else 15.sp,
                    fontWeight = if (isClosing) FontWeight.Normal else FontWeight.Medium,
                    modifier = Modifier
                        .clickable { if (isClosing) replay() else finish() }
                        .padding(horizontal = 20.dp, vertical = 10.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            AnimatedContent(
                targetState = beat,
                transitionSpec = {
                    EnterTransition.None togetherWith (fadeOut(tween(700)) +
                        slideOutVertically(tween(700)) { if (still) 0 else -shiftPx })
                },
                modifier = Modifier.fillMaxWidth().height(250.dp).padding(horizontal = 24.dp),
                contentAlignment = Alignment.Center,
                label = "beat",
            ) { b ->
                if (b >= beats.size) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(26.dp)) {
                        RevealText(closingLine, still = still)
                        // The film's own chips, gathered — full width, so
                        // they pair up rather than stack one a row.
                        CenteredFlow(Modifier.fillMaxWidth(), spacing = 6.dp, lineSpacing = 8.dp) {
                            beats.mapNotNull { it.glimpse }.forEachIndexed { i, g ->
                                Glimpse(g.first, g.second, delayMs = 1500 + i * 120, compact = true, still = still)
                            }
                        }
                    }
                } else {
                    val sb = beats[b]
                    Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(22.dp)) {
                        sb.glimpse?.let { Glimpse(it.first, it.second, delayMs = 200, still = still) }
                        RevealText(sb.text, still = still)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            // The orb's row never changes height, so it sits in the same
            // place on every line and as the button.
            Box(Modifier.fillMaxWidth().height(76.dp).padding(horizontal = 32.dp)) {
                FutureselfDoor(open = doorOpen, beat = beat, label = stringResource(R.string.get_started),
                    still = still, onClick = onGetStarted)
            }
            Box(Modifier.fillMaxWidth().heightIn(min = 110.dp).padding(bottom = 10.dp),
                contentAlignment = Alignment.TopCenter) {
                if (!isClosing) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Progress(count = beats.size, beat = beat,
                            modifier = Modifier.padding(top = 22.dp, bottom = 16.dp))
                        if (onSignIn != null) {
                            Link(stringResource(R.string.already_have_an_account_sign_in),
                                StoryInk.copy(alpha = 0.55f), onSignIn)
                        }
                    }
                } else {
                    Column(
                        Modifier.padding(top = 14.dp).arrive(if (skipped) 300 else 2500, still),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        val tint = Color(0.040f, 0.360f, 0.960f)
                        if (onSignIn != null) Link(stringResource(R.string.already_have_an_account_sign_in), tint, onSignIn)
                        if (onInviteCode != null) Link(stringResource(R.string.have_an_invite_code), tint, onInviteCode)
                    }
                }
            }
        }
    }
}

@Composable
private fun Link(text: String, color: Color, onClick: () -> Unit) {
    Text(text, color = color, fontSize = 13.sp,
        modifier = Modifier.clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp))
}

@Composable
private fun Progress(count: Int, beat: Int, modifier: Modifier = Modifier) {
    Row(modifier.clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically) {
        repeat(count) { i ->
            val w by animateDpAsState(if (i == beat) 14.dp else 5.dp, tween(400), label = "dot")
            Box(Modifier.size(w, 3.dp).background(
                StoryInk.copy(alpha = if (i <= beat) 0.6f else 0.15f), RoundedCornerShape(50)))
        }
    }
}

/** One line of the film. [holdSeconds] null = derived from the caption's
 *  length; set it from the clip's duration once the voice-over is recorded. */
data class StoryBeat(
    val text: String,
    val glimpse: Pair<ImageVector, String>? = null,
    val holdSeconds: Double? = null,
)

/** Reveal + reading time: long enough to read twice at a calm pace, short
 *  enough that the whole film stays well under a minute (iOS `duration(of:)`). */
fun beatDuration(b: StoryBeat): Double =
    b.holdSeconds ?: minOf(6.5, maxOf(3.8, 2.2 + b.text.length * 0.06))

/** The script, in the app language — iOS `WelcomeView.beats`, line for line. */
@Composable
fun welcomeBeats(): List<StoryBeat> = listOf(
    StoryBeat(stringResource(R.string.so_much_you_want_to_say_all_of_it_still_in_your_head)),
    StoryBeat(stringResource(R.string.why_is_it_so_hard_just_to_start_talking)),
    StoryBeat(stringResource(R.string.school_classes_youtube_books_apps_you_tried_so_hard_didn_t_y_70dd65)),
    StoryBeat(stringResource(R.string.hi_it_s_me_you_already_fluent)),
    StoryBeat(stringResource(R.string.i_ll_call_you_let_s_talk_five_minutes_a_day),
        Icons.Filled.Phone to stringResource(R.string.talk_like_a_phone_call)),
    StoryBeat(stringResource(R.string.stumble_get_it_wrong_that_s_fine_i_ll_show_you_how_it_goes),
        Icons.Outlined.ChatBubbleOutline to stringResource(R.string.every_line_said_naturally)),
    StoryBeat(stringResource(R.string.everything_we_talk_about_becomes_your_own_textbook),
        Icons.AutoMirrored.Outlined.MenuBook to stringResource(R.string.your_own_textbook)),
    StoryBeat(stringResource(R.string.what_you_keep_getting_wrong_comes_back_every_day_and_you_say_38c34e),
        Icons.Filled.Autorenew to stringResource(R.string.daily_review_shadowing)),
    StoryBeat(stringResource(R.string.practice_while_you_watch_yourself_until_you_feel_sure_until_5d1614),
        Icons.Filled.RecordVoiceOver to stringResource(R.string.speech_practice)),
)
