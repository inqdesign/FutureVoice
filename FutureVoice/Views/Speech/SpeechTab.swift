import SwiftUI

/// The Speech tab: read a script aloud like a presenter, under a prompter
/// that follows your voice, camera on or off, and get the take scored.
/// Nothing here synthesizes speech — the only voice is the learner's.
struct SpeechTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var gate = BillingGate.shared
    @State private var path: [UUID] = []
    @State private var composing = false
    @State private var showingPaywall = false

    private var canWrite: Bool { gate.account?.canWriteSpeechScripts ?? false }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(store.scripts) { script in
                        NavigationLink(value: script.id) {
                            SpeechScriptRow(script: script, best: store.best(for: script.id))
                        }
                    }
                } header: {
                    Text("Scripts")
                } footer: {
                    if !canWrite {
                        Text("Write your own scripts on any topic with Plus.")
                    }
                }
            }
            .navigationTitle("Speech")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            if await BillingGate.shared.allowsSpeechScripts() { composing = true }
                            else { showingPaywall = true }
                        }
                    } label: {
                        Label("New script", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                SpeechScriptDetailView(scriptId: id)
            }
        }
        .onAppear {
            store.reloadIfLanguageChanged()
            if store.scripts.isEmpty { store.reload() }
            BillingGate.shared.warm()
        }
        .onChange(of: appState.targetLanguage) { _, _ in
            path = []
            store.reload()
        }
        .sheet(isPresented: $composing) {
            SpeechComposerSheet { script in
                store.add(script)
                path = [script.id]
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "speech_script", preselectTier: "plus")
        }
    }
}

struct SpeechScriptRow: View {
    let script: SpeechScript
    let best: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: script.genre.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(script.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                    Text("·")
                    Text(script.genre.title)
                    if script.isBuiltIn {
                        Text("·")
                        Text("Sample")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let best {
                Text("\(best)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(SpeechScoreColor.color(best))
            }
        }
        .padding(.vertical, 2)
    }
}

enum SpeechScoreColor {
    static func color(_ score: Int) -> Color {
        score >= 85 ? .green : score >= 65 ? .orange : .red
    }
}

// MARK: - Detail

struct SpeechScriptDetailView: View {
    let scriptId: UUID
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = SpeechStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var practicing = false
    @State private var confirmDelete = false

    var body: some View {
        if let script = store.script(id: scriptId) {
            content(script)
        } else {
            ContentUnavailableView("Script not found", systemImage: "doc.text")
        }
    }

    private func content(_ script: SpeechScript) -> some View {
        let takes = store.takes(for: script.id)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(script.title)
                        .font(.title2.weight(.semibold))
                    if !script.summary.isEmpty {
                        Text(script.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(script.body)
                        .font(.body)
                        .lineSpacing(4)
                        .padding(.top, 4)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 6)
            } footer: {
                HStack(spacing: 6) {
                    Label(script.genre.title, systemImage: script.genre.symbol)
                    Text("·")
                    Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                }
            }

            if !script.keyTerms.isEmpty {
                Section("Key terms") {
                    ForEach(script.keyTerms, id: \.self) { term in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.term).font(.body.weight(.medium))
                            if !term.meaning.isEmpty {
                                Text(term.meaning).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !script.sources.isEmpty {
                Section {
                    Text(script.sources.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Sources")
                }
            }

            if !takes.isEmpty {
                Section("Takes") {
                    ForEach(takes) { take in
                        NavigationLink {
                            SpeechResultView(takeId: take.id)
                        } label: {
                            SpeechTakeRow(take: take)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { store.deleteTake(id: takes[i].id) }
                    }
                }
            }
        }
        .navigationTitle(script.genre.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                practicing = true
            } label: {
                Label("Practice", systemImage: "record.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .toolbar {
            if !script.isBuiltIn {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete script", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Delete this script and its takes?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteScript(id: script.id)
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $practicing) {
            SpeechPrompterView(script: script, native: appState.nativeLanguage,
                               level: appState.proficiency)
        }
    }
}

struct SpeechTakeRow: View {
    let take: SpeechTake

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(take.createdAt, format: .dateTime.month().day().hour().minute())
                HStack(spacing: 6) {
                    Text(SpeechFormat.duration(take.durationSeconds))
                    if take.videoFilename != nil {
                        Image(systemName: "video.fill")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(take.metrics.overall)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(SpeechScoreColor.color(take.metrics.overall))
        }
    }
}

// MARK: - Composer

/// Writing a new script: what kind, about what (optional), how long. One
/// button. Plus and up — the caller checks before presenting.
struct SpeechComposerSheet: View {
    var onWritten: (SpeechScript) -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speech.composer.genre") private var genreRaw = SpeechGenre.explainer.rawValue
    @AppStorage("speech.composer.seconds") private var seconds = 60
    @State private var topic = ""
    @State private var writing = false
    @State private var error: String?

    private var genre: SpeechGenre { SpeechGenre(rawValue: genreRaw) ?? .explainer }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $genreRaw) {
                        ForEach(SpeechGenre.allCases) { g in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.title)
                                    Text(g.blurb).font(.footnote).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: g.symbol)
                            }
                            .tag(g.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextField(genre.topicPlaceholder, text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Topic")
                } footer: {
                    Text("Leave it empty and we'll pick something worth knowing.")
                }

                Section("Length") {
                    Picker("Length", selection: $seconds) {
                        ForEach(SpeechLibrary.lengths, id: \.self) { s in
                            Text(SpeechFormat.length(s)).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .disabled(writing)
            .navigationTitle("New script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Write") { write() }
                        .disabled(writing)
                }
            }
            .overlay {
                if writing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Writing your script…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Couldn't write the script", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .interactiveDismissDisabled(writing)
    }

    private func write() {
        writing = true
        let avoid = SpeechStore.shared.scripts.map(\.title)
        Task {
            do {
                let script = try await SpeechScriptEngine.write(
                    genre: genre, topic: topic, seconds: seconds,
                    language: appState.targetLanguage, native: appState.nativeLanguage,
                    level: appState.proficiency, avoidTitles: avoid)
                Analytics.capture("speech_script_written", [
                    "genre": genre.rawValue, "seconds": seconds, "topic": !topic.isEmpty,
                ])
                writing = false
                dismiss()
                onWritten(script)
            } catch {
                writing = false
                self.error = error.localizedDescription
            }
        }
    }
}
