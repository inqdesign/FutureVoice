import SwiftUI

/// The ONE settings page for Talk's chip row — whichever chip is showing, the
/// same button opens it (founder, 2026-10-11: "one setting for all the
/// tabs"). Three things decide what the row offers, so all three live here:
///
/// - **Why you're learning** — which chips there are, and in what order
///   (`LearningPurposeStore.chips`). The same rows setup asked.
/// - **Exam** — which exam's topics the Exam chip deals. Only while an exam
///   is among the purposes.
/// - **Interests** — what the News chip searches for. Typed ones are chips
///   like the presets, so they can be seen and taken off; until this page a
///   typed interest ("Tesla") was saved but never drawn, and past six the
///   server dropped it without a word, so it looked like typing did nothing.
///
/// Nothing is written until Save.
struct DiscoverSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var purposes: [LearningPurpose] = []
    @State private var exam: ExamKind = .ielts
    @State private var details = PurposeDetails()
    @State private var interests: [String] = []
    @State private var draft = ""
    @State private var loaded = false

    /// The news pool reads at most this many (`news-topics` MAX_CATEGORIES).
    static let maxInterests = 6

    private static let presets = [
        "AI / tech", "parenting", "language learning", "music", "podcasts",
        "cooking", "travel", "sports", "fashion", "finance", "science", "art"
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    PurposePickerRows(purposes: $purposes, details: $details, exam: $exam,
                                      language: appState.targetLanguage)
                } header: {
                    Text(explain("Why are you learning?"))
                } footer: {
                    Text(explain("Up to three. The chips under Talk follow them in the order you picked, and what you write under one shapes its topics."))
                }

                Section {
                    interestGrid
                        .id("interestGrid")
                    HStack {
                        TextField(explain("A company, a team, a person — anything"), text: $draft)
                            .onSubmit(addDraft)
                            .submitLabel(.done)
                        Button(action: addDraft) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(!canAdd || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add")
                    }
                .id("interests")
                } header: {
                    HStack {
                        Text(explain("Interests"))
                        Spacer()
                        Text(verbatim: "\(interests.count) / \(Self.maxInterests)")
                    }
                } footer: {
                    Text(explain("The News chip brings this week's stories for each one."))
                }
            }
            .navigationTitle(explain("Talk settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                purposes = LearningPurposeStore.purposes
                exam = LearningPurposeStore.exam(for: appState.targetLanguage)
                details = LearningPurposeStore.details
                interests = Array((appState.persona?.interests ?? []).prefix(Self.maxInterests))
                loaded = true
                #if DEBUG
                if let seeded = UserDefaults.standard.stringArray(forKey: "seedInterests") { interests = seeded }
                if UserDefaults.standard.bool(forKey: "discoverSettingsScroll") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { proxy.scrollTo("interestGrid", anchor: .center) }
                }
                #endif
            }
            }
        }
    }

    private var canAdd: Bool { interests.count < Self.maxInterests }

    /// Picked ones first (presets and typed alike, each with its ×), then the
    /// presets not picked yet.
    private var interestGrid: some View {
        let unpicked = Self.presets.filter { !interests.contains($0) }
        // A flow, not a grid: a typed interest is as long as its name, and a
        // fixed column cut "FC Bayern" to "FC Baye…".
        return ChipFlow(spacing: 8) {
            ForEach(interests, id: \.self) { tag in
                Button { interests.removeAll { $0 == tag } } label: {
                    HStack(spacing: 4) {
                        Text(PersonaOnboardingView.presetLabel(tag)).lineLimit(1)
                        Image(systemName: "xmark").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(Color(.systemBackground))
                    .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(explain("Remove \(PersonaOnboardingView.presetLabel(tag))")))
            }
            ForEach(unpicked, id: \.self) { tag in
                Button { if canAdd { interests.append(tag) } } label: {
                    Text(PersonaOnboardingView.presetLabel(tag))
                        .lineLimit(1)
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(canAdd ? Color.primary : Color.secondary)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
        }
        .padding(.vertical, 4)
    }

    private func addDraft() {
        for piece in draft.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where !piece.isEmpty && canAdd
            && !interests.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) {
            interests.append(piece)
        }
        draft = ""
    }

    private func save() {
        addDraft()
        LearningPurposeStore.purposes = purposes
        LearningPurposeStore.setExam(exam, for: appState.targetLanguage)
        LearningPurposeStore.details = details
        if interests != (appState.persona?.interests ?? []) {
            var p = appState.persona ?? .empty
            p.interests = interests
            appState.savePersona(p)
        }
        dismiss()
    }
}

/// "Why are you learning?" — many answers, numbered in the order tapped.
/// Setup asks it and Talk's settings change it; one set of rows for both.
///
/// An ACCORDION: picking a purpose that has more to say opens it right
/// under its row — which exam, the role applied for, the job and the role
/// in it, the school and the subject. All optional; what is written is what
/// that chip's topics are made from (`PurposeTopicEngine`).
struct PurposePickerRows: View {
    /// At most three (founder, 2026-10-11): each purpose adds a chip to Talk,
    /// and past three the row stops being a choice and becomes a list.
    static let maxPicked = 3

    @Binding var purposes: [LearningPurpose]
    @Binding var details: PurposeDetails
    @Binding var exam: ExamKind
    let language: String

    var body: some View {
        ForEach(LearningPurpose.allCases) { p in
            let n = purposes.firstIndex(of: p)
            let full = n == nil && purposes.count >= Self.maxPicked
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if let n { purposes.remove(at: n) } else if !full { purposes.append(p) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: p.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.tint))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).foregroundStyle(.primary)
                        Text(p.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ZStack {
                        if let n {
                            Circle().fill(Color.accentColor)
                            Text(verbatim: "\(n + 1)")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(Color(.tertiaryLabel), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(full)
            .opacity(full ? 0.4 : 1)
            .accessibilityValue(n.map { Text(verbatim: "\($0 + 1)") } ?? Text(""))
            if n != nil { detail(for: p) }
        }
    }

    @ViewBuilder
    private func detail(for p: LearningPurpose) -> some View {
        switch p {
        case .exam:
            Picker(explain("Which exam?"), selection: $exam) {
                ForEach(ExamKind.options(for: language)) { Text($0.name).tag($0) }
            }
            .padding(.leading, 42)
            .onAppear {
                let options = ExamKind.options(for: language)
                if !options.contains(exam) { exam = options[0] }
            }
        case .study:
            field(explain("School or university"), $details.school)
            field(explain("Subject — e.g. mechanical engineering"), $details.subject)
        case .job:
            field(explain("Role you're applying for — e.g. backend developer"), $details.target)
        case .work:
            field(explain("Your job — e.g. product manager"), $details.job)
            field(explain("What you do in it — e.g. I run the mobile team"), $details.role)
        default:
            EmptyView()
        }
    }

    private func field(_ prompt: String, _ text: Binding<String>) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .font(.subheadline)
            .padding(.leading, 42)
    }
}

/// Chips laid out left to right, wrapping at the edge — each as wide as its
/// own label.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
