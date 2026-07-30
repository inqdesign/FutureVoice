import SwiftUI

/// Bottom sheet that shows examples, variants, and a memory hook for the
/// current drill card. Loads enrichment from Gemini on first open, then
/// persists into the DrillCard so subsequent opens are free.
struct DrillEnrichmentSheet: View {
    let card: DrillCard
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()

    @State private var enrichment: DrillCardEnrichment?
    @State private var loading = false
    @State private var error: String?
    @State private var playingExample: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    targetHeader
                    if loading {
                        loadingBlock
                    } else if let e = enrichment {
                        memoryHookCard(e.memoryHook)
                        examplesSection(e.examples)
                        variantsSection(e.variants)
                    } else if let err = error {
                        errorBlock(err)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .navigationTitle("Examples & variants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadIfNeeded() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var targetHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try saying")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(card.targetPhrase)
                .font(.title3.weight(.semibold))
            if !card.reason.isEmpty {
                Text(card.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var loadingBlock: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Pulling examples from your life…")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Try again") { Task { await reload() } }
        }
    }

    @ViewBuilder
    private func memoryHookCard(_ hook: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text("Remember this when")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(hook)
                    .font(.body)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func examplesSection(_ items: [DrillCardEnrichment.Example]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("In your life", icon: "scope")
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                exampleRow(idx: idx, item: item)
            }
        }
    }

    private func exampleRow(idx: Int, item: DrillCardEnrichment.Example) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.situation)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.sentence)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await playExample(idx: idx, text: item.sentence) }
                } label: {
                    Image(systemName: playingExample == idx ? "speaker.wave.2.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func variantsSection(_ items: [DrillCardEnrichment.Variant]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Variants", icon: "arrow.triangle.branch")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.phrase)
                        .font(.body.weight(.medium))
                    Text(item.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func loadIfNeeded() async {
        if let cached = card.enrichment {
            enrichment = cached
            return
        }
        await reload()
    }

    private func reload() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let fresh = try await DrillEnrichmentEngine.generate(
                card: card,
                persona: appState.persona,
                targetLanguage: appState.targetLanguage
            )
            enrichment = fresh
            // Persist back into the card so next open is free.
            var updated = card
            updated.enrichment = fresh
            DrillStore.shared.save(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func playExample(idx: Int, text: String) async {
        guard let voiceId = appState.voiceCloneId else { return }
        if let cached = PhraseAudioStore.shared.data(text: text, voiceId: voiceId) {
            playingExample = idx
            do {
                try player.play(cached) {
                    Task { @MainActor in self.playingExample = nil }
                }
            } catch {
                playingExample = nil
            }
            return
        }
        do {
            let audio = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: text, purpose: "drill")
            PhraseAudioStore.shared.save(audio, text: text, voiceId: voiceId)
            playingExample = idx
            try player.play(audio) {
                Task { @MainActor in self.playingExample = nil }
            }
        } catch {
            playingExample = nil
        }
    }
}
