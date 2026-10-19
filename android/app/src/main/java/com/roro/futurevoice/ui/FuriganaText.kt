package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.isSpecified
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.data.Furigana
import com.roro.futurevoice.data.LanguageScope

/** iOS `.caption2` (11 pt) — the ruby over a call line, a coach line. */
@Composable
fun rubyCaption2(): TextStyle = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp)

/** iOS `.caption` (12 pt) — the ruby over the prompter and the shadow line. */
@Composable
fun rubyCaption(): TextStyle = MaterialTheme.typography.labelSmall

/**
 * A Japanese line with its readings drawn small above the kanji (iOS
 * `FuriganaText`, `Furigana`). Compose's `Text` has no ruby, so the line is
 * laid out as units — one per kanji run with its reading, one per other
 * character — that wrap like Japanese does, anywhere, with closing
 * punctuation held on the unit before it so 。 never starts a line.
 *
 * Falls back to [fallback] (the surface's own plain rendering) whenever the
 * setting is off, the target isn't Japanese or the line has no kanji, so
 * every other language and every kana-only line draw exactly as before.
 */
@Composable
fun FuriganaText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    rubyStyle: TextStyle = rubyCaption2(),
    alignment: Alignment.Horizontal = Alignment.Start,
    style: TextStyle = LocalTextStyle.current,
    fontWeight: FontWeight? = null,
    fallback: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val plain = text.text
    if (Furigana.enabled(context) && LanguageScope.active(context) == "ja" && Furigana.hasRuby(plain)) {
        val base = if (fontWeight != null) style.copy(fontWeight = fontWeight) else style
        val baseColor = base.color.takeIf { it.isSpecified } ?: LocalContentColor.current
        RubyFlow(alignment, modifier = modifier.clearAndSetSemantics { contentDescription = plain }) {
            for (unit in units(plain)) {
                RubyUnit(unit.reading, rubyStyle, baseColor.copy(alpha = baseColor.alpha * RUBY_ALPHA)) {
                    Text(text.subSequence(unit.start, unit.end), style = base, color = baseColor,
                        maxLines = 1, softWrap = false)
                }
            }
        }
    } else {
        fallback()
    }
}

/** A plain String line whose fallback is a plain `Text` in [style]. */
@Composable
fun FuriganaText(
    text: String,
    modifier: Modifier = Modifier,
    rubyStyle: TextStyle = rubyCaption2(),
    alignment: Alignment.Horizontal = Alignment.Start,
    style: TextStyle = LocalTextStyle.current,
    fontWeight: FontWeight? = null,
) = FuriganaText(AnnotatedString(text), modifier, rubyStyle, alignment, style, fontWeight) {
    Text(text, modifier, style = style, fontWeight = fontWeight)
}

/** iOS `.secondary` over the base's own colour. */
private const val RUBY_ALPHA = 0.6f

private data class RubySpan(val start: Int, val end: Int, val reading: String?)

private val CLOSING = setOf('、', '。', '，', '．', '！', '？', '!', '?', ',', '.', '」', '』', '）', ')', 'ー',
    'っ', 'ゃ', 'ゅ', 'ょ', 'ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ', 'ッ', 'ャ', 'ュ', 'ョ', '…', '〜', '～')
private val OPENING = setOf('「', '『', '（', '(')

/**
 * Where the line may break: around every ruby run and between every other
 * character, except inside a run of Latin letters or digits, and never
 * before closing punctuation or after an opening bracket.
 */
private fun units(plain: String): List<RubySpan> {
    val out = ArrayList<RubySpan>()
    var openPending: Int? = null
    fun push(start: Int, end: Int, reading: String?) {
        val s = openPending ?: start
        openPending = null
        out.add(RubySpan(s, end, reading))
    }
    for (run in Furigana.runs(plain)) {
        if (run.reading != null) { push(run.start, run.end, run.reading); continue }
        var i = run.start
        while (i < run.end) {
            val ch = plain[i]
            if (ch in CLOSING && out.isNotEmpty() && openPending == null) {
                val last = out.last()
                out[out.size - 1] = RubySpan(last.start, i + 1, last.reading)
                i += 1
                continue
            }
            if (ch in OPENING) {
                if (openPending == null) openPending = i
                i += 1
                continue
            }
            var j = i + 1
            if (ch.code < 128 && ch.isLetterOrDigit()) {
                while (j < run.end && plain[j].code < 128 && plain[j].isLetterOrDigit()) j++
            }
            push(i, j, null)
            i = j
        }
    }
    openPending?.let { out.add(RubySpan(it, plain.length, null)) }
    return out
}

