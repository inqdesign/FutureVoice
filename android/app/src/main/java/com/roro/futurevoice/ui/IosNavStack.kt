package com.roro.futurevoice.ui

import androidx.activity.compose.PredictiveBackHandler
import androidx.activity.BackEventCompat
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.systemGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * iOS's `UINavigationController`, the ONE place a pushed page moves.
 *
 * Every page iOS reaches through a `NavigationLink` / `navigationDestination`
 * is drawn through this host, so push, pop and the interactive back swipe are
 * the same everywhere:
 *
 * - **Push**: the new page comes in from the right edge while the page under
 *   it drifts a third of the way left and dims a little (iOS parallax), on
 *   iOS's ~0.38 s ease-out curve. **Pop** is the same motion backwards.
 * - **Interactive back**: a drag from the left edge (the left [EdgeWidth])
 *   moves the top page WITH the finger; the page underneath slides back in
 *   from −1/3 and the top page throws a shadow on it. Let go past half the
 *   width, or with a flick, and it pops; otherwise it springs back.
 * - **System back** drives the same motion: on Android 14+ the predictive
 *   back gesture's progress (`PredictiveBackHandler`, which needs
 *   `android:enableOnBackInvokedCallback="true"`) follows the finger; on older
 *   versions, or the back button, the pop plays once the back is committed.
 *   With gesture navigation the system owns the left edge, so the edge drag
 *   above is what three-button phones (and any version) get.
 *
 * [stack] is bottom → top. The host never pops by itself: a committed back
 * calls [onPop], and the caller's state change is what removes the page —
 * the host only animates between what the stack was and what it is now.
 * A new top that wasn't in the stack is a push; a new top that WAS (and the
 * old top is gone) is a pop; anything else swaps in place. A move [animates]
 * refuses (a full-screen cover, a call, onboarding) swaps in place and is
 * never swiped away — that page keeps its own back handling.
 *
 * Pages call [NavPageBackHandler] instead of a bare `BackHandler(onBack)`:
 * it stands down while this host owns back for the page (so the system
 * gesture drives the animation) and answers itself otherwise.
 *
 * Each page keeps its saveable state (scroll position…) while it is covered,
 * as an iOS page under a push does, and loses it once popped.
 *
 * Pages under the top one get an inert back dispatcher while they are drawn
 * for a transition, so their own `BackHandler`s can't answer for the top page.
 */
