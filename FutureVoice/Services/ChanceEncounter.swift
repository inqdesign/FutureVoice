import Foundation

/// Bumping into someone (2026-11-04, founder: "someone you just happen to
/// meet, at random"). It is a SITUATION: the Watch map's two-figures button
/// deals ONE person and ONE place, the card's first action WATCHES the scene
/// (an ordinary `Scenario` with that person, `scenario(for:existing:)`), and
/// a call with them there is the option beside it — the place is the call's
/// topic, so the person block, their own voice, their memory of earlier
/// talks (`PersonHistory`) and the saved book are all the existing ones.
///
/// Two kinds of moment. A MEETING casts a stranger from the pool as
/// themselves, met somewhere two strangers fall into talk. A ROLE moment
/// (a barista, a neighbour) is played by a built-in character, because
/// those are job-free on purpose (`StockPerson`) — a pool persona with a
/// job of their own would be cast against it.
struct ChanceEncounter: Identifiable, Equatable {
    let id = UUID()
    let person: Counterpart
    let moment: Moment
    /// They have talked before: the call says they ran into each other again.
    let metBefore: Bool

    static func == (a: ChanceEncounter, b: ChanceEncounter) -> Bool { a.id == b.id }

    struct Moment: Equatable {
        /// Stable id, for not dealing the same place twice in a row.
        let key: String
        /// Played by a built-in character in this role; nil = a stranger as themselves.
        let role: String?
        /// The learner's side, for the scene engine ("what the learner is
        /// going in to do"). Machine-consumed, so English.
        let situation: String
        /// The other person's side, for a call with them there. English.
        let scene: String

        /// The card's line, in the app language.
        var place: String {
            switch key {
            case "bakery": return explain(key: "encounter.bakery", default: "In line at the bakery, the person ahead turns around")
            case "train": return explain(key: "encounter.train", default: "On the train, in the seat next to you")
            case "rain": return explain(key: "encounter.rain", default: "Sheltering from the rain under the same awning")
            case "gate": return explain(key: "encounter.gate", default: "At the gate, the same flight is delayed")
            case "bookshop": return explain(key: "encounter.bookshop", default: "At the bookshop, reaching for the same book")
            case "laundromat": return explain(key: "encounter.laundromat", default: "At the laundromat, waiting for the dryers")
            case "party": return explain(key: "encounter.party", default: "At a friend's party, by the snacks")
            case "bench": return explain(key: "encounter.bench", default: "Sharing a bench in the park")
            case "cafeTable": return explain(key: "encounter.cafeTable", default: "The café is full, and someone asks to share your table")
            case "barista": return explain(key: "encounter.barista", default: "The barista mixed up your order")
            case "neighbor": return explain(key: "encounter.neighbor", default: "A new neighbor knocks on your door")
            case "taxi": return explain(key: "encounter.taxi", default: "A chatty taxi driver")
            default: return explain(key: "encounter.hotel", default: "The hotel can't find your booking")
            }
        }
    }

    static let meetings: [Moment] = [
        Moment(key: "bakery", role: nil, situation: "Waiting in line at a bakery when the person ahead turns around and starts chatting", scene: "You're standing in line at a bakery behind the user; you turn around and say something about the queue or what's left on the shelves."),
        Moment(key: "train", role: nil, situation: "Sitting on a train next to a stranger who starts a conversation", scene: "You're sitting next to the user on a train; something about the journey (a stop, the view, an announcement) gives you a reason to speak."),
        Moment(key: "rain", role: nil, situation: "Sheltering from a sudden downpour under a shop awning with a stranger", scene: "A sudden downpour has you and the user sheltering under the same shop awning, waiting for it to ease off."),
        Moment(key: "gate", role: nil, situation: "At the airport gate when our flight is delayed, chatting with another passenger", scene: "You and the user are at the same airport gate and the flight has just been announced as delayed."),
        Moment(key: "bookshop", role: nil, situation: "Reaching for the same book as someone else in a bookshop", scene: "In a bookshop you and the user reach for the same book at the same moment."),
        Moment(key: "laundromat", role: nil, situation: "Waiting for the dryers at a laundromat next to someone", scene: "You're both waiting at a laundromat for the dryers to finish."),
        Moment(key: "party", role: nil, situation: "At a friend's party, standing by the snacks next to someone I don't know", scene: "You're at a mutual friend's party and end up next to the user by the snack table; you don't know many people here either."),
        Moment(key: "bench", role: nil, situation: "Sharing a park bench with a stranger on a nice afternoon", scene: "You're sitting on the same park bench as the user on a nice afternoon."),
        Moment(key: "cafeTable", role: nil, situation: "In a packed café, someone asks to share my table", scene: "The café is packed; you ask the user if you can share their table, then sit down."),
    ]

