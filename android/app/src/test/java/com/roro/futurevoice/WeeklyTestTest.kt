package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.TextScript
import com.roro.futurevoice.data.WeekRecap
import com.roro.futurevoice.data.WeeklyTest
import com.roro.futurevoice.data.WeeklyTestAnswer
import com.roro.futurevoice.data.WeeklyTestEngine
import com.roro.futurevoice.data.WeeklyTestItem
import com.roro.futurevoice.data.WeeklyTestRandom
import com.roro.futurevoice.data.WeeklyTestSchedule
import com.roro.futurevoice.data.WeeklyTestStore
import com.roro.futurevoice.data.WordClass
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.LearnerPattern
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The weekly test's pure rules (iOS `WeeklyTestTests` + `WordClassTests` +
 * `MeaningDecoyTests`): how an answer is graded, how a blank and a tile set
 * are made, which week a moment belongs to, and which misses come back. Nothing here touches a store or the network.
 *
 * Not ported: the Japanese tile round trip — segmentation is `android.icu`'s
 * `BreakIterator`, which a JVM test cannot reach (the same reason
 * `JapaneseMorphVectorTest` feeds tokens rather than cutting) — and the
 * English tagger fallback, which Android doesn't have (an off-list English
 * word is UNKNOWN, i.e. may sit beside anything).
 */
class WeeklyTestTest {

    companion object {
        @BeforeClass @JvmStatic fun tables() {
            WordClass.opener = { name ->
                File("src/main/assets/wordlists/$name").takeIf { it.exists() }?.inputStream()
            }
        }
    }

    private fun item(kind: WeeklyTestItem.Kind, answer: String, options: List<String> = emptyList(),
                     prompt: String = "") =
        WeeklyTestItem(kind = kind, prompt = prompt, answer = answer, options = options)

    private val berlin: ZoneId = ZoneId.of("Europe/Berlin")
    private fun at(y: Int, mo: Int, d: Int, h: Int, mi: Int = 0) =
        ZonedDateTime.of(y, mo, d, h, mi, 0, 0, berlin).toInstant().toEpochMilli()
    private fun dayOf(ms: Long) = java.time.Instant.ofEpochMilli(ms).atZone(berlin)

    // ── Grading

    /** Case and trailing punctuation are the transcriber's, never the learner's. */
    @Test fun choiceGradingIgnoresCaseAndPunctuation() {
        val gap = item(WeeklyTestItem.Kind.GAP, "push back on")
        assertTrue(WeeklyTestEngine.isCorrect(gap, "Push back on."))
        assertFalse(WeeklyTestEngine.isCorrect(gap, "push back"))
    }

    /** Right only in the answer's order, with every tile and no decoy left in. */
    @Test fun buildGradingIsOrderSensitive() {
        val card = item(WeeklyTestItem.Kind.BUILD, "I really like it")
        assertTrue(WeeklyTestEngine.isCorrect(card, listOf("I", "really", "like", "it"), "en"))
        assertFalse(WeeklyTestEngine.isCorrect(card, listOf("I", "like", "it", "really"), "en"))
        assertFalse(WeeklyTestEngine.isCorrect(card, listOf("I", "really", "like"), "en"))
        assertFalse(WeeklyTestEngine.isCorrect(card, listOf("I", "very", "really", "like", "it"), "en"))
    }

    // ── Making items

    /** Material in the learner's own language never becomes an item. */
    @Test fun itemsRequireTheTargetScript() {
        assertTrue(TextScript.isInTargetScript("Show me the clock once.", "en"))
        assertFalse(TextScript.isInTargetScript("한번 나올게 해줘 시계.", "en"))
        assertFalse(TextScript.isInTargetScript("Show me 시계", "en"))
        assertTrue(TextScript.isInTargetScript("시계를 보여 줘.", "ko"))
        assertTrue(TextScript.isInTargetScript("時計を見せて。", "ja"))
        assertFalse(TextScript.isInTargetScript("123 …", "en"))
    }

    @Test fun blankReplacesThePhraseOnce() {
        assertEquals("You can always ${WeeklyTestEngine.BLANK_MARK} the unpacking later.",
            WeeklyTestEngine.blank("catch up on", "You can always Catch up on the unpacking later."))
        assertNull(WeeklyTestEngine.blank("end up", "Nothing here."))
        // Diacritic-insensitive, and the rest of the line is kept as written.
        assertEquals("Das ist ${WeeklyTestEngine.BLANK_MARK} gut.", WeeklyTestEngine.blank("Uber", "Das ist über gut."))
    }

