package com.roro.futurevoice.ui

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.StockPerson

/**
 * Bumping into someone (iOS `ChanceEncounter`, 59680063, 2026-11-04,
 * founder: "someone you just happen to meet, at random"). It is a SITUATION:
 * the Watch map's two-figures button deals ONE person and ONE place, the
 * card's first action WATCHES the scene (an ordinary [Scenario] with that
 * person, [scenario]), and a call with them there is the option beside it —
 * the place is the call's topic, so the person block, their own voice, their
 * memory of earlier talks and the saved book are all the existing ones.
 *
 * Two kinds of moment. A MEETING casts a stranger from the pool as
 * themselves, met somewhere two strangers fall into talk. A ROLE moment
 * (a barista, a neighbour) is played by a built-in character, because those
 * are job-free on purpose ([StockPerson]) — a pool persona with a job of
 * their own would be cast against it.
 */
data class ChanceEncounter(
    val person: Counterpart,
    val moment: Moment,
    /** They have talked before: the call says they ran into each other again. */
    val metBefore: Boolean,
    val id: String = java.util.UUID.randomUUID().toString(),
) {
    data class Moment(
        /** Stable id, for not dealing the same place twice in a row. */
        val key: String,
        /** Played by a built-in character in this role; null = a stranger as themselves. */
        val role: String?,
        /** The learner's side, for the scene engine ("what the learner is
         *  going in to do"). Machine-consumed, so English. */
        val situation: String,
        /** The other person's side, for a call with them there. English. */
        val scene: String,
    ) {
        /** The card's line, in the app language. */
        fun place(context: Context): String = context.getString(when (key) {
            "bakery" -> R.string.encounter_bakery
            "train" -> R.string.encounter_train
            "rain" -> R.string.encounter_rain
            "gate" -> R.string.encounter_gate
            "bookshop" -> R.string.encounter_bookshop
            "laundromat" -> R.string.encounter_laundromat
            "party" -> R.string.encounter_party
            "bench" -> R.string.encounter_bench
            "cafeTable" -> R.string.encounter_cafetable
            "barista" -> R.string.encounter_barista
            "neighbor" -> R.string.encounter_neighbor
            "taxi" -> R.string.encounter_taxi
            else -> R.string.encounter_hotel
        })
    }

    /** A new encounter with the same person and place (the saved row of the
     *  person, once the gate passed) — a fresh id, like iOS's `init`. */
    fun savedAs(person: Counterpart): ChanceEncounter = ChanceEncounter(person, moment, metBefore)

    /**
     * The scene to watch: one [Scenario] per person and place, so a second
     * bump into the same person in the same place writes a fresh take into
     * the same book. A meeting, not a situation the learner built
     * (`isMeeting`), so it stays out of "Your scenarios"; the book is in
     * Practice. Returns the scenario and whether it is new.
     */
    fun scenario(context: Context, existing: List<Scenario>): Pair<Scenario, Boolean> {
        existing.firstOrNull {
            it.counterpartId == person.id && it.category == CATEGORY && it.environment == moment.situation
        }?.let { return it to false }
        val s = Scenario(
            environment = moment.situation,
            role = moment.role ?: "",
            notes = "A chance encounter, nothing planned: the two of them happen to be " +
                "in the same place and the OTHER person speaks first, with something the " +
                "moment hands them. Light, unplanned talk that can wander from there. " +
                "Not a get-to-know-you interview.",
            counterpartId = person.id,
            isMeeting = true,
            category = CATEGORY,
            categoryIcon = "figure.2.arms.open",
            summary = moment.place(context),
        )
        return s to true
    }

    /** The call's Starting context, after the place line (the topic). */
    val blurb: String
        get() {
            val lines = mutableListOf("A CHANCE ENCOUNTER, nothing planned: ${moment.scene}")
            moment.role?.let { lines += "Today you are $it in this scene." }
            if (metBefore) {
                lines += "You and the user have talked before, and you've just run into each other again here — recognise them."
            }
            lines += "YOU speak first, with something the moment itself hands you. Keep it the light, unplanned talk people fall into; it can wander anywhere from there."
            return lines.joinToString(" ")
        }

    companion object {
        val meetings: List<Moment> = listOf(
            Moment("bakery", null, "Waiting in line at a bakery when the person ahead turns around and starts chatting", "You're standing in line at a bakery behind the user; you turn around and say something about the queue or what's left on the shelves."),
            Moment("train", null, "Sitting on a train next to a stranger who starts a conversation", "You're sitting next to the user on a train; something about the journey (a stop, the view, an announcement) gives you a reason to speak."),
            Moment("rain", null, "Sheltering from a sudden downpour under a shop awning with a stranger", "A sudden downpour has you and the user sheltering under the same shop awning, waiting for it to ease off."),
            Moment("gate", null, "At the airport gate when our flight is delayed, chatting with another passenger", "You and the user are at the same airport gate and the flight has just been announced as delayed."),
            Moment("bookshop", null, "Reaching for the same book as someone else in a bookshop", "In a bookshop you and the user reach for the same book at the same moment."),
            Moment("laundromat", null, "Waiting for the dryers at a laundromat next to someone", "You're both waiting at a laundromat for the dryers to finish."),
            Moment("party", null, "At a friend's party, standing by the snacks next to someone I don't know", "You're at a mutual friend's party and end up next to the user by the snack table; you don't know many people here either."),
            Moment("bench", null, "Sharing a park bench with a stranger on a nice afternoon", "You're sitting on the same park bench as the user on a nice afternoon."),
            Moment("cafeTable", null, "In a packed café, someone asks to share my table", "The café is packed; you ask the user if you can share their table, then sit down."),
        )

        val roles: List<Moment> = listOf(
            Moment("barista", "the barista", "At a busy café, the barista hands me the wrong drink", "You are the barista at a busy café. You've just handed the user the wrong drink, and you realize it as they look at it."),
            Moment("neighbor", "the new neighbor", "A new neighbor knocks on my door to say hello", "You've just moved in next door to the user and knock on their door to introduce yourself (and ask something small about the building)."),
            Moment("taxi", "the taxi driver", "Riding in a taxi with a chatty driver", "You are a taxi driver; the user has just got in. You like to chat with passengers."),
            Moment("hotel", "the hotel receptionist", "Checking into a hotel that can't find my booking", "You work at a hotel front desk; the user is checking in and you can't find their booking under their name."),
        )

        /** Share of encounters that are a role moment. */
        const val ROLE_SHARE = 0.3

        const val CATEGORY = "Encounter"

        /**
         * One encounter. [strangers] is everyone the map can show from the
         * pool (met or not); [last] is the last encounter, so "Someone else"
         * never hands back the same face or the same place.
         */
        fun deal(
            strangers: List<Counterpart>,
            counterparts: List<Counterpart>,
            metIds: Set<String>,
            last: ChanceEncounter?,
        ): ChanceEncounter? {
            val pool = strangers.filter { it.id != last?.person?.id && !PublicPersonaClient.isWithdrawnLearner(it) }
            val useRole = pool.isEmpty() || kotlin.random.Random.nextDouble() < ROLE_SHARE
            if (useRole) {
                val moment = roles.filter { it.key != last?.moment?.key }.randomOrNull() ?: roles[0]
                val stock = StockPerson.catalog.filter { it.localId != last?.person?.id }.randomOrNull()
                    ?: StockPerson.catalog[0]
                val person = stock.asCounterpart(counterparts)
                return ChanceEncounter(person, moment, metIds.contains(person.id))
            }
            val person = pool.randomOrNull() ?: return null
            val moment = meetings.filter { it.key != last?.moment?.key }.randomOrNull() ?: meetings[0]
            return ChanceEncounter(person, moment, metIds.contains(person.id))
        }
    }
}
