import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Writing a script WITH the learner, for the thing they are preparing for
/// (2026-11-14, founder: the worst case is someone writing it in another AI
/// app and pasting it here; the whole journey belongs in the app). A chat:
/// the writer asks what the occasion is, who listens, how long, and the
/// learner's own details, one question at a time, then writes a draft and
/// revises it on request. Material (a posting, a CV, notes) can be attached.
///
/// Built from nawana's parts: the tutor chat's lines (`DialogueLine`), its
/// box (`SpeakOrTypeField` with the controls in its row), `SoftChipStyle`,
/// and Watch's attachment reader, which never copies a file into the app.
@MainActor
final class SpeechWriter: ObservableObject {
    struct Material: Identifiable, Equatable {
        enum Kind: Equatable { case file, image, link }
        let id = UUID()
        let kind: Kind
        let label: String
        var data: Data? = nil
        var mime: String? = nil
        var text: String? = nil

        var symbol: String {
            switch kind {
            case .file: return "doc"
            case .image: return "photo"
            case .link: return "link"
            }
        }
    }

    struct Message: Identifiable {
        let id = UUID()
        let fromLearner: Bool
        var text: String
        var materials: [Material] = []
        var options: [String] = []
        var draft: SpeechScript? = nil
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var thinking = false
    @Published var pending: [Material] = []
    @Published var error: String?

    /// The newest draft, the one "Use this script" saves.
    var latestDraft: SpeechScript? { messages.last { $0.draft != nil }?.draft }

    func send(_ text: String, language: String, native: String, level: CEFRLevel) async {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty || !pending.isEmpty, !thinking else { return }
        messages.append(Message(fromLearner: true, text: said, materials: pending))
        pending = []
        thinking = true
        error = nil
        defer { thinking = false }
        do {
            let reply = try await SpeechWriterEngine.turn(messages: messages, language: language,
                                                         native: native, level: level)
            messages.append(reply)
            Analytics.capture("speech_writer_turn", ["turn": messages.count / 2,
                                                     "draft": reply.draft != nil,
                                                     "materials": messages.flatMap(\.materials).count])
        } catch {
            self.error = explain("The writer couldn't answer. Try again.")
        }
    }
}

enum SpeechWriterEngine {
    private struct Payload: Decodable {
        struct Script: Decodable { let title: String?; let body: String?; let summary: String? }
        let reply: String?
        let options: [String]?
        let script: Script?
    }