    /** Tiles hold every target word, add only words the learner's version had,
     *  and never come out already in order. */
    @Test fun buildTilesCarryTheTargetPlusDecoysFromTheSource() {
        val rng = WeeklyTestRandom("00000000-0000-0000-0000-000000000042")
        val tiles = WeeklyTestEngine.buildTiles("I really like it", "I very like it", "en", rng)
        val keys = tiles.map(WeeklyTestEngine::tileKey)
        for (w in listOf("i", "really", "like", "it")) assertTrue(w, w in keys)
        assertTrue("very" in keys)
        assertEquals(5, tiles.size)
        assertNotEquals(listOf("i", "really", "like", "it", "very"), keys)
    }

    /** A word the correction merely dropped is not a decoy; a replaced one is. */
    @Test fun decoysAreReplacedWordsOnly() {
        fun w(t: String) = WordSplitter.words(t, "en")
        val replaced = WeeklyTestEngine.replacedWords(w("I felt the intro section took too long."),
            w("I felt like the intro took a bit too long."))
        assertFalse("section" in replaced)
        assertEquals(listOf("very"), WeeklyTestEngine.replacedWords(w("I very like it"), w("I really like it")))
        assertEquals(listOf("end"), WeeklyTestEngine.replacedWords(w("I end up carrying most boxes myself."),
            w("I ended up carrying most of the boxes myself.")))
        val tiles = WeeklyTestEngine.buildTiles("I felt like the intro took a bit too long.",
            "I felt the intro section took too long.", "en", WeeklyTestRandom("00000000-0000-0000-0000-000000000011"))
        assertFalse("section" in tiles)
        assertEquals(WordSplitter.count("I felt like the intro took a bit too long.", "en"), tiles.size)
    }

    /** Dictation tiles are the line's own words, never handed back in order. */
    @Test fun dictationTilesAreTheLineShuffled() {
        val line = "Give yourself a day off."
        val tiles = WeeklyTestEngine.dictationTiles(line, "en", WeeklyTestRandom(StoreJson.newId()))
        assertEquals(WordSplitter.words(line, "en").sorted(), tiles.sorted())
        assertNotEquals(WordSplitter.words(line, "en"), tiles)
    }

    @Test fun seededRandomIsDeterministic() {
        val id = StoreJson.newId()
        assertEquals(listOf(1, 2, 3, 4, 5).shuffled(WeeklyTestRandom(id)),
            listOf(1, 2, 3, 4, 5).shuffled(WeeklyTestRandom(id)))
    }

    /** A near miss is mostly right: only the misplaced tiles are marked, and
     *  the word that never arrived is named. */
    @Test fun tileCheckMarksOnlyWhatWentWrong() {
        val answer = "Considering it's only two weeks away from the launch."
        val laid = listOf("Exactly.", "it's", "Considering", "only", "two", "weeks", "from", "the", "launch.")
        val check = WeeklyTestEngine.tileCheck(laid, answer, "en")
        assertEquals(laid.size, check.correct.size)
        assertFalse(check.correct[0])
        assertTrue(check.correct.count { it } >= 6)
        val words = WordSplitter.words(answer, "en")
        val missing = words.zip(check.answerMatched).filter { !it.second }.map { it.first }
        assertTrue("away" in missing)
        val perfect = WeeklyTestEngine.tileCheck(words, answer, "en")
        assertTrue(perfect.correct.all { it })
        assertTrue(perfect.answerMatched.all { it })
    }

    /** Korean writes spaces: whitespace tiles, punctuation riding on the word. */
    @Test fun koreanBuildTilesAndBlank() {
        val target = "어제 친구랑 영화를 봤어요."
        val tiles = WeeklyTestEngine.buildTiles(target, "어제 친구 영화 봤어.", "ko",
            WeeklyTestRandom("00000000-0000-0000-0000-000000000009"))
        assertTrue("봤어요." in tiles)
        val card = item(WeeklyTestItem.Kind.BUILD, target)
        assertTrue(WeeklyTestEngine.isCorrect(card, WordSplitter.words(target, "ko"), "ko"))
        assertEquals("어제 친구랑 ${WeeklyTestEngine.BLANK_MARK} 봤어요.", WeeklyTestEngine.blank("영화를", target))
        assertFalse(TextScript.isInTargetScript("I saw a movie.", "ko"))
    }

