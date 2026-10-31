import SwiftUI

/// Today, CHOSEN (2026-10-30, founder: "the app has too many things to do;
/// the tutor should be the place where you never lose what to do"). The note
/// said "Today: 2 things" and then listed six rows — the routine and every
/// pick, side by side — so the one surface meant to calm the day down added
/// to it. Now the tutor picks: ONE thing now, with why, one thing next, and
/// the rest of the day folded under "N more today". Nothing was removed; it
/// is all one tap down.
///
/// The order is fixed in code (`TutorToday.ranked`), never asked of a
/// model, so it is instant and can't disagree with My routine:
/// 1. a routine block whose time is on,
/// 2. the nearest goal's next piece not opened today (reading → model
///    answer → drill) — what the learner said they are preparing for,
/// 3. the routine's next blocks (now's and the one after),
/// 4. the other picks (a challenge rank lost, a new episode, a reading),
/// 5. everything else; done routine blocks last.
enum TutorToday {
    enum Entry: Identifiable, Equatable {
        case routine(TutorBot.Item)
        case pick(TutorPick)

        var id: String {
            switch self {
            case .routine(let i): return "r-\(i.id)"
            case .pick(let p): return "p-\(p.id)"
            }
        }
        var isDone: Bool {
            if case .routine(let i) = self { return i.done }
            return false
        }
    }

    private static let openedKey = "futurevoice.tutorBot.openedPicks"

    /// A pick tapped today drops out of "now" (its own page took over).
    static func markOpened(_ pick: TutorPick, now: Date = Date()) {
        var d = opened(now: now)
        d.insert(pick.id)
        UserDefaults.standard.set(["day": StudyPlan.dayKey(now), "ids": Array(d)], forKey: openedKey)
    }

    static func opened(now: Date = Date()) -> Set<String> {
        guard let saved = UserDefaults.standard.dictionary(forKey: openedKey),
              saved["day"] as? String == StudyPlan.dayKey(now) else { return [] }
        return Set(saved["ids"] as? [String] ?? [])
    }

    static func ranked(today: TutorBot.Today, picks: [TutorPick], now: Date = Date()) -> [Entry] {
        let opened = opened(now: now)
        var out: [Entry] = []
        var used = Set<String>()
        func add(_ e: Entry) { if used.insert(e.id).inserted { out.append(e) } }

        let isGoal: (TutorPick) -> Bool = { [.goalReading, .goalSpeech, .goalDrill].contains($0.kind) }
        if let on = today.items.first(where: { $0.isNow(now) }) { add(.routine(on)) }
        if let g = picks.first(where: { isGoal($0) && !opened.contains($0.id) }) { add(.pick(g)) }
        if let next = today.next(at: now) { add(.routine(next)) }
        // The routine is their own promise, so its next block comes before
        // anything the tutor merely offers (a new episode read as "next"
        // ahead of the 21:00 review on the first capture).
        if let after = today.items.first(where: { !$0.done && !used.contains("r-\($0.id)") }) {
            add(.routine(after))
        }
        for p in picks where !isGoal(p) && !opened.contains(p.id) { add(.pick(p)) }
        for i in today.items where !i.done { add(.routine(i)) }
        for p in picks { add(.pick(p)) }
        for i in today.items where i.done { add(.routine(i)) }
        return out
    }
}

/// The note's and the chat's list: now, next, and the rest folded.
struct TutorTodayRows: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var bot = TutorBot.shared
    @State private var expanded = false

    var body: some View {
        let entries = TutorToday.ranked(today: bot.today, picks: bot.picks)
        let open = entries.filter { !$0.isDone }
        let now = open.first
        let next = open.dropFirst().first
        let rest = entries.filter { $0.id != now?.id && $0.id != next?.id }
        VStack(alignment: .leading, spacing: 0) {
            if let now {
                caption(explain("Now"))
                row(now, prominent: true)
            }
            if let next {
                Divider().padding(.leading, 40)
                caption(explain("Next"))
                row(next, prominent: false)
            }
            if !rest.isEmpty {
                Divider().padding(.leading, 40)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(expanded ? explain("Show less") : explain("\(rest.count) more today"))
                            .font(.footnote.weight(.semibold))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.tint)
                    .padding(.vertical, 10)
                    .padding(.leading, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    if !bot.picks.isEmpty {
                        Text(explain("This week · speaking \(bot.balance.speaking) d · listening \(bot.balance.listening) d · reading \(bot.balance.reading) d"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 40)
                            .padding(.bottom, 4)
                    }
                    ForEach(Array(rest.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider().padding(.leading, 40) }
                        row(e, prominent: false)
                    }
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 40)
            .padding(.top, 6)
    }

    @ViewBuilder
    private func row(_ e: TutorToday.Entry, prominent: Bool) -> some View {
        switch e {
        case .routine(let item):
            Button { TutorBot.shared.start(item.kind, appState: appState) } label: {
                line(symbol: item.kind.symbol, color: item.kind.color, tag: nil, title: item.title,
                     detail: TutorCopy.when(item), done: item.done, progress: item.progress,
                     prominent: prominent)
            }
            .buttonStyle(.plain)
        case .pick(let pick):
            Button { TutorBot.shared.start(pick, appState: appState) } label: {
                line(symbol: pick.symbol, color: TutorPickRows.color(pick.kind), tag: pick.tag,
                     title: pick.title, detail: pick.why, done: false, progress: 0, prominent: prominent)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(pick.buttonTitle))
        }
    }

    private func line(symbol: String, color: Color, tag: String?, title: String, detail: String,
                      done: Bool, progress: Double, prominent: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(prominent ? .body : .footnote)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let tag { Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(color) }
                Text(title)
                    .font(prominent ? .body.weight(.semibold) : .subheadline)
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if progress > 0 {
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .scaleEffect(0.45)
                    .frame(width: 22, height: 22)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
        .padding(.vertical, prominent ? 10 : 8)
        .contentShape(Rectangle())
    }
}