@Composable
fun <K : Any> IosNavStack(
    stack: List<K>,
    onPop: () -> Unit,
    modifier: Modifier = Modifier,
    /** Whether a move between these two pages is a push/pop (true) or an
     *  in-place swap (false — a cover, a call, onboarding, a sheet-like
     *  page). A swap is never swiped back either. */
    animates: (from: K, to: K) -> Boolean = { _, _ -> true },
    /** A page's identity for composition + saved state (defaults to itself). */
    pageKey: (K) -> Any = { it },
    /** Whether the pages are painted on opaque paper. A page that draws its
     *  own full background can opt out with false. */
    paper: Boolean = true,
    content: @Composable (K) -> Unit,
) {
    require(stack.isNotEmpty()) { "IosNavStack needs at least one page" }
    val scope = rememberCoroutineScope()
    val holder = rememberSaveableStateHolder()
    val parent = LocalNavEdgeRegistry.current
    // A nested host's bottom page is its parent's page: it inherits whether
    // the parent owns back for it.
    val parentOwns = LocalNavOwnsBack.current
    val registry = remember(parent) { NavEdgeRegistry(parent) }

    /** The page shown at rest. */
    var top by remember { mutableStateOf(stack.last()) }
    /** While moving: the page sliding (the top one), and the one under it. */
    var mover by remember { mutableStateOf<K?>(null) }
    var under by remember { mutableStateOf<K?>(null) }
    /** 0 = the mover fully in place; 1 = fully off to the right. */
    var off by remember { mutableFloatStateOf(0f) }
    /** Bumped for every scripted move; the effect below plays it. */
    var moveId by remember { mutableIntStateOf(0) }
    var movePush by remember { mutableStateOf(true) }
    var job by remember { mutableStateOf<Job?>(null) }
    var reacted by remember { mutableStateOf(stack) }
    val currentStack by rememberUpdatedState(stack)
    val currentOnPop by rememberUpdatedState(onPop)

    fun dropState(dropped: K?, newTop: K) {
        if (dropped != null && dropped != newTop && dropped !in currentStack)
            holder.removeState(stableKey(pageKey(dropped)))
    }

    // The stack moved: decide what kind of move it is IN THIS COMPOSITION, so
    // the very first frame already draws the right pages (a swapped-away
    // page must never be drawn once more from state that is gone).
    if (stack != reacted) {
        val old = reacted
        reacted = stack
        val newTop = stack.last()
        val shown = mover?.takeIf { under != null } ?: top
        when {
            // An interactive pop that already carried the page off: settle.
            mover != null && under == newTop && off >= 0.999f -> {
                val gone = mover
                top = newTop; mover = null; under = null; off = 0f
                dropState(gone, newTop)
            }
            newTop == shown && mover == null -> top = newTop
            else -> {
                val isPush = newTop !in old
                val isPop = !isPush && shown !in stack
                val animate = (isPush || isPop) && shown != newTop &&
                    (if (isPush) animates(shown, newTop) else animates(newTop, shown))
                job?.cancel()
                if (!animate) {
                    top = newTop; mover = null; under = null; off = 0f
                    dropState(shown, newTop)
                } else if (isPush) {
                    mover = newTop; under = shown; off = 1f; movePush = true; moveId++
                } else {
                    mover = shown; under = newTop; movePush = false; moveId++
                }
            }
        }
    }

    LaunchedEffect(moveId) {
        if (moveId == 0) return@LaunchedEffect
        val m = mover ?: return@LaunchedEffect
        val u = under ?: return@LaunchedEffect
        if (movePush) {
            animate(off, 0f, animationSpec = PushSpec) { v, _ -> off = v }
            top = m; mover = null; under = null
        } else {
            animate(off, 1f, animationSpec = PushSpec) { v, _ -> off = v }
            top = u; mover = null; under = null; off = 0f
            dropState(m, u)
        }
    }

    val beneath = currentStack.getOrNull(currentStack.size - 2)
    val ownsBack = beneath != null && animates(beneath, currentStack.last())
    val canPop = ownsBack && mover == null && top == currentStack.last()

    fun beginInteractive(): Boolean {
        val b = currentStack.getOrNull(currentStack.size - 2) ?: return false
        if (mover != null || job?.isActive == true || top != currentStack.last()) return false
        mover = top; under = b; off = 0f
        return true
    }
    suspend fun settle(commit: Boolean) {
        fun ms(d: Float) = (d * PUSH_MS).roundToInt().coerceAtLeast(120)
        if (commit) {
            animate(off, 1f, animationSpec = tween(ms(1f - off), easing = PushEasing)) { v, _ -> off = v }
            val leaving = mover
            currentOnPop()
            // The caller's state normally changes in the same frame; if it
            // refused the pop, bring the page back.
            withFrameNanos { }
            withFrameNanos { }
            if (currentStack.last() == leaving && mover == leaving) {
                animate(off, 0f, animationSpec = PushSpec) { v, _ -> off = v }
                mover = null; under = null
            }
        } else {
            animate(off, 0f, animationSpec = tween(ms(off), easing = PushEasing)) { v, _ -> off = v }
            mover = null; under = null
        }
    }

    // A nested host that can pop owns the edge; tell the parent while we can.
    DisposableEffect(parent, canPop) {
        if (canPop) parent?.claim(registry)
        onDispose { parent?.release(registry) }
    }

    // System back (and the predictive back gesture). Registered BEFORE the
    // pages so a page's own conditional handler (a card open, a take
    // recording) still answers first.
    PredictiveBackHandler(enabled = ownsBack) { progress ->
        var started = false
        var startX = Float.NaN
        var width = 1f
        try {
            progress.collect { e: BackEventCompat ->
                if (!started) { started = beginInteractive(); if (!started) return@collect }
                width = lastWidth.coerceAtLeast(1f)
                if (startX.isNaN()) startX = e.touchX
                // iOS follows the finger; predictive back's own progress is
                // eased by the system, so the finger's travel is used where
                // the gesture comes from the left edge.
                val f = if (e.swipeEdge == BackEventCompat.EDGE_LEFT && e.touchX > 0f)
                    ((e.touchX - startX) / width).coerceIn(0f, 1f).coerceAtLeast(e.progress * 0.25f)
                else e.progress
                off = f
            }
            if (!started) started = beginInteractive()
            // Mid-transition a back is swallowed — never let it fall through
            // to whatever is under the stack (the app's exit).
            if (started) settle(commit = true) else if (mover == null) currentOnPop()
        } catch (c: CancellationException) {
            if (started) scope.launch { settle(commit = false) }
            throw c
        }
    }

    val density = LocalDensity.current
    val edgePx = with(density) { EdgeWidth.toPx() }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    // With gesture navigation the system owns the left edge and hands the
    // swipe to [PredictiveBackHandler]; the app's own edge drag is for
    // three-button navigation (no gesture inset), where the edge is ours.
    val canPopNow by rememberUpdatedState(canPop)
    val systemOwnsEdge = WindowInsets.systemGestures
        .getLeft(density, LocalLayoutDirection.current) > 0

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .pointerInput(rtl, systemOwnsEdge) {
                if (rtl || systemOwnsEdge) return@pointerInput
                val slop = viewConfiguration.touchSlop
                awaitPointerEventScope {
                    while (true) {
                        val downEvent = awaitPointerEvent(PointerEventPass.Initial)
                        val down = downEvent.changes.firstOrNull { it.pressed && !it.previousPressed } ?: continue
                        // Read live: the key must not change mid-drag, or the
                        // gesture is torn down under the finger.
                        if (!canPopNow || down.position.x > edgePx || registry.childOwnsEdge) continue
                        var dx = 0f; var dy = 0f
                        var claimed = false
                        val tracker = VelocityTracker()
                        tracker.addPosition(down.uptimeMillis, down.position)
                        val w = size.width.toFloat().coerceAtLeast(1f)
                        var settled = false
                        try { while (true) {
                            val ev = awaitPointerEvent(PointerEventPass.Initial)
                            val ch = ev.changes.firstOrNull { it.id == down.id } ?: break
                            tracker.addPosition(ch.uptimeMillis, ch.position)
                            if (!ch.pressed) {
                                if (claimed) {
                                    val vx = tracker.calculateVelocity().x
                                    val vxDp = vx / density.density
                                    val commit = when {
                                        vxDp > FlingDpPerSec -> true
                                        vxDp < -FlingDpPerSec -> false
                                        else -> off > 0.5f
                                    }
                                    ch.consume()
                                    settled = true
                                    job = scope.launch { settle(commit) }
                                }
                                break
                            }
                            val d = ch.positionChange()
                            dx += d.x; dy += d.y
                            if (!claimed) {
                                if (abs(dy) > slop && abs(dy) > abs(dx)) break
                                if (dx < -slop) break
                                if (dx > slop && dx > abs(dy)) {
                                    claimed = beginInteractive()
                                    if (!claimed) break
                                }
                            }
                            if (claimed) {
                                ch.consume()
                                val f = ((ch.position.x - down.position.x) / w).coerceIn(0f, 1f)
                                off = f
                            }
                        } } catch (c: CancellationException) {
                            // Torn down mid-drag: never leave a page hanging.
                            if (claimed && !settled) scope.launch { settle(commit = false) }
                            throw c
                        }
                    }
                }
            },
    ) {
        val widthPx = constraints.maxWidth.toFloat()
        lastWidth = widthPx
        val f = off
        val m = mover
        val u = under
        val pages: List<K> = if (m != null && u != null) listOf(u, m) else listOf(top)
        val inert = remember { InertBackOwner() }
        val realOwner = androidx.activity.compose.LocalOnBackPressedDispatcherOwner.current ?: inert
        CompositionLocalProvider(LocalNavEdgeRegistry provides registry) {
            for (p in pages) {
                val isMover = m != null && p == m
                val isUnder = u != null && p == u && m != null
                key(stableKey(pageKey(p))) {
                    val pageMod = when {
                        isMover -> Modifier.zIndex(1f).offset { IntOffset((widthPx * f).roundToInt(), 0) }
                        isUnder -> Modifier.zIndex(0f).offset { IntOffset((-widthPx / 3f * (1f - f)).roundToInt(), 0) }
                        else -> Modifier
                    }
                    Box(pageMod.fillMaxSize()) {
                        val body: @Composable () -> Unit = {
                            Box(Modifier.fillMaxSize().let { if (paper) it.background(AppSurfaces.ground) else it }) {
                                holder.SaveableStateProvider(stableKey(pageKey(p))) { content(p) }
                            }
                        }
                        // ONE provider shape whatever the page's role: a
                        // page that changed shape between "under" and "top"
                        // would be torn down and rebuilt mid-transition,
                        // losing its state (the Talk greeting flashed its
                        // first-talk line that way).
                        val owns = if (isUnder) false
                            else if (ownsBack && p == currentStack.last()) true
                            else if (p == currentStack.first()) parentOwns else false
                        CompositionLocalProvider(
                            androidx.activity.compose.LocalOnBackPressedDispatcherOwner provides
                                (if (isUnder) inert else realOwner),
                            LocalNavOwnsBack provides owns,
                        ) { body() }
                        // iOS dims the page being covered, a touch.
                        if (isUnder) Box(Modifier.fillMaxSize().graphicsLayer { alpha = 0.10f * (1f - f) }
                            .background(Color.Black))
                    }
                    if (isMover && f < 1f) {
                        // The leading-edge shadow the top page throws.
                        Box(
                            Modifier.zIndex(0.5f)
                                .offset { IntOffset((widthPx * f - ShadowWidthPx(density.density)).roundToInt(), 0) }
                                .width(ShadowWidth).fillMaxHeight()
                                .graphicsLayer { alpha = 1f - f }
                                .background(Brush.horizontalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.18f)))),
                        )
                    }
                }
            }
        }
    }
}