    /** A stored item is judged in ITS test's language, never the active one. */
    @Test fun validityIsJudgedInTheTestsLanguage() {
        val en = item(WeeklyTestItem.Kind.MEANING, "chore", listOf("chore", "errand", "hobby", "shift"))
        assertTrue(WeeklyTestEngine.isValid(en, "en"))
        assertFalse(WeeklyTestEngine.isValid(en, "ko"))
        val built = item(WeeklyTestItem.Kind.BUILD, "Show me the clock once.",
            listOf("Show", "me", "the", "clock", "once."), prompt = "한번 시계 보여줘")
        assertFalse(WeeklyTestEngine.isValid(built, "en"))
    }

    // ── A whole build, from material

    private fun week(now: Long): WeeklyTestEngine.Material {
        val ended = now - 2 * 3_600_000L
        val lines = listOf(
            TurnRole.FLUENT_SELF to "So how did the move go? Did you end up hiring movers?",
            TurnRole.USER to "It was okay. I end up carrying most boxes myself.",
            TurnRole.FLUENT_SELF to "That sounds exhausting. Honestly, next time I'd push back on doing it alone.",
            TurnRole.USER to "Yeah, my back is still sore from it.",
            TurnRole.FLUENT_SELF to "Give yourself a day off. You can always catch up on the unpacking later.",
            TurnRole.USER to "I have to unpack the kitchen first, it's a chore.",
            TurnRole.FLUENT_SELF to "Kitchens are the worst part. Let me walk you through how I did mine.",
            // The week report's quotes, so grammar and upgrade find the lines.
            TurnRole.USER to "Yesterday I went to the flat and the landlord says it's fine.",
            TurnRole.FLUENT_SELF to "That's a relief. Did you sign anything yet?",
            TurnRole.USER to "Not yet. I was very tired after the move.",
            TurnRole.FLUENT_SELF to "Fair enough. And the flat itself?",
            TurnRole.USER to "The flat is good for the price.",
        )
        val turns = lines.map { (r, t) -> Turn(role = r, transcript = t) }
        val session = Session(userId = "u", targetLanguage = "en", startedAt = ended - 900_000, endedAt = ended,
            turns = turns, summary = SessionSummary(
                expressionsOffered = listOf("end up", "push back on", "catch up on", "walk you through"),
                expressionsUsed = listOf("a chore")))
        val cards = listOf(
            DrillCard(sourcePhrase = turns[1].transcript, targetPhrase = "I ended up carrying most of the boxes myself.",
                reason = "Past tense.", createdAt = ended, nextReviewAt = ended + 86_400_000, box = 0,
                sourceSessionId = session.id, sourceTurnId = turns[1].id),
            DrillCard(sourcePhrase = turns[5].transcript, targetPhrase = "I have to unpack the kitchen first. It's such a chore.",
                reason = "Two sentences.", createdAt = ended, nextReviewAt = ended + 86_400_000, box = 0,
                sourceSessionId = session.id, sourceTurnId = turns[5].id),
        )
        return WeeklyTestEngine.Material(
            sessions = listOf(session), studying = listOf("chore", "exhausting"), usedRecently = emptyList(),
            recorded = listOf("thrilling", "soothing", "spare", "errand", "hobby"), cards = cards,
            libraryExpressions = listOf("give it a go", "on the fly"),
            hasAudio = { it.role == TurnRole.FLUENT_SELF },
            graded = { band -> if (band == CefrLevel.B2) listOf("decent", "weary", "drained", "fatigued",
                "awful", "amazing", "brilliant") else emptyList() },
            bookWords = { listOf("chore" to false, "exhausting" to false) },
            coach = coach,
        )
    }

    private val coach = WeekRecap.Coach(
        headline = "Stories in the present tense",
        grammar = listOf(WeekRecap.Coach.Pattern("Past tense drops out halfway through a story",
            listOf(WeekRecap.Coach.Pair("the landlord says it's fine", "the landlord said it was fine")),
            "Once a story starts in the past, every verb stays there.")),
        upgrades = listOf(
            WeekRecap.Coach.Upgrade("very tired", 5, "exhausted", "I was very tired after the move.",
                "I was exhausted after the move.", "One word does the work of two."),
            WeekRecap.Coach.Upgrade("good", 9, "decent", "The flat is good for the price.",
                "The flat is decent for the price.", "Good, not great.")),
    )

