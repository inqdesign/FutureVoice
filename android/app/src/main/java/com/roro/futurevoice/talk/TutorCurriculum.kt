package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.StoreJson
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File

/**
 * The tutor's curriculum (iOS `TutorCurriculum`, 23ce515f; founder: "the
 * tutor has its own curriculum — chapters, and topics inside them; finish one
 * and it's checked off").
 *
 * Two tiers: a CHAPTER is an area of life, a TOPIC is one thing to be able to
 * say, small enough for one lesson. A topic is DONE when its lesson's final
 * check is passed ([TutorLesson.FinalCheck]), never by finishing the
 * challenges alone. Written once, the same map for everyone; the planner fits
 * each topic to the learner's level, so [Topic.level] only decides which
 * topics are lit and which read "a step up" (soft unlocking: a step up is
 * still a tap away).
 */
object TutorCurriculum {
    /** [icon] is the SF Symbol name ([com.roro.futurevoice.ui.brand.Symbols]);
     *  [english] is for the planner and telemetry; [title] in the app language. */
    data class Chapter(val id: String, val icon: String, val english: String, val title: Int,
                       val topics: List<Topic>)

    /** [level]: the lowest band it suits. */
    data class Topic(val id: String, val level: CefrLevel, val english: String, val title: Int)

    data class Placed(val chapter: Chapter, val topic: Topic)

