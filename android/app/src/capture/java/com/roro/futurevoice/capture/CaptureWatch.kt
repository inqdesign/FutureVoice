package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.capture.flags.WatchCaptureFlags
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.ComposerHost
import com.roro.futurevoice.ui.FindPeopleScreen
import com.roro.futurevoice.ui.PersonaDeepenSheet
import com.roro.futurevoice.ui.PracticeBody
import com.roro.futurevoice.ui.ScenarioComposer
import com.roro.futurevoice.ui.WatchSceneScreen
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * Capture modes for the Watch area. This file owns exactly these iOS modes:
 *
 *   watch
 *   watchtab
 *   watchtab-empty
 *   composer
 *   scene-end
 *   people
 *   intake-people
 *   deepen
 *   deepen-full
 *   intro-preview
 *   profile-notes
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 *
 * Absent on purpose: `watchtab` and `watchtab-empty`. The Watch tab's body
 * (`WatchBody`) and its tab chrome (`HomeScreen`) are PRIVATE to
 * `RootScreen.kt`, so no capture can call them without a change there.
 */
object CaptureWatch {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        // iOS: "The Watch tab folded into Practice's shelves" — `PracticeTab()`
        // on its default shelf, over the seeded books.
        "watch" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("watch") { CaptureSeed.seedScenarios(c) } }) {
                TabPage {
                    PracticeBody(
                        language = lang(c), level = level(c),
                        onOpenDeck = {}, onOpenWords = {}, onOpenExpressions = {},
                        onOpenScenarioBook = {}, onOpenTalk = {},
                    )
                }
            }
        },
        // The composer with Cafe picked and the sample ideas as its chips
        // (iOS `composerPreview`), opened from Talk ("Talk" CTA on iOS).
        "composer" to @Composable { c: Context ->
            Seeded({
                CaptureSeed.once("composer") { CaptureSeed.seedNews(c) }
                WatchCaptureFlags.composerPreviewIdeas = CaptureSeed.sampleCategoryIdeas
            }) {
                ScenarioComposer(
                    targetLanguage = lang(c), existingCategories = emptyList(),
                    host = ComposerHost.TALK, onDismiss = {},
                )
            }
        },
        // A finished barista scene: every line up, the end buttons showing,
        // nothing generated or spoken (iOS `previewSceneFinished`).
        "scene-end" to @Composable { c: Context ->
            var id by remember { mutableStateOf<String?>(null) }
            Seeded({
                id = CaptureSeed.seedSceneEndScenario(c)
                WatchCaptureFlags.previewSceneFinished = true
            }) {
                WatchSceneScreen(
                    scenarioId = id!!, voiceId = "", persona = null,
                    targetLanguage = lang(c), proficiency = level(c).code, onBack = {},
                )
            }
        },
        // The ONE people page: own people on top, the pool below — the pool
        // from sample rows, since the live table is out of reach offline.
        "people" to @Composable { c: Context ->
            Seeded({ WatchCaptureFlags.samplePool = CaptureSeed.samplePublicPersonas }) {
                FindPeopleScreen(language = lang(c), onTalk = {}, onOpenPerson = {}, onBack = {})
            }
        },
        // The post-first-talk persona sheet. Android's sheet has ONE height
        // (always fully expanded), so "deepen" and "deepen-full" are the same
        // state; and it opens over a blank ground, not the Talk home, because
        // `HomeScreen` is private to RootScreen.kt.
        "deepen" to @Composable { c: Context -> Deepen(c) },
        "deepen-full" to @Composable { c: Context -> Deepen(c) },
        // iOS `watchtab`: the Watch tab over the seeded scenarios.
        "watchtab" to { c ->
            CaptureTalk.TabShot(c, com.roro.futurevoice.ui.HomeTab.WATCH) {
                CaptureSeed.seedScenarios(c)
            }
        },
        // iOS `watchtab-empty`: a learner with no scenarios yet.
        "watchtab-empty" to { c ->
            CaptureTalk.TabShot(c, com.roro.futurevoice.ui.HomeTab.WATCH) {
                val store = com.roro.futurevoice.data.ScenarioStore.shared(c)
                store.load().forEach { store.delete(it.id) }
            }
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
        "intake-people" to "4.12 — Guided new-person intake (CounterpartVoiceIntakeView) not ported — " +
            "Android has only the plain person form; no plan item yet (nearest 2.25)",
        "intro-preview" to "Public-intro consent sheet (publish / edit first / not now) not ported — 2.1",
        "profile-notes" to "Remembered lines with their share lock and evidence not ported — 2.1",
    )

    @Composable
    private fun Deepen(c: Context) {
        var persona by remember { mutableStateOf<UserPersona?>(null) }
        Seeded({
            CaptureSeed.once("deepen") {
                CaptureSeed.seedVocab(c); CaptureSeed.seedSessions(c)
                CaptureSeed.seedNews(c); CaptureSeed.seedScenarios(c)
            }
            persona = PersonaStore.shared(c).load()
        }) {
            PersonaDeepenSheet(
                persona = persona,
                nativeLanguage = c.getSharedPreferences("futurevoice", 0)
                    .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative(),
                targetLanguage = lang(c),
                onSave = {}, onDismiss = {},
            )
        }
    }
}

private fun lang(c: Context) = LanguageScope.active(c)

private fun level(c: Context): CefrLevel = CefrLevel.from(
    c.getSharedPreferences("futurevoice", 0).getString("futurevoice.level.${lang(c)}", null))

/** Run the seed (and set any flag) first, then draw the real screen over it. */
@Composable
private fun Seeded(seed: suspend () -> Unit, content: @Composable () -> Unit) {
    var ready by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { seed(); StoreEvents.bump(); ready = true }
    if (ready) content()
}

/**
 * The container a tab body sits in inside `HomeScreen` (same ground, gutter,
 * spacing and scroll) — the tab's top bar and bottom bar are NOT drawn: they
 * live in `HomeScreen`, which is private to RootScreen.kt.
 */
@Composable
private fun TabPage(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(AppSurfaces.ground).statusBarsPadding()
            .verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        content()
        Spacer(Modifier.height(16.dp))
    }
}
