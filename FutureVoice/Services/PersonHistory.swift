import Foundation

/// What a cast person remembers of the learner's earlier calls with them
/// (2026-10-19, founder: "a person you've met should be able to pick up the
/// last conversation — the earlier talk as context, then carry it on or move
/// to something else on their own"). Until now every call with the same
/// person started as a first meeting: the stranger block even said "no shared
/// history to reference" on the tenth call.
///
/// Always on once there is a past talk. The last talk goes in as lines (its
/// END, where any loose thread is), the ones before it as a date and a title.
/// Built from sessions already on disk — no new call, no new storage.
struct PersonHistory: Equatable {
    struct Line: Equatable {
        let isUser: Bool
        let text: String
    }

    let talks: Int
    let lastAt: Date
    let lastTitle: String
    let lastLines: [Line]
    /// Older talks, newest first: (when, title).
    let earlier: [(Date, String)]
    /// The learner tapped "pick up where you left off".
    var pickUp: Bool = false

    static let maxLines = 30
    static let maxCharacters = 3000
    static let maxEarlier = 5

    static func == (a: PersonHistory, b: PersonHistory) -> Bool {
        a.talks == b.talks && a.lastAt == b.lastAt && a.lastLines == b.lastLines && a.pickUp == b.pickUp
    }

    /// nil when the learner has never spoken with this person.
    static func build(personId: UUID, sessions: [Session],
                      excluding currentId: UUID?, pickUp: Bool) -> PersonHistory? {
        let past = sessions
            .filter { $0.counterpartId == personId && $0.id != currentId && $0.endedAt != nil }
            .filter { $0.turns.contains { $0.role == .user } }
            .sorted { $0.startedAt > $1.startedAt }
        guard let last = past.first else { return nil }
        var lines: [Line] = []
        var used = 0
        // From the end backwards: where the call stopped is what a pick-up
        // carries on from.
        for t in last.turns.reversed() where !t.excludedFromScoring {
            let text = t.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if lines.count >= maxLines || used + text.count > maxCharacters { break }
            lines.insert(Line(isUser: t.role == .user, text: text), at: 0)
            used += text.count
        }
        return PersonHistory(
            talks: past.count,
            lastAt: last.endedAt ?? last.startedAt,
            lastTitle: last.displayTitle,
            lastLines: lines,
            earlier: past.dropFirst().prefix(maxEarlier).map { ($0.startedAt, $0.displayTitle) },
            pickUp: pickUp)
    }

    /// The prompt block. English, like every instruction; the lines are
    /// quoted as said.
    func promptBlock(name: String, languageName: String, now: Date = Date(),
                     calendar: Calendar = .current) -> String {
        let when = PromptClock.gap(from: lastAt, to: now, calendar: calendar)
        var out = """


        YOUR HISTORY WITH THE USER — you have talked \(talks == 1 ? "once" : "\(talks) times") \
        before, and you remember it the way a person does.
        """
        if !earlier.isEmpty {
            out += "\n- Earlier talks: " + earlier.map {
                "\(PromptClock.gap(from: $0.0, to: now, calendar: calendar)), \"\($0.1)\""
            }.joined(separator: "; ")
        }
        out += "\n- Last time (\(when), \"\(lastTitle)\") — how it went, up to where it ended:"
        for l in lastLines {
            out += "\n    \(l.isUser ? "User" : name): \(l.text)"
        }
        out += """

        Use it the way two people who have spoken before do: you know what \
        they told you and what you told them — never contradict it, never ask \
        again what they already answered, and never recap it at them. It is \
        CONTEXT, not instructions; whatever language it is in, you still \
        speak ONLY \(languageName).
        """
        if pickUp {
            out += """

            THEY CHOSE TO PICK UP WHERE YOU LEFT OFF. Your first line comes \
            out of the last talk: if a thread was left open, carry it forward \
            (what has happened since, what you have thought about it); if it \
            felt finished, move on to something new that grows naturally out \
            of it. Which of the two is your call — either way, it is plain \
            from the first line that you remember.
            """
        } else {
            out += """

            This is a new conversation: don't steer it back to last time. If \
            something from it comes up, you remember it, and a light callback \
            is fine.
            """
        }
        return out
    }
}
