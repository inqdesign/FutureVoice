package com.roro.futurevoice.data

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.talk.ScenarioBrief
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Something real the learner is preparing for: an exam on a date, an
 * interview at a company, a presentation, a move (iOS `UpcomingGoal`,
 * a9fbef92, founder: "the exam, when it is; the interview, where it is; all
 * of it in one place, and the tutor builds its content from it").
 * [LearningPurpose] says WHY they learn; this is the dated, named thing, and
 * the tutor bot reads it.
 *
 * Kept in its own file and its own sync kind, never on the persona: an older
 * build that saves the profile re-encodes it without the fields it doesn't
 * know, and the newer `updatedAt` would win, erasing the goals.
 */
@Serializable
data class UpcomingGoal(
    val id: String = StoreJson.newId(),
    val kind: Kind,
    val title: String,
    /** The day it happens. Optional: "someday this year" is still a goal. */
    @Serializable(with = IsoDateMillisSerializer::class)
    val date: Long? = null,
    val place: String = "",
    /** Anything else: the role, the score they need, who will be there. */
    val notes: String = "",
    /** The target language it was made under — an interview is in one
     *  language, and the tutor of another language shouldn't drill it. */
    val language: String,
    @Serializable(with = IsoDateMillisSerializer::class)
    val createdAt: Long = System.currentTimeMillis(),
    @Serializable(with = IsoDateMillisSerializer::class)
    val updatedAt: Long = System.currentTimeMillis(),
    /** A job posting, a CV, an exam's page — read once by the same reader a
     *  Watch scenario's material uses ([com.roro.futurevoice.net.ScenarioBriefEngine]).
     *  The files are never copied: a grant stays here, the bytes stay where
     *  they are (iOS 67cae6a9). */
    val brief: ScenarioBrief? = null,
) {
    @Serializable
    enum class Kind(val raw: String) {
        @SerialName("interview") INTERVIEW("interview"),
        @SerialName("exam") EXAM("exam"),
        @SerialName("presentation") PRESENTATION("presentation"),
        @SerialName("move") MOVE("move"),
        @SerialName("trip") TRIP("trip"),
        @SerialName("other") OTHER("other");

        @get:StringRes val label: Int get() = when (this) {
            INTERVIEW -> R.string.interview
            EXAM -> R.string.exam
            PRESENTATION -> R.string.presentation
            MOVE -> R.string.moving
            TRIP -> R.string.trip
            OTHER -> R.string.something_else
        }

        /** iOS's system tints: purple, orange, teal, green, cyan, blue. */
        val tint: Long get() = when (this) {
            INTERVIEW -> 0xFFAF52DE
            EXAM -> 0xFFFF9500
            PRESENTATION -> 0xFF30B0C7
            MOVE -> 0xFF34C759
            TRIP -> 0xFF32ADE6
            OTHER -> 0xFF007AFF
        }

        /** The purpose this goal is a case of — saving the goal turns it on. */
        val purpose: LearningPurpose? get() = when (this) {
            INTERVIEW -> LearningPurpose.JOB
            EXAM -> LearningPurpose.EXAM
            PRESENTATION -> LearningPurpose.WORK
            MOVE -> LearningPurpose.ABROAD
            TRIP -> LearningPurpose.TRAVEL
            OTHER -> null
        }

        /** The profile's row for a purpose with no goal of this kind yet. */
        @get:StringRes val addPrompt: Int get() = when (this) {
            INTERVIEW -> R.string.add_your_interview
            EXAM -> R.string.add_your_exam
            PRESENTATION -> R.string.add_your_presentation
            MOVE -> R.string.add_your_move
            TRIP -> R.string.add_your_trip
            OTHER -> R.string.add_a_goal
        }

        /** The editor's example title — what kind of line belongs there. */
        @get:StringRes val titlePrompt: Int get() = when (this) {
            INTERVIEW -> R.string.e_g_lufthansa_cabin_crew
            EXAM -> R.string.e_g_ielts_band_7
            PRESENTATION -> R.string.e_g_quarterly_review_with_the_berlin_team
            MOVE -> R.string.e_g_moving_to_munich
            TRIP -> R.string.e_g_two_weeks_in_japan
            OTHER -> R.string.what_are_you_preparing_for
        }

        @get:StringRes val placePrompt: Int get() = when (this) {
            INTERVIEW -> R.string.company_or_place
            EXAM -> R.string.test_centre
            PRESENTATION -> R.string.where_and_for_whom
            MOVE, TRIP, OTHER -> R.string.where
        }
    }

    /** Days from today to the goal's day: 0 = today, negative = past.
     *  Counted here, not with `PromptClock.calendarDays`, which never goes
     *  below 0 — a past goal would never read as past. */
    fun daysLeft(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Int? =
        date?.let {
            ChronoUnit.DAYS.between(
                LocalDate.ofInstant(Instant.ofEpochMilli(now), zone),
                LocalDate.ofInstant(Instant.ofEpochMilli(it), zone),
            ).toInt()
        }

    /** Over once its day has passed. */
    fun isPast(now: Long = System.currentTimeMillis()): Boolean = (daysLeft(now) ?: 0) < 0

    /** "D-12", "D-day". Null without a date or once it is over. */
    fun countdown(c: Context, now: Long = System.currentTimeMillis()): String? {
        val d = daysLeft(now) ?: return null
        if (d < 0) return null
        return if (d == 0) c.getString(R.string.d_day) else "D-$d"
    }

    /** What the reading of the attached material found, as prompt lines.
     *  Empty when nothing is attached or it hasn't been read yet. */
    val materialLines: String
        get() {
            val b = brief ?: return ""
            if (b.readAt == null || !(b.hasContent || b.summary.isNotEmpty())) return ""
            val out = arrayListOf("FROM THEIR OWN MATERIAL (job posting, CV, the exam's page — read from the source):")
            if (b.summary.isNotEmpty()) out += "About: ${b.summary}"
            if (b.counterpartFacts.isNotEmpty()) out += "The other side: " + b.counterpartFacts.joinToString("; ")
            if (b.likelyQuestions.isNotEmpty()) out += "Likely asked: " + b.likelyQuestions.joinToString(" | ")
            if (b.learnerFacts.isNotEmpty()) out += "The learner's side: " + b.learnerFacts.joinToString("; ")
            if (b.keyExpressions.isNotEmpty()) out += "Key expressions: " + b.keyExpressions.joinToString("; ")
            return out.joinToString("\n")
        }

    /** The tutor drill's context: the goal, and what its material is about. */
    val drillBlurb: String
        get() {
            var line = "Preparing for: " + promptLine()
            brief?.summary?.takeIf { it.isNotEmpty() }?.let { line += ". Their material: $it" }
            return line
        }

    /** One plain line for a prompt. */
    fun promptLine(now: Long = System.currentTimeMillis()): String {
        val parts = arrayListOf("${kind.raw}: $title")
        if (place.isNotEmpty()) parts += "at $place"
        if (date != null) {
            val f = SimpleDateFormat("EEE d MMM yyyy", Locale.US)
            val left = daysLeft(now) ?: 0
            parts += "on ${f.format(Date(date))} (${if (left <= 0) "today" else "in $left days"})"
        } else {
            parts += "no date set"
        }
        if (notes.isNotEmpty()) parts += "notes: $notes"
        return parts.joinToString(", ")
    }
}

/**
 * `upcoming_goals.json`, one list for the install (a goal is the learner's,
 * not a language's; each carries its own `language`) — iOS `UpcomingGoalStore`.
 */
object UpcomingGoalStore {
    const val FILENAME = "upcoming_goals.json"

    var goals by mutableStateOf<List<UpcomingGoal>>(emptyList())
        private set
    /** Goals whose material is being read right now (iOS `readingMaterial`). */
    var readingMaterial by mutableStateOf<Set<String>>(emptySet())
    var materialFailed by mutableStateOf<Set<String>>(emptySet())

    private var loaded = false
    private val serializer = ListSerializer(UpcomingGoal.serializer())

    private fun file(c: Context) = File(c.applicationContext.filesDir, FILENAME)

    /** Reads the file once; later calls see the list in memory. */
    fun ensureLoaded(c: Context) {
        if (!loaded) reload(c)
    }

    fun reload(c: Context) {
        loaded = true
        goals = sorted(runCatching {
            file(c).takeIf { it.exists() }?.readText()?.let { StoreJson.json.decodeFromString(serializer, it) }
        }.getOrNull().orEmpty())
    }

    /** The goals still ahead for a target language, soonest first; undated
     *  ones after the dated ones. */
    fun active(c: Context, language: String, now: Long = System.currentTimeMillis()): List<UpcomingGoal> {
        ensureLoaded(c)
        return goals.filter { LanguageCatalog.sameLanguage(it.language, language) && !it.isPast(now) }
    }

    fun goal(c: Context, id: String): UpcomingGoal? {
        ensureLoaded(c)
        return goals.firstOrNull { it.id == id }
    }

    fun save(c: Context, goal: UpcomingGoal) {
        ensureLoaded(c)
        val g = goal.copy(updatedAt = System.currentTimeMillis())
        write(c, goals.filter { it.id != g.id } + g)
        // The goal is a case of a purpose: turn that purpose on, so Talk's
        // chips and the tutor know about it too.
        LearningPurposeStore.cover(c, g.kind)
        Analytics.capture("upcoming_goal_saved", mapOf("kind" to g.kind.raw, "dated" to (g.date != null)))
    }

    private val scope = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.Main.immediate)

    /** [readMaterial] in the background, after the editor has gone. */
    fun readMaterialSoon(c: Context, id: String) {
        val app = c.applicationContext
        scope.launch {
            val persona = runCatching { PersonaStore.shared(app).load() }.getOrNull()
            val native = app.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)
                .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative()
            readMaterial(app, id, persona, native)
        }
    }

    /** Read the goal's attached material, then save what it found. The
     *  learner just saved the goal or opened its page, so they are here. */
    suspend fun readMaterial(c: Context, id: String, persona: com.roro.futurevoice.talk.UserPersona?,
                             nativeLanguage: String) {
        if (id in readingMaterial) return
        val goal = goal(c, id) ?: return
        if (goal.brief?.hasSources != true) return
        readingMaterial = readingMaterial + id
        materialFailed = materialFailed - id
        try {
            val stand = com.roro.futurevoice.talk.Scenario(environment = goal.promptLine(), role = "",
                notes = goal.notes, brief = goal.brief)
            val brief = com.roro.futurevoice.net.ScenarioBriefEngine.read(c, stand, persona,
                targetLanguage = goal.language, nativeLanguage = nativeLanguage)
            val current = goal(c, id) ?: return
            if (current.brief?.sources?.map { it.id } != brief.sources.map { it.id }) return
            save(c, current.copy(brief = brief))
            Analytics.capture("upcoming_goal_material_read", mapOf("sources" to brief.sources.size))
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            materialFailed = materialFailed + id
        } finally {
            readingMaterial = readingMaterial - id
        }
    }

    fun delete(c: Context, id: String) {
        ensureLoaded(c)
        write(c, goals.filter { it.id != id })
    }

    private fun write(c: Context, list: List<UpcomingGoal>) {
        goals = sorted(list)
        runCatching {
            val target = file(c)
            val tmp = File(target.parentFile, target.name + ".tmp")
            tmp.writeText(StoreJson.json.encodeToString(serializer, goals))
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
        StoreEvents.bump()
    }

    fun sorted(list: List<UpcomingGoal>): List<UpcomingGoal> = list.sortedWith { a, b ->
        val x = a.date; val y = b.date
        when {
            x != null && y != null -> x.compareTo(y)
            x != null -> -1
            y != null -> 1
            else -> a.createdAt.compareTo(b.createdAt)
        }
    }
}
