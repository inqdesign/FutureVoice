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
}
