package com.roro.futurevoice.data

/**
 * How talk time is WRITTEN. One rule, two registers (iOS
 * `PracticeStats.talkClock` / `talkSpan`, 2026-09):
 *
 * - A DAY is a clock, mm:ss — the home ring, the activity day summary. A day
 *   can be 40 seconds or 40 minutes, and flooring calls 40 seconds "0 min".
 * - A SPAN — a month's pool, a plan's allowance — is minutes. The plan is
 *   sold in minutes, and "55 min 12 sec of 150 min" makes the remainder
 *   harder to read, not more precise. Under a minute it names the seconds:
 *   a new account's first 40 seconds must not read as nothing used.
 *
 * Nothing else may format talk time by hand — every surface reads one of
 * these two, so a talked day and a talked month are never called zero.
 */
object TalkTime {
    fun clock(seconds: Int): String {
        val s = maxOf(0, seconds)
        return "%02d:%02d".format(s / 60, s % 60)
    }

    /** Whether [span] should be read as seconds; the caller picks the string. */
    fun spanIsSeconds(seconds: Int): Boolean = seconds in 1..59
}
