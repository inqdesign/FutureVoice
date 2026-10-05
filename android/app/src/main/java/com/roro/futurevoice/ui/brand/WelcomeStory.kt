package com.roro.futurevoice.ui.brand

import android.content.res.Configuration
import android.graphics.Bitmap
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

// The pieces of the Welcome film (WelcomeScreen) — iOS `WelcomeStory.swift`
// (d4d1d566, 10f65de5): the backdrop, the caption that writes itself in, the
// quiet feature line under it, and the fluent self's orb. Nothing here knows
// the script.

/** The film's text colour on its cream ground: a deep blue-black. */
val StoryInk = Color(0.11f, 0.13f, 0.20f)

private val Cream = floatArrayOf(0.975f, 0.955f, 0.915f)

/**
 * A warm cream ground with the app's blue coming down from the top centre
 * like a sky — deepest at the top edge, paling into the cream — near-black
 * at the very top so the status bar sinks into it, and film grain over
 * everything. It only drifts, slowly.
 */
@Composable
fun StoryBackdrop(modifier: Modifier = Modifier, still: Boolean = false) {
    var t by remember { mutableFloatStateOf(0f) }
    if (!still) {
        LaunchedEffect(Unit) {
            var last = 0L
            while (true) {
                withFrameNanos { now ->
                    if (last != 0L) t = (t + (now - last) / 1e9f) % 10_000f
                    last = now
                }
                // ~30 fps is plenty for a drift this slow.
                delay(33)
            }
        }
    }
    val grain = remember { ShaderBrush(ImageShader(grainTile(), TileMode.Repeated, TileMode.Repeated)) }
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        drawRect(Color(Cream[0], Cream[1], Cream[2]))
        // The sky: a wide ellipse centred above the top edge, so only its
        // soft lower half comes down into the screen.
        val r = h * 0.62f
        val cx = w * (0.5f + 0.04f * sin(t * 0.05f))
        val cy = h * (-0.16f + 0.02f * cos(t * 0.04f))
        scale(scaleX = 1.2f, scaleY = 1f, pivot = Offset(cx, cy)) {
            drawCircle(Brush.radialGradient(colorStops = SkyStops, center = Offset(cx, cy), radius = r),
                radius = r, center = Offset(cx, cy))
        }
        // Night at the very top.
        drawRect(Brush.verticalGradient(colorStops = NightStops, startY = 0f, endY = h * 0.26f),
            size = androidx.compose.ui.geometry.Size(w, h * 0.26f))
        // A little warmth gathering at the bottom, under the buttons.
        drawRect(Brush.verticalGradient(
            listOf(Color.Transparent, Color(0.96f, 0.88f, 0.78f).copy(alpha = 0.7f)),
            startY = h * 0.55f, endY = h))
        // Static film grain: mid-grey changes nothing under overlay.
        drawRect(grain, alpha = 0.18f, blendMode = BlendMode.Overlay)
    }
}

private fun grainTile(): androidx.compose.ui.graphics.ImageBitmap {
    val side = 160
    val px = IntArray(side * side) {
        val g = Random.nextInt(256)
        (0xFF shl 24) or (g shl 16) or (g shl 8) or g
    }
    // Scale 2 as on iOS: each speckle is two device pixels wide.
    val bmp = Bitmap.createBitmap(px, side, side, Bitmap.Config.ARGB_8888)
    return Bitmap.createScaledBitmap(bmp, side * 2, side * 2, false).asImageBitmap()
}

/** Evenly spaced key colours through a Catmull-Rom curve, sampled finely:
 *  no kinks anywhere, so no Mach bands. */
