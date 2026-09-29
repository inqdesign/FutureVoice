package com.roro.futurevoice.capture.flags

import com.roro.futurevoice.data.WeeklyTestItem

/**
 * The weekly test's capture seams (iOS `DebugCapture.weeklyTestKind` /
 * `weeklyTestAnswer`). Only the capture build writes these; everywhere else
 * they stay null and the screen behaves as it always does.
 */
object WeeklyTestCaptureFlags {
    /** Always deal a fresh paper and open it on an item of this kind. */
    @JvmField var kind: WeeklyTestItem.Kind? = null

    /** Pre-answer the first item: true = right, false = wrong. */
    @JvmField var answer: Boolean? = null

    /** A capture run has no session: meaning items read their gloss here. */
    @JvmField var glosses: Map<String, String>? = null
}
