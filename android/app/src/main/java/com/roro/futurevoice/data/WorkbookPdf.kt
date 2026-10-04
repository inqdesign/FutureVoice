package com.roro.futurevoice.data

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import com.roro.futurevoice.R
import java.io.ByteArrayOutputStream

/**
 * Draws a [BookWorkbook] as an A4 PDF — the Android half of
 * `BookWorkbook.pdfData()`.
 *
 * iOS lays the workbook out as HTML through `UIPrintPageRenderer`, one
 * renderer per part. Android's HTML route is the system print sheet
 * ([BookExport.printPdf]), which can neither hand back a file nor say how many
 * pages a part took — and the cover's contents list needs exactly that. So the
 * workbook is laid out here, block by block, with [StaticLayout] and drawn
 * onto [PdfDocument]: text still flows across pages and stays real,
 * selectable text, and every part starts on its own page.
 *
 * Nothing on these pages is a filled area (only the current index tab), so a
 * workbook costs toner only where there is text — lines are a light grey a
 * home printer still prints and a pen still covers. The index tabs down the
 * right edge become real links afterwards ([PdfLinks]), which a tablet notes
 * app reads like a planner's.
 */
class WorkbookPdf(private val context: Context, doc: BookDocument) {

    private val wb = BookWorkbook(doc)
    private val doc = doc

    private fun s(id: Int) = context.getString(id)

    private data class Part(
        val id: BookWorkbook.PartId,
        val tab: String,
        val title: String,
        val blurb: String,
    )

    private fun describe(id: BookWorkbook.PartId): Part = when (id) {
        BookWorkbook.PartId.WORDS -> Part(id, s(R.string.words_d26d55),
            s(R.string.workbook_cover_and_write), s(R.string.workbook_words_blurb))
        BookWorkbook.PartId.EXPRESSIONS -> Part(id, s(R.string.expressions),
            s(R.string.workbook_copy_it_out), s(R.string.workbook_expressions_blurb))
        BookWorkbook.PartId.DRILL -> Part(id, s(R.string.workbook_mistakes),
            s(R.string.workbook_mistake_notebook), s(R.string.workbook_drill_blurb))
        BookWorkbook.PartId.DICTATION -> Part(id, s(R.string.workbook_dictation),
            s(R.string.workbook_dictation), s(R.string.workbook_dictation_blurb))
        BookWorkbook.PartId.RECALL -> Part(id, s(R.string.workbook_recall),
            s(R.string.workbook_blank_page), s(R.string.workbook_recall_blurb))
        BookWorkbook.PartId.ANSWERS -> Part(id, s(R.string.workbook_answers),
            s(R.string.workbook_answers), s(R.string.workbook_answers_blurb))
        BookWorkbook.PartId.DIALOGUE -> {
            val d = wb.dialogue
            val title = if (d?.kind == BookDocument.Section.Kind.SCENE) d.title
                else s(R.string.workbook_whole_conversation)
            Part(id, s(R.string.talk), title, s(R.string.workbook_dialogue_blurb))
        }
    }

    // MARK: - Page geometry (points, A4)

    private companion object {
        const val PAPER_W = 595
        const val PAPER_H = 842
        const val L = 44f
        const val TOP = 48f
        /** Wider on the right: the tabs live there. */
        const val RIGHT = PAPER_W - 70f
        const val BOTTOM = PAPER_H - 62f
        const val W = RIGHT - L

        const val INK = 0xFF111111.toInt()
        fun grey(hex: Int) = (0xFF shl 24) or (hex shl 16) or (hex shl 8) or hex
    }

    /** One run of pages. Blocks are measured, then recorded as draw calls with
     *  their final position; a block that would cross the bottom starts a page. */
    private class Flow {
        val pages = ArrayList<ArrayList<(Canvas) -> Unit>>()
        var y = TOP
        init { newPage() }
        fun newPage() { pages.add(ArrayList()); y = TOP }
        fun block(h: Float, draw: (Canvas, Float) -> Unit) {
            if (y + h > BOTTOM && y > TOP) newPage()
            val top = y
            pages.last().add { c -> draw(c, top) }
            y += h
        }
        fun gap(h: Float) { y += h }
    }

