package com.roro.futurevoice.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * iOS `FutureselfThemePicker`: the six palettes as a 3×2 grid of LIVE mini
 * surfaces. Each option shows the actual mosaic rather than a swatch — a
 * single dot says nothing about what the circle will look like — and a tap
 * selects it and fires a voice bloom on that preview, so the choice is felt,
 * not just seen. Picking writes the same key iOS's `@AppStorage` uses.
 */
@Composable
fun FutureselfThemePicker(onPicked: (FutureselfTheme) -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf(FutureselfTheme.stored(context)) }
    /** The theme currently playing its tap bloom, if any. */
    var bursting by remember { mutableStateOf<FutureselfTheme?>(null) }
    val accent = MaterialTheme.colorScheme.primary
    val separator = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        FutureselfTheme.entries.chunked(3).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { theme ->
                    val selected = theme == picked
                    Column(
                        Modifier.weight(1f).clickable(
                            interactionSource = remember { MutableInteractionSource() }, indication = null) {
                            picked = theme
                            FutureselfTheme.pick(context, theme)
                            onPicked(theme)
                            // Drive the preview like a real utterance: full
                            // level, then released after a beat.
                            bursting = theme
                            scope.launch { delay(900); if (bursting == theme) bursting = null }
                        },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        // Resting previews idle at a mid level so every
                        // palette actually shows its colours.
                        Futureself(
                            mode = FutureselfMode.SPEAKING,
                            level = if (bursting == theme) 1f else 0.32f,
                            theme = theme,
                            modifier = Modifier.fillMaxWidth().height(44.dp).clip(CircleShape)
                                .border(if (selected) 2.dp else 0.5.dp,
                                    if (selected) accent else separator, CircleShape),
                        )
                        Text(theme.label, fontSize = 11.sp,
                            color = if (selected) accent else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
