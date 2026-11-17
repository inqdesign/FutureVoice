import Foundation

/// A free talk remembers the talks before it, and looks one up when it comes
/// up (2026-11-17, founder: "keep the memory somewhere and take it out when
/// it is needed").
///
/// Until now a free talk knew three things about the past: the profile, up
/// to twelve remembered facts (0–3 a talk, twelve words each), and the end of
/// ONE talk from earlier today. Yesterday's half hour was three facts the
/// next morning, and the model had no way to look: a learner was told "I
/// don't have a clear record of you saying that".
///
/// The store already exists: every talk is on the phone, whole. What was
/// missing is the fetch, and the model cannot do it (the talks are on the
/// phone, the model is not, and a reply that stops to search is a silence
/// on a call). So the APP fetches:
///   • the prompt always carries an INDEX, one line per earlier talk (when,
///     and its title), so the model knows the talk happened;
///   • after each learner line, the app asks whether it refers to one of
///     those talks (`mayRecall` in code first, then one small model call),
///     and if so puts that talk's lines into the prompt (`set.system`).
/// Nothing waits on it: the line that first mentions the talk is answered
/// from the index, the ones after it from the talk itself.
enum TalkRecall {

    /// One earlier talk with the fluent self.
    struct Entry: Equatable, Identifiable {
        let session: Session
        let endedAt: Date
        var id: UUID { session.id }
        var title: String { session.displayTitle }

        static func == (a: Entry, b: Entry) -> Bool { a.id == b.id }
    }

    /// How many talks the index lists. A prompt line each; older talks are
    /// still on the phone, just not offered.
    static let indexSize = 12
    /// How many looked-up talks a call's prompt holds at once.
    static let heldAtOnce = 2

    /// The talks worth remembering, newest first: with the fluent self (a
    /// talk with a cast person is that person's, `PersonHistory`), the
    /// learner spoke in it, and it is not this call or the talk the prompt
    /// already carries whole (`EarlierToday`).
    static func index(sessions: [Session], now: Date, excluding: Set<UUID>) -> [Entry] {
        sessions.compactMap { s -> Entry? in
            guard !excluding.contains(s.id), s.counterpartId == nil, s.origin != .scenario,
                  s.turns.contains(where: { $0.role == .user && !$0.excludedFromScoring }) else { return nil }
            let at = s.turns.map(\.timestamp).max() ?? s.endedAt ?? s.startedAt
            return at <= now ? Entry(session: s, endedAt: at) : nil
        }
        .sorted { $0.endedAt > $1.endedAt }
        .prefix(indexSize).map { $0 }
    }

    /// The index as the prompt carries it.
    static func indexLines(_ entries: [Entry], now: Date, calendar: Calendar = .current) -> [String] {
        entries.map { "\(PromptClock.gap(from: $0.endedAt, to: now, calendar: calendar)): \"\(clip($0.title, 90))\"" }
    }

    // MARK: - Is this line about an earlier talk?

    /// Worth asking the judge? A word that points at the past, in any target
    /// language or the native ones most learners here speak, or a word the
    /// line shares with a title. Wide on purpose: a miss here is "I have no
    /// record of that".
    static func mayRecall(_ text: String, entries: [Entry]) -> Bool {
        guard !entries.isEmpty else { return false }
        let t = text.lowercased()
        if cues.contains(where: { t.contains($0) }) { return true }
        let said = words(t)
        return entries.contains { !said.isDisjoint(with: words($0.title.lowercased())) }
    }

    /// Words long enough to be about something.
    private static func words(_ text: String) -> Set<String> {
        Set(WordSplitter.spaced
            ? CarryoverDetector.spendTokens(text).filter { $0.count >= 5 }.map(CarryoverDetector.folded)
            : WordSplitter.segments(text).filter { $0.count >= 2 })
    }

    private static let cues: [String] = [
        // en
        "yesterday", "last time", "last week", "last month", "the other day", "remember", "told you",
        "i said", "i mentioned", "we talked", "we spoke", "we discussed", "talked about", "earlier",
        "before", "again", "still ", "ago", "you know the", "you know my",
        // ko
        "어제", "그저께", "지난", "저번", "기억", "말했", "얘기했", "이야기했", "전에", "아까", "그때", "그 때",
        // ja
        "昨日", "おととい", "先週", "先月", "この前", "この間", "覚えて", "言った", "話した", "前に", "さっき", "あの時",
        // de
        "gestern", "vorgestern", "letzte", "letztes", "letzten", "neulich", "erinner", "erzählt", "gesagt",
        "gesprochen", "vorhin", "damals", "weißt du noch",
        // es
        "ayer", "anteayer", "pasada", "pasado", "el otro día", "recuerd", "acuerd", "te dije", "te conté",
        "hablamos", "antes", "otra vez", "todavía",
        // fr
        "hier", "dernier", "dernière", "l'autre jour", "souvien", "rappel", "je t'ai dit", "on a parlé",
        "raconté", "avant", "encore", "toujours",
        // zh
        "昨天", "前天", "上次", "上周", "上週", "上个月", "上個月", "记得", "記得", "说过", "說過", "提到",
        "之前", "那次",
    ]

