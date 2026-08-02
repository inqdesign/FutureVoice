import SwiftUI

/// The two-line navigation title used by the conversation surfaces (Talk's
/// call screen, Watch's scene): what you're doing on top, the CEFR level the
/// fluent self is speaking at underneath.
///
/// The header itself never edits the level, and there is deliberately no
/// per-conversation override behind it. The weekly assessment measures the
/// level from real talks and writes it back (`AppState`); Progress reports it
/// as a measurement. A dial here would quietly turn that measurement into a
/// taste setting and leave a hidden per-session value nothing downstream
/// could explain. So the header shows it, and the sheet explains what it
/// changes, how it moves, and — one push away — lets the ONE global setting
/// be changed.
struct LevelHeaderTitle: View {
    let title: String
    let level: CEFRLevel
    /// Which surface's copy the sheet should use — Talk and Watch shape
    /// output differently, and the sheet must not overstate either.
    let surface: LevelInfoSheet.Surface

    @State private var showingInfo = false

    var body: some View {
        Button { showingInfo = true } label: {
            VStack(spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                HStack(spacing: 3) {
                    Text(level.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                    // Chevron only — a label like "what this means" would be
                    // wider than the level it explains.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            // The principal slot is only ~44pt tall; keep the two lines from
            // fighting a long topic for it.
            .frame(maxWidth: 240)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). Level \(level.rawValue.uppercased())")
        .accessibilityHint("Explains what this level changes")
        .sheet(isPresented: $showingInfo) {
            LevelInfoSheet(level: level, surface: surface)
        }
    }
}

/// What the current level changes, how it moves, and a way to set it by hand.
/// The sheet itself writes nothing; the "Change my level" push is the single
/// global setting (`appState.proficiency`), the same one Me edits.
struct LevelInfoSheet: View {
    enum Surface {
        case talk, watch

        var headline: String {
            switch self {
            case .talk:  return "How your future self talks"
            case .watch: return "How this scene is written"
            }
        }

        /// Talk's prompt only asks the model to speak AT the level with the
        /// occasional stretch — there are no length rules, so promising a
        /// per-band shape here would be a lie. Watch DOES have per-band turn
        /// counts and sentence lengths (`ScenarioCurriculumEngine.sceneScale`),
        /// so it can show them.
        var explains: String {
            switch self {
            case .talk:
                return """
                Your future self speaks mostly at your level, and lets a word \
                or turn of phrase from just above it slip in now and then — \
                that small stretch is where you grow. Never two levels up.
                """
            case .watch:
                return """
                Your level sets how long the scene is and how full its \
                sentences are. Vocabulary is picked from just above it — \
                words a learner at your level plausibly doesn't own yet.
                """
            }
        }
    }

    let level: CEFRLevel
    let surface: Surface

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Assessment progress, computed the same way Progress computes it, so the
    /// two screens can never quote different numbers.
    @State private var unlock: WeeklyReportEngine.UnlockState = .ready

    /// The three bands Watch actually branches on, described with the values
    /// the generator really uses.
    private static let watchBands: [(band: String, levels: [CEFRLevel], detail: String)] = [
        ("A1 · A2", [.a1, .a2], "8–10 turns, one short sentence each"),
        ("B1 · B2", [.b1, .b2], "8–12 turns, 1–2 sentences each"),
        ("C1 · C2", [.c1, .c2], "10–14 turns, 1–3 sentences, follow-up questions"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(surface.explains)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(surface.headline)
                }

                if surface == .watch {
                    Section {
                        ForEach(Self.watchBands, id: \.band) { band in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(band.band)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 62, alignment: .leading)
                                Text(band.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if band.levels.contains(level) {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    } header: {
                        Text("By level")
                    }
                }

                Section {
                    unlockRow
                } header: {
                    Text("How your level moves")
                } footer: {
                    Text("Your level is measured from the talks you actually have — it isn't a setting you keep in sync by hand.")
                }

                // Not a dead end. Telling someone whose current conversation
                // is too hard to "go talk more" is a brush-off if the control
                // that would fix it today is three screens away — so this
                // GOES there rather than naming the path.
                Section {
                    NavigationLink {
                        LevelSettingView()
                            .environmentObject(appState)
                    } label: {
                        Label("Change my level", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                    }
                } footer: {
                    Text("The same setting as Me → Level. The next assessment overwrites it with what your talks show.")
                }
            }
            .navigationTitle("Level \(level.rawValue.uppercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear {
                unlock = WeeklyReportEngine.unlockState(
                    endedSessions: SessionStore.shared.load()
                        .filter { $0.endedAt != nil && $0.archivedAt == nil },
                    lastReport: appState.weeklyReports.first
                )
            }
        }
    }

    /// The concrete distance to the next measurement. "Talk more" is a
    /// platitude; "8 more minutes" is a thing someone can do today.
    @ViewBuilder
    private var unlockRow: some View {
        switch unlock {
        case .lockedFirst(let accumulated, let required):
            VStack(alignment: .leading, spacing: 8) {
                Text("Your first assessment unlocks after \(Int(required / 60)) minutes of talk.")
                    .font(.subheadline)
                HStack(spacing: 10) {
                    ProgressView(value: min(accumulated, required), total: required)
                    Text("\(Int(accumulated / 60))/\(Int(required / 60)) min")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case .lockedNext(let days, let secondsRemaining):
            let minutes = max(1, Int((secondsRemaining / 60).rounded(.up)))
            Text(days > 0
                 ? "Next assessment in \(days) day\(days == 1 ? "" : "s")."
                 : "Next assessment after \(minutes) more min of new talk.")
                .font(.subheadline)
        case .ready:
            Label("A new assessment is due — it runs after your next talk.",
                  systemImage: "sparkles")
                .font(.subheadline)
        }
    }
}

/// The level picker, reachable from the info sheet as well as from Me. Both
/// bind the SAME `appState.proficiency` — this is a second door onto one
/// setting, not a second setting. (Which is exactly why the conversation
/// header doesn't get its own dial: a per-talk override would have been a
/// second, hidden value.)
struct LevelSettingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Level", selection: $appState.proficiency) {
                    ForEach(CEFRLevel.allCases, id: \.self) { level in
                        Text(LanguageCatalog.levelLabel(level, target: appState.targetLanguage))
                            .tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Sets how your future self speaks and how scenes are written. Your measured level in Progress is unaffected until the next assessment, which will overwrite this with what your talks show.")
            }
        }
        .navigationTitle("Your level")
        .navigationBarTitleDisplayMode(.inline)
    }
}
