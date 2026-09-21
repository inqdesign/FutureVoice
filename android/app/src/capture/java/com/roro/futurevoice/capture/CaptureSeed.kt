package com.roro.futurevoice.capture

import android.content.Context
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.NewsTopicStore
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.SubscriptionReceipt
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.talk.AxisScore
import com.roro.futurevoice.talk.Carryover
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.PersonaNote
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionMode
import com.roro.futurevoice.talk.SessionOrigin
import com.roro.futurevoice.talk.SessionScorecard
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.SuggestedTopic
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.UserPersona
import java.time.LocalDate
import java.time.ZonedDateTime
import java.util.UUID

/**
 * The screenshot harness's SAMPLE DATA — the seed half of iOS
 * `DebugCaptureHarness.swift` at `4a5e8df` (1.0.7, build 54), one function per
 * iOS seed, same names, same values, same dates relative to now.
 *
 * Writes into the REAL stores. That is safe only because the capture build
 * installs as its own app (`com.roro.futurevoice.capture`) with its own empty
 * sandbox — never call any of this from `main`.
 *
 * One deliberate difference from iOS: rows iOS mints with a fresh `UUID()`
 * (drill cards, sessions) get a STABLE id derived from their content here.
 * The capture sandbox survives across launches exactly like a simulator does,
 * and iOS's `DrillStore.seed` replaces by sentence while `SessionStore.save`
 * appends — so on iOS a re-run piles up extra talks. With stable ids an
 * upsert replaces, and every launch shows iOS's first-run counts.
 */
object CaptureSeed {

    // MARK: - once (iOS `DebugCapture.once`)

    private val seeded = mutableSetOf<String>()

    /** Idempotent per name within a process — the router may evaluate more than once. */
    suspend fun once(name: String, work: suspend () -> Unit) {
        synchronized(seeded) { if (!seeded.add(name)) return }
        work()
    }

    // MARK: - Time helpers

    private const val MIN = 60_000L
    private const val HOUR = 3_600_000L
    private const val DAY = 86_400_000L

    private fun now() = System.currentTimeMillis()

    /** `Calendar.current.date(byAdding: .day, value: n, to: Date())` — calendar days, DST-aware. */
    private fun calendarDays(n: Long): Long =
        ZonedDateTime.now().plusDays(n).toInstant().toEpochMilli()

    private fun stableId(kind: String, key: String): String =
        UUID.nameUUIDFromBytes("capture:$kind:$key".toByteArray()).toString().uppercase()

    private fun lang(context: Context) = LanguageScope.active(context)

    /** iOS `DrillStore.seed`: insert as-is, replacing any card with the same sentence. */
    private suspend fun seedCard(context: Context, card: DrillCard) {
        DrillStore.shared(context).upsertMany(listOf(card.copy(id = stableId("drill", card.targetPhrase))))
    }

    // MARK: - Persona

    /**
     * iOS `seedSamplePersona`: a profile with both halves filled — the typed
     * fields and four lines the fluent self picked up.
     */
    suspend fun seedSamplePersona(context: Context) {
        val t = now()
        val p = UserPersona(
            displayName = "Eunggyu",
            city = "Munich",
            country = "Germany",
            lengthOfStay = "3 years",
            occupation = "Solo founder of an AI app for language learners",
            household = "Wife and 4yo daughter at Kita",
            interests = listOf("AI / tech", "parenting", "language learning"),
            situations = listOf("Kita / school", "Client calls", "Daily small talk"),
            freeNotes = "Thinking about moving back next year.",
            metAt = calendarDays(-20),
            learnedNotes = listOf(
                // NOT PORTED: share (.all), heard ("Saturday mornings I run along the Isar, every week"),
                // why ("취미") — Android `PersonaNote` has only id/text/sessionId/learnedAt; the
                // three-way share lock and the "You said …" evidence aren't ported yet.
                PersonaNote(text = "매주 토요일 아침 이자르 강변에서 달린다",
                    sessionId = null, learnedAt = t - 9 * DAY),
                // NOT PORTED: share (.gist), heard ("I dropped my daughter off at Kita this morning"),
                // gist ("어린 아이를 키우는 부모"), why ("가족") — same missing PersonaNote fields.
                PersonaNote(text = "유치원생 딸이 하나 있다",
                    sessionId = null, learnedAt = t - 5 * DAY),
                // NOT PORTED: share (.nothing), heard ("the investor meeting didn't go well, money is
                // getting tight"), gist ("회사를 키우는 중"), why ("돈 이야기") — same missing fields.
                PersonaNote(text = "투자자 미팅이 잘 안 풀려서 자금 압박이 있다",
                    sessionId = null, learnedAt = t - 2 * DAY),
                // NOT PORTED: kind (.now — fades after a month), share (.nothing), heard ("I got back
                // from Seoul on Sunday and I'm still waking up at 4"), gist ("최근 여행을 다녀옴"),
                // why ("지금 상황") — Android has no PersonaNote.Kind either.
                PersonaNote(text = "서울 다녀와서 시차 적응 중",
                    sessionId = null, learnedAt = t - 1 * DAY),
            ),
        )
        PersonaStore.shared(context).save(p)
    }

