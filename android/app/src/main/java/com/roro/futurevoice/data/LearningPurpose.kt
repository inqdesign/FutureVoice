package com.roro.futurevoice.data

import android.content.Context
import androidx.annotation.StringRes
import com.roro.futurevoice.R
import kotlinx.serialization.Serializable

/**
 * Why the learner is learning — asked once in setup, MANY answers allowed,
 * in the order they were picked (iOS `LearningPurpose`, founder 2026-10-11).
 * The answer shapes two things and nothing else:
 *
 * - **Talk's chip row** (`DiscoverSection`): which chips there are and in
 *   what order. Each purpose leads with its own chip, the first purpose
 *   picked is the chip the row opens on, and news + the learner's own
 *   situations follow. A learner who never answered keeps the row they
 *   always had.
 * - **The first routine** ([RoutineRecipe]): a week built for those
 *   purposes, shown at the end of setup with every time editable.
 *
 * No exam date, no target score — which exam is a filter, not a setup
 * question.
 */
enum class LearningPurpose(val raw: String) {
    START("start"), HOBBY("hobby"), EXAM("exam"), STUDY("study"),
    JOB("job"), WORK("work"), ABROAD("abroad"), TRAVEL("travel");

    @get:StringRes val title: Int get() = when (this) {
        START -> R.string.i_want_to_start_speaking
        HOBBY -> R.string.for_fun
        EXAM -> R.string.for_an_exam
        STUDY -> R.string.for_my_studies
        JOB -> R.string.for_a_job_hunt
        WORK -> R.string.i_need_it_at_work
        ABROAD -> R.string.i_live_abroad
        TRAVEL -> R.string.for_travel
    }

    @get:StringRes val subtitle: Int get() = when (this) {
        START -> R.string.words_don_t_come_out_yet
        HOBBY -> R.string.talk_about_what_i_like
        EXAM -> R.string.ielts_opic_toeic_speaking
        STUDY -> R.string.seminars_presentations_my_subject
        JOB -> R.string.interviews_the_field_i_m_applying_to
        WORK -> R.string.meetings_presentations_client_calls
        ABROAD -> R.string.landlord_town_hall_doctor_my_kid_s_school
        TRAVEL -> R.string.airport_hotel_restaurants
    }

    /** iOS SF Symbol — resolved through `Symbols.icon`. */
    val symbol: String get() = when (this) {
        START -> "bubble.left.and.bubble.right.fill"
        HOBBY -> "heart.fill"
        EXAM -> "checklist"
        STUDY -> "graduationcap.fill"
        JOB -> "person.text.rectangle.fill"
        WORK -> "briefcase.fill"
        ABROAD -> "house.fill"
        TRAVEL -> "airplane"
    }

    /** iOS system colours (light): blue, pink, orange, teal, purple, brown,
     *  green, cyan. Never indigo (the Core's). */
    val tint: Long get() = when (this) {
        START -> 0xFF007AFF
        HOBBY -> 0xFFFF2D55
        EXAM -> 0xFFFF9500
        STUDY -> 0xFF30B0C7
        JOB -> 0xFFAF52DE
        WORK -> 0xFFA2845E
        ABROAD -> 0xFF34C759
        TRAVEL -> 0xFF32ADE6
    }

    /** The chip this purpose puts first. */
    val leadChip: DiscoverChip get() = when (this) {
        START -> DiscoverChip.EVERYDAY
        HOBBY -> DiscoverChip.NEWS
        EXAM -> DiscoverChip.EXAM
        STUDY -> DiscoverChip.STUDY
        JOB -> DiscoverChip.INTERVIEW
        WORK -> DiscoverChip.WORK
        ABROAD -> DiscoverChip.LIFE
        TRAVEL -> DiscoverChip.TRAVEL
    }

    companion object {
        fun from(raw: String): LearningPurpose? = entries.firstOrNull { it.raw == raw }
    }
}

