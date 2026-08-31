package com.roro.futurevoice.ui.brand

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.roro.futurevoice.R

/**
 * The four verdicts a review card can be given, and the folders they land in.
 * Both decks — the sentence drill and the word/expression deck — file through
 * this one enum, so "Soon" can never mean two different things depending on
 * which sheet you are in.
 */
enum class DrillBin(val raw: String) {
    TEN_MINUTES("tenMinutes"),
    TOMORROW("tomorrow"),
    THREE_DAYS("threeDays"),
    GOT_IT("gotIt");

    /** Title on the drop target — the ACTION, in the tray under a held card. */
    val titleRes: Int
        get() = when (this) {
            TEN_MINUTES -> R.string.ten_min
            TOMORROW -> R.string.tomorrow
            THREE_DAYS -> R.string.three_days
            GOT_IT -> R.string.got_it
        }

    /**
     * Name at REST. Reads differently from the drop action that put a card
     * there, because the folder holds every card whose RETURN falls in its
     * window: "3 days" the action becomes "Later" the place.
     */
    val folderTitleRes: Int
        get() = when (this) {
            TEN_MINUTES -> R.string.soon
            TOMORROW -> R.string.tomorrow
            THREE_DAYS -> R.string.later
            GOT_IT -> R.string.known
        }

    val icon: ImageVector
        get() = when (this) {
            TEN_MINUTES -> Icons.Filled.Schedule
            TOMORROW -> Icons.Filled.WbTwilight
            THREE_DAYS -> Icons.Filled.DateRange
            GOT_IT -> Icons.Filled.CheckCircle
        }

    /** Soon → later → done, read as a warm-to-cool-to-green run. */
    val tint: Color
        get() = when (this) {
            TEN_MINUTES -> Color(0xFFFF9500)   // systemOrange
            TOMORROW -> Color(0xFF007AFF)      // systemBlue
            THREE_DAYS -> Color(0xFF5856D6)    // systemIndigo
            GOT_IT -> Color(0xFF34C759)        // systemGreen
        }

    /**
     * Leitner box + delay for the manual choices; null for [GOT_IT], which
     * hands the card straight to the top rung instead of writing a return.
     */
    val manual: Pair<Int, Long>?
        get() = when (this) {
            TEN_MINUTES -> 0 to SOON_DELAY_MS
            TOMORROW -> 1 to 24L * 60 * 60 * 1000
            THREE_DAYS -> 2 to 3L * 24 * 60 * 60 * 1000
            GOT_IT -> null
        }

    companion object {
        /** The shortest "show me again" delay, in ONE place so the label, the
         *  schedule and the notification can never disagree. */
        const val SOON_DELAY_MS = 10L * 60 * 1000

        /**
         * Which folder a still-future return time falls in. The windows are
         * generous on purpose — a folder is a rough "when is this coming
         * back", not a countdown — and they live here so the sentence deck and
         * the word/expression deck can never disagree about what "Soon" means.
         * (Neither deck asks about a return already in the past: that item is
         * in today's hand, not in a folder.)
         */
        fun folder(forReturnInMillis: Long): DrillBin = when {
            forReturnInMillis <= 12L * 60 * 60 * 1000 -> TEN_MINUTES
            forReturnInMillis <= 48L * 60 * 60 * 1000 -> TOMORROW
            else -> THREE_DAYS
        }
    }
}
