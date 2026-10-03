import SwiftUI

/// After the first call: "how was it?" — and the three things that change how
/// the next one feels, on one page (2026-10-03, founder request). A beginner
/// who found the call too hard had no way to know that the level they picked
/// in setup, the voice's speed and coach mode are what to move, or where each
/// of them lives (Me → level, Me → Voice, the call's own settings). So the
/// answer to "how was it?" pre-sets them — Hard: a level down, the slow voice,
/// coach on; Easy: a level up, coach off — and the learner changes anything
/// before saving. Nothing is applied until Save.
///
/// Raised ONCE, after the summary of the learner's first call (one they spoke
/// in), before the plans pitch — `ConversationView`'s summary `onDismiss`.
/// Captures: `-capture first-call-check[-hard]`.
struct FirstCallCheckSheet: View {
    static let shownKey = "futurevoice.firstCallCheck.shown"

    /// The first finished talk the learner spoke in, and never asked before.
    /// Installs with a talk history already don't see it: "your first call"
    /// would be untrue for them.
    static func shouldShow(learnerSpoke: Bool) -> Bool {
        guard learnerSpoke, !UserDefaults.standard.bool(forKey: shownKey) else { return false }
        let spokenTalks = SessionStore.shared.loadAcrossLanguages().filter {
            $0.endedAt != nil && $0.turns.contains { $0.role == .user }
        }
        return spokenTalks.count <= 1
    }

    static func markShown() { UserDefaults.standard.set(true, forKey: shownKey) }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum Feeling: CaseIterable { case easy, right, hard }

    @State var feeling: Feeling? = nil
    @State private var level: CEFRLevel = .b1
    @State private var speed: SpeechSpeed = .default
    @State private var coach = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How was your first call?")
                            .font(.title2.weight(.bold))
                        Text(explain("You picked \(LanguageCatalog.levelLabel(appState.proficiency, target: appState.targetLanguage))."))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(SetupFlowView.levelBlurb(appState.proficiency))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
                }

                Section {
                    HStack(spacing: 8) {
                        feelingButton(.easy, "Easy")
                        feelingButton(.right, "Just right")
                        feelingButton(.hard, "Hard")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                } footer: {
                    if let line = suggestionLine {
                        Text(line)
                    }
                }

                Section {
                    Picker(selection: $level) {
                        ForEach(CEFRLevel.allCases, id: \.self) { lvl in
                            Text(LanguageCatalog.levelLabel(lvl, target: appState.targetLanguage)).tag(lvl)
                        }
                    } label: {
                        Label("Your level", systemImage: "chart.bar")
                    }
                } footer: {
                    // A pick above can move this off the level named at the
                    // top; say the move out loud, or the page reads as
                    // contradicting itself ("you picked A2" over "A1").
                    VStack(alignment: .leading, spacing: 2) {
                        if level != appState.proficiency {
                            Text(verbatim: "\(LanguageCatalog.levelLabel(appState.proficiency, target: appState.targetLanguage)) → \(LanguageCatalog.levelLabel(level, target: appState.targetLanguage))")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                        Text(SetupFlowView.levelBlurb(level))
                    }
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
                } footer: {
                    Text(explain("How fast your future self talks, from the next call."))
                }

                Section {
                    Toggle(isOn: $coach) {
                        Label("Coach mode", systemImage: "lightbulb")
                    }
                } footer: {
                    Text(explain("While you think, a sentence you could say appears above the mic — swap the faded part for your own words. Calls with coach mode are practice, so they don't count toward your level."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Save").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
            }
        }
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func feelingButton(_ f: Feeling, _ title: LocalizedStringKey) -> some View {
        // Words only: a hare and a tortoise read as the voice's SPEED, which
        // is a different control on this same page (founder, 2026-10-03).
        let label = Text(title)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
        // The picked one is FILLED — the system's own "selected" — rather
        // than outlined: a drawn ring never matched the button's shape.
        if feeling == f {
            Button { pick(f) } label: { label.foregroundStyle(.white) }
                .buttonStyle(.borderedProminent)
        } else {
            Button { pick(f) } label: { label }
                .buttonStyle(.bordered)
                .tint(.secondary)
        }
    }

    /// What the pick changed below, in one line — so the moved controls are
    /// explained, not discovered.
    private var suggestionLine: String? {
        switch feeling {
        case .hard: return explain("Set below: an easier level, a slower voice and coach mode. Change anything before you save.")
        case .easy: return explain("Set below: a harder level and coach mode off. Change anything before you save.")
        case .right: return explain("Great — keep it as it is, or adjust below.")
        case nil: return nil
        }
    }

    private func pick(_ f: Feeling) {
        feeling = f
        let current = appState.proficiency
        let all = CEFRLevel.allCases
        let i = all.firstIndex(of: current) ?? 0
        withAnimation(.easeInOut(duration: 0.2)) {
            switch f {
            case .hard:
                level = all[max(0, i - 1)]
                speed = .slower
                coach = true
            case .easy:
                level = all[min(all.count - 1, i + 1)]
                speed = currentSpeed
                coach = false
            case .right:
                level = current
                speed = currentSpeed
                coach = currentCoach
            }
        }
    }

    private var currentSpeed: SpeechSpeed {
        SpeechSpeed(rawValue: UserDefaults.standard.string(forKey: SpeechSpeed.key) ?? "") ?? .default
    }

    private var currentCoach: Bool {
        CoachMode.resolve(choice: UserDefaults.standard.object(forKey: CoachMode.key) as? Bool,
                          levelRaw: appState.proficiency.rawValue)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        level = appState.proficiency
        speed = currentSpeed
        coach = currentCoach
        if let f = feeling { pick(f) }
    }

    private func save() {
        if level != appState.proficiency { appState.setLevel(level, for: appState.targetLanguage) }
        UserDefaults.standard.set(speed.rawValue, forKey: SpeechSpeed.key)
        // Always written: the learner saw the switch and confirmed it, and an
        // unset choice would follow the NEW level's default instead.
        UserDefaults.standard.set(coach, forKey: CoachMode.key)
        Telemetry.log("first_call_check", [
            "feeling": feeling.map { "\($0)" } ?? "none",
            "level": level.rawValue, "speed": speed.rawValue, "coach": coach ? "on" : "off",
        ])
        dismiss()
    }
}
