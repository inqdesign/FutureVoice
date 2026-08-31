package com.roro.futurevoice.talk

import android.content.Context
import android.util.Log
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.ProfileStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.SessionSummaryClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * Turning a finished talk into its review material — the Android twin of
 * `SessionSummarizer.swift`, in stages. What is here now: the model call
 * (server-side prompt), a LENIENT decode (an element the model got wrong is
 * skipped, never the whole list), the two verbatim guards (expressions the
 * learner "used" must appear in their own turns, "offered" ones in the
 * fluent self's and not the learner's; grammar quotes likewise, and a fix
 * that only changes punctuation/casing is dropped), the generated title
 * becoming a free talk's topic, and the save. Still to port, with vectors:
 * VocabStore ingest, DrillStore minting, CarryoverDetector, LearnerProfile
 * absorb, persona notes (`about_user` is decoded and kept on the result for
 * that day).
 *
 * Runs on an app-lifetime scope: the call screen is gone by the time the
 * model answers.
 */
object SessionSummarizer {

    private const val TAG = "SessionSummarizer"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** Session ids being analyzed right now — what a "Working…" button reads. */
    private val _inFlight = MutableStateFlow<Set<String>>(emptySet())
    val inFlight: StateFlow<Set<String>> = _inFlight

    data class Progress(
        val readBack: Boolean = false,
        val wroteCorrections: Boolean = false,
        val wroteDrills: Boolean = false,
        val wroteExpressions: Boolean = false,
        val wroteGrammar: Boolean = false,
        val finished: Boolean = false,
    ) {
        /** Same key-order reading as `Progress.absorb(partial:)` on iOS. */
        fun absorb(partial: String) = copy(
            readBack = readBack || partial.contains("\"phrases_used\""),
            wroteCorrections = wroteCorrections || partial.contains("\"new_patterns_detected\""),
            wroteDrills = wroteDrills || partial.contains("\"expressions_used\""),
            wroteExpressions = wroteExpressions || partial.contains("\"weak_vocab_areas\""),
            wroteGrammar = wroteGrammar || partial.contains("\"overall_note\""),
        )
    }

    /** What a talk is allowed to yield follows how much was said in it. */
    fun expressionBudget(fluentTurns: Int): Int = minOf(14, maxOf(6, fluentTurns))

    fun needsSummary(session: Session): Boolean =
        session.summary == null && session.turns.any { it.role == TurnRole.USER }

    /** Fire-and-forget from the call screen; the store bumps when done. */
    fun summarizeInBackground(context: Context, session: Session, nativeLanguage: String, level: CefrLevel) {
        if (!needsSummary(session)) return
        if (session.id in _inFlight.value) return
        val appContext = context.applicationContext
        _inFlight.update { it + session.id }
        scope.launch {
            try {
                runCatching { summarize(appContext, session, nativeLanguage, level) }
                    .onFailure { Log.w(TAG, "summary failed for ${session.id}: ${it.message}") }
            } finally {
                _inFlight.update { it - session.id }
            }
        }
    }

    suspend fun summarize(
        context: Context,
        session: Session,
        nativeLanguage: String,
        level: CefrLevel,
        onProgress: ((Progress) -> Unit)? = null,
    ): Session {
        val turns = session.turns
        val auth = AuthRepository()
        val client = SessionSummaryClient(auth)
        val metrics = ScorecardMetrics.compute(turns)
        var progress = Progress()

        // The REAL learner profile (what past sessions taught) — read before
        // the call, absorbed after it, exactly iOS's order.
        val profileStore = ProfileStore.shared(context)
        val profile = profileStore.load(session.targetLanguage, level.code)
        val body = SessionSummaryClient.RequestBody(
            target_language = session.targetLanguage,
            native_language = nativeLanguage,
            profile = Json.parseToJsonElement(
                StoreJson.json.encodeToString(LearnerProfile.serializer(), profile)).jsonObject,
            known_about_user = emptyList(),
            expression_budget = expressionBudget(turns.count { it.role == TurnRole.FLUENT_SELF }),
            transcript = formatTranscript(turns),
            metrics = metrics.promptJson(),
        )
        // Stable key: a retry re-runs the SAME logical request for free as
        // long as the transcript hasn't grown (iOS: "summary:<id>:<turns>").
        val key = "summary:${session.id}:${turns.size}"
        // The model occasionally writes a shape we can't read — most often a
        // native-language note carrying unescaped ASCII quotes (「"going"」).
        // The learner did nothing wrong: ask ONCE more before making the end
        // of a talk look like a failure. Free — the ledger dedupes on the key.
        // (iOS: the `isMalformedModelOutput` retry in SessionSummarizer.)
        fun parse(text: String): JsonObject = Json.parseToJsonElement(text).jsonObject
        val payload = try {
            parse(client.summarize(body, key) { partial ->
                progress = progress.absorb(partial); onProgress?.invoke(progress)
            })
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "summary payload unreadable (${e.message?.take(80)}) — retrying once")
            parse(client.summarize(body, key))
        }
        var computed = toDomain(payload)