    @Test fun aWeekBuildsEveryKindFromItsOwnMaterial() = runBlocking {
        val now = System.currentTimeMillis()
        val test = WeeklyTestEngine.build(week(now), null, "en", CefrLevel.B1, now) { word ->
            mapOf("chore" to "a tedious task", "exhausting" to "making you very tired")[word]
        }
        assertNotNull(test)
        val kinds = test!!.items.map { it.kind }.toSet()
        for (k in WeeklyTestItem.Kind.entries) assertTrue("missing $k", k in kinds)
        // Never opens on the one item that needs the speaker.
        assertNotEquals(WeeklyTestItem.Kind.LISTEN, test.items.first().kind)
        for (i in test.items) {
            when (i.kind) {
                WeeklyTestItem.Kind.MEANING, WeeklyTestItem.Kind.GAP -> {
                    assertEquals(WeeklyTestEngine.CHOICE_COUNT, i.options.size)
                    assertEquals(1, i.options.count { WeeklyTestEngine.isCorrect(i, it) })
                }
                WeeklyTestItem.Kind.BUILD -> assertNotNull(i.cardId)
                WeeklyTestItem.Kind.LISTEN -> assertEquals(
                    WordSplitter.words(i.answer, "en").sorted(), i.options.sorted())
                WeeklyTestItem.Kind.SPEAK -> assertTrue(WordSplitter.count(i.answer, "en") in 4..16)
                WeeklyTestItem.Kind.GRAMMAR -> {
                    assertEquals("Past tense drops out halfway through a story", i.rule)
                    assertEquals("Yesterday I went to the flat and the landlord said it was fine.", i.answer)
                    assertEquals("the landlord says it's fine", i.focus)
                }
                WeeklyTestItem.Kind.UPGRADE -> {
                    assertEquals(WeeklyTestEngine.CHOICE_COUNT, i.options.size)
                    assertEquals(1, i.options.count { WeeklyTestEngine.isCorrect(i, it) })
                    assertNotNull(i.focus)
                    assertTrue(i.prompt.contains(i.focus!!))
                }
            }
        }
        // A gap's blank is the phrase, and its decoys aren't in the sentence.
        test.items.filter { it.kind == WeeklyTestItem.Kind.GAP }.forEach { g ->
            assertTrue(g.prompt.contains(WeeklyTestEngine.BLANK_MARK))
        }
    }

    @Test fun aThinWeekIsNoTest() = runBlocking {
        val now = System.currentTimeMillis()
        val empty = WeeklyTestEngine.Material(emptyList(), emptyList(), emptyList(), emptyList(),
            emptyList(), emptyList(), { false })
        assertNull(WeeklyTestEngine.build(empty, null, "en", CefrLevel.B1, now) { null })
    }

    // ── Schedule

    /** Saturday 10:00. A Wednesday belongs to the Saturday before it. */
    @Test fun everyMomentBelongsToTheLatestOpening() {
        val s = WeeklyTestSchedule(weekday = 7, hour = 10, minute = 0)
        val wednesday = at(2026, 9, 23, 12)
        val opening = dayOf(s.currentOpening(wednesday, berlin))
        assertEquals(19, opening.dayOfMonth); assertEquals(10, opening.hour)
        assertEquals(26, dayOf(s.nextOpening(wednesday, berlin)).dayOfMonth)
        assertEquals(19, dayOf(s.currentOpening(at(2026, 9, 26, 9, 59), berlin)).dayOfMonth)
        assertEquals(26, dayOf(s.currentOpening(at(2026, 9, 26, 10, 0), berlin)).dayOfMonth)
    }

    private fun finished(at: Long, items: List<WeeklyTestItem> = emptyList(), kind: WeeklyTest.Kind? = null) =
        WeeklyTest(targetLanguage = "en", kind = kind, periodStart = at, periodEnd = at, createdAt = at,
            items = items, finishedAt = at)

    @Test fun weekStreakCountsFinishedWeeksBackFromNow() {
        val s = WeeklyTestSchedule(7, 10, 0)
        val now = System.currentTimeMillis()
        val opening = s.currentOpening(now)
        val week = 7 * 86_400_000L
        val tests = listOf(finished(opening - week + 3_600_000), finished(opening - 2 * week + 3_600_000),
            finished(opening - 4 * week + 3_600_000))
        assertEquals(2, WeeklyTestStore.weekStreak(tests, s, now))
        assertEquals(3, WeeklyTestStore.weekStreak(tests + finished(now), s, now))
        assertEquals(0, WeeklyTestStore.weekStreak(emptyList(), s, now))
    }

    private fun paper(items: List<WeeklyTestItem>, wrong: Set<Int>, finishedAt: Long,
                      kind: WeeklyTest.Kind? = null): WeeklyTest =
        WeeklyTest(targetLanguage = "en", kind = kind, periodStart = finishedAt, periodEnd = finishedAt,
            createdAt = finishedAt, items = items, finishedAt = finishedAt,
            answers = items.mapIndexed { i, it -> WeeklyTestAnswer(it.id, "", i !in wrong, finishedAt) })

