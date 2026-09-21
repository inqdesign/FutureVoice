package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.runtime.Composable

/**
 * Capture modes for the Onboarding area. This file owns exactly these iOS modes:
 *
 *   welcome
 *   welcome-signin
 *   setup
 *   signup-account
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 */
object CaptureOnboarding {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
    )
}
