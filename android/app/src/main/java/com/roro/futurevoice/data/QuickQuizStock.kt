package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Telemetry
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.GrammarFocus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import java.io.File
import java.security.MessageDigest

/**
 * The quick quiz's WRITTEN questions: grammar, and the level's expressions
 * (iOS `QuickQuizStock`, f3cda184 / 02aff591 / 9c61e6de — 2026-10-18,
 * founder: "words, expressions and grammar"; then "someone who has made no
 * scene and had no call still gets a quiz at their level").
 *
 * Each is a NEW everyday line with a blank and four choices, exactly one of
 * which fits. They are written by one model call per batch and kept on disk
 * (`quiz_stock.json`, per language), so most quizzes ask nothing of the
 * model: a batch is written only when a kind has fewer than [REFILL_BELOW]
 * unasked questions, and a quiz waits for it at most [WRITE_WAIT_MS] — past
 * that it goes without and the batch lands for the next.
 *
 * - grammar: the learner's own recurring grammar points first (said in two
 *   talks or more, judged a grammar point by [GrammarFocus.describe]) and,
 *   with fewer than [MIN_POINTS] of those, the grammar of their level.
 * - expression: common expressions of their level. The learner's OWN study
 *   list is asked by [QuickQuizEngine] from the lines they heard.
 *
 * Never the learner's transcript: every line is written fresh, so nothing a
 * recognizer misheard can become an answer. The model writes; code decides
 * what is kept and grades. Then a SECOND call, not told the answer, marks
 * every choice that makes the line correct, and a question is kept only when
 * that is the answer alone ([check]).
 */
object QuickQuizStock {
    @Serializable
    enum class Kind { grammar, expression }

    @Serializable
    data class Stored(
        val id: String = StoreJson.newId(),
        val kind: Kind,
        /** grammar: the point's name · expression: what it means (native). */
        val point: String,
        val tip: String,
        val sentence: String,
        val answer: String,
        val wrong: List<String>,
        val asked: Int = 0,
        val createdAt: Long,
    )

    /** Below this many unasked questions of either kind, a batch is written. */
    const val REFILL_BELOW = 5
    /** Questions asked of the model per kind; about a third fail the check. */
    const val BATCH_PER_KIND = 8
    /** The learner's own points the batch is built on, at most. */
    const val MAX_POINTS = 4
    /** With fewer of the learner's own points, the level's grammar fills in. */
    const val MIN_POINTS = 2
    /** How long a quiz waits for a batch it needs now. */
    const val WRITE_WAIT_MS = 12_000L
    /** A question is retired once asked this often; the stock is capped. */
    const val MAX_ASKED = 2
    const val MAX_STORED = 60

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val lock = Any()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private fun file(context: Context) = File(LanguageScope.activeDirectory(context), "quiz_stock.json")

    fun load(context: Context): List<Stored> = synchronized(lock) {
        runCatching { json.decodeFromString<List<Stored>>(file(context).readText()) }.getOrDefault(emptyList())
    }

    private fun save(context: Context, list: List<Stored>) = synchronized(lock) {
        runCatching {
            val f = file(context)
            val tmp = File(f.parentFile, f.name + ".tmp")
            tmp.writeText(json.encodeToString(kotlinx.serialization.builtins.ListSerializer(Stored.serializer()),
                list.takeLast(MAX_STORED)))
            tmp.renameTo(f)
        }
    }

    /** The one batch being written, shared by the prewarm and a quiz. */
    private var writing: Deferred<List<Stored>?>? = null
    private var lastFailure = 0L

    private fun startWriting(context: Context, language: String, native: String, level: CefrLevel):
        Deferred<List<Stored>?> = synchronized(lock) {
        writing?.takeIf { it.isActive }?.let { return it }
        val app = context.applicationContext
        val task = scope.async {
            val result = runCatching { writeBatch(app, language, native, level) }.getOrNull()
            synchronized(lock) {
                if (result == null) lastFailure = System.currentTimeMillis()
                writing = null
            }
            result
        }
        writing = task
        task
    }

