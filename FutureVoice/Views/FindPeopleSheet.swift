import SwiftUI

/// Find people — browse the shared pool of public personas and start a talk
/// with a stranger, like meeting someone new at a language school. Lives
/// behind the Find bubble on Watch's stories row; the stories row itself
/// stays your OWN people. Inside: the people you've already met, your
/// bookmarks, a daily-shuffled handful of new faces, and search.
///
/// Talking to someone has no effect on them whatsoever — no notification,
/// no shared record. Their words here are an AI playing their
/// self-introduction, in a preset voice, never their own.
struct FindPeopleSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Make a new OWN person (voice intake) — the host closes this sheet
    /// first, so the flow is one hop, not a sheet on a sheet.
    let onNew: () -> Void
    /// Start a live call with this (already saved) person.
    let onTalk: (Counterpart) -> Void
    /// Watch a scene of the fluent self and this person just talking.
    let onWatch: (Counterpart) -> Void
    /// Build a specific situation with them (the composer).
    var onCompose: ((Counterpart) -> Void)? = nil

    @State private var pool: [PublicPersonaService.PublicPersona] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var searchText = ""
    @State private var bookmarks: Set<String> = []

    /// Core badges for the pool's owners, keyed by lowercase user id. This
    /// sheet is the only place a learner is ever seen by a stranger, so it's
    /// the only place the seal is real status rather than a receipt.
    @State private var coreBadges: [String: CoreClubService.Badge] = [:]

    /// Which pool the sheet is showing. Two kinds live in one table and they
    /// are not interchangeable to a learner: a real person who published an
    /// intro, and someone we invented. One list would quietly ask the user to
    /// guess which is which.
    @State private var group: PublicPersonaService.Group = .user

    /// The current tab's slice of the pool.
    private var groupPool: [PublicPersonaService.PublicPersona] {
        pool.filter { $0.group == group }
    }

    /// People already met, narrowed to the tab they belong to — each tab
    /// stays a complete little world instead of repeating the same names.
    private var metPeople: [Counterpart] {
        appState.counterparts
            .filter { $0.remoteId != nil && ($0.personaKind ?? "user") == group.rawValue }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var metIds: Set<String> {
        Set(appState.counterparts.compactMap(\.remoteId))
    }

    private var bookmarkedNewFaces: [PublicPersonaService.PublicPersona] {
        groupPool.filter { bookmarks.contains($0.id) && !metIds.contains($0.id) }
    }

    /// Everyone in the pool the learner hasn't met or bookmarked — the WHOLE
    /// list, in the pool's own order. A daily six-person rotation lived here
    /// for a while and was removed (2026-08-31): it hid most of the pool to
    /// manufacture a reason to come back, and the pool is the reason.
    private var strangers: [PublicPersonaService.PublicPersona] {
        let keep = metIds.union(bookmarks)
        return groupPool.filter { !keep.contains($0.id) }
    }

    private var searchResults: [PublicPersonaService.PublicPersona] {
        PublicPersonaService.search(searchText, in: groupPool)
    }

    /// Your OWN people — they live on this page too now: one page for
    /// everyone you can practice with, made or met.
    private var ownPeople: [Counterpart] {
        appState.counterparts.filter { $0.remoteId == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ownSection
                }
                Section {
                    Picker("", selection: $group) {
                        Text("People").tag(PublicPersonaService.Group.user)
                        Text("Characters").tag(PublicPersonaService.Group.character)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                } footer: {
                    Text(groupFooter)
                }

                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    metSection
                    bookmarksSection
                    todaySection
                } else {
                    resultsSection
                }
                coreLegendSection
            }
            .navigationTitle("People")
            .toolbarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text("Name, interests, place…"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Counterpart.self) { person in
                FindPersonCard(person: person,
                               bookmarks: $bookmarks,
                               onTalk: onTalk, onWatch: onWatch,
                               onCompose: onCompose)
                    .environmentObject(appState)
            }
            .task { await loadPool() }
            .onAppear { bookmarks = PublicPersonaService.bookmarkedIds() }
        }
    }

    /// What this tab is, in one line.
    private var groupFooter: String {
        switch group {
        case .user:
            return explain("Other learners who published an introduction. Talking with someone doesn't notify them — it's an AI speaking their introduction, in a stock voice, never theirs.")
        case .character:
            return explain("People we invented to practice with — each one in the middle of something they'll want to talk about.")
        }
    }

    // MARK: - Sections

    /// The half that used to be its own "Your people" sheet — merged here so
    /// the header button answers every "who can I talk to" question at once.
    @ViewBuilder private var ownSection: some View {
        Section("Your people") {
            Button(action: onNew) {
                Label("New person", systemImage: "plus.circle.fill")
                    .font(.body.weight(.medium))
            }
            ForEach(ownPeople) { c in
                NavigationLink {
                    CounterpartDetailView(counterpart: c).environmentObject(appState)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                            Text(Books.initials(c.name))
                                .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).font(.body)
                            Text(c.relationship).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { idx in
                let people = ownPeople
                for i in idx { appState.deleteCounterpart(id: people[i].id) }
            }
        }
    }

    @ViewBuilder private var metSection: some View {
        if !metPeople.isEmpty {
            Section("People you've met") {
                ForEach(metPeople) { c in
                    NavigationLink(value: c) { metRow(c) }
                }
            }
        }
    }

    @ViewBuilder private var bookmarksSection: some View {
        if !bookmarkedNewFaces.isEmpty {
            Section("Bookmarked") {
                ForEach(bookmarkedNewFaces) { p in
                    personRow(p)
                }
            }
        }
    }

    @ViewBuilder private var todaySection: some View {
        Section {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if loadFailed {
                VStack(alignment: .leading, spacing: 8) {
                    Text(explain("Couldn't load people — check your connection."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadPool() } }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } else if groupPool.isEmpty {
                // Loaded fine but this tab's pool for the target language has
                // no one yet — say so instead of a silent blank.
                Text(explain("No one here yet for this language — check back soon."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(strangers) { p in
                    personRow(p)
                }
            }
        } header: {
            // STRANGERS, by name (2026-08-31): that they're strangers is the
            // point — talking to strangers is what the language is for.
            Text("Strangers")
        }
    }

    @ViewBuilder private var resultsSection: some View {
        Section {
            if searchResults.isEmpty {
                Text(explain("No one matches yet — try an interest, a job, or a city."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(searchResults) { p in
                    personRow(p)
                }
            }
        }
    }

    /// What the indigo seal on a row means, and the way into the club.
    ///
    /// This sheet is the only place the seal is shown to someone other than
    /// its owner, and a mark a stranger can't read isn't a badge — it's a
    /// stray glyph. It's a ROW rather than a footer because a footer can't be
    /// tapped, and the answer to "what is that?" should be one tap away, not
    /// four taps away in Me.
    ///
    /// Only drawn when a seal is actually on screen: an explanation of
    /// something nobody in this pool has is an ad. That test is `seated`, not
    /// "we got badge rows back" — a pool of people who have all lapsed has no
    /// seal on it to explain.
    @ViewBuilder private var coreLegendSection: some View {
        if coreBadges.values.contains(where: { $0.seated }) {
            Section {
                NavigationLink {
                    CoreClubView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("The Core")
                            Text(explain("The seal marks the 100 people speaking most days right now. Anyone can earn one."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "seal.fill")
                            .foregroundStyle(Color.coreClub)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func personRow(_ p: PublicPersonaService.PublicPersona) -> some View {
        NavigationLink(value: PublicPersonaService.asCounterpart(p, existing: appState.counterparts)) {
            HStack(spacing: 12) {
                PersonBubble(name: p.display_name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.display_name).font(.body.weight(.medium))
                        if isInCore(ownerId: p.owner_user_id) {
                            CoreSeal()
                        }
                        if bookmarks.contains(p.id) {
                            Image(systemName: "bookmark.fill")
                                .font(.caption2).foregroundStyle(.tint)
                        }
                    }
                    Text(facetLine(occupation: p.occupation, location: p.location))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    // A real learner's intro is whatever they typed into
                    // onboarding, for onboarding's purposes — it is not a
                    // profile, and putting it on a browsable card exposed
                    // things like who lives in their house. Their row shows
                    // the three facets a stranger has any business seeing;
                    // the rest still reaches the model, so the conversation
                    // loses nothing. Characters we wrote ARE their intro.
                    if p.group == .character {
                        Text(p.intro)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else if !p.interests.isEmpty {
                        Text(p.interests)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func metRow(_ c: Counterpart) -> some View {
        HStack(spacing: 12) {
            PersonBubble(name: c.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.name).font(.body.weight(.medium))
                    if isInCore(ownerId: ownerId(forRemote: c.remoteId)) {
                        CoreSeal()
                    }
                    if let rid = c.remoteId, bookmarks.contains(rid) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2).foregroundStyle(.tint)
                    }
                }
                Text(facetLine(occupation: c.commonTopics, location: c.location))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func facetLine(occupation: String, location: String) -> String {
        [occupation, location].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The seal is a statement about today, so a badge row that says otherwise
    /// draws nothing. The server already filters, and this is the second belt:
    /// an older payload that still carries seatless rows must not put a mark
    /// beside a name it no longer describes.
    private func isInCore(ownerId: String?) -> Bool {
        guard let ownerId else { return false }
        return coreBadges[ownerId.lowercased()]?.seated == true
    }

    /// A met person is stored as a `Counterpart` keyed by the PERSONA id, so
    /// their badge has to be found back through the pool row that minted them.
    private func ownerId(forRemote remoteId: String?) -> String? {
        guard let remoteId else { return nil }
        return pool.first { $0.id == remoteId }?.owner_user_id
    }

    private func loadPool() async {
        isLoading = true
        loadFailed = false
        do {
            pool = try await PublicPersonaService.fetchPool(language: appState.targetLanguage)
            // The pool is the only thing that can tell a stranger saved
            // without its `remoteId` apart from a person the user made —
            // heal those rows the moment we have it.
            if PublicPersonaService.healRowsMissingRemoteId(
                pool: pool, counterparts: appState.counterparts) {
                appState.reloadCounterparts()
            }
        } catch {
            loadFailed = pool.isEmpty
        }
        isLoading = false
        // Badges last and unguarded: the sheet is fully usable without them,
        // so a Core outage must never keep anyone from meeting people.
        coreBadges = await CoreClubService.fetchBadges(
            ownerIds: pool.compactMap(\.owner_user_id),
            // The pool being browsed, which is the language whose club these
            // seals belong to.
            language: appState.targetLanguage)
    }
}

// MARK: - Person card

/// One public persona, full screen: their introduction, a bookmark, the talks
/// you've already had with them (each opens the regular talk book — replay,
/// transcript, study material), and the two actions: Talk and Watch.
struct FindPersonCard: View {
    @EnvironmentObject private var appState: AppState

    let person: Counterpart
    @Binding var bookmarks: Set<String>
    let onTalk: (Counterpart) -> Void
    let onWatch: (Counterpart) -> Void
    /// Build a situation with this person (the composer). Every person gets
    /// it: meeting a stranger is a situation on its own, but once you've kept
    /// someone there are specific things to rehearse with them too. Passing
    /// nil hides the row.
    var onCompose: ((Counterpart) -> Void)? = nil

    /// Raised in place of Talk/Watch when the account can't pay for them.
    @State private var showingPaywall = false
    /// The voice this stranger speaks in — the learner's pick, never the
    /// stranger's real voice (there isn't one to have). Starts on the preset
    /// their row carries; changing it saves the person, so the pick sticks
    /// (`asCounterpart` returns the saved row over the pool's).
    @State private var voicePresetId: String = ""

    /// The person with the learner's voice pick applied — every action
    /// (Talk, Watch, compose, save) goes through this, so a voice changed a
    /// second ago is the voice that speaks.
    private var effectivePerson: Counterpart {
        var c = person
        if !voicePresetId.isEmpty { c.voicePresetId = voicePresetId }
        return c
    }

    private var currentVoiceName: String {
        VoicePreset.catalog.first(where: { $0.id == effectivePerson.voicePresetId })?.displayName ?? ""
    }

    private var pastTalks: [Session] {
        SessionStore.shared.load()
            .filter { $0.counterpartId == person.id && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    PersonBubble(name: person.name, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.name).font(.title3.weight(.semibold))
                        if !person.location.isEmpty {
                            Text(person.location).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)

                // Written characters ARE their intro — that paragraph is the
                // reason to talk to them. A real learner's "intro" is their
                // onboarding profile, written for a different purpose and
                // never meant to be browsed, so their card stays at who and
                // where and what they're into. Everything else still goes to
                // the model, so the conversation is no thinner for it.
                if person.personaKind != "user" {
                    Text(person.intro.isEmpty ? person.background : person.intro)
                        .font(.body)
                        .padding(.vertical, 2)
                }
            }

            if !person.commonTopics.isEmpty {
                Section("Topics") {
                    Text(person.commonTopics).font(.subheadline)
                }
            }

            Section {
                NavigationLink {
                    VoicePresetPickerView(selection: $voicePresetId)
                        .environmentObject(appState)
                } label: {
                    HStack {
                        Label("Voice", systemImage: "waveform")
                        Spacer()
                        Text(currentVoiceName).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(explain("Not their real voice — an AI speaks their words in a voice you pick."))
            }

            if let onCompose {
                Section {
                    Button {
                        onCompose(effectivePerson)
                    } label: {
                        Label("Make a situation", systemImage: "square.and.pencil")
                    }
                } footer: {
                    Text(explain("Something specific coming up with them — a talk you're dreading, news you have to break."))
                }
            }

            if !pastTalks.isEmpty {
                Section("Your talks together") {
                    ForEach(pastTalks) { s in
                        NavigationLink {
                            ConversationDetailView(session: s)
                                .environmentObject(appState)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.displayTitle).font(.body).lineLimit(1)
                                Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear { voicePresetId = person.voicePresetId }
        .onChange(of: voicePresetId) { _, picked in
            guard picked != person.voicePresetId else { return }
            appState.saveCounterpart(effectivePerson)
        }
        .navigationTitle("")
        .toolbar {
            if let rid = person.remoteId {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        _ = PublicPersonaService.toggleBookmark(rid)
                        bookmarks = PublicPersonaService.bookmarkedIds()
                    } label: {
                        Image(systemName: bookmarks.contains(rid) ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel("Bookmark")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                // Same weight on both: watching and talking are two ways in,
                // not a main action and a lesser one. A prominent Talk read
                // as "the real button" and made Watch look like a preamble.
                // Both actions spend — Watch writes a scene, Talk opens a
                // call — so both ask first, and the plans come up HERE rather
                // than from the tab behind this card, which couldn't show
                // them while this is on screen.
                Button {
                    BillingGate.start(orShow: $showingPaywall) { onWatch(savedPerson()) }
                } label: {
                    Label("Watch", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    BillingGate.start(orShow: $showingPaywall) { onTalk(savedPerson()) }
                } label: {
                    Label("Talk", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }

    /// First Talk/Preview is the moment you "meet" them — persist the person
    /// so sessions can link to a stable local id and they join "People you've
    /// met". Idempotent: the local id is derived from the remote one, and the
    /// store dedupes on `remoteId`, so re-tapping can't file a twin.
    private func savedPerson() -> Counterpart {
        if appState.counterparts.contains(where: { $0.id == person.id }) { return effectivePerson }
        appState.saveCounterpart(effectivePerson)
        return effectivePerson
    }
}
