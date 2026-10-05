package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * A Practice book, flattened into something you can study OFF the phone —
 * printed, marked up in a tablet notes app, or pasted into whatever the
 * learner already keeps notes in.
 *
 * Both book types collapse into the SAME shape here ([Section] of [Entry]s,
 * plus dialogue blocks), which is the point: a Watch book and a Talk book
 * have the same anatomy on screen — a scene plus material to master — so they
 * should read the same on paper. One document model, two renderers
 * ([markdown], and the workbook PDF — [WorkbookPdf]), and every builder feeds the same thing. Add a
 * field here and BOTH renderers pick it up; never render a book straight to a
 * format.
 *
 * Language follows the app's split unchanged: the material — scene lines,
 * words, expressions, corrected sentences — is in the target language, the
 * notes explaining it are in the learner's own, and the headings are chrome,
 * so a printed book uses the same words as the book on screen.
 */
data class BookDocument(
    /** "Watch book" / "Talk book" — the kicker above the title. */
    val kind: String,
    val title: String,
    val subtitle: String = "",
    /** Date, progress, score — one short line each. */
    val meta: List<String> = emptyList(),
    val sections: List<Section> = emptyList(),
    /**
     * Terms this book teaches, in the order they appear. Carried separately
     * from the sections because a glossary is built LATER and elsewhere:
     * looking a word up is async (a shared server dictionary), and document
     * building is synchronous by design so a page can render instantly.
     */
    val terms: List<Term> = emptyList(),
    /**
     * The target language's code — the workbook ([BookWorkbook]) rules Latin
     * script in four lines and Japanese/Korean/Chinese in square cells.
     */
    val language: String = "",
) {
    /** Multi-word items get the "explain the whole thing" treatment rather
     *  than a headword entry — asking for a phrase as a word is what produced
     *  a dictionary entry for "hundred". */
    data class Term(val text: String, val isExpression: Boolean)

    /** One line of a scene or transcript. */
    data class Line(
        val speaker: String,
        val text: String,
        /**
         * The learner's own side — indented differently so a printed dialogue
         * is still scannable without colour or bubbles.
         */
        val isUser: Boolean,
        /** The coached rewrite of what they said, when there is one. */
        val correction: String? = null,
        val correctionNote: String = "",
    )

    /**
     * One study item: the thing to learn, plus whatever the app knows about
     * it. [mastered] prints as a ticked box so a paper copy carries the same
     * progress the book shows.
     */
    data class Entry(
        val text: String,
        val note: String = "",
        val example: String = "",
        /** The learner's original, for a correction pair ("you said → say"). */
        val original: String? = null,
        val mastered: Boolean? = null,
    )

    data class Section(
        val title: String,
        val blurb: String = "",
        val entries: List<Entry> = emptyList(),
        val lines: List<Line> = emptyList(),
        /**
         * What the section IS, independent of its (localized) title — the
         * workbook gives each kind its own page shape (a word gets writing
         * bands, a correction gets a blank to redo it). The reader PDF and
         * Markdown ignore it.
         */
        val kind: Kind = Kind.OTHER,
    ) {
        enum class Kind { SCENE, OVERVIEW, WORDS, EXPRESSIONS, SHADOW, DRILL, TRANSCRIPT, GLOSSARY, OTHER }

        val isEmpty: Boolean get() = entries.isEmpty() && lines.isEmpty()
    }

    /** Filename stem, safe on every filesystem the share sheet can reach. */
    val filename: String
        get() {
            val base = (title.ifEmpty { kind })
                .map { if (it.isLetterOrDigit() || it.isWhitespace()) it else ' ' }
                .joinToString("").trim()
            return (base.ifEmpty { "book" }).take(60).replace(Regex("\\s+"), "-")
        }

    // MARK: - Markdown

    /**
     * Plain-text Markdown — the format that survives being pasted anywhere
     * (notes apps, Obsidian, a text editor) and still reads as a document if
     * nothing renders it.
     */
    val markdown: String
        get() {
            val out = ArrayList<String>()
            out.add("# $title")
            out.add((listOf(kind) + listOfNotNull(subtitle.takeIf { it.isNotEmpty() }) + meta)
                .joinToString(" · "))

            for (section in sections) {
                if (section.isEmpty && section.blurb.isEmpty()) continue
                out.add("\n## ${section.title}")
                if (section.blurb.isNotEmpty()) out.add(section.blurb)

                for (entry in section.entries) {
                    val box = when (entry.mastered) {
                        true -> "- [x] "
                        false -> "- [ ] "
                        null -> "- "
                    }
                    out.add(box + if (!entry.original.isNullOrEmpty())
                        "~~${entry.original}~~ → **${entry.text}**" else "**${entry.text}**")
                    // Example before note, the same order the PDF prints them:
                    // the material first, then the sentence explaining it.
                    if (entry.example.isNotEmpty()) out.add("  - _${entry.example}_")
                    if (entry.note.isNotEmpty()) out.add("  - ${entry.note}")
                }

                for (line in section.lines) {
                    out.add("\n**${line.speaker}** — ${line.text}")
                    if (!line.correction.isNullOrEmpty()) {
                        out.add("> → ${line.correction}")
                        if (line.correctionNote.isNotEmpty()) out.add("> ${line.correctionNote}")
                    }
                }
            }
            return out.joinToString("\n") + "\n"
        }

    // MARK: - Print HTML (what the PDF is laid out from)

    companion object {

        /**
         * A Watch book: the scene it was extracted from, then the words,
         * expressions and lines to master.
         */
        fun make(context: Context, scenario: Scenario, counterpartName: String?): BookDocument {
            val role = scenario.role.trim()
            val sections = ArrayList<Section>()
            val meta = ArrayList<String>()
            meta.add(dateLine(scenario.lastUsedAt ?: scenario.createdAt))

            val c = scenario.curriculum
            if (c != null) {
                val total = c.totalCount
                if (total > 0) {
                    val done = c.masteredCount
                    meta.add("${context.getString(R.string.mastered)} $done/$total")
                }
            }
            if (scenario.archivedAt != null) meta.add(context.getString(R.string.archived))

            if (c != null) {
                val dialogue = c.dialogue
                if (!dialogue.isNullOrEmpty()) {
                    val other = counterpartName
                        ?: role.ifEmpty { context.getString(R.string.the_other_person) }
                    sections.add(Section(
                        title = c.dialogueTitle ?: context.getString(R.string.scene),
                        kind = Section.Kind.SCENE,
                        lines = dialogue.map {
                            Line(
                                speaker = if (it.speaker == "user")
                                    context.getString(R.string.you) else other,
                                text = it.text,
                                isUser = it.speaker == "user",
                            )
                        },
                    ))
                }
                fun section(title: String, kind: Section.Kind,
                            items: List<ScenarioCurriculum.Item>): Section? =
                    if (items.isEmpty()) null else Section(title, kind = kind, entries = items.map {
                        Entry(it.text, it.note, it.example.orEmpty(),
                            mastered = it.masteredAt != null)
                    })
                sections += listOfNotNull(
                    section(context.getString(R.string.words_d26d55), Section.Kind.WORDS, c.words),
                    section(context.getString(R.string.expressions), Section.Kind.EXPRESSIONS, c.expressions),
                    section(context.getString(R.string.shadow), Section.Kind.SHADOW, c.shadowLines),
                )
            }

            return BookDocument(
                terms = c?.let { cur ->
                    cur.words.map { Term(it.text, false) } + cur.expressions.map { Term(it.text, true) }
                }.orEmpty(),
                kind = context.getString(R.string.watch_book),
                title = scenario.cardTitle,
                subtitle = listOfNotNull(
                    counterpartName ?: role.ifEmpty { null },
                    scenario.category,
                ).joinToString(" · "),
                meta = meta,
                sections = sections,
            )
        }

        /**
         * A Talk book: the score and the coach's note, the material the talk
         * produced, then the whole conversation with its corrections attached
         * — the transcript is what makes this worth reading on a bigger
         * screen.
         *
         * Every chapter is derived from the same fields the book PAGE reads,
         * so the paper copy and the screen can't say different things.
         */
        fun make(context: Context, session: Session): BookDocument {
            val sm = session.summary
            val meta = ArrayList<String>()
            meta.add(dateLine(session.endedAt ?: session.startedAt))
            sm?.scorecard?.let { meta.add("${context.getString(R.string.score)} ${it.overall}") }

            val sections = ArrayList<Section>()
            sm?.overallNote?.trim()?.takeIf { it.isNotEmpty() }?.let {
                sections.add(Section(context.getString(R.string.overview), blurb = it, kind = Section.Kind.OVERVIEW))
            }

            val firstTimeWords = sm?.newWordsUsed.orEmpty()
            // What the glossary at the back will look up: words as words,
            // phrases as phrases.
            val talkTerms = firstTimeWords.map { Term(it, false) } +
                sm?.expressionsOffered.orEmpty().map { Term(it, true) } +
                sm?.expressionsUsed.orEmpty().map { Term(it, true) }
            if (firstTimeWords.isNotEmpty()) {
                sections.add(Section(context.getString(R.string.words_d26d55),
                    kind = Section.Kind.WORDS,
                    entries = firstTimeWords.map {
                        Entry(it, note = context.getString(R.string.you_used_this_for_the_first_time))
                    }))
            }

            // Both halves of the book's Expressions chapter: the phrases the
            // fluent self offered, then the ones the learner already said.
            val offered = sm?.expressionsOffered.orEmpty()
            val used = sm?.expressionsUsed.orEmpty()
            if (offered.isNotEmpty() || used.isNotEmpty()) {
                sections.add(Section(context.getString(R.string.expressions),
                    kind = Section.Kind.EXPRESSIONS,
                    entries = offered.map {
                        Entry(it, note = context.getString(R.string.your_fluent_self_used_this_you_didnt),
                            example = sentence(saying = it, session = session))
                    } + used.map { Entry(it, example = sentence(saying = it, session = session)) }))
            }

            val fluentLines = session.turns
                .filter { it.role == TurnRole.FLUENT_SELF && it.transcript.isNotBlank() }
                .map { it.transcript }
            if (fluentLines.isNotEmpty()) {
                sections.add(Section(context.getString(R.string.shadow),
                    kind = Section.Kind.SHADOW,
                    entries = fluentLines.map { Entry(it) }))
            }

            // Corrections — the learner's own sentence next to the fluent one.
            // The original is TRIMMED to the sentence the correction rewrites
            // (the same trim the Drill chapter applies): a minute-long turn
            // struck through in full reads as "everything you said was wrong".
            val corrections = sm?.phrasesUsed.orEmpty().map {
                Entry(it.fluentAlternative, note = it.reason,
                    original = DrillIngest.relevantFragment(it.userSaid, it.fluentAlternative))
            }
            if (corrections.isNotEmpty()) {
                sections.add(Section(context.getString(R.string.drill), entries = corrections,
                    kind = Section.Kind.DRILL))
            }

            val transcript = session.turns.filter { it.transcript.isNotBlank() }
            if (transcript.isNotEmpty()) {
                sections.add(Section(context.getString(R.string.transcript),
                    kind = Section.Kind.TRANSCRIPT,
                    lines = transcript.map { turn ->
                        Line(
                            speaker = if (turn.role == TurnRole.USER)
                                context.getString(R.string.you)
                            else context.getString(R.string.future_self),
                            text = turn.transcript,
                            isUser = turn.role == TurnRole.USER,
                            correction = turn.suggestion?.alternative,
                            correctionNote = turn.suggestion?.reason.orEmpty(),
                        )
                    }))
            }

            return BookDocument(
                terms = talkTerms,
                kind = context.getString(R.string.talk_book),
                title = session.displayTitle ?: context.getString(R.string.conversation),
                meta = meta,
                sections = sections,
            )
        }

        /**
         * The sentence of THIS talk that carried the phrase — the fluent
         * self's first, then the learner's (iOS 25e4d8e2). A talk-book
         * expression has no example of its own, and the workbook's "Copy it
         * out" page asks for a sentence to copy: before this the only source
         * was the glossary, fetched inside a time budget, so a missed lookup
         * printed "Copy the sentence" over an empty line. The line the phrase
         * was actually said in is on the phone and is the better example.
         */
        fun sentence(saying: String, session: Session): String {
            val needle = com.roro.futurevoice.talk.CarryoverDetector.normalized(saying)
            if (needle.isEmpty()) return ""
            val spaced = WordSplitter.spaced(session.targetLanguage)
            fun pad(s: String) = if (spaced) " $s " else s
            val target = pad(needle)
            val ordered = session.turns.filter { it.role == TurnRole.FLUENT_SELF } +
                session.turns.filter { it.role == TurnRole.USER }
            for (turn in ordered) {
                for (line in TalkCurriculum.sentences(turn.transcript)) {
                    if (pad(com.roro.futurevoice.talk.CarryoverDetector.normalized(line)).contains(target)) {
                        return line.trim()
                    }
                }
            }
            return ""
        }

        /** iOS `.dateTime.year().month(.wide).day()` — a skeleton, so each
         *  language orders it itself (2026년 10월 4일, October 4, 2026). A
         *  fixed "d MMMM yyyy" read "4 10월 2026" in Korean. */
        private fun dateLine(at: Long): String {
            val locale = Locale.getDefault()
            val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "yMMMMd")
            return SimpleDateFormat(pattern, locale).format(Date(at))
        }
    }
}