    private fun needsBatch(context: Context): Boolean {
        val unasked = load(context).filter { it.asked == 0 }
        return Kind.entries.any { kind -> unasked.count { it.kind == kind } < REFILL_BELOW }
    }

    /** Fill the stock before anyone opens a quiz, so the first one is full
     *  (the Talk tab calls this when the quiz button appears). */
    fun prewarm(context: Context, language: String, native: String, level: CefrLevel) {
        // A batch that just failed (offline, signed out) is not retried on
        // every return to the tab.
        if (!needsBatch(context) || System.currentTimeMillis() - lastFailure <= 600_000L) return
        startWriting(context, language, native, level)
    }

    /**
     * What can be asked now, least-asked first — grammar one per point.
     * Writes a batch first when the stock is low, waiting only when there is
     * too little to ask without it. Nothing is marked asked here: the quiz
     * marks what it actually used ([markAsked]).
     */
    suspend fun available(context: Context, language: String, native: String, level: CefrLevel,
                          grammar: Int, expressions: Int): Pair<List<QuickQuizItem>, List<QuickQuizItem>> {
        var stock = load(context).filter { it.asked < MAX_ASKED }
        if (needsBatch(context)) {
            val task = startWriting(context, language, native, level)
            val short = stock.count { it.kind == Kind.grammar } < grammar ||
                stock.count { it.kind == Kind.expression } < expressions
            if (short) {
                val waited = withTimeoutOrNull(WRITE_WAIT_MS) { task.await() }
                if (waited != null) stock = load(context).filter { it.asked < MAX_ASKED }
            }
        }
        val ordered = stock.sortedWith(compareBy<Stored>({ it.asked }, { it.createdAt }))

        val points = HashSet<String>()
        val g = ordered.filter { it.kind == Kind.grammar }
            .filter { points.add(it.point.lowercase()) }
            .take(grammar)
        val phrases = HashSet<String>()
        val e = ordered.filter { it.kind == Kind.expression }
            .filter { phrases.add(CarryoverDetector.normalized(it.answer)) }
            .take(expressions)
        return g.map(::item) to e.map(::item)
    }

    private fun item(q: Stored): QuickQuizItem = when (q.kind) {
        Kind.grammar -> QuickQuizItem(QuickQuizItem.Kind.GRAMMAR, prompt = q.sentence, answer = q.answer,
            options = (listOf(q.answer) + q.wrong).shuffled(),
            heading = q.point.ifEmpty { null }, note = q.tip.ifEmpty { null }, stockId = q.id)
        Kind.expression -> {
            // The meaning is the note: it says what was just picked.
            val meaning = listOf(q.point, q.tip).filter { it.isNotEmpty() }.joinToString(" · ")
            QuickQuizItem(QuickQuizItem.Kind.EXPRESSION, prompt = q.sentence, answer = q.answer,
                options = (listOf(q.answer) + q.wrong).shuffled(),
                note = if (meaning.isEmpty()) null else "${q.answer} — $meaning", stockId = q.id)
        }
    }

    /** Count the questions a quiz actually asked. */
    fun markAsked(context: Context, ids: Set<String>) {
        if (ids.isEmpty()) return
        synchronized(lock) {
            save(context, load(context).map { if (it.id in ids) it.copy(asked = it.asked + 1) else it })
        }
    }

    // ── Writing

    /** One element of `items`, read one question at a time: half the first
     *  device batches failed whole because ONE item came back as a string or
     *  under another key ("question" for "sentence") (iOS 02aff591). A
     *  question that can't be read is skipped, never the batch. */
    internal data class Written(val kind: Kind, val point: String, val tip: String?, val sentence: String,
                                val answer: String, val wrong: List<String>)

    internal fun parsePayload(root: JsonElement): List<Written> {
        val obj = root as? JsonObject ?: return emptyList()
        val raw = (obj["items"] as? JsonArray) ?: (obj["questions"] as? JsonArray) ?: return emptyList()
        return raw.mapNotNull(::loose)
    }

