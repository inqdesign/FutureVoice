package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.talk.ConversationCharacter
import com.roro.futurevoice.talk.ConversationTurnPayload
import com.roro.futurevoice.talk.CorrectionOnlyPrompt
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File

/**
 * Whole-turn rewrites written for "Say it again" AFTER the talk, for the
 * learner turns the call itself left without one (iOS `SayItAgainRewrites`,
 * 2026-10-06).
 *
 * A turn can reach the book with no whole-turn rewrite in two ways: it was
 * saved before 2026-09-27, when `alternative` was a ≤15-word fragment that
 * [SayItAgainScript.coversWholeTurn] rightly refuses, or the live correction
 * call simply failed — it runs in the background mid-call and its failure was
 * invisible. Either way the prompter fell back to what they SAID, fillers and
 * false starts included, which is the one screen whose whole point is saying
 * it the better way.
 *
 * **Kept OUT of the session on purpose.** Writing a suggestion into the turn
 * would put new `fixes` in front of every reader of "the correction": the
 * talk book's Drill chapter would grow items whose cards were never minted
 * (ingest ran at the talk's end), so the book could never be finished, and
 * sync would carry a rewrite the other device never asked for. Here it is
 * practice text only: the prompter reads it, nothing is filed under it
 * (`attemptId` null), and the book is untouched. Device-local, a cache —
 * losing it costs one call on the next open (`files/say_again_rewrites.json`).
 *
 * The prompt is the live call's own [CorrectionOnlyPrompt], one turn per
 * request with the line said to them as context — the exact contract
 * `scripts/correction-probe.py` measured; a batched prompt would be a new,
 * unmeasured one.
 */
object SayItAgainRewrites {

    /** `alternative` null = asked, and the line needed nothing. Remembered so
     *  a clean turn is not asked again on every open. */
    @Serializable
    data class Entry(val alternative: String? = null, val reason: String = "")

    /** Lines in flight at once. Enough that a 20-turn talk is ready before
     *  the first answer finishes playing; few enough not to look like a burst. */
    const val CONCURRENCY = 4

    private val serializer = MapSerializer(String.serializer(), Entry.serializer())
    private var entries: MutableMap<String, Entry>? = null

    private fun file(c: Context) = File(c.filesDir, "say_again_rewrites.json")

    @Synchronized
    private fun map(c: Context): MutableMap<String, Entry> = entries ?: runCatching {
        file(c).takeIf { it.exists() }?.readText()?.let { StoreJson.json.decodeFromString(serializer, it) }
    }.getOrNull().orEmpty().let { LinkedHashMap(it) }.also { entries = it }

    @Synchronized
    fun all(c: Context): Map<String, Entry> = HashMap(map(c))

    /** Learner turns the script would read as said because the call left no
     *  whole-turn rewrite, and that haven't been asked about here yet. */
    @Synchronized
    fun missing(c: Context, session: Session): List<String> {
        val known = map(c)
        val language = session.targetLanguage
        return session.turns.mapNotNull { turn ->
            if (turn.role != TurnRole.USER || turn.excludedFromScoring || known.containsKey(turn.id)) {
                return@mapNotNull null
            }
            val said = turn.transcript.trim()
            // The live path's own floor: a two-word answer has nothing to re-say.
            if (WordSplitter.count(said, language) < 3) return@mapNotNull null
            val rewrite = turn.suggestion?.alternative.orEmpty().trim()
            if (rewrite.isNotEmpty() && SayItAgainScript.coversWholeTurn(rewrite, said, language,
                    fromWholeTurnContract = turn.suggestion?.fixes != null)) return@mapNotNull null
            turn.id
        }
    }

    /**
     * Ask for every missing turn and remember the answers. Returns once all
     * have landed or failed; a failed one stays missing and is asked again on
     * the next open.
     */
    suspend fun fill(c: Context, session: Session, nativeLanguage: String, level: CefrLevel) {
        val ids = missing(c, session).toSet()
        if (ids.isEmpty()) return
        data class Job(val id: String, val said: String, val heard: String)
        val jobs = ArrayList<Job>()
        var lastHeard = ""
        for (turn in session.turns) {
            val text = turn.transcript.trim()
            if (turn.role == TurnRole.FLUENT_SELF) { lastHeard = text; continue }
            if (turn.id in ids) jobs.add(Job(turn.id, text, lastHeard))
        }
        val person = session.counterpartId?.let { id ->
            runCatching { CounterpartStore.shared(c).load().firstOrNull { it.id == id } }.getOrNull()
        }
        val target = session.targetLanguage
        val inScene = session.originScenarioId != null
        val system = CorrectionOnlyPrompt.build(target, nativeLanguage, level,
            relationshipLine = ConversationCharacter.relationshipRegisterLine(target, person),
            politeLine = ConversationCharacter.politeSettingLine(target, person, inScene = inScene))

        val gate = Semaphore(CONCURRENCY)
        val results = coroutineScope {
            jobs.map { job ->
                async { job.id to gate.withPermit { ask(system, job.said, job.heard, job.id, target) } }
            }.awaitAll()
        }
        var failed = 0
        var filled = 0
        synchronized(this) {
            val m = map(c)
            for ((id, entry) in results) {
                if (entry == null) { failed += 1; continue }
                m[id] = entry
                if (entry.alternative != null) filled += 1
            }
        }
        save(c)
        com.roro.futurevoice.core.Telemetry.log("say_again_fill", mapOf(
            "asked" to jobs.size.toString(),
            "filled" to filled.toString(),
            "failed" to failed.toString(),
        ))
    }

    /** One turn, through the same gate the live call's answer goes through
     *  (`turnSuggestion`): a fix that isn't theirs or a rewrite that changes
     *  nothing audible never reaches the prompter. Null = the call failed. */
    private suspend fun ask(system: String, said: String, heard: String, turnId: String,
                            language: String): Entry? {
        val content = if (heard.isEmpty()) "They said: \"$said\""
            else "They were just told: \"$heard\"\nThey said: \"$said\""
        return try {
            val payload = GeminiClient(AuthRepository()).sendJson(
                system = system,
                messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, content)),
                serializer = ConversationTurnPayload.serializer(),
                maxTokens = 2048, purpose = "turn",
                idempotencyKey = "say-again-fill:$turnId",
            )
            val s = payload.turnSuggestion(said, language) ?: return Entry(null, "")
            Entry(s.alternative, s.reason)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun save(c: Context) {
        val snapshot = synchronized(this) {
            val m = map(c)
            // Bounded: one entry per learner turn ever reviewed this way, and
            // an entry is only needed while its talk is still being re-run.
            if (m.size > 4000) {
                val keep = m.entries.toList().takeLast(3000)
                m.clear(); keep.forEach { (k, v) -> m[k] = v }
            }
            HashMap(m)
        }
        withContext(Dispatchers.IO) {
            runCatching {
                val target = file(c)
                val tmp = File(target.parentFile, target.name + ".tmp")
                tmp.writeText(StoreJson.json.encodeToString(serializer, snapshot))
                if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
            }
        }
    }
}
