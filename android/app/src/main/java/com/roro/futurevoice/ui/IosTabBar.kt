package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.ui.graphics.lerp
import androidx.compose.runtime.getValue
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.Spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The iOS 26 tab bar (`RootTabView`), measured off the iOS 26 simulator at
 * 3 px/pt (`-capture tabs`, ko): a floating capsule 21pt in from the edges,
 * 62pt tall, near-white with a soft shadow. The selected tab sits in a grey
 * pill 76×51pt, 4pt in from the capsule's end and 5.5pt from its top and
 * bottom — WIDER than a tab's own step, so the outer two tabs' centres sit
 * 42pt in from the capsule's ends and the five centres step evenly between.
 * Glyph ink is 21–24pt tall (SF Symbols are larger than Material's 24dp box,
 * whose ink is ~20dp — hence the per-icon sizes below), centred 23.7pt down;
 * the label's ink starts 40.4pt down, 8.7pt tall: SF ~10pt MEDIUM, and it
 * does not grow with Dynamic Type, so the label here is fixed, not `sp`.
 * Selected icon and label in the accent, the rest in the primary ink.
 * Icons are the SF Symbols' nearest Material shapes: waveform · music.mic ·
 * play.circle.fill · book.fill · chart.bar.fill.
 */
/** How much room the floating bar needs below a page's last item, above the
 *  navigation inset: the capsule plus its margins (the bar's own height, as
 *  iOS's safe-area inset is), then 24 dp of air — iOS Talk's
 *  `.contentMargins(.bottom, 24)`. With 12 dp the last card ended inside the
 *  scroll feather and read as cut off under the bar. */
internal val IosTabBarClearance = 62.dp + 6.dp + 8.dp + 24.dp

private val PillWidth = 76.dp
private val PillInsetX = 4.dp
private val PillInsetY = 5.5.dp
/** Centre of the glyph ink, from the capsule's top. */
private val IconCenterY = 23.7.dp
/** Top of the label's line box, from the capsule's top — tuned so its INK
 *  starts 40.4dp down, where iOS's does. */
private val LabelTop = 37.8.dp
private const val LabelPt = 9.5f

@Composable
internal fun IosTabBar(selected: HomeTab, onSelect: (HomeTab) -> Unit, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.luminance() < 0.5f
    val capsule = if (dark) scheme.surfaceContainerHigh else scheme.surfaceContainerLowest
    val pill = if (dark) scheme.surfaceContainerHighest else scheme.surfaceContainerHigh
    val shape = RoundedCornerShape(percent = 50)
    val tabs = HomeTab.entries
    val density = androidx.compose.ui.platform.LocalDensity.current
    // iOS's tab labels ignore Dynamic Type: a fixed size, whatever the
    // learner's font scale.
    val labelSize = (LabelPt / density.fontScale).sp
    // The highlight is ONE pill that slides to the picked tab, the way iOS's
    // does — a spring that settles without overshooting (no bounce).
    val index by animateFloatAsState(
        targetValue = tabs.indexOf(selected).toFloat(),
        animationSpec = spring(dampingRatio = 0.82f, stiffness = Spring.StiffnessMediumLow),
        label = "tabPill",
    )
    Box(
        modifier.fillMaxWidth()
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(start = 21.dp, end = 21.dp, top = 6.dp, bottom = 8.dp),
    ) {
        BoxWithConstraints(
            Modifier.fillMaxWidth().height(62.dp)
                .shadow(18.dp, shape, ambientColor = Color.Black.copy(alpha = 0.12f),
                    spotColor = Color.Black.copy(alpha = 0.12f))
                .background(capsule, shape),
        ) {
            val edge = PillInsetX + PillWidth / 2
            val step = (maxWidth - edge * 2) / (tabs.size - 1)
            Box(
                Modifier.offset(x = PillInsetX + step * index, y = PillInsetY)
                    .width(PillWidth).height(62.dp - PillInsetY * 2)
                    .background(pill, shape),
            )
            Row(Modifier.fillMaxSize().padding(horizontal = edge - step / 2)) {
                tabs.forEachIndexed { i, t ->
                    // Colour follows the pill as it passes, rather than
                    // snapping when the tap lands.
                    val nearness = (1f - kotlin.math.abs(index - i)).coerceIn(0f, 1f)
                    val tint = lerp(scheme.onSurface, scheme.primary, nearness)
                    Box(
                        Modifier.weight(1f).fillMaxHeight()
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null, role = Role.Tab,
                            ) { onSelect(t) },
                    ) {
                        Box(
                            Modifier.align(Alignment.TopCenter).offset(y = IconCenterY - 16.dp)
                                .size(32.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(t.symbol, contentDescription = null, tint = tint,
                                modifier = Modifier.size(t.symbolSize))
                        }
                        Text(stringResource(t.label), color = tint, fontSize = labelSize,
                            fontWeight = FontWeight.Normal, maxLines = 1, softWrap = false,
                            style = androidx.compose.ui.text.TextStyle(
                                platformStyle = androidx.compose.ui.text.PlatformTextStyle(
                                    includeFontPadding = false),
                            ),
                            modifier = Modifier.align(Alignment.TopCenter).offset(y = LabelTop))
                    }
                }
            }
        }
    }
}

