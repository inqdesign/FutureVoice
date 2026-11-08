package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LearnerState
import com.roro.futurevoice.data.LevelMap
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import java.security.MessageDigest

/**
 * The LEVEL TAGGING call (docs/personal-report-plan.md, step 3; iOS
 * `LevelTagger`, 465331f6): which level-map items did the learner produce in
 * one talk, right or wrong?
 *
 * Its own call after the summary, never a field in it: the summary schema's
 * order is load-bearing and its prompt is measured, and tagging had to be
 * measured on its own. The prompt is [LevelTagPrompts], lifted byte for byte
 * from iOS — the one `scripts/level-tag-probe.py` measured.
 *
 * The model only REPORTS what it saw — counts and one verbatim quote per
 * verdict. Every quote is checked in code against the learner's own lines
 * ([isTheirs]), and an item whose quote isn't theirs is dropped; the status
 * an item ends up in is decided by [LearnerState.status], never the model.
 */
object LevelTagger {
    const val PURPOSE = "level-tag"
    /** Measured: low 91% recall, medium 96%, same zero false tags. The call
     *  runs after the talk and nobody waits on it, so the extra thinking is
     *  free time. */
    const val THINKING_LEVEL = "medium"
    /** Thinking spends from this ceiling. At 4096, 16 of 16 talks of 25 to
     *  140 learner lines came back cut off (2026-11-09); at 8192, the
     *  server's own limit, 2 of 16 did. Those go to [FALLBACK_THINKING_LEVEL]. */
    const val MAX_TOKENS = 8192
    /** For a run that still hit the ceiling: 20 of 20 long talks finished. */
    const val FALLBACK_THINKING_LEVEL = "low"

    // MARK: - Input

    /** The learner lines that may be judged: evidence only (not misheard,
     *  not read off the coach, not a tutor drill) and not empty. */
    fun evidenceLines(turns: List<Turn>): List<String> =
        turns.filter { it.isEvidence }.map { it.transcript.trim() }.filter { it.isNotEmpty() }

    /** `USER:` / `AI:` lines, the probe's format. A learner line that isn't
     *  evidence is left out entirely rather than labelled: it was not their
     *  own sentence, and the model has nothing to do with it. */
    fun transcript(turns: List<Turn>): String =
        turns.mapNotNull { turn ->
            val text = turn.transcript.trim()
            if (text.isEmpty()) return@mapNotNull null
            when (turn.role) {
                TurnRole.FLUENT_SELF -> "AI: $text"
                TurnRole.USER -> if (turn.isEvidence) "USER: $text" else null
            }
        }.joinToString("\n")

    /** The talk's verified fixes: the live call's per-turn `fixes` on
     *  evidence turns, then the summary's phrase fixes whose quote is the
     *  learner's (the same gate the summarizer applied), one per slip. */
    fun fixes(session: Session): List<Pair<String, String>> {
        val evidence = evidenceLines(session.turns)
        val seen = HashSet<String>()
        val out = mutableListOf<Pair<String, String>>()
        fun add(was: String, now: String) {
            val w = was.trim()
            val n = now.trim()
            val key = normalized(w)
            if (w.isEmpty() || n.isEmpty() || key.isEmpty() || key in seen) return
            seen += key
            out += w to n
        }
        for (turn in session.turns) {
            if (!turn.isEvidence) continue
            for (fix in turn.suggestion?.fixes.orEmpty()) add(fix.was, fix.now)
        }
        for (phrase in session.summary?.phrasesUsed.orEmpty()) {
            if (isTheirs(phrase.userSaid, evidence)) add(phrase.userSaid, phrase.fluentAlternative)
        }
        return out
    }

    fun userMessage(session: Session): String {
        var message = transcript(session.turns)
        val fixes = fixes(session)
        if (fixes.isNotEmpty()) {
            message += "\n\n" + LevelTagPrompts.FIXES_HEADER + "\n" +
                fixes.joinToString("\n") { LevelTagPrompts.fixLine(it.first, it.second) }
        }
        return message
    }

    /** What the learner said in this talk, hashed: a talk that is resumed
     *  (or has a line marked misheard) and summarized again is tagged again,
     *  its old contribution REPLACED; the same talk summarized twice is not. */
    fun fingerprint(turns: List<Turn>): String {
        val joined = evidenceLines(turns).joinToString("\n")
        val digest = MessageDigest.getInstance("SHA-256").digest(joined.toByteArray(Charsets.UTF_8))
        return digest.take(8).joinToString("") { "%02x".format(it) }
    }

    // MARK: - The quote check (mirrors the probe's `norm` / `theirs`)

