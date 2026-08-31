package com.roro.futurevoice.ui.brand

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.MedicalServices
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.talk.ShadowScore
import kotlinx.coroutines.delay

/**
 * The Welcome carousel's heroes (`WelcomeHeroes.swift`) — previews built from
 * the SAME components the real screens use, never generic icons. Each one
 * plays itself so the pitch is seen working, not described.
 */

/** 1 · Who is on the other end, and in whose voice. */
@Composable
fun FutureselfHero(modifier: Modifier = Modifier) {
    // The opening of the intro opener, split where a real call breathes.
    // MATERIAL, so it stays in the target language (English sample here, as
    // on iOS).
    val lines = remember {
        listOf(
            "Hi. I'm the future you — the one who speaks English fluently.",
            "I can't wait for all the talks ahead of us.",
            "So — what are you up to these days?",
        )
    }
    val context = LocalContext.current
    val theme = remember { FutureselfTheme.stored(context) }
    var mode by remember { mutableStateOf(FutureselfMode.IDLE) }
    var level by remember { mutableFloatStateOf(0f) }
    var line by remember { mutableIntStateOf(0) }
    var showing by remember { mutableStateOf(false) }
    val shownLevel by animateFloatAsState(level, label = "level")

    // One turn of a call: it speaks, you answer, it thinks, it speaks again.
    LaunchedEffect(Unit) {
        while (true) {
            for (i in lines.indices) {
                mode = FutureselfMode.SPEAKING; level = 0.7f
                line = i; showing = true
                delay(2800)
                if (i == lines.lastIndex) break
                // You answer, it thinks — the line it just said STAYS up: a
                // transcript doesn't erase itself between turns.
                mode = FutureselfMode.LISTENING; level = 0.85f
                delay(1600)
                mode = FutureselfMode.THINKING; level = 0f
                delay(800)
            }
            mode = FutureselfMode.IDLE; level = 0f
            delay(1400)
            showing = false
            delay(500)
        }
    }

    Column(
        modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.fillMaxWidth().height(96.dp)) {
            if (showing) {
                DialogueLine(speaker = DialogueSpeaker.OTHER, name = "Future self") {
                    Text(lines[line])
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Futureself(
            mode = mode, level = shownLevel, theme = theme,
            modifier = Modifier.size(196.dp).clip(CircleShape)
                .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape),
        )
        Text(
            when (mode) {
                FutureselfMode.IDLE -> "Tap to talk"
                FutureselfMode.LISTENING -> "Listening…"
                FutureselfMode.THINKING -> "Thinking…"
                FutureselfMode.SPEAKING -> "Speaking…"
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.weight(1f))
    }
}

private data class HeroRow(val icon: ImageVector, val title: String, val caption: String)

/** 2 · And what there is to talk about — the Discover section, mirrored. */
@Composable
fun HomeHero(modifier: Modifier = Modifier) {
    val news = remember {
        listOf(
            HeroRow(Icons.Filled.Memory, "Did you hear about OpenAI's model hacking a company?", "AI / Tech"),
            HeroRow(Icons.Filled.TrendingUp, "Germany weighs a four-day work week", "Business"),
            HeroRow(Icons.Filled.Flight, "The slow-travel comeback", "Travel"),
            HeroRow(Icons.Filled.DirectionsRun, "Why everyone suddenly runs a half marathon", "Sports"),
        )
    }
    val scenarios = remember {
        listOf(
            HeroRow(Icons.Filled.LocalCafe, "Ordering at a busy café", "with Sofia"),
            HeroRow(Icons.Filled.Schedule, "Asking your boss for Friday off", "with Mina"),
            HeroRow(Icons.Filled.MedicalServices, "Describing a cough that won't go", "with Dr. Park"),
            HeroRow(Icons.Filled.Home, "The kitchen tap has been dripping all week", "with Alex"),
        )
    }
    var onScenarios by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (true) { delay(3600); onScenarios = !onScenarios }
    }
    Column(modifier.fillMaxSize().padding(top = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SegmentChip("News", !onScenarios) { onScenarios = false }
            SegmentChip("Scenarios", onScenarios) { onScenarios = true }
        }
        Column(Modifier.padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            (if (onScenarios) scenarios else news).forEach { r ->
                DiscoverRow(title = r.title, caption = r.caption, icon = r.icon,
                    accent = if (onScenarios) Books.scenarios else Books.topics)
            }
        }
    }
}

/** 3 · The talk, bound into your own textbook. */
@Composable
fun BookHero(modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        BookCard(
            title = "Asking the landlord for the deposit back",
            origin = "Scenario", accent = Books.scenarios,
            detail = "12 of 19 mastered", progress = 12f / 19f,
        )
        HeroPanel {
            Text("Words", style = MaterialTheme.typography.titleSmall)
            listOf("deposit" to "the money held during a tenancy",
                "wear and tear" to "normal damage from regular use",
                "deducted" to "taken off the total").forEach { (w, note) ->
                Column(Modifier.padding(vertical = 4.dp)) {
                    Text(w, style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium)
                    Text(note, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** 4 · Said back in your voice, until it sticks. */
@Composable
fun ShadowHero(modifier: Modifier = Modifier) {
    val target = "I'd like the full deposit back, please."
    val attempts = remember {
        listOf("I like the full deposit back please" to 78,
               "I'd like the full deposit back, please" to 100)
    }
    var index by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(2600); index = (index + 1) % attempts.size } }
    val (said, score) = attempts[index]
    val analysis = remember(said) { ShadowScore.analyze(target, said) }
    val ops = remember(analysis) { ShadowScore.targetOps(analysis.steps) }
    val words = remember { target.split(" ") }
    val spans = remember { ShadowScore.tokenSpans(words) }

    Column(modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Text(buildAnnotatedString {
            words.forEachIndexed { i, w ->
                val range = spans.getOrNull(i) ?: IntRange.EMPTY
                val missed = !range.isEmpty() && range.all {
                    ops.getOrNull(it)?.let { op -> op != ShadowScore.DiffOp.MATCH } == true
                }
                if (missed) {
                    pushStyle(SpanStyle(color = Color(0xFFB3261E),
                        textDecoration = TextDecoration.Underline))
                    append(w); pop()
                } else append(w)
                if (i != words.lastIndex) append(" ")
            }
        }, style = MaterialTheme.typography.titleLarge)
        Text("$score", style = MaterialTheme.typography.displaySmall,
            color = if (score >= 90) Books.mastery else MaterialTheme.colorScheme.primary)
        Text(said, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
    }
}

/** 5 · A level measured, not guessed. */
@Composable
fun LevelHero(modifier: Modifier = Modifier) {
    var reassessed by remember { mutableStateOf(false) }
    var progress by remember { mutableFloatStateOf(0.55f) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(2600); progress = 1f
            delay(900); reassessed = true
            delay(2600); reassessed = false; progress = 0.55f
            delay(900)
        }
    }
    val level = if (reassessed) "B2" else "B1"
    Column(modifier.fillMaxSize().padding(horizontal = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Spacer(Modifier.weight(1f))
        HeroPanel {
            Text("Estimated level", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(level, style = DisplayFace.style(level,
                MaterialTheme.typography.displayMedium),
                color = MaterialTheme.colorScheme.primary)
            Text(
                if (reassessed) "Clear, detailed talk on many topics, including some abstract ones."
                else "Familiar topics fluently enough to get by, and tell a simple story.",
                style = MaterialTheme.typography.bodyMedium)
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Row(Modifier.fillMaxWidth()) {
                Text("Next assessment", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f))
                Text("New talk ${Math.round(progress * 10)}/10 min",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
        }
        HeroPanel {
            Text("Across skills", style = MaterialTheme.typography.titleSmall)
            listOf("Vocabulary" to level, "Fluency" to "≈B1", "Grammar" to "≈B2").forEach { (k, v) ->
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
                    Text(k, style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f))
                    Text(v, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun HeroPanel(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(AppSurfaces.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) { content() }
}
