package com.roro.futurevoice.capture

import android.content.Context
import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.talk.FileRecognizer
import java.io.File

/**
 * Shadow capture modes that iOS's harness has no counterpart for: the
 * result, duet and coach states (iOS can't seed a take), and `probe-asr`,
 * which runs the platform recognizer over bundled WAVs and logs what it
 * returns — the measurement behind the learner-timing method in plan 2.9.
 */
object CaptureShadow {

    private const val TAG = "ShadowProbe"

    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "probe-asr" to { c -> ProbeAsr(c) },
        "shadow-result" to { _ -> Result(pending = false, timed = true) },
        "shadow-result-pending" to { _ -> Result(pending = true, timed = true) },
        "shadow-words-only" to { _ -> Result(pending = false, timed = false) },
    )

    /**
     * A finished take on the capture line: one word said differently, two
     * words come in late, the coach's bullets (or its pending row), and the
     * past attempts — every result element the Swift view draws.
     */
    @Composable
    private fun Result(pending: Boolean, timed: Boolean) {
        val turn = CaptureSeed.shadowTurn
        val words = com.roro.futurevoice.data.WordSplitter.timingWords(turn.transcript, "en")
        val target = words.mapIndexed { i, w -> com.roro.futurevoice.talk.WordTiming(w, i * 380, (i + 1) * 380 - 60) }
        val said = "I really appreciate you take the time to help me"
        val late = mapOf(4 to 260, 7 to 420, 8 to 380, 10 to 520, 2 to -200)
        val learner = com.roro.futurevoice.data.WordSplitter.timingWords(said, "en").mapIndexed { i, w ->
            val s = 300 + i * 450 + (late[i] ?: 0)
            com.roro.futurevoice.talk.WordTiming(w, s, s + 380)
        }
        val now = System.currentTimeMillis()
        com.roro.futurevoice.ui.ShadowScreen(
            line = turn.transcript, voiceId = "", targetLanguage = "en", turnId = turn.id, onBack = {},
            seed = com.roro.futurevoice.ui.ShadowSeed(
                targetTimings = target, learnerText = said,
                learnerTimings = if (timed) learner else emptyList(),
                learnerDurationMs = 4_720, coachPending = pending,
                pronunciation = if (pending) "" else "\"taking\"이 \"take\"로 들렸어요 — 끝의 -ing를 살려 주세요.",
                pacing = if (pending) "" else "전체 속도는 조금 느렸고, \"to\"와 \"help\"에서 늦게 들어왔어요.",
                fix = if (pending) "" else "\"taking the time\"을 한 덩어리로 이어서 말해 보세요.",
                past = listOf(
                    com.roro.futurevoice.data.ShadowAttempt(turnId = turn.id, targetText = turn.transcript,
                        learnerTranscript = "I really appreciate you taking time to help me", matchScore = 91,
                        rhythmScore = 72, fix = "\"the time\"에서 \"the\"를 빼먹지 마세요.",
                        createdAt = now - 3 * 3_600_000L),
                    com.roro.futurevoice.data.ShadowAttempt(turnId = turn.id, targetText = "appreciate you taking",
                        learnerTranscript = "appreciate you taking", matchScore = 100, rhythmScore = 88,
                        phraseFirst = 2, phraseLast = 4, createdAt = now - 26 * 3_600_000L),
                ),
            ),
        )
    }

    @Composable
    private fun ProbeAsr(c: Context) {
        var log by remember { mutableStateOf("probing…\n") }
        LaunchedEffect(Unit) {
            fun say(s: String) { Log.i(TAG, s); log += s + "\n" }
            say("sdk=${android.os.Build.VERSION.SDK_INT} supported=${FileRecognizer.supported} " +
                "onDevice=${android.speech.SpeechRecognizer.isOnDeviceRecognitionAvailable(c)} " +
                "default=${android.speech.SpeechRecognizer.isRecognitionAvailable(c)}")
            if ((c as? android.app.Activity)?.intent?.getStringExtra("download") != null) {
                val lang = c.intent.getStringExtra("download")!!
                val sr = android.speech.SpeechRecognizer.createOnDeviceSpeechRecognizer(c)
                val i = android.content.Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE,
                        com.roro.futurevoice.data.LanguageCatalog.sttLocale(lang))
                sr.checkRecognitionSupport(i, c.mainExecutor, object : android.speech.RecognitionSupportCallback {
                    override fun onSupportResult(r: android.speech.RecognitionSupport) {
                        say("support installed=${r.installedOnDeviceLanguages} pending=${r.pendingOnDeviceLanguages} " +
                            "supported=${r.supportedOnDeviceLanguages.take(40)} online=${r.onlineLanguages.take(10)}")
                    }
                    override fun onError(error: Int) { say("support error=$error") }
                })
                kotlinx.coroutines.delay(2000)
                sr.triggerModelDownload(i, c.mainExecutor, object : android.speech.ModelDownloadListener {
                    override fun onProgress(completedPercent: Int) { say("download $completedPercent%") }
                    override fun onSuccess() { say("download success") }
                    override fun onScheduled() { say("download scheduled") }
                    override fun onError(error: Int) { say("download error=$error") }
                })
                kotlinx.coroutines.delay(60_000)
            }
            val variants = listOf(
                FileRecognizer.Feed(onDevice = false),
                FileRecognizer.Feed(onDevice = false, segmented = true),
                FileRecognizer.Feed(onDevice = false, pace = 4.0),
                FileRecognizer.Feed(onDevice = false, pace = 1.0),
                FileRecognizer.Feed(onDevice = true),
            )
            val only = (c as? android.app.Activity)?.intent?.getStringExtra("langs")?.split(",")
                ?: listOf("en", "ko", "ja")
            for (lang in only) {
                val f = File(c.cacheDir, "probe-$lang.wav")
                c.assets.open("probe/$lang.wav").use { i -> f.outputStream().use { it.let { o -> i.copyTo(o) } } }
                val pcm = com.roro.futurevoice.audio.WavPcm.read(f)!!
                val raw = File(c.cacheDir, "probe-$lang.pcm").also { it.writeBytes(pcm.pcmBytes()) }
                for (v in variants) {
                    val r = kotlinx.coroutines.withTimeoutOrNull(20_000) {
                        FileRecognizer.once(c, raw, pcm.sampleRate, lang, v)
                    }
                    if (r == null) { say("$lang $v: null"); continue }
                    say("$lang $v [${r.ms}ms] '${r.text}' parts=${r.parts.size}")
                    r.parts.forEach { say("   ${it.startMs}ms ${it.text}") }
                }
            }
            say("done")
        }
        Column(Modifier.fillMaxSize().background(Color.White).padding(16.dp)
            .verticalScroll(rememberScrollState())) {
            Text(log, fontSize = 12.sp, color = Color.Black)
        }
    }
}