    /**
     * iOS `seedUnmetPersona`: finished setup, never talked — the intake
     * answers on file, `metAt` nil, nothing remembered.
     */
    suspend fun seedUnmetPersona(context: Context) {
        PersonaStore.shared(context).save(UserPersona(
            displayName = "Eunggyu",
            city = "Munich",
            country = "Germany",
            interests = listOf("AI / tech", "parenting"),
            situations = listOf("Kita / school", "Client calls"),
        ))
    }

    // MARK: - Drill deck

    /**
     * iOS `seedDrillFolders`: cards across the deck's folder buckets (Soon /
     * Tomorrow / Later / Learned) plus 22 due cards to trip the session cap.
     */
    suspend fun seedDrillFolders(context: Context) {
        val t = now()
        val future: List<Triple<String, Long, Int>> = listOf(
            Triple("Could you say that one more time?", 10 * MIN, 0),
            Triple("I'm still getting the hang of it.", 2 * HOUR, 0),
            Triple("That works for me.", DAY, 1),
            Triple("Let me get back to you on that.", DAY + 2 * HOUR, 1),
            Triple("I'd rather we met a bit earlier.", 3 * DAY, 2),
            Triple("It slipped my mind completely.", 7 * DAY, 3),
            Triple("We're on the same page.", 30 * DAY, 5),
            Triple("That's a fair point.", 30 * DAY, 5),
        )
        for ((tgt, delay, box) in future) {
            seedCard(context, DrillCard(
                sourcePhrase = "", targetPhrase = tgt, reason = "",
                createdAt = t - DAY, lastReviewedAt = t,
                nextReviewAt = t + delay, box = box))
        }
        for (i in 0 until 22) {
            seedCard(context, DrillCard(
                sourcePhrase = "I have went there ${i + 1} times",
                targetPhrase = "I have been there ${i + 1} times",
                reason = "past participle",
                createdAt = t - i * HOUR, lastReviewedAt = null,
                nextReviewAt = t - HOUR, box = 0))
        }
    }

    // MARK: - Vocabulary + expressions

    private const val VOCAB_SESSION_ID = "00000000-0000-0000-0000-0000000000A1"

