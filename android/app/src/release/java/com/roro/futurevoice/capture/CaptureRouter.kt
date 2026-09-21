package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.runtime.Composable

/** Only the `capture` build type routes screenshots; everywhere else there is
 *  no harness and the app starts normally. */
object CaptureRouter {
    fun content(context: Context, mode: String?, lang: String? = null): (@Composable () -> Unit)? = null
}
