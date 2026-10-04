package com.roro.futurevoice.talk

import android.content.Context
import android.util.Log
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.DailyCallStore
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.PersonaStore
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
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
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

    /**
     * Live board state per session — what the wrap-up draws. Entries appear
     * when an analysis starts and stay after it finishes (the board's last
     * frame), cleared on the next analysis of the same session.
     */
    private val _progressBySession = MutableStateFlow<Map<String, Progress>>(emptyMap())
    val progressBySession: StateFlow<Map<String, Progress>> = _progressBySession

    private fun publish(sessionId: String, p: Progress) {
        _progressBySession.update { it + (sessionId to p) }
    }

    data class Progress(
        val readBack: Boolean = false,
        val wroteCorrections: Boolean = false,
        val wroteDrills: Boolean = false,
        val wroteExpressions: Boolean = false,
        val wroteGrammar: Boolean = false,
        // Final counts, once the local pass has verified everything — the
        // same numbers the summary then shows. null = not done yet; a
        // finished step with 0 shows its tick alone.
        val phrases: Int? = null,
        val words: Int? = null,
        val offered: Int? = null,
        val corrections: Int? = null,
        val carryovers: Int? = null,
        val cards: Int? = null,
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
        _progressBySession.update { it + (session.id to Progress()) }
        scope.launch {
            try {
                runCatching {
                    summarize(appContext, session, nativeLanguage, level) { publish(session.id, it) }
                }.onFailure { e ->
                    Log.w(TAG, "summary failed for ${session.id}: ${e.message}")
                    if (e is kotlinx.coroutines.CancellationException) return@onFailure
                    // A failed summary costs the talk its ENTIRE review yield,
                    // so it gets the per-turn failure's visibility (iOS
                    // `talk_summary_error`) — with the HTTP status and the
                    // body's start, or a 429, a 503 and the gateway's own
                    // refusal all read the same (iOS `cd31a1a`).
                    com.roro.futurevoice.core.Telemetry.log("talk_summary_error", mapOf(
                        "error" to e::class.java.simpleName,
                        "detail" to failureDetail(e),
                        "turns" to session.turns.size.toString(),
                        "out_of_credits" to if (e is com.roro.futurevoice.net.EdgeError.InsufficientCredits) "1" else "0",
                    ))
                }
            } finally {
                _inFlight.update { it - session.id }
            }
        }
    }

    /** What a failure says beyond its class: `http 503 «…»` for an HTTP
     *  refusal, else the message — both cut to fit a telemetry row. */
    internal fun failureDetail(e: Throwable): String = when (e) {
        is com.roro.futurevoice.net.EdgeError.Http -> "http ${e.status} «${e.body.take(160)}»"
        else -> (e.message ?: "").take(240)
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
        // The notebook as the summary call sees it, in this order. A
        // `replaces` in the payload is a 1-based index into THIS list, so it
        // is captured once here and never re-read from the persona after the
        // call (iOS `rememberedNotes`). Expired `now` lines are not in it.
        val persona = PersonaStore.shared(context).load()
        val rememberedNotes = persona?.currentNotes().orEmpty()
        val body = requestBody(
            session = session,
            nativeLanguage = nativeLanguage,
            profile = Json.parseToJsonElement(
                StoreJson.json.encodeToString(LearnerProfile.serializer(), profile)).jsonObject,
            persona = persona,
            rememberedNotes = rememberedNotes,
            metrics = metrics.promptJson(),
            relationshipRegisterLine = session.counterpartId?.let { id ->
                com.roro.futurevoice.data.CounterpartStore.shared(context).load().firstOrNull { it.id == id }
            }.let { ConversationCharacter.relationshipRegisterLine(session.targetLanguage, it) },
        )
        // Stable key: a retry re-runs the SAME logical request for free as
        // long as the transcript hasn't grown (iOS: "summary:<id>:<turns>").
        val key = "summary:${session.id}:${turns.size}"
        // The model occasionally writes a shape we can't read — most often a
        // native-language note carrying unescaped ASCII quotes (「"going"」).
        // The learner did nothing wrong: ask ONCE more before making the end
        // of a talk look like a failure. Free — the ledger dedupes on the key.
        // (iOS: the `isMalformedModelOutput` retry in SessionSummarizer.)
        // Before that retry, the read itself repairs the reported shape — a
        // retry sends the same prompt and often gets the same slip (iOS
        // `decodeRepairing`, `55aa93a`).
        fun parse(text: String): JsonObject = com.roro.futurevoice.net.GeminiJson.parseObject(text)
        fun report(edit: (Progress) -> Progress) {
            progress = edit(progress); onProgress?.invoke(progress)
        }
        val payload = try {
            parse(client.summarize(body, key) { partial ->
                report { it.absorb(partial) }
            })
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "summary payload unreadable (${e.message?.take(80)}) — retrying once")
            parse(client.summarize(body, key))
        }
        var computed = toDomain(payload)
        report { it.copy(phrases = computed.phrasesUsed.count()) }

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

        // The three states, read BEFORE ingest graduates anything: the
        // wrap-up still has to be able to say it was a notebook word they
        // used, or a claim this call confirmed.
        // What they PRACTICED, not everything filed: a word a talk kept by
        // itself can't be "what you studied" in the wrap-up.
        val studyingWordsBefore = vocab.practicedStudying(language)
        val studyingExpressionsBefore = vocab.studyingExpressions(language)
        val claimedWords = vocab.unconfirmedKnownWords(language)
        val claimedExpressions = vocab.unconfirmedKnownExpressions(language)

        // A practice call (coach mode, `Session.coached`, iOS `6e9eb92`)
        // credits NOTHING as used: the learner answered with a suggested
        // sentence in front of them, and "used in a talk" is the strongest
        // state an item has — it takes a word out of the notebook and retires
        // a card. What they said there counts as practice instead (one
        // expression rep per studied item said, below).
        val practice = session.isPractice
        // Words into the long-term pool; merge with the previous summary's
        // list so a resumed talk can't erase "words you used first".
        val freshWords = if (practice) emptyList() else vocab.ingest(session.id, userTexts, language)
        report { it.copy(words = freshWords.size + verifiedUsed.size, offered = computed.expressionsOffered.size,
            corrections = computed.grammarIssues.size) }
        // The words the talk TAUGHT go into the notebook by themselves. They
        // used to sit in the book waiting to be tapped, so a word the whole
        // call was about entered review only if the learner went looking for
        // it. Exactly the set the book's word chapter shows — page and
        // notebook can never disagree about what a talk taught.
        vocab.keepFromTalk(
            vocab.pickupCandidates(
                turns.filter { it.role == TurnRole.FLUENT_SELF }.map { it.transcript },
                level, language, excludingLemmas = VocabLemmas.lemmas(userTexts))
                .take(TalkCurriculum.MAX_WORDS),
            language)

        val priorWords = session.summary?.newWordsUsed.orEmpty()
        // Expressions: seed pre-tracking sessions, then count this batch.
        if (!practice) {
            vocab.notePriorExpressions(session.id, priorUsed, language)
            vocab.ingestExpressions(session.id, verifiedUsed, language)
        }

        // Carryovers run against the cards as they stood BEFORE this
        // session's own corrections are ingested below.
        val carryovers = CarryoverDetector.detect(
            turns = turns,
            cards = drills.load(language),
            studyingExpressions = studyingExpressionsBefore,
            studyingWords = studyingWordsBefore,
            knownWords = claimedWords,
            knownExpressions = claimedExpressions,
            sessionId = session.id, sessionStartedAt = session.startedAt,
            language = language,
        )
        computed = computed.copy(
            newWordsUsed = priorWords + freshWords.filter { it !in priorWords },
            carryovers = carryovers,
        )
        report { it.copy(carryovers = carryovers.size) }
        // Practice: each studied item said is a rep, not a graduation. Only on
        // the first analysis — a regenerate must not count twice.
        if (practice && session.summary == null) {
            repeat(carryovers.size) {
                com.roro.futurevoice.data.PracticeLog.record(context, com.roro.futurevoice.data.PracticeLog.Kind.EXPRESSION)
            }
        }

        // A free talk takes the generated title so lists don't fill with "Conversation".
        val generatedTitle = payload["title"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
        val existingTopic = session.topic?.trim().orEmpty()
        val resolvedTopic = existingTopic.ifEmpty { generatedTitle }.ifEmpty { null }

        val saved = session.copy(topic = resolvedTopic, summary = computed)
        SessionStore.shared(context).save(saved)

        // The other memory: what the talk taught the fluent self about the
        // PERSON. Capped at 3 new lines a session — this is a notebook, not a
        // transcript. Each line carries the model's verdict on how much of it
        // a stranger may hear (`share`), the gist that rung hands out, the
        // reason, and the sentence it was distilled from; the learner
        // overturns the verdict in Me → Profile. A line naming a remembered
        // line's number is an UPDATE and takes its place instead of counting
        // against the three; a number that matches nothing is a new line.
        // `about_user` is the LAST field in the schema, so a response cut at
        // the token ceiling loses this and nothing else.
        val entries = aboutUser(payload)
            .map { it to it.text.trim() }
            .filter { (_, t) -> t.isNotEmpty() && t.length <= 140 }
        val updates = ArrayList<UserPersona.NoteUpdate>()
        val learned = ArrayList<PersonaNote>()
        for ((entry, text) in entries) {
            val note = entry.toNote(text, session.id)
            val n = entry.replaces
            if (n != null && n >= 1 && n <= rememberedNotes.size && updates.size < 3) {
                updates += UserPersona.NoteUpdate(rememberedNotes[n - 1].id, note)
            } else if (learned.size < 3) {
                learned += note
            }
        }
        // A plain free talk is where the fluent self gets to know someone;
        // stamping metAt here is what retires the first-call framing.
        val wasIntroTalk = session.counterpartId == null && existingTopic.isEmpty()
        if (learned.isNotEmpty() || updates.isNotEmpty() || wasIntroTalk) {
            com.roro.futurevoice.data.PersonaMemory.remember(
                context, learned,
                metAt = if (wasIntroTalk) (session.endedAt ?: System.currentTimeMillis()) else null,
                updates = updates)
        }

        // Cards: clear this session's untouched ones (a re-analysis must not
        // reset Leitner progress), mint, then credit live production.
        drills.clearUnreviewedCards(session.id, language)
        val minted = DrillIngest.mint(drills.load(language), computed, turns, session.id,
            System.currentTimeMillis(), language = language)
        drills.upsertMany(minted, language)
        // New cards have return times; something has to ring for them.
        com.roro.futurevoice.data.DrillReminder.reschedule(context)
        report { it.copy(cards = minted.size) }
        if (!practice) {
            drills.markUsedInConversation(
                carryovers.filter { it.source == Carryover.Source.DRILL_CARD }.mapNotNull { it.sourceId },
                language)
        }

        // Grow the long-term profile — the next conversation's prompt reads it.
        val speakingSeconds = turns.filter { it.role == TurnRole.USER }
            .sumOf { it.durationMs / 1000.0 }
        profile.absorb(computed, speakingSeconds)
        profileStore.save(profile)

        // Write tomorrow's call NOW, off the talk that just ended (iOS rule:
        // never in the morning — the app may not be running then). Best
        // effort; a failed script just means a generic opener.
        if (DailyCallStore.isEnabled(context)) {
            runCatching {
                val script = com.roro.futurevoice.net.VoicemailClient(AuthRepository()).writeScript(
                    targetLanguage = language,
                    nativeLanguage = nativeLanguage,
                    proficiency = level.code,
                    personaName = PersonaStore.shared(context).load()?.displayName,
                    lastTopic = resolvedTopic,
                    lastPhrases = (computed.expressionsOffered + computed.expressionsUsed).take(4),
                    daysSinceLastTalk = 0,
                    dueCount = drills.dueCount(language),
                    lastOutcome = DailyCallStore.lastOutcome(context)?.raw,
                    consecutiveUnanswered = DailyCallStore.consecutiveUnanswered(context),
                )
                if (script.isNotBlank()) DailyCallStore.setScript(context, script)
            }
        }

        StoreEvents.bump()
        report { it.copy(finished = true) }
        return saved
    }

    /**
     * The request, as iOS `SessionSummarizer` feeds `summarySystemPrompt`:
     * what the learner TYPED about themselves as the "already on file" list
     * (`knownFacts`), the notebook numbered and dated as the lines the call
     * may UPDATE, the learner's last share-rung moves, and the expression
     * budget from how much the fluent self said. [rememberedNotes] must be
     * the SAME list the caller later maps `replaces` onto.
     */
    fun requestBody(
        session: Session,
        nativeLanguage: String,
        profile: JsonObject,
        persona: UserPersona?,
        rememberedNotes: List<PersonaNote>,
        metrics: JsonObject,
        relationshipRegisterLine: String = "",
        utcOffsetMinutes: Int = java.util.TimeZone.getDefault().getOffset(session.startedAt) / 60_000,
    ): SessionSummaryClient.RequestBody = SessionSummaryClient.RequestBody(
        target_language = session.targetLanguage,
        native_language = nativeLanguage,
        profile = profile,
        known_about_user = persona?.knownFacts.orEmpty(),
        remembered_notes = rememberedNotes.map {
            SessionSummaryClient.RememberedNote(
                text = it.text, kind = it.kind.wire,
                learned_at = java.time.Instant.ofEpochMilli(it.learnedAt)
                    .truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString())
        },
        share_corrections = persona?.shareCorrections.orEmpty().map {
            SessionSummaryClient.ShareCorrection(text = it.text, from = it.from.wire, to = it.to.wire)
        },
        expression_budget = expressionBudget(session.turns.count { it.role == TurnRole.FLUENT_SELF }),
        transcript = formatTranscript(session.turns),
        metrics = metrics,
        // The talk's own date, dated by its last line (iOS: the summary is
        // told the TALK's date — a rescued summary runs days later).
        talk_date = java.time.Instant.ofEpochMilli(
            session.turns.maxOfOrNull { it.timestamp } ?: session.endedAt ?: session.startedAt)
            .truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString(),
        utc_offset_minutes = utcOffsetMinutes,
        relationship_register_line = relationshipRegisterLine,
    )

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

    /**
     * One `about_user` entry — iOS `ClaudeSummaryPayload.AboutUser`. Two
     * shapes are read: the current object `{text, heard, kind, share, gist,
     * why, replaces}` and the old bare string. `share` falls back to the
     * pre-three-rung `private` boolean (true → nothing, false → all), and with
     * neither to NOTHING: a line nobody judged is hidden. `kind` falls back to
     * a durable fact, `replaces` to a new line.
     */
    data class AboutUser(
        val text: String,
        val share: PersonaNote.Share = PersonaNote.Share.NOTHING,
        val kind: PersonaNote.Kind = PersonaNote.Kind.FACT,
        val heard: String? = null,
        val gist: String? = null,
        val why: String? = null,
        val replaces: Int? = null,
    ) {
        fun toNote(text: String, sessionId: String): PersonaNote {
            fun clip(raw: String?, limit: Int): String? =
                raw?.trim()?.takeIf { it.isNotEmpty() && it.length <= limit }
            val g = clip(gist, 140)
            // "The gist" with no gist to hand out is an empty promise; the
            // safe rung is the one below it.
            val rung = if (share == PersonaNote.Share.GIST && g == null) PersonaNote.Share.NOTHING else share
            return PersonaNote(text = text, sessionId = sessionId, share = rung, kind = kind,
                heard = clip(heard, 240), gist = g, why = clip(why, 140))
        }
    }

    fun aboutUser(p: JsonObject): List<AboutUser> =
        (p["about_user"] as? JsonArray)?.mapNotNull { e ->
            (e as? JsonPrimitive)?.takeIf { it.isString }?.let { return@mapNotNull AboutUser(it.content) }
            val o = e as? JsonObject ?: return@mapNotNull null
            // iOS decodes `text` as a String and `replaces` as an Int: a
            // number where text belongs, or "2" where a number belongs, is
            // not read as one.
            val text = (o["text"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                ?: return@mapNotNull null
            val share = PersonaNote.Share.from(str(o, "share"))
                ?: (o["private"] as? JsonPrimitive)?.booleanOrNull
                    ?.let { if (it) PersonaNote.Share.NOTHING else PersonaNote.Share.ALL }
                ?: PersonaNote.Share.NOTHING
            AboutUser(
                text = text, share = share,
                kind = PersonaNote.Kind.from(str(o, "kind")) ?: PersonaNote.Kind.FACT,
                heard = str(o, "heard"), gist = str(o, "gist"), why = str(o, "why"),
                replaces = (o["replaces"] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull,
            )
        }.orEmpty()

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
                // Kept only when it names a real band, so a stray value can
                // never cap the Progress page on nothing.
                grammarRange = ((sc["grammar"] as? JsonObject)?.let { str(it, "range") })
                    ?.trim()?.lowercase()?.takeIf { r -> com.roro.futurevoice.data.CefrLevel.entries.any { it.code == r } },
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