    private fun loose(element: JsonElement): Written? {
        // An object written out as a JSON string.
        (element as? JsonPrimitive)?.takeIf { it.isString }?.let { p ->
            return runCatching { Json.parseToJsonElement(p.content) }.getOrNull()?.let(::loose)
        }
        val c = element as? JsonObject ?: return null
        fun string(vararg names: String): String? {
            for (n in names) {
                val v = (c[n] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
                if (v != null && v.trim().isNotEmpty()) return v
            }
            return null
        }
        fun strings(vararg names: String): List<String>? {
            for (n in names) {
                val arr = c[n] as? JsonArray ?: continue
                val v = arr.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.contentOrNull ?: return@map null }
                if (v.all { it != null }) return v.filterNotNull()
            }
            return null
        }
        val sentence = string("sentence", "question", "text", "prompt") ?: return null
        val answer = string("answer", "correct", "correct_answer") ?: return null
        var wrong = strings("wrong", "wrong_choices", "distractors", "incorrect") ?: emptyList()
        if (wrong.isEmpty()) strings("choices", "options")?.let { all -> wrong = all.filter { it != answer } }
        val kind = if ((string("type", "kind") ?: "").lowercase().startsWith("expr")) Kind.expression else Kind.grammar
        return Written(kind, point = string("point", "meaning", "grammar_point", "grammar") ?: "",
            tip = string("tip", "explanation", "why"), sentence = sentence, answer = answer, wrong = wrong)
    }

    /** Writes one batch into the stock. Returns what was added, null on failure. */
    suspend fun writeBatch(context: Context, target: String, native: String, level: CefrLevel): List<Stored>? {
        val sessions = SessionStore.shared(context).load(target)
        val profile = ProfileStore.shared(context).load(target, level.code)
        val own = ArrayList<Triple<String, String, String>>()   // label, was, now
        for ((pattern, _) in GrammarFocus.candidates(profile, sessions)) {
            if (own.size >= MAX_POINTS) break
            val named = GrammarFocus.describe(context, pattern, target, native) ?: continue
            own += Triple(named.label, pattern.mistake, pattern.correction)
        }

        val targetName = LanguageCatalog.englishName(target)
        val nativeName = LanguageCatalog.englishName(native)
        val levelName = level.code.uppercase()
        val spokenTopics = sessions.mapNotNull { it.topic }.filter { it.isNotEmpty() }.takeLast(6)
        val system = QuickQuizPrompts.writeSystem(targetName, nativeName, levelName,
            WordSplitter.spaced(target), spokenTopics)
        var user = if (own.isEmpty()) {
            "This learner has no recurring grammar slips on file yet."
        } else {
            "Grammar points this learner keeps getting wrong (their slip → the right form):\n" +
                own.mapIndexed { i, p -> "${i + 1}. ${p.first}: \"${p.second}\" → \"${p.third}\"" }
                    .joinToString("\n")
        }
        if (own.size < MIN_POINTS) {
            user += "\nAlso use grammar points a $levelName learner of $targetName is working on."
        }
        val known = load(context).filter { it.kind == Kind.expression }.map { it.answer.lowercase() }.toSortedSet()
        if (known.isNotEmpty()) {
            user += "\nExpressions already used — pick others: " + known.joinToString(", ")
        }

        val key = MessageDigest.getInstance("SHA-256")
            .digest((system + user + "${System.currentTimeMillis() / 1000.0}").toByteArray(Charsets.UTF_8))
            .take(8).joinToString("") { "%02x".format(it) }
        val client = GeminiClient(AuthRepository())
        val written: List<Written> = try {
            withTimeoutOrNull(45_000) {
                parsePayload(client.sendJson(
                    system = system,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                    serializer = JsonElement.serializer(),
                    maxTokens = 6000, purpose = "quiz",
                    idempotencyKey = "quiz-stock:$key"))
            } ?: throw java.util.concurrent.TimeoutException("quiz stock write timed out")
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException && e !is kotlinx.coroutines.TimeoutCancellationException) throw e
            Telemetry.log("quiz_stock_batch", mapOf("stage" to "write", "error" to e.toString().take(200)))
            return null
        }