    /** The weekly paper's retakes span the last few weeks (it absorbed the
     *  monthly paper, iOS 70dd26a9): every distinct miss once, newest first —
     *  and a miss a newer test asked again and got RIGHT never comes back. */
    @Test fun retakesSpanRecentWeeksUntilAnsweredRight() {
        val a = item(WeeklyTestItem.Kind.MEANING, "chore", listOf("chore", "errand", "hobby", "shift"))
        val b = item(WeeklyTestItem.Kind.GAP, "end up", listOf("end up", "push back on", "catch up on", "walk you through"),
            prompt = "Did you ${WeeklyTestEngine.BLANK_MARK} hiring movers?")
        val c = item(WeeklyTestItem.Kind.BUILD, "I really like it", listOf("I", "like", "really", "it", "very"),
            prompt = "I very like it")
        val d = item(WeeklyTestItem.Kind.SPEAK, "Give yourself a day off.")
        val now = System.currentTimeMillis()
        val week1 = paper(listOf(a, b, c), setOf(0, 1, 2), now - 14 * 86_400_000L)
        // Week 2 asked "chore" again and got it right, and missed d.
        val week2 = paper(listOf(item(WeeklyTestItem.Kind.MEANING, "Chore", a.options), d), setOf(1),
            now - 7 * 86_400_000L)
        val items = WeeklyTestEngine.retakes(listOf(week1, week2), WeeklyTestEngine.MAX_RETAKE,
            emptySet(), "en", WeeklyTestRandom("seed"))
        assertEquals(setOf("Give yourself a day off.", "end up", "I really like it"), items.map { it.answer }.toSet())
        assertEquals("Give yourself a day off.", items.first().answer)
        assertTrue(items.all { it.isRetake == true })
        // A stored pick-one listen item comes back as dictation tiles.
        val e = item(WeeklyTestItem.Kind.LISTEN, "Kitchens are the worst part.",
            listOf("Kitchens are the worst part.", "x", "y"))
        val listen = WeeklyTestEngine.retakes(listOf(paper(listOf(e), setOf(0), now)), 5, emptySet(), "en",
            WeeklyTestRandom("seed")).single()
        assertEquals(WordSplitter.words(listen.answer, "en").sorted(), listen.options.sorted())
    }

    /** A monthly paper saved before iOS 70dd26a9 never becomes the weekly's
     *  window anchor (iOS `07170af`). */
    @Test fun monthlyPaperNeverAnchorsTheWeeklyWindow() {
        val now = System.currentTimeMillis()
        val day = 86_400_000L
        val weekly = WeeklyTest(targetLanguage = "en", periodStart = now - 14 * day, periodEnd = now - 7 * day,
            createdAt = now - 7 * day, items = emptyList())
        val monthly = WeeklyTest(targetLanguage = "en", kind = WeeklyTest.Kind.MONTHLY,
            periodStart = now - 30 * day, periodEnd = now - 60_000, createdAt = now - 60_000, items = emptyList())
        assertEquals(weekly.id, WeeklyTestStore.latestWeekly(listOf(monthly, weekly))?.id)
        assertEquals(weekly.id, WeeklyTestStore.latestWeekly(listOf(weekly, monthly))?.id)
        assertNull(WeeklyTestStore.latestWeekly(listOf(monthly)))
        assertEquals(weekly.periodEnd, WeeklyTestEngine.window(weekly, now).first)
        assertEquals(now - WeeklyTestEngine.DEFAULT_WINDOW_MS, WeeklyTestEngine.window(monthly, now).first)
    }

    @Test fun nextItemWalksTheUnanswered() {
        val a = item(WeeklyTestItem.Kind.MEANING, "chore"); val b = item(WeeklyTestItem.Kind.GAP, "end up")
        var t = WeeklyTest(targetLanguage = "en", periodStart = 0, periodEnd = 0, createdAt = 0, items = listOf(a, b))
        assertEquals(a.id, t.nextItem?.id)
        t = t.copy(answers = t.answers + WeeklyTestAnswer(a.id, "chore", true, 0))
        assertEquals(b.id, t.nextItem?.id)
        t = t.copy(answers = t.answers + WeeklyTestAnswer(b.id, "x", false, 0))
        assertNull(t.nextItem)
        assertEquals(1, t.score)
    }

