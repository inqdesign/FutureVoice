import SwiftUI

/// The Speech tab: read a script aloud like a presenter, under a prompter
/// that follows your voice, camera on or off, and get the take scored.
/// Nothing here synthesizes speech — the only voice is the learner's.
struct SpeechTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var gate = BillingGate.shared
    /// The script whose prompter is open. Tapping a script opens it straight
    /// away — picking one IS starting to practise it.
    @State private var practicing: SpeechScript?
    /// A script just written or added, opened once its sheet has gone (a
    /// cover raised while a sheet is still dismissing never appears).
    @State private var openAfterSheet: SpeechScript?
    @State private var editing: SpeechScript?
    @State private var composing = false
    @State private var addingOwn = false
    @State private var showingUpsell = false
    /// The menu's two choices, for the tap that only learned after a fresh
    /// fetch that this account may write.
    @State private var choosingKind = false

    private var canWrite: Bool { gate.account?.canWriteSpeechScripts ?? false }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.scripts) { script in
                        Button {
                            practicing = script
                        } label: {
                            SpeechScriptRow(script: script, best: store.best(for: script.id))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if !script.isBuiltIn {
                                Button(role: .destructive) {
                                    store.deleteScript(id: script.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if script.genre == .own {
                                Button { editing = script } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                } header: {
                    Text("Scripts")
                } footer: {
                    if !canWrite {
                        Text("Write scripts on any topic, or add your own, with Plus.")
                    }
                }
            }
            .navigationTitle("Speech")
            // Same header as Watch and Progress: the title inline-large on
            // the toolbar row, the tab's one action at its trailing edge.
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if canWrite {
                        Menu {
                            Button { composing = true } label: {
                                Label("Write with AI", systemImage: "sparkles")
                            }
                            Button { addingOwn = true } label: {
                                Label("Add my own script", systemImage: "pencil.line")
                            }
                        } label: {
                            Label("New script", systemImage: "plus")
                        }
                    } else {
                        // Not known to be Plus: ask fresh. A purchase a minute
                        // ago must not be met with the upsell again.
                        Button {
                            Task {
                                if await BillingGate.shared.allowsSpeechScripts() { choosingKind = true }
                                else { showingUpsell = true }
                            }
                        } label: {
                            Label("New script", systemImage: "plus")
                        }
                    }
                }
            }
        }
        .onAppear {
            store.reloadIfLanguageChanged()
            if store.scripts.isEmpty { store.reload() }
            BillingGate.shared.warm()
        }
        .onChange(of: appState.targetLanguage) { _, _ in
            store.reload()
        }
        .sheet(isPresented: $composing, onDismiss: openPending) {
            SpeechComposerSheet { script in
                store.add(script)
                openAfterSheet = script
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $addingOwn, onDismiss: openPending) {
            SpeechOwnScriptSheet(existing: nil) { script in
                store.add(script)
                openAfterSheet = script
            }
            .environmentObject(appState)
        }
        .sheet(item: $editing) { script in
            SpeechOwnScriptSheet(existing: script) { updated in
                store.add(updated)
            }
            .environmentObject(appState)
        }
        .fullScreenCover(item: $practicing) { script in
            SpeechPrompterView(script: script, native: appState.nativeLanguage,
                               level: appState.proficiency)
                .environmentObject(appState)
        }
        // Any script beyond the bundled one is Plus and up. The tap is
        // answered with what the feature is FIRST, never a bare paywall; the
        // sheet owns its paywall (a sheet raised from under a sheet never
        // appears).
        .sheet(isPresented: $showingUpsell) {
            SpeechPlusSheet(isLight: gate.account?.isLightPlan ?? false)
        }
        .confirmationDialog("New script", isPresented: $choosingKind) {
            Button("Write with AI") { composing = true }
            Button("Add my own script") { addingOwn = true }
        }
    }

    private func openPending() {
        guard let script = openAfterSheet else { return }
        openAfterSheet = nil
        practicing = script
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

// MARK: - The whole script

/// The full text with its notes, opened from the prompter's script button —
/// to read it through before a take, or to look something up.
struct SpeechScriptSheet: View {
    /// Called with the script after an edit, so the prompter reads the new
    /// text at once.
    var onEdited: (SpeechScript) -> Void = { _ in }
    @State private var script: SpeechScript
    @State private var editing = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    init(script: SpeechScript, onEdited: @escaping (SpeechScript) -> Void = { _ in }) {
        _script = State(initialValue: script)
        self.onEdited = onEdited
    }

    var body: some View {
        NavigationStack {
            List {
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
                    Section("Sources") {
                        Text(script.sources.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The bundled sample is everyone's and stays as shipped;
                // changing it would make it a script of your own, which is
                // the Plus side of the tab.
                if !script.isBuiltIn {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Edit") { editing = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $editing) {
                SpeechOwnScriptSheet(existing: script) { updated in
                    SpeechStore.shared.add(updated)
                    script = updated
                    onEdited(updated)
                }
                .environmentObject(appState)
            }
        }
    }
}

// MARK: - Takes

/// Every take of one script, newest first, each opening its result.
struct SpeechTakesSheet: View {
    let scriptId: UUID
    @ObservedObject private var store = SpeechStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let takes = store.takes(for: scriptId)
        NavigationStack {
            Group {
                if takes.isEmpty {
                    ContentUnavailableView("No takes yet", systemImage: "record.circle",
                                           description: Text("Your recordings of this script will be here."))
                } else {
                    List {
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
            .navigationTitle("Takes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
                        ForEach(SpeechGenre.writable) { g in
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

// MARK: - Your own script

/// Type or paste a text to practise — a talk you have to give, a pitch, a
/// speech for a wedding. Nothing is generated; the text is saved as given.
struct SpeechOwnScriptSheet: View {
    let existing: SpeechScript?
    var onSave: (SpeechScript) -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @FocusState private var bodyFocused: Bool

    private var language: String { existing?.language ?? LanguageCatalog.base(appState.targetLanguage) }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                        .focused($bodyFocused)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Type or paste the text you want to practise.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    HStack {
                        Text("Script")
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            guard let pasted = strings.first else { return }
                            text = text.isEmpty ? pasted : text + "\n\n" + pasted
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                } footer: {
                    if !trimmed.isEmpty {
                        Text("About \(SpeechFormat.length(max(1, SpeechLibrary.estimatedSeconds(trimmed, language: language)))) to read · leave a blank line between paragraphs.")
                    } else {
                        Text("Write it in \(LanguageCatalog.name(language, in: appState.nativeLanguage)).")
                    }
                }
            }
            .navigationTitle(existing == nil ? Text("My script") : Text("Edit script"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear {
                if let existing {
                    title = existing.title
                    text = existing.body
                } else {
                    bodyFocused = true
                }
            }
        }
    }

    private func save() {
        let givenTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Editing keeps what the script already was — an AI script stays an
        // AI script with its summary and sources; only key terms the new text
        // no longer contains drop out.
        let script = SpeechScript(
            id: existing?.id ?? UUID(),
            title: givenTitle.isEmpty ? Self.defaultTitle(trimmed) : givenTitle,
            genre: existing?.genre ?? .own,
            topic: existing?.topic ?? "",
            body: trimmed,
            summary: existing?.summary ?? "",
            keyTerms: (existing?.keyTerms ?? []).filter { trimmed.localizedCaseInsensitiveContains($0.term) },
            sources: existing?.sources ?? [],
            language: language,
            targetSeconds: SpeechLibrary.estimatedSeconds(trimmed, language: language),
            createdAt: existing?.createdAt ?? Date(),
            isBuiltIn: false
        )
        if existing == nil {
            Analytics.capture("speech_script_added", ["seconds": script.targetSeconds])
        }
        dismiss()
        onSave(script)
    }

    /// The first sentence, cut to a title's length.
    static func defaultTitle(_ text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let enders: Set<Character> = [".", "!", "?", "。", "！", "？"]
        let sentence = firstLine.split(whereSeparator: { enders.contains($0) }).first.map(String.init) ?? firstLine
        let clean = sentence.trimmingCharacters(in: .whitespaces)
        return clean.count > 48 ? String(clean.prefix(46)) + "…" : clean
    }
}

// MARK: - Plus only

/// What a free or Light account sees on "+": the feature, said first, and
/// the way to it. The paywall opens only from here, on purpose.
struct SpeechPlusSheet: View {
    let isLight: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Plus and Max", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text("New scripts are a Plus feature")
                        .font(.title2.weight(.bold))
                    Text("The sample script stays free to practise. With Plus or Max, practise any text you like.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Write with AI").font(.body.weight(.medium))
                            Text("Explainers, products, people, briefings and news — true, and at your level.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                    }
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add your own script").font(.body.weight(.medium))
                            Text("A presentation, a pitch, a speech you have to give.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "pencil.line").foregroundStyle(.tint)
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        showingPaywall = true
                    } label: {
                        Text(isLight ? "Upgrade to Plus" : "See plans")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Not now") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
        .presentationDetents([.height(560), .large])
        .sheet(isPresented: $showingPaywall, onDismiss: {
            // Bought Plus in the paywall: this sheet has nothing left to say.
            Task {
                if await BillingGate.shared.allowsSpeechScripts() { dismiss() }
            }
        }) {
            PaywallView(source: "speech_script", preselectTier: "plus")
        }
        .onAppear { Analytics.capture("speech_plus_sheet", ["light": isLight]) }
    }
}