        val seen = load(context).map { CarryoverDetector.normalized(it.sentence) }.toHashSet()
        val valid = ArrayList<Stored>()
        for (it in written) {
            val q = validated(it, target) ?: continue
            if (!seen.add(CarryoverDetector.normalized(q.sentence))) continue
            valid += q
        }
        val added = check(client, valid, targetName, key)
        // One row per batch: how many were written, survived code, survived
        // the second reading — the only record of what the drop rate is.
        Telemetry.log("quiz_stock_batch", mapOf("stage" to "done", "written" to "${written.size}",
            "valid" to "${valid.size}", "kept" to "${added.size}",
            "kept_expressions" to "${added.count { it.kind == Kind.expression }}",
            "own_points" to "${own.size}", "lang" to target))
        if (added.isEmpty()) return null
        synchronized(lock) { save(context, load(context) + added) }
        return added
    }

    @Serializable
    private data class Verdicts(val results: List<Result> = emptyList()) {
        @Serializable data class Result(val n: Int = 0, val ok: List<String> = emptyList())
    }

    /** Keeps the questions whose ONLY working choice is the answer, as judged
     *  by a call that is never told which one was meant. A failed check keeps
     *  nothing: an unchecked question is the bug this exists for. */
    private suspend fun check(client: GeminiClient, questions: List<Stored>, targetName: String,
                              key: String): List<Stored> {
        if (questions.isEmpty()) return emptyList()
        val system = QuickQuizPrompts.checkSystem(targetName)
        val user = questions.mapIndexed { i, q ->
            "${i + 1}. ${q.sentence}\n   choices: ${(listOf(q.answer) + q.wrong).sorted().joinToString(" | ")}"
        }.joinToString("\n")
        val v: Verdicts = try {
            withTimeoutOrNull(45_000) {
                client.sendJson(
                    system = system,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                    serializer = Verdicts.serializer(),
                    maxTokens = 4000, purpose = "quiz",
                    idempotencyKey = "quiz-stock-check:$key")
            } ?: throw java.util.concurrent.TimeoutException("quiz stock check timed out")
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException && e !is kotlinx.coroutines.TimeoutCancellationException) throw e
            Telemetry.log("quiz_stock_batch", mapOf("stage" to "check", "error" to e.toString().take(200)))
            return emptyList()
        }
        val norm = CarryoverDetector::normalized
        return v.results.mapNotNull { r ->
            val q = questions.getOrNull(r.n - 1) ?: return@mapNotNull null
            if (r.ok.map(norm) == listOf(norm(q.answer))) q else null
        }
    }

    /** Code's half: one blank, four distinct choices, all in the target
     *  script, the answer not among the wrong ones. */
    internal fun validated(it: Written, language: String): Stored? {
        fun clean(s: String) = s.trim()
        // The model's blank comes back as "___" or "____" as often as ours.
        val blank = WeeklyTestEngine.BLANK_MARK
        val sentence = clean(it.sentence).replace(Regex("_{2,}"), blank)
        val answer = clean(it.answer)
        val wrong = it.wrong.map(::clean).filter { w -> w.isNotEmpty() }
        val all = listOf(answer) + wrong
        if (sentence.split(blank).size != 2 || answer.isEmpty() || wrong.size != 3 ||
            all.map(CarryoverDetector::normalized).toSet().size != 4 ||
            !all.all { c -> TextScript.isInTargetScript(c, language) } ||
            !TextScript.isInTargetScript(sentence.replace(blank, answer), language)) return null
        return Stored(kind = it.kind, point = clean(it.point), tip = clean(it.tip ?: ""), sentence = sentence,
            answer = answer, wrong = wrong, createdAt = System.currentTimeMillis())
    }
}
