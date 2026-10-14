package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.talk.ScriptStudyPrompt
import com.roro.futurevoice.talk.SpeechPrompts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File
import java.security.MessageDigest

/**
 * "Study" on a Speech script (iOS `ScriptStudy`, 3ebadf10, 2026-10-14): the
 * script's most useful expressions, grammar patterns and words marked IN the
 * text, and under each paragraph a short note in the learner's own language on
 * what that paragraph says or does — never a translation.
 *
 * MATERIAL vs NOTES: every highlighted span is the script's own text (target
 * language, verbatim — [locate] drops any span that isn't); every `note` and
 * paragraph note is coaching, in the native language.
 *
 * Written once per (script text, target, native, level) by one call on the
 * default model (`purpose: "script-study"`) and kept on disk, so reopening a
 * script is instant and costs nothing.
 *
 * Offsets index the paragraph's Kotlin String (UTF-16 units) where iOS counts
 * Characters; the cache is per device, so the two never meet.
 */
@Serializable
data class ScriptStudy(
    val highlights: List<Highlight>,
    /** One per paragraph, in order; "" where the model had nothing. */
    val paragraphNotes: List<String>,
) {
    @Serializable
    enum class Kind { @SerialName("expression") EXPRESSION, @SerialName("grammar") GRAMMAR, @SerialName("word") WORD;
        companion object {
            fun from(raw: String?): Kind? = when (raw?.lowercase()) {
                "expression" -> EXPRESSION; "grammar" -> GRAMMAR; "word" -> WORD; else -> null
            }
        }
    }

    @Serializable
    data class Highlight(
        val id: Int,
        /** Exactly as it stands in the script. */
        val text: String,
        val kind: Kind,
        /** A word's dictionary form, for the word card's lookup. */
        val lemma: String? = null,
        /** What it means and does HERE, in the native language. */
        val note: String,
        /** A fresh line using it, in the target language. */
        val example: String? = null,
        /** Where it is: paragraph index and offset/length inside that paragraph. */
        val paragraph: Int,
        val offset: Int,
        val length: Int,
    )

    fun count(kind: Kind) = highlights.count { it.kind == kind }
    fun highlightsIn(paragraph: Int) = highlights.filter { it.paragraph == paragraph }.sortedBy { it.offset }

    data class Candidate(
        val text: String,
        val kind: Kind,
        val lemma: String? = null,
        val note: String = "",
        val example: String? = null,
    )

    companion object {
        /** The script's paragraphs exactly as the prompter splits them: one
         *  per non-empty line. */
        fun paragraphs(body: String): List<String> =
            body.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

        /**
         * Keeps only spans that occur VERBATIM in the script, each at its
         * first place not already taken by an earlier span. Case may differ
         * only when no exact match exists. In a spaced language a span must
         * start and end on a word boundary ("art" never lights up inside
         * "start"). At most [limit].
         */
        fun locate(candidates: List<Candidate>, paragraphs: List<String>, spaced: Boolean,
                   limit: Int = 10): List<Highlight> {
            val taken = HashMap<Int, MutableList<IntRange>>()
            val out = mutableListOf<Highlight>()
            for (c in candidates) {
                if (out.size >= limit) break
                val span = c.text.trim()
                if (span.isEmpty() || span.length > 80) continue
                var placed: Pair<Int, Int>? = null
                search@ for (exactFirst in listOf(true, false)) {
                    for ((p, para) in paragraphs.withIndex()) {
                        for (start in occurrences(span, para, exactFirst)) {
                            val r = start until start + span.length
                            if (spaced && !onBoundary(para, r)) continue
                            if (taken[p].orEmpty().any { it.first <= r.last && r.first <= it.last }) continue
                            placed = p to start
                            break@search
                        }
                    }
                }
                val (p, start) = placed ?: continue
                taken.getOrPut(p) { mutableListOf() }.add(start until start + span.length)
                out.add(Highlight(id = out.size, text = paragraphs[p].substring(start, start + span.length),
                    kind = c.kind, lemma = c.lemma, note = c.note, example = c.example,
                    paragraph = p, offset = start, length = span.length))
            }
            return out
        }

        /** Offsets where [needle] starts in [hay]. */
        fun occurrences(needle: String, hay: String, caseSensitive: Boolean): List<Int> {
            val h = if (caseSensitive) hay else hay.lowercase()
            val n = if (caseSensitive) needle else needle.lowercase()
            // `lowercase` can change a string's length (İ); then only exact.
            if (n.isEmpty() || n.length > h.length ||
                (!caseSensitive && (h.length != hay.length || n.length != needle.length))) return emptyList()
            val out = mutableListOf<Int>()
            var i = 0
            while (i + n.length <= h.length) {
                if (h.regionMatches(i, n, 0, n.length)) out.add(i)
                i += 1
            }
            return out
        }

        private fun onBoundary(para: String, r: IntRange): Boolean {
            fun w(c: Char) = c.isLetterOrDigit()
            if (r.first > 0 && w(para[r.first - 1]) && w(para[r.first])) return false
            val end = r.last + 1
            if (end < para.length && w(para[end]) && w(para[end - 1])) return false
            return true
        }

        /** Bumped whenever the prompt changes what a study is. */
        const val PROMPT_VERSION = 1

        fun textHash(body: String) = sha(body.trim())

        fun cacheKey(body: String, target: String, native: String, level: String): String =
            sha("study$PROMPT_VERSION|${textHash(body)}|${target.substringBefore('-')}|$native|${level.lowercase()}")

        fun sha(s: String): String =
            MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}

/** `files/ScriptStudy/<key>.json`. Never pruned — a study is small, and
 *  re-making one is a paid call. */
object ScriptStudyStore {
    private fun dir(context: Context) = File(context.filesDir, "ScriptStudy").apply { mkdirs() }

    fun load(context: Context, key: String): ScriptStudy? = runCatching {
        StoreJson.json.decodeFromString(ScriptStudy.serializer(), File(dir(context), "$key.json").readText())
    }.getOrNull()

    fun save(context: Context, study: ScriptStudy, key: String) {
        runCatching {
            val f = File(dir(context), "$key.json")
            val tmp = File(f.path + ".tmp")
            tmp.writeText(StoreJson.json.encodeToString(ScriptStudy.serializer(), study))
            tmp.renameTo(f)
        }
    }
}

object ScriptStudyEngine {
    class StudyError : Exception("empty study")

    @Serializable private data class Item(
        val text: String? = null, val kind: String? = null, val lemma: String? = null,
        val note: String? = null, val example: String? = null,
    )
    @Serializable private data class Payload(
        val highlights: List<Item>? = null,
        @SerialName("paragraph_notes") val paragraphNotes: List<String>? = null,
    )

    /** From disk when it was made before; otherwise one model call. */
    suspend fun study(context: Context, script: SpeechScript, native: String, level: CefrLevel): ScriptStudy {
        val key = ScriptStudy.cacheKey(script.body, script.language, native, level.code)
        withContext(Dispatchers.IO) { ScriptStudyStore.load(context, key) }?.let { return it }
        val made = generate(script, native, level)
        withContext(Dispatchers.IO) { ScriptStudyStore.save(context, made, key) }
        return made
    }

    private suspend fun generate(script: SpeechScript, native: String, level: CefrLevel): ScriptStudy {
        val paragraphs = ScriptStudy.paragraphs(script.body)
        if (paragraphs.isEmpty()) throw StudyError()
        val system = ScriptStudyPrompt.system(
            level = level.code.uppercase(),
            target = LanguageCatalog.englishName(script.language),
            nativeName = LanguageCatalog.englishName(native),
            contract = SpeechPrompts.contract(script.language, native),
        )
        // The streaming door only for its long read timeout (iOS gives this
        // call 60 s; the shared client's per-read guard is 40 s). The decoded
        // payload is the same.
        val payload = GeminiClient(AuthRepository()).sendJsonStreamAccumulating(
            system = system,
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, ScriptStudyPrompt.user(paragraphs))),
            serializer = Payload.serializer(),
            model = GeminiClient.Model.FLASH_36,
            maxTokens = 4096,
            purpose = "script-study",
            onPartial = {},
        )
        fun clean(s: String?) = s?.trim()?.takeIf { it.isNotEmpty() }
        val candidates = payload.highlights.orEmpty().mapNotNull { item ->
            val text = item.text ?: return@mapNotNull null
            val kind = ScriptStudy.Kind.from(item.kind) ?: return@mapNotNull null
            ScriptStudy.Candidate(text, kind, clean(item.lemma), clean(item.note) ?: "", clean(item.example))
        }
        val highlights = ScriptStudy.locate(candidates, paragraphs, LanguageCatalog.writesSpaces(script.language))
        var notes = payload.paragraphNotes.orEmpty().map { it.trim() }
        if (notes.size > paragraphs.size) notes = notes.take(paragraphs.size)
        notes = notes + List(paragraphs.size - notes.size) { "" }
        if (highlights.isEmpty() && notes.none { it.isNotEmpty() }) throw StudyError()
        Analytics.capture("speech_study_made", mapOf("highlights" to highlights.size))
        return ScriptStudy(highlights, notes)
    }
}