    /**
     * iOS `seedVocab(freshSchedule:)`. `freshSchedule` wipes the study
     * schedule first, because the deck's folders read it from disk and the
     * file survives across launches.
     */
    suspend fun seedVocab(context: Context, freshSchedule: Boolean = false) {
        val language = lang(context)
        if (freshSchedule) StudyScheduleStore.shared(context).removeAll(language)
        val vocab = VocabStore.shared(context)
        val texts = listOf(
            "I really appreciate you taking the time to meet me today.",
            "Honestly I appreciate how straightforward the whole process was.",
            "My commute is long so I usually catch up on podcasts.",
            "The commute gave me time to genuinely think it through.",
            "We had to negotiate the deadline because the scope grew.",
            "I felt a little overwhelmed but I managed to reschedule everything.",
            "My colleague suggested we reschedule the meeting to Friday.",
            "I didn't hesitate to ask for help when I got stuck.",
            "Let me walk you through the reasoning behind this decision.",
            "It turned out to be more nuanced than I first assumed.",
            "I want to sound confident without being arrogant.",
            "She handled the awkward moment with a lot of grace.",
        )
        vocab.ingest(VOCAB_SESSION_ID, texts, language)
        for (w in listOf("appreciate", "genuinely", "negotiate", "overwhelmed",
            "straightforward", "reschedule", "nuanced", "hesitate")) {
            vocab.addStudying(w, language)
        }
        vocab.ingestExpressions(VOCAB_SESSION_ID,
            listOf("walk you through", "catch up on", "think it through",
                "turned out to be", "handled it with grace"), language)
        // iOS `addExpression` = bookmark unless already bookmarked.
        for (e in listOf("catch up on", "walk you through", "turned out to be")) {
            if (!vocab.isStudyingExpression(e, language)) vocab.setStudyingExpression(e, true, language)
        }

        // A few review cards due NOW, so Home's "Review N cards" action shows.
        val t = now()
        val due = listOf(
            Triple("it go really well", "it went really well", "past tense"),
            Triple("I very like it", "I really like it", "adverb choice"),
            Triple("more easy", "easier", "comparative form"),
        )
        for ((src, tgt, why) in due) {
            seedCard(context, DrillCard(
                sourcePhrase = src, targetPhrase = tgt, reason = why,
                createdAt = t, lastReviewedAt = null,
                nextReviewAt = t - HOUR, box = 0))
        }
        // One legacy-style card with a WHOLE rambling turn as its source, to
        // verify the render-time fragment trim keeps the card on screen.
        seedCard(context, DrillCard(
            sourcePhrase = "Hey I'm just wondering if there is any kind of Yeah, where people come and set " +
                "the same goal and Together towards to the door like English learning I see a lot of " +
                "people are learning and practicing Gather set the same goal like 100 days challenge " +
                "your 30 day challenge and they just calm and share their experience in progress. " +
                "I kinda like this whole community and I'm sure there are tons of community but I'm " +
                "just trying to. Feel something around Nirvana the app that I'm gonna be working on",
            targetPhrase = "I'm trying to build something around the app that I'm going to work on.",
            reason = "Use \"build something around\" for creating a community around an app.",
            // Newest createdAt → first in the due queue, so the capture opens on this card.
            createdAt = t + MIN, lastReviewedAt = null,
            nextReviewAt = t - 2 * HOUR, box = 0))
    }

    // MARK: - Sessions

    /** iOS `DebugCapture.sampleScorecard`. */
    val sampleScorecard: SessionScorecard
        get() = SessionScorecard(
            vocabulary = AxisScore(82, "Reached for precise, specific words."),
            grammar = AxisScore(71, "A few article and tense slips to tidy."),
            expressiveness = AxisScore(68, "Getting more natural and idiomatic."),
            fluency = AxisScore(74, "Steady pace, fewer long pauses."),
            pronunciation = AxisScore(80, "Clear, with good linking."),
            topLine = "Confident, natural talk — tighten a few articles.",
            cefrLevel = "b1",
        )

    /** Held so a route seeds once but can still hand the same session to its view. */
    var carryoverSession: Session? = null
        private set

