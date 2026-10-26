import SwiftUI

/// Before the first call: the few settings that decide how a call feels, set
/// BEFORE the fluent self says a word (2026-10-24, founder request). The
/// after-call check (`FirstCallCheckSheet`) asks "how was it?" once the
/// learner has already struggled through a call at whatever the defaults
/// were; this is the same page in front of the call, so a beginner can slow
/// the voice and turn coach mode on before they need it.
///
/// Raised ONCE, from `ConversationView.openConversation` — the one door every
/// fresh call goes through — and only on an install with no spoken talk on
/// file. Tutor mode too, since it decides how the call OPENS (a lesson
/// instead of a hello). The call waits on it like it waits on the mic sheet; Start, Skip and
/// every other dismissal resume it. Everything is written on Start; Skip
/// keeps what was there. Capture: `-capture first-call-setup`.
struct FirstCallSetupSheet: View {
    static let shownKey = "futurevoice.firstCallSetup.shown"

    /// No talk the learner spoke in yet, and never asked before. An install
    /// with a history has already found these settings by living with them.
    static func shouldShow() -> Bool {
        #if DEBUG
        // `-firstCallSetupForce 1`: on the real call screen, on a simulator
        // that already has talks.
        if UserDefaults.standard.bool(forKey: "firstCallSetupForce") { return true }
        #endif
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return false }
        return !SessionStore.shared.loadAcrossLanguages().contains {
            $0.turns.contains { $0.role == .user }
        }
    }

    static func markShown() { UserDefaults.standard.set(true, forKey: shownKey) }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var level: CEFRLevel = .b1
    @State private var speed: SpeechSpeed = .default
    @State private var coach = false
    @State private var sendToAnswer = false
    @State private var tutor = false
    @State private var loaded = false
    @State private var started = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Before your first call")
                            .font(.title2.weight(.bold))
                        Text("You can change these any time during a call.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
                }

                Section {
                    Picker(selection: $level) {
                        ForEach(CEFRLevel.allCases, id: \.self) { lvl in
                            Text(LanguageCatalog.levelLabel(lvl, target: appState.targetLanguage)).tag(lvl)
                        }
                    } label: {
                        Label("Your level", systemImage: "chart.bar")
                    }
                    // Coach mode and Send follow the level until the learner
                    // flips them (`CoachMode.resolve`), so moving the level
                    // here moves them with it, as it would anywhere else.
                    // Back on the stored level = what is stored, so loading
                    // the sheet never overwrites a choice already made.
                    .onChange(of: level) { _, new in
                        if new == appState.proficiency {
                            coach = CoachMode.isOn
                            sendToAnswer = SendToAnswer.isOn
                        } else {
                            coach = CoachMode.resolve(choice: nil, levelRaw: new.rawValue)
                            sendToAnswer = SendToAnswer.resolve(choice: nil, levelRaw: new.rawValue)
                        }
                    }
                } footer: {
                    Text(SetupFlowView.levelBlurb(level))
                }

                Section {
                    Picker(selection: $speed) {
                        ForEach(SpeechSpeed.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    } label: {
                        Label("Speaking speed", systemImage: "speedometer")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Speaking speed")
                }

                Section {
                    Toggle(isOn: $coach) {
                        Label("Coach mode", systemImage: "lightbulb")
                    }
                } footer: {
                    Text(explain("After each thing your future self says, you see a way to answer. Sometimes it uses a word you're studying, and your most common mistake becomes the call's focus."))
                }

                Section {
                    Toggle(isOn: $sendToAnswer) {
                        Label("Answer with Send", systemImage: "paperplane")
                    }
                } footer: {
                    Text(explain("Take your time. Your future self waits until you press Send."))
                }

                // Same switch and words as the call's own settings.
                if TutorMode.isAvailable {
                    Section {
                        Toggle(isOn: $tutor) {
                            Label("Tutor mode", systemImage: "graduationcap")
                        }
                    } footer: {
                        Text(explain("Pick a topic and your future self teaches it step by step, until you can say it without a mistake."))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Text("Start the call").font(.headline).frame(maxWidth: .infinity)
                }
                .accentProminent()
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
            }
        }
        .onAppear {
            load()
            report("first_call_setup_shown")
        }
        .onDisappear {
            if !started { report("first_call_setup_skipped") }
        }
    }

    private func report(_ event: String, _ extra: [String: String] = [:]) {
        var props = ["level_before": appState.proficiency.rawValue]
        props.merge(extra) { _, new in new }
        Telemetry.log(event, props)
        Analytics.capture(event, props)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        level = appState.proficiency
        speed = SpeechSpeed(rawValue: UserDefaults.standard.string(forKey: SpeechSpeed.key) ?? "") ?? .default
        coach = CoachMode.isOn
        sendToAnswer = SendToAnswer.isOn
        tutor = TutorMode.isOn
    }

    private func start() {
        if level != appState.proficiency { appState.setLevel(level, for: appState.targetLanguage) }
        UserDefaults.standard.set(speed.rawValue, forKey: SpeechSpeed.key)
        // Written even when unchanged: the learner saw the switch and chose,
        // and an unset choice would follow a later level change instead.
        UserDefaults.standard.set(coach, forKey: CoachMode.key)
        UserDefaults.standard.set(sendToAnswer, forKey: SendToAnswer.key)
        if TutorMode.isAvailable { UserDefaults.standard.set(tutor, forKey: TutorMode.key) }
        started = true
        report("first_call_setup", [
            "level": level.rawValue, "speed": speed.rawValue,
            "coach": coach ? "on" : "off", "send": sendToAnswer ? "on" : "off",
            "tutor": tutor ? "on" : "off",
        ])
        dismiss()
    }
}
