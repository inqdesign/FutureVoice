package com.roro.futurevoice.talk

import android.content.Context
import android.content.res.Resources
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyPlanStore
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.data.UpcomingGoalStore
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.WeekRecapStore
import com.roro.futurevoice.data.WeeklyReportStore
import com.roro.futurevoice.data.WeeklyTestStore
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.text.DateFormatSymbols
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * The tutor chat as an AGENT (iOS `TutorAgent`, 57ba9c6f, founder: "it really
 * needs to feel like an agent… understand the entire app and guide the
 * learner through it, whatever they ask"). Three parts, all on the phone
 * because the practice lives on the phone:
 *
 * - **The manual** ([TutorAgentPrompts.MANUAL]): what every part of the app
 *   is FOR and when to suggest it.
 * - **Lookups** ([TutorTools]): the model asks for what it needs and the app
 *   answers from the stores, up to [MAX_ROUNDS] times, before it writes the
 *   reply — a JSON protocol on the ordinary `sendJson`, no deploy.
 * - **Buttons** ([TutorAction]): up to two under a reply, each one OPENS
 *   something. Nothing the tutor hands out changes the learner's data.
 *
 * The prompt text is lifted from iOS by scripts/android/gen-tutor-agent-prompts.py.
 */
object TutorAgent {
    /** Lookup rounds before the reply must be written. */
    const val MAX_ROUNDS = 3
}

// MARK: - Buttons

/** One button under a tutor reply. Decoded leniently: an unknown type or an
 *  id that isn't on the phone is dropped, never shown as a dead button. */
@Serializable
data class TutorAction(
    val type: Kind,
    val topic: String? = null,
    val id: String? = null,
    val text: String? = null,
    val label: String? = null,
) {
    @Serializable
    enum class Kind(val raw: String) {
        @SerialName("talk") TALK("talk"),
        @SerialName("lesson") LESSON("lesson"),
        @SerialName("book") BOOK("book"),
        @SerialName("goal") GOAL("goal"),
        @SerialName("goalReading") GOAL_READING("goalReading"),
        @SerialName("goalAnswer") GOAL_ANSWER("goalAnswer"),
        @SerialName("word") WORD("word"),
        @SerialName("expression") EXPRESSION("expression"),
        @SerialName("review") REVIEW("review"),
        @SerialName("shadow") SHADOW("shadow"),
        @SerialName("sayItAgain") SAY_IT_AGAIN("sayItAgain"),
        @SerialName("listen") LISTEN("listen"),
        @SerialName("speech") SPEECH("speech"),
        @SerialName("test") TEST("test"),
        @SerialName("quiz") QUIZ("quiz"),
        @SerialName("routine") ROUTINE("routine"),
        @SerialName("settings") SETTINGS("settings"),
        @SerialName("purposes") PURPOSES("purposes"),
    }

    companion object {
        /** iOS `TutorAction(from:)`: an unknown type is no button; every
         *  string field is trimmed, an empty one is absent. */
        fun decode(e: JsonElement): TutorAction? {
            val o = e as? JsonObject ?: return null
            val raw = (o["type"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            val kind = Kind.entries.firstOrNull { it.raw == raw } ?: return null
            fun str(k: String): String? =
                (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.ifEmpty { null }
            return TutorAction(kind, topic = str("topic"), id = str("id"), text = str("text"), label = str("label"))
        }
    }

    /** The button's words: the model's own short label when it gave one. */
    fun title(res: Resources): String {
        label?.let { if (it.codePointCount(0, it.length) <= 28) return it }
        return when (type) {
            Kind.TALK -> res.getString(if (topic == null) R.string.start_a_talk else R.string.talk_about_this)
            Kind.LESSON -> res.getString(R.string.practise_it_with_the_tutor)
            Kind.BOOK -> res.getString(R.string.open_the_book)
            Kind.GOAL -> res.getString(R.string.open_the_goal)
            Kind.GOAL_READING -> res.getString(R.string.today_s_reading)
            Kind.GOAL_ANSWER -> res.getString(R.string.model_answer)
            Kind.WORD -> text ?: res.getString(R.string.open_the_word)
            Kind.EXPRESSION -> text ?: res.getString(R.string.open_the_expression)
            Kind.REVIEW -> startTitle(res, StudyPlan.Kind.REVIEW)
            Kind.SHADOW -> startTitle(res, StudyPlan.Kind.SHADOW)
            Kind.SAY_IT_AGAIN -> startTitle(res, StudyPlan.Kind.SAY_IT_AGAIN)
            Kind.LISTEN -> startTitle(res, StudyPlan.Kind.LISTEN)
            Kind.SPEECH -> startTitle(res, StudyPlan.Kind.SPEECH)
            Kind.TEST -> startTitle(res, StudyPlan.Kind.TEST)
            Kind.QUIZ -> res.getString(R.string.quick_quiz)
            Kind.ROUTINE -> res.getString(R.string.my_routine)
            Kind.SETTINGS -> res.getString(R.string.call_settings)
            Kind.PURPOSES -> res.getString(R.string.why_are_you_learning)
        }
    }

    /** Kept only if what it points at exists on this phone. */
    suspend fun isValid(c: Context): Boolean {
        val language = LanguageScope.active(c)
        return when (type) {
            Kind.TALK -> true
            Kind.LESSON -> topic != null
            Kind.BOOK -> {
                val id = id ?: return false
                runCatching { SessionStore.shared(c).load(language) }.getOrDefault(emptyList())
                    .any { it.id.equals(id, ignoreCase = true) } ||
                    runCatching { ScenarioStore.shared(c).load(language) }.getOrDefault(emptyList())
                        .any { it.id.equals(id, ignoreCase = true) }
            }
            Kind.GOAL, Kind.GOAL_READING, Kind.GOAL_ANSWER -> {
                val id = id ?: return false
                UpcomingGoalStore.ensureLoaded(c)
                UpcomingGoalStore.goals.any { it.id.equals(id, ignoreCase = true) }
            }
            // A card the notebook doesn't have opens an empty page.
            Kind.WORD -> {
                val text = text ?: return false
                val v = VocabStore.shared(c)
                val key = VocabLemmas.lemma(text, language)
                v.isStudying(key, language) || v.state(key, language) != null
            }
            Kind.EXPRESSION -> {
                val text = text ?: return false
                val v = VocabStore.shared(c)
                v.isStudyingExpression(text, language) || v.isKnownExpression(text, language) ||
                    v.hasUsedExpression(text, language)
            }
            else -> true
        }
    }

    private fun startTitle(res: Resources, kind: StudyPlan.Kind): String = res.getString(when (kind) {
        StudyPlan.Kind.TALK -> R.string.start_a_talk
        StudyPlan.Kind.REVIEW, StudyPlan.Kind.WORDS, StudyPlan.Kind.EXPRESSIONS -> R.string.start_review
        StudyPlan.Kind.SHADOW -> R.string.start_shadowing
        StudyPlan.Kind.SAY_IT_AGAIN -> R.string.say_it_again
        StudyPlan.Kind.LISTEN -> R.string.listen
        StudyPlan.Kind.SPEECH -> R.string.open_speech
        StudyPlan.Kind.TEST -> R.string.take_the_test
    })
}

// MARK: - Lookups

/**
 * What the tutor can read (iOS `TutorTools`), each a short plain-text answer
 * from the stores every screen already reads. Ids are printed so a button
 * can point at them. Hand-ported; gen-tutor-agent-prompts.py fails the day
 * the Swift of any of these changes.
 */
object TutorTools {
    data class Call(val tool: String, val args: Map<String, String> = emptyMap()) {
        fun arg(k: String): String? = args[k]?.trim()?.ifEmpty { null }

        companion object {
            /** Args arrive as strings or numbers; both are read as text. */
            fun decode(e: JsonElement): Call? {
                val o = e as? JsonObject ?: return null
                val tool = (o["tool"] as? JsonPrimitive)?.contentOrNull ?: return null
                val args = (o["args"] as? JsonObject)?.mapValues { (_, v) ->
                    (v as? JsonPrimitive)?.let { p ->
                        if (p.isString) p.content
                        else p.content.toLongOrNull()?.toString() ?: p.content
                    } ?: ""
                } ?: emptyMap()
                return Call(tool, args)
            }
        }
    }

    /** The learner the tools read for. */
    data class Learner(val targetLanguage: String, val nativeLanguage: String, val level: CefrLevel)

    /** The "thinking" line shown while a lookup runs. */
    fun progressLine(res: Resources, call: Call): String = res.getString(when (call.tool) {
        "talks" -> R.string.looking_through_your_talks
        "talk" -> R.string.reading_that_talk
        "search" -> R.string.searching_what_you_ve_said
        "mistakes" -> R.string.going_over_your_mistakes
        "notebook" -> R.string.opening_your_notebook
        "cards" -> R.string.checking_your_cards
        "progress" -> R.string.looking_at_your_progress
        "goals" -> R.string.reading_your_goals
        "routine" -> R.string.checking_your_routine
        "scenarios" -> R.string.looking_at_your_scenarios
        else -> R.string.thinking
    })

    suspend fun run(c: Context, call: Call, learner: Learner, now: Long = System.currentTimeMillis()): String {
        val out = when (call.tool) {
            "talks" -> talks(c, call.arg("days")?.toIntOrNull() ?: 30, now)
            "talk" -> talk(c, call.arg("id"))
            "search" -> search(c, call.arg("text"))
            "mistakes" -> mistakes(c, learner, now)
            "notebook" -> notebook(c)
            "cards" -> cards(c, now)
            "progress" -> progress(c, learner)
            "goals" -> goals(c, learner, now)
            "routine" -> routine(c, now)
            "scenarios" -> scenarios(c)
            else -> "Unknown tool \"${call.tool}\"."
        }
        // A lookup is context for one answer; a runaway one would crowd the
        // question out of the window.
        return "[${call.tool}]\n" + out.take(6000)
    }

    // MARK: Tools

    private fun day(at: Long): String = SimpleDateFormat("EEE d MMM", Locale.US).format(Date(at))

    private suspend fun finishedTalks(c: Context): List<Session> =
        runCatching { SessionStore.shared(c).load(LanguageScope.active(c)) }.getOrDefault(emptyList())
            .filter { it.endedAt != null && it.archivedAt == null }
            .sortedByDescending { it.startedAt }

    private fun title(s: Session): String = s.displayTitle ?: "Conversation"

    private fun kind(s: Session): String {
        if (s.tutorLesson != null) return "tutor lesson"
        if (s.counterpartId != null) return "call with a person"
        return when (s.origin ?: SessionOrigin.FREE) {
            SessionOrigin.FREE -> "free talk"
            SessionOrigin.NEWS -> "news talk"
            SessionOrigin.SCENARIO -> "scenario talk"
        }
    }

    private fun fixes(s: Session): List<TurnFix> = s.turns.filter { it.isEvidence }.flatMap { it.suggestion?.fixes ?: emptyList() }

    suspend fun talks(c: Context, days: Int, now: Long): String {
        val since = now - days.coerceIn(1, 365) * 86_400_000L
        val list = finishedTalks(c).filter { it.startedAt >= since }
        if (list.isEmpty()) return "No talks in the last $days days."
        return list.take(40).joinToString("\n") { s ->
            val said = s.turns.filter { it.isEvidence }
            val mins = (((s.endedAt ?: s.startedAt) - s.startedAt) / 60_000.0).roundToInt()
            "- id ${s.id.uppercase()} · ${day(s.startedAt)} · \"${title(s)}\" · " +
                "${kind(s)} · $mins min · they spoke ${said.size}× · ${fixes(s).size} corrections"
        }
    }

    suspend fun talk(c: Context, id: String?): String {
        val s = id?.let { i ->
            runCatching { SessionStore.shared(c).load(LanguageScope.active(c)) }.getOrDefault(emptyList())
                .firstOrNull { it.id.equals(i, ignoreCase = true) }
        } ?: return "No talk with that id. Use talks to find one."
        val lines = arrayListOf("Talk ${day(s.startedAt)}: \"${title(s)}\" (${kind(s)})")
        s.summary?.let { sum ->
            if (sum.overallNote.isNotEmpty()) lines += "Note written after it: ${sum.overallNote}"
            sum.scorecard?.let { sc ->
                lines += "Scores: vocabulary ${sc.vocabulary.score}, grammar ${sc.grammar.score}, " +
                    "expressiveness ${sc.expressiveness.score}, fluency ${sc.fluency.score}" +
                    (sc.cefrLevel?.let { ", read as ${it.uppercase()}" } ?: "")
            }
            if (sum.expressionsOffered.isNotEmpty()) {
                lines += "Expressions the fluent self used for them to learn: " + sum.expressionsOffered.joinToString("; ")
            }
            if (sum.expressionsUsed.isNotEmpty()) {
                lines += "Expressions they used well: " + sum.expressionsUsed.joinToString("; ")
            }
        }
        lines += "The conversation (THEM = the learner, FS = fluent self / the other side):"
        var budget = 3500
        for (t in s.turns) {
            if (t.transcript.isEmpty()) continue
            val who = if (t.role == TurnRole.USER) "THEM" else "FS"
            var line = "$who: ${t.transcript.take(300)}"
            val fx = t.suggestion?.fixes
            if (t.role == TurnRole.USER && !fx.isNullOrEmpty()) {
                line += "\n   corrections: " + fx.joinToString("; ") { "\"${it.was}\" → \"${it.now}\"" }
            }
            budget -= line.length
            if (budget < 0) { lines += "… (rest cut)"; break }
            lines += line
        }
        return lines.joinToString("\n")
    }

    suspend fun search(c: Context, text: String?): String {
        val q = text?.lowercase()
        if (q == null || q.length < 2) return "Give a text to search for."
        val hits = ArrayList<String>()
        outer@ for (s in finishedTalks(c)) {
            for (t in s.turns) {
                if (t.role != TurnRole.USER || !t.transcript.lowercase().contains(q)) continue
                hits += "- ${day(s.startedAt)} · talk ${s.id.uppercase()}: \"${t.transcript.take(200)}\""
                if (hits.size >= 20) break@outer
            }
        }
        return if (hits.isEmpty()) "They never said \"${text}\" in a talk." else hits.joinToString("\n")
    }

    suspend fun mistakes(c: Context, learner: Learner, now: Long): String {
        val sessions = finishedTalks(c)
        val profile = runCatching {
            com.roro.futurevoice.data.ProfileStore.shared(c).load(learner.targetLanguage, learner.level.code)
        }.getOrNull()
        val lines = ArrayList<String>()
        val candidates = profile?.let { GrammarFocus.candidates(it, sessions, now) } ?: emptyList()
        if (candidates.isNotEmpty()) {
            lines += "Recurring, with evidence in several talks:"
            for ((p, talks) in candidates.take(6)) {
                lines += "- \"${p.mistake}\" → \"${p.correction}\" (${p.context}), in $talks talks"
            }
        }
        val others = (profile?.recurringMistakes ?: emptyList())
            .filter { m -> candidates.none { it.first.mistake == m.mistake } }
            .sortedByDescending { it.lastSeenAt }.take(6)
        if (others.isNotEmpty()) {
            lines += "Seen before:"
            for (m in others) lines += "- \"${m.mistake}\" → \"${m.correction}\" (${m.context})"
        }
        val recent = sessions.take(10).flatMap { s -> fixes(s).map { s to it } }.take(25)
        if (recent.isNotEmpty()) {
            lines += "Corrections in their last talks (newest first):"
            for ((s, f) in recent) {
                lines += "- ${day(s.startedAt)}: \"${f.was}\" → \"${f.now}\"" + (if (f.why.isEmpty()) "" else " (${f.why})")
            }
        }
        return if (lines.isEmpty()) "No mistakes on file yet." else lines.joinToString("\n")
    }

    suspend fun notebook(c: Context): String {
        val language = LanguageScope.active(c)
        val v = VocabStore.shared(c)
        val studying = v.studying(language)
        val expressions = v.studyingExpressions(language)
        val lines = arrayListOf("Words they are studying (${studying.size}): " + studying.take(60).joinToString(", "))
        lines += "Expressions they are studying (${expressions.size}): " + expressions.take(40).joinToString("; ")
        val recorded = v.recordedWords(language).map { it to v.state(it, language) }
        val known = recorded.filter { it.second == "known" }.map { it.first }
        val used = recorded.filter { it.second == "used" }.map { it.first }
        lines += "Words marked known: ${known.size}. Words used in a talk (learned for good): ${used.size}."
        if (used.isNotEmpty()) lines += "Recently used: " + used.take(25).joinToString(", ")
        return lines.joinToString("\n")
    }

    suspend fun cards(c: Context, now: Long): String {
        val language = LanguageScope.active(c)
        val waiting = com.roro.futurevoice.ui.waitingDeck(c, language, now)
        val lines = arrayListOf("Waiting now: ${waiting.size}.")
        val sentences = waiting.filter { it.cardId != null }.take(15)
        if (sentences.isNotEmpty()) {
            lines += "Sentence cards waiting (their corrected lines):"
            for (s in sentences) lines += "- \"${s.text}\"" + (if (s.cardSaid.isEmpty()) "" else " (they said \"${s.cardSaid}\")")
        }
        val words = waiting.filter { it.cardId == null }.take(20).map { it.text }
        if (words.isNotEmpty()) lines += "Words/expressions waiting: " + words.joinToString("; ")
        val drills = DrillStore.shared(c)
        lines += "Sentence cards put off for later: ${drills.putOffCards(language).size}."
        val all = drills.load(language)
        lines += "All sentence cards: ${all.size}, retired as known: ${all.count { it.box >= 5 }}."
        return lines.joinToString("\n")
    }

    suspend fun progress(c: Context, learner: Learner): String {
        val lines = arrayListOf("Level on file: ${learner.level.code.uppercase()}.")
        val scored = finishedTalks(c).filter { it.summary?.scorecard != null }.take(10)
        if (scored.isNotEmpty()) {
            lines += "Per-talk scores, newest first (vocabulary/grammar/expressiveness/fluency, level read):"
            for (s in scored) {
                val sc = s.summary?.scorecard ?: continue
                lines += "- ${day(s.startedAt)}: ${sc.vocabulary.score}/${sc.grammar.score}/" +
                    "${sc.expressiveness.score}/${sc.fluency.score}" + (sc.cefrLevel?.let { " ${it.uppercase()}" } ?: "")
            }
        }
        runCatching { WeeklyReportStore.shared(c).latest(learner.targetLanguage) }.getOrNull()?.let { r ->
            lines += "Last level report (${day(r.periodEnd)}): ${r.cefrLevel?.uppercase() ?: "no level"} — ${r.summary.take(400)}"
        }
        runCatching { WeekRecapStore.lastWeek(c) }.getOrNull()?.let { recap ->
            recap.coach?.let { coach ->
                lines += "Last week's coach note: ${coach.headline} ${coach.insight}"
                if (coach.plan.isNotEmpty()) lines += "Its plan: " + coach.plan.joinToString(" / ")
            }
            lines += "Last week: ${recap.talkSeconds / 60} min talking, ${recap.cardsCleared} cards cleared, ${recap.shadowTakes} shadow takes."
        }
        val t = runCatching { WeeklyTestStore.shared(c).load(learner.targetLanguage) }.getOrDefault(emptyList())
            .maxByOrNull { it.createdAt }
        if (t != null && t.isFinished) {
            val wrong = t.items.filter { item -> t.answers.any { it.itemId == item.id && !it.correct } }
            lines += "Last weekly test: ${t.score}/${t.total}." +
                (if (wrong.isEmpty()) "" else " Missed: " + wrong.take(6).joinToString(", ") { "\"${it.answer}\"" })
        }
        return lines.joinToString("\n")
    }

    suspend fun goals(c: Context, learner: Learner, now: Long): String {
        val active = UpcomingGoalStore.active(c, learner.targetLanguage, now)
        if (active.isEmpty()) return "No upcoming goals. They can add one with the tutor's Add a goal."
        val lines = ArrayList<String>()
        for (g in active) {
            lines += "Goal id ${g.id.uppercase()}: " + g.promptLine(now)
            if (g.materialLines.isNotEmpty()) lines += g.materialLines
            GoalPrep.cachedQuestions(c, g)?.takeIf { it.isNotEmpty() }?.let { qs ->
                lines += "Likely questions: " + qs.joinToString(" | ") { "\"${it.text}\"" }
            }
            val days = GoalPrep.days(c, g)
            if (days.isNotEmpty()) {
                lines += "Prepared so far (newest first):"
                for (d in days.take(6)) {
                    lines += "- ${d.day}: focus ${d.focus}; reading \"${d.reading.title}\"; model answer" +
                        (d.speech.question?.let { " to \"$it\"" } ?: "") + ": \"${d.speech.body.take(500)}\""
                }
            }
        }
        return lines.joinToString("\n")
    }

    suspend fun routine(c: Context, now: Long): String {
        val plan = StudyPlanStore.current(c)
        if (plan.blocks.isEmpty()) return "No routine set."
        // iOS `Calendar.current.weekdaySymbols`, Sunday first (1…7).
        val names = DateFormatSymbols(Locale.getDefault()).weekdays
        val lines = ArrayList<String>()
        for (wd in 1..7) {
            val blocks = plan.blocks.filter { wd in it.weekdays }.sortedWith(compareBy({ it.hour }, { it.minute }))
            if (blocks.isEmpty()) { lines += "${names[wd]}: rest"; continue }
            lines += "${names[wd]}: " + blocks.joinToString(", ") { b ->
                (if (b.isAnytime) "anytime" else String.format(Locale.US, "%02d:%02d", b.hour, b.minute)) +
                    " ${b.kind.raw} ${b.amount}"
            }
        }
        lines += "Streak: ${TalkTimeLog.streakDays(c, now)} days."
        return lines.joinToString("\n")
    }

    suspend fun scenarios(c: Context): String {
        val lines = ArrayList<String>()
        val own = runCatching { ScenarioStore.shared(c).load(LanguageScope.active(c)) }.getOrDefault(emptyList())
            .filter { it.archivedAt == null }.take(25)
        if (own.isNotEmpty()) {
            lines += "Scenarios (Watch):"
            for (s in own) {
                val r = s.role.trim()
                lines += "- id ${s.id.uppercase()}: " + (if (r.isEmpty()) s.environment else "${s.environment} · with $r")
            }
        }
        val people = runCatching { CounterpartStore.shared(c).load() }.getOrDefault(emptyList())
            .filter { it.remoteId == null }.take(20)
        if (people.isNotEmpty()) {
            lines += "Their people: " + people.joinToString(", ") { "${it.name} (${it.relationship})" }
        }
        return if (lines.isEmpty()) "No scenarios or people yet." else lines.joinToString("\n")
    }
}
