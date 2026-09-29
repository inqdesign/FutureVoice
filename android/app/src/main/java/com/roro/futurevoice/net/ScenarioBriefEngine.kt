package com.roro.futurevoice.net

import android.content.Context
import android.util.Base64
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BriefAttachmentCache
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.ScenarioAttachmentReader
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioBrief
import com.roro.futurevoice.talk.UserPersona
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable
import java.time.LocalDate

/**
 * ONE Gemini call turns a situation's attached material into a
 * [ScenarioBrief] (iOS `ScenarioBriefEngine`, `59c6481`). Links are read by
 * the model itself (`url_context`), with web search filling what a page won't
 * give up; files ride inline. The call streams so the board on the scene can
 * tick as each section lands — the wrap-up board's rule: nothing is shown
 * before the model has actually written it.
 *
 * `purpose: "brief"` on the shared `gemini` function (cap 20/day, free) —
 * the same purpose iOS sends, so the two platforms share one daily cap.
 */
object ScenarioBriefEngine {

    /** What has landed so far. Counts are null until their section closed. */
    data class Progress(
        val sourcesRead: List<Boolean> = emptyList(),
        val summary: Boolean = false,
        val counterpartFacts: Int? = null,
        val likelyQuestions: Int? = null,
        val learnerFacts: Int? = null,
        val keyExpressions: Int? = null,
    )

    @Serializable
    private data class SourceRead(val index: Int = 0, val ok: Boolean = true, val detail: String? = null)

    @Serializable
    private data class Payload(
        val sources: List<SourceRead> = emptyList(),
        val summary: String = "",
        val counterpart_facts: List<String> = emptyList(),
        val likely_questions: List<String> = emptyList(),
        val learner_facts: List<String> = emptyList(),
        val key_expressions: List<String> = emptyList(),
    )

    class NothingToRead(message: String) : Exception(message)