    static func turn(messages: [SpeechWriter.Message], language: String, native: String,
                     level: CEFRLevel) async throws -> SpeechWriter.Message {
        let history: [GeminiClient.Message] = messages.map { m in
            if m.fromLearner {
                var content = m.text.isEmpty ? "(material attached)" : m.text
                for link in m.materials where link.kind == .link {
                    content += "\n\nMATERIAL, a page they linked (\(link.label)), as read:\n\(link.text ?? "(could not be read)")"
                }
                let files = m.materials.compactMap { mat -> GeminiClient.Message.InlineFile? in
                    guard mat.kind != .link, let data = mat.data, let mime = mat.mime else { return nil }
                    return .init(mimeType: mime, base64Data: data.base64EncodedString())
                }
                var msg = GeminiClient.Message(role: .user, content: content)
                msg.inlineFiles = files
                return msg
            }
            // The writer's own turns go back as it wrote them, the draft in
            // full, so a revision starts from the current text.
            var content = m.text
            if let d = m.draft { content += "\n\nDRAFT (title: \(d.title)):\n\(d.body)" }
            return GeminiClient.Message(role: .model, content: content)
        }
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system(language: language, native: native, level: level),
            messages: history,
            model: .flash36,
            maxTokens: 4096,
            purpose: "speech-script",
            requestTimeout: 90
        )
        let reply = (payload.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let options = (payload.options ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(4)
        var draft: SpeechScript?
        if let s = payload.script,
           let body = s.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            let title = (s.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            draft = SpeechScript(
                id: UUID(), title: title.isEmpty ? explain("My script") : title, genre: .own,
                topic: messages.first(where: \.fromLearner)?.text ?? "", body: body,
                summary: s.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                keyTerms: [], sources: [],
                language: LanguageCatalog.base(language),
                targetSeconds: SpeechLibrary.estimatedSeconds(body, language: language),
                createdAt: Date(), isBuiltIn: false)
        }
        guard !reply.isEmpty || draft != nil else { throw SpeechScriptEngine.WriteError.empty }
        return SpeechWriter.Message(fromLearner: false, text: reply, options: Array(options), draft: draft)
    }

    static func system(language: String, native: String, level: CEFRLevel) -> String {
        let target = LanguageCatalog.englishName(language)
        let nativeName = LanguageCatalog.englishName(native)
        let perMinute = SpeechLibrary.plannedUnits(seconds: 60, language: language)
        let unitName: String = {
            switch SpeechLibrary.rateUnit(language) {
            case .words: return "words"
            case .syllables: return "Hangul syllables"
            case .characters: return "characters (kana + kanji, punctuation not counted)"
            }
        }()
        let scale = ConversationEngine.speechScale(for: level)
        return """
        You are a speechwriter working WITH a language learner on a script
        they will say out loud at a real occasion that is coming up: a job
        interview answer, a toast, a presentation, a pitch, introducing
        themselves, a talk at work, or anything else. They will practise it
        from a teleprompter in this app until they can say it well. Output
        STRICT JSON only, keys in this order:
        { "reply": "...", "options": ["..."], "script": null }
        or, when you write or revise the script:
        { "reply": "...", "options": ["..."], "script": { "title": "...", "body": "...", "summary": "..." } }

        \(CoachingLanguage.contract(target: language, native: native))

        OUTPUT LANGUAGE, FIELD BY FIELD
        - "reply": \(nativeName). Short: one or two sentences. COACHING.
        - "options": \(nativeName). 0–4 short answers the learner might tap
          in reply to your question, each a few words, in their voice. Empty
          when you asked nothing.
        - "script.title": \(target), ≤ 6 words. MATERIAL.
        - "script.body": \(target). MATERIAL, the words they will say.
        - "script.summary": \(nativeName), one sentence: what the script is for.

        HOW THE CONVERSATION GOES
        - First understand what you need: the occasion, who will listen, how
          long they have, and THEIR OWN details (what happened, names,
          numbers, the story only they know). Ask ONE short question per
          turn, the most important thing still missing, and offer likely
          answers in "options".
        - After at most three questions, or as soon as you know enough, write
          the draft. If they ask you to just write it, write it now.
        - Never invent facts about their life: no made-up employers, names,
          numbers or events. Use only what they told you or attached. If a
          detail is missing, write around it, and say in "reply" what they
          could add.
        - A job interview: the script is their answer to the question that
          matters most (usually "tell me about yourself", or the one they
          name); say in "reply" that you can write the next answer.
        - Attached material (a job posting, a CV, notes, a page) is context:
          use its facts. Its language never changes yours.
        - When they ask for a change, return the WHOLE revised script, with
          everything they didn't ask to change kept as it was, and say in
          one line what changed.
        - With a draft, "reply" says in one line what you wrote and invites a
          change (shorter, more personal, a different opening).

        THE SCRIPT
        - Written in \(target) from the start, the way a native \(target)
          speaker would say it at this occasion. Never a translation.
        - LENGTH: as long as they said they have; if they didn't say, about
          one minute. A minute is about \(perMinute) \(unitName). Count.
        - Spoken, not written: an opening that fits the occasion, the points
          in a clear order, a closing line that lands. Short paragraphs
          separated by a blank line. The register the occasion asks for
          (polite for an interview, warm for a toast).
        - Vocabulary for this speaker (\(level.rawValue.uppercased())):
          \(scale.vocabulary)
        - Sentence shapes: \(scale.structure)
        - PUNCTUATE FOR BREATH: the reader pauses where you put punctuation.
          Prefer sentences a reader can say in one breath.
        - Plain text only: no headings, bullets, markdown, emoji, brackets or
          stage directions. Every word in the body is read aloud.
        """
    }
}

struct SpeechWriterView: View {
    /// Called with the script the learner chose to keep.
    var onUse: (SpeechScript) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var writer = SpeechWriter()
    @State private var draft = ""
    @State private var dictationLocale = ""
    @FocusState private var typing: Bool
    @State private var importingFile = false
    @State private var pickingPhoto = false
    @State private var photoPick: PhotosPickerItem?
    @State private var addingLink = false
    @State private var linkText = ""
    @State private var reading: SpeechScript?

    private var writerName: String { explain("Writer") }

