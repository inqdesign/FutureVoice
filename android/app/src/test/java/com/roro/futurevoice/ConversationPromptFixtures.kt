package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.SpeechRegister
import com.roro.futurevoice.talk.LearnerPattern
import com.roro.futurevoice.talk.PersonaNote
import com.roro.futurevoice.talk.PromptClock
import com.roro.futurevoice.talk.ScenarioBrief
import com.roro.futurevoice.talk.UserPersona
import java.time.ZoneId

/**
 * The fixtures of `scripts/android/promptgen/main.swift`, value for value —
 * the iOS prompt for each is in `vectors/conversation-prompts.json`. Change
 * both together.
 */
object ConversationPromptFixtures {
    val now = System.currentTimeMillis()
    fun daysAgo(d: Int) = now - d * 86_400_000L

    /** 2026-10-13 08:14 UTC = 10:14 in Berlin. */
    const val CALL_START = 1_791_879_240_000L
    val berlin: ZoneId = ZoneId.of("Europe/Berlin")
    /** A talk N days before the CALL (the clock measures from [CALL_START]);
     *  never the real clock, or the vector moves with the date. */
    fun daysBeforeCall(d: Int) = CALL_START - d * 86_400_000L

    val notes = listOf(
        PersonaNote(text = "works as a nurse on night shifts", learnedAt = daysAgo(90), share = PersonaNote.Share.ALL, kind = PersonaNote.Kind.FACT),
        PersonaNote(text = "two kids, kindergarten age", learnedAt = daysAgo(20), share = PersonaNote.Share.GIST, kind = PersonaNote.Kind.FACT,
            gist = "a parent of young kids"),
        PersonaNote(text = "has a sister in Busan", learnedAt = daysAgo(3), share = PersonaNote.Share.NOTHING, kind = PersonaNote.Kind.FACT),
        PersonaNote(text = "flying to Seoul next Thursday", learnedAt = daysAgo(2), share = PersonaNote.Share.ALL, kind = PersonaNote.Kind.NOW),
        PersonaNote(text = "had a cold", learnedAt = daysAgo(40), share = PersonaNote.Share.ALL, kind = PersonaNote.Kind.NOW),
    )

    val fullPersona = UserPersona(
        displayName = "Eunggyu", city = "Munich", country = "Germany", lengthOfStay = "3 years",
        occupation = "Solo founder of a language app", household = "Wife and 4yo daughter at Kita",
        interests = listOf("hiking", "AI", "coffee"), situations = listOf("Kita parent small talk", "client calls"),
        freeNotes = "Prefers short calls", updatedAt = now, learnedNotes = notes, metAt = daysAgo(30))

    val thinPersona = UserPersona(displayName = "Mina", updatedAt = now,
        learnedNotes = listOf(notes[2], notes[3]), metAt = null)

    val patterns = listOf(
        LearnerPattern(mistake = "I go yesterday", correction = "I went yesterday", context = "past tense", frequency = 4),
        LearnerPattern(mistake = "more better", correction = "better", context = "comparatives", frequency = 3),
        LearnerPattern(mistake = "discuss about", correction = "discuss", context = "verb + preposition", frequency = 2),
        LearnerPattern(mistake = "a advice", correction = "some advice", context = "uncountables", frequency = 1),
    )

    val brief = ScenarioBrief(
        summary = "Interview for a product role at Siemens",
        counterpartFacts = listOf("You are the hiring manager", "The team ships medical imaging software"),
        likelyQuestions = listOf("Why Siemens?", "Tell me about a hard launch"),
        learnerFacts = listOf("Eight years in product", "Led a team of five"),
        keyExpressions = listOf("walk you through", "on the same page"))

    fun clock(today: Int, lastToday: Long?, before: Long?, resumed: Long? = null) =
        PromptClock(CALL_START, berlin, today, lastToday, before, resumed)

