package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.runtime.Composable

/**
 * Capture modes for the Talk area. This file owns exactly these iOS modes:
 *
 *   home
 *   home-ring
 *   home-plus
 *   home-light
 *   home-light-fresh
 *   first-call
 *   free-minutes-welcome
 *   glow
 *   tabs
 *   talk-alt
 *   talk-alt-call
 *   talk-alt-demo
 *   level-header
 *   level-sheet
 *   themes
 *   call-meter
 *   call-meter-low
 *   call-goals
 *   call-feed-fade
 *   call-goal-sheet
 *   summary-progress
 *   summary-progress-start
 *   carryover
 *   transcript-ja
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 */
object CaptureTalk {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
    )
}