    val chapters: List<Chapter> = listOf(
        Chapter("meet", "person.2.fill", "Meeting people", R.string.meeting_people, listOf(
            Topic("meet.intro", CefrLevel.A1, "Introducing yourself", R.string.introducing_yourself),
            Topic("meet.from", CefrLevel.A2, "Where you're from and why you're here", R.string.where_you_re_from_and_why_you_re_here),
            Topic("meet.work", CefrLevel.A1, "What you do", R.string.what_you_do),
            Topic("meet.family", CefrLevel.A1, "Your family", R.string.your_family),
            Topic("meet.hobbies", CefrLevel.A1, "Hobbies", R.string.hobbies),
            Topic("meet.ask", CefrLevel.A2, "Asking someone about themselves", R.string.asking_someone_about_themselves),
            Topic("meet.keepgoing", CefrLevel.B1, "Keeping a first conversation going", R.string.keeping_a_first_conversation_going),
            Topic("meet.plans", CefrLevel.A2, "Making plans to meet again", R.string.making_plans_to_meet_again),
            Topic("meet.names", CefrLevel.A2, "Remembering and using names", R.string.remembering_and_using_names),
            Topic("meet.goodbye", CefrLevel.A2, "Saying goodbye naturally", R.string.saying_goodbye_naturally),
        )),
        Chapter("cafe", "cup.and.saucer.fill", "Café & food", R.string.caf_food, listOf(
            Topic("cafe.order", CefrLevel.A1, "Ordering at a café", R.string.ordering_at_a_caf),
            Topic("cafe.restaurant", CefrLevel.A1, "Ordering at a restaurant", R.string.ordering_at_a_restaurant),
            Topic("cafe.whatsgood", CefrLevel.A2, "Asking what's good", R.string.asking_what_s_good),
            Topic("cafe.allergy", CefrLevel.A2, "Allergies and special requests", R.string.allergies_and_special_requests),
            Topic("cafe.wrong", CefrLevel.B1, "Your order came out wrong", R.string.your_order_came_out_wrong),
            Topic("cafe.soldout", CefrLevel.A2, "Something is sold out", R.string.something_is_sold_out),
            Topic("cafe.bill", CefrLevel.A2, "Paying and splitting the bill", R.string.paying_and_splitting_the_bill),
            Topic("cafe.booking", CefrLevel.A2, "Booking a table", R.string.booking_a_table),
            Topic("cafe.likes", CefrLevel.A1, "Talking about food you like", R.string.talking_about_food_you_like),
            Topic("cafe.compliment", CefrLevel.A2, "Complimenting the food", R.string.complimenting_the_food),
        )),
        Chapter("shop", "bag.fill", "Shopping", R.string.shopping, listOf(
            Topic("shop.size", CefrLevel.A1, "Asking for a size or color", R.string.asking_for_a_size_or_color),
            Topic("shop.tryon", CefrLevel.A1, "Trying things on", R.string.trying_things_on),
            Topic("shop.price", CefrLevel.A1, "Asking the price and paying", R.string.asking_the_price_and_paying),
            Topic("shop.return", CefrLevel.B1, "Returning something", R.string.returning_something),
            Topic("shop.discount", CefrLevel.B1, "Asking for a discount", R.string.asking_for_a_discount),
            Topic("shop.supermarket", CefrLevel.A1, "At the supermarket", R.string.at_the_supermarket),
            Topic("shop.gift", CefrLevel.A2, "Buying a gift", R.string.buying_a_gift),
            Topic("shop.phoneplan", CefrLevel.B1, "Buying a phone plan", R.string.buying_a_phone_plan),
            Topic("shop.online", CefrLevel.B1, "An online order went wrong", R.string.an_online_order_went_wrong),
            Topic("shop.compare", CefrLevel.B1, "Comparing two options", R.string.comparing_two_options),
        )),
        Chapter("travel", "tram.fill", "Getting around", R.string.getting_around, listOf(
            Topic("travel.way", CefrLevel.A1, "Asking the way", R.string.asking_the_way),
            Topic("travel.ticket", CefrLevel.A1, "Buying a ticket", R.string.buying_a_ticket),
            Topic("travel.taxi", CefrLevel.A1, "Taking a taxi", R.string.taking_a_taxi),
            Topic("travel.delay", CefrLevel.B1, "A delayed or cancelled train", R.string.a_delayed_or_cancelled_train),
            Topic("travel.checkin", CefrLevel.A2, "At the airport check-in", R.string.at_the_airport_check_in),
            Topic("travel.luggage", CefrLevel.B1, "Lost luggage", R.string.lost_luggage),
            Topic("travel.car", CefrLevel.B1, "Renting a car", R.string.renting_a_car),
            Topic("travel.hotel", CefrLevel.A2, "Checking in at a hotel", R.string.checking_in_at_a_hotel),
            Topic("travel.room", CefrLevel.B1, "A problem with the room", R.string.a_problem_with_the_room),
            Topic("travel.directions", CefrLevel.A2, "Giving directions to someone", R.string.giving_directions_to_someone),
        )),
        Chapter("home", "house.fill", "Home & neighbors", R.string.home_neighbors, listOf(
            Topic("home.landlord", CefrLevel.A2, "Calling the landlord", R.string.calling_the_landlord),
            Topic("home.broken", CefrLevel.A2, "Something is broken", R.string.something_is_broken),
            Topic("home.neighbor", CefrLevel.A2, "Talking to a neighbor", R.string.talking_to_a_neighbor),
            Topic("home.noise", CefrLevel.B1, "A noise complaint", R.string.a_noise_complaint),
            Topic("home.movein", CefrLevel.A2, "Moving in", R.string.moving_in),
            Topic("home.internet", CefrLevel.B1, "Setting up internet", R.string.setting_up_internet),
            Topic("home.delivery", CefrLevel.B1, "A delivery that didn't arrive", R.string.a_delivery_that_didn_t_arrive),
            Topic("home.townhall", CefrLevel.B1, "At the town hall", R.string.at_the_town_hall),
            Topic("home.bank", CefrLevel.B1, "Opening a bank account", R.string.opening_a_bank_account),
            Topic("home.rules", CefrLevel.A2, "Recycling and house rules", R.string.recycling_and_house_rules),
        )),
        Chapter("health", "cross.case.fill", "Health", R.string.health, listOf(
            Topic("health.appointment", CefrLevel.A2, "Booking a doctor's appointment", R.string.booking_a_doctor_s_appointment),
            Topic("health.symptoms", CefrLevel.A2, "Describing symptoms", R.string.describing_symptoms),
            Topic("health.pharmacist", CefrLevel.A2, "Asking the pharmacist", R.string.asking_the_pharmacist),
            Topic("health.allergy", CefrLevel.A2, "Explaining an allergy", R.string.explaining_an_allergy),
            Topic("health.emergency", CefrLevel.B1, "An emergency call", R.string.an_emergency_call),
            Topic("health.dentist", CefrLevel.A2, "At the dentist", R.string.at_the_dentist),
            Topic("health.feel", CefrLevel.A1, "Talking about how you feel", R.string.talking_about_how_you_feel),
            Topic("health.sick", CefrLevel.A2, "Calling in sick", R.string.calling_in_sick),
            Topic("health.checkup", CefrLevel.B1, "A check-up", R.string.a_check_up),
            Topic("health.help", CefrLevel.B1, "Helping someone who is unwell", R.string.helping_someone_who_is_unwell),
        )),
        Chapter("work", "briefcase.fill", "Work", R.string.work, listOf(
            Topic("work.smalltalk", CefrLevel.A2, "Small talk with a coworker", R.string.small_talk_with_a_coworker),
            Topic("work.update", CefrLevel.B1, "Your project update", R.string.your_project_update),
            Topic("work.meeting", CefrLevel.B1, "Giving your view in a meeting", R.string.giving_your_view_in_a_meeting),
            Topic("work.help", CefrLevel.A2, "Asking for help", R.string.asking_for_help),
            Topic("work.disagree", CefrLevel.B2, "Disagreeing politely", R.string.disagreeing_politely),
            Topic("work.client", CefrLevel.B1, "A call with a client", R.string.a_call_with_a_client),
            Topic("work.delay", CefrLevel.B1, "Explaining a delay", R.string.explaining_a_delay),
            Topic("work.no", CefrLevel.B2, "Saying no to extra work", R.string.saying_no_to_extra_work),
            Topic("work.review", CefrLevel.B2, "A performance review", R.string.a_performance_review),
            Topic("work.voicemail", CefrLevel.A2, "Leaving a voicemail", R.string.leaving_a_voicemail),
        )),
        Chapter("interview", "person.crop.rectangle.fill", "Job interview", R.string.job_interview, listOf(
            Topic("interview.about", CefrLevel.B1, "Tell me about yourself", R.string.tell_me_about_yourself),
            Topic("interview.why", CefrLevel.B1, "Why this job", R.string.why_this_job),
            Topic("interview.strengths", CefrLevel.B1, "Strengths and weaknesses", R.string.strengths_and_weaknesses),
            Topic("interview.project", CefrLevel.B1, "A project you're proud of", R.string.a_project_you_re_proud_of),
            Topic("interview.conflict", CefrLevel.B2, "A conflict you handled", R.string.a_conflict_you_handled),
            Topic("interview.future", CefrLevel.B1, "Where you see yourself", R.string.where_you_see_yourself),
            Topic("interview.salary", CefrLevel.B2, "Talking about salary", R.string.talking_about_salary),
            Topic("interview.questions", CefrLevel.B1, "Questions for them", R.string.questions_for_them),
            Topic("interview.gap", CefrLevel.B2, "Explaining a gap", R.string.explaining_a_gap),
            Topic("interview.followup", CefrLevel.B1, "Following up after", R.string.following_up_after),
        )),
        Chapter("stories", "text.bubble.fill", "Opinions & stories", R.string.opinions_stories, listOf(
            Topic("stories.weekend", CefrLevel.A2, "What happened this weekend", R.string.what_happened_this_weekend),
            Topic("stories.funny", CefrLevel.B1, "A funny story", R.string.a_funny_story),
            Topic("stories.film", CefrLevel.B1, "Describing a film or book", R.string.describing_a_film_or_book),
            Topic("stories.opinion", CefrLevel.B1, "Giving your opinion", R.string.giving_your_opinion),
            Topic("stories.agree", CefrLevel.B1, "Agreeing and disagreeing", R.string.agreeing_and_disagreeing),
            Topic("stories.countries", CefrLevel.B2, "Comparing life in two countries", R.string.comparing_life_in_two_countries),
            Topic("stories.decision", CefrLevel.B1, "A decision you made", R.string.a_decision_you_made),
            Topic("stories.dreams", CefrLevel.A2, "Plans and dreams", R.string.plans_and_dreams),
            Topic("stories.news", CefrLevel.B2, "Reacting to news", R.string.reacting_to_news),
            Topic("stories.explain", CefrLevel.B2, "Explaining something you know well", R.string.explaining_something_you_know_well),
        )),
        Chapter("family", "figure.2.and.child.holdinghands", "Family & school", R.string.family_school, listOf(
            Topic("family.teacher", CefrLevel.A2, "Talking to your child's teacher", R.string.talking_to_your_child_s_teacher),
            Topic("family.event", CefrLevel.A2, "A school event", R.string.a_school_event),
            Topic("family.playdate", CefrLevel.A2, "Arranging a playdate", R.string.arranging_a_playdate),
            Topic("family.kids", CefrLevel.A1, "Talking about your kids", R.string.talking_about_your_kids),
            Topic("family.meeting", CefrLevel.B1, "A parent-teacher meeting", R.string.a_parent_teacher_meeting),
            Topic("family.absence", CefrLevel.A2, "Calling the school about an absence", R.string.calling_the_school_about_an_absence),
            Topic("family.pickup", CefrLevel.A2, "At the kindergarten pick-up", R.string.at_the_kindergarten_pick_up),
            Topic("family.help", CefrLevel.B1, "Asking another parent for help", R.string.asking_another_parent_for_help),
            Topic("family.birthday", CefrLevel.A2, "Birthdays and invitations", R.string.birthdays_and_invitations),
            Topic("family.visit", CefrLevel.A2, "A family visit", R.string.a_family_visit),
        )),
    )

