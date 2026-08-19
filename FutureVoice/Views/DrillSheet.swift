import SwiftUI

/// Spaced-repetition drill queue. Walks through the cards that are currently
/// due — the learner hears the target phrase in their cloned voice, then
/// self-rates Got it / Try again to advance the Leitner box.
///
/// Shadow practice lives in its own sheet (`ShadowBrowserSheet`); the two are
/// surfaced from separate toolbar entries so the home dashboard can track each
/// independently.
/// Card-deck SRS practice. Tap to reveal, then DRAG the card into one of four
/// bins that rise under the deck — 10 min · Tomorrow · 3 days · Got it. The
/// three delays are the learner saying when they want to meet the phrase
/// again; "Got it" hands the card back to the Leitner ladder. Each bin the
/// card crosses ticks a selection haptic, so the target is feelable without
/// looking down, and the released card is swallowed by the bin it lands on.
/// No bottom button bar — important under a tab bar so the controls don't
/// visually merge with system chrome. A faint "next card" preview sits behind
/// the active card for the deck-of-cards feel.
struct DrillView: View {
    /// Optional filter. `.due` (default) = the Leitner-scheduled queue.
    /// `.session(id)` = every card whose source matches the given session,
    /// regardless of due date. Lets the user post-mortem a specific
    /// conversation by walking just its cards.
    /// `.ahead(n)` = the n soonest-due cards regardless of schedule — for
    /// "practice ahead" when nothing is due but the user wants reps anyway.
    /// `.scenario` = cards saved from Watch dialogues ("Save phrase") — they
    /// have no source session, so without this filter they'd be reachable
    /// only through the generic due queue.
    enum Source: Equatable {
        case due
        case session(UUID)
        case ahead(Int)
        case scenario
        /// Exactly one card — a per-item callback named this line, so the
        /// deck opens on it instead of wherever the due queue happens to
        /// start (`ItemReminder`).
        case card(UUID)
    }
    var source: Source = .due
    /// Fired the moment the last card is graded. Lets `PracticeSessionView`
    /// chain the deck into the shadow stage; nil (standalone use) keeps the
    /// classic "All caught up" empty state.
    var onDeckCompleted: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()

    @State private var queue: [DrillCard] = []
    /// Which card's user recording is playing right now — drives the play
    /// button's play→stop icon swap so a tap has visible feedback.
    @State private var playingTurnId: UUID?
    @State private var initialCount: Int = 0
    @State private var isLoadingAudio = false
    @State private var error: String?
    @State private var dragOffset: CGSize = .zero
    /// Bin tray state. The tray only exists during a drag — at rest the deck
    /// is just a card, so nothing competes with the phrase being recalled.
    @State private var isDragging = false
    @State private var activeTarget: DropTarget?
    /// Measured in the "drilldeck" coordinate space so the released card can
    /// fly to the exact bin it was dropped on.
    @State private var binFrames: [DrillBin: CGRect] = [:]
    @State private var deckFrame: CGRect = .zero
    /// Shrink + fade applied while the card is being swallowed by a bin.
    @State private var flyScale: CGFloat = 1
    @State private var flyOpacity: Double = 1
    @State private var showingEnrichmentFor: DrillCard?
    @State private var shadowingCard: DrillCard?
    /// Active-recall gate: when the top card has a sourcePhrase, the target
    /// stays hidden until the learner taps to check — they should produce
    /// the fluent version in their head (or out loud) FIRST. Grading swipes
    /// are disabled until revealed, so "Got it" always means actual recall.
    @State private var topCardRevealed = false
    /// Cards parked for later, bucketed by when they'll come back. The tray's
    /// bins double as FOLDERS with live counts at rest — a graded card visibly
    /// lands somewhere instead of vanishing, and any folder opens to a list.
    @State private var folderCards: [DrillBin: [DrillCard]] = [:]
    @State private var openFolder: DrillBin?
    /// Due cards beyond today's hand — still waiting, just not dealt into
    /// this deck.
    @State private var remainingDue = 0

