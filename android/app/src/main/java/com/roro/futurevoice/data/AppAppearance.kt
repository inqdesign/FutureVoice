package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * iOS `AppAppearance`: follow the phone, or force light / dark — Me →
 * Appearance's segmented control. Same key and raw values iOS writes
 * (`futurevoice.appearance` = system | light | dark), so a backup carries it.
 *
 * Applied at the root ([com.roro.futurevoice.ui.AppearanceHost]) by
 * overriding the configuration's night bits, which is what every
 * `isSystemInDarkTheme()` in the app reads — one switch, no per-screen code.
 */
enum class AppAppearance(val raw: String, @androidx.annotation.StringRes val labelRes: Int) {
    SYSTEM("system", com.roro.futurevoice.R.string.system),
    LIGHT("light", com.roro.futurevoice.R.string.light),
    DARK("dark", com.roro.futurevoice.R.string.dark);

    companion object {
        const val KEY = "futurevoice.appearance"
        private val _live = MutableStateFlow<AppAppearance?>(null)

        fun current(context: Context): AppAppearance = _live.value ?: run {
            val raw = context.getSharedPreferences("futurevoice", 0).getString(KEY, null)
            (entries.firstOrNull { it.raw == raw } ?: SYSTEM).also { _live.value = it }
        }

        /** The mode as a flow, primed from disk on first read. */
        fun live(context: Context): StateFlow<AppAppearance?> { current(context); return _live }

        fun set(context: Context, mode: AppAppearance) {
            context.getSharedPreferences("futurevoice", 0).edit().putString(KEY, mode.raw).apply()
            _live.value = mode
        }
    }
}
