package com.roro.futurevoice.data

import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Where a `futurevoice://` link the app itself sent lands — a widget tap, or
 * the review reminder. The Activity can be handed one before Compose has
 * drawn anything, so it is parked here and the root reads it when it can.
 *
 * Auth callbacks do NOT come through here: those are the Supabase SDK's, and
 * routing one twice would race the session it is trying to establish.
 */
object DeepLinkInbox {

    enum class Destination { VOCABULARY, EXPRESSIONS, PRACTICE, REVIEW }

    val pending = MutableStateFlow<Destination?>(null)

    fun deliver(intent: Intent?) {
        if (intent?.getBooleanExtra(ReviewQueue.OPEN_REVIEW_EXTRA, false) == true) {
            pending.value = Destination.REVIEW
            return
        }
        val uri = intent?.data ?: return
        if (uri.scheme != "futurevoice") return
        pending.value = when (uri.host ?: uri.schemeSpecificPart.trimStart('/')) {
            "vocab" -> Destination.VOCABULARY
            "expressions" -> Destination.EXPRESSIONS
            "practice" -> Destination.PRACTICE
            else -> return          // login, and anything we don't own
        }
    }

    fun consume(): Destination? = pending.value.also { pending.value = null }
}
