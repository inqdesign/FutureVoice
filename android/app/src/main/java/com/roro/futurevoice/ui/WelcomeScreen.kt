package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.BookHero
import com.roro.futurevoice.ui.brand.FutureselfHero
import com.roro.futurevoice.ui.brand.HomeHero
import com.roro.futurevoice.ui.brand.LevelHero
import com.roro.futurevoice.ui.brand.ShadowHero
import kotlinx.coroutines.delay

/**
 * First screen — `WelcomeView`'s five beats in the same order (the claim,
 * when/what you talk about, the BOOK a talk leaves, what accumulates, the
 * measured level), auto-advancing like the iOS carousel. The component-built
 * heroes arrive with the design pass; the pitch must read before it can be
 * illustrated.
 */
@Composable
fun WelcomeScreen(onGetStarted: () -> Unit) {
    data class Slide(val title: Int, val subtitle: Int)
    val slides = listOf(
        Slide(R.string.learn_the_language_with_the_fluent_you,
            R.string.it_s_your_own_voice_already_fluent_say_it_however_it_comes_o_219d80),
        Slide(R.string.when_you_want_about_what_you_want,
            R.string.today_s_news_a_situation_you_re_walking_into_this_week_or_no_51bb25),
        Slide(R.string.every_talk_becomes_your_own_textbook,
            R.string.the_words_the_expressions_the_lines_you_actually_spoke_bound_584f33),
        Slide(R.string.the_more_you_say_it_the_more_it_s_yours,
            R.string.shadow_your_fluent_self_s_lines_in_your_own_voice_slow_it_do_fafe50),
        Slide(R.string.a_level_measured_not_guessed,
            R.string.your_level_is_read_from_the_words_you_actually_used_in_a_tal_b61ee0),
    )
    val pager = rememberPagerState { slides.size }
    LaunchedEffect(Unit) {
        while (true) {
            delay(6_500)
            // A hand swipe cancels autoplay for good, as on iOS.
            if (pager.isScrollInProgress) break
            pager.animateScrollToPage((pager.currentPage + 1) % slides.size)
        }
    }
    Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp)) {
        HorizontalPager(state = pager, modifier = Modifier.weight(1f)) { page ->
            Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // The hero is built from the REAL components — the pitch is
                // seen working, not described (`WelcomeHeroes.swift`).
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    when (page) {
                        0 -> FutureselfHero()
                        1 -> HomeHero()
                        2 -> BookHero()
                        3 -> ShadowHero()
                        else -> LevelHero()
                    }
                }
                Text(stringResource(slides[page].title),
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center)
                Text(stringResource(slides[page].subtitle),
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 16.dp))
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(bottom = 16.dp),
            horizontalArrangement = Arrangement.Center,
        ) {
            repeat(slides.size) { i ->
                Box(Modifier.padding(3.dp).size(7.dp).clip(CircleShape).background(
                    if (i == pager.currentPage) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.outlineVariant))
            }
        }
        Button(onClick = onGetStarted, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.get_started))
        }
    }
}
