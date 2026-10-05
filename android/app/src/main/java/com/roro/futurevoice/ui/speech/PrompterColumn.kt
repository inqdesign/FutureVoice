package com.roro.futurevoice.ui.speech

import android.graphics.Canvas
import android.graphics.Typeface
import android.os.Build
import android.text.TextPaint
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.talk.SpeechPrompterTrack

/**
 * The prompter's words, laid out ONCE in pixels — iOS `SpeechPrompterColumn`
 * + `SpeechWordWrap`. The screen draws it and the take's video draws it, from
 * the same positions, so the video's script wraps exactly as the reader saw it
 * (iOS renders the column to an image for the same reason).
 *
 * Spacing is iOS's, in units of the text size: words `0.28` apart (none for
 * an unspaced language), lines `0.35` apart, paragraphs `0.9`, 24 pt sides.
 * One colour for every word — the karaoke colouring was pulled (iOS
 * `2e9873f2`): the moving colour pulled the eye off the line.
 */
class PrompterColumn(
    val track: SpeechPrompterTrack,
    language: String,
    val widthPx: Float,
    val textSizePx: Float,
    val sidePx: Float,
    color: Int,
) {
    data class Placed(val word: Int, val x: Float, val top: Float, val width: Float, val height: Float)

    val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
        textSize = textSizePx
        this.color = color
        typeface = if (Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.DEFAULT, 600, false)
            else Typeface.DEFAULT_BOLD
    }
    private val ascent = -paint.fontMetrics.ascent
    val lineHeight = paint.fontMetrics.descent - paint.fontMetrics.ascent
    val lineSpacing = textSizePx * 0.35f
    val placed: List<Placed>
    val height: Float

    init {
        val spacing = if (LanguageCatalog.writesSpaces(language)) textSizePx * 0.28f else 0f
        val lineWidth = widthPx - 2 * sidePx
        val out = ArrayList<Placed>(track.words.size)
        var y = 0f
        track.paragraphs.forEachIndexed { p, paragraph ->
            if (p > 0) y += lineHeight + textSizePx * 0.9f
            var x = 0f
            for (w in paragraph) {
                val width = paint.measureText(w.text)
                if (x > 0 && x + width > lineWidth) { y += lineHeight + lineSpacing; x = 0f }
                out += Placed(w.id, sidePx + x, y, width, lineHeight)
                x += width + spacing
            }
        }
        placed = out
        height = if (out.isEmpty()) 0f else y + lineHeight
    }

    /** The reader's spot for word [cursor]: its line's top, plus how far
     *  across the line it sits, in line advances (iOS `onCurrentWord`). */
    fun target(cursor: Int): Triple<Float, Float, Float>? {
        if (placed.isEmpty()) return null
        val f = placed[cursor.coerceIn(0, placed.size - 1)]
        val lineWidth = maxOf(1f, widthPx - 2 * sidePx)
        val across = ((f.x - sidePx) / lineWidth).coerceIn(0f, 1f)
        val advance = f.height + lineSpacing
        return Triple(f.top + across * advance, f.top, advance)
    }

    /** Draws the words whose line overlaps [from]…[to] (column pixels). */
    fun draw(canvas: Canvas, from: Float, to: Float) {
        for (p in placed) {
            if (p.top + p.height < from) continue
            if (p.top > to) break
            canvas.drawText(track.words[p.word].text, p.x, p.top + ascent, paint)
        }
    }
}