    fun topic(id: String): Placed? {
        for (c in chapters) c.topics.firstOrNull { it.id == id }?.let { return Placed(c, it) }
        return null
    }

    /** What the planner is handed for a topic from the map. */
    fun request(id: String): String? = topic(id)?.let { "${it.chapter.english}: ${it.topic.english}" }

    fun isStepUp(topic: Topic, level: CefrLevel): Boolean = rank(topic.level) > rank(level)

    fun rank(level: CefrLevel): Int = CefrLevel.entries.indexOf(level).coerceAtLeast(0)

    /**
     * The one topic to do next: a lesson whose final check is still open
     * comes first; then the first lit topic not passed, in the chapter
     * touched last, then in chapter order. Step-ups only when nothing lit is
     * left.
     */
    fun next(progress: Map<String, TutorTopicProgress>, level: CefrLevel, excluding: String? = null): Placed? {
        val pairs = chapters.flatMap { c -> c.topics.map { Placed(c, it) } }.filter { it.topic.id != excluding }
        // iOS `max(by:)` keeps the FIRST of equal maxima.
        pairs.filter { progress[it.topic.id]?.checkLeft == true }
            .firstMaxBy { progress[it.topic.id]?.touchedAt ?: Long.MIN_VALUE }
            ?.let { return it }
        val lastChapter = pairs.mapNotNull { p -> progress[p.topic.id]?.touchedAt?.let { p.chapter.id to it } }
            .firstMaxBy { it.second }?.first
        val ordered = pairs.filter { it.chapter.id == lastChapter } + pairs.filter { it.chapter.id != lastChapter }
        val notPassed = ordered.filter { progress[it.topic.id]?.passedAt == null }
        return notPassed.firstOrNull { !isStepUp(it.topic, level) } ?: notPassed.firstOrNull()
    }