    /**
     * iOS `seedCarryoverSession(scored:)`: a finished talk carrying one
     * carryover per source; quotes pad the studied item out the way the
     * matcher accepts. `scored = false` keeps the scorecard off so the
     * carryover section lands above the fold.
     */
    suspend fun seedCarryoverSession(context: Context, scored: Boolean = false): Session {
        val sessionId = stableId("session", "carryover")
        val ended = now() - 1_800_000L
        val started = ended - 720_000L

        data class Seed(val source: Carryover.Source?, val item: String, val quote: String)
        val seeds = listOf(
            Seed(Carryover.Source.DRILL_CARD, "I'd rather stay in tonight.",
                "Honestly I'd rather just stay in tonight, if that's okay."),
            Seed(Carryover.Source.CURRICULUM_ITEM, "Could you box that up for me?",
                "Great, could you box that up for me please?"),
            Seed(Carryover.Source.STUDYING_EXPRESSION, "it slipped my mind",
                "Sorry, it totally slipped my mind."),
            Seed(Carryover.Source.SUGGESTION, "I'm really looking forward to it.",
                "Next Friday. I'm really looking forward to it."),
            Seed(Carryover.Source.STUDYING_WORD, "commute",
                "I commuted for two hours every day back then."),
            // NOT PORTED: the Carryover for source `.knownExpression` ("on the same page") —
            // Android `Carryover.Source` has no KNOWN_EXPRESSION case (the used-outranks-known
            // rule isn't ported). The turns are still seeded so the transcript matches iOS.
            Seed(null, "on the same page",
                "Just so we're on the same page, it's Friday, right?"),
            // NOT PORTED: the Carryover for source `.knownWord` ("hectic") — no KNOWN_WORD case.
            Seed(null, "hectic",
                "This week has been pretty hectic at work."),
        )

        val turns = mutableListOf<Turn>()
        val carryovers = mutableListOf<Carryover>()
        seeds.forEachIndexed { index, seed ->
            val at = started + index * 90_000L
            turns += Turn(role = TurnRole.FLUENT_SELF, transcript = "Mm — and then what?",
                durationMs = 2400, timestamp = at)
            val userTurn = Turn(role = TurnRole.USER, transcript = seed.quote,
                durationMs = 7200, timestamp = at + 4_000L)
            turns += userTurn
            if (seed.source != null) {
                carryovers += Carryover(
                    sessionId = sessionId, source = seed.source, item = seed.item,
                    quote = seed.quote, turnId = userTurn.id, sourceId = StoreJson.newId(),
                    detectedAt = ended)
            }
        }

        val summary = SessionSummary(
            overallNote = "Relaxed, natural talk — and you pulled in a lot of what you'd been studying.",
            scorecard = if (scored) sampleScorecard else null,
            carryovers = carryovers,
        )
        val session = Session(
            id = sessionId, userId = StoreJson.newId(), targetLanguage = "en",
            mode = SessionMode.CONVERSATION, topic = "Weekend plans",
            startedAt = started, endedAt = ended,
            turns = turns, summary = summary, origin = SessionOrigin.FREE)
        SessionStore.shared(context).save(session)
        carryoverSession = session
        return session
    }

    /**
     * iOS `seedSessions(scored:)`: three talks on the last three days, one per
     * origin so the Talk shelf shows every badge. `scored` attaches a
     * scorecard so Progress's assessed branch renders.
     */
    suspend fun seedSessions(context: Context, scored: Boolean = false) {
        val uid = StoreJson.newId()
        val origins = listOf(SessionOrigin.FREE, SessionOrigin.NEWS, SessionOrigin.SCENARIO)
        for (day in 0 until 3) {
            val ended = now() - day * DAY + HOUR
            val started = ended - 600_000L
            val turns = listOf(
                Turn(role = TurnRole.FLUENT_SELF, transcript = "So — how did the interview go?",
                    durationMs = 3200, timestamp = started),
                Turn(role = TurnRole.USER, transcript = "Honestly, it went really well. I felt prepared.",
                    durationMs = 62_000, timestamp = started + 6_000L),
                Turn(role = TurnRole.FLUENT_SELF, transcript = "That's great. What surprised you most?",
                    durationMs = 2600, timestamp = started + 70_000L),
                Turn(role = TurnRole.USER, transcript = "How relaxed I stayed, even on the hard questions.",
                    durationMs = 58_000, timestamp = started + 80_000L),
            )
            // iOS: `summary?.expressionsOffered = …` — only a scored summary exists to carry them.
            val summary = if (scored) SessionSummary(
                overallNote = "Confident, natural talk — tighten a few articles.",
                scorecard = sampleScorecard,
                expressionsOffered = listOf("what surprised you most", "how did it go"),
            ) else null
            val origin = origins[day % 3]
            val topic = when (origin) {
                SessionOrigin.FREE -> null
                SessionOrigin.NEWS -> "Four-day work week"
                SessionOrigin.SCENARIO -> "Job interview"
            }
            SessionStore.shared(context).save(Session(
                id = stableId("session", "sessions-$day"), userId = uid, targetLanguage = "en",
                mode = SessionMode.CONVERSATION, topic = topic,
                startedAt = started, endedAt = ended,
                turns = turns, summary = summary, origin = origin))
        }
    }

    // MARK: - News