/** One chip on Talk's discover row (iOS `DiscoverChip`). */
enum class DiscoverChip(val raw: String) {
    EXAM("exam"), STUDY("study"), INTERVIEW("interview"), WORK("work"), LIFE("life"),
    TRAVEL("travel"), EVERYDAY("everyday"), NEWS("news"), SCENARIOS("scenarios");

    @get:StringRes val label: Int get() = when (this) {
        EXAM -> R.string.exam
        STUDY -> R.string.studies
        INTERVIEW -> R.string.interview
        WORK -> R.string.work
        LIFE -> R.string.life
        TRAVEL -> R.string.travel_22fb76
        EVERYDAY -> R.string.everyday
        NEWS -> R.string.news
        SCENARIOS -> R.string.scenarios
    }

    /** The ready-made situations behind a situation chip. */
    val starters: List<StarterSituation>? get() = when (this) {
        EVERYDAY -> StarterSituation.all
        INTERVIEW -> StarterSituation.interview
        WORK -> StarterSituation.work
        LIFE -> StarterSituation.life
        TRAVEL -> StarterSituation.travel
        EXAM, STUDY, NEWS, SCENARIOS -> null
    }
}

/** What the learner wrote under a purpose (iOS `PurposeDetails`). */
@Serializable
data class PurposeDetails(
    val school: String = "",
    val subject: String = "",
    val job: String = "",
    val role: String = "",
    val target: String = "",
)

/** iOS `LearningPurposeStore` — same keys. */
object LearningPurposeStore {
    private const val PREFS = "futurevoice"
    private const val KEY = "futurevoice.learningPurposes"
    private const val EXAM_KEY = "futurevoice.examKind"
    private const val DETAILS_KEY = "futurevoice.purposeDetails"
    /** Setup saved the suggested week — the call's own setup then keeps its
     *  times instead of collapsing them to one. */
    const val ROUTINE_APPLIED_KEY = "futurevoice.routineFromPurpose"

    private fun p(c: Context) = c.getSharedPreferences(PREFS, 0)

    /** In the order picked. Empty = never asked (every install before this). */
    fun purposes(c: Context): List<LearningPurpose> =
        (p(c).getString(KEY, null) ?: "").split(',').mapNotNull { LearningPurpose.from(it) }.take(3)

    fun setPurposes(c: Context, value: List<LearningPurpose>) {
        p(c).edit().putString(KEY, value.joinToString(",") { it.raw }).apply()
    }

    /** Each optional; a filled one turns its chip's topics into topics of
     *  THAT field (`PurposeTopicClient`). */
    fun details(c: Context): PurposeDetails = p(c).getString(DETAILS_KEY, null)
        ?.let { runCatching { StoreJson.json.decodeFromString(PurposeDetails.serializer(), it) }.getOrNull() }
        ?: PurposeDetails()

    fun setDetails(c: Context, value: PurposeDetails) {
        p(c).edit().putString(DETAILS_KEY, StoreJson.json.encodeToString(PurposeDetails.serializer(), value)).apply()
    }

    fun routineApplied(c: Context): Boolean = p(c).getBoolean(ROUTINE_APPLIED_KEY, false)
    fun setRoutineApplied(c: Context) { p(c).edit().putBoolean(ROUTINE_APPLIED_KEY, true).apply() }

    /** The exam picked in the Exam chip's filter, for this target language. */
    fun exam(c: Context, language: String): ExamKind {
        val options = ExamKind.options(language)
        val saved = p(c).getString(EXAM_KEY + "." + base(language), null)
        return options.firstOrNull { it.raw == saved } ?: options[0]
    }

    fun setExam(c: Context, exam: ExamKind, language: String) {
        p(c).edit().putString(EXAM_KEY + "." + base(language), exam.raw).apply()
    }

