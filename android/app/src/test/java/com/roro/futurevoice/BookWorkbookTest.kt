package com.roro.futurevoice

import com.roro.futurevoice.data.BookDocument
import com.roro.futurevoice.data.BookDocument.Entry
import com.roro.futurevoice.data.BookDocument.Line
import com.roro.futurevoice.data.BookDocument.Section
import com.roro.futurevoice.data.BookDocument.Section.Kind
import com.roro.futurevoice.data.BookWorkbook
import com.roro.futurevoice.data.BookWorkbook.PartId
import com.roro.futurevoice.data.PdfLinks
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of iOS `BookWorkbookTests` (`ab56652`). The workbook lays a book out
 * for a pen; what is worth guarding: every study item gets its writing
 * space, every correction's answer lands in the answer pages (never beside
 * its question), dictation never prints the line it asks for, and Japanese
 * writes in cells. The drawing itself ([com.roro.futurevoice.data.WorkbookPdf])
 * needs a device; the link post-processor is pure and tested here.
 */
class BookWorkbookTest {

    private fun englishTalkBook() = BookDocument(
        kind = "Talk book", title = "Chores, kids and the weekend", language = "en",
        meta = listOf("30 September 2026", "Mastered 3/18", "Score 72"),
        sections = listOf(
            Section("Overview", kind = Kind.OVERVIEW,
                blurb = "이야기를 길게 이어 가는 힘이 좋아졌어요."),
            Section("Words", kind = Kind.WORDS, entries = listOf(
                Entry("chore"), Entry("laundry", mastered = true), Entry("split"),
                Entry("exhausted"), Entry("take turns"), Entry("errand"),
                Entry("tidy up"), Entry("routine"))),
            Section("Expressions", kind = Kind.EXPRESSIONS, entries = listOf(
                Entry("it's my turn to", note = "Your fluent self used this — you didn't.",
                    example = "Tonight it's my turn to cook, so I'm keeping it simple."),
                Entry("end up -ing", example = "We always end up doing the dishes at midnight."),
                Entry("to be fair"),
                Entry("push back on", example = "I pushed back on doing every school run."))),
            Section("Shadow", kind = Kind.SHADOW, entries = listOf(
                Entry("Honestly, the laundry never really ends — you just catch up for a day."),
                Entry("We split it by days, so nobody has to keep score."),
                Entry("On Saturdays we tidy up together and then go get pancakes."))),
            Section("Drill", kind = Kind.DRILL, entries = listOf(
                Entry("Yesterday I did the laundry and cooked dinner.", note = "어제 일이니까 과거형으로",
                    original = "Yesterday I do the laundry and cook dinner."),
                Entry("We take turns doing the dishes.", note = "take turns 다음엔 -ing",
                    original = "We take turns to do dishes."),
                Entry("I'm exhausted after work.", note = "사람의 상태는 -ed",
                    original = "I'm exhausting after work."),
                // No original: nothing to redo, so no question.
                Entry("A line with nothing to compare against."))),
            Section("Transcript", kind = Kind.TRANSCRIPT, lines = listOf(
                Line("Future self", "So what does a normal weekday evening look like at your place?", false),
                Line("You", "Yesterday I do the laundry and cook dinner.", true,
                    correction = "Yesterday I did the laundry and cooked dinner."))),
            Section("Glossary", kind = Kind.GLOSSARY, entries = listOf(
                Entry("chore", note = "n. 집안일, 허드렛일"),
                Entry("split", note = "v. 나누다 · n. 분담 · v. 쪼개다"),
                Entry("to be fair", note = "공정하게 말하자면", example = "To be fair, she does most of the laundry."))),
        ),
    )

    private fun japaneseWatchBook() = BookDocument(
        kind = "Watch book", title = "カフェで注文が違ったとき", language = "ja",
        sections = listOf(
            Section("Scene", kind = Kind.SCENE, lines = listOf(
                Line("店員", "お待たせしました。カフェラテです。", false),
                Line("You", "すみません、アイスで頼んだんですけど…", true))),
            Section("Words", kind = Kind.WORDS, entries = listOf(Entry("注文"), Entry("作り直す"))),
            Section("Expressions", kind = Kind.EXPRESSIONS, entries = listOf(
                Entry("〜んですけど", example = "アイスで頼んだんですけど…"))),
        ),
    )