    /** The on-disk shape round-trips (iOS field names, ISO dates). */
    @Test fun storeShapeRoundTrips() {
        val t = paper(listOf(item(WeeklyTestItem.Kind.BUILD, "I really like it", listOf("I", "really"))),
            setOf(0), 1_790_000_000_000, WeeklyTest.Kind.MONTHLY)
        val text = StoreJson.json.encodeToString(WeeklyTest.serializer(), t)
        assertTrue(text.contains("\"kind\": \"monthly\"") || text.contains("\"kind\":\"monthly\""))
        assertTrue(text.contains("\"build\""))
        assertEquals(t, StoreJson.json.decodeFromString(WeeklyTest.serializer(), text))
    }

    // ── Word classes (tables) and meaning decoys

    @Test fun englishTable() {
        assertEquals(setOf(WordClass.VERB), WordClass.classes("abandon", "en"))
        assertEquals(setOf(WordClass.NOUN), WordClass.classes("kitchen", "en"))
        assertEquals(setOf(WordClass.NOUN, WordClass.VERB), WordClass.classes("run", "en"))
        assertEquals(setOf(WordClass.ADVERB), WordClass.classes("quickly", "en"))
        assertEquals(setOf(WordClass.NOUN), WordClass.classes("Kitchen", "en"))
    }

    @Test fun germanTableAndOrthography() {
        assertEquals(setOf(WordClass.NOUN), WordClass.classes("Haus", "de"))
        assertEquals(setOf(WordClass.VERB), WordClass.classes("bitten", "de"))
        assertEquals(setOf(WordClass.ADJECTIVE), WordClass.classes("offen", "de"))
        assertEquals(setOf(WordClass.VERB, WordClass.ADJECTIVE), WordClass.classes("erfahren", "de"))
        assertEquals(setOf(WordClass.VERB), WordClass.classes("unterbrechen", "de"))
        assertEquals(setOf(WordClass.NOUN), WordClass.classes("Zwischenbericht", "de"))
        assertEquals(setOf(WordClass.VERB), WordClass.classes("herumwurschteln", "de"))
        assertEquals(setOf(WordClass.ADJECTIVE), WordClass.classes("knallgelb", "de"))
        assertEquals(setOf(WordClass.ADJECTIVE), WordClass.classes("unausgegoren", "de"))
    }

    @Test fun japaneseTableAndEndings() {
        assertEquals(setOf(WordClass.VERB), WordClass.classes("行く", "ja"))
        assertEquals(setOf(WordClass.NOUN), WordClass.classes("違い", "ja"))
        assertEquals(setOf(WordClass.NA_ADJECTIVE), WordClass.classes("静か", "ja"))
        assertEquals(setOf(WordClass.VERB), WordClass.classes("食べすぎる", "ja"))
        assertEquals(setOf(WordClass.ADJECTIVE), WordClass.classes("うすぐらい", "ja"))
        assertEquals(setOf(WordClass.NOUN), WordClass.classes("ドーナツ", "ja"))
        assertEquals(setOf(WordClass.OTHER), WordClass.classes("お待ちください", "ja"))
        assertEquals(setOf(WordClass.NOUN), WordClass.classes("十一つ", "ja"))
        assertEquals(setOf(WordClass.ADVERB), WordClass.classes("ぺらぺら", "ja"))
        assertEquals(setOf(WordClass.OTHER), WordClass.classes("ぬこう", "ja"))
    }

    @Test fun koreanTableAndDictionaryForm() {
        assertEquals(setOf(WordClass.PREDICATE), WordClass.classes("가다", "ko"))
        assertEquals(setOf(WordClass.OTHER), WordClass.classes("바다", "ko"))
        assertEquals(setOf(WordClass.PREDICATE), WordClass.classes("뿌리내리다", "ko"))
        assertEquals(setOf(WordClass.OTHER), WordClass.classes("김치찌개", "ko"))
        assertEquals(setOf(WordClass.PREDICATE), WordClass.classes("가다", "ko-KR"))
    }

    @Test fun sameClassMatchesAnySharedClass() {
        assertTrue(WordClass.sameClass("run", "house", "en"))
        assertTrue(WordClass.sameClass("run", "decide", "en"))
        assertFalse(WordClass.sameClass("kitchen", "decide", "en"))
        assertTrue(WordClass.sameClass("zzqx", "house", "xx"))
    }

    /** A verb's gloss gets verbs beside it even when the own pool is nouns. */
    @Test fun englishVerbTakesGradedVerbsOverOwnNouns() {
        val decoys = WeeklyTestEngine.meaningDecoys("abandon", listOf("kitchen", "table", "onion", "abandon"),
            listOf("negotiate", "table", "pursue", "chair", "hesitate"), "en",
            WeeklyTestRandom("00000000-0000-0000-0000-000000000007"))
        assertEquals(setOf("negotiate", "pursue", "hesitate"), decoys.toSet())
    }

