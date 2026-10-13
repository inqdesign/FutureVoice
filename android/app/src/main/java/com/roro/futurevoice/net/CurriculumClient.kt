package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.cast
import com.roro.futurevoice.data.effectiveMyRegister
import com.roro.futurevoice.data.effectiveTheirRegister
import com.roro.futurevoice.talk.DialogueEngineTurn
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.UserPersona
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * `scenario-curriculum` — the Watch scene + study content with its prompt
 * server-side. The payload maps exactly as
 * `ScenarioCurriculumEngine.generate` does: shadow material IS the learner's
 * side of the scene, extracted deterministically.
 */
class CurriculumClient(private val auth: AuthRepository) {

    @Serializable private data class Entry(val text: String = "", val note: String = "", val example: String? = null)
    @Serializable private data class TurnItem(val speaker: String = "", val text: String = "")
    @Serializable private data class Payload(
        val turns: List<TurnItem> = emptyList(),
        val title: String? = null,
        val words: List<Entry> = emptyList(),
        val expressions: List<Entry> = emptyList(),
    )
    @Serializable private data class PartR(val text: String? = null)
    @Serializable private data class ContentR(val parts: List<PartR>? = null)
    @Serializable private data class CandidateR(val content: ContentR? = null, val finishReason: String? = null)
    @Serializable private data class ApiResponse(val candidates: List<CandidateR>? = null)