    /**
     * iOS `seedNews(into:)`: interests + a cached news pool, so Home renders
     * the news rail offline. iOS sets the interests on the IN-MEMORY
     * `appState.persona` only; Android's screens read the persona from
     * [PersonaStore], so it is written there — and only when missing or
     * interest-less, exactly the cases iOS touches.
     */
    suspend fun seedNews(context: Context) {
        val interests = listOf("ai / tech", "cooking")
        val personas = PersonaStore.shared(context)
        val existing = personas.load()
        val effective = when {
            existing == null -> {
                personas.save(UserPersona(displayName = "Alex", city = "Munich",
                    country = "Germany", interests = interests))
                interests
            }
            existing.interests.isEmpty() -> {
                personas.save(existing.copy(interests = interests))
                interests
            }
            else -> existing.interests
        }
        NewsTopicStore.shared(context).save(listOf(
            SuggestedTopic(title = "Did you hear about OpenAI's model hacking a company?",
                blurb = "An AI model reportedly breached another tech firm, leading to discussions about controlling autonomous agents.",
                category = "ai / tech"),
            SuggestedTopic(title = "Have you heard beef tallow is making a comeback?",
                blurb = "The traditional cooking fat is seeing a resurgence in restaurants and home kitchens.",
                category = "cooking"),
            SuggestedTopic(title = "Did you see the home robot folding laundry?",
                blurb = "A startup demoed a household robot completing chores end to end.",
                category = "ai / tech"),
        ), effective, lang(context))
    }

    // MARK: - Watch (curriculum books)

    private fun item(text: String, note: String, mastered: Boolean = false) =
        ScenarioCurriculum.Item(text = text, note = note, masteredAt = if (mastered) now() else null)

    /** A 14-item curriculum with the first [mastered] items checked off. */
    private fun curriculum(mastered: Int): ScenarioCurriculum {
        val words = listOf("appreciate", "straightforward", "negotiate", "reschedule", "nuanced", "overwhelmed")
        val exprs = listOf("catch up on", "walk you through", "turned out to be", "a bit of a stretch")
        val lines = listOf(
            "I really appreciate you making the time.",
            "Let me walk you through what happened.",
            "Honestly, it turned out better than expected.",
            "Could we reschedule for later this week?",
        )
        var n = mastered
        fun take(texts: List<String>) = texts.map { t -> item(t, "", mastered = n > 0).also { n -= 1 } }
        return ScenarioCurriculum(
            words = take(words),
            expressions = take(exprs),
            shadowLines = take(lines),
            dialogueTitle = "The scene",
        )
    }

    /**
     * iOS `seedScenarios(into:)`: clears every saved scenario, then four topic
     * books at varied progress, four situation books (one at 0%, one fully
     * mastered for the finished shelf).
     */
    suspend fun seedScenarios(context: Context) {
        seedVocab(context)
        val store = ScenarioStore.shared(context)
        for (s in store.load()) store.delete(s.id)

        val topics = listOf(
            "Germany weighs a nationwide four-day work week" to 4,
            "AI tutors are reshaping how adults learn languages" to 8,
            "Why night trains are quietly making a comeback in Europe" to 2,
            "The unexpected revival of handwritten letters" to 11,
        )
        for ((title, done) in topics) {
            store.save(Scenario(environment = title, role = "the discussion", notes = "",
                curriculum = curriculum(done), isTopic = true))
        }
        store.save(Scenario(
            environment = "At the café with Sarah: catching up after months apart — she asks what I've been up to and I keep the story going.",
            role = "Sarah (close friend)", notes = "",
            lastUsedAt = now() - 5 * HOUR,
            curriculum = curriculum(5), isTopic = false,
            category = "Cafe", categoryIcon = "cup.and.saucer.fill",
            summary = "Café · catching up"))
        store.save(Scenario(
            environment = "At the doctor's office: describing a symptom I've had for a week and answering their follow-up questions.",
            role = "Doctor", notes = "",
            lastUsedAt = now() - 2 * DAY,
            curriculum = curriculum(3), isTopic = false,
            category = "Health", categoryIcon = "cross.case.fill",
            summary = "Doctor's visit"))
        // One brand-new 0% book so the Studying page's "Start next" section renders.
        store.save(Scenario(
            environment = "A panel interview: introducing myself, walking through my experience, and handling curveball questions.",
            role = "Interviewer", notes = "",
            curriculum = curriculum(0), isTopic = false,
            category = "Work", categoryIcon = "briefcase.fill",
            summary = "Job interview · panel round"))
        // …and one taken all the way (14 = every item) for the finished shelf.
        store.save(Scenario(
            environment = "At the pharmacy: picking up a prescription, and the pharmacist has questions about my insurance.",
            role = "Pharmacist", notes = "",
            lastUsedAt = now() - 10 * DAY,
            curriculum = curriculum(14), isTopic = false,
            category = "Health", categoryIcon = "cross.case.fill",
            summary = "Pharmacy · picking up a prescription"))
    }

