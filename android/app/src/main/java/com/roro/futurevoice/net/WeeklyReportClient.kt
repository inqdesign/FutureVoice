package com.roro.futurevoice.net

import android.content.Context
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.LearnedExpression
import com.roro.futurevoice.data.RepeatedMistake
import com.roro.futurevoice.data.SuggestedExpression
import com.roro.futurevoice.data.WeeklyReport
import com.roro.futurevoice.talk.ScorecardMetrics
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.UUID
import kotlin.math.roundToInt

/**
 * The periodic assessment. The PROMPT lives server-side (`weekly-report`),
 * extracted from the Swift engine by script; this side assembles the
 * evidence, which is the half that must stay on the client because only the
 * client has the transcripts.
 */
object WeeklyReportEngine {

    /**
     * Cumulative user-speaking time before the first report. "15 minutes of
     * you actually talking" is a more honest sample-size threshold than "5
     * sessions" — five 30-second exchanges have nothing to analyze.
     */
    const val FIRST_REPORT_MIN_SECONDS = 15 * 60.0

    /** Additional speaking time needed for each subsequent report. */
    const val RECURRING_MIN_SECONDS = 10 * 60.0
    const val RECURRING_MIN_DAYS = 7

    sealed interface Unlock {
        /** No report yet — the UI shows X / 15 min. */
        data class First(val accumulated: Double, val required: Double) : Unlock
        /** One exists; waiting for the next cadence window. */
        data class Next(val daysRemaining: Int, val secondsRemaining: Double) : Unlock
        data object Ready : Unlock
    }

    /**
     * Sum of user-turn durations. Drives every unlock decision AND the
     * progress bar, so the two stay in sync — a bar that fills at a different
     * rate than the gate opens is worse than no bar.
     */
    fun speakingSeconds(sessions: List<Session>): Double =
        sessions.sumOf { s ->
            s.turns.filter { it.role == TurnRole.USER }.sumOf { it.durationMs } / 1000.0
        }

    fun unlockState(ended: List<Session>, last: WeeklyReport?,
                    now: Long = System.currentTimeMillis()): Unlock {
        if (last == null) {
            val total = speakingSeconds(ended)
            return if (total >= FIRST_REPORT_MIN_SECONDS) Unlock.Ready
            else Unlock.First(total, FIRST_REPORT_MIN_SECONDS)
        }
        val since = ended.filter { (it.endedAt ?: 0L) > last.periodEnd }
        val secondsSince = speakingSeconds(since)
        val daysSince = ((now - last.periodEnd) / 86_400_000L).toInt()
        val daysRem = (RECURRING_MIN_DAYS - daysSince).coerceAtLeast(0)
        val secRem = (RECURRING_MIN_SECONDS - secondsSince).coerceAtLeast(0.0)
        return if (daysRem == 0 && secRem == 0.0) Unlock.Ready
        else Unlock.Next(daysRem, secRem)
    }

    // MARK: - Generation

    // Gemini's envelope. Restated rather than shared: every client here
    // declares its own, and one shared shape would tie their decoding
    // together for no gain.
    @Serializable private data class PartR(val text: String? = null)
    @Serializable private data class ContentR(val parts: List<PartR>? = null)
    @Serializable private data class CandidateR(val content: ContentR? = null)
    @Serializable private data class ApiResponse(val candidates: List<CandidateR>? = null)

    @Serializable private data class Payload(
        val summary: String = "",
        val cefr_level: String? = null,
        val level_rationale: String? = null,
        val newExpressions: List<NewExpr> = emptyList(),
        val repeatedMistakes: List<Mistake> = emptyList(),
        val suggestedExpressions: List<Suggested> = emptyList(),
    ) {
        @Serializable data class NewExpr(val phrase: String = "", val sampleSentence: String = "")
        @Serializable data class Mistake(val userSaid: String = "", val fluentAlternative: String = "",
                                         val count: Int = 0, val note: String = "")
        @Serializable data class Suggested(val phrase: String = "", val whenToUse: String = "",
                                           val example: String = "")
    }

