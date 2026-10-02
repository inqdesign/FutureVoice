package com.roro.futurevoice.talk

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * What the model is told about WHEN it is — iOS `PromptClock` (2026-09-28),
 * the only clock any prompt has.
 *
 * Without it the call prompt carried no date, no time and no talk history,
 * and the model — told elsewhere never to say "I don't know" — guessed:
 * "long time no see" on a second call the same day, "this afternoon" at
 * eight in the morning. Seen on Android 2026-10-02: "pasta for a Sunday
 * night" on a Friday morning.
 *
 * PINNED when the call starts: the prompt is handed to the gateway once and
 * must describe one moment. Every distance in days is a CALENDAR distance
 * ([calendarDays]), never elapsed time over 24 h.
 */
data class PromptClock(
    /** When this call started, epoch ms. */
    val now: Long,
    val zone: ZoneId,
    /** Talks the learner SPOKE in earlier today, any language, not this one. */
    val talksEarlierToday: Int,
    val lastTalkToday: Long?,
    val lastTalkBeforeToday: Long?,
    /** This call picks up a saved talk paused at this moment. */
    val resumedFrom: Long? = null,
) {
    companion object {
        /**
         * Build from the saved talks of EVERY language — the fluent self is
         * one person. A talk counts only if the learner said something; it
         * is dated by its LAST line; anything after [now] is ignored.
         */
        fun make(now: Long = System.currentTimeMillis(), sessions: List<Session>,
                 excluding: String? = null, resumedFrom: Long? = null,
                 zone: ZoneId = ZoneId.systemDefault()): PromptClock {
            val startOfToday = LocalDate.ofInstant(Instant.ofEpochMilli(now), zone)
                .atStartOfDay(zone).toInstant().toEpochMilli()
            val times = sessions.mapNotNull { s ->
                if (s.id == excluding || s.turns.none { it.role == TurnRole.USER }) return@mapNotNull null
                val at = s.turns.maxOfOrNull { it.timestamp } ?: s.endedAt ?: s.startedAt
                at.takeIf { it <= now }
            }
            val today = times.filter { it >= startOfToday }
            val before = times.filter { it < startOfToday }
            return PromptClock(now, zone, today.size, today.maxOrNull(), before.maxOrNull(),
                resumedFrom?.let { minOf(it, now) })
        }

        /** Whole calendar days from [from] to [to] in [zone]; never negative. */
        fun calendarDays(from: Long, to: Long, zone: ZoneId = ZoneId.systemDefault()): Int {
            val a = LocalDate.ofInstant(Instant.ofEpochMilli(from), zone)
            val b = LocalDate.ofInstant(Instant.ofEpochMilli(to), zone)
            return maxOf(0L, ChronoUnit.DAYS.between(a, b)).toInt()
        }

        /** Before 5 is still the night before in anyone's head. */
        fun partOfDay(hour: Int): String = when (hour) {
            in 5..11 -> "morning"
            in 12..16 -> "afternoon"
            in 17..21 -> "evening"
            else -> "night"
        }

        fun gap(from: Long, to: Long, zone: ZoneId = ZoneId.systemDefault()): String {
            val days = calendarDays(from, to, zone)
            if (days == 0) {
                val minutes = maxOf(0L, (to - from) / 60_000).toInt()
                if (minutes < 10) return "a few minutes ago"
                if (minutes < 60) return "about $minutes minutes ago"
                val hours = minutes / 60
                return if (hours == 1) "about an hour ago" else "about $hours hours ago"
            }
            val weekday = " (${fmt("EEEE", zone).format(Instant.ofEpochMilli(from))})"
            return when {
                days == 1 -> "yesterday$weekday"
                days < 7 -> "$days days ago$weekday"
                days < 14 -> "$days days ago"
                days < 60 -> "${days / 7} weeks ago"
                else -> "${days / 30} months ago"
            }
        }

        /** English, Gregorian, in the learner's zone — the model never converts. */
        private fun fmt(pattern: String, zone: ZoneId): DateTimeFormatter =
            DateTimeFormatter.ofPattern(pattern, Locale.US).withZone(zone)

        /** "Monday, 28 September 2026". */
        fun dayLine(at: Long, zone: ZoneId = ZoneId.systemDefault()): String =
            fmt("EEEE, d MMMM yyyy", zone).format(Instant.ofEpochMilli(at))
    }

    /**
     * The block the conversation prompt carries. [includeHistory] is false
     * for a cast stranger and for the first meeting, whose own blocks define
     * the relationship.
     */
    fun promptBlock(includeHistory: Boolean): String {
        val day = dayLine(now, zone)
        val time = fmt("HH:mm", zone).format(Instant.ofEpochMilli(now))
        val part = partOfDay(ZonedDateTime.ofInstant(Instant.ofEpochMilli(now), zone).hour)
        val lines = mutableListOf("- This call started on $day, at $time — $part where the user is.")
        if (includeHistory) {
            if (talksEarlierToday == 0) {
                lines += "- This is their FIRST talk today."
            } else {
                val latest = lastTalkToday?.let { ", the latest ended ${gap(it, now, zone)}" } ?: ""
                val count = if (talksEarlierToday == 1) "1 talk" else "$talksEarlierToday talks"
                lines += "- They already had $count earlier today$latest."
            }
            if (lastTalkBeforeToday != null) {
                lines += "- Before today, their last talk was ${gap(lastTalkBeforeToday, now, zone)}."
            } else if (talksEarlierToday == 0) {
                lines += "- They have never had a talk here before this one."
            }
        }
        resumedFrom?.let {
            lines += "- This call RESUMES a saved talk that paused ${gap(it, now, zone)}. The lines already in the conversation were said then, not just now — pick it back up the way you would after that much time."
        }
        return "\n\nWHEN THIS IS — the user's own clock, and your ONLY source for time:\n" +
            lines.joinToString("\n") + "\n" +
            "Use this to get time RIGHT, not to talk about it. Greet for the part of " +
            "the day it actually is, or don't mention it at all. Never announce the " +
            "date, a count of talks, or how long it has been unless it comes up " +
            "naturally. A talk earlier today means you spoke recently — never greet " +
            "them as if after a long absence. Anything about time that is not " +
            "written here — the hour later in the call, a count, a gap — you do NOT " +
            "know: never guess it, and never invent how many times you have talked. " +
            "If you are playing a character in a scene rather than their future " +
            "self, their talk history is not yours; leave it out."
    }
}
