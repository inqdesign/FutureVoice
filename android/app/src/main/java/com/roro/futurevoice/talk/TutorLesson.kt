package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * Tutor mode's lesson (iOS `TutorLesson`, af3c7ffe … bd242766; founder: "not
 * friendly talk — the goal of the call is that they can SAY it, properly,
 * and they keep at it until they nail it").
 *
 * A topic becomes a short CURRICULUM of 3–4 challenges, each one part the
 * learner must be able to say, then a FINAL CHECK where they say the whole
 * thing in one go with nothing on screen ([TutorFinalCheck]). The APP judges
 * every answer and the tutor says it (iOS af32f171):
 *
 * - [TutorPlanner.plan] writes the curriculum (default model).
 * - [TutorJudge.read] decides, after each learner turn, whether the line DID
 *   the current challenge. "Clean" is two witnesses, never the tutor's mood:
 *   the per-turn correction found no fixes, AND this judge says it was done.
 * - [TutorLessonStore] keeps lessons per target language, so a lesson left
 *   halfway is picked up by the next tutor call.
 *
 * The tutor reads the curriculum from the system prompt ([TutorPrompt]),
 * which the app resends whenever a challenge is ticked; each answer is held
 * at the gateway until the app's verdict note answers it.
 */
@Serializable
data class TutorLesson(
    val id: String = StoreJson.newId(),
    /** The topic as the learner would name it — native language (chrome). */
    val title: String,
    /** The same topic in the target language, for the tutor's own lines. */
    val titleTarget: String,
    val language: String,
    val challenges: List<Challenge>,
    @Serializable(with = IsoDateMillisSerializer::class)
    val createdAt: Long,
    @Serializable(with = IsoDateMillisSerializer::class)
    val finishedAt: Long? = null,
    /** The learner asked for another topic (by voice or the strip's menu):
     *  never offered again as "pick up where we left off". */
    @Serializable(with = IsoDateMillisSerializer::class)
    val droppedAt: Long? = null,
    /** Every talk the lesson ran in. */
    val sessionIds: List<String> = emptyList(),
    /** The curriculum topic this lesson is for (iOS `TutorCurriculum`), when
     *  it came from the map. Null for a topic the learner made up — and,
     *  until the map is ported, always. */
    val topicId: String? = null,
    /** The final check, once every challenge is done (iOS 23ce515f, founder
     *  2026-10-28): the screen goes blank and they say it all in their own
     *  words, in one go. Passing it is what finishes the lesson. */
    val check: FinalCheck? = null,
) {
    @Serializable
    data class FinalCheck(
        @Serializable(with = IsoDateMillisSerializer::class)
        val startedAt: Long,
        /** Whole attempts judged. */
        val tries: Int = 0,
        /** "Say it once more" was asked for this attempt — only once. */
        val onceMoreUsed: Boolean = false,
        @Serializable(with = IsoDateMillisSerializer::class)
        val passedAt: Long? = null,
        /** The answer that passed, and the slips named with it. */
        val line: String? = null,
        val slips: List<String> = emptyList(),
    )

    @Serializable
    data class Challenge(
        val id: String = StoreJson.newId(),
        /** What to be able to say, short, native language — the checklist row. */
        val goal: String,
        /** The same, in English, precise enough for the judge and the tutor. */
        val task: String,
        /** One example line that does it, target language, at their level. */
        val example: String,
        @Serializable(with = IsoDateMillisSerializer::class)
        val doneAt: Long? = null,
        /** The learner's line that cleared it — what the summary shows. */
        val line: String? = null,
    )

    val current: Int? get() = challenges.indexOfFirst { it.doneAt == null }.takeIf { it >= 0 }
    val doneCount: Int get() = challenges.count { it.doneAt != null }
    val challengesDone: Boolean get() = challenges.isNotEmpty() && current == null
    /** Finished = the final check passed. Lessons from before the check had
     *  `finishedAt` stamped with their last tick, so they still read done. */
    val isFinished: Boolean get() = finishedAt != null
    /** Every challenge ticked, the check not passed yet. */
    val inFinalCheck: Boolean get() = challengesDone && finishedAt == null

    val record: TutorLessonRecord
        get() = TutorLessonRecord(
            lessonId = id, title = title,
            done = challenges.mapNotNull { c -> c.line?.let { TutorLessonRecord.Done(c.goal, it) } },
            total = challenges.size, finished = isFinished)
}

