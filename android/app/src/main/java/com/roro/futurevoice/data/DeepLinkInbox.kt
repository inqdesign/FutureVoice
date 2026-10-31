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
        /** The routine widget: the block of this kind's door, or My routine
         *  when there is no kind (iOS `openRoutineBlock`, a0836bbe). */
        data class Routine(val kind: StudyPlan.Kind?) : WidgetRoute
        /** The tutor bot's "N cards waiting" → exactly those N cards (iOS
         *  `futurevoice://waiting`, bcddcc40). */
        data object Waiting : WidgetRoute
        /** A speech challenge's page (iOS `futurevoice://speech?id=…`: a
         *  challenge's push, the tutor bot's challenge pick). */
        data class SpeechChallenge(val id: String) : WidgetRoute
    }

    val widgetRoute = MutableStateFlow<WidgetRoute?>(null)

    /** Which in-app door staged a [WidgetRoute.FreeTalk] — telemetry only
     *  (iOS `requestFreeTalk(from:)`). Null = the widget's own link. */
    @Volatile var freeTalkEntry: String? = null

    /** A free talk asked for from inside the app (iOS `requestFreeTalk(from:)`). */
    fun requestFreeTalk(entry: String) {
        freeTalkEntry = entry
        widgetRoute.value = WidgetRoute.FreeTalk
    }

    val pending = MutableStateFlow<Destination?>(null)

    /** The word or phrase a `futurevoice://vocab?q=…` / `expressions?q=…`
     *  link names: its card opens on the list (iOS `focusWord` /
     *  `focusPhrase`). Read by the root with [Destination.VOCABULARY] /
     *  [Destination.EXPRESSIONS]. */
    val libraryFocus = MutableStateFlow<String?>(null)

    /** The words or expressions page, on one item's card when [q] is set. */
    fun openLibrary(destination: Destination, q: String?) {
        libraryFocus.value = q?.trim()?.ifEmpty { null }
        pending.value = destination
    }

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
            // A tapped widget note carries its item as ?q=… so that exact
            // word/phrase opens; absent, the plain list (iOS `handleURL`).
            "vocab" -> { libraryFocus.value = uri.getQueryParameter("q")?.ifBlank { null }; Destination.VOCABULARY }
            "expressions" -> { libraryFocus.value = uri.getQueryParameter("q")?.ifBlank { null }; Destination.EXPRESSIONS }
            "practice" -> Destination.PRACTICE
            // Streak widget: open Talk so the learner does something today.
            "talk" -> { widgetRoute.value = WidgetRoute.Talk; return }
            "freetalk" -> { widgetRoute.value = WidgetRoute.FreeTalk; return }
            // The routine widget: a block tapped opens that block.
            "routine" -> {
                val raw = uri.getQueryParameter("kind")
                widgetRoute.value = WidgetRoute.Routine(StudyPlan.Kind.entries.firstOrNull { it.raw == raw })
                return
            }
            // The tutor bot's Start: the cards it counted as waiting.
            "waiting" -> { widgetRoute.value = WidgetRoute.Waiting; return }
            // A routine's say-it-again reminder: the talk picker.
            "sayitagain" -> { PlanReminder.pendingSayItAgain.value = true; return }
            // A routine's Speech reminder: the Speech tab.
            "speech" -> {
                val id = uri.getQueryParameter("id")?.takeIf { it.isNotBlank() }
                if (id != null) widgetRoute.value = WidgetRoute.SpeechChallenge(id)
                else PlanReminder.pendingSpeech.value = true
                return
            }
            // A routine's listening reminder: the player, already playing.
            "listen" -> { PlanReminder.pendingListen.value = true; return }
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
