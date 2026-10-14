package com.roro.futurevoice.ui

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SheetState
import androidx.compose.material3.SheetValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity

/**
 * Every ModalBottomSheet's state — the app's stand-in for Material's
 * `rememberModalBottomSheetState`, same parameters, closing the way an iOS
 * sheet does ([IosSheetHost]): let go past a third of the screen, or with a
 * real flick (1000 dp/s). Material's own default closed after 56 dp of drag or
 * a 125 dp/s flick, so the slightest pull down threw a sheet away (founder,
 * 2026-10-14). Every call site imports THIS one; never Material's.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun rememberModalBottomSheetState(
    skipPartiallyExpanded: Boolean = false,
    confirmValueChange: (SheetValue) -> Boolean = { true },
): SheetState {
    // Callers pass a fresh lambda on every recomposition; keying the state on
    // it would rebuild the sheet hidden mid-presentation. Read the latest.
    val confirm by rememberUpdatedState(confirmValueChange)
    val gate: (SheetValue) -> Boolean = remember { { v -> confirm(v) } }
    val density = LocalDensity.current
    val screenPx = with(density) { LocalConfiguration.current.screenHeightDp.toFloat() * this.density }
    val positional = { screenPx * CLOSE_FRACTION }
    val velocity = { with(density) { FLICK_DP_PER_S * this.density } }
    return rememberSaveable(skipPartiallyExpanded,
        saver = SheetState.Saver(skipPartiallyExpanded, positional, velocity, gate, false)) {
        SheetState(skipPartiallyExpanded, positional, velocity, SheetValue.Hidden, gate, false)
    }
}

private const val CLOSE_FRACTION = 0.33f
private const val FLICK_DP_PER_S = 1000f
