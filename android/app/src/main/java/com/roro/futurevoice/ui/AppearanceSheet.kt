package com.roro.futurevoice.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme

/**
 * The Futureself palette — six of them, stored and used everywhere (the call
 * pill, the home ring, the day card, the widgets) and until now unchangeable
 * on Android.
 *
 * Each option shows the ACTUAL surface rather than a colour swatch: the
 * palette is a mosaic, and a single dot says nothing about what the circle
 * will look like. Picking writes the same key iOS's `@AppStorage` uses, so a
 * learner's choice survives moving between platforms.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppearanceSheet(onPicked: (FutureselfTheme) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var picked by remember { mutableStateOf(FutureselfTheme.stored(context)) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.appearance),
                style = MaterialTheme.typography.titleLarge)
            FutureselfTheme.entries.forEach { theme ->
                Row(
                    Modifier.fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .border(
                            width = if (theme == picked) 2.dp else 1.dp,
                            color = if (theme == picked) theme.tint()
                            else MaterialTheme.colorScheme.outlineVariant,
                            shape = RoundedCornerShape(14.dp))
                        .clickable {
                            picked = theme
                            context.getSharedPreferences("futurevoice", 0).edit()
                                .putInt(FutureselfTheme.PREF_KEY, theme.ordinal).apply()
                            onPicked(theme)
                        }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    // The real surface, at the call pill's own cell size, so
                    // the preview is what the learner will actually get.
                    Futureself(
                        mode = FutureselfMode.IDLE, level = 0f, theme = theme,
                        virtualHeight = 64f,
                        modifier = Modifier.size(width = 76.dp, height = 40.dp)
                            .clip(CircleShape),
                    )
                    Text(theme.label, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}