/** What a talk keeps of its lesson (iOS `Session.tutorLesson`): the lines
 *  that cleared each challenge. Optional on the session, so old rows decode. */
@Serializable
data class TutorLessonRecord(
    val lessonId: String,
    val title: String,
    val done: List<Done>,
    val total: Int,
    val finished: Boolean,
) {
    @Serializable
    data class Done(val goal: String, val line: String)
}

/** `lang/<code>/tutor_lessons.json`. Device-local, like iOS: the talks a
 *  lesson ran in sync; the checklist is this phone's. */
object TutorLessonStore {
    /** An unfinished lesson older than this is not offered again. */
    const val RESUME_DAYS = 21
    private const val KEEP = 30
    private val serializer = ListSerializer(TutorLesson.serializer())

    private fun file(context: Context, language: String) =
        File(LanguageScope.directory(context, language.substringBefore('-')), "tutor_lessons.json")

    fun all(context: Context, language: String): List<TutorLesson> = runCatching {
        StoreJson.json.decodeFromString(serializer, file(context, language).readText())
    }.getOrDefault(emptyList())

    @Synchronized
    fun save(context: Context, lesson: TutorLesson) {
        val list = listOf(lesson) + all(context, lesson.language).filter { it.id != lesson.id }
        runCatching {
            file(context, lesson.language).writeText(StoreJson.json.encodeToString(serializer, list.take(KEEP)))
        }
    }

    /** The newest unfinished lesson, if it is recent enough to pick up. */
    fun resumable(context: Context, language: String, now: Long = System.currentTimeMillis()): TutorLesson? =
        resumable(all(context, language), now)

    internal fun resumable(lessons: List<TutorLesson>, now: Long): TutorLesson? {
        val since = now - RESUME_DAYS * 86_400_000L
        return lessons.firstOrNull { !it.isFinished && it.droppedAt == null && it.createdAt >= since }
    }
}

object TutorPlanner {
    @Serializable
    internal data class Plan(
        val topic: Boolean = false,
        val title: String? = null,
        @SerialName("title_target") val titleTarget: String? = null,
        val challenges: List<Item>? = null,
    ) {
        @Serializable
        data class Item(val goal: String, val task: String, val example: String)
    }

    /** iOS `plan(request:askedWith:…)`'s user message. */
    internal fun content(request: String, askedWith: String?): String =
        askedWith?.let { "The tutor asked: \"$it\"\nThey answered: \"$request\"" }
            ?: "They picked on screen: \"$request\""

    /** iOS `about`: occupation · city, both trimmed, blanks dropped. */
    internal fun about(persona: UserPersona?): String =
        listOf(persona?.occupation, persona?.city)
            .mapNotNull { it?.trim() }.filter { it.isNotEmpty() }.joinToString(" · ")

