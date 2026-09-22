package com.roro.futurevoice.ui

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.roro.futurevoice.core.UILanguage

/**
 * A line the FLUENT SELF says on screen, resolved in the TARGET language —
 * the material half of "Two languages" (see CLAUDE.md), drawn as UI.
 *
 * Everything the APP says goes through the ordinary `stringResource`, which
 * follows the app language. Use this only for a line spoken in the learner's
 * own future voice, and it follows the language switcher the moment it moves.
 */
@Composable
fun materialString(@StringRes id: Int): String {
    val context = LocalContext.current
    val material = remember(context) { UILanguage.materialContext(context) }
    return material.getString(id)
}
