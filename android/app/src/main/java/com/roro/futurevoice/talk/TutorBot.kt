package com.roro.futurevoice.talk

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.ActivityEventLog
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DeepLinkInbox
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PlanReminder
import com.roro.futurevoice.data.PlannerDay
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.ProfileStore
import com.roro.futurevoice.data.RoutineText
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyPlanStore
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.nowLine
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.ui.PlannerSnapshot
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.text.DateFormatSymbols
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

/**
 * The tutor bot (iOS `TutorBot`, 2026-10-28, founder): the face at the Talk
 * tab's bottom right. Its ONE job is that the learner always knows what to do
 * next, and why. It speaks in three ways, each quieter than the last:
 *
 * - **A note, once a day** — on the first open of the day, today's plan rises
 *   out of the face. No dim, nothing blocked; a tap elsewhere folds it back.
 *   The very first one introduces the bot.
 * - **A bubble, only when there is something to say** — a step just finished
 *   and the next is ready, a planned time arrived, the day is done. Never the
 *   same thing twice a day, never more than [MAX_BUBBLES].
 * - **A chat, when tapped** — today's plan as the first message, then any
 *   question about the learner's own practice ([TutorChat]).
 *
 * Everything the note and the bubble say is computed in code from the routine
 * and the logs Activity already reads ([PlannerSnapshot]), so it is instant,
 * free and cannot disagree with My routine. Only the chat asks a model. It
 * replaced the quick quiz's door; the quiz is now one of the things the bot
 * can hand you.
 */
object TutorBot {

    /** One thing to do today. */
    data class Item(
        val id: String,
        val kind: StudyPlan.Kind,
        val title: String,
        val start: Long,
        val anytime: Boolean,
        val progress: Double,
        val end: Long,
    ) {
        val done: Boolean get() = progress >= 1
        fun isNow(now: Long): Boolean = !done && !anytime && start <= now && now < end
    }

    data class Today(
        val day: Long = Long.MIN_VALUE,
        val items: List<Item> = emptyList(),
        /** No routine for today: the items are the bot's own suggestion. */
        val suggested: Boolean = false,
        /** The learner has blocks on other days — today rests. */
        val restDay: Boolean = false,
        val dueCards: Int = 0,
        val streak: Int = 0,
        val focusLabel: String? = null,
        val focusTalks: Int = 0,
        val talkedToday: Int = 0,
    ) {
        val left: List<Item> get() = items.filter { !it.done }
        val allDone: Boolean get() = items.isNotEmpty() && left.isEmpty()
        val minutesLeft: Int get() = left.sumOf { maxOf(1, ((it.end - it.start) / 60_000.0).roundToInt()) }

        /** The one thing to do now: a block whose time is on, then an anytime
         *  one, then the next timed one, then anything undone. */
        fun next(now: Long = System.currentTimeMillis()): Item? =
            items.firstOrNull { it.isNow(now) }
                ?: items.firstOrNull { !it.done && it.anytime }
                ?: items.firstOrNull { !it.done && it.start > now }
                ?: items.firstOrNull { !it.done }
    }

    data class Bubble(
        /** The "said today" key. */
        val id: String,
        val text: String,
        val kind: StudyPlan.Kind?,
        /** Button title; null = just OK. */
        val action: String?,
    )

    var today by mutableStateOf(Today())
        private set
    var noteShown by mutableStateOf(false)
        private set
    var introShown by mutableStateOf(false)
    var bubble by mutableStateOf<Bubble?>(null)
        private set
    /** When the face last had something to say — its happy blink runs from here. */
    var bubbleSince by mutableLongStateOf(0L)
        private set
    var chatOpen by mutableStateOf(false)
    var quizOpen by mutableStateOf(false)

    const val MAX_BUBBLES = 3
    /** Quiet after the note closes — the note just said everything. */
    const val QUIET_AFTER_NOTE_MS = 60_000L