    val FILLERS: Set<String> = setOf("uh", "um", "er", "erm", "ah", "hmm", "mm", "eh")

    /** Swift's `CharacterSet.alphanumerics`: letters, marks and numbers. */
    private fun isAlphanumeric(cp: Int): Boolean = when (Character.getType(cp).toByte()) {
        Character.UPPERCASE_LETTER, Character.LOWERCASE_LETTER, Character.TITLECASE_LETTER,
        Character.MODIFIER_LETTER, Character.OTHER_LETTER,
        Character.NON_SPACING_MARK, Character.ENCLOSING_MARK, Character.COMBINING_SPACING_MARK,
        Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
        else -> false
    }

    private fun isSpace(cp: Int): Boolean = Character.isWhitespace(cp) || Character.isSpaceChar(cp) ||
        cp == 0x85

    /**
     * Lowercased words with punctuation, fillers and stutters ("I am I am")
     * removed — the transcriber's noise, which a quote may fairly leave out
     * ("I am working on a new app" from "I am uh I am working on uh a new
     * app"). A typographic apostrophe reads as a plain one, so a model's
     * "I’m" still matches the recognizer's "I'm".
     */
    fun normalized(s: String): String {
        val lowered = s.lowercase().replace("’", "'")
        val cleaned = StringBuilder()
        var i = 0
        while (i < lowered.length) {
            val cp = lowered.codePointAt(i)
            val keep = isAlphanumeric(cp) || cp == '_'.code || cp == '\''.code || isSpace(cp)
            if (keep) cleaned.appendCodePoint(cp) else cleaned.append(' ')
            i += Character.charCount(cp)
        }
        val words = ArrayList<String>()
        val current = StringBuilder()
        var j = 0
        while (j < cleaned.length) {
            val cp = cleaned.codePointAt(j)
            if (isSpace(cp)) {
                if (current.isNotEmpty()) { words += current.toString(); current.setLength(0) }
            } else current.appendCodePoint(cp)
            j += Character.charCount(cp)
        }
        if (current.isNotEmpty()) words += current.toString()
        words.removeAll { it in FILLERS }
        var changed = true
        while (changed) {
            changed = false
            search@ for (n in intArrayOf(3, 2, 1)) {
                if (words.size < 2 * n) continue
                for (k in 0..(words.size - 2 * n)) {
                    if (words.subList(k, k + n) == words.subList(k + n, k + 2 * n)) {
                        words.subList(k + n, k + 2 * n).clear()
                        changed = true
                        break@search
                    }
                }
            }
        }
        return words.joinToString(" ")
    }

    /** The quote, cleaned, is inside one of the learner's lines, cleaned. */
    fun isTheirs(quote: String, lines: List<String>): Boolean {
        val q = normalized(quote)
        return q.isNotEmpty() && lines.any { normalized(it).contains(q) }
    }

    // MARK: - The answer

    data class GrammarHit(
        val id: String,
        val right: Int,
        val wrong: Int,
        val rightQuote: String = "",
        val wrongQuote: String = "",
    )

    data class FunctionHit(val id: String, val quote: String)

