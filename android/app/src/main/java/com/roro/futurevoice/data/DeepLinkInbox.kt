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

    enum class Destination { VOCABULARY, EXPRESSIONS, PRACTICE, REVIEW, REVIEW_ITEM }

    /** A widget tap that has to clear whatever page is open: the Talk tab, a
     *  book, or a call to start (iOS RootTabView "talk" / "book" / "freetalk"). */
    sealed interface WidgetRoute {
        data object Talk : WidgetRoute
        data class Book(val kind: String, val id: String) : WidgetRoute
        data object FreeTalk : WidgetRoute
    }

    val widgetRoute = MutableStateFlow<WidgetRoute?>(null)

    val pending = MutableStateFlow<Destination?>(null)

    /** The one item a per-item reminder named: (kind, value). Read by the
     *  root when it handles [Destination.REVIEW_ITEM]. */
    val reviewItem = MutableStateFlow<Pair<String, String>?>(null)

    fun deliver(intent: Intent?) {
        val itemKind = intent?.getStringExtra(ReviewQueue.ITEM_KIND_EXTRA)
        val itemValue = intent?.getStringExtra(ReviewQueue.ITEM_VALUE_EXTRA)
        if (itemKind != null && itemValue != null) {
            reviewItem.value = itemKind to itemValue
            pending.value = Destination.REVIEW_ITEM
            return
        }
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
            // Streak widget: open Talk so the learner does something today.
            "talk" -> { widgetRoute.value = WidgetRoute.Talk; return }
            "freetalk" -> { widgetRoute.value = WidgetRoute.FreeTalk; return }
            // A routine's say-it-again reminder: the talk picker.
            "sayitagain" -> { PlanReminder.pendingSayItAgain.value = true; return }
            // Continue widget: that book's page, else the shelf.
            "book" -> uri.getQueryParameter("id")?.takeIf { it.isNotBlank() }?.let { id ->
                widgetRoute.value = WidgetRoute.Book(uri.getQueryParameter("type") ?: "talk", id)
                return
            } ?: Destination.PRACTICE
            // The weekly test lives on the Practice tab; the tab opens it.
            "weeklytest" -> { WeeklyTestInbox.pending.value = true; Destination.PRACTICE }
            // The week-turn notice spoke about the week: its cards, raised
            // over whatever is on screen (the deck's last card is the test).
            "weekrecap" -> { WeekRecapInbox.asked.value = true; return }
            else -> return          // login, and anything we don't own
        }
    }

    fun consume(): Destination? = pending.value.also { pending.value = null }
}