    /** Talk's chips: each purpose's own chip in the order picked, then news
     *  and the learner's own situations. A beginner who picked "for fun"
     *  gets the everyday starters too — news alone asks too much of A1/A2. */
    fun chips(picked: List<LearningPurpose>, level: CefrLevel): List<DiscoverChip> {
        if (picked.isEmpty()) return listOf(DiscoverChip.NEWS, DiscoverChip.EVERYDAY, DiscoverChip.SCENARIOS)
        val out = mutableListOf<DiscoverChip>()
        fun add(chip: DiscoverChip) { if (chip !in out) out += chip }
        picked.forEach { add(it.leadChip) }
        add(DiscoverChip.NEWS)
        if (LearningPurpose.HOBBY in picked && level in setOf(CefrLevel.A1, CefrLevel.A2)) add(DiscoverChip.EVERYDAY)
        add(DiscoverChip.SCENARIOS)
        return out
    }

    fun chips(c: Context, level: CefrLevel): List<DiscoverChip> = chips(purposes(c), level)

    internal fun base(language: String) = language.substringBefore('-').lowercase()
}

// MARK: - Exams

/** Speaking exams per target language. A language with none of its own
 *  falls back to OPIc, which is offered in most. */
enum class ExamKind(val raw: String, val examName: String) {
    IELTS("ielts", "IELTS"), TOEFL("toefl", "TOEFL"), OPIC("opic", "OPIc"),
    TOEIC_SPEAKING("toeicSpeaking", "TOEIC Speaking"), GOETHE("goethe", "Goethe-Zertifikat"),
    TELC("telc", "telc"), TOPIK("topik", "TOPIK"), BJT("bjt", "BJT"),
    DELE("dele", "DELE"), SIELE("siele", "SIELE");

    companion object {
        fun options(language: String): List<ExamKind> = when (LearningPurposeStore.base(language)) {
            "en" -> listOf(IELTS, TOEFL, OPIC, TOEIC_SPEAKING)
            "de" -> listOf(GOETHE, TELC, OPIC)
            "ko" -> listOf(TOPIK, OPIC)
            "ja" -> listOf(OPIC, BJT)
            "es" -> listOf(DELE, SIELE, OPIC)
            else -> listOf(OPIC)
        }
    }
}

/** One common exam question, talked through with the fluent self. */
data class ExamTopic(
    val title: String,
    /** "Part 2", "Task 1" — shown beside the exam's name. */
    val part: String,
    /** A cue card's bullet points, when the exam gives them. */
    val points: List<String> = emptyList(),
) {
    /** What the call is told: the exam, the part, the question. */
    fun callBlurb(exam: ExamKind): String {
        var s = "Speaking practice for the ${exam.examName} exam. This is a common $part question: \"$title\"."
        if (points.isNotEmpty()) s += " The cue card asks them to cover: " + points.joinToString("; ") + "."
        s += " Ask it the way the examiner would, let the learner do most of the talking, and follow up on what they say — one question at a time. Never score them."
        return s
    }
}