    const val INTRO_SEEN_KEY = "futurevoice.tutorBot.introSeen"
    private const val NOTE_DAY_KEY = "futurevoice.tutorBot.noteDay"
    private const val SAID_DAY_KEY = "futurevoice.tutorBot.saidDay"
    private const val SAID_KEY = "futurevoice.tutorBot.said"
    private const val DONE_IDS_KEY = "futurevoice.tutorBot.doneIds"
    private const val FOCUS_CACHE_KEY = "futurevoice.coach.focusDescriptions.v2"

    private var noteClosedAt: Long? = null

    private fun prefs(c: Context) = c.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    // The string sets are stored as joined lists (UserDefaults keeps arrays).
    private fun readList(c: Context, key: String): List<String> =
        prefs(c).getString(key, null)?.let { s -> if (s.isEmpty()) emptyList() else s.split('\n') } ?: emptyList()

    private fun writeList(c: Context, key: String, list: List<String>) =
        prefs(c).edit().putString(key, list.joinToString("\n")).apply()

    private fun putBubble(b: Bubble?) {
        bubble = b
        if (b != null) bubbleSince = System.currentTimeMillis()
    }

    // MARK: - Today

    /** Today's plan, judged by Activity's own rule. With no routine at all,
     *  the bot suggests a day from what is waiting. */
    suspend fun makeToday(c: Context, targetLanguage: String, nativeLanguage: String, level: CefrLevel,
                          now: Long = System.currentTimeMillis()): Today {
        val day = StudyPlan.startOfDay(now)
        val plan = StudyPlanStore.current(c)
        val snap = PlannerSnapshot.make(c, weekStart = day, plan = plan, now = now)
        val progress = snap.progress[day] ?: emptyMap()
        val res = c.resources
        var items = (snap.planned[day] ?: emptyList()).map { occ ->
            Item(occ.id, occ.kind,
                title = if (occ.kind == StudyPlan.Kind.REVIEW) RoutineText.label(res, occ.kind)
                    else RoutineText.titled(res, occ.kind, occ.amount),
                start = occ.start, anytime = occ.anytime, progress = progress[occ.id] ?: 0.0, end = occ.end)
        }
        val language = LanguageScope.active(c)
        val dueCards = runCatching { DrillStore.shared(c).dueCount(language, now) }.getOrDefault(0) +
            runCatching { StudyScheduleStore.shared(c).snapshot(language).dueItems(now).size }.getOrDefault(0)
        val streak = TalkTimeLog.streakDays(c, now)
        val talkedToday = TalkTimeLog.secondsToday(c, now) / 60
        var suggested = false
        var restDay = false
        if (items.isEmpty()) {
            if (plan.blocks.isEmpty()) {
                suggested = true
                items = suggestedDay(c, day, dueCards)
            } else {
                restDay = true
            }
        }
        val sessions = runCatching { SessionStore.shared(c).load(language) }.getOrDefault(emptyList())
            .filter { it.endedAt != null }
        val profile = runCatching { ProfileStore.shared(c).load(targetLanguage, level.code) }.getOrNull()
        var focusTalks = 0
        var focusLabel: String? = null
        val top = profile?.let { GrammarFocus.candidates(it, sessions, now).firstOrNull() }
        if (top != null) {
            focusTalks = top.second
            focusLabel = cachedFocusLabel(c, top.first, nativeLanguage)
                ?: "“${top.first.mistake}” → “${top.first.correction}”"
        }
        return Today(day, items, suggested, restDay, dueCards, streak, focusLabel, focusTalks, talkedToday)
    }

    /** No routine: a talk, and review when something is waiting. Judged done
     *  by the same totals a planned block would be. */
    private fun suggestedDay(c: Context, day: Long, dueCards: Int): List<Item> {
        val next = StudyPlan.addDays(day, 1)
        val events = ActivityEventLog.events(c, day, next)
        val totals = PlannerDay.totals(TalkTimeLog.secondsToday(c, day), PracticeLog.day(c, day), events, false)
        val res = c.resources
        val items = ArrayList<Item>()
        if (dueCards > 0) {
            val n = minOf(10, dueCards)
            items += Item("suggested-review", StudyPlan.Kind.REVIEW, RoutineText.label(res, StudyPlan.Kind.REVIEW),
                start = day, anytime = true,
                progress = minOf(1.0, totals.amount(StudyPlan.Kind.REVIEW) / n),
                end = day + StudyPlan.Kind.REVIEW.drawnMinutes(n) * 60_000L)
        }
        items += Item("suggested-talk", StudyPlan.Kind.TALK, RoutineText.titled(res, StudyPlan.Kind.TALK, 10),
            start = day, anytime = true,
            progress = minOf(1.0, totals.talkMinutes / 10), end = day + 600_000L)
        return items
    }