    /**
     * A curriculum for [request] — a topic the learner picked, or what they
     * said when asked what to practice. Null when it names no topic or the
     * call failed; the tutor then asks again. [askedWith]: the tutor's line
     * the words answered, when they were SAID.
     */
    suspend fun plan(request: String, askedWith: String? = null, targetLanguage: String,
                     nativeLanguage: String, level: CefrLevel, persona: UserPersona?,
                     miss: ((String) -> Unit)? = null): TutorLesson? {
        val system = TutorPrompts.plannerSystem(
            LanguageCatalog.englishName(targetLanguage), LanguageCatalog.englishName(nativeLanguage),
            level, about(persona))
        val content = content(request, askedWith)
        // One retry: now and then the reply is the challenge list alone
        // instead of the object, which decodes to nothing.
        var plan: Plan? = null
        for (i in 0 until 2) {
            if (plan != null) break
            plan = withTimeoutOrNull(20_000) {
                runCatching {
                    GeminiClient(AuthRepository()).sendJson(
                        system = system,
                        messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, content)),
                        serializer = Plan.serializer(),
                        maxTokens = 2000, purpose = "tutor",
                        idempotencyKey = "tutor-plan:${StoreJson.newId()}",
                    )
                }.getOrNull()
            }
        }
        return lesson(plan, targetLanguage, miss = miss)
    }

    /** iOS `plan`'s checks on what came back. */
    internal fun lesson(plan: Plan?, targetLanguage: String, now: Long = System.currentTimeMillis(),
                        miss: ((String) -> Unit)? = null): TutorLesson? {
        // `miss` says why there is no lesson: "no_topic" is the ordinary
        // answer to "hi" or "I don't know", the other two are failures.
        if (plan == null) { miss?.invoke("request_failed"); return null }
        if (!plan.topic) { miss?.invoke("no_topic"); return null }
        val title = plan.title?.trim()?.takeIf { it.isNotEmpty() } ?: run { miss?.invoke("too_few"); return null }
        val items = plan.challenges?.takeIf { it.isNotEmpty() } ?: run { miss?.invoke("too_few"); return null }
        val challenges = items.take(4).mapNotNull { i ->
            val goal = i.goal.trim()
            val task = i.task.trim()
            if (goal.isEmpty() || task.isEmpty()) null
            else TutorLesson.Challenge(goal = goal, task = task, example = i.example.trim())
        }
        if (challenges.size < 2) { miss?.invoke("too_few"); return null }
        val titleTarget = plan.titleTarget?.trim().orEmpty()
        return TutorLesson(title = title, titleTarget = titleTarget.ifEmpty { title },
            language = targetLanguage, challenges = challenges, createdAt = now)
    }
}

/** What the learner wants once a lesson is done (iOS `TutorNext`). */
object TutorNext {
    @Serializable
    /** [AGAIN]: say the passed lesson once more, for practice (the tutor
     *  offers it after a pass with slips). */
    enum class Choice { @SerialName("more") MORE, @SerialName("again") AGAIN, @SerialName("new") NEW, @SerialName("stop") STOP, @SerialName("unclear") UNCLEAR }

    @Serializable
    data class Answer(val choice: Choice, val topic: String? = null)

    suspend fun read(line: String, askedWith: String, lesson: String, suggested: String? = null): Answer? =
        withTimeoutOrNull(10_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = TutorPrompts.nextSystem(lesson, suggested),
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER,
                        "The tutor asked: \"$askedWith\"\nThey answered: \"$line\"")),
                    serializer = Answer.serializer(),
                    model = GeminiClient.Model.FLASH_LITE_31, maxTokens = 120, purpose = "tutor",
                    idempotencyKey = "tutor-next:${StoreJson.newId()}",
                    fastThinking = true,
                )
            }.getOrNull()
        }
}

object TutorJudge {
    @Serializable
    data class Verdict(
        val done: Boolean = false,
        /** They asked to change the topic or stop this lesson. */
        @SerialName("other_topic") val otherTopic: Boolean? = null,
        /** What the line still lacks, in a few English words, for the tutor. */
        @SerialName("missing_note") val missingNote: String? = null,
    ) {
        val wantsOtherTopic: Boolean get() = otherTopic == true
    }

    /** Did [line] do [challenge]? Content only — the correction call judges
     *  the mistakes. Also asked on every try: do they want out of the lesson? */
    suspend fun read(line: String, challenge: TutorLesson.Challenge, targetLanguage: String,
                     askedWith: String): Verdict? =
        withTimeoutOrNull(10_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = TutorPrompts.judgeSystem(LanguageCatalog.englishName(targetLanguage)),
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER,
                        TutorPrompts.judgeContent(challenge.task, challenge.example, askedWith, line))),
                    serializer = Verdict.serializer(),
                    model = GeminiClient.Model.FLASH_LITE_31, maxTokens = 120, purpose = "tutor",
                    idempotencyKey = "tutor-judge:${StoreJson.newId()}",
                    fastThinking = true,
                )
            }.getOrNull()
        }
}