    static let roles: [Moment] = [
        Moment(key: "barista", role: "the barista", situation: "At a busy café, the barista hands me the wrong drink", scene: "You are the barista at a busy café. You've just handed the user the wrong drink, and you realize it as they look at it."),
        Moment(key: "neighbor", role: "the new neighbor", situation: "A new neighbor knocks on my door to say hello", scene: "You've just moved in next door to the user and knock on their door to introduce yourself (and ask something small about the building)."),
        Moment(key: "taxi", role: "the taxi driver", situation: "Riding in a taxi with a chatty driver", scene: "You are a taxi driver; the user has just got in. You like to chat with passengers."),
        Moment(key: "hotel", role: "the hotel receptionist", situation: "Checking into a hotel that can't find my booking", scene: "You work at a hotel front desk; the user is checking in and you can't find their booking under their name."),
    ]

    /// Share of encounters that are a role moment.
    static let roleShare = 0.3

    /// One encounter. `strangers` is everyone the map can show from the pool
    /// (met or not); `avoiding` is the last encounter, so "Someone else"
    /// never hands back the same face or the same place.
    @MainActor static func deal(strangers: [Counterpart], counterparts: [Counterpart],
                     metIds: Set<UUID>, avoiding last: ChanceEncounter?) -> ChanceEncounter? {
        let pool = strangers.filter { $0.id != last?.person.id && !PublicPersonaService.isWithdrawnLearner($0) }
        let useRole = pool.isEmpty || Double.random(in: 0..<1) < roleShare
        if useRole {
            let moment = roles.filter { $0.key != last?.moment.key }.randomElement() ?? roles[0]
            let stock = StockPerson.catalog.filter { $0.localId != last?.person.id }.randomElement()
                ?? StockPerson.catalog[0]
            let person = stock.asCounterpart(existing: counterparts)
            return ChanceEncounter(person: person, moment: moment, metBefore: metIds.contains(person.id))
        }
        guard let person = pool.randomElement() else { return nil }
        let moment = meetings.filter { $0.key != last?.moment.key }.randomElement() ?? meetings[0]
        return ChanceEncounter(person: person, moment: moment, metBefore: metIds.contains(person.id))
    }

    /// The scene to watch: one `Scenario` per person and place, so a second
    /// bump into the same person in the same place writes a fresh take into
    /// the same book. A meeting, not a situation the learner built
    /// (`isMeeting`), so it stays out of "Your scenarios"; the book is in
    /// Practice.
    static let category = "Encounter"

    func scenario(existing: [Scenario]) -> (Scenario, isNew: Bool) {
        if let s = existing.first(where: {
            $0.counterpartId == person.id && $0.category == Self.category
                && $0.environment == moment.situation
        }) { return (s, false) }
        var s = Scenario(
            environment: moment.situation,
            role: moment.role ?? "",
            notes: "A chance encounter, nothing planned: the two of them happen to be "
                + "in the same place and the OTHER person speaks first, with something the "
                + "moment hands them. Light, unplanned talk that can wander from there. "
                + "Not a get-to-know-you interview."
        )
        s.counterpartId = person.id
        s.isMeeting = true
        s.category = Self.category
        s.categoryIcon = "figure.2.arms.open"
        s.summary = moment.place
        return (s, true)
    }

    /// The call's Starting context, after the place line (the topic).
    var blurb: String {
        var lines = ["A CHANCE ENCOUNTER, nothing planned: \(moment.scene)"]
        if let role = moment.role {
            lines.append("Today you are \(role) in this scene.")
        }
        if metBefore {
            lines.append("You and the user have talked before, and you've just run into each other again here — recognise them.")
        }
        lines.append("YOU speak first, with something the moment itself hands you. Keep it the light, unplanned talk people fall into; it can wander anywhere from there.")
        return lines.joined(separator: " ")
    }
}
