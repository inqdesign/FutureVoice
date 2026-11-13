import SwiftUI

/// Plan, account, legal. Opened from the Speech tab's leading button.
struct SpeechSettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingDelete = false
    @State private var deleteError: String?
    @ObservedObject private var gate = BillingGate.shared
    /// Season 2's scoring before it opens, for admin accounts (as in
    /// nawana's Me → Lab). Takes scored this way stay off every board.
    @AppStorage(SpeechScoreV4.defaultsKey) private var speechScoring4 = false

    /// Admin accounts, and every development build (nawana's Me → Lab rule).
    private var showsLab: Bool {
        #if DEBUG
        return true
        #else
        return gate.account?.unlimited == true
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                if let account = gate.account {
                    Section {
                        LabeledContent("Plan", value: account.planLabel)
                        if account.isEntitled && !account.unlimited {
                            Link("Manage subscription", destination: AccountStatus.manageSubscriptionsURL)
                        }
                    } footer: {
                        if account.isEntitled || account.unlimited {
                            Text("The same plan works in nawana and here.")
                        } else {
                            Text("Subscribed on nawana? Sign in with the account you use there.")
                        }
                    }
                }

                Section("Account") {
                    if let email = auth.session?.user.email {
                        LabeledContent("Signed in as", value: email)
                    }
                    Button("Sign out") {
                        Task { await auth.signOut(); dismiss() }
                    }
                    Button("Delete account", role: .destructive) { confirmingDelete = true }
                }

                if showsLab {
                    Section {
                        Toggle(isOn: $speechScoring4) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(explain("Season 2 scoring"))
                                Text(explain("English speech takes are scored the new way and stay off the boards"))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Lab")
                    }
                }

                Section {
                    Link("Privacy policy", destination: URL(string: "https://nawana.app/privacy.html")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete your account? This is your nawana account too: your voice, talks, scores and subscription record are deleted on both apps, and it can't be undone.",
                isPresented: $confirmingDelete, titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task {
                        do { try await auth.deleteAccount(); dismiss() }
                        catch { deleteError = error.localizedDescription }
                    }
                }
            }
            .alert("Couldn't delete the account", isPresented: Binding(
                get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: { Text(deleteError ?? "") }
        }
        .onAppear {
            BillingGate.shared.warm()
        }
    }
}
