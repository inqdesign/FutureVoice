package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Which first-visit guides this install has seen — iOS `PageIntroStore`
 * (`e4bcd83`, `e864003`). Device-local on purpose: a second device is a
 * second first look. Same keys as iOS, so a backup carries the answer.
 */
object PageIntroStore {
    /** The five tabs plus My routine, by the raw value iOS stores. */
    enum class Page(val raw: String) {
        TALK("talk"),
        /** The Speech tab (iOS 1.1.4 (72), `6f2ccd53`). */
        SPEECH("speech"),
        WATCH("watch"), REVIEW("review"), PROGRESS("progress"),
        /** Not a tab: My routine, reached from the Talk header's streak. */
        ROUTINE("routine");

        companion object {
            val tabs = listOf(TALK, SPEECH, WATCH, REVIEW, PROGRESS)
            fun from(raw: String): Page? = entries.firstOrNull { it.raw == raw }
        }
    }

    private const val PREFS = "futurevoice"
    /**
     * `v2` (iOS a2788455, 1.1.4, founder: "every user sees the guide cards
     * once, the first time"): the guides were finished for this release, so
     * everyone gets each tab's guide once — existing learners included, and
     * installs that flipped through an earlier cut start over. The old rule
     * marked every tab seen for anyone who had already talked; that hid the
     * guides from exactly the people the pages changed under.
     */
    private fun key(page: Page) = "futurevoice.pageIntro.seen.v2.${page.raw}"

    private val _revision = MutableStateFlow(0)
    /** Moves on every mark / reset, so a host waiting on a guide re-checks. */
    val revision: StateFlow<Int> = _revision

    /** True while a guide sheet is up — other auto-raised sheets wait. */
    val showing = MutableStateFlow(false)

    @Suppress("RedundantSuspendModifier")
    suspend fun isDue(context: Context, page: Page): Boolean =
        !prefs(context).getBoolean(key(page), false)

    /** The cheap read, for gates that can't suspend. */
    fun wasSeen(context: Context, page: Page): Boolean =
        prefs(context).getBoolean(key(page), false)

    fun markSeen(context: Context, page: Page) {
        prefs(context).edit().putBoolean(key(page), true).apply()
        _revision.value++
    }

    /** Me → App guide's "show them again": each tab opens with its guide
     *  the next time it is opened. */
    fun resetAll(context: Context) {
        val e = prefs(context).edit()
        Page.entries.forEach { e.remove(key(it)) }
        e.apply()
        _revision.value++
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
