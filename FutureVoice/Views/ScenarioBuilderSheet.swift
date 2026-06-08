import SwiftUI

/// Constructs a single Scenario via two structured pickers (Where + Who) +
/// an optional note. Used by `ScenariosListSheet` to add a new entry to the
/// user's scenario library. Returns the built Scenario via `onSave` —
/// persistence + UI dismiss is handled by the caller.
struct ScenarioBuilderSheet: View {
    let onSave: (Scenario) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var environment: String = ""
    @State private var customEnvironment: String = ""
    @State private var role: String = ""
    @State private var customRole: String = ""
    @State private var notes: String = ""

    private static let environments = [
        "Casual chat",
        "Cafe / restaurant",
        "Office / work meeting",
        "Doctor / clinic",
        "Kita / school",
        "Travel / airport",
        "Shopping / store",
        "Outdoors / park",
        "Phone / online",
        "Party / social"
    ]

    private static let roles = [
        "Friend",
        "Family member",
        "Colleague",
        "Manager / boss",
        "Doctor / nurse",
        "Teacher",
        "Shopkeeper",
        "Stranger",
        "Service agent",
        "Date / romantic",
        "Kid / child",
        "Neighbor"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    chipGrid(items: Self.environments, selection: $environment) {
                        customEnvironment = ""
                    }
                    TextField("Or describe where (custom)…", text: $customEnvironment)
                        .onChange(of: customEnvironment) { _, new in
                            if !new.trimmingCharacters(in: .whitespaces).isEmpty {
                                environment = ""
                            }
                        }
                } header: {
                    Text("Where")
                }

                Section {
                    chipGrid(items: Self.roles, selection: $role) {
                        customRole = ""
                    }
                    TextField("Or describe who (custom)…", text: $customRole)
                        .onChange(of: customRole) { _, new in
                            if !new.trimmingCharacters(in: .whitespaces).isEmpty {
                                role = ""
                            }
                        }
                } header: {
                    Text("Who you're talking to")
                } footer: {
                    Text("The avatar will play this role. You practice your side.")
                }

                Section("Anything specific?") {
                    TextField("Optional — what's the situation about?",
                              text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("New scenario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func chipGrid(items: [String],
                           selection: Binding<String>,
                           onPick: @escaping () -> Void) -> some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selection.wrappedValue == item
                Button {
                    selection.wrappedValue = on ? "" : item
                    onPick()
                } label: {
                    Text(item)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
                        .background(
                            Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var resolvedEnvironment: String {
        let c = customEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? environment : c
    }
    private var resolvedRole: String {
        let c = customRole.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? role : c
    }
    private var canSave: Bool {
        !resolvedEnvironment.isEmpty && !resolvedRole.isEmpty
    }

    private func save() {
        let scenario = Scenario(
            environment: resolvedEnvironment,
            role: resolvedRole,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(scenario)
        dismiss()
    }
}