    /** Every seed once, in the order iOS's fullest routes ("home", "tabs") run them. */
    suspend fun seedAll(context: Context) {
        once("sample-persona") { seedSamplePersona(context) }
        once("vocab") { seedVocab(context) }
        once("drills") { seedDrillFolders(context) }
        once("sessions") { seedSessions(context, scored = true) }
        once("carryover") { seedCarryoverSession(context) }
        once("news") { seedNews(context) }
        once("scenarios") { seedScenarios(context) }
    }

    // MARK: - Sample accounts (billing captures render these, never the network)

    /**
     * iOS `sampleLightAccount`: a Light subscriber mid-period, 55 of 150 min
     * and 12 of 60 scenes spent, refilling in 18 days. ONE sample for every
     * billing page — they quote each other's numbers.
     *
     * NOT PORTED: `email` (nil), `fullTankSeconds` (9000), `periodStart` (−12 days) —
     * Android `AccountStatus` has none of the three. `periodEnd` is Android's
     * `yyyy-MM-dd` string rather than a Date.
     */
    val sampleLightAccount: AccountStatus
        get() = AccountStatus(
            secondsBalance = 0,
            planId = "light_monthly",
            subscriptionStatus = "active",
            secondsUsedPeriod = 3300,
            monthlyCapSeconds = 9000,
            scenesUsedPeriod = 12,
            monthlyScenesCap = 60,
            periodEnd = LocalDate.now().plusDays(18).toString(),
        )

    /**
     * The store half of iOS `sampleLightAccount` — Android keeps it on its own
     * [SubscriptionReceipt] read. A launch-code subscriber: every row of the
     * Usage page's subscription section has something to show.
     *
     * NOT PORTED: `renewalOfferType` (3), `renewalPriceMilliunits` (7_500_000),
     * `renewalCurrency` ("KRW") — Android has no renewal-info fields (the
     * 2026-09-18 `renewal_*` columns aren't read on Android yet).
     */
    val sampleLightReceipt: SubscriptionReceipt
        get() {
            val started = LocalDate.now().minusDays(12)
            return SubscriptionReceipt(
                source = "apple",
                startedAt = started,
                lastChargeMilliunits = 7_500_000,
                lastChargeCurrency = "KRW",
                lastChargeDate = started,   // iOS: = periodStart, which is the same −12 days
                currentOfferType = 3,
                offerCodeSince = started,
            )
        }

    /**
     * iOS `sampleTrialAccount`: the same Light account in its FIRST week —
     * trialing, started 3 days ago, period ends in 4.
     */
    val sampleTrialAccount: AccountStatus
        get() = sampleLightAccount.copy(
            subscriptionStatus = "trialing",
            periodEnd = LocalDate.now().plusDays(4).toString(),
        )

    /**
     * The store half of iOS `sampleTrialAccount`: nothing charged yet, the
     * latest transaction is the intro offer (type 1), no offer-code
     * transaction. (Renewal fields: NOT PORTED, as on [sampleLightReceipt].)
     */
    val sampleTrialReceipt: SubscriptionReceipt
        get() = sampleLightReceipt.copy(
            startedAt = LocalDate.now().minusDays(3),
            lastChargeMilliunits = null,
            lastChargeCurrency = null,
            lastChargeDate = null,
            currentOfferType = 1,
            offerCodeSince = null,
        )

    /**
     * iOS `UsageBreakdown.sample` — the period/today/free/day figures that add
     * up against [sampleLightAccount] (3300 s spent). Android has no
     * `UsageBreakdown` type and no screen that draws the per-day bars yet, so
     * the numbers are kept here as plain data for whoever ports that section.
     */
    object SampleUsage {
        /** (meter key, seconds, count) for the billing period. */
        val period = listOf(Triple("talk_time", 3300, 24), Triple("tts_scene", 780, 12))
        val today = listOf(Triple("talk_time", 120, 2))
        /** (free key, count) today. */
        val freeToday = listOf("drills" to 34, "shadow" to 12, "ideas" to 7, "reports" to 3)
        /** Talk seconds per UTC day, today first; sums to 3300. Zero days are dropped except today. */
        val dayTalkSeconds = listOf(120, 420, 0, 360, 180, 540, 90, 300, 0, 240, 480, 150, 210, 210)
    }
}
