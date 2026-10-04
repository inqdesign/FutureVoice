package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonElevation
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * iOS's `.controlSize(.large)` buttons, which is what every CTA in the iOS app
 * is (`.borderedProminent` / `.bordered`). Measured on the iOS 1.1.3 gallery:
 * 48–50 pt tall capsules, where Material's default is a 40 dp pill (41.6 dp
 * on the A34 with its font scale) — every Android CTA read a size smaller.
 *
 * Same signatures as Material's, so screens take them through an import
 * alias (`import com.roro.futurevoice.ui.brand.IosButton as Button`) and a
 * screen can't forget the size. A caller's own height (`heightIn(min = 58)`)
 * still wins: this is only the floor.
 */
val IosLargeButtonHeight: Dp = 50.dp

private val LargePadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp)

@Composable
fun IosButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: Shape = CircleShape,
    colors: ButtonColors = ButtonDefaults.buttonColors(),
    elevation: ButtonElevation? = ButtonDefaults.buttonElevation(),
    border: BorderStroke? = null,
    contentPadding: PaddingValues = LargePadding,
    interactionSource: MutableInteractionSource? = null,
    content: @Composable RowScope.() -> Unit,
) = androidx.compose.material3.Button(onClick, modifier.defaultMinSize(minHeight = IosLargeButtonHeight),
    enabled, shape, colors, elevation, border, contentPadding, interactionSource, content)

@Composable
fun IosTonalButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: Shape = CircleShape,
    colors: ButtonColors = ButtonDefaults.filledTonalButtonColors(),
    elevation: ButtonElevation? = ButtonDefaults.filledTonalButtonElevation(),
    border: BorderStroke? = null,
    contentPadding: PaddingValues = LargePadding,
    interactionSource: MutableInteractionSource? = null,
    content: @Composable RowScope.() -> Unit,
) = androidx.compose.material3.FilledTonalButton(onClick, modifier.defaultMinSize(minHeight = IosLargeButtonHeight),
    enabled, shape, colors, elevation, border, contentPadding, interactionSource, content)

/** iOS has no outlined button: its secondary CTA is `.bordered`, a light
 *  tint of the accent with the accent label and no stroke (the setup flow's
 *  Back, "Go to Practice" on the spent sheet). Material's outline drew a
 *  white pill with a grey ring beside every such button. */
@Composable
fun IosOutlinedButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: Shape = CircleShape,
    colors: ButtonColors = ButtonDefaults.buttonColors(
        containerColor = androidx.compose.material3.MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
        contentColor = androidx.compose.material3.MaterialTheme.colorScheme.primary,
        disabledContainerColor = androidx.compose.material3.MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f),
        disabledContentColor = androidx.compose.material3.MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)),
    elevation: ButtonElevation? = null,
    border: BorderStroke? = null,
    contentPadding: PaddingValues = LargePadding,
    interactionSource: MutableInteractionSource? = null,
    content: @Composable RowScope.() -> Unit,
) = androidx.compose.material3.OutlinedButton(onClick, modifier.defaultMinSize(minHeight = IosLargeButtonHeight),
    enabled, shape, colors, elevation, border, contentPadding, interactionSource, content)
