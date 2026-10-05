package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.roro.futurevoice.capture.flags.SpeechCaptureFlags
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.SpeechCoaching
import com.roro.futurevoice.data.SpeechGenre
import com.roro.futurevoice.data.SpeechKeyTerm
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechMetrics
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.ui.HomeTab
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.speech.SpeechComposerSheet
import com.roro.futurevoice.ui.speech.SpeechOwnScriptSheet
import com.roro.futurevoice.ui.speech.SpeechPlusSheet
import com.roro.futurevoice.ui.speech.SpeechPrompterScreen
import com.roro.futurevoice.ui.speech.SpeechResultScreen
import com.roro.futurevoice.ui.speech.SpeechScriptSheet

/**
 * The Speech tab (iOS `DebugCaptureHarness` speech modes, HEAD `8f135c24`):
 *
 *   speech                the tab: the bundled script plus two written ones
 *   speech-composer       "Write with AI"
 *   speech-prompter       mid-take: a third of the way through, mic panel
 *                         (`--ez fakecam true` puts iOS's stand-in picture
 *                         where the camera goes)
 *   speech-open           the prompter as a tap opens it: cursor 0, ready
 *   speech-plus           the Plus sheet a Light account meets on +
 *   speech-script-sheet   the whole-script sheet for a written script
 *   speech-script-edit    its editor
 *   speech-own            "Add my own script"
 *   speech-result         a scored take, coach notes landed
 */
object CaptureSpeech {
    private fun native(context: Context) = context.getSharedPreferences("futurevoice", 0)
        .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative()

    private fun fakeCam(context: Context) =
        (context as? android.app.Activity)?.intent?.getBooleanExtra("fakecam", false) == true

    /** iOS `seedSpeech`: two written scripts and a scored take of the sample. */
    private suspend fun seed(context: Context) = CaptureSeed.once("speech") {
        val store = SpeechStore.shared(context)
        store.reload()
        val lang = LanguageScope.active(context)
        val now = System.currentTimeMillis()
        val written = SpeechScript(
            id = "C0FFEE00-0000-4000-8000-000000000001", title = "Marie Curie, twice a Nobel winner",
            genre = SpeechGenre.PERSON, topic = "Marie Curie",
            body = "Marie Curie is the only person to win Nobel Prizes in two different sciences. Born in Warsaw in 1867, she moved to Paris to study, at a time when few universities admitted women.\n\nWith her husband Pierre, she discovered two new elements, polonium and radium. She coined the word radioactivity.\n\nHer notebooks are still radioactive today, and are kept in lead-lined boxes.",
            summary = "The scientist who discovered radium, and the only person with Nobels in two sciences.",
            keyTerms = listOf(SpeechKeyTerm("radioactivity", "Strahlung · 방사능"), SpeechKeyTerm("lead-lined", "lined with lead")),
            sources = listOf("Nobel Prize Outreach", "Encyclopaedia Britannica"),
            language = lang, targetSeconds = 60, createdAt = now - 3_600_000)
        val news = SpeechScript(
            id = "C0FFEE00-0000-4000-8000-000000000002", title = "Why the sky is blue",
            genre = SpeechGenre.EXPLAINER,
            body = "Sunlight looks white, but it is a mix of every colour. Blue light has a short wavelength, so air molecules scatter it far more than red.",
            sources = listOf("NASA"), language = lang, targetSeconds = 30, createdAt = now - 86_400_000)
        store.add(news)
        store.add(written)
        val builtIn = store.scripts.value.firstOrNull { it.isBuiltIn } ?: return@once
        store.save(SpeechTake(
            id = "C0FFEE00-0000-4000-8000-0000000000A1", scriptId = builtIn.id, createdAt = now,
            durationSeconds = 62.0, audioFilename = "missing.wav",
            transcript = "Good evening. Tonight, a question most of us never um stop to ask: how do noise-cancelling headphones actually work?",
            metrics = SpeechMetrics(accuracy = 91, rate = 168, rateLow = 120, rateHigh = 160, paceScore = 90,
                pausesAtBreaks = 7, breaks = 9, hesitations = 1, pauseScore = 70, fillers = 3, fillerScore = 82,
                steadiness = 74, missed = listOf("in a fraction of a millisecond", "rising and falling"), overall = 84),
            coaching = SpeechCoaching("Clear and confident opening — the middle ran a little fast.", listOf(
                "Slow down in the third paragraph and land each sentence on a full stop.",
                "You skipped “in a fraction of a millisecond” — say it as one breath.",
                "Keep your volume up on the last word of each sentence.")),
        ))
    }

    @Composable
    private fun Seeded(context: Context, content: @Composable () -> Unit) {
        var ready by remember { mutableStateOf(false) }
        LaunchedEffect(Unit) { seed(context); StoreEvents.bump(); ready = true }
        if (ready) Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) { content() }
    }

    private fun builtIn(context: Context) = SpeechLibrary.builtIn(LanguageScope.active(context))!!

    @Composable
    private fun Prompter(context: Context, cursor: Int?) {
        SpeechCaptureFlags.fakeCamera = fakeCam(context)
        Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
            SpeechPrompterScreen(builtIn(context), native(context), CefrLevel.B1, onClose = {}, previewCursor = cursor)
        }
    }

    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "speech" to { ctx -> CaptureTalk.TabShot(ctx, HomeTab.SPEECH) { seed(ctx) } },
        "speech-composer" to { ctx ->
            Seeded(ctx) {
                SpeechComposerSheet(LanguageScope.active(ctx), native(ctx), CefrLevel.B1, onWritten = {}, onDismiss = {})
            }
        },
        "speech-prompter" to { ctx -> Prompter(ctx, 24) },
        "speech-open" to { ctx -> Prompter(ctx, null) },
        "speech-plus" to { ctx -> Seeded(ctx) { SpeechPlusSheet(isLight = true, onDismiss = {}) } },
        "speech-script-sheet" to { ctx ->
            Seeded(ctx) {
                val s = SpeechStore.shared(ctx).scripts.value.first { !it.isBuiltIn && it.genre == SpeechGenre.PERSON }
                SpeechScriptSheet(s, native(ctx), onEdited = {}, onDismiss = {})
            }
        },
        "speech-script-edit" to { ctx ->
            Seeded(ctx) {
                val s = SpeechStore.shared(ctx).scripts.value.first { !it.isBuiltIn && it.genre == SpeechGenre.PERSON }
                SpeechOwnScriptSheet(s, s.language, native(ctx), onSave = {}, onDismiss = {})
            }
        },
        "speech-own" to { ctx ->
            Seeded(ctx) { SpeechOwnScriptSheet(null, LanguageScope.active(ctx), native(ctx), onSave = {}, onDismiss = {}) }
        },
        "speech-result" to { ctx ->
            Seeded(ctx) {
                val take = SpeechStore.shared(ctx).takes.value.first()
                SpeechResultScreen(take.id, null, onBack = {}, onAgain = {})
            }
        },
    )
}