/** Each Material glyph's box, sized so its INK is as tall as the SF Symbol's
 *  on iOS (waveform 24 · music.mic 23.3 · play.circle 23 · book 20.7 ·
 *  chart.bar 21.3 pt); Material's play circle fills 84% of its box. The
 *  waveform, mic, book and chart are drawn here at their iOS size. */
private val HomeTab.symbolSize: androidx.compose.ui.unit.Dp
    get() = when (this) {
        HomeTab.TALK -> 32.dp
        HomeTab.SPEECH -> 24.dp
        HomeTab.WATCH -> 27.3.dp
        HomeTab.PRACTICE -> 32.dp
        HomeTab.PROGRESS -> 32.dp
    }

private val HomeTab.symbol: ImageVector
    get() = when (this) {
        HomeTab.TALK -> TabWaveform
        // SF `music.mic`: a hand-held stage mic.
        HomeTab.SPEECH -> MusicMic
        HomeTab.WATCH -> Icons.Filled.PlayCircle
        HomeTab.PRACTICE -> BookFill
        HomeTab.PROGRESS -> ChartBarFill
    }

/** SF `book.fill` — two solid pages split by a thin spine, each with a
 *  domed top and a bottom edge that bows up in the middle (traced off the
 *  iOS bar). Material's MenuBook draws text lines on the pages, which iOS
 *  doesn't. */
private val BookFill: ImageVector by lazy {
    ImageVector.Builder(name = "book.fill", defaultWidth = 24.dp, defaultHeight = 24.dp,
        viewportWidth = 24f, viewportHeight = 24f)
        .addPath(pathData = addPathNodes(
            "M2,7C2,5.3 4.1,4.3 6.7,4.3C9.3,4.3 11.4,5.3 11.4,7V19.6" +
                "C10.2,18.3 8.6,17.6 6.7,17.6C4.8,17.6 3.2,18.3 2,19.6Z" +
                "M22,7C22,5.3 19.9,4.3 17.3,4.3C14.7,4.3 12.6,5.3 12.6,7V19.6" +
                "C13.8,18.3 15.4,17.6 17.3,17.6C19.2,17.6 20.8,18.3 22,19.6Z"),
            fill = SolidColor(Color.Black))
        .build()
}

/** SF `chart.bar.fill` — three thick rounded bars, measured off the iOS
 *  bar: 29 × 21.3pt of ink, bars 8 · 8.3 · 8.3 wide with 2.3 / 2 gaps and
 *  14.7 / 18 / 21.3 tall, centred in a 32 box. Material has no equivalent
 *  (its bar icons are thin strokes). */
private val ChartBarFill: ImageVector by lazy {
    fun bar(l: Float, t: Float, r: Float, b: Float, k: Float = 1.8f) =
        "M${l + k},${t}H${r - k}A$k,$k 0 0 1 $r,${t + k}V${b - k}A$k,$k 0 0 1 ${r - k},${b}" +
            "H${l + k}A$k,$k 0 0 1 $l,${b - k}V${t + k}A$k,$k 0 0 1 ${l + k},${t}Z"
    ImageVector.Builder(name = "chart.bar.fill", defaultWidth = 32.dp, defaultHeight = 32.dp,
        viewportWidth = 32f, viewportHeight = 32f)
        .addPath(pathData = addPathNodes(
            bar(1.5f, 11.95f, 9.5f, 26.65f) + bar(11.8f, 8.65f, 20.1f, 26.65f) +
                bar(22.1f, 5.35f, 30.5f, 26.65f)), fill = SolidColor(Color.Black))
        .build()
}