        // Verbatim guards — the same normalization CarryoverDetector uses.
        val userTexts = turns.filter { it.role == TurnRole.USER }.map { it.transcript }
        val haystack = normalized(userTexts.joinToString(" "))
        val verifiedUsed = computed.expressionsUsed.filter { p ->
            val n = normalized(p); n.isNotEmpty() && haystack.contains(n)
        }
        val fluentHaystack = normalized(
            turns.filter { it.role == TurnRole.FLUENT_SELF }.joinToString(" ") { it.transcript })
        val alreadyMine = verifiedUsed.map(::normalized).toSet()
        val seenOffered = HashSet<String>()
        val verifiedOffered = computed.expressionsOffered.filter { p ->
            val n = normalized(p)
            n.isNotEmpty() && n !in alreadyMine && !haystack.contains(n) &&
                fluentHaystack.contains(n) && seenOffered.add(n)
        }
        val priorUsed = session.summary?.expressionsUsed.orEmpty()
        val priorOffered = session.summary?.expressionsOffered.orEmpty()
        val grammar = computed.grammarIssues.filter { g ->
            val needle = normalized(g.quote)
            needle.isNotEmpty() && haystack.contains(needle) && needle != normalized(g.correction)
        }
        computed = computed.copy(
            expressionsUsed = priorUsed + verifiedUsed.filter { it !in priorUsed },
            expressionsOffered = priorOffered + verifiedOffered.filter { it !in priorOffered },
            grammarIssues = grammar,
        )

        // ── The loop closes (`SessionSummarizer.swift`, in stages) ──
        val language = session.targetLanguage
        val vocab = VocabStore.shared(context)
        val drills = DrillStore.shared(context)

        // Words into the long-term pool; merge with the previous summary's
        // list so a resumed talk can't erase "words you used first".
        val freshWords = vocab.ingest(session.id, userTexts, language)
        val priorWords = session.summary?.newWordsUsed.orEmpty()
        // Expressions: seed pre-tracking sessions, then count this batch.
        vocab.notePriorExpressions(session.id, priorUsed, language)
        vocab.ingestExpressions(session.id, verifiedUsed, language)

        // Carryovers run against the cards as they stood BEFORE this
        // session's own corrections are ingested below.
        val carryovers = CarryoverDetector.detect(
            turns = turns,
            cards = drills.load(language),
            studyingExpressions = vocab.studyingExpressions(language),
            studyingWords = vocab.studying(language),
            sessionId = session.id, sessionStartedAt = session.startedAt,
            language = language,
        )
        computed = computed.copy(
            newWordsUsed = priorWords + freshWords.filter { it !in priorWords },
            carryovers = carryovers,
        )

        // A free talk takes the generated title so lists don't fill with "Conversation".
        val generatedTitle = payload["title"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
        val existingTopic = session.topic?.trim().orEmpty()
        val resolvedTopic = existingTopic.ifEmpty { generatedTitle }.ifEmpty { null }

        val saved = session.copy(topic = resolvedTopic, summary = computed)
        SessionStore.shared(context).save(saved)

        // Cards: clear this session's untouched ones (a re-analysis must not
        // reset Leitner progress), mint, then credit live production.
        drills.clearUnreviewedCards(session.id, language)
        val minted = DrillIngest.mint(drills.load(language), computed, turns, session.id,
            System.currentTimeMillis())
        drills.upsertMany(minted, language)
        drills.markUsedInConversation(
            carryovers.filter { it.source == Carryover.Source.DRILL_CARD }.mapNotNull { it.sourceId },
            language)

        // Grow the long-term profile — the next conversation's prompt reads it.
        val speakingSeconds = turns.filter { it.role == TurnRole.USER }
            .sumOf { it.durationMs / 1000.0 }
        profile.absorb(computed, speakingSeconds)
        profileStore.save(profile)

        StoreEvents.bump()
        progress = progress.copy(finished = true); onProgress?.invoke(progress)
        return saved
    }

