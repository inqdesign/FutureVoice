package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechGenre
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.UpcomingGoal
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

/**
 * A day of preparation for an upcoming goal (iOS `GoalPrepDay`, 70bb10f4,
 * founder: "if I'm applying to Lufthansa cabin crew, tomorrow's training,
 * reading, analysis and speech should be about THAT"). One call writes the
 * day's reading and the day's model answer together, and only when the
 * learner taps one of them — never ahead of time, never for a day they don't
 * open the app. The tutor drill needs no writing here: the tutor call plans
 * its own lesson from the goal.
 *
 * Material (titles, bodies, the question) is in the target language at the
 * learner's level; summaries are notes in the native language. Cached per
 * goal per day in `goal_prep.json`, device-local like every other generated
 * cache.
 */
@Serializable
data class GoalPrepDay(
    val goalId: String,
    val day: String,
    val language: String,
    val reading: Piece,
    val speech: Piece,
    /** The angle of the day in the native language — also the tutor drill's topic. */
    val focus: String,
    @Serializable(with = IsoDateMillisSerializer::class)
    val createdAt: Long = System.currentTimeMillis(),
) {
    @Serializable
    data class Piece(
        val title: String,
        val summary: String,
        val body: String,
        /** The speech's prompt — the question this answer is for. */
        val question: String? = null,
    )

    val id: String get() = "${goalId.uppercase()}|$day"

    fun script(part: GoalPrep.Part): SpeechScript {
        val p = if (part == GoalPrep.Part.READING) reading else speech
        val summary = listOfNotNull(p.question?.let { "“$it”" }, p.summary.ifEmpty { null })
            .joinToString("\n")
        // A stable id per piece, so its study and looked-up words are found again.
        val h = MessageDigest.getInstance("SHA-256").digest("$id|${part.raw}".toByteArray())
        val bb = ByteBuffer.wrap(h, 0, 16)
        val uuid = UUID(bb.long, bb.long).toString().uppercase()
        return SpeechScript(id = uuid, title = p.title,
            genre = if (part == GoalPrep.Part.READING) SpeechGenre.EXPLAINER else SpeechGenre.BRIEFING,
            topic = focus, body = p.body, summary = summary, language = language, targetSeconds = 0,
            createdAt = createdAt)
    }
}

object GoalPrep {
    enum class Part(val raw: String) { READING("reading"), SPEECH("speech") }

    const val FILENAME = "goal_prep.json"
    private const val KEEP = 60
    private val serializer = ListSerializer(GoalPrepDay.serializer())

    private fun file(c: Context) = File(c.applicationContext.filesDir, FILENAME)

    fun all(c: Context): List<GoalPrepDay> = runCatching {
        file(c).takeIf { it.exists() }?.readText()?.let { StoreJson.json.decodeFromString(serializer, it) }
    }.getOrNull().orEmpty()

    /** Today's set for a goal, if it has been written. */
    fun today(c: Context, goal: UpcomingGoal, now: Long = System.currentTimeMillis()): GoalPrepDay? {
        val day = StudyPlan.dayKey(now)
        return all(c).firstOrNull { it.goalId == goal.id && it.day == day && it.language == goal.language }
    }

    /** Every day written for a goal, newest first. */
    fun days(c: Context, goal: UpcomingGoal): List<GoalPrepDay> =
        all(c).filter { it.goalId == goal.id }.sortedByDescending { it.createdAt }

    private fun save(c: Context, prep: GoalPrepDay) {
        val list = (all(c).filter { it.id != prep.id } + prep).sortedByDescending { it.createdAt }.take(KEEP)
        runCatching { file(c).writeText(StoreJson.json.encodeToString(serializer, list)) }
    }