    data class Payload(val grammar: List<GrammarHit>, val functions: List<FunctionHit>) {
        companion object {
            /** One malformed entry costs that entry, not the talk (iOS's
             *  lossy decode): `id` must be a string; a count or quote that
             *  isn't one reads as 0 / "". */
            fun from(obj: JsonObject): Payload {
                fun str(o: JsonObject, k: String): String? =
                    (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
                fun int(o: JsonObject, k: String): Int {
                    val p = o[k] as? JsonPrimitive ?: return 0
                    if (p.isString) return 0
                    val d = p.doubleOrNull ?: return 0
                    return if (d == Math.floor(d) && !d.isInfinite() &&
                        d >= Int.MIN_VALUE && d <= Int.MAX_VALUE) d.toInt() else 0
                }
                fun entries(k: String): List<JsonObject> =
                    (obj[k] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()
                val grammar = entries("grammar").mapNotNull { o ->
                    val id = str(o, "id") ?: return@mapNotNull null
                    GrammarHit(id, int(o, "right"), int(o, "wrong"),
                        str(o, "right_quote") ?: "", str(o, "wrong_quote") ?: "")
                }
                val functions = entries("functions").mapNotNull { o ->
                    val id = str(o, "id") ?: return@mapNotNull null
                    FunctionHit(id, str(o, "quote") ?: "")
                }
                return Payload(grammar, functions)
            }
        }
    }

    /** A verdict above this is the model counting something else (every
     *  article in a monologue) — kept, but not allowed to swamp the state. */
    const val MAX_COUNT_PER_TALK = 20
    const val MAX_QUOTE_LENGTH = 160

    /**
     * The payload checked against the map and the learner's lines. An item
     * not on the map, with no use, or with a quote that isn't the learner's
     * is dropped (`dropped` counts the last kind — the measure of how often
     * the model put words in their mouth). Same rule as the probe: BOTH
     * quotes a verdict needs must be theirs.
     */
    fun verify(payload: Payload, map: LevelMap, evidence: List<String>): Pair<List<LearnerState.ItemTag>, Int> {
        val grammarIds = map.grammar.map { it.id }.toSet()
        val functionIds = map.functions.map { it.id }.toSet()
        val items = mutableListOf<LearnerState.ItemTag>()
        val taken = HashSet<String>()
        var dropped = 0
        fun clip(q: String): String {
            val t = q.trim()
            return if (t.codePointCount(0, t.length) > MAX_QUOTE_LENGTH)
                t.substring(0, t.offsetByCodePoints(0, MAX_QUOTE_LENGTH)) else t
        }
        for (hit in payload.grammar) {
            if (hit.id !in grammarIds || hit.id in taken) continue
            val right = hit.right.coerceIn(0, MAX_COUNT_PER_TALK)
            val wrong = hit.wrong.coerceIn(0, MAX_COUNT_PER_TALK)
            if (right + wrong <= 0) continue
            val rightOK = right == 0 || isTheirs(hit.rightQuote, evidence)
            val wrongOK = wrong == 0 || isTheirs(hit.wrongQuote, evidence)
            if (!(rightOK && wrongOK)) { dropped += 1; continue }
            val quotes = mutableListOf<LearnerState.Quote>()
            if (wrong > 0) quotes += LearnerState.Quote(text = clip(hit.wrongQuote), right = false)
            if (right > 0) quotes += LearnerState.Quote(text = clip(hit.rightQuote), right = true)
            items += LearnerState.ItemTag(id = hit.id, kind = LearnerState.Kind.GRAMMAR,
                right = right, wrong = wrong, quotes = quotes)
            taken += hit.id
        }
        for (hit in payload.functions) {
            if (hit.id !in functionIds || hit.id in taken) continue
            if (!isTheirs(hit.quote, evidence)) { dropped += 1; continue }
            // A function is DONE or not; one talk counts once.
            items += LearnerState.ItemTag(id = hit.id, kind = LearnerState.Kind.FUNCTION,
                right = 1, wrong = 0, quotes = listOf(LearnerState.Quote(text = clip(hit.quote), right = true)))
            taken += hit.id
        }
        return items to dropped
    }

    // MARK: - The call

    data class Outcome(val tag: LearnerState.SessionTag, val dropped: Int)

    /** A fresh key per request. The server treats a repeated key as a retry
     *  only for ten minutes and answers 409 after that, so a key made from
     *  the talk alone refused every later attempt. */
    fun requestKey(sessionId: String, fingerprint: String): String =
        "level-tag:$sessionId:$fingerprint:${java.util.UUID.randomUUID().toString().take(8)}"

    /** Tags one talk. Null when the language has no map or the learner said
     *  nothing that counts; throws only on the network/decode. */
    suspend fun tag(session: Session): Outcome? {
        val map = LevelMap.load(session.targetLanguage) ?: return null
        val evidence = evidenceLines(session.turns)
        if (evidence.isEmpty()) return null
        val fingerprint = fingerprint(session.turns)
        val system = LevelTagPrompts.systemPrompt(map, LanguageCatalog.englishName(session.targetLanguage))
        // iOS runs this on `GeminiClient.longRunning` (no 60 s ceiling): the
        // shared OkHttp client has none either — only its per-read guard.
        suspend fun send(thinking: String): JsonObject = GeminiClient(AuthRepository()).sendJson(
            system = system,
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, userMessage(session))),
            serializer = JsonObject.serializer(),
            model = GeminiClient.Model.FLASH_36,
            maxTokens = MAX_TOKENS,
            purpose = PURPOSE,
            idempotencyKey = requestKey(session.id.toString(), fingerprint),
            thinkingLevel = thinking,
        )
        val raw = try {
            send(THINKING_LEVEL)
        } catch (_: EdgeError.Truncated) {
            send(FALLBACK_THINKING_LEVEL)
        }
        val (items, dropped) = verify(Payload.from(raw), map, evidence)
        val talkDate = session.turns.lastOrNull()?.timestamp ?: session.endedAt ?: session.startedAt
        val tag = LearnerState.SessionTag(talkDate = talkDate, taggedAt = System.currentTimeMillis(),
            fingerprint = fingerprint, mapVersion = map.version, items = items)
        return Outcome(tag, dropped)
    }
}