    @Test fun ownWordsOfTheSameClassLead() {
        val decoys = WeeklyTestEngine.meaningDecoys("decide", listOf("negotiate", "kitchen"),
            listOf("pursue", "recommend", "table"), "en", WeeklyTestRandom("00000000-0000-0000-0000-000000000007"))
        assertEquals(3, decoys.size)
        assertTrue("negotiate" in decoys)
        assertFalse("kitchen" in decoys)
        assertFalse("table" in decoys)
    }

    private fun decoys(word: String, own: List<String>, graded: List<String>, language: String) =
        WeeklyTestEngine.meaningDecoys(word, own, graded, language,
            WeeklyTestRandom("00000000-0000-0000-0000-000000000007")).toSet()

    @Test fun koreanPredicateGetsPredicates() {
        assertEquals(setOf("예쁘다", "먹다", "보다"),
            decoys("가다", listOf("학교", "가끔", "예쁘다"), listOf("먹다", "책", "보다", "친구"), "ko"))
    }

    @Test fun japaneseAdjectiveSkipsDeverbalNouns() {
        assertEquals(setOf("安い", "面白い", "新しい"),
            decoys("高い", listOf("違い", "願い"), listOf("安い", "面白い", "犬", "新しい"), "ja"))
    }

    @Test fun germanAdjectiveGetsAdjectives() {
        assertEquals(setOf("alt", "offen", "langsam"),
            decoys("schnell", listOf("laufen", "Haus"), listOf("alt", "offen", "verstehen", "langsam"), "de"))
    }

    @Test fun fallsBackToOtherClassesRatherThanShort() {
        assertEquals(setOf("학교", "책", "친구"), decoys("가다", listOf("학교"), listOf("책", "친구"), "ko"))
    }

    @Test fun unknownClassKeepsTheOldOrder() {
        assertEquals(setOf("house", "car", "tree"),
            decoys("zzqx", listOf("house", "car", "tree"), listOf("recommend", "table"), "xx"))
    }

    @Test fun bandsAreLevelThenNeighbours() {
        assertEquals(listOf(CefrLevel.B1, CefrLevel.A2, CefrLevel.B2), WeeklyTestEngine.decoyBands(CefrLevel.B1))
        assertEquals(listOf(CefrLevel.A1, CefrLevel.A2), WeeklyTestEngine.decoyBands(CefrLevel.A1))
        assertEquals(listOf(CefrLevel.C2, CefrLevel.C1), WeeklyTestEngine.decoyBands(CefrLevel.C2))
    }

    // ── iOS 1.1.4: words from the books, the report's two kinds, trap tiles

    /** Meaning items come from the week's book Words chapters only — never the
     *  notebook — and unmastered words lead (iOS `36342dd`). */
    @Test fun meaningItemsComeFromTheBooksUnmasteredFirst() = runBlocking {
        val now = System.currentTimeMillis()
        val m = week(now)
        val books = WeeklyTestEngine.Material(m.sessions, studying = listOf("house", "chore"),
            usedRecently = listOf("house"), recorded = m.recorded, cards = emptyList(),
            libraryExpressions = emptyList(), hasAudio = { false },
            bookWords = { listOf("exhausting" to true, "chore" to false, "appreciate" to false) })
        val glosses = mapOf("chore" to "a tedious task", "exhausting" to "making you very tired",
            "appreciate" to "to be grateful", "house" to "a building to live in")
        val test = WeeklyTestEngine.build(books, null, "en", CefrLevel.B1, now) { glosses[it] }
        val words = test!!.items.filter { it.kind == WeeklyTestItem.Kind.MEANING }.map { it.answer }
        assertFalse("house" in words)
        assertEquals(setOf("chore", "appreciate", "exhausting"), words.toSet())
        val noBooks = WeeklyTestEngine.Material(m.sessions, studying = listOf("chore", "exhausting"),
            usedRecently = emptyList(), recorded = m.recorded, cards = m.cards,
            libraryExpressions = m.libraryExpressions, hasAudio = m.hasAudio)
        val plain = WeeklyTestEngine.build(noBooks, null, "en", CefrLevel.B1, now) { glosses[it] }
        assertTrue(plain!!.items.none { it.kind == WeeklyTestItem.Kind.MEANING })
    }