/** The page width last laid out — the predictive back gesture reports pixels. */
private var lastWidth = 1080f

private fun stableKey(k: Any): String = k.toString()

/** iOS's push curve (UINavigationController: ~0.35–0.38 s, ease-out). */
internal val PushEasing = CubicBezierEasing(0.2f, 0.9f, 0.3f, 1f)
internal const val PUSH_MS = 380
private val PushSpec = tween<Float>(PUSH_MS, easing = PushEasing)

/** Where a back drag may start (iOS's screen-edge pan, ~20 pt). */
private val EdgeWidth = 20.dp
private val ShadowWidth = 12.dp
private fun ShadowWidthPx(density: Float) = 12f * density
/** A flick this fast decides the swipe whatever the distance. */
private const val FlingDpPerSec = 500f

/**
 * Who may start a back swipe at the left edge. A nested host that can pop,
 * or a cover drawn in place inside a page ([NavCoverGuard]), claims the edge
 * from EVERY host above it — the innermost thing on screen answers the swipe.
 */
internal class NavEdgeRegistry(val parent: NavEdgeRegistry?) {
    private var claims by mutableIntStateOf(0)
    private val owners = mutableSetOf<Any>()
    val childOwnsEdge: Boolean get() = claims > 0
    fun claim(owner: Any) {
        if (owners.add(owner)) claims = owners.size
        parent?.claim(owner)
    }
    fun release(owner: Any) {
        if (owners.remove(owner)) claims = owners.size
        parent?.release(owner)
    }
}

