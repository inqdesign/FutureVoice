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
    /** The four tabs plus My routine, by the raw value iOS stores. */
    enum class Page(val raw: String) {
        TALK("talk"), WATCH("watch"), REVIEW("review"), PROGRESS("progress"),
        /** Not a tab: My routine, reached from the Talk header's streak. */
        ROUTINE("routine");

        companion object {
            val tabs = listOf(TALK, WATCH, REVIEW, PROGRESS)
            fun from(raw: String): Page? = entries.firstOrNull { it.raw == raw }
        }
    }

    private const val PREFS = "futurevoice"
    private const val PREPARED = "futurevoice.pageIntro.prepared"
    private fun key(page: Page) = "futurevoice.pageIntro.seen.${page.raw}"

    private val _revision = MutableStateFlow(0)
    /** Moves on every mark / reset, so a host waiting on a guide re-checks. */
    val revision: StateFlow<Int> = _revision

    /** True while a guide sheet is up — other auto-raised sheets wait. */
    val showing = MutableStateFlow(false)

    suspend fun isDue(context: Context, page: Page): Boolean {
        prepareOnce(context)
        return !prefs(context).getBoolean(key(page), false)
    }

    /** The cheap read, for gates that can't suspend. Ignores [prepareOnce]. */
    fun wasSeen(context: Context, page: Page): Boolean =
        prefs(context).getBoolean(key(page), false)

    fun markSeen(context: Context, page: Page) {
        prefs(context).edit().putBoolean(key(page), true).apply()
        _revision.value++
    }

    /**
     * The guides shipped after people already knew these pages. An install
     * that has talked before has opened every tab it cares about, so it is
     * marked as having seen the four TABS, once. Not My routine: its guide
     * came later than the page, and what it explains (which days are green)
     * is exactly what people who already use the page were asking.
     */
    private suspend fun prepareOnce(context: Context) {
        val p = prefs(context)
        if (p.getBoolean(PREPARED, false)) return
        p.edit().putBoolean(PREPARED, true).apply()
        val store = SessionStore.shared(context)
        val talked = LanguageScope.enrolled(context).any { code ->
            runCatching { store.load(code).isNotEmpty() }.getOrDefault(false)
        }
        if (talked) Page.tabs.forEach { markSeen(context, it) }
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
