import SwiftUI

// MARK: - Card on the Speech tab

/// One challenge as a card, the review page's book card anatomy
/// (2026-10-16, founder): the trophy in a tinted disc top-left, the
/// learner's standing top-right, the title large, one quiet line under it,
/// and the board's top three at the foot.
struct SpeechChallengeRow: View {
    let script: SpeechScript
    let standing: SpeechChallenges.Standing?
    /// This phone's best take, for a challenge read but not on the board.
    var localBest: Int? = nil

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
                            .foregroundStyle(Color.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.themeAccent))
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
                } else if let localBest {
                    Text("\(localBest)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(SpeechScoreColor.color(localBest))
                }
            }
            // The title hangs under the disc; the meta line belongs to the
            // FOOT, just above the faces, so it sits at the same height on
            // every card whatever the title's length. The slack goes between.
            // What kind of challenge it is, so a title like "Wake up
            // glowing" reads as a show host's pitch (founder, 2026-10-30).
            if let category = SpeechChallengeCategory.label(standing?.category) {
                Text(category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .padding(.top, 14)
            }
            Text(script.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SpeechChallengeCategory.label(standing?.category) == nil ? 14 : 2)
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
        // Tries, not people: how often it has been read is the livelier
        // number. A server that doesn't send it yet still has the people.
        // "0 tries" says the same thing as the foot, only sadder.
        if let tries = standing?.attempts {
            guard tries > 0 else { return length }
            return [explain("\(tries) tries"), length].joined(separator: " · ")
        }
        let entrants = standing?.entrants ?? 0
        guard entrants > 0 else { return length }
        return [explain("\(entrants) taking part"), length].joined(separator: " · ")
    }
}

