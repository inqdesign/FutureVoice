package com.roro.futurevoice.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper

/**
 * The Activity behind a Compose `LocalContext`.
 *
 * Inside a `Dialog` or a `ModalBottomSheet` the local context is the
 * dialog's own `ContextThemeWrapper`, not the Activity, so `context as?
 * Activity` is null there. Every paywall is hosted in a `Dialog` and the
 * spent-pool sheet is a bottom sheet: with the plain cast, the Subscribe
 * button and the minute-pack button did nothing at all (2026-11-10, a
 * tester's report; no Android account had ever logged a purchase tap).
 * Anything that hands an Activity to Play goes through this.
 */
fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return null
}