    /** Today's set, written now if it isn't yet. Throws when the call fails. */
    suspend fun load(c: Context, goal: UpcomingGoal, nativeLanguage: String, level: CefrLevel,
                     persona: UserPersona?, now: Long = System.currentTimeMillis()): GoalPrepDay {
        today(c, goal, now)?.let { return it }
        val earlier = days(c, goal)
        val weak = runCatching {
            LearnerWeakPoints.goalPrepBlock(LearnerWeakPoints.lines(
                com.roro.futurevoice.data.ProfileStore.shared(c).load(goal.language, level.code),
                com.roro.futurevoice.data.SessionStore.shared(c).load(goal.language), now))
        }.getOrDefault("").let { block ->
            val tried = runCatching { lastAttempt(c, goal) }.getOrNull() ?: return@let block
            block + "\n\nWHAT THEY SAID WHEN THEY LAST TRIED THIS (their own words, with mistakes; keep their facts and their story, fix the English)\nQ: ${tried.first}\nA: \"${tried.second}\"\nToday's answer is for this question."
        }
        val r = withTimeout(60_000) {
            GeminiClient(AuthRepository()).sendJson(
                system = system(goal, nativeLanguage, level, persona, earlier, now, weak),
                messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, "Write today's preparation.")),
                serializer = JsonObject.serializer(),
                model = GeminiClient.Model.FLASH_36, maxTokens = 4096, purpose = "goal-prep",
                idempotencyKey = "goal-prep:${goal.id.uppercase()}:${StudyPlan.dayKey(now)}",
            )
        }
        fun str(o: JsonObject?, k: String): String? = (o?.get(k) as? JsonPrimitive)?.contentOrNull
        fun piece(key: String): GoalPrepDay.Piece {
            val o = r[key]?.jsonObject ?: throw IllegalStateException("no $key")
            return GoalPrepDay.Piece(
                title = (str(o, "title") ?: throw IllegalStateException("no title")).trim(),
                summary = (str(o, "summary") ?: "").trim(),
                body = (str(o, "body") ?: throw IllegalStateException("no body")).trim(),
                question = str(o, "question")?.trim()?.ifEmpty { null },
            )
        }
        val focus = r["focus"]?.jsonPrimitive?.contentOrNull ?: throw IllegalStateException("no focus")
        // The model answer is memorized, so it gets a second reader.
        val written = piece("speech")
        val speech = written.copy(body = MaterialCheck.correctedText(written.body, goal.language, "goal-prep"))
        val prep = GoalPrepDay(goalId = goal.id, day = StudyPlan.dayKey(now), language = goal.language,
            reading = piece("reading"), speech = speech, focus = focus.trim())
        withContext(Dispatchers.IO) { save(c, prep) }
        Analytics.capture("goal_prep_made", mapOf("kind" to goal.kind.raw, "day" to earlier.size + 1,
            "days_left" to (goal.daysLeft(now) ?: -1)))
        return prep
    }

    // MARK: Likely questions

    /** What the day itself will most likely ask, with what each one checks.
     *  Written once per goal (again when the goal is edited), when its page
     *  is opened. */
    @Serializable
    data class Question(val text: String, val looksFor: String) {
        val id: String get() = text
    }

    @Serializable
    private data class QuestionSet(
        val goalId: String,
        @Serializable(with = IsoDateMillisSerializer::class) val goalUpdatedAt: Long,
        val questions: List<Question>,
    )

    private val setsSerializer = ListSerializer(QuestionSet.serializer())
    // ── Where each question stands (iOS `GoalPrep.state`) ──

    /** Computed from the lessons on file, never stored. */
    enum class QuestionState { UNTOUCHED, PRACTICING, READY }

    /** A lesson's `topicId` when it practices one question of a goal. Same
     *  string as iOS, since lessons sync. */
    fun topicId(goal: UpcomingGoal, question: String): String {
        val hash = MessageDigest.getInstance("SHA-256").digest(question.toByteArray()).take(4)
            .joinToString("") { "%02x".format(it) }
        return "goal:${goal.id.uppercase()}:$hash"
    }

    fun state(question: String, goal: UpcomingGoal, lessons: List<TutorLesson>): QuestionState {
        val id = topicId(goal, question)
        val mine = lessons.filter { it.topicId == id }
        if (mine.any { it.check?.passedAt != null }) return QuestionState.READY
        return if (mine.any { it.droppedAt == null }) QuestionState.PRACTICING else QuestionState.UNTOUCHED
    }

    private const val MIN_ATTEMPT_WORDS = 8

    /** The question they tried last and haven't got yet, with what they said. */
    private suspend fun lastAttempt(c: Context, goal: UpcomingGoal): Pair<String, String>? {
        val questions = cachedQuestions(c, goal) ?: return null
        val lessons = TutorLessonStore.all(c, goal.language).sortedByDescending { it.createdAt }
        val sessions = com.roro.futurevoice.data.SessionStore.shared(c).load(goal.language)
        for (lesson in lessons) {
            val q = questions.firstOrNull { topicId(goal, it.text) == lesson.topicId } ?: continue
            if (state(q.text, goal, lessons) != QuestionState.PRACTICING) continue
            val turns = sessions.filter { it.id in lesson.sessionIds }.flatMap { it.turns }.filter { it.role == TurnRole.USER }
            val said = turns.lastOrNull { it.tutorRole == TutorTurnRole.CHECK }?.transcript
                ?: turns.maxByOrNull { it.transcript.length }?.transcript
            if (said != null && com.roro.futurevoice.data.WordSplitter.count(said, goal.language) >= MIN_ATTEMPT_WORDS) return q.text to said
        }
        return null
    }

    private fun questionsFile(c: Context) = File(c.applicationContext.filesDir, "goal_questions.json")

    private fun questionSets(c: Context): List<QuestionSet> = runCatching {
        questionsFile(c).takeIf { it.exists() }?.readText()?.let { StoreJson.json.decodeFromString(setsSerializer, it) }
    }.getOrNull().orEmpty()

    fun cachedQuestions(c: Context, goal: UpcomingGoal): List<Question>? =
        questionSets(c).firstOrNull {
            // Whole seconds: the file's ISO dates drop the fraction the goal
            // in memory still has (iOS 67cae6a9).
            it.goalId == goal.id && it.goalUpdatedAt / 1000 == goal.updatedAt / 1000
        }?.questions

    suspend fun questions(c: Context, goal: UpcomingGoal, nativeLanguage: String, level: CefrLevel): List<Question> {
        cachedQuestions(c, goal)?.let { return it }
        val r = withTimeout(45_000) {
            GeminiClient(AuthRepository()).sendJson(
                system = GoalPrepPrompts.questionsSystem(
                    target = LanguageCatalog.englishName(goal.language),
                    native = LanguageCatalog.englishName(nativeLanguage),
                    level = level.code.uppercase(),
                    promptLine = goal.promptLine(),
                    materialLines = goal.materialLines,
                    korean = GoalPrepPrompts.questionsKorean(nativeLanguage)),
                messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, "List the likely questions.")),
                serializer = JsonObject.serializer(),
                model = GeminiClient.Model.FLASH_36, maxTokens = 2048, purpose = "goal-prep",
                idempotencyKey = "goal-questions:${goal.id.uppercase()}:${goal.updatedAt / 1000}",
            )
        }
        // An object as asked, or now and then a bare string (measured: one
        // run in two) — kept either way, without its note.
        val raw = r["questions"] as? kotlinx.serialization.json.JsonArray ?: throw IllegalStateException("no questions")
        val list = raw.mapNotNull { e ->
            when (e) {
                is JsonPrimitive -> e.contentOrNull?.let { Question(it.trim(), "") }
                is JsonObject -> {
                    val q = (e["question"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                    Question(q.trim(), ((e["looks_for"] as? JsonPrimitive)?.contentOrNull ?: "").trim())
                }
                else -> null
            }
        }.filter { it.text.isNotEmpty() }
        withContext(Dispatchers.IO) {
            val sets = questionSets(c).filter { it.goalId != goal.id } + QuestionSet(goal.id, goal.updatedAt, list)
            runCatching { questionsFile(c).writeText(StoreJson.json.encodeToString(setsSerializer, sets.takeLast(20))) }
        }
        return list
    }

    // MARK: Prompt

    /** Where the preparation is: early days build knowledge and words, the
     *  last days rehearse the real thing (iOS `GoalPrep.phase`). */
    fun phase(goal: UpcomingGoal, now: Long): String = GoalPrepPrompts.phase(goal.daysLeft(now))

    /** iOS `GoalPrep.system`: the learner's facts and the days already done
     *  are built here (pinned by gen-goal-prep-prompts.py), the text is lifted. */
    private fun system(goal: UpcomingGoal, nativeLanguage: String, level: CefrLevel, persona: UserPersona?,
                       earlier: List<GoalPrepDay>, now: Long, weak: String = ""): String {
        val about = ArrayList<String>()
        if (persona != null) {
            if (persona.occupation.isNotEmpty()) about += "Work: ${persona.occupation}"
            val place = listOf(persona.city, persona.country).filter { it.isNotEmpty() }.joinToString(", ")
            if (place.isNotEmpty()) about += "Lives in $place"
            if (persona.interests.isNotEmpty()) about += "Interests: ${persona.interests.joinToString(", ")}"
            for (n in persona.currentNotes(now).takeLast(8)) about += n.text
        }
        // The goal's notes are the learner's own words about THIS day: an
        // experience they want to tell is theirs to use in the answer, and
        // the part they dread is where the days should go (iOS 333b3ee6).
        if (goal.notes.isNotEmpty()) about += "About this goal, in their words: ${goal.notes}"
        if (weak.isNotEmpty()) about += weak
        val done = earlier.take(10).map {
            "- ${it.day}: ${it.focus} (reading \"${it.reading.title}\", answer \"${it.speech.title}\")"
        }
        return GoalPrepPrompts.daySystem(
            target = LanguageCatalog.englishName(goal.language),
            native = LanguageCatalog.englishName(nativeLanguage),
            level = level.code.uppercase(),
            promptLine = goal.promptLine(now),
            phase = phase(goal, now),
            materialLines = goal.materialLines,
            about = about, done = done,
            words = GoalPrepPrompts.words(level),
            korean = GoalPrepPrompts.dayKorean(nativeLanguage),
        )
    }
}
