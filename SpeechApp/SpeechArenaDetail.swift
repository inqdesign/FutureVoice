import SwiftUI

// A challenge's page in the speech app (2026-11-12, founder: "the card scales
// up and becomes the hero, the rest slides and fades in"). The card a learner
// tapped grows into the top of this page through the zoom transition; what
// it holds (what to keep in mind, my best, the boards) comes in under it.

extension View {
    /// The card a tap grows out of (iOS 18; a plain push before).
    /// A card dims and zooms as ONE sheet. Without the group, a press dims
    /// the picture and the card behind it separately, and the picture's cream
    /// over the half-dimmed card cream shows up as a lighter square.
    @ViewBuilder func zoomSource(_ id: String, in ns: Namespace.ID?, radius: CGFloat) -> some View {
        if #available(iOS 18.0, *), let ns {
            compositingGroup().matchedTransitionSource(id: id, in: ns) {
                $0.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        } else {
            compositingGroup()
        }
    }

    /// The page a card grows into.
    @ViewBuilder func zoomDestination(_ id: String, in ns: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let ns {
            navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }

    /// Comes in after the hero: a short slide up and a fade, one step later
    /// per section.
    /// No darkening under the bars. iOS 26 softens content that scrolls
    /// under a bar with a dark layer in the dark look; over the cream cards
    /// and the picture that layer reads as a stain on the image, and it comes
    /// and goes as the page zooms open and is dragged shut.
    @ViewBuilder func noBarShade(_ edges: Edge.Set = .all) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: edges)
        } else {
            self
        }
    }

    /// Under the tab bar the shade has to stay: the bar's labels are white
    /// (the app is dark), and over a cream card with nothing dark behind the
    /// glass they vanish. A hard edge keeps it a short band behind the bar
    /// instead of a long dim creeping up the card.
    @ViewBuilder func tabBarBand() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            self
        }
    }

    /// A round button that belongs to the page: solid, no glass, so it reads
    /// on the cream picture and on the black below it alike.
    func pageButtonFace() -> some View {
        foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.white.opacity(0.92)))
            .contentShape(Circle())
    }

    func arrives(_ shown: Bool, step: Int) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 26)
            .animation(.spring(response: 0.55, dampingFraction: 0.9).delay(0.12 + Double(step) * 0.07), value: shown)
    }
}

/// The face every challenge card shares: its figure, its kind and its title,
/// on the card ground. The grid, the ticket and the page's hero all draw it,
/// so the card the learner tapped is the card that grows.
struct ChallengeCardFace: View {
    let script: SpeechScript
    let category: String?
    var figureHeight: CGFloat? = nil
    var titleSize: CGFloat = 17
    var titleLines: Int = 2

    var body: some View {
        VStack(spacing: titleSize > 24 ? 12 : 8) {
            if let art = ChallengeArt.image(for: script.id) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: figureHeight ?? .infinity)
                    .frame(height: figureHeight)
            } else {
                Spacer(minLength: 0)
            }
            if titleSize > 24, let label = SpeechChallengeCategory.label(category) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(ChallengeArt.inkText.opacity(0.55))
            }
            Text(script.title)
                .font(Arena.display(titleSize))
                .foregroundStyle(ChallengeArt.inkText)
                .multilineTextAlignment(.center)
                // Every card keeps room for the longest title, so a short
                // one never hands its line to the picture.
                .lineLimit(titleLines, reservesSpace: true)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }
}

struct SpeechArenaDetail: View {
    let script: SpeechScript
    var zoomID: String? = nil
    var zoom: Namespace.ID? = nil

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenges = SpeechChallenges.shared
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var groups = SpeechGroups.shared
    @ObservedObject private var gate = BillingGate.shared
    @Environment(\.dismiss) private var dismiss

    @State private var board: [SpeechChallenges.BoardRow]?
    @State private var groupBoard: [SpeechGroups.BoardRow]?
    @State private var shown = false
    @State private var practicing = false
    @State private var naming = false
    @State private var startAfterNaming = false
    @State private var showingScript = false
    @State private var showingTakes = false
    @State private var confirmWithdraw = false
    @State private var confirmRetire = false
    /// The fluent reading's opening, fading in as the page opens (2026-11-13,
    /// founder: an intro to how it should sound).
    @StateObject private var intro = SpeechListenModel()

