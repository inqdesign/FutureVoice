package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.runtime.Composable

/**
 * Capture modes for the Me area. This file owns exactly these iOS modes:
 *
 *   me
 *   plan
 *   plan-guide
 *   plan-trial
 *   paywall
 *   paywall-plans
 *   day-spent
 *   day-spent-scenes
 *   day-spent-unlimited
 *   day-spent-trial
 *   day-spent-trial-plus
 *   credits-out
 *   update
 *   update-required
 *   sync
 *   feedback
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 */
object CaptureMe {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "paywall" to { _ -> com.roro.futurevoice.ui.PaywallScreen(onDismiss = {}) },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
    )
}
