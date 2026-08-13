import SwiftUI

// Shared building blocks for the guided "tell me about…" intake flows —
// persona onboarding (`PersonaIntakeView`) and new-People
// (`CounterpartVoiceIntakeView`). Each flow walks fixed categories one card
// at a time; every category uses whichever input fits it best: plain text
// fields for short facts, chips for enumerable choices, speak-first (with a
// typing fallback) for narrative answers.

// MARK: - Step header

/// The big friendly question at the top of every intake card.
struct IntakeStepHeader: View {
    var question: String
    var detail: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.title2.bold())
            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Hints card

/// "Worth mentioning" bullet card — tells the user what kind of detail makes
/// a good answer, without demanding any of it.
struct IntakeHints: View {
    var title: String = "Worth mentioning"
    var bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(bullets, id: \.self) { b in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 7)
                    Text(b)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Chips

/// One capsule chip; selection styling shared by every intake chip grid.
struct IntakeChipLabel: View {
    var text: String
    var isOn: Bool

    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary)
            .background(Capsule().fill(isOn ? Color.accentColor : Color(.tertiarySystemFill)))
    }
}

/// Multi-select chip grid with an optional "add your own" free-text row.
/// Custom entries the user already picked show up as chips too.
struct ChipPickerField: View {
    var presets: [String]
    @Binding var selection: [String]
    var allowsCustom: Bool = true
    var addPrompt: String = "Add your own (comma-separated)"

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let all = presets + selection.filter { !presets.contains($0) }
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(all, id: \.self) { tag in
                    Button {
                        toggle(tag)
                    } label: {
                        IntakeChipLabel(text: tag, isOn: selection.contains(tag))
                    }
                    .buttonStyle(.plain)
                }
            }
            if allowsCustom {
                TextField(addPrompt, text: $draft)
                    .submitLabel(.done)
                    .onSubmit(mergeDraft)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onDisappear(perform: mergeDraft)   // fold unsubmitted text on Next
    }

    private func toggle(_ value: String) {
        if let idx = selection.firstIndex(of: value) {
            selection.remove(at: idx)
        } else {
            selection.append(value)
        }
    }

    private func mergeDraft() {
        let pieces = draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for p in pieces where !selection.contains(p) { selection.append(p) }
        draft = ""
    }
}

// MARK: - Speak or type

/// ONE input field for a free-form answer — no modes, no swapping cards. The
/// user can type at any time, or tap the mic in the field's corner and talk;
/// dictation streams live into the same field. State changes touch only the
/// mic button's color/icon and the caption text, never the geometry, so
/// nothing jumps when recording starts or stops.
struct SpeakOrTypeField: View {
    @EnvironmentObject private var appState: AppState
    @Binding var text: String
    @Binding var locale: String

    /// Every language the device can dictate in, with the learner's own and
    /// the one they're practising lifted to the top.
    ///
    /// This was a two-way toggle between exactly those two, which is a pair
    /// the app invented: someone Japanese living in Germany and learning
    /// English may find it easiest to say the situation in German, and being
    /// told to pick one of two is just a wall. The device knows what it can
    /// hear; the list is that, ordered so the likely picks are first.
    /// What dictation opens on: the app language (Me → App language — the
    /// one the learner reads and thinks in), falling back to a language the
    /// device can actually hear. Hosts used to seed their own `@State
    /// locale = "ko"`, so every screen but one started in Korean no matter
    /// who was holding the phone.
    static func defaultLocale(appLanguage: String, targetLanguage: String) -> String {
        for code in [appLanguage, targetLanguage]
        where LanguageCatalog.canDictate(code) { return code }
        return LanguageCatalog.dictatableLanguages().first ?? "en"
    }

    private var dictationChoices: [String] {
        let all = LanguageCatalog.dictatableLanguages()
        var preferred: [String] = []
        for code in [appState.nativeLanguage, appState.targetLanguage]
        where !preferred.contains(code) && all.contains(code) {
            preferred.append(code)
        }
        return preferred + all.filter { !preferred.contains($0) }
    }

