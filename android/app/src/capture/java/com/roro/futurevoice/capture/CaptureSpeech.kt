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
import com.roro.futurevoice.data.ScriptStudy
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.ui.HomeTab
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.speech.SpeechChallengeNameSheet
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
 *   speech-study-off/-on  the Script sheet, Study off / on (iOS 38d34fcd)
 *   speech-study-card     a highlight's card ("fall apart") over it
 *   speech-voiceover      the "Hear it in my voice" price under the script
 *   speech-composer-voiceover / speech-own-voiceover
 *                         the two creation flows with "Also make it in my voice" on
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
    private fun Seeded(context: Context, inline: Boolean = true, content: @Composable () -> Unit) {
        // iOS returns these sheets' views as the page; only speech-plus is
        // presented over a background.
        SpeechCaptureFlags.inlineSheets = inline
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

    /** iOS `studySampleScript`: the approved mockup's script. */
    private fun studyScript(language: String) = SpeechScript(
        id = "5EED0000-0000-4000-8000-0000000000D1", title = "Why practise out loud?",
        genre = SpeechGenre.EXPLAINER,
        body = "Have you ever had the perfect sentence in your head, only to watch it fall apart the moment you said it?\n" +
            "Speaking is a skill, not just knowledge. You can know the words and the grammar, but if your mouth has never actually built the sentence, it tends to let you down when it matters.\n" +
            "Saying things aloud also helps them stick. Research suggests we remember what we've said better than what we've only read.",
        language = language, targetSeconds = 60, createdAt = System.currentTimeMillis())

    /** iOS `studySample`. */
    private fun studySample(script: SpeechScript): ScriptStudy {

        val found = ScriptStudy.locate(listOf(
            ScriptStudy.Candidate("only to", ScriptStudy.Kind.GRAMMAR, note = "기대와 달리 결과가 실망스러울 때 써요. ‘…했는데 결국 …하고 말았다’는 흐름이에요.", example = "I ran to the station, only to miss the train."),
            ScriptStudy.Candidate("fall apart", ScriptStudy.Kind.EXPRESSION, note = "계획이나 말이 버티지 못하고 무너질 때 써요. 여기서는 준비한 문장이 말하는 순간 흐트러지는 느낌이에요.", example = "Our weekend plans fell apart when it started raining."),
            ScriptStudy.Candidate("not just", ScriptStudy.Kind.GRAMMAR, note = "‘단지 …만이 아니라’ — 뒤에 더 중요한 걸 덧붙일 때 써요."),
            ScriptStudy.Candidate("tends to", ScriptStudy.Kind.GRAMMAR, note = "‘…하는 경향이 있다’ — 늘 그렇다고 단정하지 않고 부드럽게 말할 때 써요."),
            ScriptStudy.Candidate("let you down", ScriptStudy.Kind.EXPRESSION, note = "기대를 저버리다, 실망시키다. 여기서는 입이 말을 안 들어준다는 뜻이에요."),
            ScriptStudy.Candidate("when it matters", ScriptStudy.Kind.EXPRESSION, note = "정말 중요한 순간에."),
            ScriptStudy.Candidate("stick", ScriptStudy.Kind.WORD, lemma = "stick", note = "머리에 남다, 기억되다."),
            ScriptStudy.Candidate("Research suggests", ScriptStudy.Kind.EXPRESSION, note = "근거를 소개할 때 쓰는 말이에요. ‘연구에 따르면’."),
        ), ScriptStudy.paragraphs(script.body), spaced = true)
        return ScriptStudy(found, listOf(
            "머릿속엔 완벽했던 문장이 입 밖으로 나오는 순간 무너진 경험을 물으며 시작해요.",
            "핵심 주장이에요. 단어와 문법을 알아도 입으로 직접 만들어 본 적이 없으면 중요한 순간에 안 나온다는 거예요.",
            "근거를 하나 더해요. 소리 내어 말한 건 눈으로 읽기만 한 것보다 더 오래 기억에 남아요.",
        ))
    }

    /** Study + voiceover modes: a voice and the Light sample account so the
     *  price line shows the pool it comes from (iOS 38d34fcd). */
    private fun studyFlags(mode: String, script: SpeechScript) {
        SpeechCaptureFlags.voiceId = SpeechCaptureFlags.voiceId ?: "capture-voice"
        SpeechCaptureFlags.account = CaptureSeed.sampleLightAccount
        val study = studySample(script)
        SpeechCaptureFlags.study = study
        SpeechCaptureFlags.studyOn = mode != "speech-study-off" && mode != "speech-voiceover"
        SpeechCaptureFlags.studyCard = if (mode == "speech-study-card")
            study.highlights.firstOrNull { it.text == "fall apart" }?.id else null
        SpeechCaptureFlags.voiceoverOn = mode.endsWith("-voiceover") && mode != "speech-voiceover"
        SpeechCaptureFlags.ownDraft = if (mode == "speech-own-voiceover") script.body else null
    }

    private fun studyMode(mode: String): @Composable (Context) -> Unit = { ctx ->
        val script = remember { studyScript(LanguageScope.active(ctx)).also { studyFlags(mode, it) } }
        Seeded(ctx) {
            when (mode) {
                "speech-composer-voiceover" ->
                    SpeechComposerSheet(script.language, native(ctx), CefrLevel.B1, onWritten = {}, onDismiss = {})
                "speech-own-voiceover" ->
                    SpeechOwnScriptSheet(null, script.language, native(ctx), onSave = {}, onDismiss = {})
                else -> SpeechScriptSheet(script, native(ctx), onEdited = {}, onDismiss = {})
            }
        }
    }

    val wired: Map<String, @Composable (Context) -> Unit> = listOf(
        "speech-study-off", "speech-study-on", "speech-study-card", "speech-voiceover",
        "speech-composer-voiceover", "speech-own-voiceover",
    ).associateWith { studyMode(it) } + mapOf(
        "speech" to { ctx -> CaptureTalk.TabShot(ctx, HomeTab.SPEECH) { seed(ctx) } },
        "speech-composer" to { ctx ->
            Seeded(ctx) {
                SpeechComposerSheet(LanguageScope.active(ctx), native(ctx), CefrLevel.B1, onWritten = {}, onDismiss = {})
            }
        },
        "speech-prompter" to { ctx -> Prompter(ctx, 24) },
        "speech-open" to { ctx -> Prompter(ctx, null) },
        // The name on the boards (iOS `SpeechChallengeNameSheet`, medium detent).
        "speech-name" to { ctx -> Seeded(ctx, inline = false) { SpeechChallengeNameSheet("Eunggyu", onDismiss = {}) } },
        "speech-plus" to { ctx -> Seeded(ctx, inline = false) { SpeechPlusSheet(isLight = true, onDismiss = {}) } },
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
