package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.WeeklyReport
import com.roro.futurevoice.data.WeeklyReportStore
import com.roro.futurevoice.ui.brand.AppSurfaces
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The assessment in full.
 *
 * Progress carries the digest — the trend line, the counts, the level and its
 * rationale. Everything item-by-item lives here instead, because a wall of
 * text at the bottom of Progress was getting skipped rather than read.
 *
 * Three lists, in the order they are useful: what you SAID for the first time
 * (evidence you are growing), what you keep getting wrong (what to drill),
 * then what to reach for next.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssessmentScreen(language: String, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    var report by remember { mutableStateOf<WeeklyReport?>(null) }
    LaunchedEffect(language) { report = WeeklyReportStore.shared(context).latest(language) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.latest_assessment)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        val r = report ?: return@Scaffold
        LazyColumn(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Column(Modifier.padding(vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(period(r), style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (r.summary.isNotBlank()) {
                        Text(r.summary, style = MaterialTheme.typography.bodyLarge)
                    }
                    r.levelRationale?.takeIf { it.isNotBlank() }?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            if (r.newExpressions.isNotEmpty()) {
                item { SectionTitle(stringResource(R.string.you_said_these_for_the_first_time)) }
                items(r.newExpressions.size) { i ->
                    val e = r.newExpressions[i]
                    Entry(e.phrase) {
                        // The learner's OWN sentence, not an invented one:
                        // the proof is that they already produced it.
                        if (e.sampleSentence.isNotBlank()) {
                            Text("“${e.sampleSentence}”",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            if (r.repeatedMistakes.isNotEmpty()) {
                item { SectionTitle(stringResource(R.string.keeps_coming_back)) }
                items(r.repeatedMistakes.size) { i ->
                    val m = r.repeatedMistakes[i]
                    Entry(m.fluentAlternative) {
                        Text(m.userSaid, style = MaterialTheme.typography.bodySmall,
                            textDecoration = TextDecoration.LineThrough,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (m.note.isNotBlank()) {
                            Text(m.note, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            if (r.suggestedExpressions.isNotEmpty()) {
                item { SectionTitle(stringResource(R.string.worth_reaching_for)) }
                items(r.suggestedExpressions.size) { i ->
                    val s = r.suggestedExpressions[i]
                    Entry(s.phrase) {
                        if (s.example.isNotBlank()) {
                            Text(s.example, style = MaterialTheme.typography.bodySmall)
                        }
                        if (s.whenToUse.isNotBlank()) {
                            Text(s.whenToUse, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            item { Column(Modifier.padding(bottom = 24.dp)) {} }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Column(Modifier.padding(top = 12.dp)) {
        Text(text, style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold)
        HorizontalDivider(Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun Entry(headline: String, detail: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(headline, style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium)
        detail()
    }
}

private fun period(r: WeeklyReport): String {
    val f = SimpleDateFormat("d MMM", Locale.getDefault())
    return "${f.format(Date(r.periodStart))} – ${f.format(Date(r.periodEnd))} · ${r.sessionCount}"
}
