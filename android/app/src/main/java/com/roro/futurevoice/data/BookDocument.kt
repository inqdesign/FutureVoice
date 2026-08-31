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
 * ([markdown], [html] → PDF), and every builder feeds the same thing. Add a
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
) {
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
    ) {
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

    /**
     * Print-shaped HTML: black on white, one column, generous leading — meant
     * to be marked up with a pencil, not to look like the app.
     *
     * The document is authored as HTML because the PDF is produced by handing
     * this to a WebView's print adapter, which is the only thing on Android
     * that flows arbitrary-length text across pages without hand-rolling
     * pagination — the same reason iOS authors it as HTML.
     */
    val html: String
        get() {
            fun esc(s: String) = s
                .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

            val body = StringBuilder()
            body.append("<header><p class=\"kind\">${esc(kind)}</p><h1>${esc(title)}</h1>")
            val head = (if (subtitle.isEmpty()) emptyList() else listOf(subtitle)) + meta
            if (head.isNotEmpty()) {
                body.append("<p class=\"meta\">${esc(head.joinToString(" · "))}</p>")
            }
            body.append("</header>")

            for (section in sections) {
                if (section.isEmpty && section.blurb.isEmpty()) continue
                body.append("<section><h2>${esc(section.title)}</h2>")
                if (section.blurb.isNotEmpty()) {
                    body.append("<p class=\"blurb\">${esc(section.blurb)}</p>")
                }

                if (section.entries.isNotEmpty()) {
                    body.append("<ul>")
                    for (entry in section.entries) {
                        val box = when (entry.mastered) {
                            true -> "<span class=\"box done\">&#10003;</span>"
                            false -> "<span class=\"box\"></span>"
                            null -> "<span class=\"box none\"></span>"
                        }
                        body.append("<li>$box<div class=\"item\">")
                        if (!entry.original.isNullOrEmpty()) {
                            body.append("<p class=\"said\">${esc(entry.original)}</p>")
                        }
                        body.append("<p class=\"text\">${esc(entry.text)}</p>")
                        if (entry.example.isNotEmpty()) {
                            body.append("<p class=\"example\">${esc(entry.example)}</p>")
                        }
                        if (entry.note.isNotEmpty()) {
                            body.append("<p class=\"note\">${esc(entry.note)}</p>")
                        }
                        body.append("</div></li>")
                    }
                    body.append("</ul>")
                }

                for (line in section.lines) {
                    body.append("<div class=\"turn${if (line.isUser) " mine" else ""}\">")
                    body.append("<p class=\"speaker\">${esc(line.speaker)}</p>")
                    body.append("<p class=\"line\">${esc(line.text)}</p>")
                    if (!line.correction.isNullOrEmpty()) {
                        body.append("<p class=\"fix\">${esc(line.correction)}</p>")
                        if (line.correctionNote.isNotEmpty()) {
                            body.append("<p class=\"note\">${esc(line.correctionNote)}</p>")
                        }
                    }
                    body.append("</div>")
                }
                body.append("</section>")
            }

            return """
            <!doctype html><html><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1"><style>
            * { box-sizing: border-box; }
            body { font: 12pt/1.55 sans-serif; color: #111; margin: 0; }
            header { border-bottom: 1.5px solid #111; padding-bottom: 10pt; margin-bottom: 18pt; }
            .kind { font-size: 8.5pt; letter-spacing: .1em; text-transform: uppercase;
                    color: #777; margin: 0 0 4pt; }
            h1 { font-size: 21pt; line-height: 1.2; margin: 0; font-weight: 600; }
            .meta { font-size: 9.5pt; color: #666; margin: 6pt 0 0; }
            section { margin-bottom: 20pt; }
            h2 { font-size: 12.5pt; font-weight: 600; margin: 0 0 8pt;
                 padding-bottom: 3pt; border-bottom: .5px solid #ccc; }
            .blurb { margin: 0 0 8pt; color: #333; }
            ul { list-style: none; margin: 0; padding: 0; }
            li { display: flex; align-items: flex-start; page-break-inside: avoid;
                 padding: 5pt 0; border-bottom: .5px solid #eee; }
            .box { display: inline-block; width: 11pt; height: 11pt; margin: 3pt 9pt 0 0;
                   border: .8px solid #999; border-radius: 2pt; flex: 0 0 auto;
                   text-align: center; line-height: 11pt; font-size: 8.5pt; color: #111; }
            .box.done { border-color: #111; }
            .box.none { border: none; }
            .item { flex: 1 1 auto; }
            .item p { margin: 0; }
            .text { font-weight: 600; }
            .said { color: #888; text-decoration: line-through; }
            .example { color: #333; font-style: italic; margin-top: 1pt !important; }
            .note { color: #777; font-size: 10pt; margin-top: 2pt !important; }
            .turn { page-break-inside: avoid; margin-bottom: 10pt; padding-left: 0; }
            .turn.mine { padding-left: 24pt; }
            .speaker { font-size: 8.5pt; letter-spacing: .06em; text-transform: uppercase;
                       color: #888; margin: 0 0 1pt; }
            .line { margin: 0; }
            .fix { margin: 3pt 0 0; padding-left: 8pt; border-left: 2px solid #bbb; }
            </style></head><body>$body</body></html>
            """.trimIndent()
        }

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
                val total = c.words.size + c.expressions.size + c.shadowLines.size
                if (total > 0) {
                    val done = c.words.count { it.masteredAt != null } +
                        c.expressions.count { it.masteredAt != null }
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
                fun section(title: String, items: List<ScenarioCurriculum.Item>): Section? =
                    if (items.isEmpty()) null else Section(title, entries = items.map {
                        Entry(it.text, it.note, it.example.orEmpty(),
                            mastered = it.masteredAt != null)
                    })
                sections += listOfNotNull(
                    section(context.getString(R.string.words_d26d55), c.words),
                    section(context.getString(R.string.expressions), c.expressions),
                    section(context.getString(R.string.shadow), c.shadowLines),
                )
            }

            return BookDocument(
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
                sections.add(Section(context.getString(R.string.overview), blurb = it))
            }

            val firstTimeWords = sm?.newWordsUsed.orEmpty()
            if (firstTimeWords.isNotEmpty()) {
                sections.add(Section(context.getString(R.string.words_d26d55),
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
                    entries = offered.map {
                        Entry(it, note = context.getString(R.string.your_fluent_self_used_this_you_didnt))
                    } + used.map { Entry(it) }))
            }

            val fluentLines = session.turns
                .filter { it.role == TurnRole.FLUENT_SELF && it.transcript.isNotBlank() }
                .map { it.transcript }
            if (fluentLines.isNotEmpty()) {
                sections.add(Section(context.getString(R.string.shadow),
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
                sections.add(Section(context.getString(R.string.drill), entries = corrections))
            }

            val transcript = session.turns.filter { it.transcript.isNotBlank() }
            if (transcript.isNotEmpty()) {
                sections.add(Section(context.getString(R.string.transcript),
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
                kind = context.getString(R.string.talk_book),
                title = session.displayTitle ?: context.getString(R.string.conversation),
                meta = meta,
                sections = sections,
            )
        }

        private fun dateLine(at: Long): String =
            SimpleDateFormat("d MMMM yyyy", Locale.getDefault()).format(Date(at))
    }
}
