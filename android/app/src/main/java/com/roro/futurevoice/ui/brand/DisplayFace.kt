package com.roro.futurevoice.ui.brand

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import com.roro.futurevoice.R

/**
 * The app's DISPLAY face — Geist Pixel (`RootView.geistPixel`), used for the
 * hero line, page titles and big numbers. Body text stays the system face;
 * this is the brand's voice, not the app's reading font.
 *
 * Geist Pixel carries no Hangul, so Korean falls to Galmuri — a pixel face
 * too, so a mixed screen still reads as one voice. Android picks a custom
 * family's font by weight/style, never by glyph coverage, so the choice is
 * made per STRING here rather than left to a fallback that doesn't exist.
 * A string mixing scripts takes Galmuri (which covers Latin as well).
 */
object DisplayFace {

    private val geist = FontFamily(Font(R.font.geist_pixel_square))
    private val galmuri = FontFamily(Font(R.font.galmuri14))

    private val HANGUL = Regex("[\\uAC00-\\uD7A3\\u1100-\\u11FF\\u3130-\\u318F]")

    fun family(text: String): FontFamily =
        if (HANGUL.containsMatchIn(text)) galmuri else geist

    /** Apply the display face to [style] for the given text. */
    @Composable
    fun style(text: String, style: TextStyle): TextStyle =
        style.copy(fontFamily = family(text))
}