    /** The grammar focus's name as the call strip shows it — read from
     *  [GrammarFocus.describe]'s cache only, never asked for here. */
    private fun cachedFocusLabel(c: Context, p: LearnerPattern, native: String): String? {
        val cache = runCatching {
            Json.parseToJsonElement(prefs(c).getString(FOCUS_CACHE_KEY, null) ?: "{}").jsonObject
        }.getOrNull() ?: return null
        val hit = runCatching { cache["${LearnerProfile.patternKey(p)}|$native"]?.jsonObject }.getOrNull()
            ?: return null
        if (hit["grammar"]?.jsonPrimitive?.content == "false") return null
        return hit["label"]?.jsonPrimitive?.content
    }

    // MARK: - Refresh

    /** Re-reads the day and decides whether there is anything to say.
     *  [visible] is the Talk home on screen with nothing over it. */
    suspend fun refresh(c: Context, targetLanguage: String, nativeLanguage: String, level: CefrLevel,
                        visible: () -> Boolean, now: Long = System.currentTimeMillis()) {
        val fresh = makeToday(c, targetLanguage, nativeLanguage, level, now)
        val dayKey = StudyPlan.dayKey(now)
        val p = prefs(c)
        if (p.getString(SAID_DAY_KEY, null) != dayKey) {
            p.edit().putString(SAID_DAY_KEY, dayKey).apply()
            writeList(c, SAID_KEY, emptyList())
            writeList(c, DONE_IDS_KEY, fresh.items.filter { it.done }.map { it.id })
        }
        val before = readList(c, DONE_IDS_KEY).toSet()
        val doneNow = fresh.items.filter { it.done }.map { it.id }.toSet()
        writeList(c, DONE_IDS_KEY, doneNow.toList())
        today = fresh
        if (!visible()) return

        // Once a day, the note — the first open of the day.
        if (p.getString(NOTE_DAY_KEY, null) != dayKey) {
            p.edit().putString(NOTE_DAY_KEY, dayKey).apply()
            putBubble(null)
            introShown = !p.getBoolean(INTRO_SEEN_KEY, false)
            bubbleSince = now
            Analytics.capture("tutor_bot_note", mapOf("intro" to introShown, "items" to fresh.items.size,
                "suggested" to fresh.suggested))
            noteShown = true
            return
        }
        if (noteShown || chatOpen) return
        noteClosedAt?.let { if (now - it < QUIET_AFTER_NOTE_MS) return }
        nextBubble(c, fresh, doneNow - before, now)?.let { say(c, it) }
    }

    /** The one thing worth saying now, or null — the usual answer. */
    private fun nextBubble(c: Context, today: Today, newlyDone: Set<String>, now: Long): Bubble? {
        val res = c.resources
        val next = today.next(now)
        // The day just finished.
        if (newlyDone.isNotEmpty() && today.allDone) {
            return Bubble("done", res.getString(R.string.that_s_everything_for_today_nicely_done),
                kind = null, action = null)
        }
        // A step just finished and the next one is ready.
        val justDone = today.items.firstOrNull { it.id in newlyDone }
        if (justDone != null && next != null) {
            return Bubble("after-${justDone.id}",
                res.getString(R.string.nice_done_next_up,
                    RoutineText.label(res, justDone.kind).lowercase(), next.title),
                kind = next.kind, action = res.getString(R.string.start))
        }
        // A planned time has come.
        today.items.firstOrNull { it.isNow(now) }?.let { on ->
            return Bubble("now-${on.id}", PlanReminder.nowLine(res, on.kind) + " · " + on.title,
                kind = on.kind, action = res.getString(R.string.start))
        }
        return null
    }

