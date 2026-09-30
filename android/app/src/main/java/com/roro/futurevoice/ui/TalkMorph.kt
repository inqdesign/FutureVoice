package com.roro.futurevoice.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseIn
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.lerp
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.ui.brand.DisplayFace
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * The free-talk morph (iOS `RootTabView.freeTalkProxy`): the Talk ring's
 * Futureself surface detaches and springs down onto the call screen's mic
 * pill, and back up on hang-up. A PROXY animated by hand between two measured
 * poses, exactly as iOS does it — the ring's circle (reported by the home) and
 * the call's 156×64 pill (reported by the call screen).
 *
 * The timeline is iOS's: proxy on the ring + backdrop in (220 ms) → 30 ms later
 * the spring to the pill → the call mounts only after the spring has settled
 * (400 ms), fading in over a static stage so its mount cost can't stutter the
 * morph → 250 ms later the proxy hands off to the call's own identical pill.
 * Closing plays it backwards, and the home fades back in only after the proxy
 * has landed on the ring.
 */
internal object TalkMorph {
    /** The ring's surface circle, window coordinates (the home reports it). */
    var ringRect by mutableStateOf<Rect?>(null)
    /** The call's mic pill, window coordinates — measured by the call screen
     *  and kept for the next call's fly-in. */
    var pillRect by mutableStateOf<Rect?>(null)
    /** The ring's two lines, so the proxy wears the exact label it lifts off. */
    var ringLabel by mutableStateOf("")
    var ringSub by mutableStateOf("")
    /** The call screen is drawing its pill. Android's call shows no pill
     *  while connecting, so the proxy holds the pose until there is one to
     *  hand off to — fading to nothing would drop the surface mid-morph. */
    var pillPresent by mutableStateOf(false)

    /** The proxy exists (and the home ring hides its own surface). */
    var active by mutableStateOf(false)
        private set
    private var busy = false

    /** 0 = ring pose, 1 = docked on the pill. */
    val progress = Animatable(0f)
    val backdrop = Animatable(0f)
    val callAlpha = Animatable(1f)
    val proxyAlpha = Animatable(1f)
    /** The ring's dressing — label + vignette — shed while docking. */
    val dressing = Animatable(1f)

    /** Can the morph play from here? Only when the ring was measured. */
    fun canOpen() = ringRect != null && !active && !busy

    fun open(scope: CoroutineScope, mount: () -> Unit) {
        if (!canOpen()) { mount(); return }
        busy = true
        scope.launch {
            progress.snapTo(0f); backdrop.snapTo(0f); callAlpha.snapTo(0f)
            proxyAlpha.snapTo(1f); dressing.snapTo(1f)
            active = true
            launch { backdrop.animateTo(1f, tween(220, easing = EaseOut)) }
            // One frame later, so the proxy exists at its start pose.
            delay(30)
            // iOS: .spring(response: 0.45, dampingFraction: 0.85).
            launch { progress.animateTo(1f, spring(dampingRatio = 0.85f, stiffness = 195f)) }
            launch { dressing.animateTo(0f, tween(150, easing = EaseOut)) }
            delay(400)
            mount()
            launch { callAlpha.animateTo(1f, tween(200, easing = EaseOut)) }
            delay(250)
            kotlinx.coroutines.withTimeoutOrNull(15_000) {
                androidx.compose.runtime.snapshotFlow { pillPresent }.first { it }
            }
            proxyAlpha.animateTo(0f, tween(150, easing = EaseOut))
            busy = false
        }
    }

    /** Hang-up. [unmount] takes the call away; the home comes back behind the
     *  backdrop and is revealed only once the proxy is back on the ring. */
    fun close(scope: CoroutineScope, unmount: () -> Unit) {
        if (!active || busy) { unmount(); active = false; return }
        busy = true
        scope.launch {
            proxyAlpha.animateTo(1f, tween(100, easing = EaseIn))
            backdrop.snapTo(1f)
            launch { callAlpha.animateTo(0f, tween(200, easing = EaseOut)) }
            // iOS: .spring(response: 0.4, dampingFraction: 0.9).
            launch { progress.animateTo(0f, spring(dampingRatio = 0.9f, stiffness = 247f)) }
            launch { dressing.animateTo(1f, tween(150, easing = EaseOut)) }
            delay(200)
            unmount()
            delay(250)
            backdrop.animateTo(0f, tween(250, easing = EaseOut))
            active = false
            callAlpha.snapTo(1f)
            busy = false
        }
    }
}

/**
 * The layer the morph plays on, above whatever the root is showing. The
 * backdrop is drawn only while the HOME is underneath (the call screen sits
 * on the same page colour, so the hand-off between the two is seamless).
 */
@Composable
internal fun TalkMorphOverlay(inCall: Boolean) {
    if (!TalkMorph.active) return
    val context = LocalContext.current
    val theme = remember { FutureselfTheme.stored(context) }
    val page = MaterialTheme.colorScheme.background
    val density = LocalDensity.current
    val navBottom = WindowInsets.navigationBars.getBottom(density)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        if (!inCall) {
            Box(Modifier.fillMaxSize().graphicsLayer { alpha = TalkMorph.backdrop.value }.background(page))
        }
        val dock = TalkMorph.pillRect ?: with(density) {
            // Before the first call has been measured: the call screen's pill
            // sits 20 dp + its hint line + 10 dp above the navigation inset.
            val w = 156.dp.toPx(); val h = 64.dp.toPx()
            val bottom = constraints.maxHeight - navBottom - (20 + 18 + 10).dp.toPx()
            Rect(constraints.maxWidth / 2f - w / 2f, bottom - h, constraints.maxWidth / 2f + w / 2f, bottom)
        }
        val start = TalkMorph.ringRect ?: dock
        val rect = lerp(start, dock, TalkMorph.progress.value)
        val dressing = TalkMorph.dressing.value
        Box(
            Modifier
                .offset { IntOffset(rect.left.roundToInt(), rect.top.roundToInt()) }
                .size(with(density) { rect.width.toDp() }, with(density) { rect.height.toDp() })
                .graphicsLayer { alpha = TalkMorph.proxyAlpha.value }
                .clip(CircleShape)
                .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Futureself(mode = FutureselfMode.IDLE, level = 0f, theme = theme,
                virtualHeight = 64f, modifier = Modifier.fillMaxSize())
            // At the ring pose the proxy wears the ring's exact dressing and
            // sheds it while docking — the call pill is bare.
            val dark = isSystemInDarkTheme()
            Canvas(Modifier.fillMaxSize().graphicsLayer { alpha = dressing }) {
                val r = size.minDimension / 2f
                drawCircle(Brush.radialGradient(
                    0.86f to Color.Transparent,
                    1f to Color.Black.copy(alpha = if (dark) 0.38f else 0.10f),
                    center = center, radius = r), radius = r)
            }
            Column(Modifier.graphicsLayer { alpha = dressing },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(TalkMorph.ringLabel, style = DisplayFace.style(TalkMorph.ringLabel,
                    MaterialTheme.typography.titleLarge))
                Text(TalkMorph.ringSub, style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