private fun smoothStops(keys: List<FloatArray>, samples: Int = 40): Array<Pair<Float, Color>> {
    fun at(i: Int) = keys[i.coerceIn(0, keys.size - 1)]
    fun cr(a: Float, b: Float, c: Float, d: Float, t: Float): Float {
        val v = 0.5f * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t +
            (3 * b - a - 3 * c + d) * t * t * t)
        return v.coerceIn(0f, 1f)
    }
    val segs = (keys.size - 1).toFloat()
    return Array(samples + 1) { n ->
        val x = n.toFloat() / samples
        val f = x * segs
        val i = min(f.toInt(), keys.size - 2)
        val t = f - i
        val p0 = at(i - 1); val p1 = at(i); val p2 = at(i + 1); val p3 = at(i + 2)
        x to Color(cr(p0[0], p1[0], p2[0], p3[0], t), cr(p0[1], p1[1], p2[1], p3[1], t),
            cr(p0[2], p1[2], p2[2], p3[2], t), cr(p0[3], p1[3], p2[3], p3[3], t))
    }
}

private val SkyStops = smoothStops(listOf(
    floatArrayOf(0.06f, 0.26f, 0.90f, 1f), floatArrayOf(0.14f, 0.38f, 0.96f, 1f),
    floatArrayOf(0.40f, 0.60f, 1.00f, 1f), floatArrayOf(0.72f, 0.82f, 1.00f, 1f),
    floatArrayOf(Cream[0], Cream[1], Cream[2], 0f),
))

private val NightStops = smoothStops(listOf(
    floatArrayOf(0.015f, 0.03f, 0.10f, 1f), floatArrayOf(0.03f, 0.10f, 0.36f, 0.6f),
    floatArrayOf(0.05f, 0.20f, 0.70f, 0f),
))

/**
 * A caption that writes itself in, word by word: each word rises a few dp
 * out of a soft blur. A language without spaces (Japanese, Chinese) comes in
 * phrase-sized pieces cut at word boundaries. `\n` breaks the line; a line
 * too long for the width wraps, centred and BALANCED.
 */
@Composable
fun RevealText(text: String, still: Boolean = false) {
    val lines = remember(text) {
        text.split("\n").map { line ->
            if (line.contains(" ")) line.split(" ").filter { it.isNotEmpty() } else unspacedPieces(line)
        }
    }
    val total = lines.sumOf { it.size }
    // The whole line arrives in about a second and a half however long it is.
    val stagger = min(0.12, 1.5 / max(total, 1))
    val spaced = text.contains(" ")
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    Column(
        Modifier.clearAndSetSemantics { contentDescription = text.replace("\n", " ") },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        var before = 0
        lines.forEachIndexed { li, tokens ->
            val start = before
            before += tokens.size
            CenteredFlow(
                spacing = if (spaced) 7.dp else 0.dp,
                lineSpacing = 6.dp,
                closers = tokens.map { it.length == 1 && it in LineClosers },
                modifier = Modifier.alpha(if (li == 0 || lines.size == 1) 1f else 0.78f),
            ) {
                tokens.forEachIndexed { ti, token ->
                    val delayMs = if (still) 0 else ((start + ti) * stagger * 1000).toInt()
                    val dur = if (still) 400 else 900
                    val p by animateFloatAsState(if (shown) 1f else 0f,
                        tween(dur, delayMs, LinearOutSlowInEasing), label = "word")
                    val moving = if (still) 0f else 1f - p
                    Text(
                        token,
                        color = StoryInk,
                        fontSize = 25.sp,
                        lineHeight = 31.sp,
                        fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .graphicsLayer {
                                alpha = p
                                translationY = moving * 7.dp.toPx()
                            }
                            .blur((moving * 9).dp),
                    )
                }
            }
        }
    }
}

private const val LineClosers = "、。，．！？…」』）〉》,.!?:;)"

/**
 * Where a line without spaces (Japanese, Chinese) may break: at word
 * boundaries, never inside a word. Punctuation rides on the word before it
 * (an opening bracket on the word after), and in Japanese a run of hiragana —
 * a particle, an ending — stays with the word it follows.
 */