    @Test fun everyItemGetsItsPartAndAnswersStayAtTheBack() {
        val wb = BookWorkbook(englishTalkBook())
        assertEquals(
            listOf(PartId.WORDS, PartId.EXPRESSIONS, PartId.DRILL, PartId.DICTATION,
                PartId.RECALL, PartId.ANSWERS, PartId.DIALOGUE),
            wb.parts())

        // The question carries only what was said; the fix is in the answers.
        assertEquals(3, wb.questions.size)
        assertEquals("Yesterday I do the laundry and cook dinner.", wb.questions[0].said)
        assertFalse(wb.questions.any { it.said.contains("Yesterday I did the laundry") })
        assertEquals("Yesterday I did the laundry and cooked dinner.", wb.drillAnswers[0].text)
        assertEquals("Q1", wb.drillAnswers[0].label)
        assertEquals("어제 일이니까 과거형으로", wb.drillAnswers[0].why)

        // Dictation's line is an ANSWER, not part of the question page.
        assertEquals(3, wb.dictation.size)
        assertTrue(wb.dictationAnswers.any { it.text.contains("catch up for a day") })
        assertEquals("D1", wb.dictationAnswers[0].label)

        // The glossary meaning reaches the word row — the first two senses only.
        assertEquals("n. 집안일, 허드렛일", wb.words.first { it.text == "chore" }.meaning)
        assertEquals("v. 나누다 · n. 분담", wb.words.first { it.text == "split" }.meaning)
        assertEquals("", wb.words.first { it.text == "errand" }.meaning)
        assertTrue(wb.words.first { it.text == "laundry" }.mastered)
        // An expression with no example of its own borrows the glossary's.
        assertEquals("To be fair, she does most of the laundry.",
            wb.expressions.first { it.text == "to be fair" }.example)
        assertFalse(wb.usesCells)
    }

    @Test fun japaneseWritesInCellsAndTheSceneIsTheDialogue() {
        val wb = BookWorkbook(japaneseWatchBook())
        assertTrue(wb.usesCells)
        assertTrue(BookWorkbook(japaneseWatchBook().copy(language = "zh-Hant")).usesCells)
        assertTrue(BookWorkbook(japaneseWatchBook().copy(language = "ko")).usesCells)
        assertEquals(listOf("作", "り", "直", "す"), BookWorkbook.traceCells("作り直す"))
        // No corrections and no shadow lines: no question pages, no answers.
        assertEquals(listOf(PartId.WORDS, PartId.EXPRESSIONS, PartId.RECALL, PartId.DIALOGUE),
            BookWorkbook(japaneseWatchBook()).parts())
        assertEquals(Kind.SCENE, wb.dialogue?.kind)
    }

    @Test fun anEmptyBookHasNoParts() {
        assertTrue(BookWorkbook(BookDocument(kind = "Talk book", title = "x")).parts().isEmpty())
    }

    @Test fun dictationRulesGrowWithTheLine() {
        assertEquals(2, BookWorkbook.dictationRules("short"))
        assertEquals(3, BookWorkbook.dictationRules("x".repeat(53)))
    }

    // MARK: - Links

    /** A PDF shaped the way Skia writes one: classic xref, a page tree. */
    private fun skiaLikePdf(): ByteArray {
        val objects = listOf(
            "<</Type /Catalog\n/Pages 2 0 R>>",
            "<</Type /Pages\n/Kids [3 0 R 4 0 R]\n/Count 2>>",
            "<</Type /Page\n/Parent 2 0 R\n/MediaBox [0 0 595 842]\n/Resources <</ProcSet [/PDF /Text]>>\n/Contents 5 0 R>>",
            "<</Type /Page\n/Parent 2 0 R\n/MediaBox [0 0 595 842]\n/Resources <</ProcSet [/PDF /Text]>>\n/Contents 5 0 R>>",
            "<</Length 0>> stream\n\nendstream",
        )
        val sb = StringBuilder("%PDF-1.4\n%âãÏÓ\n")
        val offsets = ArrayList<Int>()
        objects.forEachIndexed { i, o ->
            offsets.add(sb.length)
            sb.append("${i + 1} 0 obj\n$o\nendobj\n")
        }
        val xref = sb.length
        sb.append("xref\n0 ${objects.size + 1}\n0000000000 65535 f \n")
        offsets.forEach { sb.append(String.format("%010d 00000 n \n", it)) }
        sb.append("trailer\n<</Size ${objects.size + 1}\n/Root 1 0 R>>\nstartxref\n$xref\n%%EOF")
        return sb.toString().toByteArray(Charsets.ISO_8859_1)
    }