    /**
     * Read every source on the brief and return it filled in. Bytes come from
     * [BriefAttachmentCache] first, then from each source's content URI; a
     * file that can be found neither way is marked `readOK = false` and the
     * reading goes on with the rest.
     */
    suspend fun read(
        context: Context,
        scenario: Scenario,
        persona: UserPersona?,
        targetLanguage: String,
        nativeLanguage: String,
        onProgress: (Progress) -> Unit = {},
    ): ScenarioBrief {
        val start = scenario.brief?.takeIf { it.hasSources }
            ?: throw NothingToRead(context.getString(R.string.nothing_to_read_attach_a_link_or_a_file_first))
        val sources = start.sources.toMutableList()

        val files = ArrayList<GeminiClient.InlineFile>()
        val fileLines = ArrayList<String>()
        val linkLines = ArrayList<String>()
        var total = 0
        sources.forEachIndexed { i, src ->
            when (src.kind) {
                ScenarioBrief.Kind.LINK -> linkLines += "- source ${i + 1} (link): ${src.label}"
                ScenarioBrief.Kind.FILE, ScenarioBrief.Kind.IMAGE -> {
                    var got = BriefAttachmentCache.take(src.id)
                    if (got == null) src.androidUri?.let { uri ->
                        got = runCatching { ScenarioAttachmentReader.reread(context, uri, src.label) }
                            .getOrNull()
                    }
                    val bytes = got
                    if (bytes == null || total + bytes.first.size > GeminiClient.MAX_INLINE_BYTES) {
                        sources[i] = src.copy(readOK = false,
                            detail = context.getString(R.string.couldn_t_open_pick_it_again))
                        fileLines += "- source ${i + 1} (file, NOT ATTACHED — could not be opened): ${src.label}"
                    } else {
                        total += bytes.first.size
                        files += GeminiClient.InlineFile(bytes.second,
                            Base64.encodeToString(bytes.first, Base64.NO_WRAP))
                        fileLines += "- source ${i + 1} (file, attached in order): ${src.label}"
                    }
                }
            }
        }

        val hasLinks = linkLines.isNotEmpty()
        val user = ArrayList<String>()
        user += "situation (the learner's own words): ${scenario.environment}"
        if (persona != null && persona.isMinimallyComplete) {
            val about = ArrayList<String>()
            if (persona.occupation.isNotBlank()) about += "work: ${persona.occupation}"
            val place = listOf(persona.city, persona.country).filter { it.isNotBlank() }.joinToString(", ")
            if (place.isNotEmpty()) about += "lives in: $place"
            if (about.isNotEmpty()) user += "learner: " + about.joinToString("; ")
        }
        user += ""
        user += "sources:"
        user += fileLines + linkLines
        if (hasLinks) {
            user += ""
            user += "Open every link above with the URL tool and read it. If a page cannot be opened, " +
                "search the web for what it names (the company and the position, the listing) " +
                "and say in that source's `detail` that you read coverage instead of the page."
        }
        user += ""
        user += "Today is ${LocalDate.now()}."

        val message = GeminiClient.Message(
            GeminiClient.Message.Role.USER, user.joinToString("\n"), inlineFiles = files)
        val system = systemPrompt(targetLanguage, nativeLanguage, sources.size)
        val key = "brief-v1:${scenario.id}:${System.currentTimeMillis() / 60_000}"

        var progress = Progress(sourcesRead = sources.map { false })
        onProgress(progress)
        val onPartial: suspend (String) -> Unit = { partial ->
            val read = progress.sourcesRead.toMutableList()
            for (obj in completedArrayObjects("sources", partial)) {
                val item = runCatching { Edge.json.decodeFromString(SourceRead.serializer(), obj) }.getOrNull()
                if (item != null && item.index in 1..read.size) read[item.index - 1] = true
            }
            val next = Progress(
                sourcesRead = read,
                summary = progress.summary || JsonFieldScanner.completedStringField("summary", partial) != null,
                counterpartFacts = completedCount("counterpart_facts", partial) ?: progress.counterpartFacts,
                likelyQuestions = completedCount("likely_questions", partial) ?: progress.likelyQuestions,
                learnerFacts = completedCount("learner_facts", partial) ?: progress.learnerFacts,
                keyExpressions = completedCount("key_expressions", partial) ?: progress.keyExpressions,
            )
            if (next != progress) { progress = next; onProgress(next) }
        }

        // Tools only when there is a link to open. If the tool call is refused
        // upstream, the same request runs again on search alone, then with no
        // tools — the files still ride inline, and an unopened link is
        // reported as such rather than failing the whole reading.
        val attempts = ArrayDeque(
            if (hasLinks) listOf(true to true, true to false, false to false)
            else listOf(false to false))
        val client = GeminiClient(AuthRepository())
        var payload: Payload? = null
        while (payload == null && attempts.isNotEmpty()) {
            val (search, url) = attempts.removeFirst()
            try {
                payload = client.sendJsonStreamAccumulating(
                    system = system,
                    messages = listOf(message),
                    serializer = Payload.serializer(),
                    model = GeminiClient.Model.FLASH_36,
                    maxTokens = 4000,
                    purpose = "brief",
                    idempotencyKey = key + if (url) "" else if (search) ":s" else ":n",
                    searchGrounding = search,
                    urlContext = url,
                    onPartial = onPartial,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // A spent pool or a hard wall is not a tool problem.
                if (attempts.isEmpty() || e is EdgeError.InsufficientCredits) throw e
            }
        }
        val p = payload ?: throw NothingToRead(context.getString(R.string.nothing_to_read_attach_a_link_or_a_file_first))

        for (r in p.sources) {
            val i = r.index - 1
            if (i !in sources.indices) continue
            // A file the app could not open stays "not read" whatever the model
            // says about it — it never saw the bytes.
            if (sources[i].readOK) {
                val d = r.detail?.trim()?.takeIf { it.isNotEmpty() }
                sources[i] = sources[i].copy(readOK = r.ok, detail = d ?: sources[i].detail)
            }
        }
        val brief = ScenarioBrief(
            sources = sources,
            summary = p.summary.trim(),
            counterpartFacts = clean(p.counterpart_facts, 8),
            likelyQuestions = clean(p.likely_questions, 10),
            learnerFacts = clean(p.learner_facts, 8),
            keyExpressions = clean(p.key_expressions, 14),
            readAt = System.currentTimeMillis(),
        )
        sources.forEach { BriefAttachmentCache.drop(it.id) }
        onProgress(Progress(
            sourcesRead = sources.map { true }, summary = true,
            counterpartFacts = brief.counterpartFacts.size,
            likelyQuestions = brief.likelyQuestions.size,
            learnerFacts = brief.learnerFacts.size,
            keyExpressions = brief.keyExpressions.size))
        return brief
    }

    private fun clean(list: List<String>, max: Int): List<String> {
        val seen = HashSet<String>()
        return list.map { it.trim() }.filter { it.isNotEmpty() && seen.add(it.lowercase()) }.take(max)
    }

    /** Index of the `[` opening the named array, or -1. */
    private fun arrayOpen(name: String, partial: String): Int {
        val k = partial.indexOf("\"$name\"")
        if (k < 0) return -1
        return partial.indexOf('[', k + name.length + 2)
    }

    /** Closed string elements of a string array that has itself closed; null
     *  while the array is still being written. */
    internal fun completedCount(name: String, partial: String): Int? {
        val open = arrayOpen(name, partial)
        if (open < 0) return null
        var depth = 0; var inString = false; var escaped = false; var count = 0
        for (i in open until partial.length) {
            val ch = partial[i]
            if (inString) {
                when {
                    escaped -> escaped = false
                    ch == '\\' -> escaped = true
                    ch == '"' -> { inString = false; if (depth == 1) count++ }
                }
            } else when (ch) {
                '"' -> inString = true
                '[' -> depth++
                ']' -> { depth--; if (depth == 0) return count }
            }
        }
        return null
    }

    /** Every `{…}` element of the named array that has closed so far. */
    internal fun completedArrayObjects(name: String, partial: String): List<String> {
        val open = arrayOpen(name, partial)
        if (open < 0) return emptyList()
        val out = ArrayList<String>()
        var depth = 0; var inString = false; var escaped = false; var objStart = -1
        for (i in open until partial.length) {
            val ch = partial[i]
            if (inString) {
                when {
                    escaped -> escaped = false
                    ch == '\\' -> escaped = true
                    ch == '"' -> inString = false
                }
                continue
            }
            when (ch) {
                '"' -> inString = true
                '[', '{' -> { depth++; if (ch == '{' && depth == 2) objStart = i }
                '}' -> { if (depth == 2 && objStart >= 0) { out += partial.substring(objStart, i + 1); objStart = -1 }; depth-- }
                ']' -> { depth--; if (depth == 0) return out }
            }
        }
        return out
    }

    private fun systemPrompt(targetLanguage: String, nativeLanguage: String, sourceCount: Int): String {
        val target = LanguageCatalog.englishName(targetLanguage)
        val native = LanguageCatalog.englishName(nativeLanguage)
        return """
        A language learner is about to go into a real situation and has attached material for it: a job posting and their CV, a listing, a letter, a slide deck, a photo of a form. You read the material ONCE and write a brief the app will use to simulate the situation — a scene in which a fluent version of the learner handles it, and a live role-play call in which the learner practices their side.

        TWO SIDES, KEPT APART. Sort every fact by whose it is:
        - the OTHER side (the company, the position, the landlord, the clinic): who they are, what they want, how they talk, and what they will ASK. A CV is never the other side's material.
        - the LEARNER's side (their CV, their portfolio, their letter): what they have done, the numbers they can quote, the gaps they will be asked about, what to prepare an answer for.
        Never hand the learner's facts to the other side to recite, and never invent a fact that is in neither source. Where a link could not be read and search gave only the company name, say so in `detail` and keep the facts thin rather than guessed.

        OUTPUT LANGUAGE, FIELD BY FIELD:
        - `likely_questions` and `key_expressions` are MATERIAL — what will be said out loud in the situation — so they are in $target, natural spoken register for this exact setting.
        - `summary`, `counterpart_facts`, `learner_facts` and every `detail` are NOTES the learner reads, so they are in $native. Keep proper names, product names and numbers as they appear in the source.

        Return STRICT JSON only — no prose, no code fences — with the keys in EXACTLY this order (the app reads progress off which key has closed):
        {
          "sources": [ { "index": 1, "ok": true, "detail": "..." } ],
          "summary": "...",
          "counterpart_facts": ["..."],
          "likely_questions": ["..."],
          "learner_facts": ["..."],
          "key_expressions": ["..."]
        }

        Rules:
        - sources: one entry per source, $sourceCount in total, in the order given. ok=false when you could not read it. detail = ONE short fragment saying what it is ("job posting · Berlin", "CV, 3 pages", "listing, 2 rooms") — never a sentence about what you did.
        - summary: one line naming what this is about — the company and the position, the flat and the street, the clinic and the visit.
        - counterpart_facts: 4–8 short lines. What the other side is, what they are looking for, anything they state they care about.
        - likely_questions: 6–10 lines the other side would actually say or ask in this situation, grounded in THEIR material. Vary the beats: openers, follow-ups, the awkward one.
        - learner_facts: 3–8 short lines from the learner's OWN material: the points worth bringing up, the numbers to quote, the gap or weak spot to have an answer for, the overlap between their material and the other side's.
        - key_expressions: 8–14 reusable chunks (2–6 words) this situation calls for — collocations, softeners, the moves natives make here. No full sentences, no single words.
        - Empty arrays are fine where a source did not give you the material. Never pad.
        """.trimIndent()
    }
}