fun unspacedPieces(line: String): List<String> {
    val hasKana = line.any { it.code in 0x3040..0x30FF }
    val it = android.icu.text.BreakIterator.getWordInstance(
        android.icu.util.ULocale(if (hasKana) "ja" else "zh"))
    it.setText(line)
    val raw = mutableListOf<String>()
    var s = it.first()
    var e = it.next()
    while (e != android.icu.text.BreakIterator.DONE) {
        raw += line.substring(s, e)
        s = e; e = it.next()
    }
    fun isPunct(x: String) = x.isNotEmpty() && x.all { c ->
        when (Character.getType(c).toByte()) {
            Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
            Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
            Character.OTHER_PUNCTUATION, Character.MATH_SYMBOL, Character.CURRENCY_SYMBOL,
            Character.MODIFIER_SYMBOL, Character.OTHER_SYMBOL -> true
            else -> c == '…'
        }
    }
    fun isHiragana(x: String) = x.isNotEmpty() && x.all { c -> c.code in 0x3040..0x309F }
    val opening = setOf("「", "『", "（", "(", "【", "〈", "《", "“", "‘")
    val out = mutableListOf<String>()
    var leading = ""
    for (t in raw) {
        if (t.isBlank()) continue
        if (t in opening) { leading += t; continue }
        val last = out.lastOrNull()
        if (last != null && (isPunct(t) || (hasKana && isHiragana(t) && !isPunct(last.takeLast(1))))) {
            out[out.size - 1] = last + t
        } else {
            out += leading + t
            leading = ""
        }
    }
    if (leading.isNotEmpty()) out += leading
    return if (out.isEmpty()) listOf(line) else out
}

/**
 * Lays its children out in rows, wrapping at the width, each row centred —
 * and BALANCED: when the content needs more than one row, the narrowest
 * width that still fits in that many rows, so a wrapped line splits into
 * halves of a similar length instead of leaving one word alone (CSS's
 * `text-wrap: balance`). A child flagged in [closers] never starts a row.
 */
@Composable
fun CenteredFlow(
    modifier: Modifier = Modifier,
    spacing: Dp = 6.dp,
    lineSpacing: Dp = 4.dp,
    closers: List<Boolean> = emptyList(),
    content: @Composable () -> Unit,
) {
    Layout(content, modifier) { measurables, constraints ->
        val placeables = measurables.map { it.measure(Constraints()) }
        val gap = spacing.roundToPx()
        val lineGap = lineSpacing.roundToPx()
        val widths = placeables.map { it.width }

        fun rows(width: Int): List<List<Int>> {
            val rows = mutableListOf<List<Int>>()
            var row = mutableListOf<Int>()
            var rowW = 0
            for (i in widths.indices) {
                val added = if (row.isEmpty()) widths[i] else rowW + gap + widths[i]
                if (added > width && row.isNotEmpty() && !closers.getOrElse(i) { false }) {
                    rows += row
                    row = mutableListOf(i); rowW = widths[i]
                } else {
                    row += i; rowW = added
                }
            }
            if (row.isNotEmpty()) rows += row
            return rows
        }
        val maxW = if (constraints.hasBoundedWidth) constraints.maxWidth else Int.MAX_VALUE
        val greedy = rows(maxW)
        val chosen = if (greedy.size > 1 && constraints.hasBoundedWidth) {
            var lo = widths.maxOrNull() ?: 0
            var hi = maxW
            while (hi - lo > 1) {
                val mid = (lo + hi) / 2
                if (rows(mid).size <= greedy.size) hi = mid else lo = mid
            }
            rows(hi)
        } else greedy
        fun rowWidth(r: List<Int>) = r.sumOf { widths[it] } + gap * (r.size - 1).coerceAtLeast(0)
        fun rowHeight(r: List<Int>) = r.maxOf { placeables[it].height }
        val contentW = chosen.maxOfOrNull(::rowWidth) ?: 0
        val layoutW = if (constraints.hasBoundedWidth) max(min(contentW, maxW), constraints.minWidth) else contentW
        val layoutH = chosen.sumOf(::rowHeight) + lineGap * (chosen.size - 1).coerceAtLeast(0)
        layout(layoutW, max(layoutH, constraints.minHeight)) {
            var y = 0
            for (r in chosen) {
                val rh = rowHeight(r)
                var x = (layoutW - rowWidth(r)) / 2
                for (i in r) {
                    val p = placeables[i]
                    p.place(x, y + (rh - p.height) / 2)
                    x += p.width + gap
                }
                y += rh + lineGap
            }
        }
    }
}

