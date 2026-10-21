package com.roro.futurevoice.data

import com.roro.futurevoice.R

/**
 * Where a learner reaches the person building this, in one tap — port of
 * `SupportChannel.swift`.
 *
 * **A DM first, email beside it.** A mail draft is a form: a subject line, a
 * signature, an empty body that asks to be composed — a DM is a sentence, and
 * the whole point of a one-person app is that the person is reachable. But
 * not everyone has Instagram, and some things (a receipt, a screenshot of a
 * charge) are easier to send as a mail, so email sits under the DM
 * (2026-10-21, founder) at the same address the Privacy page names.
 *
 * **Instagram first, Threads beside it.** `https://ig.me/m/<handle>` opens
 * Instagram straight into a DM thread (the web when it isn't installed).
 * Threads has had DMs since July 2025, but in its OWN inbox, not Instagram's,
 * and there is no link that opens a thread with an account — so its row opens
 * the profile, where Message is one more tap (checked 2026-10-21). It is the
 * founder's own account, the one every mail to learners links to.
 *
 * Telegram is offered beside it for learners who don't use Instagram — the
 * app ships in several UI languages and Instagram is not universal.
 *
 * **A channel with no handle draws no row.** A contact row that opens
 * nothing is worse than no contact row at all, so filling these in is what
 * turns the section on.
 */
enum class SupportChannel(
    /** The account to write to. Handle only — no `@`, no URL. */
    val handle: String,
    val titleRes: Int,
) {
    INSTAGRAM("nawana.app", R.string.instagram_dm),
    THREADS("adaywithboram", R.string.threads_channel),
    EMAIL(ConsentStore.CONTACT_EMAIL, R.string.email),
    TELEGRAM("", R.string.telegram);   // e.g. "nawanaapp"

    /** `ig.me/m/` is Instagram's own "message this account" link: it opens
     *  the app on a DM thread, and the web on a desktop. */
    val url: String?
        get() = when {
            handle.isEmpty() -> null
            this == INSTAGRAM -> "https://ig.me/m/$handle"
            this == THREADS -> "https://www.threads.com/@$handle"
            this == EMAIL -> "mailto:$handle"
            else -> "https://t.me/$handle"
        }

    val subtitle: String get() = if (this == EMAIL) handle else "@$handle"

    companion object {
        /** Channels that are actually set up, in the order they show. */
        val available: List<SupportChannel> get() = entries.filter { it.handle.isNotEmpty() }
    }
}
