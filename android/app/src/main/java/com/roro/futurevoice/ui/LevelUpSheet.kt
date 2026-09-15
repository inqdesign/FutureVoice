package com.roro.futurevoice.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import kotlinx.coroutines.delay

/**
 * A MEASURED assessment raised the level.
 *
 * Only measurement gets a celebration — a manual change in Me is the learner
 * telling the app something, not the app telling them something, and
 * congratulating someone for editing a picker is hollow.
 *
 * A drop is never announced. The number is an estimate that moves both ways
 * for reasons that have nothing to do with the learner getting worse, and
 * being told you fell a band is not news anyone asked for. The rule is
 * enforced where the level is written (`AppViewModel.applyMeasuredLevel`
 * only arms `levelUp` when the band ROSE), so this sheet never has to ask.
 *
 * The two bands are named the way the rest of the app names them —
 * [LanguageCatalog.levelLabel], which is CEFR plus the local exam scale where
 * one exists (TOPIK for Korean, JLPT for Japanese). A learner who has seen
 * "B1 · TOPIK 3" in Me and on the setup picker should not meet a bare "B1"
 * at the one moment the number is the whole point.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LevelUpSheet(from: CefrLevel, to: CefrLevel, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val target = remember { LanguageScope.active(context) }
    var revealed by remember { mutableStateOf(false) }
    // Same beat as iOS: a short hold, then a half-second ease. Instant is a
    // state change; this reads as an arrival.
    LaunchedEffect(Unit) { delay(150); revealed = true }
    val alpha by animateFloatAsState(
        targetValue = if (revealed) 1f else 0f,
        animationSpec = tween(durationMillis = 500), label = "levelUp",
    )
    val scale by animateFloatAsState(
        targetValue = if (revealed) 1f else 0.85f,
        animationSpec = tween(durationMillis = 500), label = "levelUpScale",
    )
    val green = Color(0xFF34C759)

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
                .padding(horizontal = 24.dp).padding(bottom = 32.dp, top = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Icon(Icons.AutoMirrored.Filled.TrendingUp, contentDescription = null,
                tint = green, modifier = Modifier.size(44.dp).alpha(alpha))
            Text(stringResource(R.string.level_up),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold)
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(LanguageCatalog.levelLabel(from, target),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(LanguageCatalog.levelLabel(to, target),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.alpha(alpha).scale(scale))
            }
            Text(stringResource(R.string.your_recent_conversations_measure_at_a_higher_level_scoring_8861e0),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center)
            Spacer(Modifier.height(4.dp))
            Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.continue_))
            }
        }
    }
}
