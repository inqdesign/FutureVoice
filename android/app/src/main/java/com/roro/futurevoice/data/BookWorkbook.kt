package com.roro.futurevoice.data

/**
 * A book as a WORKBOOK — the same [BookDocument], laid out for a pen. Port of
 * `BookWorkbook.swift` (iOS `ab56652`).
 *
 * The reader PDF ([BookDocument.html]) is a document: everything is printed,
 * nothing is left to do. People who study by hand work differently, and the
 * pages here are built around what they already do rather than a new method:
 *
 * - **Cover, write** (words): the word sits left of a fold line, its meaning
 *   right of it. Fold the word under (or lay a notes app's tape over it), read
 *   the meaning, write the word, unfold to check.
 * - **Copying** (expressions): the fluent self's sentence, then lines to copy
 *   it and to say it about your own life — 필사, a whole genre of its own.
 * - **Mistake notebook** (corrections): what you said and a blank to redo it.
 *   The fix is in the answer pages at the back, never beside the question.
 * - **Dictation** (shadow lines): the line is played in the app, the page has
 *   only its number, its length and the lines to write on.
 * - **Blank-page recall**: one empty page — write everything you remember.
 *
 * Copying a word ten times (깜지) is deliberately absent: copying with the
 * answer in view trains the hand, recalling it trains the memory, so the
 * space goes to recall.
 *
 * This file is the PLAN — which parts exist and what each one carries — and
 * is pure Kotlin so the rules above are JVM-tested. [WorkbookPdf] draws it.
 */
class BookWorkbook(val doc: BookDocument) {

    enum class PartId(val key: String) {
        WORDS("words"), EXPRESSIONS("expressions"), DRILL("drill"),
        DICTATION("dictation"), RECALL("recall"), ANSWERS("answers"), DIALOGUE("dialogue"),
    }

    data class WordRow(val text: String, val meaning: String, val mastered: Boolean)
    data class ExpressionRow(val text: String, val meaning: String, val example: String)
    /** A correction as a QUESTION: only what the learner said. */
    data class Question(val number: Int, val said: String)
    /** A dictation slot: the line itself is never printed here — only its
     *  number and length. [text] is kept for counting, not for drawing. */
    data class DictationSlot(val number: Int, val text: String)
    data class Answer(val label: String, val text: String, val why: String)

    private fun section(kind: BookDocument.Section.Kind): BookDocument.Section? =
        doc.sections.firstOrNull { it.kind == kind && !it.isEmpty }

    /** Dictionary meanings by term, from the glossary the export appended.
     *  Short on purpose: a writing row has room for a gloss, not an entry. */
    private val meanings: Map<String, String> by lazy {
        section(BookDocument.Section.Kind.GLOSSARY)?.entries?.associate { e ->
            key(e.text) to e.note.split(" · ").take(2).joinToString(" · ")
        }.orEmpty()
    }

    private val examples: Map<String, String> by lazy {
        val out = LinkedHashMap<String, String>()
        section(BookDocument.Section.Kind.GLOSSARY)?.entries?.forEach { e ->
            out.putIfAbsent(key(e.text), e.example)
        }
        out
    }

    /** Squares for scripts written one character to a box. */
    val usesCells: Boolean
        get() = doc.language.split("-", "_").first().lowercase() in setOf("ja", "ko", "zh")

    val words: List<WordRow>
        get() = section(BookDocument.Section.Kind.WORDS)?.entries?.map {
            WordRow(it.text, meanings[key(it.text)].orEmpty(), it.mastered == true)
        }.orEmpty()

    val expressions: List<ExpressionRow>
        get() = section(BookDocument.Section.Kind.EXPRESSIONS)?.entries?.map {
            ExpressionRow(
                it.text,
                meanings[key(it.text)].orEmpty(),
                it.example.ifEmpty { examples[key(it.text)].orEmpty() },
            )
        }.orEmpty()

    private val drillEntries: List<BookDocument.Entry>
        get() = section(BookDocument.Section.Kind.DRILL)?.entries
            ?.filter { !it.original.isNullOrEmpty() }.orEmpty()

    val questions: List<Question>
        get() = drillEntries.mapIndexed { i, e -> Question(i + 1, e.original.orEmpty()) }

    val dictation: List<DictationSlot>
        get() = section(BookDocument.Section.Kind.SHADOW)?.entries
            ?.mapIndexed { i, e -> DictationSlot(i + 1, e.text) }.orEmpty()

    /** The fixes, at the back — never beside their question. */
    val drillAnswers: List<Answer>
        get() = drillEntries.mapIndexed { i, e -> Answer("Q${i + 1}", e.text, e.note) }

    val dictationAnswers: List<Answer>
        get() = dictation.map { Answer("D${it.number}", it.text, "") }

    /** The talk's transcript, else the Watch book's scene. */
    val dialogue: BookDocument.Section?
        get() = section(BookDocument.Section.Kind.TRANSCRIPT) ?: section(BookDocument.Section.Kind.SCENE)

    val overview: String
        get() = section(BookDocument.Section.Kind.OVERVIEW)?.blurb.orEmpty()

    /** The parts in page order. Every part starts on its own page. */
    fun parts(): List<PartId> {
        val out = ArrayList<PartId>()
        if (section(BookDocument.Section.Kind.WORDS) != null) out.add(PartId.WORDS)
        if (section(BookDocument.Section.Kind.EXPRESSIONS) != null) out.add(PartId.EXPRESSIONS)
        if (questions.isNotEmpty()) out.add(PartId.DRILL)
        if (dictation.isNotEmpty()) out.add(PartId.DICTATION)
        if (out.isNotEmpty()) out.add(PartId.RECALL)
        if (questions.isNotEmpty() || dictation.isNotEmpty()) out.add(PartId.ANSWERS)
        if (dialogue != null) out.add(PartId.DIALOGUE)
        return out
    }

    companion object {
        const val CELLS_PER_ROW = 14

        fun key(s: String): String = s.trim().lowercase()

        /** Writing lines a dictation line gets: one per ~52 characters, plus one. */
        fun dictationRules(text: String): Int = maxOf(1, Math.ceil(text.length / 52.0).toInt()) + 1

        /** The first boxes of a cell row carry the word traced in light grey. */
        fun traceCells(text: String): List<String> =
            text.filterNot { it.isWhitespace() }.codePoints().toArray()
                .map { String(Character.toChars(it)) }
    }
}