/**
 * The lesson's final check (iOS `TutorFinalCheck`, founder 2026-10-28): every
 * challenge said in one answer, with nothing on screen to lean on. The bar is
 * CONFIDENCE, not perfection — every part said and understood passes, small
 * slips and a little hesitation included — but every slip is named, pass or
 * not, and praise is for a clean answer only. The judge reads content and
 * delivery; the slips are the per-turn correction call's; the outcome is code.
 */
object TutorFinalCheck {
    enum class Outcome(val raw: String) { PASS("pass"), ONCE_MORE("onceMore"), NOT_YET("notYet"), NOT_AN_ATTEMPT("notAnAttempt") }

    @Serializable
    data class Verdict(
        /** They tried to say the whole thing (not one part, a question, a chat). */
        val attempt: Boolean = false,
        /** 1-based challenge numbers their answer left out. */
        val missing: List<Int>? = null,
        /** What was missing or unclear, in English, for the tutor. */
        @SerialName("missing_note") val missingNote: String? = null,
        /** A listener would understand what they mean. */
        val understood: Boolean? = null,
        /** Very shaky: long stalls, restarts, many broken bits. */
        val shaky: Boolean? = null,
        /** Not an attempt: they asked to be SHOWN how the whole thing goes. */
        @SerialName("wants_example") val wantsExample: Boolean? = null,
    )

    /** Not perfect the first time → once more, always; the second try passes
     *  when every part is there and understood. */
    fun outcome(v: Verdict, slips: Int, onceMoreUsed: Boolean): Outcome {
        if (!v.attempt) return Outcome.NOT_AN_ATTEMPT
        if (v.understood == false || !v.missing.isNullOrEmpty()) return Outcome.NOT_YET
        if ((v.shaky == true || slips > 0) && !onceMoreUsed) return Outcome.ONCE_MORE
        return Outcome.PASS
    }

    suspend fun read(line: String, lesson: TutorLesson, askedWith: String, targetLanguage: String): Verdict? {
        val parts = lesson.challenges.withIndex().joinToString("\n") { (i, c) -> "${i + 1}. ${c.task}" }
        return withTimeoutOrNull(15_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = TutorPrompts.finalCheckSystem(LanguageCatalog.englishName(targetLanguage), lesson.titleTarget),
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER,
                        TutorPrompts.finalCheckContent(parts, askedWith, line))),
                    serializer = Verdict.serializer(),
                    maxTokens = 400, purpose = "tutor",
                    idempotencyKey = "tutor-check:${StoreJson.newId()}",
                    fastThinking = true,
                )
            }.getOrNull()
        }
    }
}

/**
 * iOS `ConversationEngine.tutorBlock`'s choice of lesson part and `tutorNow`
 * — the text is [ConversationPrompt]'s (generated); which piece, and the
 * checklist rows, are here.
 */
object TutorPrompt {
    fun block(targetLanguage: String, languageName: String, lesson: TutorLesson?,
              justTicked: Boolean, lastFixes: List<String>, planning: Boolean = false): String {
        val now = lesson?.current
        val lessonPart = when {
            planning && lesson != null -> ConversationPrompt.tutorLessonPlanning(
                if (lesson.isFinished) " — the next round of \"${lesson.titleTarget}\", which they asked for" else "")
            lesson != null && lesson.inFinalCheck -> ConversationPrompt.tutorLessonFinalCheck(
                lesson.titleTarget,
                lesson.challenges.withIndex().joinToString("\n") { (i, c) -> "  ${i + 1}. ${c.task}" })
            lesson != null && lesson.isFinished -> ConversationPrompt.tutorLessonDone(lesson.titleTarget)
            lesson != null && now != null -> {
                val rows = lesson.challenges.withIndex().joinToString("\n") { (i, c) ->
                    val mark = if (c.doneAt != null) "DONE" else if (i == now) "NOW " else "    "
                    "  [$mark] ${i + 1}. ${c.task} — e.g. \"${c.example}\""
                }
                ConversationPrompt.tutorLessonOn(lesson.titleTarget, rows, now,
                    ConversationPrompt.tutorLastFixes(lastFixes))
            }
            else -> ConversationPrompt.TUTOR_NO_TOPIC
        }
        return ConversationPrompt.tutorBlock(targetLanguage, languageName, lessonPart,
            tutorNow(lesson, justTicked && !planning))
    }

