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
 * A topic becomes a short CURRICULUM of 3–4 challenges, each one thing the
 * learner must be able to say, the last one usually the whole thing in one
 * go. The tutor walks them in order and stays on a challenge until it comes
 * out clean:
 *
 * - [TutorPlanner.plan] writes the curriculum (default model).
 * - [TutorJudge.read] decides, after each learner turn, whether the line DID
 *   the current challenge. "Clean" is two witnesses, never the tutor's mood:
 *   the per-turn correction found no fixes, AND this judge says it was done.
 * - [TutorLessonStore] keeps lessons per target language, so a lesson left
 *   halfway is picked up by the next tutor call.
 *
 * The tutor reads the curriculum from the system prompt ([TutorPrompt]),
 * which the app resends whenever a challenge is ticked.
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
) {
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
    val isFinished: Boolean get() = finishedAt != null || (challenges.isNotEmpty() && current == null)

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
                     nativeLanguage: String, level: CefrLevel, persona: UserPersona?): TutorLesson? {
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
        return lesson(plan, targetLanguage)
    }

    /** iOS `plan`'s checks on what came back. */
    internal fun lesson(plan: Plan?, targetLanguage: String, now: Long = System.currentTimeMillis()): TutorLesson? {
        if (plan == null || !plan.topic) return null
        val title = plan.title?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val items = plan.challenges?.takeIf { it.isNotEmpty() } ?: return null
        val challenges = items.take(4).mapNotNull { i ->
            val goal = i.goal.trim()
            val task = i.task.trim()
            if (goal.isEmpty() || task.isEmpty()) null
            else TutorLesson.Challenge(goal = goal, task = task, example = i.example.trim())
        }
        if (challenges.size < 2) return null
        val titleTarget = plan.titleTarget?.trim().orEmpty()
        return TutorLesson(title = title, titleTarget = titleTarget.ifEmpty { title },
            language = targetLanguage, challenges = challenges, createdAt = now)
    }
}

/** What the learner wants once a lesson is done (iOS `TutorNext`). */
object TutorNext {
    @Serializable
    enum class Choice { @SerialName("more") MORE, @SerialName("new") NEW, @SerialName("stop") STOP, @SerialName("unclear") UNCLEAR }

    @Serializable
    data class Answer(val choice: Choice, val topic: String? = null)

    suspend fun read(line: String, askedWith: String, lesson: String): Answer? =
        withTimeoutOrNull(10_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = TutorPrompts.nextSystem(lesson),
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
 * iOS `ConversationEngine.tutorBlock`'s choice of lesson part and `tutorNow`
 * — the text is [ConversationPrompt]'s (generated); which piece, and the
 * checklist rows, are here.
 */
object TutorPrompt {
    fun block(targetLanguage: String, languageName: String, lesson: TutorLesson?,
              justTicked: Boolean, lastFixes: List<String>): String {
        val now = lesson?.current
        val lessonPart = when {
            lesson != null && lesson.isFinished -> ConversationPrompt.tutorLessonDone(
                lesson.titleTarget, lesson.challenges.lastOrNull()?.task?.lowercase() ?: "do it")
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
        return ConversationPrompt.tutorBlock(targetLanguage, languageName, lessonPart, tutorNow(lesson, justTicked))
    }

    private fun tutorNow(lesson: TutorLesson?, justTicked: Boolean): String {
        if (!justTicked || lesson == null) return ""
        if (lesson.isFinished) return ConversationPrompt.TUTOR_NOW_FINISHED
        val now = lesson.current ?: return ""
        if (now <= 0) return ""
        val next = lesson.challenges[now]
        return ConversationPrompt.tutorNowNext(now, next.task, next.example)
    }
}

/** The app's notes to the tutor (iOS ConversationView's `realtime.nudge`
 *  lines), verbatim. The gateway answers each once nothing is playing. */
object TutorNudges {
    const val TURNED_ON = "Tutor mode was just turned on. Ask them, in one short question, what they want to be able to say today — they can also pick a topic from the button on their screen."
    const val RESUME = "The learner is back to finish last time's lesson (see TUTOR MODE). Greet them in a few words, say you're picking it up where you left off and which challenge is next, give its example line, and ask them to say it."
    fun picked(request: String) = "The learner picked a topic on their screen: \"$request\". Say in a few words that this is today's lesson and that you're setting it up — nothing else yet."
    fun planFailed(request: String) = "Setting up the lesson didn't work. Ask them, in one short question, what exactly they want to be able to say about: \"$request\"."
    const val READY = "Today's lesson is ready (see TUTOR MODE). In a few words say what it is and that you'll go one step at a time, then start challenge 1: say what it is, give its example line, and ask them to say it about themselves."
    const val SAVED_FINISHED = "The learner tapped to choose another topic. The app is saving the finished lesson in their book. Say so in a few words and ask what they want to practice next — they can also pick a topic from the button on their screen."
    const val DROPPED = "The learner tapped to choose another topic, and the app dropped today's lesson. Say sure in a few words and ask what they want to practice instead — they can also pick a topic from the button on their screen."
    fun more(title: String, done: String) = "More practice on \"$title\" — the next round, one step further. Already done: $done. New challenges only."
}