    val closeFriend = Counterpart(name = "Minsu", relationship = "best friend from university", voicePresetId = "preset",
        relationshipKind = "Friend", howWeMet = "College roommates, 8 years",
        location = "Seoul, works at a game studio", conversationStyle = "jokes a lot",
        commonTopics = "games, football", background = "We backpacked through Japan together",
        freeNotes = "Just had a baby", myRegister = SpeechRegister.CASUAL, theirRegister = SpeechRegister.CASUAL,
        iCallThem = "민수야", theyCallMe = "형")
    val manager = Counterpart(name = "Ms. Keller", relationship = "my manager", voicePresetId = "preset",
        relationshipKind = "Colleague", conversationStyle = "careful, formal")
    private const val LENA = "I teach piano in Munich and hike every weekend. My son just started school."
    val stranger = Counterpart(name = "Lena", relationship = "Met on nawana", voicePresetId = "preset",
        remoteId = "remote-lena", location = "Munich, Germany", commonTopics = "hiking, piano",
        intro = LENA, background = LENA, conversationStyle = "warm, curious", personaKind = "user")
    val strangerNoGround = Counterpart(name = "Paul", relationship = "Met on nawana", voicePresetId = "preset",
        remoteId = "remote-paul", intro = "Je suis boulanger à Lyon.", background = "Je suis boulanger à Lyon.",
        personaKind = "character")
    val publicFigure = Counterpart(name = "RM", relationship = "", voicePresetId = "preset",
        isPublicFigure = true, publicIdentity = "BTS RM · rapper", relationshipKind = "Public figure")

    data class Fixture(
        val name: String, val target: String, val native: String, val level: CefrLevel,
        val patterns: List<LearnerPattern> = emptyList(), val weak: List<String> = emptyList(),
        val topic: String = "", val persona: UserPersona? = null, val counterpart: Counterpart? = null,
        val news: List<String> = emptyList(), val brief: ScenarioBrief? = null,
        val firstMeeting: Boolean = false, val clock: PromptClock? = null, val tutor: Boolean = false,
    )

    val fixtures = listOf(
        Fixture("free_en_b1_bare", "en", "ko", CefrLevel.B1),
        Fixture("free_ko_a2_full_tutor", "ko", "en", CefrLevel.A2, patterns = patterns, weak = listOf("food", "work"),
            topic = "Weekend plans", persona = fullPersona,
            news = listOf("The city opened a new tram line", "Fares stay the same"),
            clock = clock(2, CALL_START - 3 * 3_600_000L, daysBeforeCall(3)), tutor = true),
        Fixture("first_ja_a1_tutor", "ja", "ko", CefrLevel.A1, persona = thinPersona, firstMeeting = true,
            clock = clock(0, null, null), tutor = true),
        Fixture("brief_de_c1", "de", "en", CefrLevel.C1, topic = "Job interview at Siemens. Practice the interview.",
            persona = fullPersona, brief = brief,
            clock = clock(1, CALL_START - 20 * 60_000L, null, resumed = CALL_START - 2 * 86_400_000L), tutor = true),
        Fixture("cast_own_close_ko", "ko", "en", CefrLevel.B2, persona = fullPersona, counterpart = closeFriend,
            clock = clock(1, CALL_START - 3_600_000L, daysBeforeCall(10))),
        Fixture("cast_own_manager_en", "en", "ko", CefrLevel.B1, persona = fullPersona, counterpart = manager),
        Fixture("cast_stranger_en_tutor", "en", "ko", CefrLevel.B1, persona = fullPersona, counterpart = stranger,
            clock = clock(0, null, daysBeforeCall(1)), tutor = true),
        Fixture("cast_stranger_fr_noground", "fr", "en", CefrLevel.C2, counterpart = strangerNoGround),
        Fixture("cast_public_figure_ko", "ko", "en", CefrLevel.A2, persona = thinPersona, counterpart = publicFigure),
        Fixture("first_counterpart_ignored_es", "es", "en", CefrLevel.B2, persona = null, counterpart = manager,
            firstMeeting = true),
    )

    /** name → (target, native, counterpart, inScene) for `turnOutputInstruction`. */
    val outputs = listOf(
        listOf("output/en_plain", "en", "ko", null, false),
        listOf("output/ko_close_friend", "ko", "en", closeFriend, false),
        listOf("output/ko_scene", "ko", "en", null, true),
        listOf("output/ko_manager", "ko", "ja", manager, false),
        listOf("output/ja_stranger", "ja", "ko", stranger, false),
        listOf("output/de_plain", "de", "en", null, false),
    )

    /** Mirrors `corrections` in scripts/android/promptgen/main.swift. */
    val corrections = listOf(
        listOf("correction/en_plain", "en", "ko", CefrLevel.B1, null, false),
        listOf("correction/ko_close_friend", "ko", "en", CefrLevel.B2, closeFriend, false),
        listOf("correction/ko_scene", "ko", "en", CefrLevel.A2, null, true),
        listOf("correction/ko_manager", "ko", "ja", CefrLevel.B1, manager, false),
        listOf("correction/ja_stranger", "ja", "ko", CefrLevel.A1, stranger, false),
        listOf("correction/de_plain", "de", "en", CefrLevel.C1, null, false),
    )
}