object ExamTopics {
    fun topics(exam: ExamKind, language: String): List<ExamTopic> = when (exam) {
        ExamKind.IELTS -> listOf(
            ExamTopic("Describe a skill you learned as an adult", "Part 2",
                listOf("what the skill is", "how you learned it", "how long it took you", "why you decided to learn it")),
            ExamTopic("Your hometown", "Part 1"),
            ExamTopic("Should children have smartphones?", "Part 3"),
            ExamTopic("Describe a time you helped a stranger", "Part 2",
                listOf("who the person was", "what happened", "how you helped", "how you felt afterwards")),
            ExamTopic("Work or study", "Part 1"),
            ExamTopic("Is public transport worth what it costs?", "Part 3"),
            ExamTopic("Describe a place you would like to visit", "Part 2",
                listOf("where it is", "how you know about it", "what you would do there", "why you want to go")),
            ExamTopic("How you spend your weekends", "Part 1"),
            ExamTopic("Will robots replace teachers?", "Part 3"),
            ExamTopic("Describe a book or film that changed your mind", "Part 2",
                listOf("what it was", "when you read or saw it", "what it was about", "how it changed your view")),
            ExamTopic("Music in your life", "Part 1"),
            ExamTopic("Do cities need more green space?", "Part 3"),
        )
        ExamKind.TOEFL -> listOf(
            ExamTopic("Is it better to study alone or in a group?", "Task 1"),
            ExamTopic("Should university attendance be required?", "Task 1"),
            ExamTopic("Working from home or at the office — which do you prefer?", "Task 1"),
            ExamTopic("Is it better to live in a dorm or off campus?", "Task 1"),
            ExamTopic("Should students take a gap year?", "Task 1"),
            ExamTopic("A big decision you made recently", "Task 1"),
        )
        ExamKind.OPIC -> when (LearningPurposeStore.base(language)) {
            "ja" -> listOf(
                ExamTopic("あなたの住んでいる家について話してください", "Survey"),
                ExamTopic("最近行った旅行について", "Survey"),
                ExamTopic("週末によくすること", "Survey"),
                ExamTopic("よく行くカフェについて", "Survey"),
                ExamTopic("予約が取れなかったときの対応", "Role-play"),
            )
            "es" -> listOf(
                ExamTopic("Describa su casa", "Survey"),
                ExamTopic("Su último viaje", "Survey"),
                ExamTopic("¿Qué hace normalmente los fines de semana?", "Survey"),
                ExamTopic("Una cafetería a la que va a menudo", "Survey"),
                ExamTopic("Llame a una tienda por un producto que llegó roto", "Role-play"),
            )
            "de" -> listOf(
                ExamTopic("Beschreiben Sie Ihre Wohnung", "Survey"),
                ExamTopic("Ihre letzte Reise", "Survey"),
                ExamTopic("Was machen Sie am Wochenende?", "Survey"),
                ExamTopic("Ein Problem im Restaurant lösen", "Role-play"),
            )
            else -> listOf(
                ExamTopic("Describe your home", "Survey"),
                ExamTopic("Your most recent trip", "Survey"),
                ExamTopic("What you usually do on weekends", "Survey"),
                ExamTopic("A café you often go to", "Survey"),
                ExamTopic("Your favourite park and what you do there", "Survey"),
                ExamTopic("Call a store about a broken item", "Role-play"),
                ExamTopic("A time something went wrong on a trip", "Unexpected"),
            )
        }
        ExamKind.TOEIC_SPEAKING -> listOf(
            ExamTopic("Your ideal workplace", "Express an opinion"),
            ExamTopic("Should companies let employees work from home?", "Express an opinion"),
            ExamTopic("A survey about your commute", "Respond to questions"),
            ExamTopic("A survey about shopping habits", "Respond to questions"),
            ExamTopic("Is it better to have one long vacation or several short ones?", "Express an opinion"),
        )
        ExamKind.GOETHE -> listOf(
            ExamTopic("Stellen Sie sich vor", "Teil 1"),
            ExamTopic("Sollen Kinder ein eigenes Handy haben?", "Teil 2"),
            ExamTopic("Eine Feier gemeinsam planen", "Teil 1"),
            ExamTopic("Wohnen in der Stadt oder auf dem Land?", "Teil 2"),
            ExamTopic("Homeoffice — Vor- und Nachteile", "Teil 2"),
            ExamTopic("Ein Ausflug mit dem Sprachkurs", "Teil 1"),
        )
        ExamKind.TELC -> listOf(
            ExamTopic("Über sich selbst sprechen", "Teil 1"),
            ExamTopic("Ein Foto beschreiben: Freizeit", "Teil 2"),
            ExamTopic("Gemeinsam etwas planen: ein Geschenk", "Teil 3"),
        )
        ExamKind.TOPIK -> listOf(
            ExamTopic("자기소개를 해 보세요", "1번"),
            ExamTopic("주말에 보통 무엇을 해요?", "2번"),
            ExamTopic("식당에서 주문이 잘못 나왔을 때", "3번"),
            ExamTopic("온라인 수업과 교실 수업, 어느 쪽이 좋아요?", "5번"),
            ExamTopic("도시에 사는 것의 장점과 단점", "6번"),
        )
        ExamKind.BJT -> listOf(
            ExamTopic("取引先に納期の遅れを伝える", "Business"),
            ExamTopic("上司に休みを相談する", "Business"),
            ExamTopic("新しい企画を短く説明する", "Business"),
        )
        ExamKind.DELE -> listOf(
            ExamTopic("Hable de una persona que ha sido importante en su vida", "Tarea 1",
                listOf("quién es", "cómo la conoció", "qué ha aprendido de ella")),
            ExamTopic("Describa una fotografía: una familia en un parque", "Tarea 2"),
            ExamTopic("Organice con un amigo una cena para celebrar algo", "Tarea 3"),
            ExamTopic("¿Es mejor vivir en el centro o en las afueras?", "Tarea 1",
                listOf("ventajas", "inconvenientes", "su preferencia y por qué")),
            ExamTopic("Describa una fotografía: personas trabajando en una oficina", "Tarea 2"),
            ExamTopic("Quéjese en un hotel porque la habitación no es la que reservó", "Tarea 3"),
        )
        ExamKind.SIELE -> listOf(
            ExamTopic("Preséntese: dónde vive, a qué se dedica y por qué estudia español", "Tarea 1"),
            ExamTopic("Describa una foto: una calle llena de gente", "Tarea 2"),
            ExamTopic("Llame a un compañero para cambiar el día de una reunión", "Tarea 3"),
            ExamTopic("Cuente una experiencia que le hizo cambiar de opinión", "Tarea 4"),
            ExamTopic("¿Deberían los estudiantes llevar uniforme? Dé su opinión", "Tarea 5"),
        )
    }
}