    private fun say(c: Context, b: Bubble) {
        val said = readList(c, SAID_KEY).toMutableList()
        if (b.id in said || said.size >= MAX_BUBBLES) return
        said += b.id
        writeList(c, SAID_KEY, said)
        Analytics.capture("tutor_bot_bubble", mapOf("kind" to b.id.split("-").first()))
        putBubble(b)
    }

    // MARK: - Actions

    fun closeNote(c: Context) {
        if (introShown) prefs(c).edit().putBoolean(INTRO_SEEN_KEY, true).apply()
        noteClosedAt = System.currentTimeMillis()
        noteShown = false
    }

    /** The note, again — the face's long-press. */
    fun showNote(intro: Boolean = false) {
        putBubble(null)
        introShown = intro
        bubbleSince = System.currentTimeMillis()
        noteShown = true
    }

    /** The intro's "Show me today": the plan, and the bot is met. */
    fun finishIntro(c: Context) {
        introShown = false
        prefs(c).edit().putBoolean(INTRO_SEEN_KEY, true).apply()
    }

    fun dismissBubble() {
        putBubble(null)
    }

    fun openChat(c: Context) {
        dismissBubble()
        if (noteShown) closeNote(c)
        chatOpen = true
    }

    /** Opens the practice a kind names, through the door its reminder and
     *  widget already use. null = the quick quiz. */
    fun start(c: Context, kind: StudyPlan.Kind?) {
        dismissBubble()
        if (noteShown) closeNote(c)
        chatOpen = false
        Analytics.capture("tutor_bot_start", mapOf("kind" to (kind?.raw ?: "quiz")))
        if (kind == null) { quizOpen = true; return }
        if (kind == StudyPlan.Kind.TALK) {
            DeepLinkInbox.requestFreeTalk(TalkEntry.TUTOR_BOT)
            return
        }
        DeepLinkInbox.widgetRoute.value = DeepLinkInbox.WidgetRoute.Routine(kind)
    }
}

// MARK: - Chat

/**
 * "Ask me anything" (iOS `TutorChat`): a short thread whose first message is
 * today's plan. Each answer is grounded in the learner's own numbers
 * ([context]) and ends in something to start. Kept in memory for the day,
 * never written to disk.
 */
object TutorChat {

    data class Message(
        val id: String = UUID.randomUUID().toString(),
        val fromLearner: Boolean,
        val text: String,
        val action: StudyPlan.Kind? = null,
        val quiz: Boolean = false,
    )

    val messages = mutableStateListOf<Message>()
    var thinking by mutableStateOf(false)
        private set
    private var day = ""

    fun resetIfNewDay() {
        val key = StudyPlan.dayKey(System.currentTimeMillis())
        if (key != day) { day = key; messages.clear() }
    }

    @Serializable
    private data class Reply(val reply: String, val action: String? = null)

    suspend fun ask(c: Context, question: String, targetLanguage: String, nativeLanguage: String,
                    level: CefrLevel, persona: UserPersona?) {
        val q = question.trim()
        if (q.isEmpty() || thinking) return
        messages += Message(fromLearner = true, text = q)
        thinking = true
        try {
            val history = messages.takeLast(12).map {
                GeminiClient.Message(if (it.fromLearner) GeminiClient.Message.Role.USER
                    else GeminiClient.Message.Role.MODEL, it.text)
            }
            val r = runCatching {
                val system = system(c, targetLanguage, nativeLanguage, level, persona)
                withTimeout(30_000) {
                    GeminiClient(AuthRepository()).sendJson(
                        system = system,
                        messages = history,
                        serializer = Reply.serializer(),
                        model = GeminiClient.Model.FLASH_36, maxTokens = 2048, purpose = "tutor-bot",
                        idempotencyKey = "tutor-bot:${UUID.randomUUID()}",
                    )
                }
            }.getOrNull()
            if (r != null) {
                val action = r.action?.let { a -> if (a == "quiz") null else StudyPlan.Kind.entries.firstOrNull { it.raw == a } }
                messages += Message(fromLearner = false, text = r.reply.trim(),
                    action = action, quiz = r.action == "quiz")
                Analytics.capture("tutor_bot_asked", mapOf("action" to (r.action ?: "none")))
            } else {
                messages += Message(fromLearner = false,
                    text = c.getString(R.string.i_couldn_t_answer_that_just_now_try_again_in_a_moment))
            }
        } finally {
            thinking = false
        }
    }