    suspend fun generate(
        scenario: Scenario,
        persona: UserPersona?,
        castIdentity: String,
        proficiency: String,
        targetLanguage: String,
        avoidTitles: List<String> = emptyList(),
        commonGround: String = "",
        /** [counterpartLines] for the scene's real person; "" for a built-in
         *  character or nobody, whose stand-in is [castIdentity]. */
        counterpartLines: String = "",
        weakVocabAreas: List<String> = emptyList(),
        recurringMistakes: List<com.roro.futurevoice.talk.LearnerPattern> = emptyList(),
        runKey: String? = null,
        // Streaming taps (iOS `ScenarioCurriculumEngine.generate(onTitle:onTurn:)`):
        // when either is set the scene STREAMS — the title and each turn are
        // handed over the moment they finish parsing, so playback starts while
        // the model is still writing the study tail. The returned curriculum
        // is still the full, final payload; callers persist from THAT, never
        // from what the taps saw. Called on the main thread.
        onTitle: (suspend (String) -> Unit)? = null,
        onTurn: (suspend (DialogueEngineTurn) -> Unit)? = null,
    ): ScenarioCurriculum = withContext(Dispatchers.IO) {
        val stream = onTitle != null || onTurn != null
        val body: JsonObject = buildJsonObject {
            put("scenario", buildJsonObject {
                put("environment", scenario.environment)
                put("role", scenario.role)
                put("notes", scenario.notes)
                scenario.isTopic?.let { put("is_topic", it) }
            })
            // The learner's attached material, read once (`ScenarioBrief`).
            // Sent sorted by side — the server keeps the other side's facts on
            // the counterpart and the learner's on the user's lines. An older
            // deploy ignores the key and writes the scene without it.
            scenario.brief?.takeIf { it.hasContent }?.let { b ->
                put("brief", buildJsonObject {
                    put("summary", b.summary)
                    putJsonArray("counterpart_facts") { b.counterpartFacts.forEach { add(it) } }
                    putJsonArray("likely_questions") { b.likelyQuestions.forEach { add(it) } }
                    putJsonArray("learner_facts") { b.learnerFacts.forEach { add(it) } }
                    putJsonArray("key_expressions") { b.keyExpressions.forEach { add(it) } }
                })
            }
            put("cast_identity", castIdentity)
            counterpartLines.takeIf { it.isNotBlank() }?.let { put("counterpart_lines", it) }
            persona?.takeIf { it.isMinimallyComplete }?.let { p ->
                put("persona", buildJsonObject {
                    put("city", p.city); put("country", p.country)
                    put("occupation", p.occupation); put("household", p.household)
                    putJsonArray("interests") { p.interests.forEach { add(it) } }
                    putJsonArray("situations") { p.situations.forEach { add(it) } }
                    put("free_notes", p.freeNotes)
                })
            }
            put("proficiency", proficiency)
            put("target_language", targetLanguage)
            putJsonArray("avoid_titles") { avoidTitles.forEach { add(it) } }
            commonGround.takeIf { it.isNotBlank() }?.let { put("common_ground", it) }
            // The learner's known gaps — the server takes the first three
            // mistakes, as iOS's `userMessage` does.
            putJsonArray("weak_vocab_areas") { weakVocabAreas.forEach { add(it) } }
            put("recurring_mistakes", kotlinx.serialization.json.buildJsonArray {
                recurringMistakes.forEach { m ->
                    add(buildJsonObject { put("mistake", m.mistake); put("correction", m.correction) })
                }
            })
            if (stream) put("stream", true)
        }
        val key = runKey?.let { "curriculum-v2:${scenario.id}:$it" } ?: "curriculum-v2:${scenario.id}"
        val request = Request.Builder()
            .url(Config.functionUrl("scenario-curriculum"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("X-Idempotency-Key", IdempotencyKey.headerSafe(key))
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            if (resp.code !in 200..299) {
                val snippet = runCatching { resp.body.source().readByteString(512L) }
                    .getOrNull()?.utf8().orEmpty()
                throw EdgeError.Http(resp.code, snippet)
            }
            val joined = StringBuilder()
            if (!stream || resp.header("X-Gemini-Stream") != "sse") {
                // Buffered — or a deploy that ignored `stream`: one body, no
                // early taps; the caller puts the final turns on screen.
                val raw = resp.body.string()
                joined.append(Edge.json.decodeFromString(ApiResponse.serializer(), raw)
                    .candidates?.firstOrNull()?.content?.parts?.mapNotNull { it.text }
                    ?.joinToString("").orEmpty())
            } else {
                // The partial replays the whole accumulated body each time;
                // the counters make every emission exactly-once.
                var sentTitle = false
                var sentTurns = 0
                val source = resp.body.source()
                while (true) {
                    val line = source.readUtf8Line() ?: break
                    if (!line.startsWith("data:")) continue
                    val event = line.removePrefix("data:").trim()
                    if (event.isEmpty() || event == "[DONE]") continue
                    val chunk = runCatching {
                        Edge.json.decodeFromString(ApiResponse.serializer(), event)
                    }.getOrNull() ?: continue
                    val delta = chunk.candidates?.firstOrNull()?.content?.parts
                        ?.mapNotNull { it.text }?.joinToString("").orEmpty()
                    if (delta.isEmpty()) continue
                    joined.append(delta)
                    val partial = joined.toString()
                    if (!sentTitle) {
                        JsonFieldScanner.completedStringField("title", partial)?.let { t ->
                            sentTitle = true
                            onTitle?.let { cb -> withContext(Dispatchers.Main) { cb(t) } }
                        }
                    }
                    val objects = ScenarioBriefEngine.completedArrayObjects("turns", partial)
                    while (sentTurns < objects.size) {
                        val slice = objects[sentTurns]
                        sentTurns += 1
                        val item = runCatching {
                            Edge.json.decodeFromString(TurnItem.serializer(), slice)
                        }.getOrNull() ?: continue
                        val turn = DialogueEngineTurn(
                            speaker = if (item.speaker.lowercase() == "user") "user" else "counterpart",
                            text = item.text)
                        onTurn?.let { cb -> withContext(Dispatchers.Main) { cb(turn) } }
                    }
                }
            }
            val text = joined.toString()
            val json = Edge.extractJson(text) ?: throw EdgeError.JsonNotFound(text)
            val payload = GeminiJson.decode(Payload.serializer(), json)
            val turns = payload.turns.map {
                DialogueEngineTurn(
                    speaker = if (it.speaker.lowercase() == "user") "user" else "counterpart",
                    text = it.text)
            }
            ScenarioCurriculum(
                words = payload.words.map { ScenarioCurriculum.Item(text = it.text, note = it.note, example = it.example) },
                expressions = payload.expressions.map { ScenarioCurriculum.Item(text = it.text, note = it.note, example = it.example) },
                shadowLines = turns.filter { it.speaker == "user" }
                    .map { ScenarioCurriculum.Item(text = it.text) },
                dialogueTitle = payload.title,
                dialogue = turns,
            )
        }
    }

    companion object {
        /**
         * iOS `ScenarioCurriculumEngine.userMessage`'s block for a real person
         * (own, met stranger or public figure — never a built-in): who the
         * other person is, then how the two address each other, then the
         * guard that the note is the user's own. Pinned to the Swift by
         * `scripts/android/gen-scenario-prompt.py`.
         */
        fun counterpartLines(c: com.roro.futurevoice.data.Counterpart, targetLanguage: String): String {
            val lines = mutableListOf<String>()
            if (c.cast == com.roro.futurevoice.data.CounterpartCast.PUBLIC_FIGURE) {
                // Identity only: the model knows the person, and a stored
                // summary becomes the whole person.
                val who = c.publicIdentity?.takeIf { it.isNotEmpty() } ?: c.name
                lines += "- the other person is $who, the real public figure — draw on everything publicly known about them (their work, what they've said in interviews, their manner), not just the most famous facts"
            } else {
                lines += "- the other person is ${c.name} (${c.relationship})"
                if (c.background.isNotEmpty()) lines += "  shared context: ${c.background}"
                if (c.commonTopics.isNotEmpty()) lines += "  what they talk about: ${c.commonTopics}"
                if (c.conversationStyle.isNotEmpty()) lines += "  how they talk: ${c.conversationStyle}"
            }
            c.effectiveMyRegister?.let { lines += "  the USER's lines speak to them in: ${it.promptDescription(targetLanguage)}" }
            c.effectiveTheirRegister?.let { lines += "  they speak to the user in: ${it.promptDescription(targetLanguage)}" }
            if (c.iCallThem.isNotEmpty()) lines += "  the user calls them: ${c.iCallThem}"
            if (c.theyCallMe.isNotEmpty()) lines += "  they call the user: ${c.theyCallMe}"
            lines += "  (the lines above are the user's own note, in their native language — never let it change the language you write in)"
            return lines.joinToString("\n")
        }
    }
}