    @Test fun linksAreAppendedAsAnIncrementalUpdate() {
        val pdf = skiaLikePdf()
        val out = PdfLinks.add(pdf, 842f, listOf(
            PdfLinks.Link(page = 0, left = 559f, top = 70f, right = 581f, bottom = 162f, targetPage = 1)))
        val text = String(out, Charsets.ISO_8859_1)
        // The original bytes are untouched.
        assertTrue(out.size > pdf.size)
        assertEquals(String(pdf, Charsets.ISO_8859_1), text.substring(0, pdf.size))
        // The first page is re-emitted with an annotation pointing at page 2.
        assertTrue(text.contains("/Annots [6 0 R]"))
        assertTrue(text.contains("/Subtype /Link"))
        assertTrue(text.contains("/Rect [559.00 680.00 581.00 772.00]"))
        assertTrue(text.contains("/Dest [4 0 R /Fit]"))
        assertTrue(text.contains("/Prev ${String(pdf, Charsets.ISO_8859_1).substringAfter("startxref\n").substringBefore("\n")}"))
        assertTrue(text.trimEnd().endsWith("%%EOF"))

        // The new xref offsets point at the objects they name.
        val newXref = text.substringAfterLast("startxref\n").substringBefore("\n").toInt()
        val table = text.substring(newXref).lines()
        assertEquals("xref", table[0])
        var row = 1
        while (row < table.size && !table[row].startsWith("trailer")) {
            val (first, count) = table[row].split(" ").map { it.toInt() }
            for (k in 0 until count) {
                val off = table[row + 1 + k].substring(0, 10).toInt()
                assertTrue(text.startsWith("${first + k} 0 obj", off))
            }
            row += 1 + count
        }
    }

    @Test fun anythingUnexpectedLeavesThePdfAsItWas() {
        val garbage = "not a pdf".toByteArray()
        assertSame(garbage, PdfLinks.add(garbage, 842f,
            listOf(PdfLinks.Link(0, 0f, 0f, 1f, 1f, 0))))
        val pdf = skiaLikePdf()
        assertSame(pdf, PdfLinks.add(pdf, 842f, emptyList()))
        // A link to a page that doesn't exist is dropped, not written.
        assertSame(pdf, PdfLinks.add(pdf, 842f, listOf(PdfLinks.Link(0, 0f, 0f, 1f, 1f, 9))))
    }

    /** iOS 25e4d8e2: a talk-book expression's example is the sentence of
     *  that talk that carried it — the fluent self's first, then the
     *  learner's, whole words only. */
    @Test fun talkExpressionExampleIsTheSentenceItWasSaidIn() {
        val session = com.roro.futurevoice.talk.Session(
            userId = "u", targetLanguage = "en", startedAt = 0L,
            turns = listOf(
                com.roro.futurevoice.talk.Turn(role = com.roro.futurevoice.talk.TurnRole.USER,
                    transcript = "I want to end up somewhere warm."),
                com.roro.futurevoice.talk.Turn(role = com.roro.futurevoice.talk.TurnRole.FLUENT_SELF,
                    transcript = "Nice. You might end up loving it. Pushback is normal."),
            ))
        assertEquals("You might end up loving it.", BookDocument.sentence("end up", session))
        assertEquals("I want to end up somewhere warm.",
            BookDocument.sentence("end up somewhere", session))
        // Whole words: "push" is not "Pushback".
        assertEquals("", BookDocument.sentence("push", session))
        assertEquals("", BookDocument.sentence("", session))
    }
}
