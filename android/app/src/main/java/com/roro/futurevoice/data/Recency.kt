package com.roro.futurevoice.data

import android.icu.text.RelativeDateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * "2주 전", "어제", "방금" — when something last happened, as RECENCY.
 *
 * `DateUtils.getRelativeTimeSpanString` gives up after a week and prints an
 * absolute date, so a book studied a month ago read as "2026년 8월 30일"
 * beside iOS's "a month ago". A book's line is about how long it has been
 * left alone; a calendar date makes the reader do that subtraction.
 */
object Recency {
    fun label(at: Long, now: Long = System.currentTimeMillis()): String {
        val fmt = RelativeDateTimeFormatter.getInstance(Locale.getDefault())
        val seconds = (now - at) / 1000.0
        val past = seconds >= 0
        val direction = if (past) RelativeDateTimeFormatter.Direction.LAST
        else RelativeDateTimeFormatter.Direction.NEXT
        val magnitude = abs(seconds)
        val (value, unit) = when {
            magnitude < 60 -> 0.0 to RelativeDateTimeFormatter.RelativeUnit.SECONDS
            magnitude < 3_600 -> (magnitude / 60).roundToLong().toDouble() to
                RelativeDateTimeFormatter.RelativeUnit.MINUTES
            magnitude < 86_400 -> (magnitude / 3_600).roundToLong().toDouble() to
                RelativeDateTimeFormatter.RelativeUnit.HOURS
            magnitude < 7 * 86_400 -> (magnitude / 86_400).roundToLong().toDouble() to
                RelativeDateTimeFormatter.RelativeUnit.DAYS
            magnitude < 30 * 86_400 -> (magnitude / (7 * 86_400)).roundToLong().toDouble() to
                RelativeDateTimeFormatter.RelativeUnit.WEEKS
            magnitude < 365 * 86_400 -> (magnitude / (30 * 86_400)).roundToLong().toDouble() to
                RelativeDateTimeFormatter.RelativeUnit.MONTHS
            else -> (magnitude / (365 * 86_400)).roundToLong().toDouble() to
                RelativeDateTimeFormatter.RelativeUnit.YEARS
        }
        // Under a minute has no number worth printing.
        if (value == 0.0) {
            return fmt.format(RelativeDateTimeFormatter.Direction.PLAIN,
                RelativeDateTimeFormatter.AbsoluteUnit.NOW)
        }
        return fmt.format(value, direction, unit)
    }
}