    // MARK: Prompt

    suspend fun system(c: Context, targetLanguage: String, nativeLanguage: String, level: CefrLevel,
                       persona: UserPersona?): String {
        val native = LanguageCatalog.englishName(nativeLanguage)
        val target = LanguageCatalog.englishName(targetLanguage)
        val korean = if (nativeLanguage == "ko")
            "\nIn Korean, write in polite 해요체. Never use 당신; address them by nothing at all." else ""
        // Byte for byte iOS's literal, whose `\` continuations keep the next
        // line's two extra spaces of indent ("number,   a talk").
        return "You are the learner's TUTOR inside nawana, an app where they practise $target by " +
            "talking with their own cloned voice (their \"fluent self\"). You are NOT the fluent " +
            "self and not a conversation partner. You know their routine, their talks, their " +
            "mistakes and their review cards — the data below. Your one job: they always know " +
            "what to do next, and why.\n" +
            "\n" +
            "HOW YOU ANSWER\n" +
            "- Answer what they ASKED, fully, before anything else. A question about $target " +
            "(how to say something, a grammar point, a word, a sentence of theirs), a request " +
            "for material (another model answer, more interview answers, example sentences, a " +
            "question to practise) or about their own progress: do exactly that, here, in the " +
            "reply. Writing the material IS the answer; never answer a request for content by " +
            "pointing them to a feature.\n" +
            "- As long as the answer needs and no longer. A plain question: 2 to 4 sentences. " +
            "Material: write it out, in short paragraphs separated by a blank line. No " +
            "headings, no markdown, no emoji.\n" +
            "- Material is built from THEIR life in the data (their work, their talks). A model " +
            "answer is in $target, at their level, as they could say it; a line of explanation " +
            "in $native may follow it.\n" +
            "- Use their numbers and their own sentences from the data. Never invent a number, a " +
            "talk or a mistake that is not in the data. If the data can't answer, say so.\n" +
            "- Don't bring up their routine, their card count or a feature unless they asked what " +
            "to do, asked about their progress, or it is the honest answer to their question. " +
            "Being honest about something holding them back is fine when they ask; never " +
            "scold, never guilt.\n" +
            "- \"action\" is a button under your reply. Set it only when a step plainly follows " +
            "from what they asked (they asked what to do; or after a model answer, speech to " +
            "say it out loud). Otherwise \"none\", which is the usual answer.\n" +
            "- Explanations in $native. Anything to SAY goes in $target, quoted.$korean\n" +
            "- If they ask about something with nothing to do with learning $target, answer in " +
            "one line that you're here for their $target.\n" +
            "\n" +
            "WHAT YOU CAN HAND THEM (\"action\", exactly one of):\n" +
            "talk (a call with the fluent self), review (cards from their own mistakes and saved " +
            "words), shadow (repeat lines from their talks), sayItAgain (redo a past talk the right " +
            "way), listen (podcast and their scenes), speech (record a speech), quiz (one-minute " +
            "quiz), none.\n" +
            "\n" +
            "Return JSON: {\"reply\": \"...\", \"action\": \"...\"}\n" +
            "\n" +
            "THE LEARNER, AS OF NOW\n" +
            context(c, targetLanguage, nativeLanguage, level, persona)
    }

