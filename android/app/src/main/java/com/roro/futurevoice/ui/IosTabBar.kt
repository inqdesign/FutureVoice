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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.MicExternalOn
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
 * The iOS 26 tab bar (`RootTabView`), measured off the App Store screenshot:
 * a floating capsule ~21pt in from the edges, 62pt tall, near-white with a
 * soft shadow; the selected tab sits in a lighter-grey pill with its icon and
 * label in the accent, the rest in the primary ink. Icons are the SF Symbols'
 * nearest Material shapes: waveform · play.circle.fill · book.fill ·
 * chart.bar.fill.
 */
/** How much room the floating bar needs below a page's last item, above the
 *  navigation inset: the capsule plus its margins. */
internal val IosTabBarClearance = 62.dp + 6.dp + 8.dp + 12.dp

@Composable
internal fun IosTabBar(selected: HomeTab, onSelect: (HomeTab) -> Unit, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.luminance() < 0.5f
    val capsule = if (dark) scheme.surfaceContainerHigh else scheme.surfaceContainerLowest
    val pill = if (dark) scheme.surfaceContainerHighest else scheme.surfaceContainerHigh
    val shape = RoundedCornerShape(percent = 50)
    val tabs = HomeTab.entries
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
                .background(capsule, shape)
                .padding(4.dp),
        ) {
            val itemWidth = maxWidth / tabs.size
            Box(
                Modifier.offset(x = itemWidth * index).width(itemWidth).fillMaxHeight()
                    .background(pill, shape),
            )
            Row(Modifier.fillMaxSize()) {
                tabs.forEachIndexed { i, t ->
                    // Colour follows the pill as it passes, rather than
                    // snapping when the tap lands.
                    val nearness = (1f - kotlin.math.abs(index - i)).coerceIn(0f, 1f)
                    val tint = lerp(scheme.onSurface, scheme.primary, nearness)
                    Column(
                        Modifier.weight(1f).fillMaxHeight()
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null, role = Role.Tab,
                            ) { onSelect(t) },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(t.symbol, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
                        Spacer(Modifier.height(2.dp))
                        Text(stringResource(t.label), color = tint, fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold, maxLines = 1)
                    }
                }
            }
        }
    }
}

private val HomeTab.symbol: ImageVector
    get() = when (this) {
        HomeTab.TALK -> Icons.Filled.GraphicEq
        // SF `music.mic`: a hand-held stage mic.
        HomeTab.SPEECH -> Icons.Filled.MicExternalOn
        HomeTab.WATCH -> Icons.Filled.PlayCircle
        HomeTab.PRACTICE -> Icons.Filled.MenuBook
        HomeTab.PROGRESS -> ChartBarFill
    }

/** SF `chart.bar.fill` — three thick rounded bars, heights read off the iOS
 *  screenshot. Material has no equivalent (its bar icons are thin strokes). */
private val ChartBarFill: ImageVector by lazy {
    ImageVector.Builder(name = "chart.bar.fill", defaultWidth = 24.dp, defaultHeight = 24.dp,
        viewportWidth = 24f, viewportHeight = 24f)
        .addPath(pathData = addPathNodes("M3.60,9.20H6.60A1.6,1.6 0 0 1 8.20,10.80V18.90A1.6,1.6 0 0 1 6.60,20.50H3.60A1.6,1.6 0 0 1 2.00,18.90V10.80A1.6,1.6 0 0 1 3.60,9.20ZM10.50,6.60H13.50A1.6,1.6 0 0 1 15.10,8.20V18.90A1.6,1.6 0 0 1 13.50,20.50H10.50A1.6,1.6 0 0 1 8.90,18.90V8.20A1.6,1.6 0 0 1 10.50,6.60ZM17.40,4.00H20.40A1.6,1.6 0 0 1 22.00,5.60V18.90A1.6,1.6 0 0 1 20.40,20.50H17.40A1.6,1.6 0 0 1 15.80,18.90V5.60A1.6,1.6 0 0 1 17.40,4.00Z"), fill = SolidColor(Color.Black))
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