    /// How far the card must travel before a release counts as a drop rather
    /// than a fumble. Below this the card springs home and nothing is graded.
    private static let commitThreshold: CGFloat = 64
    /// A due pile in the hundreds is a lost game before the first card. Deal
    /// a hand this size instead; the empty state offers the next hand. Also
    /// the Practice tab's Sentences challenge target, so a 150-card backlog
    /// reads as "clear today's deck", not "do 150".
    static let sessionCap = 20
    /// A single talk's post-talk review run — short enough to finish in one
    /// sitting right after the call.
    private static let quickRunCap = 8
    /// Dead zone before any bin lights up — without it the card starts life
    /// straddling two bins and the first millimetre of movement buzzes.
    private static let binDeadZone: CGFloat = 28
    /// A new bin has to be this much closer than the current one to steal the
    /// highlight, so a finger resting on a boundary doesn't rattle.
    private static let binHysteresis: CGFloat = 14
    /// Upward travel that means "not into any of these". Above the folders'
    /// dead zone so a sideways drag that drifts a little high still files.
    private static let cancelThreshold: CGFloat = 44

    var body: some View {
        Group {
            if !queue.isEmpty {
                cardDeck
            } else {
                emptyState
            }
        }
        .alert("Couldn't play audio", isPresented: errorBinding) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .sheet(item: $showingEnrichmentFor, onDismiss: refreshTopCard) { card in
            DrillEnrichmentSheet(card: card)
                .environmentObject(appState)
        }
        .sheet(item: $shadowingCard) { card in
            // Build a synthetic fluentSelf turn from the drill card so we
            // can reuse the existing ShadowDrillView surface. Deterministic
            // id (derived from card.id) keeps saved attempts linked to the
            // same card across sessions.
            ShadowDrillView(
                turn: Turn(
                    id: card.id,
                    role: .fluentSelf,
                    audioURL: nil,
                    transcript: card.targetPhrase,
                    durationMs: 0,
                    timestamp: card.createdAt,
                    suggestion: nil
                ),
                targetLanguage: appState.targetLanguage
            )
            .environmentObject(appState)
        }
        .sheet(item: $openFolder) { bin in
            folderSheet(bin)
        }
        .onAppear {
            loadQueue()
            refreshFolders()
            #if DEBUG
            if DebugCapture.previewDrillFolder {
                openFolder = .tomorrow
            }
            if DebugCapture.previewDrillTray {
                topCardRevealed = true
                isDragging = true
                activeTarget = .bin(.tomorrow)
                // Dragged DOWN and right — the case where the card's own
                // buttons would otherwise poke out under the tray.
                dragOffset = CGSize(width: 40, height: 150)
            }
            #endif
        }
        // Clear the play-button state the moment playback naturally ends.
        .onChange(of: player.isPlaying) { _, playing in
            if !playing { playingTurnId = nil }
        }
        .onDisappear {
            player.stop()
            // The queue just changed shape — every card graded here moved its
            // due date. Without this the pending notification keeps whatever
            // the last app launch computed, and a 10-minute snooze never
            // fires at all.
            Task { await DrillReminder.reschedule() }
        }
    }

    // MARK: - Geometry plumbing for the bin tray

