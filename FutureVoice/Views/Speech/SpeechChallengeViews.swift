import SwiftUI

// MARK: - Card on the Speech tab

/// One challenge as a card, the review page's book card anatomy
/// (2026-10-16, founder): the trophy in a tinted disc top-left, the
/// learner's standing top-right, the title large, one quiet line under it,
/// and the board's top three at the foot.
struct SpeechChallengeRow: View {
    let script: SpeechScript
    let standing: SpeechChallenges.Standing?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                BookIconDisc {
                    Image(systemName: "trophy.fill").font(.title3).foregroundStyle(.tint)
                }
                // "New" rides on the trophy's corner, not in the rank's slot:
                // there it vanished the moment the learner had a record, and
                // the card's corner changed shape (founder, 2026-10-18).
                // One word in every language — the translations ran long and
                // wrapped into a ball on large text.
                .overlay(alignment: .bottomTrailing) {
                    if isNew {
                        Text(verbatim: "New")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 14, y: 4)
                    }
                }
                Spacer()
                if let rank = standing?.myRank, let best = standing?.myBest {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("#\(rank)")
                            .font(.headline.monospacedDigit())
                        Text("\(best)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(SpeechScoreColor.color(best))
                    }
                }
            }
            // The title hangs under the disc; the meta line belongs to the
            // FOOT, just above the faces, so it sits at the same height on
            // every card whatever the title's length. The slack goes between.
            Text(script.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Spacer(minLength: 16)
            Text(metaLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.bottom, 8)
            // The board's top three, or, on a board nobody is on yet, an
            // invitation in the same slot so every card ends alike.
            if let faces = standing?.topThree, !faces.isEmpty {
                SpeechChallengeFaces(faces: faces, size: 30)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                    Text("Be the first").lineLimit(1)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(height: 30)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
    }

    /// Out within the last week — whether or not this learner has taken it.
    private var isNew: Bool {
        script.createdAt > Date().addingTimeInterval(-7 * 86_400)
    }

    private var metaLine: String {
        let length = SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language))
        // "0 taking part" says the same thing as the foot, only sadder.
        let entrants = standing?.entrants ?? 0
        guard entrants > 0 else { return length }
        return [explain("\(entrants) taking part"), length].joined(separator: " · ")
    }
}

extension View {
    /// A card standing alone in a List: no row fill, no separator, a gap
    /// above and below, and the push without the row's chevron.
    func speechCardRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }
}

/// A NavigationLink drawn as its card alone — a List would add a chevron
/// and a row fill around it.
struct SpeechCardLink<Destination: View, Label: View>: View {
    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            NavigationLink(destination: destination) { EmptyView() }
                .opacity(0)
            label()
        }
        .speechCardRow()
    }
}

/// The board's top three as overlapping circles, first place in front: the
/// photo when they chose to show one, else their initial.
struct SpeechChallengeFaces: View {
    let faces: [SpeechChallenges.Face]
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(Array(faces.prefix(3).enumerated()), id: \.offset) { i, face in
                SpeechChallengeFace(face: face, size: size)
                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    .zIndex(Double(3 - i))
            }
        }
        .accessibilityHidden(true)
    }
}

struct SpeechChallengeFace: View {
    let face: SpeechChallenges.Face
    var size: CGFloat = 22
    /// The learner's own photo, drawn straight from `AvatarStore`.
    var localImage: UIImage? = nil