    private fun tutorNow(lesson: TutorLesson?, justTicked: Boolean): String {
        if (!justTicked || lesson == null) return ""
        if (lesson.inFinalCheck) return ConversationPrompt.TUTOR_NOW_FINAL_CHECK
        if (lesson.isFinished) return ConversationPrompt.TUTOR_NOW_FINISHED
        val now = lesson.current ?: return ""
        if (now <= 0) return ""
        val next = lesson.challenges[now]
        return ConversationPrompt.tutorNowNext(now, next.task, next.example)
    }
}

/** The app's notes to the tutor (iOS ConversationView's `realtime.nudge` /
 *  `tutorNudge` lines), verbatim. The gateway answers each once nothing is
 *  playing; while a lesson runs, the note IS the reply to the held turn. */
object TutorNudges {
    const val TURNED_ON = "Tutor mode was just turned on. Ask them, in one short question, what they want to be able to say today — they can also pick a topic from the button on their screen."
    const val RESUME = "The learner is back to finish last time's lesson (see TUTOR MODE). Greet them in a few words, say you're picking it up where you left off and which challenge is next, give its example line, and ask them to say it."
    const val RESUME_FINAL_CHECK = "The learner is back for the final check of last time's lesson (see TUTOR MODE). Greet them in a few words, say the only thing left is the final check, and ask them to say it all in their own words, in one go — no example, no hints."
    fun picked(request: String) = "The learner picked a topic on their screen: \"$request\". Say in a few words that this is today's lesson and that you're setting it up — nothing else yet."
    fun planFailed(request: String) = "Setting up the lesson didn't work. Ask them, in one short question, what exactly they want to be able to say about: \"$request\"."
    const val NEXT_ROUND_READY = "The next round is ready (see TUTOR MODE): new challenges, a step further than the last round. Say so in a few words — don't go over the last round again — then start challenge 1: say what it is, give its example line, and ask them to say it about themselves."
    fun nextRoundFailed(title: String) = "Setting up the next round of \"$title\" didn't work. Say so in a few words and ask whether they'd like another topic instead."
    const val READY = "Today's lesson is ready (see TUTOR MODE). In a few words say what it is and that you'll go one step at a time, then start challenge 1: say what it is, give its example line, and ask them to say it about themselves."
    const val SAVED_FINISHED = "The learner tapped to choose another topic. The app is saving the finished lesson in their book. Say so in a few words and ask what they want to practice next — they can also pick a topic from the button on their screen."
    const val DROPPED = "The learner tapped to choose another topic, and the app dropped today's lesson. Say sure in a few words and ask what they want to practice instead — they can also pick a topic from the button on their screen."
    fun more(title: String, done: String) = "More practice on \"$title\" — the next round, one step further. Already done: $done. New challenges only."

    // A challenge (iOS `tutorCheck`).
    const val LEAVE = "They asked to leave this lesson. Agree right away in a few words — never \"let's finish this one first\". If they named what they'd like instead, say that's the new lesson and you're setting it up; otherwise ask what they'd like to practice."
    const val LINE_UNCHECKED = "The app couldn't check that line. Ask them, in a few words, to say it once more."
    fun notYet(what: String, noSlips: Boolean) = "Result: NOT YET. $what Say their line back the right way as ONE sentence (their words, only that fixed)${if (noSlips) ", or give them the example fitted to them" else ""}, and ask them to say it again. Not \"great\", nothing that sounds like it's done."
    const val ONCE_MORE = "Result: ONCE MORE. That was right. Say so in a few words and ask them to say it one more time, so it sticks. Don't move on yet."
    const val DONE_LAST = "Result: DONE — that was the last challenge. In a few words say that's every part, then ask them to say it all now, in their own words, in one go — no example, no list of the parts, no hints. That is the final check."
    fun doneNext(i: Int, n: Int, task: String, example: String) = "Result: DONE — challenge ${i + 1} is checked off. A short \"you got it\", then start challenge ${n + 1}: say what it is (\"$task\"), give its example line (\"$example\") and ask them to say it about themselves."

