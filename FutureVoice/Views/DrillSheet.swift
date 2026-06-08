import SwiftUI

/// Spaced-repetition drill queue. Walks through the cards that are currently
/// due — the learner hears the target phrase in their cloned voice, then
/// self-rates Got it / Try again to advance the Leitner box.
///
/// Shadow practice lives in its own sheet (`ShadowBrowserSheet`); the two are
/// surfaced from separate toolbar entries so the home dashboard can track each
/// independently.
/// Card-deck SRS practice. Swipe right = Got it, left = Try again. Tap to
/// hear it. No bottom button bar — important under a tab bar so the controls
/// don't visually merge with system chrome. A faint "next card" preview sits
/// behind the active card for the deck-of-cards feel.
struct DrillView: View {
    /// Optional filter. `.due` (default) = the Leitner-scheduled queue.
    /// `.session(id)` = every card whose source matches the given session,
    /// regardless of due date. Lets the user post-mortem a specific
    /// conversation by walking just its cards.
    enum Source: Equatable {
        case due
        case session(UUID)
    }
    var source: Source = .due

    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()

    @State private var queue: [DrillCard] = []
    @State private var initialCount: Int = 0
    @State private var isLoadingAudio = false
    @State private var error: String?
    @State private var dragOffset: CGSize = .zero
    @State private var showingEnrichmentFor: DrillCard?

    private static let swipeThreshold: CGFloat = 100

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
        .onAppear(perform: loadQueue)
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
            ZStack {
                // Peek of the next card so the user feels there's a deck
                if queue.count > 1 {
                    cardSurface(queue[1])
                        .scaleEffect(0.95)
                        .opacity(0.45)
                        .offset(y: 14)
                }
                cardSurface(queue[0])
                    .overlay(swipeIndicator)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation }
                            .onEnded { handleDragEnded($0) }
                    )
                    .onTapGesture {
                        Task { await playTarget(queue[0]) }
                    }
            }
            .padding(.horizontal, 16)
            hintRow
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var counterRow: some View {
        Text("\(initialCount - queue.count + 1) of \(initialCount)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var swipeIndicator: some View {
        Group {
            if dragOffset.width > 20 {
                Label("Got it", systemImage: "checkmark")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.green))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-12))
                    .opacity(min(1.0, Double(dragOffset.width) / 120.0))
            } else if dragOffset.width < -20 {
                Label("Try again", systemImage: "arrow.counterclockwise")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(12))
                    .opacity(min(1.0, Double(-dragOffset.width) / 120.0))
            }
        }
    }

    private var hintRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left").foregroundStyle(.red)
                Text("Try again")
            }
            Text("·").foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                Image(systemName: "hand.tap")
                Text("Tap to hear")
            }
            Text("·").foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                Text("Got it")
                Image(systemName: "arrow.right").foregroundStyle(.green)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let width = value.translation.width
        if width > Self.swipeThreshold {
            HapticEngine.drillCorrect()
            withAnimation(.easeOut(duration: 0.25)) {
                dragOffset = CGSize(width: 600, height: value.translation.height)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                markCorrect()
                dragOffset = .zero
            }
        } else if width < -Self.swipeThreshold {
            HapticEngine.drillIncorrect()
            withAnimation(.easeOut(duration: 0.25)) {
                dragOffset = CGSize(width: -600, height: value.translation.height)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                markIncorrect()
                dragOffset = .zero
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
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
                .navigationTitle("Drills")
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
    func cardSurface(_ card: DrillCard) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !card.sourcePhrase.isEmpty {
                labeled("You said") {
                    Text(card.sourcePhrase)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
            }

            labeled("Try saying") {
                Text(card.targetPhrase)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }

            if !card.reason.isEmpty {
                labeled("Why") {
                    Text(card.reason)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    if isLoadingAudio {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                    }
                    Text(isLoadingAudio ? "Loading…" : "Tap card to hear")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingEnrichmentFor = card
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "books.vertical")
                        Text(card.enrichment == nil ? "Examples" : "Examples ✓")
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    @ViewBuilder
    func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            initialCount == 0 ? "No drills due" : "Nice work",
            systemImage: initialCount == 0 ? "lightbulb" : "checkmark.circle.fill",
            description: Text(initialCount == 0
                ? "Drills appear here after you end a conversation."
                : "You finished \(initialCount) card\(initialCount == 1 ? "" : "s"). They'll surface again on the Leitner schedule.")
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    // MARK: - Actions

    private func loadQueue() {
        switch source {
        case .due:
            queue = DrillStore.shared.due()
        case .session(let sid):
            queue = DrillStore.shared.load()
                .filter { $0.sourceSessionId == sid }
                .sorted { $0.createdAt < $1.createdAt }
        }
        initialCount = queue.count
    }

    private func markCorrect() {
        guard let card = queue.first else { return }
        DrillStore.shared.markCorrect(card)
        advance()
    }

    private func markIncorrect() {
        guard let card = queue.first else { return }
        DrillStore.shared.markIncorrect(card)
        advance()
    }

    private func advance() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
    }

    private func playTarget(_ card: DrillCard) async {
        guard let voiceId = appState.voiceCloneId else { return }
        if let cached = PhraseAudioStore.shared.data(text: card.targetPhrase, voiceId: voiceId) {
            do { try player.play(cached) } catch { self.error = error.localizedDescription }
            return
        }
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        do {
            let audio = try await ElevenLabsClient.shared.synthesize(
                voiceId: voiceId,
                text: card.targetPhrase
            )
            PhraseAudioStore.shared.save(audio, text: card.targetPhrase, voiceId: voiceId)
            try player.play(audio)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