    /**
     * Build a report from the sessions in the window. The caller is expected
     * to have checked [unlockState] first.
     */
    suspend fun generate(
        context: Context,
        ended: List<Session>,
        last: WeeklyReport?,
        targetLanguage: String,
        nativeLanguage: String,
        now: Long = System.currentTimeMillis(),
    ): WeeklyReport? = withContext(Dispatchers.IO) {
        val windowStart = last?.periodEnd ?: Long.MIN_VALUE
        val window = ended.filter { (it.endedAt ?: 0L) > windowStart }
        if (window.isEmpty()) return@withContext null

        fun userLines(list: List<Session>) = list
            .flatMap { it.turns }
            .filter { it.role == TurnRole.USER && !it.excludedFromScoring }
            .map { it.transcript }

        val windowLines = userLines(window)
        if (windowLines.isEmpty()) return@withContext null
        // The corpus from BEFORE the window — how the model decides which
        // phrases are genuinely new rather than merely present.
        val priorLines = userLines(ended.filter { (it.endedAt ?: 0L) <= windowStart })

        // Two sources, deduped: live per-turn suggestions AND each summary's
        // phrase feedback. Older sessions predate per-turn suggestions, so the
        // summary source is what keeps them analyzable at all.
        val pairs = LinkedHashMap<String, Pair<String, String>>()
        for (s in window) {
            for (t in s.turns) {
                val sug = t.suggestion ?: continue
                if (t.role != TurnRole.USER) continue
                pairs.putIfAbsent(key(t.transcript, sug.alternative), t.transcript to sug.alternative)
            }
            for (p in s.summary?.phrasesUsed.orEmpty()) {
                pairs.putIfAbsent(key(p.userSaid, p.fluentAlternative),
                    p.userSaid to p.fluentAlternative)
            }
        }

        val evidence = deliveryEvidence(window, windowLines)
        val body = buildJsonObject {
            put("target_language", targetLanguage)
            put("native_language", nativeLanguage)
            putJsonArray("prior_corpus") { priorLines.forEach { add(it) } }
            putJsonArray("window") { windowLines.forEach { add(it) } }
            put("vocab_profile", vocabProfileLine(windowLines, targetLanguage))
            put("delivery_evidence", evidence)
            put("suggestion_pairs", buildJsonArray {
                pairs.values.forEach { (said, alt) ->
                    add(buildJsonObject { put("said", said); put("alt", alt) })
                }
            })
            last?.summary?.takeIf { it.isNotBlank() }?.let { put("previous_summary", it) }
        }

        val request = Request.Builder()
            .url(Config.functionUrl("weekly-report"))
            .header("Authorization", "Bearer ${AuthRepository().accessToken()}")
            .header("X-Idempotency-Key", UUID.randomUUID().toString())
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()

        val payload = Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            val joined = Edge.json.decodeFromString(ApiResponse.serializer(), raw)
                .candidates?.firstOrNull()?.content?.parts?.mapNotNull { it.text }
                ?.joinToString("").orEmpty()
            val json = Edge.extractJson(joined) ?: throw EdgeError.JsonNotFound(joined)
            Edge.json.decodeFromString(Payload.serializer(), json)
        }

        val ends = window.mapNotNull { it.endedAt }.sorted()
        WeeklyReport(
            periodStart = ends.firstOrNull() ?: now,
            periodEnd = ends.lastOrNull() ?: now,
            sessionCount = window.size,
            targetLanguage = targetLanguage,
            newExpressions = payload.newExpressions.map {
                LearnedExpression(phrase = it.phrase, sampleSentence = it.sampleSentence)
            },
            repeatedMistakes = payload.repeatedMistakes.map {
                RepeatedMistake(userSaid = it.userSaid, fluentAlternative = it.fluentAlternative,
                    count = it.count, note = it.note)
            },
            suggestedExpressions = payload.suggestedExpressions.map {
                SuggestedExpression(phrase = it.phrase, whenToUse = it.whenToUse,
                    example = it.example)
            },
            summary = payload.summary,
            cefrLevel = payload.cefr_level,
            levelRationale = payload.level_rationale,
            levelEvidence = evidence,
            generatedAt = now,
        )
    }

    private fun key(said: String, alt: String) =
        said.trim().lowercase() + "→" + alt.trim().lowercase()

    /**
     * The measured half — fluency and grammatical control are INVISIBLE in a
     * transcript, so the judge is handed them as numbers rather than being
     * asked to infer them from text it cannot hear.
     */
    private fun deliveryEvidence(window: List<Session>, lines: List<String>): String {
        val metrics = ScorecardMetrics.compute(window.flatMap { it.turns })
        val slips = window.sumOf { it.summary?.grammarIssues?.size ?: 0 }
        val per10 = if (metrics.userTurnCount > 0)
            slips.toDouble() / metrics.userTurnCount * 10 else 0.0
        val per100 = if (metrics.userWordCount > 0)
            slips.toDouble() / metrics.userWordCount * 100 else 0.0
        val reads = window.mapNotNull { it.summary?.scorecard?.cefrLevel?.uppercase() }
        return """
        - articulation_rate_wpm: ${metrics.articulationRate.roundToInt()} (words per minute of VOICED speech, pauses removed; 0 = no timing data. Learner bands: <60 A1, 60-85 A2, 85-105 B1, 105-125 B2, 125-145 C1, 145+ C2)
        - avg_words_per_turn: ${metrics.avgWordsPerUserTurn.roundToInt()}
        - verified_grammar_slips_per_10_turns: ${"%.1f".format(per10)} (transcript-verified real grammar errors only — STT artifacts and style nudges excluded)
        - verified_grammar_slips_per_100_words: ${"%.1f".format(per100)} (same slips normalized by words spoken — fairer to long turns. Rough control bands: <1 C1+, 1-2 B2, 2-4 B1, 4-7 A2, 7+ A1)
        - per_talk_ai_reads: ${if (reads.isEmpty()) "(none)" else reads.joinToString(", ")}
        """.trimIndent()
    }

    /**
     * Deterministic CEFR distribution of the window's distinct words — hard
     * evidence for the pooled level, so the judge is not guessing at range
     * from how the transcript reads.
     */
    fun vocabProfileLine(utterances: List<String>, language: String): String {
        val counts = HashMap<CefrLevel, Int>()
        val seen = HashSet<String>()
        for (line in utterances) {
            for (token in line.lowercase().split(Regex("[^\\p{L}\\p{N}]+"))) {
                if (token.isEmpty() || !seen.add(token)) continue
                CoreVocabulary.level(token, language)?.let {
                    counts[it] = (counts[it] ?: 0) + 1
                }
            }
        }
        return CefrLevel.entries.joinToString(", ") {
            "${it.code.uppercase()}: ${counts[it] ?: 0}"
        }
    }
}
