package com.roro.futurevoice.capture.flags

/**
 * Speech-tab hooks for the screenshot harness (capture build only sets them;
 * every field is inert in a normal build).
 */
object SpeechCaptureFlags {
    /** A stand-in picture where the camera goes — iOS `-speechfakecam 1`:
     *  the on-camera chrome, with no camera in an emulator capture. */
    @Volatile var fakeCamera: Boolean = false

    /** Draw the speech sheets as the page itself — iOS's harness returns the
     *  sheet's view rather than presenting it. */
    @Volatile var inlineSheets: Boolean = false

    /** An account to draw voiceover prices and pools against (iOS
     *  `BillingGate.debugSetAccount`). */
    @Volatile var account: com.roro.futurevoice.data.AccountStatus? = null

    /** A ready study for the Script sheet, Study on (iOS `SpeechScriptSheet(study:)`). */
    @Volatile var study: com.roro.futurevoice.data.ScriptStudy? = null

    /** Study switched on when the Script sheet opens. */
    @Volatile var studyOn: Boolean? = null

    /** A highlight id whose card opens over the Script sheet. */
    @Volatile var studyCard: Int? = null

    /** The voice id the Script sheet / composers draw against. */
    @Volatile var voiceId: String? = null

    /** The composers open with "Also make it in my voice" on, the own-script
     *  editor with this draft. */
    @Volatile var voiceoverOn: Boolean = false
    @Volatile var ownDraft: String? = null
}