/**
 * What the app does, said quietly under a line: one symbol, a few words,
 * arriving after the caption has. One size everywhere, the closing frame
 * included (iOS e57dc08e).
 */
@Composable
fun Glimpse(icon: ImageVector, label: String, delayMs: Int = 2800, still: Boolean = false) {
    val shape = RoundedCornerShape(50)
    Row(
        Modifier
            .arrive(delayMs, still)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.55f))
            .border(0.5.dp, StoryInk.copy(alpha = 0.10f), shape)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val tint = StoryInk.copy(alpha = 0.75f)
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(16.dp))
        Text(label, color = tint, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

/** Fades a view up into place after a delay, once, when it appears. */
@Composable
fun Modifier.arrive(delayMs: Int, still: Boolean = false): Modifier {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val p by animateFloatAsState(if (shown) 1f else 0f,
        tween(800, if (still) 0 else delayMs, LinearOutSlowInEasing), label = "arrive")
    return this.graphicsLayer {
        alpha = p
        translationY = if (still) 0f else (1f - p) * 8.dp.toPx()
    }
}

/**
 * The fluent self on the Welcome film: the call button's own surface. It
 * starts as a circle under the captions and, at the end, stretches into the
 * Get started button — the stretch and the blue fill are ONE motion, every
 * cell lighting as it widens. On every new beat it speaks for about as long
 * as the words take to arrive, then rests. The pixel grid is pinned to the
 * call pill's height (`virtualHeight`), so the cells keep their size while
 * the shape changes. Always drawn in the light palette (the film's ground is
 * cream whatever the phone's mode).
 */
@Composable
fun FutureselfDoor(open: Boolean, beat: Int, label: String, still: Boolean = false, onClick: () -> Unit) {
    var mode by remember { mutableStateOf(FutureselfMode.IDLE) }
    var level by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(beat, open) {
        if (open) { mode = FutureselfMode.SPEAKING; level = 1f; return@LaunchedEffect }
        level = 0f; mode = FutureselfMode.IDLE
        if (still) return@LaunchedEffect
        mode = FutureselfMode.SPEAKING
        // A speaking voice's energy: uneven syllables, not a sine.
        val end = System.currentTimeMillis() + 1800
        while (System.currentTimeMillis() < end) {
            level = 0.25f + Random.nextFloat() * 0.6f
            delay(140)
        }
        level = 0f
        mode = FutureselfMode.IDLE
    }
    val p by animateFloatAsState(if (open) 1f else 0f, tween(900, easing = FastOutSlowInEasing), label = "door")
    val labelAlpha by animateFloatAsState(if (open) 1f else 0f,
        tween(350, if (open) 600 else 0, LinearOutSlowInEasing), label = "doorLabel")
    val blue = Color(0.040f, 0.360f, 0.960f) // FutureselfTheme.BLUE, light
    val cfg = LocalConfiguration.current
    val lightCfg = remember(cfg) {
        Configuration(cfg).apply {
            uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_NO
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val side = 76.dp
        val w = lerp(side, maxWidth, p)
        val h = lerp(side, 58.dp, p)
        val shape = RoundedCornerShape(50)
        Box(
            Modifier
                .size(w, h)
                .clip(shape)
                .border(0.5.dp, StoryInk.copy(alpha = 0.10f * (1f - p)), shape)
                .then(if (open) Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = androidx.compose.material3.ripple(), onClick = onClick) else Modifier)
                .then(if (open) Modifier else Modifier.clearAndSetSemantics { }),
            contentAlignment = Alignment.Center,
        ) {
            CompositionLocalProvider(LocalConfiguration provides lightCfg) {
                Futureself(mode = mode, level = level, modifier = Modifier.fillMaxSize(),
                    theme = FutureselfTheme.BLUE, virtualHeight = 64f)
            }
            Box(Modifier.fillMaxSize().background(blue.copy(alpha = p)))
            Text(label, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.alpha(labelAlpha))
        }
    }
}

