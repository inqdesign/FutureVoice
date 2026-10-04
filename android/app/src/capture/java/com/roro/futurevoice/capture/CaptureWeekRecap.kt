package com.roro.futurevoice.capture

import android.app.Activity
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.WeekRecap
import com.roro.futurevoice.data.WeekRecapBuilder
import com.roro.futurevoice.ui.WeekRecapDeck
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * "Your week" (iOS `week-recap` / `week-recap-quiet`): every card dealt from a
 * hand-written week — the real one is built from logs a capture run doesn't
 * have. `--ei recappage N` opens on card N; the coach is pre-written so the
 * capture never waits on the network.
 */
object CaptureWeekRecap {

    private const val DAY = 86_400_000L
    private const val HOUR = 3_600_000L

    fun sample(c: Context): WeekRecap {
        val (start, end) = WeekRecapBuilder.lastWeek(c)
        fun day(n: Int, h: Int) = start + n * DAY + h * HOUR
        return WeekRecap(
            start = start, end = end,
            activeDays = listOf(true, true, false, true, true, false, true),
            streak = 3,
            talkSeconds = 42 * 60, previousTalkSeconds = 28 * 60,
            talks = listOf(
                WeekRecap.TalkLine("Moving flats in Berlin", day(0, 2), 12, "free"),
                WeekRecap.TalkLine("Asking the landlord about the deposit", day(1, 9), 7, "scenario"),
                WeekRecap.TalkLine("Why rents keep rising", day(3, 10), 9, "news"),
                WeekRecap.TalkLine("Catching up with Jenny", day(4, 11), 8, "person"),
                WeekRecap.TalkLine("The weekend plan", day(6, 1), 6, "free")),
            usedCount = 4,
            used = listOf(
                WeekRecap.Evidence("end up", "I ended up carrying most of the boxes myself."),
                WeekRecap.Evidence("push back on", "I pushed back on the deadline a little."),
                WeekRecap.Evidence("chore", "Cleaning the kitchen is my least favourite chore.")),
            cardsCleared = 12, wordsKnown = 9, expressionsKnown = 4,
            shadowTakes = 17, shadowAverage = 81, previousShadowAverage = 74,
            scenes = 3,
            nowYours = listOf("deposit", "landlord", "sublet", "boiler", "catch up on", "chore", "exhausting", "end up"),
            sentencesGot = listOf("I ended up carrying most of the boxes myself.", "I've lived here for two years."),
            newExpressionCount = 7,
            newExpressions = listOf(
                WeekRecap.Evidence("catch up on", "You can always catch up on the unpacking later."),
                WeekRecap.Evidence("walk you through", "Let me walk you through what the landlord actually needs."),
                WeekRecap.Evidence("give yourself a day off", "Honestly, give yourself a day off after the move.")),
            newCards = 6,
            stumbles = listOf(
                WeekRecap.Stumble("I end up carrying", "I ended up carrying", 3),
                WeekRecap.Stumble("since two years", "for two years", 2)),
            shakyLines = emptyList(),
            testScore = 5, testTotal = 7,
            coach = WeekRecap.Coach(
                headline = "You tell stories, but in the present tense",
                insight = "When you talk about something that already happened, you slip back into the present as the story goes on. It starts in the past and ends in the present.",
                insightQuote = "Yesterday I went to the flat and the landlord says it's fine.",
                grammar = listOf(
                    WeekRecap.Coach.Pattern("Past tense drops out halfway through a story", listOf(
                        WeekRecap.Coach.Pair("the landlord says it's fine", "the landlord said it was fine"),
                        WeekRecap.Coach.Pair("I end up carrying", "I ended up carrying"),
                        WeekRecap.Coach.Pair("then she ask me", "then she asked me")),
                        "Once a story starts with “yesterday” or “last week”, every verb stays in the past until it ends."),
                    WeekRecap.Coach.Pattern("“the” before a place you both know", listOf(
                        WeekRecap.Coach.Pair("went to kitchen", "went to the kitchen"),
                        WeekRecap.Coach.Pair("called landlord", "called the landlord")),
                        "If you could point at it, it takes “the”.")),
                upgrades = listOf(
                    WeekRecap.Coach.Upgrade("very tired", 5, "exhausted",
                        "I was very tired after the move.", "I was exhausted after the move.",
                        "One word does the work of two. Use it when tired isn't strong enough."),
                    WeekRecap.Coach.Upgrade("good", 9, "decent",
                        "The flat is good for the price.", "The flat is decent for the price.",
                        "Good, but not great: exactly what you meant about the flat.")),
                plan = listOf(
                    "Tell the story of the move again, and keep every verb in the past until the end.",
                    "Say “exhausted” once in your next talk instead of “very tired”.",
                    "Take this week's test. The two you missed are back.")),
        )
    }

    fun quiet(c: Context): WeekRecap {
        val (start, end) = WeekRecapBuilder.lastWeek(c)
        return WeekRecap(
            start = start, end = end, activeDays = List(7) { false }, streak = 0,
            talkSeconds = 0, previousTalkSeconds = 12 * 60, talks = emptyList(),
            usedCount = 0, used = emptyList(), cardsCleared = 0, wordsKnown = 0, expressionsKnown = 0,
            shadowTakes = 0, scenes = 0, nowYours = emptyList(), sentencesGot = emptyList(),
            newExpressionCount = 0, newExpressions = emptyList(), newCards = 0,
            stumbles = emptyList(), shakyLines = emptyList(),
        )
    }

    private fun deck(make: (Context) -> WeekRecap): @Composable (Context) -> Unit = { c ->
        val page = (c as? Activity)?.intent?.getIntExtra("recappage", 0) ?: 0
        Box(Modifier.fillMaxSize().background(AppSurfaces.ground).statusBarsPadding()) {
            WeekRecapDeck(recap = make(c),
                level = CefrLevel.from(LanguageScope.level(c, LanguageScope.active(c), "b1")),
                startPage = page, writeCoach = false, onClose = {})
        }
    }

    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "week-recap" to deck(::sample),
        "week-recap-quiet" to deck(::quiet),
    )
}