    /** With no report, the profile's recurring mistakes stand in, named in
     *  the learner's language; a mistake not found in this week's lines is
     *  never asked. */
    @Test fun grammarFallsBackToRecurringMistakes() = runBlocking {
        val now = System.currentTimeMillis()
        val m = week(now)
        val fallback = WeeklyTestEngine.Material(m.sessions, m.studying, m.usedRecently, m.recorded, m.cards,
            m.libraryExpressions, m.hasAudio, bookWords = m.bookWords,
            mistakes = listOf(
                LearnerPattern(mistake = "I was very tired", correction = "I was so tired", context = ""),
                LearnerPattern(mistake = "since two years", correction = "for two years", context = "")),
            describeMistake = { p -> if (p.mistake.startsWith("I was")) "intensifiers" to "Use so." else null })
        val test = WeeklyTestEngine.build(fallback, null, "en", CefrLevel.B1, now) { null }
        val grammar = test!!.items.filter { it.kind == WeeklyTestItem.Kind.GRAMMAR }
        assertEquals(1, grammar.size)
        assertEquals("intensifiers", grammar[0].rule)
        assertEquals("I was so tired after the move.", grammar[0].answer)
        assertEquals("Use so.", grammar[0].note)
        assertTrue(test.items.none { it.kind == WeeklyTestItem.Kind.UPGRADE })
    }

    /** A grammar item's tiles are the fixed line plus the learner's replaced
     *  words; those are the traps the screen names (iOS `cf5b08d`). */
    @Test fun decoyTilesAreTheTilesTheAnswerDoesNotUse() {
        val rng = WeeklyTestRandom("00000000-0000-0000-0000-000000000077")
        val answer = "I ended up carrying most of the boxes myself."
        val tiles = WeeklyTestEngine.buildTiles(answer, "I end up carrying most boxes myself.", "en", rng)
        val built = item(WeeklyTestItem.Kind.BUILD, answer, tiles, prompt = "I end up carrying most boxes myself.")
        assertEquals(listOf("end"), WeeklyTestEngine.decoyTiles(built, "en").map(WeeklyTestEngine::tileKey))
        // A repeated word is a multiset: the answer's two "the"s use two tiles.
        val twice = item(WeeklyTestItem.Kind.BUILD, "the cat and the dog",
            listOf("dog", "the", "and", "a", "the", "cat"))
        assertEquals(listOf("a"), WeeklyTestEngine.decoyTiles(twice, "en"))
        val dictation = item(WeeklyTestItem.Kind.LISTEN, "Give yourself a day off.",
            WeeklyTestEngine.dictationTiles("Give yourself a day off.", "en", rng))
        assertTrue(WeeklyTestEngine.decoyTiles(dictation, "en").isEmpty())
    }

    /** The report's kinds are judged like the rest: in the test's language,
     *  and a missed grammar item comes back with its rule and fresh tiles. */
    @Test fun reportKindsValidateAndRetake() {
        val g = WeeklyTestItem(kind = WeeklyTestItem.Kind.GRAMMAR, prompt = "the landlord says it's fine",
            answer = "the landlord said it was fine", options = listOf("the", "landlord", "said", "it",
                "was", "fine", "says"), rule = "Past tense", focus = "says")
        assertTrue(WeeklyTestEngine.isValid(g, "en"))
        assertFalse(WeeklyTestEngine.isValid(g, "ko"))
        val u = WeeklyTestItem(kind = WeeklyTestItem.Kind.UPGRADE, prompt = "어제는 정말 아주 피곤했어.",
            answer = "exhausted", options = listOf("exhausted", "decent", "weary", "drained"), focus = "아주")
        assertFalse(WeeklyTestEngine.isValid(u, "en"))
        val now = System.currentTimeMillis()
        val last = WeeklyTest(targetLanguage = "en", periodStart = now - 7 * 86_400_000L, periodEnd = now,
            createdAt = now, finishedAt = now, items = listOf(g),
            answers = listOf(WeeklyTestAnswer(g.id, "", false, now)))
        val paper = WeeklyTestEngine.retryPaper(last)!!
        assertEquals("Past tense", paper.items[0].rule)
        assertEquals("says", paper.items[0].focus)
        assertEquals(WordSplitter.words(g.answer, "en").map(WeeklyTestEngine::tileKey).sorted(),
            (paper.items[0].options - WeeklyTestEngine.decoyTiles(paper.items[0], "en").toSet())
                .map(WeeklyTestEngine::tileKey).sorted())
    }

    @Test fun foldedRangeIgnoresCaseAndDiacritics() {
        assertEquals(7 until 13, WeeklyTestEngine.foldedRange("Es ist über gut", "UBER g"))
        assertNull(WeeklyTestEngine.foldedRange("nothing here", "landlord"))
    }
}