    /// Flips true once any dictation lands in `text` — callers use it to
    /// decide whether the answer needs an LLM cleanup pass on finish.
    var usedVoice: Binding<Bool>? = nil
    var placeholder: String = "Type here — or tap the mic and just talk. I'll sort it out."
    /// Hide the per-field native/target segmented control when the host puts
    /// ONE shared toggle above several stacked fields (PersonaDeepenSheet) —
    /// three copies of the same picker read as clutter.
    var showsLocalePicker = true
    /// Field height, in lines. Intake narration wants room (5–10); a one-line
    /// scenario prompt wants a compact field.
    var lineRange: ClosedRange<Int> = 5...10
    /// Host-owned focus for the inner TextField, so a host that reacts to
    /// blur (the scenario composer derives a category there) keeps working
    /// when this field replaces its plain TextField. nil = self-managed.
    var externalFocus: FocusState<Bool>.Binding? = nil
    /// Card fill. The default reads on a plain systemBackground page (the
    /// intake flows); hosts embedding the field in a grouped Form must pass
    /// the grouped-row color instead — on light mode the default is the SAME
    /// gray as the Form's page background and the card disappears.
    var cardBackground = Color(.secondarySystemBackground)

    @StateObject private var live = LiveTranscriber()
    @FocusState private var internalFocus: Bool
    @State private var isRecording = false
    @State private var error: String?
    /// `text` snapshot at record start (plus separator) — each live partial
    /// re-renders as base + partial, so dictation streams into the field
    /// without duplicating on revision.
    @State private var dictationBase = ""
    /// What `text` was before the take, restored if nothing was heard.
    @State private var preTakeText = ""

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(lineRange)
                    .focused(externalFocus ?? $internalFocus)
                    .padding(14)
                    // Don't fight the dictation stream mid-take; visually
                    // unchanged, so this isn't a mode — just turn-taking.
                    .allowsHitTesting(!isRecording)

                // Control row — fixed height; contents swap, geometry doesn't.
                HStack(spacing: 10) {
                    if isRecording {
                        HStack(spacing: 5) {
                            Circle().fill(.red).frame(width: 7, height: 7)
                            Text("Listening — tap to finish")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if showsLocalePicker, dictationChoices.count > 1 {
                        // A menu, not a segmented control: the list is every
                        // language the device can hear, which never fits in
                        // two slots.
                        Picker("Language", selection: $locale) {
                            ForEach(dictationChoices, id: \.self) { code in
                                Text(LanguageCatalog.endonym(code)).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await toggleMic() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red : Color.accentColor)
                                .frame(width: 40, height: 40)
                                .scaleEffect(isRecording ? 1.08 : 1.0)
                                .animation(
                                    isRecording
                                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                        : .default,
                                    value: isRecording
                                )
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(.systemBackground))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRecording ? "Stop dictation" : "Dictate")
                }
                .frame(height: 44)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let e = error {
                Label(e, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        // Live dictation: every partial re-renders as base + partial, so the
        // words appear in the field as they're spoken.
        .onChange(of: live.transcript) { _, partial in
            guard isRecording else { return }
            let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { return }
            text = dictationBase + p
        }
        .onDisappear {
            if isRecording { commitRecordingNow() }
        }
    }

    // MARK: Recording

    private func toggleMic() async {
        if isRecording {
            isRecording = false
            finishTake(with: await live.stopAndFinalize())
            return
        }
        let granted = await LiveTranscriber.requestPermissions()
        guard granted else {
            error = "Microphone or speech permission denied."
            return
        }
        error = nil
        // Never open a recognizer for a language iOS can't do — it fails with
        // a bare "unavailable" that reads as the mic being broken. Move to a
        // language we know works and say which one is listening.
        if !LanguageCatalog.canDictate(locale), let fallback = dictationChoices.first {
            locale = fallback
        }
        guard LanguageCatalog.canDictate(locale) else {
            error = String(localized: "Dictation isn't available in this language on your device — you can still type.")
            return
        }
        do {
            try live.start(locale: locale)
            preTakeText = text
            dictationBase = text.isEmpty ? "" : text + "\n"
            isRecording = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Synchronous commit for onDisappear — skips the final-pass wait
    /// `stopAndFinalize` would do.
    private func commitRecordingNow() {
        isRecording = false
        finishTake(with: live.stop())
    }

    /// Settle the field after a take: final transcript wins; a silent take
    /// restores exactly what was there before.
    private func finishTake(with heard: String) {
        let trimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = preTakeText
        } else {
            text = dictationBase + trimmed
            usedVoice?.wrappedValue = true
        }
    }
}

// MARK: - Bottom bar

/// Back / Next bar shared by both intake flows. `isWorking` shows a spinner
/// in the primary button (parse pass at the end of a flow).
struct IntakeBottomBar: View {
    var backVisible: Bool
    var nextTitle: String
    var nextEnabled: Bool = true
    var isWorking: Bool = false
    var workingTitle: String = "Sorting it out…"
    var onBack: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if backVisible {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isWorking)
            }
            Button(action: onNext) {
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(workingTitle)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(nextTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!nextEnabled || isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
