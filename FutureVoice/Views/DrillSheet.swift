import SwiftUI

/// Spaced-repetition drill queue. Walks through the cards that are currently
/// due — the learner hears the target phrase in their cloned voice, then
/// self-rates Got it / Try again to advance the Leitner box.
struct DrillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()

    @State private var queue: [DrillCard] = []
    @State private var initialCount: Int = 0
    @State private var isLoadingAudio = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let card = queue.first {
                    cardView(card)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Drills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if initialCount > 0 {
                        Text("\(initialCount - queue.count + (queue.isEmpty ? 0 : 1)) of \(initialCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't play audio", isPresented: errorBinding) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .onAppear(perform: loadQueue)
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func cardView(_ card: DrillCard) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    if !card.reason.isEmpty {
                        labeled("Why") {
                            Text(card.reason)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }

            Divider().opacity(0.15)

            VStack(spacing: 12) {
                Button {
                    Task { await playTarget(card) }
                } label: {
                    HStack(spacing: 8) {
                        if isLoadingAudio {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        Text(isLoadingAudio ? "Loading…" : "Hear it")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isLoadingAudio || appState.voiceCloneId == nil)

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        markIncorrect()
                    } label: {
                        Label("Try again", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        markCorrect()
                    } label: {
                        Label("Got it", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
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
        queue = DrillStore.shared.due()
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
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        do {
            let audio = try await ElevenLabsClient.shared.synthesize(
                voiceId: voiceId,
                text: card.targetPhrase
            )
            try player.play(audio)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