    // MARK: - Ink

    private fun text(size: Float, color: Int = INK, bold: Boolean = false,
                     italic: Boolean = false, spacing: Float = 0f) =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            this.color = color
            typeface = when {
                bold && italic -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD_ITALIC)
                bold -> Typeface.DEFAULT_BOLD
                italic -> Typeface.create(Typeface.DEFAULT, Typeface.ITALIC)
                else -> Typeface.DEFAULT
            }
            letterSpacing = spacing
        }

    private fun line(width: Float, color: Int, dash: Float = 0f) =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = width
            this.color = color
            if (dash > 0f) pathEffect = DashPathEffect(floatArrayOf(dash, dash), 0f)
        }

    private fun layout(t: CharSequence, p: TextPaint, width: Float,
                       align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL): StaticLayout =
        StaticLayout.Builder.obtain(t, 0, t.length, p, width.toInt().coerceAtLeast(1))
            .setAlignment(align)
            .setLineSpacing(0f, 1.18f)
            .setIncludePad(false)
            .build()

    private fun Canvas.put(l: StaticLayout, x: Float, y: Float) {
        save(); translate(x, y); l.draw(this); restore()
    }

    private fun Canvas.hline(x1: Float, x2: Float, y: Float, p: Paint) = drawLine(x1, y, x2, y, p)

    private fun Canvas.box(x: Float, y: Float) =
        drawRoundRect(RectF(x, y, x + 10f, y + 10f), 2f, 2f, line(0.8f, grey(0x77)))

    // MARK: - Writing surfaces

    /** One handwriting band in four lines — ascender, x-height (dashed),
     *  baseline (darker), descender: the English notebook every Korean
     *  learner wrote their first alphabet in. */
    private val bandHeight = 26f
    private fun Canvas.band(x1: Float, x2: Float, y: Float) {
        hline(x1, x2, y, line(0.6f, grey(0xC4)))
        hline(x1, x2, y + 8f, line(0.6f, grey(0xB4), dash = 2f))
        hline(x1, x2, y + 18f, line(0.9f, grey(0x8F)))
        hline(x1, x2, y + 26f, line(0.6f, grey(0xC4)))
    }

    private val ruleHeight = 25f
    private fun Canvas.rule(x1: Float, x2: Float, y: Float) =
        hline(x1, x2, y + ruleHeight, line(0.6f, grey(0xBD)))

    /** A row of squares with a faint centre cross; the word is traced in the
     *  first boxes in light grey, the rest are empty. */
    private val cell = 23f
    private fun Canvas.cells(x: Float, y: Float, trace: String) {
        val chars = BookWorkbook.traceCells(trace)
        val border = line(0.7f, grey(0xA8))
        val cross = line(0.4f, grey(0xDC), dash = 1.5f)
        val glyph = text(15f, grey(0xC4))
        for (i in 0 until BookWorkbook.CELLS_PER_ROW) {
            val cx = x + i * cell
            drawRect(cx, y, cx + cell, y + cell, border)
            if (i < chars.size) {
                val w = glyph.measureText(chars[i])
                val fm = glyph.fontMetrics
                drawText(chars[i], cx + (cell - w) / 2, y + cell / 2 - (fm.ascent + fm.descent) / 2, glyph)
            } else {
                drawLine(cx + cell / 2, y + 1, cx + cell / 2, y + cell - 1, cross)
                drawLine(cx + 1, y + cell / 2, cx + cell - 1, y + cell / 2, cross)
            }
        }
    }

    // MARK: - Shared pieces

    private fun h2(f: Flow, title: String) {
        val l = layout(title, text(17f, bold = true), W)
        f.block(l.height + 6f) { c, y -> c.put(l, L, y) }
    }

    private fun h3(f: Flow, title: String) {
        val l = layout(title.uppercase(), text(10f, grey(0x77), bold = true, spacing = 0.08f), W)
        f.gap(18f)
        f.block(l.height + 6f) { c, y -> c.put(l, L, y) }
    }

    /** A part's title and its numbered steps, ruled off from the page. */
    private fun header(f: Flow, title: String, steps: List<String>) {
        h2(f, title)
        if (steps.isEmpty()) return
        val p = text(9f, grey(0x55))
        val num = text(7.5f, grey(0x55), bold = true)
        val lineH = 17f
        data class Placed(val n: Int, val label: String, val x: Float, val row: Int)
        val placed = ArrayList<Placed>()
        var x = L; var row = 0
        steps.forEachIndexed { i, step ->
            val w = 15f + p.measureText(step)
            if (x > L && x + w > RIGHT) { x = L; row++ }
            placed.add(Placed(i + 1, step, x, row))
            x += w + 9f
        }
        val height = (row + 1) * lineH + 10f
        f.block(height + 14f) { c, top ->
            val circle = line(0.7f, grey(0x55))
            for (s in placed) {
                val cy = top + s.row * lineH + lineH / 2
                c.drawCircle(s.x + 6f, cy, 6f, circle)
                val n = s.n.toString()
                c.drawText(n, s.x + 6f - num.measureText(n) / 2,
                    cy - (num.fontMetrics.ascent + num.fontMetrics.descent) / 2, num)
                c.drawText(s.label, s.x + 15f, cy - (p.fontMetrics.ascent + p.fontMetrics.descent) / 2, p)
            }
            c.hline(L, RIGHT, top + height, line(1.2f, INK))
        }
    }

    // MARK: - Parts

    private fun wordsPart(f: Flow) {
        header(f, s(R.string.workbook_cover_and_write), listOf(
            s(R.string.workbook_say_the_word),
            s(R.string.workbook_fold_column),
            s(R.string.workbook_read_meaning_write),
            s(R.string.workbook_unfold_check),
            s(R.string.workbook_use_in_sentence),
        ))
        val leftW = 120f
        val rx = L + leftW + 12f
        val rw = RIGHT - rx
        for (w in wb.words) {
            val word = layout(w.text, text(12.5f, bold = true), leftW - 10f - 16f)
            val tag = if (w.mastered) layout(s(R.string.workbook_mastered_in_app),
                text(7.5f, grey(0x99)), leftW - 10f) else null
            val leftH = 2f + word.height + (tag?.let { 2f + it.height } ?: 0f)

            val meaning = if (w.meaning.isEmpty()) layout(s(R.string.meaning), text(9.5f, grey(0xAA)), rw * 0.6f)
                else layout(w.meaning, text(9.5f, grey(0x55)), rw)
            val surface = if (wb.usesCells) cell else bandHeight
            val cap = layout(s(R.string.workbook_your_sentence), text(7.5f, grey(0x99), spacing = 0.04f), rw)
            val second = if (wb.usesCells) ruleHeight else bandHeight
            val rightH = 2f + meaning.height + 5f + surface + 5f + cap.height + 1f + second
            val contentH = maxOf(leftH, rightH)

            f.block(contentH + 8f + 10f) { c, top ->
                c.box(L, top + 4f)
                c.put(word, L + 16f, top + 2f)
                tag?.let { c.put(it, L, top + 2f + word.height + 2f) }
                c.drawLine(L + leftW, top, L + leftW, top + contentH, line(0.9f, grey(0x99), dash = 2.5f))

                var y = top + 2f
                c.put(meaning, rx, y)
                if (w.meaning.isEmpty()) c.hline(rx, rx + rw * 0.6f, y + meaning.height + 1f, line(0.6f, grey(0xCC)))
                y += meaning.height + 5f
                if (wb.usesCells) c.cells(rx, y, w.text) else c.band(rx, RIGHT, y)
                y += surface + 5f
                c.put(cap, rx, y)
                y += cap.height + 1f
                if (wb.usesCells) c.rule(rx, RIGHT, y) else c.band(rx, RIGHT, y)
                c.hline(L, RIGHT, top + contentH + 8f, line(0.5f, grey(0xE2)))
            }
        }
    }

    private fun expressionsPart(f: Flow) {
        header(f, s(R.string.workbook_copy_it_out), listOf(
            s(R.string.workbook_read_aloud),
            s(R.string.workbook_copy_sentence),
            s(R.string.workbook_say_about_life),
        ))
        val x = L + 16f
        val w = RIGHT - x
        val labels = listOf(s(R.string.workbook_copy), s(R.string.workbook_mine), "")
        val labelPaint = text(7.5f, grey(0x99))
        for (e in wb.expressions) {
            val head = SpannableStringBuilder(e.text).apply {
                setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                if (e.meaning.isNotEmpty()) {
                    val from = length
                    append("  ").append(e.meaning)
                    setSpan(AbsoluteSizeSpan(10), from, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    setSpan(ForegroundColorSpan(grey(0x55)), from, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
            }
            val headL = layout(head, text(12.5f), w)
            val ex = e.example.takeIf { it.isNotEmpty() }?.let { layout(it, text(11f, grey(0x33), italic = true), w) }
            val h = headL.height + (ex?.let { 3f + it.height } ?: 0f) + labels.size * ruleHeight
            f.block(h + 14f) { c, top ->
                c.box(L, top + 4f)
                c.put(headL, x, top)
                var y = top + headL.height
                ex?.let { c.put(it, x, y + 3f); y += 3f + it.height }
                for (label in labels) {
                    if (label.isNotEmpty()) c.drawText(label, x, y + ruleHeight - 3f, labelPaint)
                    c.rule(x + 34f, RIGHT, y)
                    y += ruleHeight
                }
            }
        }
    }

    /** "Q1 … Looked again ___ ___ ___" / "D1 12 words … ○○○○○" */
    private fun Canvas.cardHead(x: Float, right: Float, y: Float, label: String, aside: String?,
                                dates: String?, dots: Int) {
        val q = text(11f, bold = true)
        val base = y + 12f
        drawText(label, x, base, q)
        aside?.let { drawText(it, x + q.measureText(label) + 5f, base, text(8.5f, grey(0x88))) }
        var rx = right
        if (dots > 0) {
            val p = line(0.7f, grey(0x99))
            repeat(dots) { i -> drawCircle(rx - 5f - i * 14f, base - 4f, 5f, p) }
        }
        if (dates != null) {
            val p = line(0.6f, grey(0xBB))
            repeat(3) { drawLine(rx - 34f, base + 1f, rx, base + 1f, p); rx -= 40f }
            val t = text(7.5f, grey(0x99))
            drawText(dates, rx - t.measureText(dates), base, t)
        }
    }

    private fun drillPart(f: Flow) {
        header(f, s(R.string.workbook_mistake_notebook), listOf(
            s(R.string.workbook_read_what_you_said),
            s(R.string.workbook_write_it_now),
            s(R.string.workbook_check_answers_back),
            s(R.string.workbook_come_back_date),
        ))
        val ix = L + 10f
        val iw = W - 20f
        val lbl = text(7.5f, grey(0x99), spacing = 0.04f)
        val youSaid = layout(s(R.string.workbook_you_said), lbl, iw)
        val redo = layout(s(R.string.workbook_redo), lbl, iw)
        for (q in wb.questions) {
            val said = layout(q.said, text(11.5f), iw)
            val inner = 16f + 6f + youSaid.height + 1f + said.height + 6f + redo.height + 2 * ruleHeight
            val h = 8f + inner + 6f
            f.block(h + 10f) { c, top ->
                c.drawRoundRect(RectF(L, top, RIGHT, top + h), 5f, 5f, line(0.7f, grey(0xBB)))
                var y = top + 8f
                c.cardHead(ix, RIGHT - 10f, y, "Q${q.number}", null, s(R.string.workbook_looked_again), 0)
                y += 16f + 6f
                c.put(youSaid, ix, y); y += youSaid.height + 1f
                c.put(said, ix, y); y += said.height + 6f
                c.put(redo, ix, y); y += redo.height
                c.rule(ix, RIGHT - 10f, y); y += ruleHeight
                c.rule(ix, RIGHT - 10f, y)
            }
        }
    }

    private fun dictationPart(f: Flow) {
        header(f, s(R.string.workbook_dictation), listOf(
            s(R.string.workbook_play_in_shadow),
            s(R.string.workbook_write_what_you_hear),
            s(R.string.workbook_check_at_back),
            s(R.string.workbook_read_five_times),
        ))
        for (d in wb.dictation) {
            val words = WordSplitter.count(d.text, doc.language.ifEmpty { "en" })
            val rules = BookWorkbook.dictationRules(d.text)
            val aside = context.getString(R.string.lld_words, words)
            f.block(16f + rules * ruleHeight + 12f) { c, top ->
                c.cardHead(L, RIGHT, top, "D${d.number}", aside, null, 5)
                var y = top + 16f
                repeat(rules) { c.rule(L, RIGHT, y); y += ruleHeight }
            }
        }
    }

    private fun recallPart(f: Flow) {
        header(f, s(R.string.workbook_blank_page), listOf(
            s(R.string.workbook_close_book),
            s(R.string.workbook_write_everything),
            s(R.string.workbook_check_fill_gaps),
        ))
        repeat(24) { f.block(ruleHeight) { c, y -> c.rule(L, RIGHT, y) } }
    }

    private fun answerRows(f: Flow, answers: List<BookWorkbook.Answer>) {
        val label = text(9f, grey(0x77))
        val tx = L + 30f
        for (a in answers) {
            val t = layout(a.text, text(11f), RIGHT - tx)
            val why = a.why.takeIf { it.isNotEmpty() }?.let { layout(it, text(9f, grey(0x66)), RIGHT - tx) }
            val h = 5f + t.height + (why?.height ?: 0) + 5f
            f.block(h) { c, top ->
                c.drawText(a.label, L, top + 5f - label.fontMetrics.ascent + 1.5f, label)
                c.put(t, tx, top + 5f)
                why?.let { c.put(it, tx, top + 5f + t.height) }
                c.hline(L, RIGHT, top + h, line(0.5f, grey(0xE6)))
            }
        }
    }

    private fun answersPart(f: Flow) {
        h2(f, s(R.string.workbook_answers))
        if (wb.drillAnswers.isNotEmpty()) {
            h3(f, s(R.string.workbook_mistake_notebook))
            answerRows(f, wb.drillAnswers)
        }
        if (wb.dictationAnswers.isNotEmpty()) {
            h3(f, s(R.string.workbook_dictation))
            answerRows(f, wb.dictationAnswers)
        }
    }

    private fun dialoguePart(f: Flow, title: String) {
        val section = wb.dialogue ?: return
        h2(f, title)
        val memoW = 130f
        val memoX = RIGHT - memoW
        val whoW = 64f
        val notes = layout(s(R.string.workbook_notes), text(7.5f, grey(0xAA), spacing = 0.05f), memoW - 8f)
        f.block(notes.height + 6f) { c, y -> c.put(notes, memoX + 8f, y) }
        val whoP = text(7.5f, grey(0x88), spacing = 0.05f)
        for (line in section.lines) {
            val sx = L + whoW + if (line.isUser) 14f else 0f
            val sw = memoX - 8f - sx
            val who = layout(line.speaker.uppercase(), whoP, whoW - 4f)
            val say = layout(line.text, text(11f), sw)
            val fix = line.correction?.takeIf { it.isNotEmpty() }?.let { layout("→ $it", text(11f), sw - 7f) }
            val why = line.correctionNote.takeIf { it.isNotEmpty() && fix != null }
                ?.let { layout(it, text(9f, grey(0x66)), sw - 9f) }
            val sayH = say.height + (fix?.let { 3f + it.height } ?: 0f) + (why?.height ?: 0)
            val h = 5f + maxOf(sayH, 2f + who.height) + 5f
            f.block(h) { c, top ->
                c.put(who, L, top + 7f)
                var y = top + 5f
                c.put(say, sx, y); y += say.height
                fix?.let {
                    y += 3f
                    c.drawLine(sx + 0.8f, y, sx + 0.8f, y + it.height, line(1.6f, grey(0x99)))
                    c.put(it, sx + 7f, y); y += it.height
                }
                why?.let { c.put(it, sx + 9f, y) }
                c.drawLine(memoX, top, memoX, top + h, line(0.8f, grey(0xBB), dash = 2.5f))
                c.hline(L, RIGHT, top + h, line(0.5f, grey(0xEE)))
            }
        }
    }

    private fun cover(parts: List<Part>, firstPages: List<Int>): Flow {
        val f = Flow()
        f.gap(40f)
        val kind = layout("${doc.kind} · ${s(R.string.workbook)}".uppercase(),
            text(9f, grey(0x77), spacing = 0.12f), W)
        f.block(kind.height.toFloat()) { c, y -> c.put(kind, L, y) }
        val title = StaticLayout.Builder.obtain(doc.title, 0, doc.title.length, text(28f, bold = true), W.toInt())
            .setLineSpacing(0f, 1.05f).setIncludePad(false).build()
        f.block(6f + title.height + 8f) { c, y -> c.put(title, L, y + 6f) }
        val head = (if (doc.subtitle.isEmpty()) emptyList() else listOf(doc.subtitle)) + doc.meta
        val meta = layout(head.joinToString(" · "), text(10f, grey(0x66)), W)
        f.block((if (head.isEmpty()) 0f else meta.height.toFloat()) + 14f) { c, y ->
            if (head.isNotEmpty()) c.put(meta, L, y)
            c.hline(L, RIGHT, y + (if (head.isEmpty()) 0f else meta.height.toFloat()) + 14f, line(1.5f, INK))
        }
        if (wb.overview.isNotEmpty()) {
            val o = layout(wb.overview, text(10.5f, grey(0x33)), W)
            f.block(14f + o.height) { c, y -> c.put(o, L, y + 14f) }
        }

        h3(f, s(R.string.workbook_in_this_book))
        val numP = text(11f, grey(0x77))
        for ((p, page) in parts.zip(firstPages)) {
            val t = layout(p.title, text(11.5f, bold = true), W - 50f)
            val b = layout(p.blurb, text(9.5f, grey(0x55)), W - 50f)
            val h = 7f + t.height + b.height + 7f
            f.block(h) { c, top ->
                c.box(L, top + h / 2 - 5f)
                c.put(t, L + 20f, top + 7f)
                c.put(b, L + 20f, top + 7f + t.height)
                val n = (page + 1).toString()
                c.drawText(n, RIGHT - numP.measureText(n), top + h / 2 - (numP.fontMetrics.ascent + numP.fontMetrics.descent) / 2, numP)
                c.hline(L, RIGHT, top + h, line(0.5f, grey(0xE2)))
            }
        }

        h3(f, s(R.string.workbook_review_days))
        val hint = layout(s(R.string.workbook_review_days_hint), text(9.5f, grey(0x55)), W)
        f.block(hint.height + 6f) { c, y -> c.put(hint, L, y) }
        val labels = listOf(R.string.workbook_day_1, R.string.workbook_day_3,
            R.string.workbook_day_7, R.string.workbook_day_14).map { s(it) }
        f.block(74f) { c, top ->
            val cw = W / 4
            val border = line(0.7f, grey(0xBB))
            c.drawRect(L, top, RIGHT, top + 74f, border)
            val lp = text(8.5f, grey(0x55), bold = true)
            val slash = text(10f, grey(0xBB))
            labels.forEachIndexed { i, label ->
                val x = L + i * cw
                if (i > 0) c.drawLine(x, top, x, top + 74f, border)
                c.put(layout(label, lp, cw - 14f), x + 7f, top + 7f)
                c.drawText("/", x + cw - 7f - 22f, top + 74f - 12f, slash)
            }
        }
        return f
    }

    // MARK: - PDF

    private fun flow(part: Part): Flow {
        val f = Flow()
        when (part.id) {
            BookWorkbook.PartId.WORDS -> wordsPart(f)
            BookWorkbook.PartId.EXPRESSIONS -> expressionsPart(f)
            BookWorkbook.PartId.DRILL -> drillPart(f)
            BookWorkbook.PartId.DICTATION -> dictationPart(f)
            BookWorkbook.PartId.RECALL -> recallPart(f)
            BookWorkbook.PartId.ANSWERS -> answersPart(f)
            BookWorkbook.PartId.DIALOGUE -> dialoguePart(f, part.title)
        }
        return f
    }

    fun pdfData(): ByteArray {
        val parts = wb.parts().map { describe(it) }
        val flows = parts.map { flow(it) }
        val counts = flows.map { it.pages.size }

        // The cover lists page numbers, which depend on how long the cover is.
        fun starts(after: Int): List<Int> {
            var p = after
            return counts.map { c -> p.also { p += c } }
        }
        var cover = cover(parts, starts(1))
        if (cover.pages.size != 1) cover = cover(parts, starts(cover.pages.size))
        val coverCount = cover.pages.size
        val firstPages = listOf(0) + starts(coverCount)
        val total = coverCount + counts.sum()

        val tabs = listOf(s(R.string.workbook_contents)) + parts.map { it.tab }
        val tabRects = tabRects(tabs.size)
        val links = ArrayList<PdfLinks.Link>()

        val pdf = PdfDocument()
        var pageNo = 0
        fun draw(f: Flow, tab: Int) {
            for (ops in f.pages) {
                val page = pdf.startPage(PdfDocument.PageInfo.Builder(PAPER_W, PAPER_H, pageNo + 1).create())
                val c = page.canvas
                ops.forEach { it(c) }
                drawTabs(c, tabs, tabRects, tab)
                tabRects.forEachIndexed { i, r ->
                    if (i != tab) links.add(PdfLinks.Link(pageNo, r.left, r.top, r.right, r.bottom, firstPages[i]))
                }
                if (pageNo > 0) drawFooter(c, pageNo + 1, total)
                pdf.finishPage(page)
                pageNo++
            }
        }
        draw(cover, 0)
        flows.forEachIndexed { i, f -> draw(f, i + 1) }

        val out = ByteArrayOutputStream()
        pdf.writeTo(out)
        pdf.close()
        return PdfLinks.add(out.toByteArray(), PAPER_H.toFloat(), links)
    }

    private fun tabRects(n: Int): List<RectF> {
        val top = 70f
        val bottom = PAPER_H - 90f
        val gap = 4f
        val h = minOf(92f, (bottom - top - gap * (n - 1)) / n)
        val w = 22f
        val x = PAPER_W - w - 14f
        return (0 until n).map { i ->
            val y = top + i * (h + gap)
            RectF(x, y, x + w, y + h)
        }
    }

    /** Index tabs down the right edge — on paper a way to find your place, in
     *  a notes app a tap ([PdfLinks]). */
    private fun drawTabs(c: Canvas, labels: List<String>, rects: List<RectF>, current: Int) {
        labels.forEachIndexed { i, label ->
            val r = rects[i]
            val on = i == current
            if (on) {
                c.drawRoundRect(r, 4f, 4f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = grey(0x1A) })
            } else {
                c.drawRoundRect(r, 4f, 4f, line(0.6f, grey(0xB8)))
            }
            val p = text(7.5f, if (on) 0xFFFFFFFF.toInt() else grey(0x59), bold = on, spacing = 0.05f)
            val shown = TextUtils.ellipsize(label, p, r.height() - 8f, TextUtils.TruncateAt.END).toString()
            val w = p.measureText(shown)
            c.save()
            c.rotate(90f, r.centerX(), r.centerY())
            c.drawText(shown, r.centerX() - w / 2,
                r.centerY() - (p.fontMetrics.ascent + p.fontMetrics.descent) / 2, p)
            c.restore()
        }
    }

    private fun drawFooter(c: Canvas, page: Int, total: Int) {
        val p = text(7.5f, grey(0x8C))
        val y = PAPER_H - 36f - (p.fontMetrics.ascent + p.fontMetrics.descent) / 2
        val left = TextUtils.ellipsize("${doc.title}   ·   $page / $total", p, W - 80f,
            TextUtils.TruncateAt.MIDDLE).toString()
        c.drawText(left, L, y, p)
        val brand = text(7.5f, grey(0xA6))
        c.drawText("nawana.app", RIGHT - brand.measureText("nawana.app"), y, brand)
    }
}
