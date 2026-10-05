package com.roro.futurevoice.capture.flags

import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.talk.TalkUiState
import com.roro.futurevoice.ui.TalkGoalItem

/**
 * Talk-area hooks for the screenshot harness (capture build only sets them).
 * Every field is null in every normal build, so nothing here changes how the
 * app behaves — each one only lets a capture hand a real screen a state it
 * could otherwise reach only through the network, the mic or a live call.
 */
object TalkCaptureFlags {

    /**
     * A prepared call for `TalkScreen`: when set, the screen draws [state]
     * instead of its view model's, and never starts the call — no socket, no
     * mic, no notification ask, no "which mic?" sheet. iOS stages the same
     * states (`call-meter`, `call-goals`, `call-feed-fade`) from sample lines.
     */
    class CallPreview(
        val state: TalkUiState,
        val goals: List<TalkGoalItem> = emptyList(),
        val goalsUsed: Set<String> = emptySet(),
        /** A goal chip's sheet already open (iOS `GoalSheetPreview`). */
        val openGoal: TalkGoalItem? = null,
        /** A plain one-line title instead of topic · level (iOS stages
         *  `call-coach` / `call-focus` with `Text("Let's talk")` /
         *  `Text("Free talk")` as the principal item, no level line). */
        val titleRes: Int? = null,
    )

    @JvmField var callPreview: CallPreview? = null

    /**
     * The account the Talk header's avatar ring draws, instead of loading it
     * (a capture run is signed out). iOS injects one per capture name in
     * `ConversationHome.refreshAccount`.
     */
    @JvmField var headerAccount: AccountStatus? = null

    /**
     * The dictionary entry `TalkGoalSheet` shows instead of a WordLore lookup
     * (iOS `DebugCapture.stubWordEntry`).
     */
    @JvmField var stubGoalEntry: WordLore.Entry? = null

    /** The Discover chip Talk opens on (iOS `previewScenariosTab`, the
     *  `home-scenarios` capture opens on Everyday). */
    @JvmField var discoverTab: com.roro.futurevoice.ui.DiscoverTab? = null

    /** `VoiceRevivalScreen` holds this stage instead of rebuilding the voice
     *  ("rebuilding" or "tune" — iOS `voice-revival[-tune]`). */
    @JvmField var revivalStage: String? = null
}
