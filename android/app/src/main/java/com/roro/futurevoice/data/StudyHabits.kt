package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.talk.TurnRole
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * How the learner actually USES the app — when, how often, what — read from
 * the logs, and the coaching that follows from it (iOS `StudyHabits`,
 * 2026-10-27, founder: "it's all about how the user actually uses the app …
 * a coach gives harsh advice too, with a good reason, and then constructive
 * feedback").
 *
 * Everything here is counted in code. [HabitAdvisor] turns the counts into
 * findings by fixed rules, so the same week always gets the same advice and
 * every finding carries the numbers it rests on; a model only words it
 * ([HabitAdvice.phrase]). The routine the report recommends is built from
 * these findings — never from a template the learner's week had no say in.
 */
data class StudyHabits(
    val dayCount: Int,
    val activeDays: Int,
    /** The longest run of days with nothing, inside the window. */
    val longestGapDays: Int,
    val talkMinutes: Int,
    val talkDays: Int,
    val talks: Int,
    val reviewReps: Int,
    val reviewDays: Int,
    val shadowTakes: Int,
    val sayItAgainRuns: Int,
    val listens: Int,
    /** Share of all effort that fell on the busiest day (0…1). */
    val busiestDayShare: Double,
    val busiestDay: Long?,
    /** The hour most sittings start around, and how many of them do. */
    val habitHour: Int?,
    val habitShare: Double,
    /** Review cards the talks made from corrections, and the corrections
     *  that came back more than once (`was → now`, times). */
    val correctionsMade: Int,
    val repeatedFixes: List<WeekRecap.Stumble>,
    val plan: List<PlanKept>,
    val sittingsCount: Int,
) {
    enum class Activity { TALK, REVIEW, SHADOW, SAY_IT_AGAIN, LISTEN, SPEECH, SCENE }

    /** One thing done, at a time. A talk carries its minutes; every other
     *  sitting is one rep. */
    data class Sitting(val activity: Activity, val at: Long, val minutes: Double = 0.0)

    /** What the learner's own routine asked of a kind, and what happened. */
    data class PlanKept(
        val kind: StudyPlan.Kind,
        /** Days in the window the routine had this kind. */
        val plannedDays: Int,
        /** Of those, days it happened at all. */
        val keptDays: Int,
        /** The block's own hour, for "planned at 21:30". */
        val hour: Int,
        val minute: Int,
        val anytime: Boolean,
    )

    companion object {
        /** Pure: everything it reads is passed in. */
        fun compute(
            start: Long, end: Long,
            sittings: List<Sitting>,
            correctionsMade: Int,
            repeatedFixes: List<WeekRecap.Stumble>,
            planBlocks: List<StudyPlan.Block>,
            zone: TimeZone = TimeZone.getDefault(),
        ): StudyHabits {
            val inWindow = sittings.filter { it.at >= start && it.at < end }.sortedBy { it.at }
            val days = mutableListOf<Long>()
            var d = StudyPlan.startOfDay(start, zone)
            while (d < end) { days += d; d = StudyPlan.addDays(d, 1, zone) }
            val byDay = inWindow.groupBy { StudyPlan.startOfDay(it.at, zone) }

            // Effort per day: talk minutes, and half a minute per rep — a rough
            // common unit, used only to see whether the work was spread out.
            fun effort(s: Sitting) = if (s.activity == Activity.TALK) max(1.0, s.minutes) else 0.5
            val effortByDay = byDay.mapValues { (_, list) -> list.sumOf { effort(it) } }
            val total = effortByDay.values.sum()
            val busiest = effortByDay.entries.maxByOrNull { it.value }

            var longest = 0
            var run = 0
            for (day in days) {
                if (byDay[day] == null) { run += 1; longest = max(longest, run) } else run = 0
            }
            // A gap that is still running at the window's end counts too; a
            // leading one before the first sitting does not (they hadn't started).
            inWindow.firstOrNull()?.let { first ->
                val firstDay = StudyPlan.startOfDay(first.at, zone)
                longest = 0; run = 0
                for (day in days) {
                    if (day < firstDay) continue
                    if (byDay[day] == null) { run += 1; longest = max(longest, run) } else run = 0
                }
            }

            // The habit hour: the hour with the most sitting STARTS within ±1 h.
            // A talk is one sitting; reps within 20 min of each other are one too.
            val starts = mutableListOf<Long>()
            for (s in inWindow) {
                val last = starts.lastOrNull()
                if (last != null && s.at - last < 20 * 60_000L) continue
                starts += s.at
            }
            val hours = starts.map { Calendar.getInstance(zone).apply { timeInMillis = it }.get(Calendar.HOUR_OF_DAY) }
            var habitHour: Int? = null
            var habitShare = 0.0
            if (hours.isNotEmpty()) {
                fun near(h: Int, c: Int): Boolean { val diff = abs(h - c); return min(diff, 24 - diff) <= 1 }
                // Ties within the window go to the hour most sittings start IN.
                fun score(h: Int) = hours.count { near(it, h) } * 100 + hours.count { it == h }
                val best = (0 until 24).maxByOrNull { score(it) }!!
                habitHour = best
                habitShare = hours.count { near(it, best) }.toDouble() / hours.size
            }

            fun count(a: Activity) = inWindow.count { it.activity == a }
            fun daysWith(a: Activity) = inWindow.filter { it.activity == a }.map { StudyPlan.startOfDay(it.at, zone) }.toSet().size

            val kept = planBlocks.mapNotNull { block ->
                val activity = when (block.kind) {
                    StudyPlan.Kind.TALK -> Activity.TALK
                    StudyPlan.Kind.REVIEW, StudyPlan.Kind.WORDS, StudyPlan.Kind.EXPRESSIONS -> Activity.REVIEW
                    StudyPlan.Kind.SHADOW -> Activity.SHADOW
                    StudyPlan.Kind.SAY_IT_AGAIN -> Activity.SAY_IT_AGAIN
                    StudyPlan.Kind.LISTEN -> Activity.LISTEN
                    StudyPlan.Kind.SPEECH -> Activity.SPEECH
                    StudyPlan.Kind.TEST -> null
                } ?: return@mapNotNull null
                val planned = days.filter { StudyPlan.weekday(it, zone) in block.weekdays }
                if (planned.isEmpty()) return@mapNotNull null
                val keptDays = planned.count { day -> byDay[day]?.any { it.activity == activity } == true }
                PlanKept(block.kind, planned.size, keptDays, block.hour, block.minute, block.isAnytime)
            }

            return StudyHabits(
                dayCount = days.size,
                activeDays = byDay.size,
                longestGapDays = longest,
                talkMinutes = Math.round(inWindow.filter { it.activity == Activity.TALK }.sumOf { it.minutes }).toInt(),
                talkDays = daysWith(Activity.TALK),
                talks = count(Activity.TALK),
                reviewReps = count(Activity.REVIEW),
                reviewDays = daysWith(Activity.REVIEW),
                shadowTakes = count(Activity.SHADOW),
                sayItAgainRuns = count(Activity.SAY_IT_AGAIN),
                listens = count(Activity.LISTEN),
                busiestDayShare = if (total > 0) (busiest?.value ?: 0.0) / total else 0.0,
                busiestDay = busiest?.key,
                habitHour = habitHour,
                habitShare = habitShare,
                correctionsMade = correctionsMade,
                repeatedFixes = repeatedFixes,
                plan = kept,
                sittingsCount = starts.size,
            )
        }

        /** From the app's own logs, for `[start, end)`. */
        suspend fun read(c: Context, start: Long, end: Long, recap: WeekRecap): StudyHabits {
            val sittings = mutableListOf<Sitting>()
            // Corrections are counted in the talks themselves — every fix the
            // learner was given — not by the cards minted from them, which a
            // talk summarized offline may not have made yet.
            var corrections = 0
            for (s in WeekRecapBuilder.sessionsAcrossLanguages(c)) {
                val ended = s.endedAt ?: continue
                if (s.turns.none { it.role == TurnRole.USER }) continue
                val began = s.turns.firstOrNull()?.timestamp ?: s.startedAt
                sittings += Sitting(Activity.TALK, began, max(0L, ended - began) / 60_000.0)
                if (began < start || began >= end) continue
                for (turn in s.turns) if (turn.isEvidence) corrections += turn.suggestion?.fixes?.size ?: 0
            }
            for (e in ActivityEventLog.events(c, start, end)) {
                val activity = when (e.kind) {
                    ActivityEventLog.Kind.DRILL, ActivityEventLog.Kind.WORD, ActivityEventLog.Kind.EXPRESSION -> Activity.REVIEW
                    ActivityEventLog.Kind.SHADOW -> Activity.SHADOW
                    ActivityEventLog.Kind.SAY_IT_AGAIN -> Activity.SAY_IT_AGAIN
                    ActivityEventLog.Kind.LISTEN -> Activity.LISTEN
                    ActivityEventLog.Kind.SPEECH -> Activity.SPEECH
                    ActivityEventLog.Kind.SCENE -> Activity.SCENE
                }
                sittings += Sitting(activity, e.at)
            }
            return compute(start, end, sittings,
                correctionsMade = max(corrections, recap.newCards), repeatedFixes = recap.stumbles,
                planBlocks = StudyPlanStore.current(c).blocks)
        }
    }
}

// MARK: - The rules

/** One thing the coach saw. Decided in code; [facts] are what a model is
 *  handed to word it, and nothing else. */
@Serializable
data class HabitFinding(
    /** A stable name for the rule ("cramming", "no-review", …). */
    val rule: String,
    val tone: Tone,
    /** The evidence, in English, numbers included — the model's only input. */
    val facts: List<String>,
    /** What the routine changes because of it, in English. */
    val change: String? = null,
) {
    @Serializable
    enum class Tone(val raw: String) {
        @SerialName("good") GOOD("good"),
        @SerialName("nudge") NUDGE("nudge"),
        @SerialName("firm") FIRM("firm"),
    }
}

object HabitAdvisor {
    /** At most this many findings reach the learner: a coach says the few
     *  things that matter, not everything that's true. */
    const val MAX_FINDINGS = 4

    /** The review block the no-review finding adds — the size it names. */
    const val SHORT_REVIEW_CARDS = 10

    /** A routine block, and the rule that changed or added it (null: as it was). */
    data class RoutineLine(val block: StudyPlan.Block, val rule: String?)

    private fun hhmm(h: Int, m: Int) = String.format(Locale.ROOT, "%02d:%02d", h, m)

    fun findings(h: StudyHabits): List<HabitFinding> {
        val out = mutableListOf<HabitFinding>()
        val habit = h.habitHour?.let { String.format(Locale.ROOT, "%02d:00", it) }

        // 1. Everything in one sitting.
        if (h.dayCount >= 4 && h.activeDays <= 2 && h.sittingsCount >= 1 && h.busiestDayShare >= 0.6) {
            val share = Math.round(h.busiestDayShare * 100).toInt()
            out += HabitFinding("cramming", HabitFinding.Tone.FIRM, listOf(
                "$share% of everything they did in ${h.dayCount} days happened on ONE day.",
                "They practised on ${h.activeDays} of ${h.dayCount} days.",
                "Why it matters: what is practised once a week fades within days; short practice on most days is what makes it stick.",
            ), "Talk on five weekdays instead, shorter" + (habit?.let { ", around $it when they already practise" } ?: "") + ".")
        }

        // 2. A long gap.
        if (h.dayCount >= 7 && h.longestGapDays >= 4 && out.none { it.rule == "cramming" }) {
            out += HabitFinding("gap", if (h.longestGapDays >= 6) HabitFinding.Tone.FIRM else HabitFinding.Tone.NUDGE, listOf(
                "They went ${h.longestGapDays} days in a row without practising.",
                "They practised on ${h.activeDays} of ${h.dayCount} days.",
                "Why it matters: after a few days off, the first talk back starts from further behind.",
            ), "A short talk every day, even five minutes, so no gap gets that long.")
        }

        // 3. Talking, never reviewing what the talks corrected.
        val top = h.repeatedFixes.firstOrNull()
        if (h.correctionsMade >= 5 && h.reviewReps == 0) {
            val facts = mutableListOf(
                "Their talks corrected ${h.correctionsMade} things they said, each saved as a review card. They reviewed none of them.",
                "They talked ${h.talkMinutes} min in ${h.talks} talk(s).",
            )
            if (top != null) facts += "The same correction came back ${top.count} times: \"${top.was}\" → \"${top.now}\"."
            facts += "Why it matters: talking without reviewing means making the same mistakes again; the review is where a correction becomes theirs."
            out += HabitFinding("no-review", HabitFinding.Tone.FIRM, facts,
                "Add a short review ($SHORT_REVIEW_CARDS cards) right after the talk." +
                    (if (h.repeatedFixes.isEmpty()) "" else " Add say it again after the talk."))
        } else if (top != null && h.sayItAgainRuns == 0) {
            // 4. The same fix twice, never practised in context.
            out += HabitFinding("repeated-fix", HabitFinding.Tone.NUDGE, listOf(
                "The same correction came back ${top.count} times: \"${top.was}\" → \"${top.now}\".",
                "They haven't used say it again (re-doing a talk the corrected way) yet.",
                "Why it matters: a fix that keeps coming back needs saying out loud the right way, not just reading.",
            ), "Add say it again right after the talk.")
        }

        // 4b. Corrected often, never re-said the right way (no fix came
        // back word for word yet, but the corrections are there).
        if (h.correctionsMade >= 5 && h.sayItAgainRuns == 0 && h.talks >= 2 &&
            out.none { it.rule == "repeated-fix" || it.rule == "no-review" }) {
            out += HabitFinding("no-say-again", HabitFinding.Tone.NUDGE, listOf(
                "Their talks corrected ${h.correctionsMade} things they said.",
                "They haven't used say it again (re-doing a talk, saying their own lines the corrected way) yet.",
                "Why it matters: reading a correction is not the same as saying it; saying the right version in the same conversation is what makes it come out next time.",
            ), "Add say it again right after the talk.")
        }

        // 5. A planned kind that never happened.
        for (p in h.plan) {
            if (p.plannedDays < 3 || p.keptDays != 0 || p.kind == StudyPlan.Kind.TALK) continue
            val kind = p.kind.raw
            val whenText = if (p.anytime) "" else " at " + hhmm(p.hour, p.minute)
            val facts = mutableListOf("Their own routine has $kind$whenText on ${p.plannedDays} day(s) so far. It happened on none of them.")
            var change = "Make it smaller so it fits: one short $kind block a day."
            val hh = h.habitHour
            if (habit != null && !p.anytime && hh != null && abs(hh - p.hour) >= 2) {
                facts += "They usually practise around $habit, not$whenText."
                change = "Move $kind to around $habit, when they already practise."
            }
            facts += "Why it matters: a plan that never happens teaches that plans don't count; a smaller one that happens beats a big one that doesn't."
            out += HabitFinding("plan-missed-$kind", HabitFinding.Tone.NUDGE, facts, change)
        }

        // 6. Only reviewing, barely talking.
        if (h.talkMinutes < 10 && h.reviewReps >= 20) {
            out += HabitFinding("little-talk", HabitFinding.Tone.NUDGE, listOf(
                "They reviewed ${h.reviewReps} cards but talked only ${h.talkMinutes} min.",
                "Why it matters: review keeps what they know; only talking makes new mistakes to learn from and makes the words come out under pressure.",
            ), "A ten-minute talk on the days they review.")
        }

        // 7. What is working — said as plainly as what isn't.
        if (h.dayCount >= 2 && h.dayCount < 4 && h.activeDays == h.dayCount) {
            out += HabitFinding("came-back", HabitFinding.Tone.GOOD, listOf(
                "They practised on every one of the ${h.dayCount} days since they started.",
                "Why it matters: coming back the next day is what most people never do; it is the start of a habit.",
            ), null)
        }
        if (h.reviewReps > 0 && h.correctionsMade > 0) {
            out += HabitFinding("reviewed", HabitFinding.Tone.GOOD, listOf(
                "Their talks corrected ${h.correctionsMade} things; they reviewed ${h.reviewReps} card(s) on ${h.reviewDays} day(s).",
                "Why it matters: reviewing what a talk corrected is where the correction becomes theirs.",
            ), null)
        }
        if (h.dayCount >= 4 && h.activeDays.toDouble() / h.dayCount >= 0.7) {
            out += HabitFinding("consistent", HabitFinding.Tone.GOOD, listOf(
                "They practised on ${h.activeDays} of ${h.dayCount} days.",
                "Why it matters: this regularity is the part most learners never manage.",
            ), null)
        } else if (habit != null && h.sittingsCount >= 3 && h.habitShare >= 0.6) {
            out += HabitFinding("habit-time", HabitFinding.Tone.GOOD, listOf(
                "${Math.round(h.habitShare * 100).toInt()}% of their sittings start around $habit.",
                "Why it matters: a fixed time is what turns practice into a habit; the routine is placed there.",
            ), null)
        }
        if (h.talks >= 3 && out.none { it.tone == HabitFinding.Tone.GOOD }) {
            out += HabitFinding("talking", HabitFinding.Tone.GOOD, listOf(
                "They talked ${h.talkMinutes} min in ${h.talks} talks.",
                "Why it matters: speaking is the hard part, and they are doing it.",
            ), null)
        }

        // Firm first, then nudges, the good news last — but always one good
        // thing when there is one, so the list is never only criticism.
        val order = mapOf(HabitFinding.Tone.FIRM to 0, HabitFinding.Tone.NUDGE to 1, HabitFinding.Tone.GOOD to 2)
        val sorted = out.sortedBy { order.getValue(it.tone) }
        val picked = sorted.filter { it.tone != HabitFinding.Tone.GOOD }.take(MAX_FINDINGS - 1).toMutableList()
        sorted.firstOrNull { it.tone == HabitFinding.Tone.GOOD }?.let { picked += it }
        if (picked.size < MAX_FINDINGS) {
            picked += sorted.filter { it.tone != HabitFinding.Tone.GOOD && it !in picked }.take(MAX_FINDINGS - picked.size)
        }
        return picked
    }

    /** The routine the findings call for: the learner's own routine (or the
     *  starting one) with what each finding changes, every touched block
     *  carrying the rule that touched it. */
    fun routine(base: List<StudyPlan.Block>, habits: StudyHabits,
                findings: List<HabitFinding>, goalMinutes: Int): List<RoutineLine> {
        val h = habits
        val lines = base.map { RoutineLine(it, null) }.toMutableList()
        val hour = h.habitHour
        val weekdays = setOf(2, 3, 4, 5, 6)
        val rules = findings.map { it.rule }.toSet()

        fun talkIndex(): Int? = lines.indexOfFirst { it.block.kind == StudyPlan.Kind.TALK }.takeIf { it >= 0 }

        if ("cramming" in rules || "gap" in rules) {
            val minutes = max(5, min(goalMinutes, if (h.talks > 0) h.talkMinutes / max(1, 5) else goalMinutes))
            val days = if ("gap" in rules) (1..7).toSet() else weekdays
            val rule = if ("cramming" in rules) "cramming" else "gap"
            val i = talkIndex()
            if (i != null) {
                var b = lines[i].block.copy(weekdays = days, minutes = max(5, minutes))
                if (hour != null && !b.isAnytime) b = b.copy(hour = hour, minute = 0)
                lines[i] = RoutineLine(b, rule)
            } else {
                lines.add(0, RoutineLine(StudyPlan.Block(kind = StudyPlan.Kind.TALK, weekdays = days,
                    hour = hour ?: 20, minute = 0, minutes = max(5, minutes),
                    anytime = if (hour == null) true else null), rule))
            }
        }
        val talk = talkIndex()?.let { lines[it].block }
        val after = talk?.let { if (it.isAnytime) (hour ?: 20) * 60 + 30 else it.startMinute + it.minutes }
            ?: ((hour ?: 20) * 60 + 30)
        val talkDays = talk?.weekdays ?: (1..7).toSet()

        if ("no-review" in rules && lines.none { it.block.kind == StudyPlan.Kind.REVIEW }) {
            lines += RoutineLine(StudyPlan.Block(kind = StudyPlan.Kind.REVIEW, weekdays = talkDays,
                hour = (after + 5) / 60 % 24, minute = (after + 5) % 60,
                minutes = SHORT_REVIEW_CARDS), "no-review")
        }
        if (("repeated-fix" in rules || "no-say-again" in rules ||
                ("no-review" in rules && h.repeatedFixes.isNotEmpty())) &&
            lines.none { it.block.kind == StudyPlan.Kind.SAY_IT_AGAIN }) {
            lines += RoutineLine(StudyPlan.Block(kind = StudyPlan.Kind.SAY_IT_AGAIN, weekdays = talkDays,
                hour = after / 60 % 24, minute = after % 60, minutes = 1),
                when {
                    "repeated-fix" in rules -> "repeated-fix"
                    "no-say-again" in rules -> "no-say-again"
                    else -> "no-review"
                })
        }
        for (f in findings) {
            if (!f.rule.startsWith("plan-missed-")) continue
            val kind = f.rule.removePrefix("plan-missed-")
            val i = lines.indexOfFirst { it.block.kind.raw == kind }.takeIf { it >= 0 } ?: continue
            val b = lines[i].block
            val next = if (hour != null && !b.isAnytime && abs(hour - b.hour) >= 2) {
                b.copy(hour = hour, minute = 30)
            } else if (!b.kind.isTimed) {
                b.copy(minutes = max(1, b.minutes / 2))
            } else b
            lines[i] = RoutineLine(next, f.rule)
        }
        if ("little-talk" in rules && talkIndex() == null) {
            val days = lines.filter { it.block.kind == StudyPlan.Kind.REVIEW }.flatMap { it.block.weekdays }.toSet()
            lines.add(0, RoutineLine(StudyPlan.Block(kind = StudyPlan.Kind.TALK,
                weekdays = days.ifEmpty { weekdays }, hour = hour ?: 20, minute = 0, minutes = 10), "little-talk"))
        }
        return lines.sortedBy { it.block.startMinute }
    }
}

// MARK: - Wording

/** The findings, worded for the learner in their native language. The rules
 *  chose them and their numbers; this only says them the way a good coach
 *  would — straight when it's firm, specific when it's good. */
@Serializable
data class HabitAdvice(val lines: List<Line>) {
    @Serializable
    data class Line(
        val rule: String,
        val tone: HabitFinding.Tone,
        /** A short headline (native). */
        val title: String,
        /** What we saw and why it matters (native), numbers as given. */
        val body: String,
        /** What the routine does about it (native), when anything. */
        val change: String? = null,
    )

    @Serializable
    private data class Payload(val lines: List<Raw>) {
        @Serializable
        data class Raw(val rule: String, val title: String, val body: String, val change: String? = null)
    }

    companion object {
        suspend fun phrase(findings: List<HabitFinding>, firstTalks: Boolean, nativeLanguage: String): HabitAdvice {
            if (findings.isEmpty()) return HabitAdvice(emptyList())
            val native = LanguageCatalog.englishName(nativeLanguage)
            val system = "You are a language learner's coach. Below are findings about HOW they have been using their practice app — decided already, with the numbers that prove them. Word each one for the learner, in ${native}. You add no finding, drop none, change no number.\n" +
            "\n" +
            "For each finding write:\n" +
            "- \"title\": the point in at most ~8 words.\n" +
            "- \"body\": 1–2 sentences: what you saw (with its numbers, exactly as given) and why it matters.\n" +
            "- \"change\": one sentence on what their routine does about it, from the given change; null when none is given.\n" +
            "\n" +
            "TONE, by the finding's tone:\n" +
            "- firm: say it straight, like a coach who wants them to succeed. No softening (\"maybe\", \"a little\", \"it seems\"), no \"unfortunately\", no apology. Never shame, never call them lazy, never exaggerate — the numbers carry the weight. The reason makes it fair; the change makes it constructive.\n" +
            "- nudge: direct and friendly.\n" +
            "- good: specific praise of what they actually did. No \"great job!\", no exclamation marks anywhere.\n" +
            "\n" +
            "LANGUAGE: natural ${native}, written, not translated. Korean: 해요체 in every sentence, never 합니다/습니다, never 당신. Japanese: です・ます. German/French/Spanish: informal you. Activity names: talk, review, say it again (re-doing a talk the corrected way), shadowing, listening — use the app's ordinary words for them in ${native}. ${if (firstTalks) "These are their first days with the app; never say \"this week\"." else ""}\n" +
            "\n" +
            "JSON only: {\"lines\": [{\"rule\": \"...\", \"title\": \"...\", \"body\": \"...\", \"change\": null}]}, one per finding, same order, rule copied exactly."
            
            val user = findings.joinToString("\n\n") { f ->
                "FINDING ${f.rule} (tone: ${f.tone.raw})\n" + f.facts.joinToString("\n") { "- $it" } +
                    (f.change?.let { "\nCHANGE: $it" } ?: "")
            }
            val response = GeminiClient(AuthRepository()).sendJson(
                system = system,
                messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
                serializer = Payload.serializer(),
                maxTokens = 2048,
                purpose = "week-recap",
            )
            val tones = buildMap { findings.forEach { putIfAbsent(it.rule, it.tone) } }
            return HabitAdvice(response.lines.mapNotNull { raw ->
                val tone = tones[raw.rule] ?: return@mapNotNull null
                if (raw.title.isEmpty()) return@mapNotNull null
                val change = raw.change?.trim()
                Line(raw.rule, tone, raw.title, raw.body, if (change.isNullOrEmpty()) null else change)
            })
        }
    }
}