/**
 * A full-screen cover or sheet that a page draws IN PLACE (Say it again,
 * the plan editor, shadowing a line): while it is up, no host under it may
 * be swiped back — on iOS a cover is dismissed downwards, never by the edge.
 */
@Composable
fun NavCoverGuard() {
    val registry = LocalNavEdgeRegistry.current ?: return
    DisposableEffect(registry) {
        val token = Any()
        registry.claim(token)
        onDispose { registry.release(token) }
    }
}

internal val LocalNavEdgeRegistry = compositionLocalOf<NavEdgeRegistry?> { null }

/** True for the top page of a host that pops it (system back + edge swipe). */
internal val LocalNavOwnsBack = compositionLocalOf { false }

/**
 * A pushed page's "back = leave this page". Use it instead of a bare
 * `BackHandler(onBack = onBack)`: inside an [IosNavStack] that can pop the
 * page it stands down, so the host's predictive back plays the iOS pop;
 * anywhere else (a page shown in place) it answers itself, so back never
 * leaves the app from a sub-page.
 */
@Composable
fun NavPageBackHandler(enabled: Boolean = true, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(enabled = enabled && !LocalNavOwnsBack.current, onBack = onBack)
}

/** A back dispatcher nothing ever presses — for pages drawn under the top. */
private class InertBackOwner : androidx.activity.OnBackPressedDispatcherOwner {
    private val lifecycleOwner = object : androidx.lifecycle.LifecycleOwner {
        val registry = androidx.lifecycle.LifecycleRegistry.createUnsafe(this).apply {
            currentState = androidx.lifecycle.Lifecycle.State.RESUMED
        }
        override val lifecycle: androidx.lifecycle.Lifecycle get() = registry
    }
    override val onBackPressedDispatcher = androidx.activity.OnBackPressedDispatcher()
    override val lifecycle: androidx.lifecycle.Lifecycle get() = lifecycleOwner.lifecycle
}
