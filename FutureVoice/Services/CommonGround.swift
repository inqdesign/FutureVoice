import Foundation

/// What the learner and the person they're talking to actually have in
/// common, worked out in CODE before any prompt is written.
///
/// Two strangers don't open on a randomly chosen fact from one side's
/// biography — they find the overlap and start there. The scene and
/// conversation prompts used to inject the learner and the counterpart as two
/// separate blocks with no instruction to cross them, so the model picked
/// something arbitrary from the counterpart's intro. With a thin intro (a real
/// user's, auto-published from onboarding: a job, a city, a household) there
/// was almost nothing to pick, so it invented — and that is where the strange
/// topics came from.
///
/// Computing it here rather than asking the model to "find what you share"
/// follows the same rule as every other derived value in the app: if code can
/// work it out, the model doesn't get to guess at it.
enum CommonGround {

    /// One line per thing the two genuinely share, most concrete first.
    /// Empty when they share nothing findable — the caller then says so
    /// explicitly instead of letting the model imagine an overlap.
    static func between(learner: UserPersona?, counterpart: Counterpart) -> [String] {
        guard let p = learner else { return [] }
        var found: [String] = []

        // Same place beats every other overlap: it gives a scene somewhere to
        // physically be, and two people in one city always have something.
        let theirPlace = counterpart.location.lowercased()
        for mine in [p.city, p.country] where !mine.isEmpty {
            if theirPlace.contains(mine.lowercased()) {
                found.append("both in \(mine)")
                break
            }
        }

        // Interests: the learner's list against whatever the person is known
        // to talk about (their topics, their work, their own words).
        let theirs = (counterpart.commonTopics + " " + counterpart.occupationLike)
            .lowercased()
        for interest in p.interests {
            let needle = interest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard needle.count >= 3, theirs.contains(needle) else { continue }
            found.append("both into \(interest)")
        }

        // Same shape of life. These are the things people actually bond over
        // on meeting, and none of them show up as a matching keyword.
        let theirText = ([counterpart.intro, counterpart.background,
                          counterpart.commonTopics, counterpart.location]
                            .joined(separator: " ")).lowercased()
        if !p.household.isEmpty, mentionsFamily(p.household), mentionsFamily(theirText) {
            found.append("both have kids at home")
        }
        if counterpart.personaKind == "user" {
            // Two learners: the situation itself is the common ground, and
            // it's the most reliable one in the pool.
            found.append("both learning this language, and both know what it is to be the slowest person in the room")
        }

        return found
    }

    /// The block to splice into a prompt. Never invents an overlap: when
    /// there is none it says what to do instead, because "find common ground"
    /// with nothing in common is exactly what produced the odd topics.
    static func block(learner: UserPersona?, counterpart: Counterpart) -> String {
        let shared = between(learner: learner, counterpart: counterpart)
        guard !shared.isEmpty else {
            return """
            COMMON GROUND: none found. Don't force one. Open on something \
            concrete from YOUR OWN life (the person you are), the way a real \
            person offers a piece of themselves first, and let the learner \
            pick up whatever interests them.
            """
        }
        return """
        COMMON GROUND — start here, this is what you two actually share:
        \(shared.map { "- \($0)" }.joined(separator: "\n"))
        Real strangers open on the overlap, not on a fact plucked from one \
        side's biography. Take one of these and get specific about it fast.
        """
    }

    private static func mentionsFamily(_ text: String) -> Bool {
        let markers = ["kid", "child", "children", "son", "daughter", "kita",
                       "school", "baby", "toddler", "아이", "아들", "딸", "육아",
                       "Kind", "Kinder", "Tochter", "Sohn"]
        let lower = text.lowercased()
        return markers.contains { lower.contains($0.lowercased()) }
    }
}

private extension Counterpart {
    /// The person's work, wherever it's recorded. Own personas keep it in the
    /// free-text background; pool rows carry it as part of the intro.
    var occupationLike: String { [relationship, background].joined(separator: " ") }
}
