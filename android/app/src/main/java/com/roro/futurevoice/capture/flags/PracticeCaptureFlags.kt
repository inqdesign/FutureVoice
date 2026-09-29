package com.roro.futurevoice.capture.flags

import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.Session
import kotlinx.coroutines.delay

/**
 * The Practice screens' capture seams — Android's half of the iOS
 * `DebugCapture` statics the Practice modes set (`previewDrillTray`,
 * `previewDrillFolder`, `previewStudyTray`, `previewWordCard`,
 * `slowLookupSeconds`, `failLookups`, `stubWordEntry`).
 *
 * Only the capture build type ever writes these; in every other build they
 * keep their defaults and each screen behaves exactly as it always has.
 */
object PracticeCaptureFlags {
    /** Drill deck opens revealed and frozen mid-drag over the Tomorrow folder. */
    @JvmField var previewDrillTray = false

    /** Drill deck opens with the Tomorrow folder sheet already presented. */
    @JvmField var previewDrillFolder = false

    /** Study deck opens revealed and frozen mid-drag (folders out). */
    @JvmField var previewStudyTray = false

    /** The word cloud opens with this word's card already up. */
    @JvmField var cloudOpenWord: String? = null

    /** A capture run has no session: every dictionary lookup answers nil
     *  without touching the network, as it does on iOS. */
    @JvmField var offlineLookups = false

    /** Hold every lookup this long first, so the loading state can be shot. */
    @JvmField var slowLookupMs = 0L

    /** Every lookup returns this entry instead (iOS `stubWordEntry`). */
    @JvmField var stubWordEntry: WordLore.Entry? = null

    /** The talk book reads this session instead of the store (iOS hands
     *  `ConversationDetailView` a session value that was never saved). */
    @JvmField var talkDetailSession: Session? = null

    /** The talk book opens on this chapter (`TalkChapter` name). */
    @JvmField var talkDetailChapter: String? = null

    /** The talk book opens with the transcript already unfolded — Android
     *  has no separate transcript destination, so this is how the shot of it
     *  is reached (iOS captures `TalkTranscriptView` on its own). */
    @JvmField var talkDetailTranscript = false

    /** The scenario book reads this scenario instead of the store. */
    @JvmField var bookScenario: Scenario? = null

    /** The scenario book opens on this chapter (`Chapter` name). */
    @JvmField var bookChapter: String? = null

    /** The talk / scenario book opens straight into Say it again, parked on
     *  this stage: "intro", "reading" or "done" (iOS
     *  `DebugCapture.sayItAgainStage`). A capture run has no mic, so the two
     *  running states are SEEDED rather than driven. */
    @JvmField var sayItAgainStage: String? = null

    /** Every dictionary lookup on a Practice screen goes through here. */
    suspend fun lookup(real: suspend () -> WordLore.Entry?): WordLore.Entry? {
        if (slowLookupMs > 0) delay(slowLookupMs)
        stubWordEntry?.let { return it }
        if (offlineLookups) return null
        return real()
    }
}