    /** Everything the tutor may say about the learner, in plain lines. */
    suspend fun context(c: Context, targetLanguage: String, nativeLanguage: String, level: CefrLevel,
                        persona: UserPersona?, now: Long = System.currentTimeMillis()): String {
        val t = TutorBot.makeToday(c, targetLanguage, nativeLanguage, level, now)
        val lines = ArrayList<String>()
        val f = SimpleDateFormat("EEE d MMM HH:mm", Locale.US)
        lines += "Now: ${f.format(Date(now))}"
        lines += "Learning ${LanguageCatalog.englishName(targetLanguage)}, level ${level.code.uppercase()}; native ${LanguageCatalog.englishName(nativeLanguage)}."
        if (persona != null) {
            if (persona.displayName.isNotEmpty()) lines += "Name: ${persona.displayName}"
            val about = listOf(persona.occupation, persona.city, persona.interests.joinToString(", "))
                .filter { it.isNotEmpty() }
            if (about.isNotEmpty()) lines += "They told setup: " + about.joinToString(" · ")
        }
        lines += "Streak: ${t.streak} days. Talked today: ${t.talkedToday} min. Review cards waiting: ${t.dueCards}."

        if (t.restDay) {
            lines += "Today: a rest day in their routine."
        } else if (t.items.isNotEmpty()) {
            lines += if (t.suggested) "Today (no routine set; your suggestion):" else "Today's routine:"
            for (i in t.items) {
                val cal = Calendar.getInstance().apply { timeInMillis = i.start }
                val whenText = if (i.anytime) "anytime" else String.format(Locale.US, "%02d:%02d",
                    cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE))
                lines += "- ${i.kind.raw} $whenText: ${(i.progress * 100).toInt()}% done"
            }
        }

        // The last seven days, from the same logs Activity reads.
        val shortWeekdays = DateFormatSymbols(Locale.US).shortWeekdays
        val week = ArrayList<String>()
        val today0 = StudyPlan.startOfDay(now)
        for (back in 6 downTo 0) {
            val d = StudyPlan.addDays(today0, -back)
            val log = PracticeLog.day(c, d) ?: PracticeLog.Day()
            val talk = TalkTimeLog.secondsToday(c, d) / 60
            val review = log.wordReps + log.expressionReps + log.drillReps
            week += "${shortWeekdays[StudyPlan.weekday(d)]}: talk ${talk}m, review $review, shadow ${log.shadowDone}"
        }
        lines += "Last 7 days: " + week.joinToString("; ")

        val language = LanguageScope.active(c)
        val sessions = runCatching { SessionStore.shared(c).load(language) }.getOrDefault(emptyList())
            .filter { it.endedAt != null && it.archivedAt == null }
            .sortedByDescending { it.startedAt }
        lines += "Talks in total: ${sessions.size}."
        for (s in sessions.take(5)) {
            val said = s.turns.filter { it.isEvidence }
            lines += "- Talk ${f.format(Date(s.startedAt))}: \"${s.displayTitle ?: "Conversation"}\", they spoke ${said.size} times" +
                (said.lastOrNull()?.let { ". Their last line: \"${it.transcript.take(140)}\"" } ?: "")
        }

        val profile = runCatching { ProfileStore.shared(c).load(targetLanguage, level.code) }.getOrNull()
        if (profile != null) {
            val mistakes = GrammarFocus.candidates(profile, sessions, now)
            if (mistakes.isEmpty()) {
                val any = profile.recurringMistakes.sortedByDescending { it.lastSeenAt }.take(3)
                for (m in any) lines += "Mistake seen: \"${m.mistake}\" → \"${m.correction}\" (${m.context})"
            } else {
                for ((p, talks) in mistakes.take(3)) {
                    lines += "Recurring mistake, said in $talks talks: \"${p.mistake}\" → \"${p.correction}\" (${p.context})"
                }
            }
            if (profile.weakVocabAreas.isNotEmpty()) {
                lines += "Weak vocabulary areas: " + profile.weakVocabAreas.take(5).joinToString(", ")
            }
            if (profile.strongPatterns.isNotEmpty()) {
                lines += "Already strong at: " + profile.strongPatterns.take(5).joinToString(", ")
            }
        }
        val vocab = VocabStore.shared(c)
        val words = runCatching { vocab.studying(language).size }.getOrDefault(0)
        val expressions = runCatching { vocab.studyingExpressions(language).size }.getOrDefault(0)
        lines += "Notebook: $words words, $expressions expressions being studied."
        val notes = persona?.currentNotes(now)?.takeLast(6)
        if (!notes.isNullOrEmpty()) {
            lines += "About their life: " + notes.joinToString("; ") { it.text }
        }
        return lines.joinToString("\n")
    }
}
