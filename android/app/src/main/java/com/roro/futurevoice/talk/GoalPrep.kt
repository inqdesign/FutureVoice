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
        val r = withTimeout(60_000) {
            GeminiClient(AuthRepository()).sendJson(
                system = system(goal, nativeLanguage, level, persona, earlier, now),
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
        val prep = GoalPrepDay(goalId = goal.id, day = StudyPlan.dayKey(now), language = goal.language,
            reading = piece("reading"), speech = piece("speech"), focus = focus.trim())
        withContext(Dispatchers.IO) { save(c, prep) }
        Analytics.capture("goal_prep_made", mapOf("kind" to goal.kind.raw, "day" to earlier.size + 1,
            "days_left" to (goal.daysLeft(now) ?: -1)))
        return prep
    }

    // MARK: Prompt

    /** Where the preparation is: early days build knowledge and words, the
     *  last days rehearse the real thing (iOS `GoalPrep.phase`). */
    fun phase(goal: UpcomingGoal, now: Long): String = GoalPrepPrompts.phase(goal.daysLeft(now))

    /** iOS `GoalPrep.system`: the learner's facts and the days already done
     *  are built here (pinned by gen-goal-prep-prompts.py), the text is lifted. */
    private fun system(goal: UpcomingGoal, nativeLanguage: String, level: CefrLevel, persona: UserPersona?,
                       earlier: List<GoalPrepDay>, now: Long): String {
        val about = ArrayList<String>()
        if (persona != null) {
            if (persona.occupation.isNotEmpty()) about += "Work: ${persona.occupation}"
            val place = listOf(persona.city, persona.country).filter { it.isNotEmpty() }.joinToString(", ")
            if (place.isNotEmpty()) about += "Lives in $place"
            if (persona.interests.isNotEmpty()) about += "Interests: ${persona.interests.joinToString(", ")}"
            for (n in persona.currentNotes(now).takeLast(8)) about += n.text
        }
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
