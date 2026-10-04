package com.roro.futurevoice.ui

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import com.roro.futurevoice.talk.SpokenWords

/**
 * A corrected line with the parts the learner did NOT say lit — the one
 * painter every correction surface uses (iOS `highlightedCorrection`, one
 * function for the call card, the book, Say it again). What is lit is
 * [SpokenWords.changedRanges]: words for a spaced language (a contraction
 * the transcriber expanded lights nothing), characters for Japanese.
 */
fun correctionLine(alternative: String, original: String, language: String, lit: SpanStyle): AnnotatedString {
    val text = SpokenWords.displayText(alternative, language)
    val ranges = SpokenWords.changedRanges(alternative, original, language)
    return buildAnnotatedString {
        append(text)
        for (r in ranges) if (r.last < text.length) addStyle(lit, r.first, r.last + 1)
    }
}
