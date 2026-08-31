package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * RESERVED FOR THE CORE. Nothing else in the app may use indigo.
 *
 * The UI rules allow only system colours, so a badge can't be made special
 * by drawing it differently. Scarcity of the colour is the badge instead: if
 * indigo appears nowhere else, indigo MEANS the Core. Spend it on anything
 * else and the seal stops reading as one.
 */
val CoreClubColor = Color(0xFF5856D6)   // systemIndigo

/**
 * The Core's one glyph: this person is in the Core, RIGHT NOW.
 *
 * **It has no second state, and must never get one back.** It used to come
 * in two — filled for a seated member, outlined for someone who had
 * qualified but held no seat — so the month that earned it could never be
 * taken away. That is sound about the RECORD and wrong about the BADGE, and
 * it failed in the only place the seal is ever seen by someone else: a mark
 * beside a stranger's name in Find people. A stranger cannot read one seal,
 * let alone tell two apart, and nothing on that row can explain that this
 * one means "was here once".
 *
 * A stranger sees the seal and nothing else — no number, no rank, no talk
 * time. Rank decides who gets in; inside the club everyone is equal.
 */
@Composable
fun CoreSeal(size: Dp = 13.dp) {
    Canvas(Modifier.size(size).semantics { contentDescription = "The Core" }) {
        // A scalloped disc — SF Symbols' `seal.fill`, drawn.
        val r = this.size.minDimension / 2f
        val cx = this.size.width / 2f
        val cy = this.size.height / 2f
        val lobes = 11
        val path = Path()
        val steps = lobes * 12
        for (i in 0..steps) {
            val t = i / steps.toFloat() * 2f * PI.toFloat()
            val wave = 1f + 0.10f * cos(lobes * t)
            val x = cx + r * wave * cos(t)
            val y = cy + r * wave * sin(t)
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        drawPath(path, CoreClubColor)
    }
}
