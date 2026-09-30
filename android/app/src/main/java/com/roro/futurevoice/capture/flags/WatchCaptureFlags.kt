package com.roro.futurevoice.capture.flags

import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.talk.SuggestedTopic

/**
 * Screenshot-harness hooks for the Watch and Progress screens — Android's
 * half of the iOS `DebugCapture` statics those modes set
 * (`previewSceneFinished`, `composerPreview`). Only the capture build ever
 * sets them; every field is false/null in a normal build, so the screens
 * behave exactly as before.
 */
object WatchCaptureFlags {
    /**
     * iOS `previewSceneFinished`: the Watch scene opens already FINISHED on
     * the scenario's saved take — no scene is written, nothing is spoken, the
     * end-of-scene buttons are up. A capture must never call the model or TTS.
     */
    @JvmField var previewSceneFinished = false

    /**
     * iOS `composerPreview` + `sampleCategoryIdeas`: the composer opens with
     * the Cafe category already picked and these ideas as its chips, so the
     * narrowing step renders offline.
     */
    @JvmField var composerPreviewIdeas: List<SuggestedTopic>? = null

    /**
     * Find people's stranger pool, rendered instead of fetching
     * `public_personas` (and the Core badges) — the capture app is offline
     * and signed out.
     */
    @JvmField var samplePool: List<PublicPersonaClient.PublicPersona>? = null

    /**
     * iOS `-intakeStep <n>`: the guided new-person intake opens on card n
     * (0 = who … 6 = style) with iOS's stand-in answers — name "Boram", a
     * fellow parent. Null = the intake starts blank on the first card.
     */
    @JvmField var intakeStep: Int? = null
}