    private struct DeckFrameKey: PreferenceKey {
        static var defaultValue: CGRect { .zero }
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            let next = nextValue()
            if next != .zero { value = next }
        }
    }

    private struct BinFramesKey: PreferenceKey {
        static var defaultValue: [DrillBin: CGRect] { [:] }
        static func reduce(value: inout [DrillBin: CGRect], nextValue: () -> [DrillBin: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// After dismissing the enrichment sheet, the top card may have had its
    /// enrichment persisted — pull the fresh copy from disk so the in-memory
    /// queue reflects it.
    private func refreshTopCard() {
        guard let top = queue.first else { return }
        let fresh = DrillStore.shared.due().first(where: { $0.id == top.id })
        if let fresh = fresh {
            queue[0] = fresh
        }
    }

    private var cardDeck: some View {
        VStack(spacing: 12) {
            counterRow
            deck
            binHintRow
            // The folders live where the tray will rise — at rest they're
            // quiet counters, mid-drag the panel takes their place.
            folderChipsRow
                .opacity(isDragging ? 0 : 1)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        // The panel FLOATS over the bottom of the deck rather than sitting
        // under it in the stack: reserving its height left a dead band at
        // rest, and letting it push the card would move the card out from
        // under the finger the moment the drag — and with it the drop
        // targets — began.
        .overlay(alignment: .bottom) {
            if isDragging {
                binPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: Self.deckSpace)
        .onPreferenceChange(DeckFrameKey.self) { deckFrame = $0 }
        .onPreferenceChange(BinFramesKey.self) { binFrames = $0 }
    }

    private var deck: some View {
        Group {
            ZStack {
                // Peek of the next card so the user feels there's a deck.
                // Recall cards stay concealed in the peek so the upcoming
                // answer doesn't leak while grading the current one.
                if queue.count > 1 {
                    cardSurface(queue[1], revealed: !needsReveal(queue[1]))
                        .scaleEffect(0.95)
                        .opacity(0.45)
                        .offset(y: 14)
                }
                cardSurface(queue[0], revealed: isTopRevealed, isTop: true)
                    .scaleEffect(flyScale)
                    .opacity(flyOpacity)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                    .gesture(
                        DragGesture()
                            .onChanged { handleDragChanged($0) }
                            .onEnded { handleDragEnded($0) }
                    )
                    .onTapGesture {
                        guard !isTopRevealed else { return }
                        HapticEngine.drillCorrect()
                        withAnimation(.easeOut(duration: 0.2)) { topCardRevealed = true }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityActions { binAccessibilityActions }
            }
            .padding(.horizontal, 16)
            .background {
                GeometryReader { g in
                    Color.clear.preference(key: DeckFrameKey.self,
                                           value: g.frame(in: .named(Self.deckSpace)))
                }
            }
        }
    }

    private static let deckSpace = "drilldeck"

    /// The drop targets plus the line that names the one you're over. They
    /// exist only mid-drag: the panel answers "where do I let go?", a question
    /// that doesn't exist until the card is moving.
    ///
    /// The folders themselves ARE the panel — no container behind them. A
    /// blurred tray was tried and pulled: it drew a second surface rising over
    /// the card, and the folders had to compete with it to read as targets.
    private var binPanel: some View {
        VStack(spacing: 10) {
            // Above the row, and centred: the folders are a decision, and
            // this is the way past it — so it sits on the path back to the
            // card rather than at the end of the row, where it would read as
            // a fifth folder.
            cancelSlot
            HStack(spacing: 8) {
                ForEach(DrillBin.allCases) { bin in
                    binSlot(bin)
                }
            }
            Group {
                switch activeTarget {
                case .bin(let bin): Text(bin.dropHint)
                case .cancel:       Text("Leave it undecided")
                case nil:           Text("Drop it on a folder")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: activeTarget)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        // As low as it can go — see StudyDeckView's twin for why the inner
        // bottom padding went away with the slab.
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity)
        // No slab behind the row. The folders and the cancel circle carry
        // their own fills, and a tray drawn around them read as a second
        // surface sliding up over the card.
        .allowsHitTesting(false)
    }

    /// The way out: drag UP and the card goes back where it was. Not red —
    /// nothing is being destroyed, and a card you aren't ready to grade is a
    /// normal thing to want, not a mistake being undone.
    private var cancelSlot: some View {
        let active = activeTarget == .cancel && isDragging
        return Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active ? Color(.systemBackground) : Color.secondary)
            .frame(width: 46, height: 46)
            .background {
                // Same blur as the folders — the circle sits over the card too.
                // Aimed-at is OPAQUE: `.secondary` is a label colour at ~60%
                // alpha, so the card read through the active target.
                Circle().fill(active ? AnyShapeStyle(Color(.systemGray))
                                     : AnyShapeStyle(.regularMaterial))
            }
            .scaleEffect(active ? 1.12 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
            .accessibilityIdentifier("drill.cancel")
            .accessibilityLabel(Text("Leave it undecided"))
    }

    private func binSlot(_ bin: DrillBin) -> some View {
        let active = activeTarget == .bin(bin) && isDragging
        return VStack(spacing: 5) {
            Image(systemName: bin.icon)
                .font(.title3)
            Text(bin.title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(active ? Color.white : Color.secondary)
        .background {
            // Blur, not a translucent fill: with no tray behind the row each
            // target has to make its own backdrop, and a fill lets the card's
            // text read straight through it.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(active ? AnyShapeStyle(bin.tint) : AnyShapeStyle(.regularMaterial))
        }
        .scaleEffect(active ? 1.08 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
        .background {
            GeometryReader { g in
                Color.clear.preference(key: BinFramesKey.self,
                                       value: [bin: g.frame(in: .named(Self.deckSpace))])
            }
        }
    }

    /// VoiceOver can't drag. Same four outcomes, as rotor actions.
    @ViewBuilder
    private var binAccessibilityActions: some View {
        ForEach(DrillBin.allCases) { bin in
            Button(bin.accessibilityTitle) {
                guard isTopRevealed else { return }
                apply(bin)
            }
        }
    }

    private var counterRow: some View {
        HStack(spacing: 0) {
            Text("\(initialCount - queue.count + 1) of \(initialCount)")
            if remainingDue > 0 {
                // The rest of the due pile didn't vanish — it's just not in
                // this hand. Saying so here keeps the cap from reading as a
                // miscount next to a 399-card queue.
                Text(" · \(remainingDue) waiting")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    // MARK: - Folder chips

    private var folderChipsRow: some View {
        HStack(spacing: 8) {
            ForEach(DrillBin.allCases) { bin in
                folderChip(bin)
            }
        }
    }

    private func folderChip(_ bin: DrillBin) -> some View {
        let count = folderCards[bin]?.count ?? 0
        return Button {
            openFolder = bin
        } label: {
            HStack(spacing: 5) {
                Image(systemName: bin.icon)
                    .font(.caption)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(bin.tint))
            .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .animation(.snappy, value: count)
        .accessibilityLabel("\(bin.folderTitle): \(count)")
    }

    private func folderSheet(_ bin: DrillBin) -> some View {
        NavigationStack {
            List {
                // The menu below is the only way back out of a folder, and a
                // long-press nothing points at is a dead end for anyone who
                // doesn't guess it. Same footer as the study deck's folders.
                Section {
                    ForEach(folderCards[bin] ?? []) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.targetPhrase)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text("Back \(card.nextReviewAt, format: .relative(presentation: .named))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            // The same four verdicts as the tray, so a card can
                            // be pulled forward, pushed back, or finished without
                            // waiting for it to come due. "Got it" is dropped for
                            // a card that already graduated — it would do nothing.
                            ForEach(DrillBin.allCases.filter {
                                $0 != .gotIt || bin != .gotIt
                            }) { target in
                                Button {
                                    resnooze(card, to: target)
                                } label: {
                                    Label(target.accessibilityTitle, systemImage: target.icon)
                                }
                            }
                        }
                    }
                } footer: {
                    if !(folderCards[bin] ?? []).isEmpty {
                        Text("Touch and hold to file it again.")
                    }
                }
            }
            .overlay {
                if (folderCards[bin] ?? []).isEmpty {
                    ContentUnavailableView(bin.folderTitle, systemImage: bin.icon)
                }
            }
            .navigationTitle(bin.folderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { openFolder = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }


    /// Recall cards (those with a sourcePhrase) start concealed.
    private func needsReveal(_ card: DrillCard) -> Bool {
        !card.sourcePhrase.isEmpty
    }

    private var isTopRevealed: Bool {
        guard let top = queue.first else { return true }
        return topCardRevealed || !needsReveal(top)
    }

    @ViewBuilder
    private var binHintRow: some View {
        if isTopRevealed {
            // Mid-drag the panel says where the card is headed, so this row
            // goes quiet — but keeps its height, or the deck would jump the
            // instant a drag begins.
            Label("Drag the card into a folder", systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .opacity(isDragging ? 0 : 1)
        } else {
            Label("Say it out loud, then tap the card to check", systemImage: "hand.tap")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Drag → bin

    private func handleDragChanged(_ value: DragGesture.Value) {
        // No grading before recall — the card doesn't move until revealed.
        guard isTopRevealed else { dragOffset = .zero; return }
        if !isDragging {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isDragging = true }
        }
        dragOffset = value.translation
        updateActiveTarget(for: value.translation)
    }

    /// Which bin the card is currently over. Nearest-centre rather than
    /// containment, so the gap between bins (and the space above the tray,
    /// where the card actually is) still resolves to a target.
    private func updateActiveTarget(for translation: CGSize) {
        let travelled = hypot(translation.width, translation.height)
        guard travelled > Self.binDeadZone, !binFrames.isEmpty else {
            if activeTarget != nil { activeTarget = nil }
            return
        }
        // Direction decides between the two KINDS of target before position
        // decides between folders. The folders sit at the bottom of the
        // screen, so pulling the card up is already the gesture for "away
        // from all of them" — cancel only has to be given a face.
        if translation.height < -Self.cancelThreshold {
            guard activeTarget != .cancel else { return }
            activeTarget = .cancel
            HapticEngine.drillBinChanged()
            return
        }
        let x = deckFrame.midX + translation.width
        let candidate = binFrames
            .min { abs($0.value.midX - x) < abs($1.value.midX - x) }
            .map(\.key)
        guard let candidate, activeTarget != .bin(candidate) else { return }
        // Hysteresis applies between two FOLDERS only. Coming back down from
        // cancel there is no previous folder to be sticky about, and making
        // it sticky would leave the card highlighting nothing on the way.
        if case .bin(let current) = activeTarget,
           let currentFrame = binFrames[current],
           let candidateFrame = binFrames[candidate] {
            let gain = abs(currentFrame.midX - x) - abs(candidateFrame.midX - x)
            guard gain > Self.binHysteresis else { return }
        }
        activeTarget = .bin(candidate)
        HapticEngine.drillBinChanged()
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let travelled = hypot(value.translation.width, value.translation.height)
        // Cancel and "didn't drag far enough" end the same way, on purpose:
        // the card goes back, ungraded, and nothing is written. The circle
        // exists to make that outcome VISIBLE, not to add a new one.
        guard isTopRevealed, travelled > Self.commitThreshold,
              case .bin(let bin) = activeTarget else {
            springBack()
            return
        }
        drop(into: bin)
    }

    private func springBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            dragOffset = .zero
            isDragging = false
        }
        activeTarget = nil
    }

    /// The card gets swallowed: it flies to the bin's centre while shrinking
    /// out of existence, and only then is the schedule written and the queue
    /// advanced — so the next card never appears under a card still in flight.
    private func drop(into bin: DrillBin) {
        HapticEngine.drillBinned(mastered: bin == .gotIt)
        let target = binFrames[bin].map {
            CGSize(width: $0.midX - deckFrame.midX, height: $0.midY - deckFrame.midY)
        } ?? .zero
        withAnimation(.easeIn(duration: 0.28)) {
            dragOffset = target
            flyScale = 0.12
            flyOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            apply(bin)
            dragOffset = .zero
            flyScale = 1
            flyOpacity = 1
            withAnimation(.easeOut(duration: 0.2)) { isDragging = false }
            activeTarget = nil
        }
    }
}

/// Where a drilled card goes when the learner lets go of it: three explicit
/// "show me this again in…" delays plus the automatic promotion.
///
/// The three delays double as Leitner boxes (see `DrillStore.snooze`), so
/// picking one parks the card on a rung of the same ladder rather than off it.
/// Where a dragged card can land — either a folder, or back where it came
/// from. Shared by BOTH decks so the sentence drill and the study deck can't
/// drift on what a drag can do, the same reason they share `DrillBin`.
///
/// `cancel` writes nothing: it's the card you've looked at and don't want to
/// answer for yet. Releasing short of the commit threshold has always done
/// this, but silently — nothing on screen said it was possible, so the only
/// visible way out of a drag was to file the card somewhere you didn't mean.
enum DropTarget: Hashable {
    case bin(DrillBin)
    case cancel
}

enum DrillBin: String, CaseIterable, Identifiable {
    case tenMinutes, tomorrow, threeDays, gotIt

    var id: String { rawValue }

    // The shortest "show me again" delay, in one place so the label, the
    // schedule and the accessibility title can never disagree. (It was
    // temporarily a minute in DEBUG to make the drop → notification → review
    // round trip testable by hand.)
    static let soonDelay: TimeInterval = 10 * 60
    static let soonTitle = "10 min"
    static let soonHint = "Back in 10 minutes"
    static let soonAccessibilityTitle = "Show again in 10 minutes"

    var title: String {
        switch self {
        case .tenMinutes: return Self.soonTitle
        case .tomorrow:   return "Tomorrow"
        case .threeDays:  return "3 days"
        case .gotIt:      return "Got it"
        }
    }

    var icon: String {
        switch self {
        case .tenMinutes: return "clock"
        case .tomorrow:   return "sunrise"
        case .threeDays:  return "calendar"
        case .gotIt:      return "checkmark.circle.fill"
        }
    }

    /// Soon → later → done, read as a warm-to-cool-to-green run.
    var tint: Color {
        switch self {
        case .tenMinutes: return .orange
        case .tomorrow:   return .blue
        case .threeDays:  return .indigo
        case .gotIt:      return .green
        }
    }

    /// Box + delay for the manual choices; nil for `.gotIt`, which hands the
    /// card straight to the top rung (`DrillStore.markKnown`).
    var manual: (box: Int, delay: TimeInterval)? {
        switch self {
        case .tenMinutes: return (0, Self.soonDelay)
        case .tomorrow:   return (1, 24 * 60 * 60)
        case .threeDays:  return (2, 3 * 24 * 60 * 60)
        case .gotIt:      return nil
        }
    }

    /// Folder name at rest. Reads differently from the drop action that put
    /// a card there: the folder holds every card whose RETURN falls in its
    /// window, so "3 days" the action becomes "Later" the place, and box-5
    /// graduates collect under "Known".
    var folderTitle: String {
        switch self {
        case .tenMinutes: return "Soon"
        case .tomorrow:   return "Tomorrow"
        case .threeDays:  return "Later"
        case .gotIt:      return "Known"
        }
    }

    /// Which folder a still-future return time falls in. The windows are
    /// generous on purpose — a folder is a rough "when is this coming back",
    /// not a countdown — and they live here so the sentence deck and the
    /// word/expression deck can never disagree about what "Soon" means.
    /// (Neither deck asks about a return already in the past: that item is in
    /// today's hand, not in a folder.)
    static func folder(forReturnIn interval: TimeInterval) -> DrillBin {
        if interval <= 12 * 60 * 60 { return .tenMinutes }
        if interval <= 48 * 60 * 60 { return .tomorrow }
        return .threeDays
    }

    var dropHint: String {
        switch self {
        case .tenMinutes: return Self.soonHint
        case .tomorrow:   return "Back tomorrow"
        case .threeDays:  return "Back in 3 days"
        case .gotIt:      return explain("Marked as known")
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .tenMinutes: return Self.soonAccessibilityTitle
        case .tomorrow:   return "Show again tomorrow"
        case .threeDays:  return "Show again in 3 days"
        case .gotIt:      return "Got it"
        }
    }
}

extension DrillView {
    /// Bigger phrases get smaller type so the full sentence always shows —
    /// truncating a line the user has to read OUT LOUD is fatal. Shared with
    /// `PracticeSessionView`'s shadow stage.
    static func targetFont(for text: String) -> Font {
        switch text.count {
        case ..<60:    return .title.weight(.semibold)
        case 60..<120: return .title2.weight(.semibold)
        default:       return .title3.weight(.semibold)
        }
    }
}

/// Sheet wrapper — kept for backward compat; main app uses `DrillView`
/// directly inside `PracticeTab` now.
struct DrillSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DrillView()
                .navigationTitle("Sentences")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private extension DrillView {

    // MARK: - Card surface

    @ViewBuilder
    func cardSurface(_ card: DrillCard, revealed: Bool = true, isTop: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Every text below is `fixedSize(vertical:)` — when the card runs
            // out of room SwiftUI otherwise compresses the texts and elides
            // them with "…", which is fatal for a phrase the user must READ
            // OUT LOUD. The target font also steps down for long phrases so
            // the whole card still fits on screen.
            if !card.sourcePhrase.isEmpty {
                labeled("You said") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Cards ingested before the fragment trim carry the
                        // WHOLE turn transcript — trim at render too, so the
                        // stored backlog doesn't blow the card off the screen.
                        Text(DrillStore.relevantFragment(of: card.sourcePhrase,
                                                         matching: card.targetPhrase))
                            .font(.callout)
                            .foregroundStyle(Self.onCardSecondary)
                            .strikethrough(revealed)
                            .fixedSize(horizontal: false, vertical: true)
                        // The transcript is STT output and occasionally wrong —
                        // when the user's actual recording survives on disk,
                        // let them replay what they REALLY said.
                        if let turnId = card.sourceTurnId,
                           TurnAudioStore.shared.url(for: turnId) != nil {
                            let playingThis = playingTurnId == turnId && player.isPlaying
                            Button {
                                if playingThis {
                                    player.stop()
                                    playingTurnId = nil
                                } else {
                                    playUserRecording(turnId)
                                }
                            } label: {
                                // play → stop while the recording runs, with a
                                // replace transition — the tap visibly "takes"
                                // and the running state is tellable at a glance.
                                Image(systemName: playingThis ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .contentTransition(.symbolEffect(.replace))
                                    .symbolEffect(.pulse, isActive: playingThis)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(playingThis ? "Stop your recording" : "Play your recording")
                        }
                    }
                }
            }

            labeled(revealed ? "Try saying" : "How would a fluent speaker say it?") {
                Text(card.targetPhrase)
                    .font(Self.targetFont(for: card.targetPhrase))
                    .foregroundStyle(Self.onCard)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .redacted(reason: revealed ? [] : .placeholder)
            }

            if revealed, !card.reason.isEmpty {
                labeled("Why") {
                    Text(card.reason)
                        .font(.subheadline)
                        .foregroundStyle(Self.onCardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if revealed {
                HStack(spacing: 8) {
                    pillButton(systemImage: isLoadingAudio ? nil : "speaker.wave.2.fill",
                               text: isLoadingAudio ? "Loading…" : "Hear it",
                               showSpinner: isLoadingAudio) {
                        Task { await playTarget(card) }
                    }
                    .disabled(isLoadingAudio)

                    pillButton(systemImage: "waveform.badge.mic", text: "Shadow") {
                        shadowingCard = card
                    }

                    pillButton(systemImage: card.enrichment == nil ? "books.vertical" : "books.vertical.fill",
                               text: "Examples") {
                        showingEnrichmentFor = card
                    }
                }
            } else {
                Label("Tap to reveal", systemImage: "eye")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        // Dropped the 360pt minHeight — long targetPhrases were being
        // clipped because Spacer + tight box left no room. Now the card
        // grows to fit the text; minHeight kept just for visual presence
        // on short cards.
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        // The accent IS the card now, so every foreground on it reads against
        // the accent, not the system background. Setting the tint once here
        // carries `.foregroundStyle(.tint)` descendants (play glyph, "Tap to
        // reveal", pill labels) along with it.
        .tint(Self.onCard)
        .shadow(color: Color.accentColor.opacity(0.28), radius: 8, y: 4)
    }

    /// Content color on the accent card.
    static var onCard: Color { .white }
    /// Supporting text — the card's own "secondary".
    static var onCardSecondary: Color { .white.opacity(0.72) }

    @ViewBuilder
    func pillButton(systemImage: String?, text: String, showSpinner: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if showSpinner {
                    ProgressView().controlSize(.mini)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.18)))
            .foregroundStyle(Self.onCard)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Self.onCardSecondary)
            content()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label(initialCount == 0 ? "No drills due" : "Nice work",
                      systemImage: initialCount == 0 ? "lightbulb" : "checkmark.circle.fill")
            } description: {
                if initialCount == 0 {
                    Text("Drills appear here after you end a conversation.")
                } else if remainingDue > 0 {
                    Text("You finished \(initialCount) cards. \(remainingDue) more are waiting when you're ready.")
                } else {
                    Text("You finished \(initialCount) card\(initialCount == 1 ? "" : "s"). They'll surface again on the Leitner schedule.")
                }
            } actions: {
                if remainingDue > 0 {
                    Button {
                        loadQueue()
                        refreshFolders()
                    } label: {
                        Text("Next \(min(remainingDue, Self.sessionCap))")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            // Folders stay reachable with nothing due — that's when "what's
            // coming back tomorrow?" is the question being asked.
            folderChipsRow
                .padding(.bottom, 16)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    // MARK: - Actions

    private func loadQueue() {
        remainingDue = 0
        switch source {
        case .due:
            let due = DrillStore.shared.due()
            queue = Array(due.prefix(Self.sessionCap))
            remainingDue = due.count - queue.count
        case .session(let sid):
            // The post-talk run is a quick close-out, not a grind: the
            // talk's first cards (corrections lead the ingestion order),
            // capped small. Everything else surfaces through the due queue
            // like any other card — nothing is lost by stopping here.
            queue = Array(
                DrillStore.shared.load()
                    .filter { $0.sourceSessionId == sid }
                    .sorted { $0.createdAt < $1.createdAt }
                    .prefix(Self.quickRunCap)
            )
        case .ahead(let limit):
            queue = Array(
                DrillStore.shared.load()
                    .sorted { $0.nextReviewAt < $1.nextReviewAt }
                    .prefix(limit)
            )
        case .scenario:
            queue = DrillStore.shared.load()
                .filter { $0.sourceSessionId == nil }
                .sorted { $0.createdAt < $1.createdAt }
        case .card(let id):
            // Deleted between the promise and the tap → empty state, which
            // reads honestly ("nothing here") instead of opening a stranger.
            queue = DrillStore.shared.load().filter { $0.id == id }
        }
        initialCount = queue.count
    }

    /// Write the bin's choice to the top card and move on.
    private func apply(_ bin: DrillBin) {
        guard let card = queue.first else { return }
        if let manual = bin.manual {
            let at = Date().addingTimeInterval(manual.delay)
            DrillStore.shared.snooze(card, box: manual.box, until: at)
            // A folder drop is a promise about THIS line — the callback names
            // it and opens it (see ItemReminder).
            Task {
                await ItemReminder.schedule(.sentence(card.id),
                                            text: card.targetPhrase, at: at)
            }
        } else {
            DrillStore.shared.markKnown(card)
            ItemReminder.cancel(.sentence(card.id))
        }
        // Only "Got it" finishes a card; the delay bins are "not yet".
        PracticeLog.shared.record(.drill, finished: bin.manual == nil)
        // The chip the card landed in ticks up as the deck advances — the
        // visible "it went somewhere" that makes grading feel like sorting.
        withAnimation(.snappy) { refreshFolders() }
        advance()
    }

    /// Rebucket every future-scheduled card into the folder it currently
    /// sits in. Buckets are by WHEN the card comes back, not by which bin
    /// last swallowed it — "Got it" from a low box honestly lands in
    /// Tomorrow, because that's when the ladder will bring it back.
    private func refreshFolders(now: Date = Date()) {
        var buckets: [DrillBin: [DrillCard]] = [:]
        for card in DrillStore.shared.load() where card.nextReviewAt > now {
            let bin = card.box >= DrillStore.maxBox
                ? .gotIt
                : DrillBin.folder(forReturnIn: card.nextReviewAt.timeIntervalSince(now))
            buckets[bin, default: []].append(card)
        }
        folderCards = buckets.mapValues { $0.sorted { $0.nextReviewAt < $1.nextReviewAt } }
    }

    /// Reschedule straight from a folder list — the card never re-enters
    /// the deck for this.
    private func resnooze(_ card: DrillCard, to bin: DrillBin) {
        if let manual = bin.manual {
            DrillStore.shared.snooze(card, box: manual.box,
                                     until: Date().addingTimeInterval(manual.delay))
        } else {
            // Same verdict the rightmost bin writes, minus the rep: the card
            // was already counted when it was graded, and changing your mind
            // about it isn't a second one.
            DrillStore.shared.markKnown(card)
            ItemReminder.cancel(.sentence(card.id))
        }
        withAnimation(.snappy) { refreshFolders() }
    }

    private func advance() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        topCardRevealed = false
        player.stop()
        playingTurnId = nil
        if queue.isEmpty { onDeckCompleted?() }
    }

    /// Replay the user's own mic recording for the turn this card came from.
    /// Local file only — no credits, no network.
    private func playUserRecording(_ turnId: UUID) {
        guard let data = TurnAudioStore.shared.data(for: turnId) else { return }
        do {
            try player.play(data, source: "drill", forceSessionReset: true)
            playingTurnId = turnId
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func playTarget(_ card: DrillCard) async {
        guard let voiceId = appState.voiceCloneId else { return }
        // Force-reset keeps playback loud even if another surface left the
        // audio session in .measurement mode (same fix as ShadowDrillView).
        playingTurnId = nil
        if let cached = PhraseAudioStore.shared.data(text: card.targetPhrase, voiceId: voiceId) {
            do { try player.play(cached, source: "drill", forceSessionReset: true) } catch { self.error = error.localizedDescription }
            return
        }
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        do {
            let audio = try await ElevenLabsClient.shared.synthesize(
                voiceId: voiceId,
                text: card.targetPhrase,
                purpose: "drill"
            )
            PhraseAudioStore.shared.save(audio, text: card.targetPhrase, voiceId: voiceId)
            try player.play(audio, source: "drill", forceSessionReset: true)
        } catch {
            // Out of credits: only HEARING a never-synthesized line is
            // blocked — grading itself is on-device and stays free. Say so,
            // instead of surfacing the raw 402.
            self.error = error.isOutOfCredits
                ? "Hearing this line for the first time needs credits — Say-it grading is still free."
                : error.localizedDescription
        }
    }
}
