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

    private var todaysPeople: [PublicPersonaService.PublicPersona] {
        PublicPersonaService.todaysPeople(from: groupPool, excluding: metIds.union(bookmarks))
    }

    private var searchResults: [PublicPersonaService.PublicPersona] {
        PublicPersonaService.search(searchText, in: groupPool)
    }

    var body: some View {
        NavigationStack {
            List {
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
            }
            .navigationTitle("Find people")
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
                ForEach(todaysPeople) { p in
                    personRow(p)
                }
            }
        } header: {
            Text("People today")
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

    // MARK: - Rows

    private func personRow(_ p: PublicPersonaService.PublicPersona) -> some View {
        NavigationLink(value: PublicPersonaService.asCounterpart(p, existing: appState.counterparts)) {
            HStack(spacing: 12) {
                PersonBubble(name: p.display_name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.display_name).font(.body.weight(.medium))
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

            if let onCompose {
                Section {
                    Button {
                        onCompose(person)
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
                Button {
                    onWatch(savedPerson())
                } label: {
                    Label("Watch", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onTalk(savedPerson())
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
    }

    /// First Talk/Preview is the moment you "meet" them — persist the person
    /// so sessions can link to a stable local id and they join "People you've
    /// met". Idempotent: the local id is derived from the remote one, and the
    /// store dedupes on `remoteId`, so re-tapping can't file a twin.
    private func savedPerson() -> Counterpart {
        if appState.counterparts.contains(where: { $0.id == person.id }) { return person }
        appState.saveCounterpart(person)
        return person
    }
}
