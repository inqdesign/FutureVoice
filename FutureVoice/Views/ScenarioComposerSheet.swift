import SwiftUI

/// The ONE scenario creator — used everywhere (Talk's "+", Watch's flows).
///
/// A breadcrumb DRILL-DOWN, like the old situation builder but AI-driven and
/// with a custom-category step in front:
///   • Overview (top): the breadcrumb path + the assembled scenario text
///     (editable) — the "summary window".
///   • Choices (below): the current level as a 2-column grid.
///       level 0 → categories (presets OR your own keyword + icon/emoji)
///       level 1 → broad sub-areas of the category   (AI)
///       level 2 → specific, concrete scenarios       (AI)
///
/// Pick to narrow (Travel › hotel › room isn't ready), tap a breadcrumb to back
/// up, or just type your own. Per host only the primary action changes
/// (Talk vs Watch) and what the caller does with the minted `Scenario`.
struct ScenarioComposerSheet: View {
    var person: Counterpart?
    /// Pre-select a category on open (Watch's "Likely situations" cards jump
    /// straight into it, so its AI ideas load immediately).
    var initialCategory: Category? = nil
    let ctaTitle: String
    let ctaIcon: String
    let onCommit: (Scenario) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// One step in the drill path. `scenario` is the practiceable sentence at
    /// that step (empty for the bare category). `icon` only set on level 0.
    struct Crumb: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let scenario: String
        var icon: String? = nil
    }

    // Drill state
    @State private var path: [Crumb] = []
    @State private var situation = ""
    @State private var options: [SuggestedTopic] = []
    @State private var loadingOptions = false
    @State private var optionsError: String?
    @State private var optionsCache: [String: [SuggestedTopic]] = [:]

    // Custom category creation (keyword title + icon or emoji)
    @State private var addingCustom = false
    @State private var customTitle = ""
    @State private var customIcon = "sparkles"
    @State private var customEmoji = ""
    @State private var customCategories: [Category] = []

    // Optional person attach
    @State private var attachedPersonId: UUID?
    @FocusState private var situationFocused: Bool

    /// True once the user has TYPED their own scenario (vs building via chips).
    /// In custom mode the chip grid hides and the category is DERIVED from the
    /// text, so the two input styles never contradict each other.
    @State private var customMode = false
    /// Set right before WE write `situation` (picking a chip), so its onChange
    /// isn't mistaken for the user typing.
    @State private var programmaticSituation = false
    @State private var categorizing = false
    /// The tidy card summary — a picked chip's short label, or the AI's
    /// paraphrase of typed text. Never the raw prompt.
    @State private var summary = ""

    struct Category: Identifiable, Hashable {
        var id: String { title.lowercased() }
        let title: String
        let icon: String
    }

    static let presets: [Category] = [
        .init(title: "Cafe",     icon: "cup.and.saucer.fill"),
        .init(title: "Travel",   icon: "airplane"),
        .init(title: "Work",     icon: "briefcase.fill"),
        .init(title: "Health",   icon: "cross.case.fill"),
        .init(title: "Shopping", icon: "bag.fill"),
        .init(title: "Social",   icon: "person.2.fill"),
        .init(title: "School",   icon: "graduationcap.fill"),
        .init(title: "Phone",    icon: "phone.fill"),
    ]

    static let iconPalette = [
        "sparkles", "cup.and.saucer.fill", "airplane", "briefcase.fill",
        "cross.case.fill", "bag.fill", "person.2.fill", "graduationcap.fill",
        "phone.fill", "house.fill", "heart.fill", "cart.fill",
        "fork.knife", "car.fill", "building.2.fill", "gift.fill",
        "figure.wave", "dumbbell.fill", "pawprint.fill", "music.mic",
    ]

    /// Category + 2 narrowing picks. Past this the scenario is specific enough.
    private static let maxDepth = 3

    private var allCategories: [Category] { Self.presets + customCategories }
    private var gridColumns: [GridItem] { [GridItem(.adaptive(minimum: 150), spacing: 8)] }
    private var effectiveCustomIcon: String { customEmoji.isEmpty ? customIcon : customEmoji }
    private var canDrillDeeper: Bool { !path.isEmpty && path.count < Self.maxDepth }

    var body: some View {
        NavigationStack {
            Form {
                if let p = person { personHeader(p) }
                overviewSection
                choiceSection
                if person == nil { attachSection }
            }
            .navigationTitle("New scenario")
            .navigationBarTitleDisplayMode(.inline)
            // A vertical TextField in a Form has no built-in way to dismiss the
            // keyboard — add both a swipe-down and an explicit Done button.
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if let initialCategory, path.isEmpty { pickCategory(initialCategory) }
            }
            #if DEBUG
            .onAppear {
                if DebugCapture.composerPreview, path.isEmpty {
                    path = [Crumb(label: "Cafe", scenario: "", icon: "cup.and.saucer.fill")]
                    options = DebugCapture.sampleCategoryIdeas
                }
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { commit() } label: {
                        Label(ctaTitle, systemImage: ctaIcon).labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(situation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { situationFocused = false }
                }
            }
        }
    }

    // MARK: - Overview (breadcrumb + the assembled scenario)

    private var overviewSection: some View {
        Section {
            if !path.isEmpty { breadcrumb }
            TextField("Describe the scenario", text: $situation, axis: .vertical)
                .lineLimit(2...4)
                .focused($situationFocused)
                .onChange(of: situation) { _, _ in
                    // Ignore our own writes (chip picks); a real keystroke means
                    // the user is writing their own — detach the stale category
                    // so the breadcrumb can't contradict the text.
                    if programmaticSituation { programmaticSituation = false; return }
                    if situation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Cleared → back to browsing categories from scratch.
                        customMode = false
                        if !path.isEmpty { withAnimation { path = []; options = [] } }
                        return
                    }
                    customMode = true
                    if !path.isEmpty { withAnimation { path = []; options = [] } }
                }
                .onChange(of: situationFocused) { _, focused in
                    // Done typing → derive the category (existing or new) so the
                    // typed scenario lands in the same structure as a built one.
                    if !focused && customMode && path.isEmpty
                        && !situation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { await deriveCategory() }
                    }
                }
            if categorizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Filing this under a category…").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Your scenario")
        } footer: {
            Text("Build it from a category below, or just type it — then \(ctaTitle) it.")
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(path.enumerated()), id: \.element.id) { i, crumb in
                    if i > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    Button {
                        navigate(to: Array(path.prefix(i + 1)))
                    } label: {
                        HStack(spacing: 5) {
                            if let icon = crumb.icon { glyph(icon, font: .caption2) }
                            Text(crumb.label).font(.subheadline.weight(.medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(i == path.count - 1
                                                   ? Color.accentColor.opacity(0.15)
                                                   : Color(.tertiarySystemFill)))
                        .foregroundStyle(i == path.count - 1 ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - Choices (current drill level)

    @ViewBuilder
    private var choiceSection: some View {
        if customMode {
            // The user is writing their own — no chip grid to contradict it.
            // The derived category shows in the breadcrumb; tap it to switch to
            // browsing that category's ideas instead.
            EmptyView()
        } else if path.isEmpty {
            categoryChoices
        } else if canDrillDeeper || loadingOptions {
            optionChoices
        } else {
            leafHint
        }
    }

    private var categoryChoices: some View {
        Section {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                ForEach(allCategories) { c in
                    choiceCard(title: c.title, icon: c.icon) { pickCategory(c) }
                }
                choiceCard(title: "Custom", icon: "plus") {
                    withAnimation { addingCustom.toggle() }
                }
            }
            if addingCustom { customEditor }
        } header: {
            Text("Pick a category")
        }
    }

    private var optionChoices: some View {
        Section {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                if loadingOptions && options.isEmpty {
                    // Skeleton chips keep the grid the SAME shape while loading,
                    // so nothing jumps and no empty gap opens up.
                    ForEach(0..<6, id: \.self) { _ in skeletonCard }
                } else {
                    ForEach(options) { o in
                        choiceCard(title: o.title, icon: nil) { pickOption(o) }
                    }
                }
            }
            if let e = optionsError {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        } header: {
            HStack {
                Text(path.count == 1 ? "Narrow it down" : "Pick a scenario")
                Spacer()
                Button { Task { await refreshOptions(force: true) } } label: {
                    if loadingOptions {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("More", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon).font(.caption.weight(.semibold))
                    }
                }
                .disabled(loadingOptions)
            }
        } footer: {
            Text(path.count == 1
                 ? "Pick an area to go one step deeper — or type your own above."
                 : "Tap one to fill your scenario above, then edit it freely.")
        }
    }

    private var leafHint: some View {
        Section {
            Label("Specific enough — \(ctaTitle) it, or tap a breadcrumb to explore more.",
                  systemImage: "checkmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func choiceCard(title: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { glyph(icon, font: .subheadline).foregroundStyle(.tint) }
                Text(title)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 10)
            // Fill the row's height so a 1-line chip matches its 2-line sibling
            // (LazyVGrid sizes the row to the tallest cell; this stretches the
            // shorter ones to fill instead of leaving a gap).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var skeletonCard: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemFill).opacity(0.6))
            .frame(height: 42)
            .redacted(reason: .placeholder)
    }

    /// SF Symbol name → Image; a single emoji → Text. Lets custom categories
    /// use any emoji when no symbol fits.
    @ViewBuilder
    private func glyph(_ icon: String, font: Font) -> some View {
        if isEmoji(icon) {
            Text(icon).font(font)
        } else {
            Image(systemName: icon).font(font)
        }
    }

    private func isEmoji(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && scalar.value > 0x203C
    }

    /// Name-your-own-category editor: keyword + a symbol from the palette OR an
    /// emoji you type (so there's always a fitting icon).
    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                glyph(effectiveCustomIcon, font: .title3).foregroundStyle(.tint).frame(width: 30)
                TextField("Category name (e.g. Landlord, Gym)", text: $customTitle)
            }
            HStack(spacing: 10) {
                TextField("😀", text: $customEmoji)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .onChange(of: customEmoji) { _, new in
                        // Keep only the first emoji; typing one picks it as icon.
                        customEmoji = new.first.map(String.init).flatMap { isEmoji($0) ? $0 : nil } ?? ""
                    }
                Divider().frame(height: 24)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Self.iconPalette, id: \.self) { icon in
                            Button { customIcon = icon; customEmoji = "" } label: {
                                Image(systemName: icon)
                                    .font(.body)
                                    .foregroundStyle(customEmoji.isEmpty && customIcon == icon
                                                     ? Color(.systemBackground) : Color.primary)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(customEmoji.isEmpty && customIcon == icon
                                                              ? Color.accentColor : Color(.tertiarySystemFill)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Button { addCustomCategory() } label: {
                Text("Add category").font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(customTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Person

    private func personHeader(_ p: Counterpart) -> some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                    Text(Books.initials(p.name)).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.body.weight(.medium))
                    if !p.relationship.isEmpty {
                        Text(p.relationship).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var attachSection: some View {
        Section {
            if appState.counterparts.isEmpty {
                Text("Add people under Watch to have them play a scene in their own voice.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(appState.counterparts) { c in
                        let on = attachedPersonId == c.id
                        Button {
                            attachedPersonId = on ? nil : c.id
                        } label: {
                            Text(c.name).font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
                                .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("With someone? (optional)")
        }
    }

    // MARK: - Navigation / drill

    private func pickCategory(_ c: Category) {
        navigate(to: [Crumb(label: c.title, scenario: "", icon: c.icon)])
    }

    private func pickOption(_ o: SuggestedTopic) {
        let scenario = o.blurb.isEmpty ? o.title : o.blurb
        summary = o.title   // the chip's short label is the tidy card title
        navigate(to: path + [Crumb(label: o.title, scenario: scenario)])
    }

    /// Move to a new path: update the scenario text from the deepest step, then
    /// (re)load that level's options from cache or the model.
    private func navigate(to newPath: [Crumb]) {
        withAnimation(.easeOut(duration: 0.15)) {
            path = newPath
            addingCustom = false
            customMode = false   // browsing chips, not free-typing
        }
        if let s = newPath.last?.scenario, !s.isEmpty {
            programmaticSituation = true   // this write isn't the user typing
            situation = s
            situationFocused = false
        }
        Task { await refreshOptions() }
    }

    /// Read the free-typed scenario and set the breadcrumb category — an
    /// existing one when it fits, otherwise a freshly-minted custom category.
    private func deriveCategory() async {
        let text = situation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        categorizing = true
        defer { categorizing = false }
        do {
            let r = try await TopicEngine.categorize(
                text: text,
                existing: allCategories.map(\.title),
                iconOptions: Self.iconPalette,
                targetLanguage: appState.targetLanguage)
            // Reuse the existing category with that title if there is one.
            let match = allCategories.first { $0.title.lowercased() == r.category.lowercased() }
            let cat = match ?? Category(title: r.category, icon: r.icon)
            if match == nil { customCategories.append(cat) }
            summary = r.summary
            // Show the derived category as the breadcrumb; stay in custom mode
            // (their text is the scenario — no chip grid needed).
            withAnimation(.easeOut(duration: 0.15)) {
                path = [Crumb(label: cat.title, scenario: "", icon: cat.icon)]
            }
        } catch {
            // Categorizing is a nicety — a failure just leaves the free text as
            // the scenario with no breadcrumb. Never blocks committing.
        }
    }

    private func addCustomCategory() {
        let title = customTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let c = Category(title: title, icon: effectiveCustomIcon)
        if !allCategories.contains(c) { customCategories.append(c) }
        customTitle = ""; customIcon = "sparkles"; customEmoji = ""
        pickCategory(c)
    }

    private func refreshOptions(force: Bool = false) async {
        guard canDrillDeeper else { options = []; return }
        let labels = path.map(\.label)
        let key = labels.joined(separator: "›")
        if !force, let cached = optionsCache[key] { options = cached; return }
        loadingOptions = true
        optionsError = nil
        options = []            // → skeleton
        defer { loadingOptions = false }
        do {
            let result = try await TopicEngine.suggestForPath(
                path: labels, persona: appState.persona, counterpart: person,
                targetLanguage: appState.targetLanguage)
            optionsCache[key] = result
            // Guard against a stale response (user navigated during the await).
            if path.map(\.label) == labels { options = result }
        } catch {
            optionsError = "Couldn't fetch ideas — type your own, or tap More to retry."
        }
    }

    private func commit() {
        let text = situation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            var categoryName = path.first?.label
            var icon = path.first?.icon
            var sum = summary
            // Typed but never categorized (they hit the CTA before blur) → tidy
            // it up now so the card shows a clean category + summary, not the
            // raw prompt.
            if categoryName == nil || sum.isEmpty {
                if let r = try? await TopicEngine.categorize(
                    text: text, existing: allCategories.map(\.title),
                    iconOptions: Self.iconPalette, targetLanguage: appState.targetLanguage) {
                    categoryName = categoryName ?? r.category
                    icon = icon ?? r.icon
                    if sum.isEmpty { sum = r.summary }
                }
            }
            let who = person ?? attachedPersonId.flatMap { id in
                appState.counterparts.first { $0.id == id }
            }
            var s = Scenario(
                environment: text,
                role: who.map { $0.relationship.isEmpty ? $0.name : $0.relationship } ?? "",
                notes: ""
            )
            s.counterpartId = who?.id
            s.category = categoryName
            s.categoryIcon = icon
            s.summary = sum.isEmpty ? nil : sum
            onCommit(s)
            dismiss()
        }
    }
}