    // After a lesson (iOS `tutorAfterLesson`).
    const val ONCE_MORE_CLEAN = "Their once-more was clean. Say so warmly in a few words, then ask whether they want more of this topic or another one."
    fun onceMoreNotes(slips: String, missing: String?) = "Their once-more:${if (slips.isEmpty()) "" else " slips $slips."}${missing?.let { " Missing or unclear: $it." } ?: ""} Name each by saying it the right way, briefly — no \"great\". Then ask whether they want more of this topic or another one."
    const val WANTS_MORE = "They want more of this topic. Say great in a few words and that you're setting up the next round, a step further — nothing else yet."
    const val WANTS_NEW = "They want another topic. Say you're saving today's lesson in their book, and ask what they want to practice next — they can also pick one from the button on their screen."
    fun choseTopic(topic: String) = "They chose another topic: \"$topic\". Say you're saving today's lesson in their book and setting that one up — nothing else yet."
    const val WANTS_AGAIN = "They want to say it once more. Ask them to go ahead — the whole thing, in one go, no hints."
    const val WANTS_STOP = "They're done for today. Say goodbye warmly in a few words; the call ends when they hang up. Don't start anything new."
    const val UNCLEAR = "Answer what they said in one short line, then ask again, in other words: say it once more, more of this topic, or another topic?"

    // The final check (iOS `tutorFinalCheckTry`).
    const val ANSWER_UNCHECKED = "The app couldn't check that answer. Ask them, in a few words, to say it all once more, in one go."
    fun showExample(languageName: String, own: String) = "They asked you to show them how the whole thing goes. Show it: say it as ONE natural answer, in $languageName, built from their own lines in this lesson${if (own.isEmpty()) "" else " ($own)"} with any slip fixed — like a model answer, no list of parts. Then ask them to say it themselves now, in one go."
    fun notAnAttempt(slips: String) = "Final check: that was not an attempt at the whole thing (a question, a remark, or one part only).${if (slips.isEmpty()) "" else " Slips in it: $slips — say that line back the right way first."} Answer what they said in a line, give no verdict on the whole, then ask them to say it all, in one go."
    fun checkNotYet(missing: String?, slips: String) = "Final check result: NOT YET. ${missing?.let { "Missing or unclear: $it." } ?: ""}${if (slips.isEmpty()) "" else " Slips: $slips."} Tell them plainly, in a few words, what was missing — no \"great job\", nothing that sounds like a pass. Then practice just that part once: give them the line for it and ask them to say it. After that, ask for the whole thing again, in one go, with no hints."
    fun checkOnceMore(slips: String) = "Final check result: ONCE MORE. Every part was there and you understood it, but it wasn't clean yet.${if (slips.isEmpty()) "" else " Slips: $slips."} Don't say they passed. Say you understood all of it${if (slips.isEmpty()) "" else ", name each slip by saying it the right way, briefly"}, and ask them to say the whole thing once more, in one go${if (slips.isEmpty()) ", a little more smoothly" else ", with those fixed"}. Don't call it great."
    fun passedClean(nextLine: String) = "Final check result: PASSED, nothing to fix. Tell them warmly that they passed — they can say it now, on their own. Then ask whether they want more of this or another topic.$nextLine"
    fun passedWithSlips(slips: String, nextLine: String) = "Final check result: PASSED. They said every part and you understood them. Slips: $slips. Tell them they passed and that you understood all of it, then name each slip in a few words by saying it the right way (\"one small thing: …\"). Don't call it great, perfect or flawless. Then ask whether they'd like to say it once more, or move on.$nextLine"
}