    private var starters: [String] {
        [explain("A job interview"),
         explain("A toast at a wedding"),
         explain("A presentation at work"),
         explain("Introducing myself")]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DialogueLine(speaker: .other, name: writerName) {
                            Text("What are you preparing for? Tell me the occasion, and attach anything that helps, like a job posting or your notes. We'll write it together.")
                        }
                        ForEach(writer.messages) { m in
                            line(m).id(m.id)
                        }
                        if writer.thinking {
                            DialogueLine(speaker: .other, name: writerName) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Writing…").foregroundStyle(.secondary)
                                }
                            }
                            .id("thinking")
                        }
                        if let error = writer.error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: writer.messages.count) { _, _ in
                    if let last = writer.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .top) } }
                }
                .onChange(of: writer.thinking) { _, on in
                    if on { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            .navigationTitle(Text("Write with AI"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BarCloseButton { dismiss() }
                }
            }
            .fadingBottomBar { composer }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: ScenarioAttachmentReader.allowedTypes,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                do {
                    let read = try ScenarioAttachmentReader.read(pickedURL: url)
                    writer.pending.append(.init(kind: .file, label: read.source.label, data: read.data, mime: read.mime))
                } catch {
                    writer.error = error.localizedDescription
                }
            }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoPick, matching: .images)
        .onChange(of: photoPick) { _, item in
            guard let item else { return }
            photoPick = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                   let read = ScenarioAttachmentReader.read(image: image, label: explain("Photo")) {
                    writer.pending.append(.init(kind: .image, label: read.source.label, data: read.data, mime: read.mime))
                }
            }
        }
        .alert("Paste a link", isPresented: $addingLink) {
            TextField("https://…", text: $linkText)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("Add") { addLink() }
            Button("Cancel", role: .cancel) { linkText = "" }
        }
        .sheet(item: $reading) { script in
            SpeechWriterDraftSheet(script: script) { use(script) }
        }
        .onAppear {
            if dictationLocale.isEmpty {
                dictationLocale = SpeakOrTypeField.defaultLocale(appLanguage: appState.nativeLanguage,
                                                                 targetLanguage: appState.targetLanguage)
            }
            Analytics.capture("speech_writer_opened")
        }
    }

    @ViewBuilder
    private func line(_ m: SpeechWriter.Message) -> some View {
        if m.fromLearner {
            DialogueLine(speaker: .user, name: chrome("You")) {
                VStack(alignment: .leading, spacing: 6) {
                    if !m.text.isEmpty { Text(m.text) }
                    ForEach(m.materials) { mat in
                        Label(mat.label, systemImage: mat.symbol)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            DialogueLine(speaker: .other, name: writerName) {
                VStack(alignment: .leading, spacing: 10) {
                    if !m.text.isEmpty { Text(m.text).textSelection(.enabled) }
                    if let d = m.draft { draftCard(d, latest: d.id == writer.latestDraft?.id) }
                }
            } accessory: {
                if m.id == writer.messages.last?.id, !m.options.isEmpty, !writer.thinking {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(m.options, id: \.self) { option in
                            Button(option) { send(option) }
                                .buttonStyle(SoftChipStyle(selected: true))
                        }
                    }
                }
            }
        }
    }

    /// A draft in the chat: its title, how long it runs, its opening, the
    /// whole of it a tap away, and the one button that keeps it.
    private func draftCard(_ d: SpeechScript, latest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { reading = d } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(d.title).font(.headline)
                        Spacer()
                        Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(d.body, language: d.language)))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(d.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    Text("Read it all").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(.plain)
            if latest {
                Button { use(d) } label: {
                    Label("Use this script", systemImage: "checkmark")
                }
                .buttonStyle(SoftChipStyle(selected: true))
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if writer.messages.isEmpty, draft.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(starters, id: \.self) { s in
                            Button(s) { send(s) }
                                .buttonStyle(SoftChipStyle(selected: true))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .padding(.bottom, 10)
            }
            if !writer.pending.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(writer.pending) { mat in
                            HStack(spacing: 6) {
                                Image(systemName: mat.symbol)
                                Text(mat.label).lineLimit(1)
                                Button {
                                    writer.pending.removeAll { $0.id == mat.id }
                                } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel(Text("Remove"))
                            }
                            .font(.footnote)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }
            SpeakOrTypeField(text: $draft,
                             locale: $dictationLocale,
                             placeholder: explain("Answer, or ask for a change…"),
                             showsLocalePicker: true,
                             lineRange: 1...5,
                             externalFocus: $typing,
                             cardBackground: Color.clear,
                             micStyle: .plain,
                             leadingControls: AnyView(attachMenu),
                             trailingControls: AnyView(sendButton))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemBackground)))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: draft.isEmpty)
    }

    /// Watch's "+": a link, a file or a photo.
    private var attachMenu: some View {
        AppMenu {
            Button { addingLink = true } label: { Label("Paste a link", systemImage: "link") }
            Button { importingFile = true } label: { Label("Pick a file", systemImage: "doc") }
            Button { pickingPhoto = true } label: { Label("Photo library", systemImage: "photo.on.rectangle") }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.medium))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(.tertiarySystemFill)))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("Attach material")
        .fixedSize()
    }

    @ViewBuilder private var sendButton: some View {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if (hasText || !writer.pending.isEmpty), !writer.thinking {
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.themeAccent))
                    .foregroundStyle(Color.onAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Send"))
        }
    }

    private func send(_ text: String) {
        draft = ""
        typing = false
        Task {
            await writer.send(text, language: appState.targetLanguage, native: appState.nativeLanguage,
                              level: appState.proficiency)
        }
    }

    private func addLink() {
        let link = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        linkText = ""
        guard !link.isEmpty else { return }
        Task {
            // Read from the phone, like Watch's brief: the model's own
            // fetcher is refused by most sites that matter here.
            let text = await ScenarioLinkReader.text(of: link)
            writer.pending.append(.init(kind: .link, label: link, text: text))
        }
    }

    private func use(_ script: SpeechScript) {
        Analytics.capture("speech_writer_used", ["turns": writer.messages.count / 2])
        reading = nil
        dismiss()
        onUse(script)
    }
}

/// The whole draft, to read before keeping it.
private struct SpeechWriterDraftSheet: View {
    let script: SpeechScript
    var onUse: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(script.title).font(.title2.weight(.semibold))
                    if !script.summary.isEmpty {
                        Text(script.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(script.body)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BarCloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this script") { onUse() }
                }
            }
        }
    }
}
