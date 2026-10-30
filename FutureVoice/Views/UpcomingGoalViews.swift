import PhotosUI
import SwiftUI

/// One upcoming goal as a row: its kind's glyph, the title, where and when,
/// and the countdown at the trailing edge.
struct UpcomingGoalRow: View {
    let goal: UpcomingGoal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: goal.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(goal.kind.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title.isEmpty ? goal.kind.label : goal.title)
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let countdown = goal.countdown() {
                Text(countdown)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(goal.kind.tint)
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if !goal.place.isEmpty { parts.append(goal.place) }
        if let date = goal.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }
}

/// Add or change one upcoming goal.
struct UpcomingGoalEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var goal: UpcomingGoal
    @State private var hasDate: Bool
    @State private var confirmingDelete = false
    @State private var addingLink = false
    @State private var linkText = ""
    @State private var importingFile = false
    @State private var pickingPhoto = false
    @State private var photoPick: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var attachError: String?
    private let isNew: Bool
    /// The sources as opened, so a save knows whether to read them again.
    private let sourcesBefore: [UUID]

    init(goal: UpcomingGoal?, language: String) {
        let g = goal ?? UpcomingGoal(kind: .interview, title: "", language: language)
        _goal = State(initialValue: g)
        _hasDate = State(initialValue: g.date != nil)
        isNew = goal == nil
        sourcesBefore = g.brief?.sources.map(\.id) ?? []
    }

    private var sources: [ScenarioBrief.Source] { goal.brief?.sources ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(explain("What is it?"), selection: $goal.kind) {
                        ForEach(UpcomingGoal.Kind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    TextField(goal.kind.titlePrompt, text: $goal.title, axis: .vertical)
                }
                Section {
                    Toggle(explain("It has a date"), isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker(explain("Date"), selection: dateBinding, in: Calendar.current.startOfDay(for: Date())...,
                                   displayedComponents: .date)
                    }
                    TextField(goal.kind.placePrompt, text: $goal.place)
                }
                Section {
                    TextField(explain("The role, the score you need, who will be there…"),
                              text: $goal.notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Notes")
                } footer: {
                    Text(explain("Your tutor prepares you for this. The more it knows, the closer the practice gets."))
                }
                materialSection
                if !isNew {
                    Section {
                        Button(explain("Delete goal"), role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? chrome("New goal") : chrome("Goal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            // Read from where the file lives: never copied into the app.
            .fileImporter(isPresented: $importingFile,
                          allowedContentTypes: ScenarioAttachmentReader.allowedTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    for url in urls { attach(fileURL: url) }
                case .failure(let error):
                    attachError = error.localizedDescription
                }
            }
            .photosPicker(isPresented: $pickingPhoto, selection: $photoPick, matching: .images)
            .onChange(of: photoPick) { _, item in
                guard let item else { return }
                photoPick = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        attach(image: img)
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { attach(image: $0) }.ignoresSafeArea()
            }
            .alert("Paste a link", isPresented: $addingLink) {
                TextField("https://…", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Add") { attach(link: linkText); linkText = "" }
                Button("Cancel", role: .cancel) { linkText = "" }
            }
            .alert(attachError ?? "", isPresented: Binding(get: { attachError != nil },
                                                           set: { if !$0 { attachError = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog(explain("Delete this goal?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button(explain("Delete"), role: .destructive) {
                    UpcomingGoalStore.shared.delete(goal.id)
                    dismiss()
                }
            }
        }
    }

    /// A date picked once survives the toggle being flipped off and on.
    private var dateBinding: Binding<Date> {
        Binding(get: { goal.date ?? Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date() },
                set: { goal.date = $0 })
    }

    private func save() {
        var g = goal
        g.title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
        g.place = g.place.trimmingCharacters(in: .whitespacesAndNewlines)
        g.notes = g.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        g.date = hasDate ? Calendar.current.startOfDay(for: dateBinding.wrappedValue) : nil
        let changed = (g.brief?.sources.map(\.id) ?? []) != sourcesBefore
        if changed, g.brief != nil {
            // New material: what was found in the old set no longer stands.
            g.brief = ScenarioBrief(sources: g.brief?.sources ?? [])
            if g.brief?.sources.isEmpty == true { g.brief = nil }
        }
        UpcomingGoalStore.shared.save(g)
        if g.brief?.needsReading == true {
            let id = g.id
            Task { await UpcomingGoalStore.shared.readMaterial(id, appState: appState) }
        }
        dismiss()
    }

    // MARK: Material

    private var materialSection: some View {
        Section {
            ForEach(sources) { src in
                HStack(spacing: 10) {
                    Image(systemName: Self.icon(for: src)).foregroundStyle(.tint).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.label(for: src)).lineLimit(1).truncationMode(.middle)
                        if let d = src.detail, !d.isEmpty {
                            Text(d).font(.caption).foregroundStyle(src.readOK ? Color.secondary : Color.red)
                        }
                    }
                }
            }
            .onDelete { idx in
                let gone = idx.map { sources[$0] }
                for s in gone { BriefAttachmentCache.shared.drop(s.id) }
                goal.brief?.sources.remove(atOffsets: idx)
            }
            AppMenu {
                Button { addingLink = true } label: { Label("Paste a link", systemImage: "link") }
                Button { importingFile = true } label: { Label("Pick a file", systemImage: "doc") }
                Button { pickingPhoto = true } label: { Label("Photo library", systemImage: "photo.on.rectangle") }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: { Label("Take a photo", systemImage: "camera") }
                }
            } label: {
                Label(explain("Attach a posting, a CV, the exam's page…"), systemImage: "paperclip")
            }
        } header: {
            Text("Material")
        } footer: {
            Text(explain("Read once when you save. Files stay where they are on your phone."))
        }
    }

    static func icon(for src: ScenarioBrief.Source) -> String {
        switch src.kind {
        case .link: return "link"
        case .file: return "doc.text"
        case .image: return "photo"
        }
    }

    /// A link shows its host and path, never the scheme; a file its name.
    static func label(for src: ScenarioBrief.Source) -> String {
        guard src.kind == .link, let url = URL(string: src.label) else { return src.label }
        return (url.host ?? src.label) + (url.path == "/" ? "" : url.path)
    }

    private func add(_ source: ScenarioBrief.Source) {
        var brief = goal.brief ?? ScenarioBrief()
        brief.sources.append(source)
        goal.brief = brief
    }

    private func attach(fileURL url: URL) {
        do {
            let read = try ScenarioAttachmentReader.read(pickedURL: url)
            BriefAttachmentCache.shared.put(read.data, mime: read.mime, for: read.source.id)
            add(read.source)
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func attach(image: UIImage) {
        let n = sources.filter { $0.kind == .image }.count + 1
        guard let read = ScenarioAttachmentReader.read(image: image, label: explain("Photo \(n)")) else {
            attachError = explain("Couldn't read that photo.")
            return
        }
        BriefAttachmentCache.shared.put(read.data, mime: read.mime, for: read.source.id)
        add(read.source)
    }

    private func attach(link raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host, host.contains(".") else {
            attachError = explain("That doesn't look like a link.")
            return
        }
        guard !sources.contains(where: { $0.kind == .link && $0.label == url.absoluteString }) else { return }
        add(.init(kind: .link, label: url.absoluteString))
    }
}

/// One goal's own page, opened from the tutor's note: the countdown, what
/// the day will most likely ask (tap one to drill it with the tutor), and
/// every day of preparation so far.
struct UpcomingGoalPage: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UpcomingGoalStore.shared
    private let initial: UpcomingGoal
    /// The goal as stored now — reading its material saves it again.
    private var goal: UpcomingGoal { store.goals.first { $0.id == initial.id } ?? initial }

    init(goal: UpcomingGoal) { initial = goal }
    @State private var questions: [GoalPrep.Question]?
    @State private var failed = false
    @State private var reading: TutorReading?
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    UpcomingGoalRow(goal: goal)
                    if !goal.notes.isEmpty {
                        Text(goal.notes).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if goal.brief?.hasSources == true { materialSection }
                Section {
                    if let questions {
                        ForEach(questions) { q in
                            Button { drill(q.text) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(q.text).foregroundStyle(.primary)
                                        if !q.looksFor.isEmpty {
                                            Text(q.looksFor).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "graduationcap.fill")
                                        .foregroundStyle(goal.kind.tint)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else if failed {
                        Button("Try again") { failed = false; Task { await load() } }
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Working out what they'll ask…").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Likely questions")
                } footer: {
                    if questions != nil {
                        Text("Tap one to practice it with your tutor until it comes out clean.")
                    }
                }
                let days = GoalPrep.days(for: goal)
                if !days.isEmpty {
                    Section("Prepared so far") {
                        ForEach(days) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.focus).font(.subheadline.weight(.semibold))
                                Button { open(day, .reading) } label: {
                                    Label(day.reading.title, systemImage: "text.book.closed.fill")
                                }
                                Button { open(day, .speech) } label: {
                                    Label(day.speech.question ?? day.speech.title, systemImage: "music.mic")
                                }
                            }
                            .buttonStyle(.borderless)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(goal.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { editing = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $reading) { r in
                TutorReadingSheet(reading: r).environmentObject(appState)
            }
            .sheet(isPresented: $editing, onDismiss: {
                // Saved or deleted: the page shows a goal that may be gone.
                if !UpcomingGoalStore.shared.goals.contains(where: { $0.id == goal.id && $0.updatedAt == goal.updatedAt }) {
                    dismiss()
                }
            }) {
                UpcomingGoalEditor(goal: goal, language: goal.language).environmentObject(appState)
            }
        }
        .task(id: goal.updatedAt) {
            questions = nil
            if goal.brief?.needsReading == true, !store.materialFailed.contains(goal.id) {
                await store.readMaterial(goal.id, appState: appState)
                // Read and saved: this task runs again for the new goal.
                // Not read: the questions go ahead without it.
                if goal.brief?.needsReading != true { return }
            }
            await load()
        }
    }

    /// What the material is and what the reading found, with Read again.
    private var materialSection: some View {
        let brief = goal.brief ?? ScenarioBrief()
        return Section {
            if store.readingMaterial.contains(goal.id) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading your material…").foregroundStyle(.secondary)
                }
            } else if !brief.summary.isEmpty {
                Text(brief.summary).font(.subheadline)
            }
            ForEach(brief.sources) { src in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UpcomingGoalEditor.label(for: src)).lineLimit(1).truncationMode(.middle)
                        if let d = src.detail, !d.isEmpty {
                            Text(d).font(.caption).foregroundStyle(src.readOK ? Color.secondary : Color.red)
                        }
                    }
                } icon: {
                    Image(systemName: UpcomingGoalEditor.icon(for: src)).foregroundStyle(.tint)
                }
            }
            if store.materialFailed.contains(goal.id) {
                Text("Couldn't read it this time.").font(.footnote).foregroundStyle(.red)
            }
            if !store.readingMaterial.contains(goal.id) {
                Button(brief.readAt == nil ? "Read it" : "Read again") {
                    var g = goal
                    g.brief?.readAt = nil
                    store.save(g)
                    Task { await store.readMaterial(g.id, appState: appState) }
                }
            }
        } header: {
            Text("Material")
        } footer: {
            if let at = brief.readAt {
                Text("Read \(at.formatted(date: .abbreviated, time: .omitted))")
            }
        }
    }

    private func load() async {
        if let cached = GoalPrep.cachedQuestions(for: goal) { questions = cached; return }
        do {
            questions = try await GoalPrep.questions(for: goal, appState: appState)
        } catch {
            failed = true
        }
    }

    private func open(_ day: GoalPrepDay, _ part: GoalPrep.Part) {
        reading = TutorReading(script: day.script(part), goal: goal, part: part)
    }

    /// A tutor-mode call on this one question. The page goes first: the
    /// call is a full-screen cover on the Talk home, which can't rise over
    /// a sheet.
    private func drill(_ question: String) {
        Analytics.capture("upcoming_goal_question_drill", ["kind": goal.kind.rawValue])
        dismiss()
        // Opened from the tutor chat, the chat goes too.
        TutorBot.shared.chatOpen = false
        let call = TutorBot.GoalCall(topic: "\u{201C}\(question)\u{201D} — \(goal.title)",
                                     blurb: goal.drillBlurb)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { TutorBot.shared.goalCall = call }
    }
}