    private inline fun <T> List<T>.firstMaxBy(key: (T) -> Long): T? {
        var best: T? = null
        var bestKey = Long.MIN_VALUE
        for (x in this) {
            val k = key(x)
            if (best == null || k > bestKey) { best = x; bestKey = k }
        }
        return best
    }
}

/** How far a learner got with one topic of the map (iOS `TutorTopicProgress`). */
@Serializable
data class TutorTopicProgress(
    @Serializable(with = IsoDateMillisSerializer::class)
    val startedAt: Long? = null,
    /** Every challenge done; the final check is what's left. */
    @Serializable(with = IsoDateMillisSerializer::class)
    val lessonDoneAt: Long? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val passedAt: Long? = null,
    /** Final checks passed on this topic — the first is the tick, the rest
     *  are the depth shown beside it. */
    val rounds: Int = 0,
    @Serializable(with = IsoDateMillisSerializer::class)
    val touchedAt: Long? = null,
) {
    val checkLeft: Boolean get() = passedAt == null && lessonDoneAt != null
    val inProgress: Boolean get() = passedAt == null && lessonDoneAt == null && startedAt != null
}

/** `lang/<code>/tutor_progress.json`, per target language. Device-local, as on iOS. */
object TutorProgressStore {
    private val serializer = MapSerializer(String.serializer(), TutorTopicProgress.serializer())

    private fun file(context: Context, language: String) =
        File(LanguageScope.directory(context, language.substringBefore('-')), "tutor_progress.json")

    fun all(context: Context, language: String): Map<String, TutorTopicProgress> = runCatching {
        StoreJson.json.decodeFromString(serializer, file(context, language).readText())
    }.getOrDefault(emptyMap())

    @Synchronized
    fun update(context: Context, language: String, topicId: String,
               change: (TutorTopicProgress) -> TutorTopicProgress) {
        val all = all(context, language).toMutableMap()
        val p = change(all[topicId] ?: TutorTopicProgress()).copy(touchedAt = System.currentTimeMillis())
        all[topicId] = p
        runCatching { file(context, language).writeText(StoreJson.json.encodeToString(serializer, all)) }
    }
}