    var body: some View {
        Group {
            if let image = localImage ?? face.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(face.display_name.first.map { String($0).uppercased() } ?? "")
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
                    // The fill is translucent: on its own, the face behind it
                    // in an overlapping stack showed through (2026-10-14).
                    .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - One challenge: its board and the way in

struct SpeechChallengeView: View {
    let script: SpeechScript
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenges = SpeechChallenges.shared
    @ObservedObject private var gate = BillingGate.shared
    @ObservedObject private var store = SpeechStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var board: [SpeechChallenges.BoardRow]?
    @State private var loadFailed = false
    @State private var practicing = false
    @State private var naming = false
    /// The name sheet was raised by the start button: start once it's saved.
    @State private var startAfterNaming = false
    @State private var showingScript = false
    @State private var showingTakes = false
    @State private var confirmRetire = false

    private var standing: SpeechChallenges.Standing? { challenges.standings[script.id] }
    /// Retired: the board is frozen and nobody can enter.
    private var isPast: Bool { standing?.retiredAt != nil }

    var body: some View {
        List {
            Section {
                if let board {
                    if board.isEmpty {
                        Text("Nobody's on this board yet. Be the first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rowsWithGap(board), id: \.id) { item in
                            switch item {
                            case .row(let row): boardRow(row)
                            case .gap: Text("…").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                            }
                        }
                    }
                } else if loadFailed {
                    Text("The board couldn't load. Pull to try again.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } header: {
                Text("Leaderboard")
            } footer: {
                if isPast {
                    Text("This challenge has ended. These are the final standings.")
                } else {
                    Text("Only takes with the camera on go on the board, and your best one stands. The board shows your name and score — your video and voice stay on your phone.")
                }
            }

            if let best = standing?.myBest, let rank = standing?.myRank {
                Section("You") {
                    LabeledContent("Best") {
                        Text("\(best)")
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SpeechScoreColor.color(best))
                    }
                    LabeledContent("Place") {
                        Text("#\(rank) of \(standing?.entrants ?? rank)")
                            .monospacedDigit()
                    }
                    if let attempts = standing?.myAttempts {
                        // Tapping the count lists them (2026-10-16, founder).
                        Button { showingTakes = true } label: {
                            LabeledContent("Takes") {
                                HStack(spacing: 6) {
                                    Text("\(attempts)").monospacedDigit()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.inline)
        // A page pushed into the tab, like a book page: the tab bar goes,
        // and the glass panel's buttons take the foot.
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await reload() }
        .task { await reload() }
        // The board first; the script and the way in together at the foot
        // (2026-10-16, founder: the board sat under a summary and a
        // script row, and the start button was a bar of its own).
        .safeAreaInset(edge: .bottom) { actionBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        startAfterNaming = false
                        naming = true
                    } label: {
                        Label("Name on the board", systemImage: "person.text.rectangle")
                    }
                    if gate.account?.unlimited == true, !isPast {
                        Button(role: .destructive) {
                            confirmRetire = true
                        } label: {
                            Label("Retire challenge", systemImage: "archivebox")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $naming, onDismiss: {
            if startAfterNaming, SpeechChallenges.displayName != nil {
                startAfterNaming = false
                practicing = true
            }
        }) {
            SpeechChallengeNameSheet(suggested: appState.persona?.displayName ?? "")
        }
        .sheet(isPresented: $showingScript) {
            SpeechScriptSheet(script: script)
        }
        .sheet(isPresented: $showingTakes) {
            SpeechTakesSheet(scriptId: script.id)
        }
        .fullScreenCover(isPresented: $practicing, onDismiss: {
            Task { await reload() }
        }) {
            SpeechPrompterView(script: script, native: appState.nativeLanguage,
                               level: appState.proficiency)
                .environmentObject(appState)
        }
        .confirmationDialog("Retire this challenge? It leaves everyone's Speech tab.",
                            isPresented: $confirmRetire, titleVisibility: .visible) {
            Button("Retire", role: .destructive) {
                Task {
                    try? await challenges.retire(script.id)
                    dismiss()
                }
            }
        }
    }

    /// One container at the foot: what the script is, then three buttons —
    /// your takes (the prompter's own clock-and-count, no label), Read the
    /// script, and the start button (2026-10-17, founder). Glass, so the
    /// board shows through as it scrolls under.
    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if !script.summary.isEmpty {
                    Text(script.summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                    Text("·")
                    Text(script.genre.title)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    showingTakes = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.headline)
                        .frame(width: 28)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .overlay(alignment: .topTrailing) {
                    let count = store.takes(for: script.id).count
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
                .accessibilityLabel(Text("Takes"))
                Button {
                    showingScript = true
                } label: {
                    Label("Script", systemImage: "doc.text")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                if !isPast {
                    Button {
                        start()
                    } label: {
                        Text(standing?.myBest == nil ? LocalizedStringKey("speech.challenge.take") : LocalizedStringKey("speech.challenge.again"))
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .modifier(GlassPanel(cornerRadius: 28))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Nothing goes on a public board until the learner has seen the name.
    private func start() {
        if SpeechChallenges.displayName == nil {
            startAfterNaming = true
            naming = true
        } else {
            practicing = true
        }
    }

    private func reload() async {
        async let list: Void = challenges.refresh(language: script.language)
        let rows = await challenges.board(script.id)
        _ = await list
        if let rows { board = rows; loadFailed = false } else if board == nil { loadFailed = true }
    }

    private enum Item {
        case row(SpeechChallenges.BoardRow)
        case gap(Int)
        var id: String {
            switch self {
            case .row(let r): return r.id
            case .gap(let n): return "gap-\(n)"
            }
        }
    }

    /// The top of the board, then "…" before the learner's own row when it
    /// sits further down.
    private func rowsWithGap(_ rows: [SpeechChallenges.BoardRow]) -> [Item] {
        var out: [Item] = []
        var previous: Int?
        for row in rows {
            if let previous, row.rank > previous + 1, row.is_me { out.append(.gap(row.rank)) }
            out.append(.row(row))
            previous = row.rank
        }
        return out
    }

    @ViewBuilder
    private func boardRow(_ row: SpeechChallenges.BoardRow) -> some View {
        if row.rank <= 3 {
            SpeechPodiumRow(row: row)
        } else {
            HStack(spacing: 12) {
                Text("\(row.rank)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
                SpeechChallengeFace(face: row.face, size: 28)
                Text(row.display_name)
                    .fontWeight(row.is_me ? .semibold : .regular)
                    .lineLimit(1)
                if row.is_me {
                    Text("You")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text("\(row.score)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SpeechScoreColor.color(row.score))
            }
        }
    }
}

/// Liquid Glass on iOS 26, a material below it: either way the content
/// behind shows through.
private struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 2)
        }
    }
}

/// A top-three line, drawn large: the face with its place on a medal-coloured
/// tag at the top-right, the name, and the score.
struct SpeechPodiumRow: View {
    let row: SpeechChallenges.BoardRow

    private var medal: Color {
        switch row.rank {
        case 1: return .yellow
        case 2: return .gray
        default: return .brown
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            SpeechChallengeFace(face: row.face, size: row.rank == 1 ? 56 : 48)
                .overlay(alignment: .topTrailing) {
                    Text("#\(row.rank)")
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(row.rank == 1 ? Color.black : Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(medal, in: Capsule())
                        .overlay(Capsule().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        .offset(x: 8, y: -4)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.display_name)
                    .font(row.rank == 1 ? .title3.weight(.semibold) : .headline)
                    .lineLimit(1)
                if row.is_me {
                    Text("You")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            Spacer()
            Text("\(row.score)")
                .font((row.rank == 1 ? Font.title : .title2).monospacedDigit().weight(.bold))
                .foregroundStyle(SpeechScoreColor.color(row.score))
        }
        .padding(.vertical, row.rank == 1 ? 8 : 4)
    }
}

// MARK: - Every challenge, live and past

struct SpeechChallengeListView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenges = SpeechChallenges.shared

    var body: some View {
        List {
            if !challenges.live.isEmpty {
                Section("Live") {
                    ForEach(challenges.live) { row($0) }
                }
            }
            if !challenges.past.isEmpty {
                Section {
                    ForEach(challenges.past) { row($0) }
                } header: {
                    Text("Past challenges")
                } footer: {
                    Text("Ended challenges keep their final standings.")
                }
            }
        }
        .navigationTitle("All challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await challenges.refresh(language: appState.targetLanguage) }
    }

    private func row(_ script: SpeechScript) -> some View {
        SpeechCardLink {
            SpeechChallengeView(script: script).environmentObject(appState)
        } label: {
            SpeechChallengeRow(script: script, standing: challenges.standings[script.id])
        }
    }
}

// MARK: - The name on the boards

struct SpeechChallengeNameSheet: View {
    let suggested: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var avatar = AvatarStore.shared
    @State private var name = ""
    @State private var showsPhoto = SpeechChallenges.showsPhoto
    @FocusState private var focused: Bool

    private var clean: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SpeechChallengeFace(
                            face: .init(display_name: clean.isEmpty ? "?" : clean, avatar: nil),
                            size: 44, localImage: showsPhoto ? avatar.image : nil)
                        TextField("Name", text: $name)
                        .focused($focused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: name) { _, value in
                            if value.count > SpeechChallenges.maxNameLength {
                                name = String(value.prefix(SpeechChallenges.maxNameLength))
                            }
                        }
                    }
                    if avatar.image != nil {
                        Toggle("Show my photo", isOn: $showsPhoto)
                    }
                } footer: {
                    Text("Shown beside your score on every challenge board.")
                }
            }
            .navigationTitle("Your name on the board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        SpeechChallenges.displayName = clean
                        SpeechChallenges.showsPhoto = showsPhoto
                        Task { await SpeechChallenges.shared.saveProfile() }
                        dismiss()
                    }
                    .disabled(clean.isEmpty)
                }
            }
            .onAppear {
                name = SpeechChallenges.displayName ?? suggested
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - On a take's result page

struct SpeechChallengeEntrySection: View {
    let entry: SpeechChallenges.Entry?
    let standing: SpeechChallenges.Standing?

    var body: some View {
        Section {
            switch entry {
            case .submitting:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Putting it on the board…").foregroundStyle(.secondary)
                }
            case .entered(let rank, let previousRank, let entrants, let best, let improved):
                VStack(alignment: .leading, spacing: 4) {
                    if improved, let previousRank, rank < previousRank {
                        Label("Up to #\(rank) of \(entrants)", systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.green)
                            .font(.body.weight(.semibold))
                    } else if improved, previousRank == nil {
                        Label("On the board at #\(rank) of \(entrants)", systemImage: "trophy.fill")
                            .foregroundStyle(.tint)
                            .font(.body.weight(.semibold))
                    } else if improved {
                        Label("New best · #\(rank) of \(entrants)", systemImage: "star.fill")
                            .foregroundStyle(.tint)
                            .font(.body.weight(.semibold))
                    } else {
                        Label("#\(rank) of \(entrants)", systemImage: "trophy")
                            .font(.body.weight(.semibold))
                        Text("Your best stays at \(best).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            case .cameraOff:
                Label("The camera was off, so this take isn't on the board.", systemImage: "video.slash")
                    .foregroundStyle(.secondary)
            case .failed:
                Label("This take couldn't reach the board.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case nil:
                if let rank = standing?.myRank, let best = standing?.myBest {
                    Label("Your best on the board: \(best) · #\(rank)", systemImage: "trophy")
                }
            }
        } header: {
            Text("Challenge")
        }
    }
}

// MARK: - The moment a take moves up the board

/// What a take did on the board, for the sheet that follows a better take.
/// Never raised for a take that didn't beat the learner's best.
struct SpeechChallengeMoment: Identifiable, Equatable {
    enum Kind: Equatable {
        /// First time on this board, outside the top three.
        case debut
        /// Moved up, still outside the top three.
        case up
        /// In the top three now (rank 1–3).
        case podium
    }

    let id = UUID()
    let kind: Kind

    /// The moment a submit earned, or nil when it's not one: a sheet only for
    /// a first entry, a climb, or a better take inside the top three. A new
    /// best at the same place is the result page's one line.
    static func make(rank: Int, previousRank: Int?, entrants: Int, best: Int, improved: Bool,
                     board: [SpeechChallenges.BoardRow]) -> SpeechChallengeMoment? {
        guard improved else { return nil }
        let kind: Kind
        if rank <= 3 { kind = .podium }
        else if previousRank == nil { kind = .debut }
        else if let previousRank, rank < previousRank { kind = .up }
        else { return nil }
        var neighbors: [SpeechChallenges.BoardRow] = []
        if let i = board.firstIndex(where: \.is_me) {
            if i > 0 { neighbors.append(board[i - 1]) }
            neighbors.append(board[i])
            if i + 1 < board.count { neighbors.append(board[i + 1]) }
        }
        return SpeechChallengeMoment(kind: kind, rank: rank, previousRank: previousRank,
                                     entrants: entrants, score: best, neighbors: neighbors)
    }
    let rank: Int
    let previousRank: Int?
    let entrants: Int
    let score: Int
    /// The rows around the learner: the one above (if any), theirs, the one
    /// below (if any).
    let neighbors: [SpeechChallenges.BoardRow]

    var above: SpeechChallenges.BoardRow? {
        neighbors.last { !$0.is_me && $0.rank < rank }
    }
    var below: SpeechChallenges.BoardRow? {
        neighbors.first { !$0.is_me && $0.rank > rank }
    }
}

struct SpeechChallengeMomentSheet: View {
    let moment: SpeechChallengeMoment
    var onSeeBoard: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: appeared)
                .padding(.top, 28)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 0) {
                ForEach(Array(moment.neighbors.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider().padding(.leading, 56) }
                    SpeechBoardRowView(row: row)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    dismiss()
                    onSeeBoard()
                } label: {
                    Text("See the leaderboard")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Button("Done") { dismiss() }
                    .font(.body)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.medium, .large])
        .onAppear {
            appeared = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var symbol: String {
        switch moment.kind {
        case .podium: return "medal.fill"
        case .up: return "arrow.up.circle.fill"
        case .debut: return "trophy.fill"
        }
    }

    private var tint: Color {
        switch moment.kind {
        case .podium:
            switch moment.rank {
            case 1: return .yellow
            case 2: return .gray
            default: return .brown
            }
        case .up: return .green
        case .debut: return .accentColor
        }
    }

    private var title: String {
        switch moment.kind {
        case .podium:
            return moment.rank == 1 ? explain("You're #1") : explain("You're #\(moment.rank)")
        case .up:
            return explain("#\(moment.previousRank ?? moment.rank) → #\(moment.rank)")
        case .debut:
            return explain("You're on the board")
        }
    }

    private var subtitle: String {
        if moment.rank == 1 {
            if let below = moment.below {
                return explain("Ahead of #2 by \(moment.score - below.score)")
            }
            return explain("The top score of \(moment.entrants) people")
        }
        if moment.kind == .debut {
            return explain("#\(moment.rank) of \(moment.entrants)")
        }
        if let above = moment.above {
            return explain("\(max(1, above.score - moment.score)) to go for #\(above.rank)")
        }
        return explain("#\(moment.rank) of \(moment.entrants)")
    }
}

/// One line of a board: rank, name, "You", score. Shared by the board page
/// and the moment sheet.
struct SpeechBoardRowView: View {
    let row: SpeechChallenges.BoardRow

    var body: some View {
        HStack(spacing: 12) {
            Text("\(row.rank)")
                .font(.body.monospacedDigit().weight(row.rank <= 3 ? .bold : .regular))
                .foregroundStyle(row.rank <= 3 ? Color.accentColor : .secondary)
                .frame(minWidth: 28, alignment: .leading)
            Text(row.display_name)
                .fontWeight(row.is_me ? .semibold : .regular)
                .lineLimit(1)
            if row.is_me {
                Text("You")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Spacer()
            Text("\(row.score)")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(SpeechScoreColor.color(row.score))
        }
    }
}