    private var standing: SpeechChallenges.Standing? { challenges.standings[script.id] }
    private var isPast: Bool { standing?.retiredAt != nil }
    private var best: Int? { [standing?.myBest, store.best(for: script.id)].compactMap { $0 }.max() }
    private var takes: Int { store.takes(for: script.id).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    about.arrives(shown, step: 0)
                    VStack(alignment: .leading, spacing: 8) {
                        mine
                        seasonRecordLine
                    }
                    .arrives(shown, step: 1)
                    if let group = groups.selected {
                        groupSection(group).arrives(shown, step: 2)
                    }
                    everyone.arrives(shown, step: 3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
        }
        // The picture runs under the status bar to the screen's edges.
        .ignoresSafeArea(edges: .top)
        .noBarShade(.top)
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // Dark clock and battery over the cream picture.
        .toolbarColorScheme(.light, for: .navigationBar)
        // The page draws its own back and ⋯ (`pageButtons`): the system's
        // glass buttons are drawn apart from the page, and while it zooms
        // open or is dragged shut they showed as grey blocks on the picture.
        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .top) { pageButtons }
        // A challenge is a page of its own: the tabs step aside and the
        // buttons below are the way on (2026-11-13, founder).
        .toolbar(MacLayout.tabBarOnPhoneOnly, for: .tabBar)
        .safeAreaInset(edge: .bottom) { actions.arrives(shown, step: 4) }
        .zoomDestination(zoomID ?? "", in: zoomID == nil ? nil : zoom)
        // The boards load once the card has grown, not during it.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            await reload()
        }
        .refreshable { await reload() }
        // After the card has grown: a sound under a zoom that is still
        // opening reads as the tap making a noise.
        .task {
            guard SpeechListenService.available(for: script) else { return }
            try? await Task.sleep(for: .milliseconds(600))
            await intro.load(script)
            if !practicing, !showingScript, !showingTakes { intro.playIntro() }
        }
        .onAppear { shown = true }
        .onDisappear { intro.fadeOut() }
        .onChange(of: practicing) { _, on in if on { intro.fadeOut() } }
        .onChange(of: showingScript) { _, on in if on { intro.fadeOut() } }
        .onChange(of: showingTakes) { _, on in if on { intro.fadeOut() } }
        .sheet(isPresented: $naming, onDismiss: {
            if startAfterNaming, SpeechChallenges.displayName != nil {
                startAfterNaming = false
                practicing = true
            }
        }) {
            SpeechChallengeNameSheet(suggested: appState.persona?.displayName ?? "")
        }
        .sheet(isPresented: $showingScript) { SpeechScriptSheet(script: script) }
        .fullScreenCover(isPresented: $showingTakes) { SpeechTakesPager(scriptId: script.id) }
        .fullScreenCover(isPresented: $practicing, onDismiss: { Task { await reload() } }) {
            SpeechPrompterView(script: script, native: appState.nativeLanguage, level: appState.proficiency)
                .environmentObject(appState)
        }
        .confirmationDialog("Remove your score from this board?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Remove me from this board", role: .destructive) {
                Task {
                    try? await challenges.withdraw(script.id)
                    await reload()
                }
            }
        }
        .confirmationDialog("Retire this challenge? It leaves everyone's Speech tab.", isPresented: $confirmRetire, titleVisibility: .visible) {
            Button("Retire", role: .destructive) {
                Task {
                    try? await challenges.retire(script.id)
                    dismiss()
                }
            }
        }
    }

    // MARK: The hero: the card itself, grown

    /// The picture across the whole top of the screen, edge to edge and
    /// under the status bar, on the card's ground (2026-11-12, founder). A
    /// pull down stretches it. The title sits at its foot.
    private var hero: some View {
        VStack(spacing: 10) {
            heroPicture
            if let label = SpeechChallengeCategory.label(standing?.category) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Arena.dim)
            }
            Text(script.title)
                .font(Arena.display(32))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 20)
            if let best, let tier = MedalTier(score: best) {
                MedalBadge(tier: tier, label: "\(best)", size: 52).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The picture across the top, edge to edge and under the status bar. Its
    /// paper doesn't stop at a line: it bleeds into the page's black below
    /// (2026-11-12, founder). A pull down stretches it.
    private var heroPicture: some View {
        // The picture is drawn on the card's own cream, so paper and picture
        // are one sheet with no edge between them; black thickens over its
        // foot (eased, so it never meets the page as a band). Nothing here
        // reads the scroll position in the body: the stretch on a pull is a
        // `visualEffect`, worked out at draw time, so a zoom or a scroll never
        // rebuilds this block (it did every frame, and the open stuttered).
        ZStack(alignment: .top) {
            ChallengeArt.paper
            if let art = ChallengeArt.image(for: script.id) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
                    .padding(.top, 36)
            }
        }
        .frame(height: 480, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay {
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0.56),
                .init(color: .black.opacity(0.1), location: 0.64),
                .init(color: .black.opacity(0.3), location: 0.73),
                .init(color: .black.opacity(0.55), location: 0.82),
                .init(color: .black.opacity(0.8), location: 0.9),
                .init(color: .black.opacity(0.95), location: 0.96),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .visualEffect { content, proxy in
            let pull = max(0, proxy.frame(in: .scrollView).minY)
            return content.scaleEffect(1 + pull / 480, anchor: .bottom)
        }
    }

    // MARK: What it is

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let intro = SpeechChallenges.intro(standing, native: LanguageCatalog.currentNative) {
                Text(intro)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else if !script.summary.isEmpty {
                Text(script.summary).font(.body).foregroundStyle(.white.opacity(0.85))
            }
            HStack(spacing: 8) {
                Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                Text(verbatim: "·")
                Text(script.genre.title)
                if let tries = standing?.attempts, tries > 0 {
                    Text(verbatim: "·")
                    Text("\(tries) tries")
                }
            }
            .font(.footnote)
            .foregroundStyle(Arena.dim)
            if let link = standing?.link {
                Link(destination: link) {
                    Label("Watch the original", systemImage: "play.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: Me: my best, the next medal, my place

    private var mine: some View {
        HStack(spacing: 16) {
            MedalBadge(tier: best.flatMap(MedalTier.init(score:)), label: best.map(String.init) ?? "", size: 56)
            VStack(alignment: .leading, spacing: 3) {
                if let best {
                    Text("Best \(best)").font(Arena.display(22))
                } else {
                    Text("Not tried yet").font(Arena.display(22))
                }
                nextMedal.font(.subheadline).foregroundStyle(Arena.dim)
            }
            Spacer()
            if let rank = standing?.myRank {
                VStack(spacing: 2) {
                    Text(verbatim: "#\(rank)").font(Arena.display(22)).monospacedDigit()
                    Text("of \(standing?.entrants ?? rank)").font(.caption).foregroundStyle(Arena.dim)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Arena.card))
    }

    /// A challenge back from an earlier season keeps my score there, frozen.
    @ViewBuilder
    private var seasonRecordLine: some View {
        if let record = challenges.seasonRecords[script.id] {
            Text("Season \(record.season): \(record.score) · #\(record.rank) of \(record.entrants)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Arena.dim)
                .padding(.horizontal, 18)
        }
    }

    private var nextMedal: Text {
        guard let best else { return Text("Gold at 90") }
        if best >= 90 { return Text("Gold won") }
        if let next = MedalTier.allCases.first(where: { $0.bar > best }) {
            switch next {
            case .bronze: return Text("\(next.bar - best) to bronze")
            case .silver: return Text("\(next.bar - best) to silver")
            case .gold: return Text("\(next.bar - best) to gold")
            }
        }
        return Text("Gold at 90")
    }

    // MARK: Boards

    private func groupSection(_ group: SpeechGroups.Group) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.name).font(Arena.display(24))
            if let groupBoard {
                if groupBoard.isEmpty {
                    Text("Nobody in the group has read this yet.").font(.subheadline).foregroundStyle(Arena.dim)
                } else {
                    VStack(spacing: 0) {
                        ForEach(groupBoard) { row in boardLine(row.row) }
                    }
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Arena.card))
                }
            } else {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
            }
        }
    }

    private var everyone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard").font(Arena.display(24))
            if let board {
                if board.isEmpty {
                    Text("Nobody's on this board yet. Be the first.").font(.subheadline).foregroundStyle(Arena.dim)
                } else {
                    VStack(spacing: 0) {
                        ForEach(board) { row in boardLine(row) }
                    }
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Arena.card))
                }
            } else {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
            }
            Group {
                if isPast {
                    Text("This challenge has ended. These are the final standings.")
                } else {
                    Text("Camera-on takes go on the board, and your best one stands. The board shows your name and score — your video and voice stay on your phone.")
                }
            }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func boardLine(_ row: SpeechChallenges.BoardRow) -> some View {
        HStack(spacing: 12) {
            if let tier = MedalTier(rank: row.rank) {
                MedalBadge(tier: tier, label: "\(row.rank)", size: 34)
            } else {
                Text(verbatim: "\(row.rank)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Arena.dim)
                    .frame(width: 34)
            }
            SpeechChallengeFace(face: row.face, size: 34)
            Text(row.display_name)
                .font(.body.weight(row.is_me ? .semibold : .regular))
                .lineLimit(1)
            if row.is_me {
                Text("You").font(.caption.weight(.semibold)).foregroundStyle(Arena.gold)
            }
            Spacer()
            Text(verbatim: "\(row.score)")
                .font(Arena.display(20))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: The way in

    private var actions: some View {
        HStack(spacing: 10) {
            Button { showingTakes = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.headline)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Arena.raised))
                    .overlay(alignment: .topTrailing) {
                        if takes > 0 {
                            Text("\(takes)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(.white))
                        }
                    }
            }
            .accessibilityLabel(Text("Takes"))
            Button { showingScript = true } label: {
                Image(systemName: "doc.text")
                    .font(.headline)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Arena.raised))
                    .overlay { ListenRing(model: intro) }
            }
            .accessibilityLabel(Text("Script"))
            Button(action: start) {
                Text(isPast ? LocalizedStringKey("speech.challenge.practice")
                            : best == nil ? LocalizedStringKey("speech.challenge.take")
                                          : LocalizedStringKey("speech.challenge.again"))
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Color(white: 0.92)))
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

    private var pageButtons: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .pageButtonFace()
            }
            .accessibilityLabel(Text("Back"))
            Spacer()
            AppMenu {
                Button {
                    startAfterNaming = false
                    naming = true
                } label: {
                    Label("Name on the board", systemImage: "person.text.rectangle")
                }
                if standing?.myBest != nil {
                    Button(role: .destructive) { confirmWithdraw = true } label: {
                        Label("Remove me from this board", systemImage: "minus.circle")
                    }
                }
                if gate.account?.unlimited == true, !isPast {
                    Button(role: .destructive) { confirmRetire = true } label: {
                        Label("Retire challenge", systemImage: "archivebox")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .pageButtonFace()
            }
            .accessibilityLabel(Text("More"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /// Nothing goes on a public board until the learner has seen the name.
    private func start() {
        if !isPast, SpeechChallenges.displayName == nil {
            startAfterNaming = true
            naming = true
        } else {
            practicing = true
        }
    }

    private func reload() async {
        async let rows = challenges.board(script.id)
        if let group = groups.selected {
            groupBoard = await groups.board(group: group.id, script: script.id)
        }
        if let rows = await rows { board = rows }
    }
}

/// The ring round the Script button (2026-11-13, founder): the fluent
/// reading lives under that button, so while the page's intro plays the ring
/// moves with the voice, and a faint ring stays once it has stopped. Its own
/// view, so the player's 30-a-second level redraws the ring and nothing else.
private struct ListenRing: View {
    @ObservedObject var model: SpeechListenModel
    @ObservedObject var player: AudioPlayer

    init(model: SpeechListenModel) {
        self.model = model
        self.player = model.player
    }

    var body: some View {
        let playing = player.isPlaying
        let level = CGFloat(playing ? player.level : 0)
        Circle()
            .stroke(Arena.accent.opacity(playing ? 0.55 + 0.45 * level : 0.4),
                    lineWidth: playing ? 1.5 + 2.5 * level : 1.2)
            .padding(-(3 + 4 * level))
            .animation(.easeOut(duration: 0.12), value: level)
            .opacity(model.phase == .ready ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: model.phase == .ready)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
