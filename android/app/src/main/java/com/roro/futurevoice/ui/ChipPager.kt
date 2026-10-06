package com.roro.futurevoice.ui

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch

/**
 * The chip-tab pager Review and Progress share (iOS `PracticeTab` /
 * `ProgressTab`: a horizontal paging ScrollView whose pages are their own
 * vertical scroll views, under a chip bar pinned to the top). Swiping a page
 * moves the selected chip and keeps it in view; tapping a chip slides to its
 * page. The chip bar is a panel of the page's ground, feathered at the
 * bottom (iOS: `.bar` masked 0 → 0.82 solid → clear), so a scrolled page
 * dissolves under it instead of being cut at a hard edge.
 */
@Composable
internal fun ChipPager(
    state: PagerState,
    /** Page `index`'s chip; `onClick` slides to that page. */
    chip: @Composable (index: Int, selected: Boolean, onClick: () -> Unit) -> Unit,
    page: @Composable ColumnScope.(Int) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    var barHeight by remember { mutableStateOf(0) }
    // Every page keeps its own scroll position across swipes, as iOS's do.
    val scrolls = remember(state.pageCount) { List(state.pageCount) { ScrollState(0) } }
    val chipRow = rememberScrollState()
    val chipBounds = remember { mutableMapOf<Int, androidx.compose.ui.geometry.Rect>() }
    val selected = state.currentPage
    // Keep the active chip in view as you swipe pages or tap (iOS
    // `proxy.scrollTo(new, anchor: .center)`).
    LaunchedEffect(selected) {
        val b = chipBounds[selected] ?: return@LaunchedEffect
        val viewport = chipRow.viewportSize
        if (viewport <= 0) return@LaunchedEffect
        val target = (b.center.x - viewport / 2f).toInt().coerceIn(0, chipRow.maxValue)
        chipRow.animateScrollTo(target)
    }
    Box(Modifier.fillMaxSize()) {
        HorizontalPager(state, Modifier.fillMaxSize()) { i ->
            Column(
                Modifier.fillMaxSize().verticalScroll(scrolls[i])
                    .padding(top = with(density) { barHeight.toDp() } + 8.dp)
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                page(i)
                // Room to scroll the last item up past the floating bar.
                Spacer(Modifier.height(IosTabBarClearance)
                    .windowInsetsPadding(WindowInsets.navigationBars))
            }
        }
        val ground = AppSurfaces.ground
        Box(
            Modifier.fillMaxWidth()
                .onSizeChanged { barHeight = it.height }
                .background(Brush.verticalGradient(
                    0f to ground, 0.82f to ground, 1f to ground.copy(alpha = 0f)))
                .padding(top = 4.dp, bottom = 6.dp),
        ) {
            Row(
                Modifier.horizontalScroll(chipRow)
                    .padding(horizontal = 20.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Top,
            ) {
                repeat(state.pageCount) { i ->
                    Box(Modifier.onGloballyPositioned { chipBounds[i] = it.boundsInParent() }) {
                        chip(i, i == selected) { scope.launch { state.animateScrollToPage(i) } }
                    }
                }
            }
        }
    }
}