    /** `ConversationEngine.formatTranscript` — role-labelled lines. */
    fun formatTranscript(turns: List<Turn>): String =
        turns.joinToString("\n") { t ->
            "[${if (t.role == TurnRole.USER) "USER" else "FLUENT_SELF"}] ${t.transcript}"
        }

    /** `CarryoverDetector.normalized`: letters/digits/spaces only, lowercase, single-spaced. */
    fun normalized(text: String): String =
        text.filter { it.isLetterOrDigit() || it.isWhitespace() }
            .lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

    // ── Lenient decode (`ClaudeSummaryPayload.lossyArray` + `toDomain`) ──

    private fun str(o: JsonObject, k: String): String? =
        (o[k] as? JsonElement)?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }

    private fun strings(o: JsonObject, k: String): List<String> =
        (o[k] as? JsonArray)?.mapNotNull { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }.orEmpty()

    private fun objects(o: JsonObject, k: String): List<JsonObject> =
        (o[k] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

    private fun toDomain(p: JsonObject): SessionSummary {
        val now = System.currentTimeMillis()
        val scorecard = (p["scorecard"] as? JsonObject)?.let { sc ->
            fun axis(k: String): AxisScore? {
                val a = sc[k] as? JsonObject ?: return null
                val score = a["score"]?.jsonPrimitive?.intOrNull ?: return null
                return AxisScore(score.coerceIn(0, 100), str(a, "note").orEmpty())
            }
            val v = axis("vocabulary"); val g = axis("grammar"); val e = axis("expressiveness")
            val fRaw = (sc["fluency"] as? JsonObject)?.get("score")?.jsonPrimitive?.intOrNull
            if (v == null || g == null || e == null || fRaw == null) null
            else SessionScorecard(
                vocabulary = v, grammar = g, expressiveness = e,
                // -1 signals "no timing data" — clamp and say so, as iOS does.
                fluency = if (fRaw < 0) AxisScore(0, "Speak a bit more next session for a fluency read.")
                else axis("fluency")!!,
                topLine = str(sc, "top_line").orEmpty(),
                cefrLevel = str(sc, "cefr_level")?.lowercase(),
            )
        }
        return SessionSummary(
            phrasesUsed = objects(p, "phrases_used").mapNotNull { o ->
                val said = str(o, "user_said") ?: return@mapNotNull null
                val alt = str(o, "fluent_alternative") ?: return@mapNotNull null
                PhraseFeedback(userSaid = said, fluentAlternative = alt, reason = str(o, "reason").orEmpty())
            },
            newPatternsDetected = objects(p, "new_patterns_detected").mapNotNull { o ->
                val m = str(o, "mistake") ?: return@mapNotNull null
                val c = str(o, "correction") ?: return@mapNotNull null
                val freq = when (str(o, "frequency_hint")?.lowercase()) { "often" -> 5; "sometimes" -> 2; else -> 1 }
                LearnerPattern(mistake = m, correction = c, context = str(o, "context").orEmpty(),
                    frequency = freq, lastSeenAt = now)
            },
            suggestedDrills = strings(p, "suggested_drills"),
            overallNote = str(p, "overall_note").orEmpty(),
            scorecard = scorecard,
            expressionsUsed = strings(p, "expressions_used"),
            expressionsOffered = strings(p, "expressions_offered"),
            weakVocabAreas = strings(p, "weak_vocab_areas"),
            grammarIssues = objects(p, "grammar_errors").mapNotNull { o ->
                val q = str(o, "quote")?.trim().orEmpty(); val c = str(o, "correction")?.trim().orEmpty()
                if (q.isEmpty() || c.isEmpty()) null else GrammarIssue(quote = q, correction = c, note = str(o, "note").orEmpty())
            },
        )
    }
}
