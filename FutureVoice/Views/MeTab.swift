import SwiftUI

/// Pure settings — account, persona, level, appearance, voice. All growth /
/// progress signals live in `ProgressTab` now; mixing them in here buried
/// both. Account sits FIRST so plan + credit balance are one tab-tap away
/// instead of hidden under practice stats.
struct MeTab: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @State private var account: AccountStatus = .empty
    @State private var showingPersonaEdit = false
    @State private var confirmingVoiceReset = false
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(icon: "person.crop.circle",
                        title: account.email ?? "Signed in with Apple",
                        subtitle: "Apple ID")
                    HStack {
                        row(icon: "creditcard",
                            title: account.planLabel,
                            subtitle: "Plan")
                        Spacer()
                        Text("\(account.creditBalance) credits")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(account.creditBalance > 0 ? Color.primary : Color.orange)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Credits are spent on voice synthesis and AI calls. They refill with your plan cycle.")
                }

                Section("Profile") {
                    Button {
                        showingPersonaEdit = true
                    } label: {
                        row(icon: "person.text.rectangle",
                            title: appState.persona?.displayName.isEmpty == false
                                ? appState.persona!.displayName
                                : "Edit profile",
                            subtitle: "Persona used in every conversation")
                    }
                }

                Section {
                    Picker(selection: $appState.proficiency) {
                        ForEach(CEFRLevel.allCases, id: \.self) { level in
                            Text(level.rawValue.uppercased()).tag(level)
                        }
                    } label: {
                        row(icon: "chart.bar",
                            title: "Level",
                            subtitle: "Calibrates conversations and feedback")
                    }
                } header: {
                    Text("Learning")
                } footer: {
                    Text("CEFR scale — A1 beginner to C2 near-native. The avatar stays at your level and grades against it.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appState.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Voice") {
                    Button(role: .destructive) {
                        confirmingVoiceReset = true
                    } label: {
                        row(icon: "mic.badge.plus",
                            title: "Re-record voice",
                            subtitle: "Replace your current clone with a new one")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPersonaEdit) {
                PersonaOnboardingView(initialPersona: appState.persona)
                    .environmentObject(appState)
            }
            .alert("Re-record your voice?", isPresented: $confirmingVoiceReset) {
                Button("Cancel", role: .cancel) {}
                Button("Start over", role: .destructive) {
                    appState.resetVoiceClone()   // RootView swaps to onboarding
                }
            } message: {
                Text("Your current clone will be deleted on ElevenLabs after the new one is created.")
            }
            .alert("Sign out?", isPresented: $confirmingSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            } message: {
                Text("Your practice data stays on this device. Your voice clone and credits stay with your account.")
            }
            .task { account = await AccountStatus.fetch() }
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