/** SF `waveform` — six thin rounded bars, measured off the iOS bar:
 *  1.7–2pt wide on a ~3.8pt pitch, 6 · 15 · 24 · 12 · 18.7 · 8pt tall about
 *  one centre line, 21 × 24pt of ink, centred in a 32 box. Material's
 *  GraphicEq has five fat bars and read as a different glyph. */
private val TabWaveform: ImageVector by lazy {
    val bars = listOf(5.5f to 6f, 9.17f to 15f, 13.17f to 24f, 16.83f to 12f, 20.83f to 18.7f, 24.5f to 8f)
    val w = 1.85f
    val r = w / 2
    val d = bars.joinToString("") { (x, h) ->
        val t = 16f - h / 2
        val b = 16f + h / 2
        "M$x,${t + r}A$r,$r 0 0 1 ${x + w},${t + r}V${b - r}A$r,$r 0 0 1 $x,${b - r}Z"
    }
    ImageVector.Builder(name = "waveform", defaultWidth = 32.dp, defaultHeight = 32.dp,
        viewportWidth = 32f, viewportHeight = 32f)
        .addPath(pathData = addPathNodes(d), fill = SolidColor(Color.Black))
        .build()
}

/** SF `music.mic` — a hand-held stage mic held at 45°, head up and to the
 *  right: a ball head split by a clear band, an outlined handle that ends in
 *  a short tip, and a straight stand dropping from the handle. Drawn upright
 *  and turned 45° about the centre; the stand is drawn after the turn so it
 *  stays vertical. Ink ≈ 22.5 × 23.3 in a 24 box, as iOS's. */
private val MusicMic: ImageVector by lazy {
    val ink = SolidColor(Color.Black)
    ImageVector.Builder(name = "music.mic", defaultWidth = 24.dp, defaultHeight = 24.dp,
        viewportWidth = 24f, viewportHeight = 24f)
        .addGroup(rotate = 45f, pivotX = 12f, pivotY = 12f)
        // Head above the band, then the sliver below it.
        .addPath(pathData = addPathNodes("M6.633,5.7A5.6,5.6 0 1 1 17.367,5.7Z"), fill = ink)
        .addPath(pathData = addPathNodes("M7.15,6.9A5.6,5.6 0 0 0 16.85,6.9Z"), fill = ink)
        // Handle: an outline that narrows to the tip.
        .addPath(pathData = addPathNodes("M10.15,9.4L10.95,25L13.05,25L13.85,9.4"),
            stroke = ink, strokeLineWidth = 1.6f,
            strokeLineJoin = androidx.compose.ui.graphics.StrokeJoin.Round)
        .addPath(pathData = addPathNodes("M12,25.6L12,27.1"), stroke = ink, strokeLineWidth = 1.9f,
            strokeLineCap = androidx.compose.ui.graphics.StrokeCap.Round)
        .clearGroup()
        .addPath(pathData = addPathNodes("M12.4,13.6L12.05,22.6"), stroke = ink, strokeLineWidth = 1.7f,
            strokeLineCap = androidx.compose.ui.graphics.StrokeCap.Round)
        .build()
}

/** The wash a scrolling page dissolves into at the bottom edge (iOS
 *  `ScrollEdgeFeather`, `ramp` 72 / `solid` 44), drawn to the physical screen
 *  edge — through the navigation inset — so the strip beside the floating bar
 *  is feathered too. It takes no touches. */
@Composable
internal fun ScrollEdgeFeather(color: Color, modifier: Modifier = Modifier,
                               ramp: androidx.compose.ui.unit.Dp = 72.dp,
                               solid: androidx.compose.ui.unit.Dp = 44.dp) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val nav = with(density) { WindowInsets.navigationBars.getBottom(density).toDp() }
    Box(
        modifier.fillMaxWidth().height(ramp + solid + nav)
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(
                0f to color.copy(alpha = 0f),
                (ramp / (ramp + solid + nav)) to color,
                1f to color,
            )),
    )
}