    static let system = """
        A language learner is on a voice call with someone they talk to \
        often. You get a numbered list of earlier talks between the two \
        (when each was, its title, and some of what the learner said in \
        it), then the last line said to the learner and the learner's \
        newest line.
        Decide whether the newest line is about something from ONE of the \
        earlier talks: it brings that talk up ("the interview I told you \
        about"), carries on with its particular subject (the same event, \
        person, plan or problem), or asks what was said in it.
        A general subject is not enough: two talks about work are not the \
        same talk. A line about today, or about something none of the \
        listed talks holds, is none. When two talks fit, take the more \
        recent one.
        Return {"talk": <number>} or {"talk": null}.
        """

    static func content(entries: [Entry], lastReply: String, newest: String, now: Date,
                        calendar: Calendar = .current) -> String {
        let list = entries.enumerated().map { i, e in
            "\(i + 1). \(PromptClock.gap(from: e.endedAt, to: now, calendar: calendar)) — \"\(clip(e.title, 90))\"\n   the learner said: \(gist(e.session))"
        }.joined(separator: "\n")
        return "Earlier talks, newest first:\n\(list)\n\nLast line said to the learner: \"\(clip(lastReply, 300))\"\nNewest line from the learner: \"\(clip(newest, 400))\""
    }

    /// Some of what the learner said in a talk, for the judge only.
    static func gist(_ session: Session, budget: Int = 420) -> String {
        var out = ""
        for turn in session.turns where turn.role == .user && !turn.excludedFromScoring {
            let text = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let piece = clip(text, 140)
            if out.count + piece.count > budget { break }
            out += (out.isEmpty ? "" : " / ") + piece
        }
        return "\"\(out)\""
    }

    private struct Verdict: Decodable { let talk: Int? }

    /// The earlier talk the newest line is about, or nil. Free (`coach`).
    static func recalled(newest: String, lastReply: String, entries: [Entry], turnId: UUID,
                         now: Date = Date()) async -> Entry? {
        guard !entries.isEmpty else { return nil }
        let v: Verdict? = try? await GeminiClient.background.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user,
                                            content: content(entries: entries, lastReply: lastReply,
                                                             newest: newest, now: now))],
            model: .flashLite31, maxTokens: 100, purpose: "coach",
            idempotencyKey: "recall:\(turnId.uuidString)", requestTimeout: 8,
            fastThinking: true)
        guard let n = v?.talk, entries.indices.contains(n - 1) else { return nil }
        return entries[n - 1]
    }

    // MARK: - The talk itself

    /// The looked-up talk as the prompt carries it: when, its title, and its
    /// lines around what the learner is talking about now.
    static func record(of entry: Entry, about query: String, now: Date,
                       calendar: Calendar = .current, lines count: Int = 24, budget: Int = 2400) -> String {
        let gap = PromptClock.gap(from: entry.endedAt, to: now, calendar: calendar)
        // A line flagged as misheard was never theirs, and the reply after it
        // was built on it (`EarlierToday.lastLines`).
        var dropped = Set<UUID>()
        let all = entry.session.turns
        for (i, t) in all.enumerated() where t.role == .user && t.excludedFromScoring {
            dropped.insert(t.id)
            if i + 1 < all.count, all[i + 1].role != .user { dropped.insert(all[i + 1].id) }
        }
        let turns = all.filter {
            !dropped.contains($0.id) && !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !turns.isEmpty else { return "A talk you two had \(gap), \"\(clip(entry.title, 90))\"." }

        // Centre on the line that shares the most with what was just said.
        let asked = words(query.lowercased())
        let scores = turns.map { words($0.transcript.lowercased()).intersection(asked).count }
        let centre = scores.max().flatMap { $0 > 0 ? scores.firstIndex(of: $0) : nil } ?? 0
        var lo = centre, hi = centre
        func line(_ t: Turn) -> String { "\(t.role == .user ? "them" : "you"): \"\(clip(t.transcript, 200))\"" }
        var used = line(turns[centre]).count
        // Grow forward first: what came after the mention is what it led to.
        while hi - lo + 1 < count {
            let next = hi + 1 < turns.count ? hi + 1 : nil
            let prev = lo > 0 ? lo - 1 : nil
            guard let pick = (hi - centre <= (centre - lo) * 2 ? next ?? prev : prev ?? next) else { break }
            let cost = line(turns[pick]).count
            guard used + cost <= budget else { break }
            used += cost
            if pick > hi { hi = pick } else { lo = pick }
        }
        let whole = lo == 0 && hi == turns.count - 1
        let body = turns[lo...hi].map(line).joined(separator: "\n")
        return "A talk you two had \(gap), \"\(clip(entry.title, 90))\".\n\(whole ? "All of it" : "Part of it"), oldest first:\n\(body)"
    }

    private static func clip(_ s: String, _ max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= max ? t : String(t.prefix(max - 1)) + "…"
    }
}