// MARK: - The first routine

/**
 * The week a learner's purposes suggest, built from ordinary plan blocks so
 * everything after setup treats it like any routine. Each block carries a
 * one-line WHY, shown only in setup (iOS `RoutineRecipe`).
 */
object RoutineRecipe {
    data class Line(val block: StudyPlan.Block, @StringRes val why: Int)

    fun lines(purposes: List<LearningPurpose>, goalMinutes: Int): List<Line> {
        val minutes = maxOf(5, goalMinutes)
        val everyDay = (1..7).toSet()
        val mwf = setOf(2, 4, 6)
        val out = mutableListOf<Line>()
        val picked = purposes.ifEmpty { listOf(LearningPurpose.START) }
        // De-duplicate by chip: two purposes sharing a chip share a talk.
        val leads = mutableListOf<LearningPurpose>()
        for (p in picked) if (leads.none { it.leadChip == p.leadChip }) leads += p

        // Talks: the first purpose every day (a hobby, four evenings), the
        // second Tue/Thu evening, a third Saturday late morning.
        val slots = listOf(Triple(everyDay, 8, 0), Triple(setOf(3, 5), 20, 0), Triple(setOf(7), 11, 0))
        leads.take(3).forEachIndexed { i, p ->
            var (days, h, m) = slots[i]
            if (i == 0 && p == LearningPurpose.HOBBY) { days = setOf(2, 4, 6, 7); h = 19 }
            out += Line(StudyPlan.Block(kind = StudyPlan.Kind.TALK, weekdays = days, hour = h, minute = m,
                minutes = minutes), talkWhy(p))
        }

        // Say it again right after the first talk: every day for someone
        // starting out (repetition is the whole method), else Mon/Wed/Fri.
        out.firstOrNull()?.block?.let { first ->
            val end = first.startMinute + minutes
            val days = if (picked.first() == LearningPurpose.START) first.weekdays else first.weekdays.intersect(mwf)
            if (end + StudyPlan.SAY_IT_AGAIN_MINUTES <= 24 * 60 && days.isNotEmpty()) {
                out += Line(StudyPlan.Block(kind = StudyPlan.Kind.SAY_IT_AGAIN, weekdays = days,
                    hour = end / 60, minute = end % 60, minutes = 1),
                    R.string.that_day_s_talk_said_the_way_it_should_have_gone)
            }
        }

        // Review: every evening, or three for a hobby.
        val reviewDays = if (picked == listOf(LearningPurpose.HOBBY)) mwf else everyDay
        out += Line(StudyPlan.Block(kind = StudyPlan.Kind.REVIEW, weekdays = reviewDays, hour = 21, minute = 30,
            minutes = StudyPlan.Kind.REVIEW.defaultAmount), R.string.the_sentences_your_talks_corrected)

        // A speech for purposes that end in speaking alone to someone.
        when {
            LearningPurpose.JOB in picked -> out += Line(StudyPlan.Block(kind = StudyPlan.Kind.SPEECH,
                weekdays = setOf(1), hour = 19, minute = 0, minutes = 1), R.string.polish_your_one_minute_self_introduction)
            LearningPurpose.WORK in picked -> out += Line(StudyPlan.Block(kind = StudyPlan.Kind.SPEECH,
                weekdays = setOf(6), hour = 18, minute = 0, minutes = 1), R.string.a_short_update_the_way_you_d_give_it_in_a_meeting)
            LearningPurpose.EXAM in picked -> out += Line(StudyPlan.Block(kind = StudyPlan.Kind.SPEECH,
                weekdays = setOf(1), hour = 19, minute = 0, minutes = 1), R.string.two_minutes_on_one_topic_without_stopping)
        }
        return out
    }