/// A challenge's category key, named in the learner's language. A key this
/// build doesn't know draws nothing rather than the raw key.
enum SpeechChallengeCategory {
    static func label(_ key: String?) -> String? {
        switch key {
        case "show_host": return explain(key: "speech.category.show_host", default: "Show host")
        case "famous_speech": return explain(key: "speech.category.famous_speech", default: "Famous speech")
        case "movie_scene": return explain(key: "speech.category.movie_scene", default: "Movie scene")
        case "film_review": return explain(key: "speech.category.film_review", default: "Film critic")
        case "acceptance": return explain(key: "speech.category.acceptance", default: "Acceptance speech")
        case "product_launch": return explain(key: "speech.category.product_launch", default: "Product launch")
        case "in_flight": return explain(key: "speech.category.in_flight", default: "In-flight announcement")
        case "podcast": return explain(key: "speech.category.podcast", default: "Podcast")
        case "short_talk": return explain(key: "speech.category.short_talk", default: "Short talk")
        case "docent": return explain(key: "speech.category.docent", default: "Museum guide")
        case "weather": return explain(key: "speech.category.weather", default: "Weather forecast")
        case "wedding": return explain(key: "speech.category.wedding", default: "Wedding speech")
        default: return nil
        }
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
    @State private var confirmWithdraw = false
    #if SPEECH_APP
    @State private var groupReload = 0
    #endif

    private var standing: SpeechChallenges.Standing? { challenges.standings[script.id] }
    /// Retired: the board is frozen and nobody can enter.
    private var isPast: Bool { standing?.retiredAt != nil }

    var body: some View {
        List {
            #if SPEECH_APP
            // The group being looked at, above everyone.
            SpeechGroupBoardSection(scriptId: script.id, reloadToken: groupReload)
            #endif
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This challenge has ended. These are the final standings.")
                        Text("You can keep practicing. Your place stays as it is.")
                    }
                } else {
                    Text("Camera-on takes go on the board, and your best one stands. The board shows your name and score — your video and voice stay on your phone.")
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
                    Button("Remove me from this board", role: .destructive) {
                        confirmWithdraw = true
                    }
                }
            }
        }
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.inline)
        // A page pushed into the tab, like a book page: the tab bar goes,
        // and the glass panel's buttons take the foot.
        .hidesTabBar()
        .refreshable { await reload() }
        .task { await reload() }
        // The board first; the script and the way in together at the foot
        // (2026-10-16, founder: the board sat under a summary and a
        // script row, and the start button was a bar of its own).
        .safeAreaInset(edge: .bottom) { actionBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AppMenu {
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
        .fullScreenCover(isPresented: $showingTakes) {
            SpeechTakesPager(scriptId: script.id)
        }
        .fullScreenCover(isPresented: $practicing, onDismiss: {
            Task {
                await reload()
                #if SPEECH_APP
                groupReload += 1
                #endif
            }
        }) {
            SpeechPrompterView(script: script, native: appState.nativeLanguage,
                               level: appState.proficiency)
                .environmentObject(appState)
        }
        .confirmationDialog("Remove your score from this board?",
                            isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Remove me from this board", role: .destructive) {
                Task {
                    try? await challenges.withdraw(script.id)
                    await reload()
                }
            }
        } message: {
            if isPast {
                Text("Your score and place come off the board for good. Your takes stay on your phone.")
            } else {
                Text("Your score and place come off the board. Your next camera take goes back on it.")
            }
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
                // What the challenge is and what to keep in mind ("you're
                // the show host…"), in the app's language (founder,
                // 2026-11-04). The script's own summary stands in without one.
                if let intro = SpeechChallenges.intro(standing, native: LanguageCatalog.currentNative) {
                    Text(intro)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                } else if !script.summary.isEmpty {
                    Text(script.summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                // The original, to watch before reading it (founder, 2026-11-04).
                if let link = standing?.link {
                    Link(destination: link) {
                        Label("Watch the original", systemImage: "play.rectangle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.bottom, 4)
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
                            .foregroundStyle(Color.onAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.themeAccent, in: Capsule())
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
                Button {
                    start()
                } label: {
                    Text(isPast ? LocalizedStringKey("speech.challenge.practice")
                                : standing?.myBest == nil ? LocalizedStringKey("speech.challenge.take")
                                                          : LocalizedStringKey("speech.challenge.again"))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .accentProminent()
            }
        }
        .padding(16)
        .modifier(GlassPanel(cornerRadius: 28))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Nothing goes on a public board until the learner has seen the name.
    private func start() {
        // Practice on an ended challenge puts no name anywhere.
        if !isPast, SpeechChallenges.displayName == nil {
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
                if let theme = row.core_theme { CoreCubeBadge(theme: theme) }
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
                HStack(spacing: 4) {
                    Text(row.display_name)
                        .font(row.rank == 1 ? .title3.weight(.semibold) : .headline)
                        .lineLimit(1)
                    if let theme = row.core_theme { CoreCubeBadge(theme: theme, size: 18) }
                }
                HStack(spacing: 6) {
                    if row.is_me {
                        Text("You")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    if let count = row.challenges {
                        Text("\(count) challenges")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text("\(row.score)")
                .font((row.rank == 1 ? Font.title : .title2).monospacedDigit().weight(.bold))
                .foregroundStyle(SpeechScoreColor.board(row))
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
                Section {
                    ForEach(challenges.live) { row($0) }
                } header: {
                    if !SpeechAppFlags.isSpeechApp, let season = challenges.openSeason, season >= 2 {
                        Text("Season \(season) · Live")
                    } else {
                        Text("Live")
                    }
                }
            }
            // The speech app has no seasons on screen: one list of what ended.
            if SpeechAppFlags.isSpeechApp, !challenges.past.isEmpty {
                Section {
                    ForEach(challenges.past) { script in
                        if challenges.season(of: script.id) != nil { pastRow(script) } else { row(script) }
                    }
                } header: {
                    Text("Past challenges")
                } footer: {
                    Text("Ended challenges keep their final standings.")
                }
            }
            ForEach(SpeechAppFlags.isSpeechApp ? [] : challenges.pastSeasons, id: \.self) { season in
                Section {
                    ForEach(challenges.past.filter { challenges.season(of: $0.id) == season }) { pastRow($0) }
                } header: {
                    Text("Season \(season) · Ended")
                } footer: {
                    Text("Ended challenges keep their final standings.")
                }
            }
            // Retired before seasons, or from a server without them.
            let unseasoned = SpeechAppFlags.isSpeechApp ? []
                : challenges.past.filter { challenges.season(of: $0.id) == nil }
            if !unseasoned.isEmpty {
                Section {
                    ForEach(unseasoned) { row($0) }
                } header: {
                    Text("Past challenges")
                } footer: {
                    Text("Ended challenges keep their final standings.")
                }
            }
        }
        .navigationTitle("All challenges")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .refreshable { await challenges.refresh(language: appState.targetLanguage) }
    }

    private func row(_ script: SpeechScript) -> some View {
        SpeechCardLink {
            SpeechArenaDetail(script: script).environmentObject(appState)
        } label: {
            SpeechChallengeRow(script: script, standing: challenges.standings[script.id])
        }
    }

    /// An ended challenge is a record: the title and where the reader finished.
    private func pastRow(_ script: SpeechScript) -> some View {
        let standing = challenges.standings[script.id]
        return NavigationLink {
            SpeechArenaDetail(script: script).environmentObject(appState)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.title).lineLimit(1)
                    Text("\(standing?.entrants ?? 0) joined")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let rank = standing?.myRank, let best = standing?.myBest {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: "#\(rank)")
                            .font(.headline.monospacedDigit())
                        Text(verbatim: "\(best)")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(SpeechScoreColor.color(best))
                    }
                }
            }
        }
    }
}

// MARK: - A season that ended

/// "Season N records" (2026-11-15, founder: the link opened All challenges,
/// which held only Season 2's cards). English Season 1's challenges went live
/// again in Season 2 on 2026-11-13, so nothing of that season is "past" any
/// more: its record is the frozen final standings and the learner's own
/// frozen score on each challenge (`my_speech_season_records`).
struct SpeechSeasonRecordsView: View {
    let season: Int
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenges = SpeechChallenges.shared
    @State private var rows: [SpeechChallenges.BoardRow]?

    /// My frozen scores of this season, the best place first.
    private var mine: [SpeechChallenges.SeasonRecord] {
        challenges.seasonRecords.values
            .filter { $0.season == season && challenges.script(id: $0.challenge_id) != nil }
            .sorted { ($0.rank, -$0.score) < ($1.rank, -$1.score) }
    }

    /// Challenges retired inside this season (none for English Season 1).
    private var retired: [SpeechScript] {
        challenges.past.filter { challenges.season(of: $0.id) == season }
    }

    var body: some View {
        List {
            Section {
                if let rows {
                    ForEach(rows) { row in
                        if row.rank <= 3 { SpeechPodiumRow(row: row) } else { SpeechOverallRow(row: row) }
                    }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } header: {
                Text("Final standings")
            } footer: {
                Text("This season has ended. These are the final standings.")
            }
            if !mine.isEmpty {
                Section("Challenges") {
                    ForEach(mine, id: \.challenge_id) { record in
                        HStack(spacing: 10) {
                            Text(challenges.script(id: record.challenge_id)?.title ?? "")
                                .lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("#\(record.rank) of \(record.entrants)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(verbatim: "\(record.score)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(SpeechScoreColor.color(record.score))
                            }
                        }
                    }
                }
            }
            if !retired.isEmpty {
                Section {
                    ForEach(retired) { script in
                        NavigationLink {
                            SpeechArenaDetail(script: script).environmentObject(appState)
                        } label: {
                            Text(script.title).lineLimit(1)
                        }
                    }
                } footer: {
                    Text("Ended challenges keep their final standings.")
                }
            }
        }
        .navigationTitle("Season \(season) records")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if let fresh = await challenges.overallBoard(language: appState.targetLanguage,
                                                     season: season, limit: 50) {
            rows = fresh
        } else if rows == nil {
            rows = []
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
                    BarCloseButton(title: "Cancel") { dismiss() }
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
            case .newScoring:
                Label("Scored the Season 2 way, so it stays off this board.", systemImage: "flask")
                    .foregroundStyle(.secondary)
            case .practice:
                Label("A practice take. It stays off the board.", systemImage: "mic")
                    .foregroundStyle(.secondary)
            case .unfinished:
                Label("Read the script to the end, and the take goes on the board.", systemImage: "text.alignleft")
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
                .accentProminent()
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
        case .debut: return Color.themeAccent
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
                .foregroundStyle(row.rank <= 3 ? Color.themeAccent : .secondary)
                .frame(minWidth: 28, alignment: .leading)
            Text(row.display_name)
                .fontWeight(row.is_me ? .semibold : .regular)
                .lineLimit(1)
            if let theme = row.core_theme { CoreCubeBadge(theme: theme) }
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

// MARK: - Every challenge on one board

/// The overall ranking on the Speech tab (2026-11-05, founder): a banner with
/// the top three drawn large, second · first · third like a podium, and a tap
/// opens the whole board. Each learner's best score per challenge, added up.
struct SpeechOverallBanner: View {
    let rows: [SpeechChallenges.BoardRow]

    private var top: [SpeechChallenges.BoardRow] { Array(rows.prefix(3)) }
    private var me: SpeechChallenges.BoardRow? { rows.first { $0.is_me } }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Overall ranking", systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach([1, 0, 2], id: \.self) { index in
                    if index < top.count {
                        place(top[index])
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            if let me, me.rank > 3 {
                HStack(spacing: 6) {
                    Text("You")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(verbatim: "#\(me.rank)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("·").foregroundStyle(.secondary)
                    Text(verbatim: "\(me.score)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
    }

    private func place(_ row: SpeechChallenges.BoardRow) -> some View {
        let first = row.rank == 1
        return VStack(spacing: 6) {
            SpeechChallengeFace(face: row.face, size: first ? 76 : 60)
                .overlay(alignment: .topTrailing) {
                    Text(verbatim: "#\(row.rank)")
                        .font(.caption.weight(.heavy).monospacedDigit())
                        .foregroundStyle(row.rank == 1 ? Color.black : Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SpeechOverallBanner.medal(row.rank), in: Capsule())
                        .overlay(Capsule().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        .offset(x: 6, y: -4)
                }
            HStack(spacing: 3) {
                Text(row.display_name)
                    .font(first ? .headline : .subheadline.weight(.semibold))
                    .lineLimit(1)
                if let theme = row.core_theme { CoreCubeBadge(theme: theme) }
            }
            Text(verbatim: "\(row.score)")
                .font((first ? Font.title2 : .title3).monospacedDigit().weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    static func medal(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        default: return .brown
        }
    }
}

/// The whole overall board: the top fifty and the learner's own row.
struct SpeechOverallBoardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenges = SpeechChallenges.shared
    @State private var rows: [SpeechChallenges.BoardRow]?
    /// nil until picked: the season the banner showed.
    @State private var pickedSeason: Int?
    /// A page of its own in the speech app's bottom tabs: the bar stays.
    var inTab = false

    private var season: Int? { pickedSeason ?? challenges.overallSeason }
    private var isFinal: Bool { season.map(challenges.seasonEnded) ?? false }

    var body: some View {
        List {
            if !SpeechAppFlags.isSpeechApp, challenges.boardSeasons.count > 1 {
                Section {
                    Picker("Season", selection: Binding(get: { season ?? 0 }, set: { pickedSeason = $0 })) {
                        ForEach(challenges.boardSeasons, id: \.self) { Text("Season \($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            #if SPEECH_APP
            // The top three as standing mics (2026-11-13, founder: moved here
            // from the challenge page).
            if let rows = shownRows, !rows.isEmpty {
                Section {
                    ArenaPodium(rows: rows.filter { $0.rank <= 3 })
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            #endif
            Section {
                if let rows = shownRows {
                    if rows.isEmpty {
                        Text("Nobody's on this board yet. Be the first.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items(rows), id: \.id) { item in
                        switch item {
                        case .row(let row):
                            #if SPEECH_APP
                            if row.rank > 3 { SpeechOverallRow(row: row) }
                            #else
                            if row.rank <= 3 { SpeechPodiumRow(row: row) } else { SpeechOverallRow(row: row) }
                            #endif
                        case .gap:
                            Text("…").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } header: {
                if isFinal { Text("Final standings") }
            } footer: {
                if isFinal, !SpeechAppFlags.isSpeechApp {
                    Text("This season has ended. These are the final standings.")
                } else {
                    Text("Your best score on each challenge, added up. Every challenge you take moves you up.")
                }
            }
        }
        .navigationTitle("Overall ranking")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar(!inTab)
        .refreshable { await load() }
        .task(id: season) { await load() }
    }

    private var shownRows: [SpeechChallenges.BoardRow]? {
        rows ?? (pickedSeason == nil ? challenges.overall : nil)
    }

    private func load() async {
        // Opened before the challenge list has loaded (the speech app's
        // Ranking tab can be the first page): without the seasons the board
        // would fall back to Season 1's.
        if season == nil, challenges.seasons.isEmpty {
            await challenges.refresh(language: appState.targetLanguage)
            if season != nil { return }  // the change of season reloads
        }
        if pickedSeason != nil { rows = nil }
        if let fresh = await challenges.overallBoard(language: appState.targetLanguage, season: season, limit: 50) {
            rows = fresh
        }
    }

    private enum Item {
        case row(SpeechChallenges.BoardRow)
        case gap
        var id: String {
            switch self {
            case .row(let r): return r.id
            case .gap: return "gap"
            }
        }
    }

    /// "…" before the learner's own row when it sits below the top fifty.
    private func items(_ rows: [SpeechChallenges.BoardRow]) -> [Item] {
        var out: [Item] = []
        var previous: Int?
        for row in rows {
            if let previous, row.rank > previous + 1, row.is_me { out.append(.gap) }
            out.append(.row(row))
            previous = row.rank
        }
        return out
    }
}

/// A line of the overall board from 4th down: rank, face, name, how many
/// challenges, the total. The total is a sum, not a 0–100 score, so it is
/// never coloured by the score scale.
struct SpeechOverallRow: View {
    let row: SpeechChallenges.BoardRow

    var body: some View {
        HStack(spacing: 12) {
            Text("\(row.rank)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
            SpeechChallengeFace(face: row.face, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.display_name)
                        .fontWeight(row.is_me ? .semibold : .regular)
                        .lineLimit(1)
                    if let theme = row.core_theme { CoreCubeBadge(theme: theme) }
                    if row.is_me {
                        Text("You")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                if let count = row.challenges {
                    Text("\(count) challenges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(row.score)")
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}
