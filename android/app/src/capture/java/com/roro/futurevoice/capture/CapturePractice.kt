package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.runtime.Composable

/**
 * Capture modes for the Practice area. This file owns exactly these iOS modes:
 *
 *   practice-talk
 *   practice-watch
 *   practice-due
 *   practice-review-route
 *   practice-studying
 *   review-due
 *   review-item-word
 *   review-item-sentence
 *   drills
 *   drills-tray
 *   drills-folder
 *   daily-words
 *   daily-words-tray
 *   daily-words-full
 *   daily-expressions
 *   vocab
 *   vocab-card
 *   vocab-failed
 *   vocab-loading
 *   wordcard-ja
 *   expr
 *   book
 *   book-words
 *   book-lines
 *   talkdetail
 *   talkdetail-mid
 *   talkdetail-low
 *   talkdetail-words
 *   talkdetail-expressions
 *   talkdetail-lines
 *   talkdetail-cards
 *   talkdetail-ja
 *   finished
 *   finished-empty
 *   shadow
 *   shadow-ja
 *   score
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 */
object CapturePractice {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
    )
}