    @StringRes
    private fun talkWhy(p: LearningPurpose): Int = when (p) {
        LearningPurpose.START -> R.string.everyday_chip_a_caf_asking_the_way_a_neighbor
        LearningPurpose.HOBBY -> R.string.news_chip_stories_on_what_you_re_into
        LearningPurpose.EXAM -> R.string.exam_chip_topics_the_exam_keeps_asking
        LearningPurpose.STUDY -> R.string.studies_chip_topics_from_your_subject
        LearningPurpose.JOB -> R.string.interview_chip_about_yourself_why_this_job
        LearningPurpose.WORK -> R.string.work_chip_meetings_presentations_client_calls
        LearningPurpose.ABROAD -> R.string.life_chip_landlord_town_hall_doctor
        LearningPurpose.TRAVEL -> R.string.travel_chip_airport_hotel_restaurants
    }

    @StringRes
    fun headline(purposes: List<LearningPurpose>): Int = when (purposes.firstOrNull() ?: LearningPurpose.START) {
        LearningPurpose.START -> R.string.a_week_to_get_you_talking
        LearningPurpose.HOBBY -> R.string.a_week_of_talking_about_what_you_love
        LearningPurpose.EXAM -> R.string.a_week_of_exam_practice
        LearningPurpose.STUDY -> R.string.a_week_of_talking_about_what_you_study
        LearningPurpose.JOB -> R.string.a_week_to_get_interview_ready
        LearningPurpose.WORK -> R.string.a_week_of_the_talk_you_need_at_work
        LearningPurpose.ABROAD -> R.string.a_week_of_handling_life_where_you_live
        LearningPurpose.TRAVEL -> R.string.a_week_to_get_ready_for_your_trip
    }

    /** The plan to save: these blocks, a promise from today like the plain
     *  seeded routine. */
    fun plan(lines: List<Line>, now: Long = System.currentTimeMillis()): StudyPlan =
        StudyPlan(blocks = lines.map { it.block }, streakSince = StudyPlan.startOfDay(now), unitsVersion = 2)
}
