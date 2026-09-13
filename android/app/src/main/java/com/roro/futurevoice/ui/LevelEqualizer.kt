package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * The "how your level gets built" glyph for a voice-first app — an audio
 * equalizer. Four columns (vocabulary / fluency / grammar / expression), each
 * six LED blocks, one per CEFR band with A1 at the bottom. Lit blocks are
 * that axis's level, so a weak axis reads instantly as a shorter column.
 * A level derived from a proxy measurement carries "≈" in its label.
 */
object LevelEqualizer {
    class Bar(val name: String, val level: String, val lit: Int, val color: Color)

    private val bands = listOf("C2", "C1", "B2", "B1", "A2", "A1")   // top → bottom
    private val blockHeight = 15.dp
    private val blockSpacing = 4.dp
    private val labelHeight = 34.dp

    @Composable
    fun View(bars: List<Bar>, modifier: Modifier = Modifier) {
        Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top) {
            // The CEFR scale — one y-axis shared by every column.
            Column(verticalArrangement = Arrangement.spacedBy(blockSpacing)) {
                bands.forEach { band ->
                    Text(band, style = MaterialTheme.typography.labelSmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.outline,
                        modifier = Modifier.height(blockHeight))
                }
                // Keeps this column as tall as the bars' label block.
                Modifier.height(labelHeight).let { Text("", modifier = it) }
            }
            bars.forEach { bar ->
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(blockSpacing),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    (0 until 6).forEach { row ->
                        // Row 0 is the TOP block (C2): lit when the level
                        // reaches this band counted from the bottom.
                        Modifier.fillMaxWidth().height(blockHeight).let { m ->
                            androidx.compose.foundation.layout.Box(
                                m.background(
                                    if (6 - row <= bar.lit) bar.color
                                    else MaterialTheme.colorScheme.surfaceVariant,
                                    RoundedCornerShape(3.5.dp)))
                        }
                    }
                    Column(Modifier.height(labelHeight), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(bar.name, style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1, textAlign = TextAlign.Center)
                        Text(bar.level, style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold,
                            color = if (bar.lit > 0) bar.color else MaterialTheme.colorScheme.outline)
                    }
                }
            }
        }
    }
}
