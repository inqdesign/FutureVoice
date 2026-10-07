package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * "Say it again" from the routine: which talk? (iOS `SayItAgainPicker`.) A
 * say-it-again block names no talk — it recurs every week, and the talk worth
 * redoing is whichever the learner just had — so the choice is made when it is
 * time, here. The most recent talk is picked already; one tap starts it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SayItAgainPicker(language: String, onClose: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onClose)
    NavCoverGuard()
    val context = LocalContext.current
    var talks by remember { mutableStateOf<List<Session>?>(null) }
    var picked by remember { mutableStateOf<String?>(null) }
    var running by remember { mutableStateOf<Session?>(null) }
    LaunchedEffect(language) {
        val since = System.currentTimeMillis() - LOOKBACK_DAYS * 86_400_000L
        val list = SessionStore.shared(context).load(language)
            .filter { s ->
                val end = s.endedAt ?: return@filter false
                // A talk the learner never spoke in has nothing to say again.
                end >= since && s.turns.any { it.role == TurnRole.USER }
            }
            .sortedByDescending { it.endedAt ?: it.startedAt }
            .take(LIMIT)
        talks = list
        if (picked == null) picked = list.firstOrNull()?.id
    }

    val futureSelfName = stringResource(R.string.future_self_1384d5)
    running?.let { session ->
        val source = remember(session.id) { SayItAgainSource.talk(context, session, futureSelfName) }
        SayItAgainScreen(source = source, onClose = onClose)
        return
    }

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.routine_kind_say_it_again)) },
                navigationIcon = { TextButton(onClick = onClose) { Text(stringResource(R.string.routine_cancel)) } },
                actions = {
                    TextButton(enabled = picked != null, onClick = {
                        val list = talks.orEmpty()
                        running = list.firstOrNull { it.id == picked }
                        com.roro.futurevoice.core.Analytics.capture("plan_say_again_start",
                            mapOf("index" to list.indexOfFirst { it.id == picked }))
                    }) { Text(stringResource(R.string.routine_start), fontWeight = FontWeight.SemiBold) }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp)) {
            val list = talks ?: return@Column
            if (list.isEmpty()) {
                Text(stringResource(R.string.routine_no_talks_yet),
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp))
                return@Column
            }
            GroupedCard {
                list.forEachIndexed { i, talk ->
                    if (i > 0) GroupedRowDivider()
                    val on = talk.id == picked
                    val lines = talk.turns.count { it.role == TurnRole.USER }
                    val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEMMMdHHmm")
                    val whenText = SimpleDateFormat(pattern, Locale.getDefault()).format(Date(talk.endedAt ?: talk.startedAt))
                    Row(Modifier.fillMaxWidth().clickable { picked = talk.id }.padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(if (on) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null,
                            tint = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(24.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(talk.displayTitle ?: stringResource(R.string.conversation),
                                style = MaterialTheme.typography.bodyLarge, maxLines = 2)
                            Text(stringResource(R.string.routine_talk_line, whenText, lines),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            GroupedFooter(stringResource(R.string.routine_whole_talk_again))
        }
    }
}

private const val LOOKBACK_DAYS = 14
private const val LIMIT = 12
