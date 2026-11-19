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
 * - expression: common expressions of their level.
 * - own: the learner's OWN expressions — on the "To study" list, never said
 *   in a talk, never marked known, never put off in the deck (those are the
 *   weekly test's) — each in a NEW sentence, and only when [rate] puts it at
 *   the learner's level or above (iOS 6912c9db, 2026-10-21: the old blanked
 *   fluent-self line asked "So ______?" with four choices that all fit).
 *
 * Never the learner's transcript: every line is written fresh, so nothing a
 * recognizer misheard can become an answer. The model writes; code decides
 * what is kept and grades. Then a SECOND call, not told the answer, marks
 * every choice that makes the line correct, and a question is kept only when
 * that is the answer alone ([check]).
 */
object QuickQuizStock {
    @Serializable
    enum class Kind { grammar, expression, own }

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
        /** own: the CEFR level [rate] gave the phrase. */
        val level: String? = null,
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
    /** The learner's own expressions sent per batch to be written. */
    const val OWN_PER_BATCH = 8
    /** How many batches each own phrase is sent to. One whose question keeps
     *  failing the check stops being sent, or a learner with a few such
     *  phrases would start a batch on every quiz. */
    const val MAX_TRIES = 2

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

    private suspend fun needsBatch(context: Context, language: String, level: CefrLevel): Boolean {
        val unasked = load(context).filter { it.asked == 0 }
        val low = listOf(Kind.grammar, Kind.expression).any { kind -> unasked.count { it.kind == kind } < REFILL_BELOW }
        // Own questions need a phrase still to rate or to write.
        val ownLow = unasked.count { it.kind == Kind.own } < REFILL_BELOW &&
            (unratedOwn(context, language).isNotEmpty() || unwrittenOwn(context, language, level).isNotEmpty())
        return low || ownLow
    }

    // ── The learner's own expressions

    private fun levelsFile(context: Context) = File(LanguageScope.activeDirectory(context), "quiz_levels.json")
    private fun triesFile(context: Context) = File(LanguageScope.activeDirectory(context), "quiz_own_tries.json")

    /** [rate]'s CEFR rating per own phrase (normalized key → a1…c2, or "none"
     *  for a phrase that is not an expression). */
    fun levels(context: Context): Map<String, String> = synchronized(lock) {
        runCatching { json.decodeFromString<Map<String, String>>(levelsFile(context).readText()) }.getOrDefault(emptyMap())
    }

    private fun tries(context: Context): Map<String, Int> = synchronized(lock) {
        runCatching { json.decodeFromString<Map<String, Int>>(triesFile(context).readText()) }.getOrDefault(emptyMap())
    }

    private fun writeMap(file: File, text: String) = synchronized(lock) {
        runCatching {
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(text)
            tmp.renameTo(file)
        }
    }

    private fun normalizedKey(text: String) = text.trim().lowercase()

    /** Still quiz material: never said, never marked known, never put off. */
    suspend fun isOpen(context: Context, phrase: String, language: String): Boolean =
        !VocabStore.shared(context).hasUsedExpression(phrase, language) &&
            StudyScheduleStore.shared(context).nextReview(StudyScheduleStore.Kind.EXPRESSION, phrase, language) == null

    /** At the learner's level or above. */
    fun atLevel(raw: String?, level: CefrLevel): Boolean {
        val l = CefrLevel.entries.firstOrNull { it.code.equals(raw, ignoreCase = true) } ?: return false
        return l.ordinal >= level.ordinal
    }

    /** A phrase with a slot in it ("end up -ing", "make up one's mind",
     *  "remind sb of sth") cannot stand in a sentence as written, and the
     *  answer must be the phrase as written. */
    fun hasSlot(phrase: String): Boolean {
        if (phrase.any { it in "~…/()[]" } || phrase.contains("...")) return true
        val slots = setOf("sb", "sth", "sb's", "sth's", "one's")
        return phrase.split(" ").any { it.startsWith("-") || it.lowercase() in slots }
    }

    private suspend fun ownCandidates(context: Context, language: String): List<String> {
        val all = runCatching { ExpressionCatalog.library(context, language) }.getOrDefault(emptyList())
        val out = ArrayList<String>()
        for (item in all) {
            if (item.known || !TextScript.isInTargetScript(item.text, language) || hasSlot(item.text)) continue
            if (isOpen(context, item.text, language)) out += item.text
        }
        return out
    }

    /** Own expressions with no rating yet, newest first. */
    private suspend fun unratedOwn(context: Context, language: String): List<String> {
        val rated = levels(context)
        return ownCandidates(context, language).filter { normalizedKey(it) !in rated }
    }

