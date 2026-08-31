package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.rememberCoroutineScope
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.LiveTranscriber
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.core.InstallSalt
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.talk.ShadowScore
import kotlinx.coroutines.launch

/**
 * Shadow one line — `ShadowDrillView`'s spine: hear the fluent self say it
 * (cached TTS: deterministic idempotency key, so replays are free), say it
 * back, get the DETERMINISTIC score (`ShadowScore`, golden-vector-verified)
 * with the target's words colored by the diff. Karaoke timing and the coach
 * bullets arrive later.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShadowScreen(
    line: String,
    voiceId: String,
    targetLanguage: String,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mp3 = remember { Mp3Player(context.cacheDir) }
    val live = remember { LiveTranscriber(context) }
    var recording by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf<ShadowScore.Analysis?>(null) }
    var said by remember { mutableStateOf("") }

    fun playLine() {
        busy = true
        scope.launch {
            runCatching {
                val audio = ElevenLabsClient(AuthRepository()).synthesize(
                    voiceId = voiceId, text = line,
                    idempotencyKey = InstallSalt.ttsKey(line, voiceId, timestamps = false),
                    purpose = "shadow")
                mp3.play(audio)
            }
            busy = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.say_it_out_loud)) },
                navigationIcon = {
                    IconButton(onClick = { mp3.stop(); runCatching { live.stop() }; onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // The target line, colored by the last attempt's diff.
            val a = attempt
            if (a == null) {
                Text(line, style = MaterialTheme.typography.titleLarge)
            } else {
                val ops = ShadowScore.targetOps(a.steps)
                val words = line.split(Regex("\\s+")).filter { it.isNotEmpty() }
                val spans = ShadowScore.tokenSpans(words, targetLanguage)
                Text(buildAnnotatedString {
                    words.forEachIndexed { i, word ->
                        // A word is painted only when EVERY token inside it
                        // went un-matched (the iOS highlight rule).
                        val range = spans.getOrNull(i) ?: IntRange.EMPTY
                        val allMissed = !range.isEmpty() && range.all { t ->
                            ops.getOrNull(t)?.let { it != ShadowScore.DiffOp.MATCH } == true
                        }
                        if (allMissed) {
                            pushStyle(SpanStyle(color = Color(0xFFB3261E),
                                textDecoration = TextDecoration.Underline))
                            append(word); pop()
                        } else append(word)
                        if (i != words.lastIndex) append(" ")
                    }
                }, style = MaterialTheme.typography.titleLarge)
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Text("${a.score}", style = MaterialTheme.typography.headlineLarge,
                        color = MaterialTheme.colorScheme.primary)
                    Text("  ·  ${a.matchCount}/${a.targetTokenCount}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (said.isNotBlank()) {
                    Text(said, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())

            OutlinedButton(onClick = { playLine() }, enabled = !busy && !recording,
                modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.listen))
            }
            if (!recording) {
                Button(onClick = {
                    attempt = null; said = ""
                    runCatching {
                        live.start(LanguageCatalog.sttLocale(targetLanguage)) { }
                        recording = true
                    }
                }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.start_recording))
                }
            } else {
                Button(onClick = {
                    val text = runCatching { live.stop() }.getOrDefault("")
                    recording = false
                    said = text
                    attempt = ShadowScore.analyze(line, text, targetLanguage)
                }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.stop))
                }
            }
        }
    }
}
