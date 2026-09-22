package com.roro.futurevoice.data

import com.roro.futurevoice.R

/**
 * Where a learner reaches the person building this, in one tap — port of
 * `SupportChannel.swift`.
 *
 * **Not email.** A mail draft is a form: a subject line, a signature, an
 * empty body that asks to be composed — and the answer comes back hours
 * later into an inbox nobody opens for fun. A DM is a sentence. The whole
 * point of a one-person app is that the person is reachable, and the channel
 * has to feel like reaching a person.
 *
 * **Instagram is the primary, and Threads deliberately is not.** Threads has
 * no direct messages at all — a reply there is a public post, which is a
 * different thing with a different audience, and the one time someone most
 * wants to write is when something went wrong in private. Threads accounts
 * are Instagram accounts, so the same person is behind `ig.me`.
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
    TELEGRAM("", R.string.telegram);   // e.g. "nawanaapp"

    /** `ig.me/m/` is Instagram's own "message this account" link: it opens
     *  the app on a DM thread, and the web on a desktop. */
    val url: String?
        get() = when {
            handle.isEmpty() -> null
            this == INSTAGRAM -> "https://ig.me/m/$handle"
            else -> "https://t.me/$handle"
        }

    val subtitle: String get() = "@$handle"

    companion object {
        /** Channels that are actually set up, in the order they show. */
        val available: List<SupportChannel> get() = entries.filter { it.handle.isNotEmpty() }
    }
}