    /** Own expressions rated at the learner's level with no question yet. */
    private suspend fun unwrittenOwn(context: Context, language: String, level: CefrLevel): List<String> {
        val rated = levels(context)
        val written = load(context).filter { it.kind == Kind.own }.map { normalizedKey(it.answer) }.toSet()
        val tried = tries(context)
        return ownCandidates(context, language).filter {
            val k = normalizedKey(it)
            k !in written && (tried[k] ?: 0) < MAX_TRIES && atLevel(rated[k], level)
        }
    }

    @Serializable
    private data class Ratings(val results: List<Rating> = emptyList()) {
        @Serializable data class Rating(val n: Int = 0, val level: String? = null)
    }

    /** Rates each phrase's CEFR level, or "none" when it is not a reusable
     *  expression at all. Never told the learner's level — told it, the model
     *  rated "what's on your mind" a2 for an A2 learner and b1 for a B1 one
     *  (iOS probe, 2026-10-21). A phrase the call leaves out stays unrated. */
    private suspend fun rate(context: Context, client: GeminiClient, phrases: List<String>, targetName: String) {
        if (phrases.isEmpty()) return
        val user = phrases.mapIndexed { i, p -> "${i + 1}. $p" }.joinToString("\n")
        val key = MessageDigest.getInstance("SHA-256").digest(user.toByteArray(Charsets.UTF_8))
            .take(8).joinToString("") { "%02x".format(it) }
        val r: Ratings = try {
            withTimeoutOrNull(30_000) {
                client.sendJson(
                    system = QuickQuizPrompts.rateSystem(targetName),
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                    serializer = Ratings.serializer(),
                    maxTokens = 1500, purpose = "quiz",
                    idempotencyKey = "quiz-rate:$key")
            } ?: return
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException && e !is kotlinx.coroutines.TimeoutCancellationException) throw e
            return
        }
        val map = levels(context).toMutableMap()
        for (it in r.results) {
            val phrase = phrases.getOrNull(it.n - 1) ?: continue
            val lvl = it.level?.lowercase() ?: continue
            if (lvl != "none" && CefrLevel.entries.none { c -> c.code == lvl }) continue
            map[normalizedKey(phrase)] = lvl
        }
        writeMap(levelsFile(context), json.encodeToString(map))
    }

    /** Fill the stock before anyone opens a quiz, so the first one is full
     *  (the Talk tab calls this when the quiz button appears). */
    fun prewarm(context: Context, language: String, native: String, level: CefrLevel) {
        // A batch that just failed (offline, signed out) is not retried on
        // every return to the tab.
        if (System.currentTimeMillis() - lastFailure <= 600_000L) return
        val app = context.applicationContext
        scope.async { if (needsBatch(app, language, level)) startWriting(app, language, native, level) }
    }

    /**
     * What can be asked now, least-asked first — grammar one per point.
     * Writes a batch first when the stock is low, waiting only when there is
     * too little to ask without it. Nothing is marked asked here: the quiz
     * marks what it actually used ([markAsked]).
     */
    suspend fun available(context: Context, language: String, native: String, level: CefrLevel,
                          grammar: Int, expressions: Int): Triple<List<QuickQuizItem>, List<QuickQuizItem>, List<QuickQuizItem>> {
        var stock = load(context).filter { it.asked < MAX_ASKED }
        if (needsBatch(context, language, level)) {
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
        // Re-judged at every quiz: a phrase said or put off since it was
        // written is no longer the quiz's, and the level may have moved.
        val o = ArrayList<Stored>()
        for (q in ordered) {
            if (o.size >= expressions) break
            if (q.kind != Kind.own || !atLevel(q.level, level) || !isOpen(context, q.answer, language)) continue
            if (phrases.add(CarryoverDetector.normalized(q.answer))) o += q
        }
        return Triple(g.map(::item), e.map(::item), o.map(::item))
    }

    private fun item(q: Stored): QuickQuizItem = when (q.kind) {
        Kind.grammar -> QuickQuizItem(QuickQuizItem.Kind.GRAMMAR, prompt = q.sentence, answer = q.answer,
            options = (listOf(q.answer) + q.wrong).shuffled(),
            heading = q.point.ifEmpty { null }, note = q.tip.ifEmpty { null }, stockId = q.id)
        Kind.expression, Kind.own -> {
            // The meaning is the note: it says what was just picked.
            val meaning = listOf(q.point, q.tip).filter { it.isNotEmpty() }.joinToString(" · ")
            QuickQuizItem(QuickQuizItem.Kind.EXPRESSION, prompt = q.sentence, answer = q.answer,
                options = (listOf(q.answer) + q.wrong).shuffled(),
                note = if (meaning.isEmpty()) null else "${q.answer} — $meaning", stockId = q.id,
                isOwn = q.kind == Kind.own)
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
        val type = (string("type", "kind") ?: "").lowercase()
        val kind = when {
            type.startsWith("own") -> Kind.own
            type.startsWith("expr") -> Kind.expression
            else -> Kind.grammar
        }
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
        val client = GeminiClient(AuthRepository())
        // Rate first, in a call that is never told the learner's level.
        rate(context, client, unratedOwn(context, target).take(OWN_PER_BATCH * 2), targetName)
        val ownPhrases = unwrittenOwn(context, target, level).take(OWN_PER_BATCH)
        if (ownPhrases.isNotEmpty()) {
            user += "\nThe learner's own expressions (type \"own\"):\n" +
                ownPhrases.joinToString("\n") { "- $it" }
        }

        val key = MessageDigest.getInstance("SHA-256")
            .digest((system + user + "${System.currentTimeMillis() / 1000.0}").toByteArray(Charsets.UTF_8))
            .take(8).joinToString("") { "%02x".format(it) }
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

        val rated = levels(context)
        val sentKeys = ownPhrases.map(::normalizedKey).toSet()
        if (sentKeys.isNotEmpty()) {
            val t = tries(context).toMutableMap()
            for (k in sentKeys) t[k] = (t[k] ?: 0) + 1
            writeMap(triesFile(context), json.encodeToString(t))
        }

        val seen = load(context).map { CarryoverDetector.normalized(it.sentence) }.toHashSet()
        val valid = ArrayList<Stored>()
        for (it in written) {
            var q = validated(it, target) ?: continue
            if (!seen.add(CarryoverDetector.normalized(q.sentence))) continue
            if (q.kind == Kind.own) {
                // The answer must be the phrase itself, rated at the level.
                val k = normalizedKey(q.answer)
                if (k !in sentKeys || !atLevel(rated[k], level)) continue
                q = q.copy(level = rated[k])
            }
            valid += q
        }
        val added = check(client, valid, targetName, key)
        // One row per batch: how many were written, survived code, survived
        // the second reading — the only record of what the drop rate is.
        Telemetry.log("quiz_stock_batch", mapOf("stage" to "done", "written" to "${written.size}",
            "valid" to "${valid.size}", "kept" to "${added.size}",
            "kept_expressions" to "${added.count { it.kind == Kind.expression }}",
            "own_sent" to "${ownPhrases.size}", "kept_own" to "${added.count { it.kind == Kind.own }}",
            "own_points" to "${own.size}", "lang" to target))
        if (added.isEmpty()) return null
        synchronized(lock) { save(context, load(context) + added) }
        return added
    }

    @Serializable
    private data class Verdicts(val results: List<Result> = emptyList()) {
        @Serializable data class Result(val n: Int = 0, val ok: List<String> = emptyList())
    }

    /** The weekly test's way in to [check]: its blanked lines are kept only
     *  when the answer alone fits them (iOS `keepOnlyAnswer`). */
    suspend fun keepOnlyAnswer(questions: List<Stored>, targetName: String, key: String): List<Stored> =
        check(GeminiClient(AuthRepository()), questions, targetName, key)

    /** The weekly test's way in to [rate]: rates whichever of [phrases] has
     *  no rating yet (the same cache the quiz reads). */
    suspend fun rateMissing(context: Context, phrases: List<String>, targetName: String) {
        val rated = levels(context)
        rate(context, GeminiClient(AuthRepository()), phrases.filter { normalizedKey(it) !in rated }, targetName)
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

    // ── A quiz made to order from the learner's own mistakes

    // The quiz the tutor hands over when asked for one "from my mistakes"
    // (iOS 40b95f3f, founder: a quiz written into the chat as text is worth
    // nothing; it has to be tapped through). Each question is a NEW sentence
    // on the point of one correction from their last week of talks, written
    // and then checked like every stock question ([validated], [check]), so a
    // misheard line never becomes the right answer. Nothing is stored: it is
    // written when the button is tapped, for that sitting.

    data class Mistake(val was: String, val now: String, val why: String)

    const val MISTAKE_QUIZ_SIZE = 8
    /** Under this many corrections in the last week, the window widens. */
    const val MISTAKE_QUIZ_THIN = 4

    /** What a mistake quiz would be written from: the corrections of the last
     *  7 days of talks, then 30 when that is thin, then the recurring ones. */
    suspend fun mistakeSources(context: Context, target: String, level: CefrLevel,
                               now: Long = System.currentTimeMillis()): List<Mistake> {
        val sessions = SessionStore.shared(context).load(target)
            .filter { it.endedAt != null }
            .sortedByDescending { it.startedAt }
        val seen = HashSet<String>()
        val out = ArrayList<Mistake>()
        fun add(was: String, fixed: String, why: String) {
            val w = was.trim()
            val f = fixed.trim()
            if (w.isEmpty() || f.isEmpty() || !TextScript.isInTargetScript(f, target) ||
                !seen.add(CarryoverDetector.normalized(w))) return
            out += Mistake(was = w, now = f, why = why)
        }
        for (days in listOf(7.0, 30.0)) {
            val since = now - (days * 86_400_000).toLong()
            for (s in sessions) {
                if (s.startedAt < since) continue
                for (fix in s.turns.filter { it.isEvidence }.flatMap { it.suggestion?.fixes ?: emptyList() }) {
                    add(fix.was, fix.now, fix.why)
                }
            }
            if (out.size >= MISTAKE_QUIZ_THIN) break
        }
        if (out.size < MISTAKE_QUIZ_THIN) {
            val profile = ProfileStore.shared(context).load(target, level.code)
            for ((pattern, _) in GrammarFocus.candidates(profile, sessions, now)) {
                add(pattern.mistake, pattern.correction, pattern.context)
            }
        }
        return out.take(14)
    }

    suspend fun mistakeQuiz(context: Context, target: String, native: String, level: CefrLevel): List<QuickQuizItem> {
        val sources = mistakeSources(context, target, level)
        if (sources.isEmpty()) return emptyList()
        val targetName = LanguageCatalog.englishName(target)
        val nativeName = LanguageCatalog.englishName(native)
        val system = QuickQuizPrompts.mistakeSystem(targetName, nativeName, level.code.uppercase(),
            WordSplitter.spaced(target))
        val user = sources.mapIndexed { i, m ->
            "${i + 1}. \"${m.was}\" → \"${m.now}\"" + (if (m.why.isEmpty()) "" else " (${m.why})")
        }.joinToString("\n")
        val key = MessageDigest.getInstance("SHA-256")
            .digest((user + "${System.currentTimeMillis() / 1000.0}").toByteArray(Charsets.UTF_8))
            .take(8).joinToString("") { "%02x".format(it) }
        val client = GeminiClient(AuthRepository())
        val items: List<JsonObject> = try {
            withTimeoutOrNull(45_000) {
                val root = client.sendJson(
                    system = system,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                    serializer = JsonObject.serializer(),
                    maxTokens = 6000, purpose = "quiz",
                    idempotencyKey = "quiz-stock:$key")
                (root["items"] as? JsonArray ?: throw IllegalStateException("no items")).mapNotNull { it as? JsonObject }
            } ?: throw java.util.concurrent.TimeoutException("mistake quiz write timed out")
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException && e !is kotlinx.coroutines.TimeoutCancellationException) throw e
            Telemetry.log("mistake_quiz", mapOf("stage" to "write", "error" to e.toString().take(200)))
            return emptyList()
        }
        val from = HashMap<String, Mistake>()
        val seen = HashSet<String>()
        val written = ArrayList<Stored>()
        for (it in items) {
            fun string(name: String) = (it[name] as? JsonPrimitive)?.takeIf { p -> p.isString }?.contentOrNull
            val sentence = string("sentence") ?: continue
            val answer = string("answer") ?: continue
            val wrong = (it["wrong"] as? JsonArray)?.mapNotNull { w ->
                (w as? JsonPrimitive)?.takeIf { p -> p.isString }?.contentOrNull
            } ?: emptyList()
            val q = validated(Written(Kind.grammar, point = string("point") ?: "", tip = string("tip"),
                sentence = sentence, answer = answer, wrong = wrong), target) ?: continue
            if (!seen.add(CarryoverDetector.normalized(q.sentence))) continue
            written += q
            val n = (it["n"] as? JsonPrimitive)?.intOrNull
            if (n != null && n - 1 in sources.indices) from[q.id] = sources[n - 1]
        }
        val kept = check(client, written, targetName, key)
        Telemetry.log("mistake_quiz", mapOf("stage" to "done", "sources" to "${sources.size}",
            "written" to "${items.size}", "valid" to "${written.size}",
            "kept" to "${kept.size}", "lang" to target))
        return kept.take(MISTAKE_QUIZ_SIZE).map { q ->
            // The note says why, then shows the line it came from.
            var note = q.tip
            from[q.id]?.let { m ->
                note += (if (note.isEmpty()) "" else "\n") +
                    "${context.getString(com.roro.futurevoice.R.string.last_time_you_said)}: ${m.was} → ${m.now}"
            }
            QuickQuizItem(QuickQuizItem.Kind.GRAMMAR, prompt = q.sentence, answer = q.answer,
                options = (listOf(q.answer) + q.wrong).shuffled(),
                heading = q.point.ifEmpty { null },
                note = note.ifEmpty { null }, isOwn = true)
        }
    }
}