/**
 * Wrapping row for [FuriganaText]: no gap between units, lines aligned as
 * asked, and only as wide as its widest line so a bubble still hugs a short
 * line.
 */
@Composable
private fun RubyFlow(
    alignment: Alignment.Horizontal,
    modifier: Modifier = Modifier,
    lineSpacing: Dp = 2.dp,
    content: @Composable () -> Unit,
) {
    Layout(content, modifier) { measurables, constraints ->
        val placeables = measurables.map { it.measure(Constraints()) }
        val maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth else Int.MAX_VALUE
        val lines = ArrayList<MutableList<Int>>()
        val widths = ArrayList<Int>()
        val heights = ArrayList<Int>()
        var line = ArrayList<Int>(); var w = 0; var h = 0
        placeables.forEachIndexed { i, p ->
            if (line.isNotEmpty() && w + p.width > maxWidth) {
                lines.add(line); widths.add(w); heights.add(h)
                line = ArrayList(); w = 0; h = 0
            }
            line.add(i); w += p.width; h = maxOf(h, p.height)
        }
        if (line.isNotEmpty()) { lines.add(line); widths.add(w); heights.add(h) }
        val gap = lineSpacing.roundToPx()
        val width = (widths.maxOrNull() ?: 0).coerceIn(constraints.minWidth, constraints.maxWidth)
        val height = (heights.sum() + gap * maxOf(0, lines.size - 1))
            .coerceIn(constraints.minHeight, constraints.maxHeight)
        layout(width, height) {
            var y = 0
            lines.forEachIndexed { n, items ->
                var x = alignment.align(widths[n], width, layoutDirection)
                for (i in items) {
                    placeables[i].placeRelative(x, y)
                    x += placeables[i].width
                }
                y += heights[n] + gap
            }
        }
    }
}

/**
 * A base with its reading above. The BASE sets the width: a reading wider
 * than its kanji (しゅうまつ over 週末) overhangs the kana beside it, as
 * printed ruby does, instead of opening a gap in the middle of the line. The
 * ruby row is reserved even with no reading, so bases share a line.
 */
@Composable
private fun RubyUnit(reading: String?, rubyStyle: TextStyle, rubyColor: Color, base: @Composable () -> Unit) {
    Layout({
        Text(reading ?: " ", style = rubyStyle, color = rubyColor, maxLines = 1, softWrap = false)
        base()
    }) { measurables, _ ->
        val ruby = measurables[0].measure(Constraints())
        val b = measurables[1].measure(Constraints())
        layout(b.width, ruby.height + b.height) {
            if (reading != null) ruby.place((b.width - ruby.width) / 2, 0)
            b.place(0, ruby.height)
        }
    }
}

/**
 * One word of a line cut into words elsewhere (the shadow target's karaoke
 * words), with the readings of the WHOLE line laid over it: a word read on
 * its own loses its context (何 before で is なん). Every word of a line that
 * has any ruby reserves the ruby row, so the bases stay on one baseline.
 *
 * [offset] is where [word] starts in the line [runs] were cut from.
 */
@Composable
fun FuriganaWord(
    word: String,
    offset: Int,
    runs: List<Furigana.Run>,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    rubyStyle: TextStyle = rubyCaption(),
) {
    val end = offset + word.length
    val pieces = ArrayList<Furigana.Run>()
    for (run in runs) {
        if (run.end > offset && run.start < end) {
            pieces.add(Furigana.Run(maxOf(run.start, offset), minOf(run.end, end),
                if (run.start >= offset) run.reading else null))
        }
    }
    if (pieces.isEmpty()) pieces.add(Furigana.Run(offset, end, null))
    Row(modifier.clearAndSetSemantics { contentDescription = word }) {
        for (p in pieces) {
            RubyUnit(p.reading, rubyStyle, color.copy(alpha = color.alpha * RUBY_ALPHA)) {
                Text(word.substring(p.start - offset, p.end - offset), style = style, color = color,
                    maxLines = 1, softWrap = false)
            }
        }
    }
}
