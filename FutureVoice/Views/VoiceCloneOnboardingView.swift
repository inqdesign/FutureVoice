import AuthenticationServices
import SwiftUI

/// First-run voice cloning — and re-run from the Profile menu. Not a form: a
/// single full-screen stage where the Futureself surface is the protagonist
/// from first frame to last, changing only its cell state (the component's
/// own philosophy).
///
/// The pre-recording half is a step-by-step wizard — one idea per screen,
/// nothing sprung on the user (recording NEVER starts as a side effect of
/// entering a page):
///
///   1. **Intro**   — the narrative: another you, already fluent; you follow.
///   2. **Consent** — the voice model is biometric data, so its permission is
///                    its own screen with its own toggle, before the mic is
///                    even asked for. Skipped once consent is on record (a
///                    re-record is the same permission). See `ConsentStore`.
///   3. **Mic**     — never Bluetooth earbuds; the mic permission is asked
///                    HERE, on its own step, not mid-flow.
///   4. **Spot**    — LIVE quiet-spot finder: ambient monitoring drives the
///                    orb (noise stirs it, calm settles it) plus a verdict
///                    line, so the user walks the phone to the right room.
///                    Can't record now → it waits; bad take → re-record.
///   5. **Script**  — read the script; mistakes are fine, keep going. Only
///                    the explicit "Record my voice" tap starts recording.
///
/// Then the performance half:
///
///   6. **Recording** — the orb ignites with the LIVE mic level while the
///                      teleprompter scrolls; a ring tracks the 60–90s window.
///   7. **Review**    — listen back + the deterministic quality verdict.
///   8. **Becoming**  — uploading: the orb thinks, cycling all six palettes.
///   9. **Meet**      — the clone SPEAKS its first words in the user's own
///                      voice; they pick the theme their fluent self wears.
///  10. **Account**   — sign up to KEEP it.
///
/// The account moved BEHIND the meet act on 2026-08-18. It used to sit between
/// review and cloning, which meant the app asked for an account in front of the
/// one thing that sells it — a voice nobody had heard yet. What the server
/// actually needs is a session, not an account, so `useThisVoice` opens an
/// ANONYMOUS one (`AuthService.startAnonymousSession`), the clone speaks, and
/// the sign-up then asks about something already in the user's ears. Apple is
/// LINKED to that anonymous user, so the id — and with it the voice, the
/// consent record and the credit row — survives the sign-up. Sessions nobody
/// claims are collected nightly (`cleanup-anonymous-voices`), and the whole
/// path degrades to the old order if anonymous sign-ins are unavailable.
struct VoiceCloneOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = AudioPlayer()

    @State private var status: Status = .intro
    /// The two toggles on the `.consent` step, which together arm its Next.
    /// Never pre-checked: a consent that arrives already ticked is not a
    /// consent — so they start false every time the step is shown, and the
    /// step is only shown when there's nothing on record (see `stepAfterIntro`).
    /// ONE toggle for two facts. Age and voice are still recorded separately
    /// (see `ConsentStore`) — what merged is the asking: two checkboxes above
    /// one disclosure read as a form to clear, and the second one was never a
    /// separate decision for anyone who had already made the first.
    @State private var agreedToVoiceCloning = false
    @State private var error: String?
    @State private var startedAt: Date?
    @State private var elapsedSeconds: Double = 0
    @State private var ticker: Timer?
    /// Recording captured this session, awaiting the user's review (listen +
    /// quality check) before we commit to cloning.
    @State private var recordedSampleURL: URL?
    @State private var quality: AudioSampleQuality?

    // Becoming: cycling palette + staged narration.
    @State private var becomingTheme: FutureselfTheme = .blue
    @State private var becomingLine = Self.becomingLines[0]

    // Meet: the greeting in the user's cloned voice, and the burst that
    // blooms the orb when the act opens even if synthesis failed.
    @State private var greetingData: Data?
    @State private var meetBurst = false
    @AppStorage("futureselfTheme") private var storedTheme = FutureselfTheme.blue.rawValue

    /// The meet act is the first time the user HEARS the clone — and the only
    /// honest moment to judge it. If it doesn't sound like them, they can go
    /// straight back to the script from there; this flag marks that second
    /// pass, so Back cancels back to the voice they already have instead of
    /// walking the wizard backwards, and a failed re-clone doesn't strand them.
    @State private var isReRecordingClone = false
    @State private var confirmReRecord = false
    /// A/B against the recording — the meet act's answer to "is this me?".
    @State private var comparingVoice = false

    /// ElevenLabs IVC quality climbs steeply to ~60s and keeps improving to
    /// ~90s. These three had all been collapsed to 60, which broke the flow in
    /// two ways: the script below needs ~75-80s to read, so it was ALWAYS cut
    /// off mid-sentence (and a cut-off take is a worse clone); and with
    /// min == max the "Stop" affordance and the "Xs more for the cleanest
    /// clone" hint were both unreachable. Back to a real spread — 60s is a
    /// usable clone, 75s is the target, 90s is the ceiling. AudioSampleQuality
    /// has told the user "aim for 60-90s" the whole time; now that's true.
    private static let minSeconds: Double = 60
    private static let recommendedSeconds: Double = 75
    /// Hard cap — auto-stop here.
    private static let maxSeconds: Double = 90

    /// Filename of a take that reached review but was never cloned — if the
    /// app dies there, the next launch reopens review instead of making the
    /// user re-record 90 seconds. Stores the name only (container paths can
    /// change between launches); cleared on re-record and successful clone.
    private static let pendingTakeKey = "futurevoice.pendingCloneTake"

    enum Status: Int, Equatable {
        // Order is load-bearing: `prepareNativeScript` compares rawValues to
        // decide whether the script choice is still ahead of the reader.
        case intro, consent, mic, spot, script   // the wizard — one idea per screen
        case recording
        case reviewing   // recorded; user can listen + see quality before cloning
        case uploading
        case meet        // clone landed; greeting + theme pick
        case account     // sign-up: keep the voice they just heard
    }

    /// Which language the user reads the script in. The clone captures a
    /// VOICE, not a language: a reader stumbling through English hands the
    /// cloner disfluent speech and gets a clone of the stumble. Comfortable
    /// English readers still do better in English (their own phonemes, no
    /// accent transfer), so this is a choice, defaulted by self-rated level
    /// and switchable right on the script step. See `CloneScriptStore`.
    @State private var readInNative = false

    /// Accent picker off the meet act — only offered after a NATIVE-language
    /// take (see the button in `meetContent`).
    @State private var pickingAccent = false
    /// The native-language script once it's on the device — nil until the
    /// generation lands (or forever, for a native language it never does,
    /// in which case the picker simply never appears).
    @State private var nativeScript: [String]?

    /// The clone's first words — spoken in the user's own voice the moment it
    /// exists. Short on purpose (one TTS call per onboarding).
    private var greetingLine: String {
        VoiceCloneScript.greeting(for: appState.targetLanguage)
    }

    /// The words both sides of the comparison say. Uses the LIVE pick while
    /// onboarding is still running (`scriptLanguageCode` knows what's on the
    /// teleprompter right now, before any clone has been minted), then the
    /// same shared cut as Me → Voice.
    private var comparisonOpening: String {
        VoiceCloneScript.comparisonOpening(scriptLanguage: scriptLanguageCode,
                                           targetLanguage: appState.targetLanguage)
    }

    /// Staged narration for the cloning wait. Honest theater — no fake
    /// percentages, just what the process is genuinely about.
    /// Computed, not stored: a stored static resolves its strings once per
    /// process, and these have to follow the learner's language.
    private static var becomingLines: [String] {
        [
            explain("Listening back to every word…"),
            explain("Learning your vowels…"),
            explain("Finding your tone…"),
            explain("Practicing your rhythm…"),
            explain("Almost there…"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            stage
                .padding(.top, 28)
            // The script/teleprompter acts fill the space; the wizard steps
            // keep their short copy anchored under the orb.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, contentTopPadding)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            actionBar
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        // Attached to the BODY, not to `meetContent` inside the `status`
        // switch. A sheet lives and dies with the view it hangs off, and that
        // switch is a `_ConditionalContent`: any change of `status` while the
        // accent picker was open tore the picker down mid-generate, throwing
        // away a ~30 s request that had already been charged against the
        // daily cap. Out here it survives everything but this whole screen
        // going away.
        .sheet(isPresented: $pickingAccent) {
            VoiceAccentSheet(onApplied: { refreshGreetingForNewVoice() })
                .environmentObject(appState)
        }
        .sheet(isPresented: $comparingVoice) {
            VoiceComparisonSheet(scriptOpening: comparisonOpening,
                                 onRerecord: { beginReRecordFromMeet() })
                .environmentObject(appState)
        }
        .animation(.easeInOut(duration: 0.35), value: status)
        .task(id: status == .uploading) {
            if status == .uploading { await runBecoming() }
        }
        // Sign-up landed: the account act resolves itself with no second tap.
        //
        // The one branch is the returning user who walked "Get started" instead
        // of signing in: Apple's identity already had an account, so the
        // anonymous user couldn't be upgraded and the session now belongs to
        // someone else — the voice minted minutes ago hangs off a throwaway
        // user the nightly cleanup deletes. Re-clone from the take still on
        // disk so the voice they accepted belongs to the account they landed in.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn, status == .account else { return }
            // No clone yet means the anonymous session never opened and this is
            // the old order (sign up, then clone). A clone that belongs to a
            // throwaway user has to be rebuilt under the account that just
            // claimed the session. Either way: build it now.
            if appState.voiceCloneId == nil || auth.adoptedExistingAccount {
                performClone()
            } else {
                finishMeet()
            }
        }
        // The quiet-spot finder: monitor ambient noise only while the spot
        // step is on stage — the orb becomes the room's meter.
        .task(id: status == .spot) {
            if status == .spot {
                try? await recorder.startMonitoring()
            } else {
                recorder.stopMonitoring()
            }
        }
        .onDisappear {
            stopTicker()
            recorder.stopMonitoring()
            player.stop()
        }
        .onAppear {
            debugSeed()
            resumeUnclaimedVoice()
            restorePendingTake()
        }
        // Fetch the native script while the user is still reading the intro:
        // three wizard steps of slack, so the script step lands with the
        // choice already there instead of popping a picker in mid-read.
        .task { await prepareNativeScript() }
    }

    private var contentTopPadding: CGFloat {
        switch status {
        case .script, .recording: return 8
        default:                  return 32
        }
    }

    // MARK: - The stage (orb + ring + timer)

    /// One fixed-size stage across every act so nothing jumps: the pixel
    /// headline, the orb (with its recording ring), and the timer line.
    private var stage: some View {
        VStack(spacing: 20) {
            Text(stageTitle)
                .geistPixel(24)
                .id(stageTitle)
                .transition(.opacity)

            ZStack {
                // Recording ring — present only while it means something.
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 5)
                    .opacity(status == .recording ? 1 : 0)
                Circle()
                    .trim(from: 0, to: min(1, elapsedSeconds / Self.maxSeconds))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(status == .recording ? 1 : 0)
                    .animation(.linear(duration: 0.15), value: elapsedSeconds)

                Futureself(mode: orbMode, level: orbLevel, theme: orbTheme)
                    .frame(width: orbSize, height: orbSize)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
            }
            .frame(width: 182, height: orbSize + 14)

            Text(timerLine)
                .geistPixel(16)
                .foregroundStyle(timerColor)
                .opacity(timerLine.isEmpty ? 0 : 1)
                .frame(height: 20)
        }
    }

    /// The script step shrinks the orb so the full script gets the room —
    /// the being steps aside while you rehearse.
    private var orbSize: CGFloat {
        status == .script ? 72 : 168
    }

    private var stageTitle: String {
        switch status {
        case .intro:     return chrome("Your fluent self")
        case .consent:   return chrome("Your voice, in safe hands")
        case .spot:      return chrome("Find a quiet spot")
        case .mic:       return chrome("Mic check")
        case .script:    return chrome("Read this aloud")
        case .recording: return chrome("It's listening")
        case .reviewing: return chrome("How you sound")
        case .account:   return chrome("Make it yours")
        case .uploading: return chrome("Becoming you")
        case .meet:      return chrome("Meet your fluent self")
        }
    }

    private var orbMode: Futureself.Mode {
        switch status {
        case .intro, .consent, .mic, .script, .account:
            return .idle
        // The spot step wears listening: ambient noise visibly stirs the
        // surface, and finding a quiet room visibly settles it.
        case .spot:      return .listening
        case .recording: return .listening
        case .reviewing: return player.isPlaying ? .speaking : .idle
        case .uploading: return .thinking
        case .meet:      return player.isPlaying ? .speaking : .idle
        }
    }

    private var orbLevel: Float {
        switch status {
        case .intro, .consent, .mic, .script, .account:
            return 0
        case .spot:      return recorder.levels
        case .recording: return recorder.levels
        case .reviewing: return player.level
        case .uploading: return 0.35
        case .meet:      return meetBurst ? 1 : player.level
        }
    }

    /// Palette override: the becoming act cycles all six; every other act
    /// follows the stored theme (which the meet act's picker updates live).
    private var orbTheme: FutureselfTheme? {
        status == .uploading ? becomingTheme : nil
    }

    private var ringColor: Color {
        elapsedSeconds >= Self.minSeconds ? .green : .red
    }

    private var timerLine: String {
        switch status {
        case .spot:
            return ""   // the gate rows below carry the live readings
        case .recording:
            return elapsedText
        case .reviewing:
            if let q = quality { return chrome("\(Int(q.durationSeconds))s recorded") }
            return ""
        default:
            return ""
        }
    }

    private var timerColor: Color {
        status == .recording && elapsedSeconds >= Self.minSeconds ? .green : .secondary
    }

    // MARK: - Per-act content

    @ViewBuilder
    private var content: some View {
        switch status {
        case .intro:     introContent
        case .consent:   consentContent
        case .mic:       micContent
        case .spot:      spotContent
        case .script:    scriptContent
        case .recording: recordingContent
        case .reviewing: reviewingContent
        case .account:   accountContent
        case .uploading: uploadingContent
        case .meet:      meetContent
        }
    }

    // The sign-up moment — deferred past the MEET act, so it asks about
    // something the user has already heard. Everything before this ran on an
    // anonymous session; nothing here creates the voice, it only keeps it.
    private var accountContent: some View {
        VStack(spacing: 26) {
            stepHeader(explain("Save this voice to your account."),
                       explain("It's built and it's yours. Sign in and it stays — with your progress, on whichever iPhone you use."))

            // The code was typed on the Welcome screen, several steps back.
            // Showing it here is the only sign it's still coming.
            if let code = AuthService.pendingInviteCode() {
                Label(explain("Invite code \(code) · \(ReferralService.bonusMinutes) min when you sign up"),
                      systemImage: "gift")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if auth.isWorking { ProgressView() }
        }
        .transition(.opacity)
    }

    /// A wizard step's type stack: one big hook (the thing to remember) over
    /// a quiet support line. The support's measure is capped so lines break
    /// on phrases, never stranding a single word.
    private func stepHeader(_ hook: String, _ support: String?) -> some View {
        VStack(spacing: 12) {
            Text(hook)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let support { supportLine(support) }
        }
        .padding(.horizontal, 32)
    }

    /// A quiet line under the hook. Its measure is capped so lines break on
    /// phrases, never stranding a single word.
    private func supportLine(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: 300)
            .fixedSize(horizontal: false, vertical: true)
    }

    // Step 1 — the narrative. Why it's YOUR voice and not a stranger's (the
    // pitch the consent screen used to carry, moved to where the decision is
    // actually being made), then what the next minute buys.
    private var introContent: some View {
        VStack(spacing: 12) {
            stepHeader(explain("Another you.\nAlready fluent."),
                       explain("Don't imitate a stranger — practice with the fluent you."))
            supportLine(explain("Time to meet the you who speaks perfect \(LanguageCatalog.learnerName(appState.targetLanguage)) — in your own voice. One minute of reading is all it takes."))
                .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }

    // Step 2 — age + biometric consent, on one screen, gating the CTA.
    //
    // A voice model is GDPR Art. 9 special-category data, an Illinois BIPA
    // "voiceprint", and PIPA sensitive information; all three want a consent
    // that is SEPARATE from the general terms, informed about who processes it
    // and for how long, and recorded. The age sits here rather than on a screen
    // of its own because it exists for the same reason the consent does — the
    // provider that builds the model forbids under-16s and forbids us passing
    // its service on under looser terms than we got it — and because a lone
    // "how old are you?" screen in front of a language app reads as a form to
    // get past, not as a fact about what happens next.
    //
    // ONE toggle carries both facts, and they are still stored as two dated
    // records (`ConsentStore`). It starts OFF and Next is dead until it's on;
    // it is never pre-ticked, because a consent that arrives already agreed is
    // not a consent, and an age box that does is not a check.
    //
    // It sits between the narrative and the mic on purpose: after the user
    // knows what the clone is FOR (an agreement to something unexplained isn't
    // informed) and before anything has been recorded.
    private var consentContent: some View {
        VStack(spacing: 22) {
            // One promise, then what backs it. The "why your own voice" pitch
            // moved to the intro — it belongs where the learner is deciding to
            // do this at all, and here it only delayed the two facts this
            // screen exists to state. The consent still has to be separate,
            // informed and recorded (GDPR Art. 9 / BIPA / PIPA); what shrank
            // is the reading, not the disclosure.
            stepHeader(explain("Your voice is handled with care."), nil)

            VoiceConsentDetail()

            Toggle(isOn: $agreedToVoiceCloning) {
                Text(explain("I'm \(ConsentStore.minimumAge) or older, and I agree to my recording being used to build my voice model."))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 340)

            Link(explain("Privacy Policy"), destination: ConsentStore.privacyURL)
                .font(.footnote)
        }
        .padding(.horizontal, 8)
        .transition(.opacity)
    }

    /// The plain-language description of what happens to a voice recording:
    /// who processes it, what it's used for, and how it ends. Sits above the
    /// toggle because consent to something unexplained isn't informed consent
    /// — this IS the disclosure the toggle agrees to.
    private struct VoiceConsentDetail: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // Two lines, not five. The processor is NOT named here — the
                // privacy policy names it, says what it does with a recording
                // and on what legal basis, and the link to it sits under this
                // toggle. What an informed consent needs is that the facts are
                // findable and the agreement is separate and recorded, which
                // they are; the screen states the promise the learner is
                // agreeing to, not the sub-processor list.
                row("person.fill.viewfinder", explain("Your voice model is built by the most trusted service there is, and used for your language practice only."))
                row("trash", explain("Re-record it or delete it whenever you want, and deleting your account deletes it too."))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 340)
        }

        private func row(_ symbol: String, _ text: String) -> some View {
            Label {
                Text(text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).foregroundStyle(.tint)
            }
        }
    }

    // Step 3 — the mic. Permission is asked here, on its own step, so the
    // system dialog never interrupts anything else (and so the next step can
    // listen to the room).
    private var micContent: some View {
        VStack(spacing: 26) {
            // Framed as QUALITY, not as a threat. It used to warn that the
            // clone "won't sound like you", which is a punishment for getting
            // it wrong; the same instruction reads better as what a good mic
            // buys. The AirPods line below stays because it's the one concrete
            // action — Bluetooth records at phone-call quality, and the voice
            // clone is the one surface where the worn mic must NOT win.
            stepHeader(explain("Use the iPhone's mic — or a better one."),
                       explain("The better the mic, the better the voice that comes out. A wired mic is best if you have one."))

            Label("Take your AirPods out before recording", systemImage: "airpods.gen3")
                .font(.subheadline)
                .foregroundStyle(.orange)
        }
        .transition(.opacity)
    }

    // Step 3 — the quiet-spot finder. The orb is LIVE: ambient noise stirs
    // it, calm settles it. TWO gates, because quiet alone isn't enough — an
    // open room can be silent and still smear the clone with echo:
    //   1. noise  — walk until the room reads quiet;
    //   2. echo   — clap once; the decay tail says dry or reverberant.
    private var spotContent: some View {
        VStack(spacing: 26) {
            // Just give the answer. This used to say "walk until it settles",
            // which asks the reader to wander their home running an experiment
            // whose result we already know. A closet is the answer; the
            // fallbacks and the go-signal are the rest of it.
            stepHeader(explain("A closet is the best spot."),
                       explain("Clothes soak up the echo, so the recording comes out clean. No closet? A curtain or a parked car works too. Start once the readings below go quiet."))

            if recorder.isMonitoring {
                VStack(spacing: 0) {
                    gateRow(symbol: "waveform", title: chrome("Noise"),
                            value: String(format: "%.0f dB", recorder.ambientDBFS),
                            state: noiseGate.state, tint: noiseGate.tint)
                    // inset 0 — the card itself already pads 14 on both sides.
                    CardDivider(inset: 0)
                    gateRow(symbol: echoGate.symbol, title: chrome("Echo"),
                            value: recorder.echoTailMs.map { String(format: "%.0f ms", $0) },
                            state: echoGate.state, tint: echoGate.tint)
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                .frame(maxWidth: 340)
                .animation(.easeInOut(duration: 0.3), value: noiseGate.state)
                .animation(.easeInOut(duration: 0.3), value: echoGate.state)

                if bothGatesPass {
                    Label("Record here.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Can't record now? No rush — this will wait.", systemImage: "clock")
                Label("Not happy with a take? You can re-record.", systemImage: "arrow.counterclockwise")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }

    /// One gate of the room checklist: leading symbol, name, live reading,
    /// and a short colored state word.
    private func gateRow(symbol: String, title: String, value: String?,
                         state: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(state)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 12)
    }

    /// Echo tails at or under this read as a dry, soft room; longer means the
    /// space is too live. Tune on device, not the simulator.
    private static let dryTailMs: Double = 220

    /// Gate 1 — how loud the room is. dBFS on the `.measurement` capture
    /// chain (no AGC), read off `AudioRecorder.ambientDBFS`: a ~0.6 s EMA of
    /// 10 ms RMS windows.
    ///
    /// Thresholds are derived from the SNR the clone actually needs, not from
    /// a desk reading. Read at conversational distance a voice lands around
    /// −25 dBFS, and a usable clone wants the room sitting ~30 dB under that.
    /// So −55 is "quiet", and −45 (20 dB SNR) is the last tolerable rung.
    ///
    /// They were −45/−35 until 2026-08-17, which is where the bug was: a room
    /// with a TV playing measures about −47 dBFS, comfortably under the old
    /// −45 bar, so the gate called a living room with the TV on "quiet" and
    /// sent the learner off to record a take the noise had already ruined.
    /// Both rungs moved down 10 dB.
    private var noiseGate: (state: String, tint: Color) {
        let db = recorder.ambientDBFS
        if db > -45 { return (explain("too noisy"), .red) }
        if db > -55 { return (explain("almost"), .orange) }
        return (explain("quiet"), .green)
    }

    /// Gate 2 — how live the room is. Waits for a clap; each clap re-measures.
    private var echoGate: (symbol: String, state: String, tint: Color) {
        guard let tail = recorder.echoTailMs else {
            return ("hands.clap", explain("clap to check"), Color.accentColor)
        }
        if tail <= Self.dryTailMs { return ("checkmark.circle.fill", explain("dry"), .green) }
        return ("water.waves", explain("echoey"), .orange)
    }

    private var bothGatesPass: Bool {
        noiseGate.tint == .green && echoGate.tint == .green
    }

    /// The paragraphs on stage — the native script only when it exists AND
    /// the user picked it.
    private var activeScript: [String] {
        (readInNative ? nativeScript : nil)
            ?? VoiceCloneScript.paragraphs(for: appState.targetLanguage)
    }

    // Step 4 — the script, in full, BEFORE anything records. Recording only
    // starts on the explicit button tap.
    private var scriptContent: some View {
        VStack(spacing: 10) {
            // The language choice is made by LOOKING at the text — "can I
            // read this aloud for a minute without stumbling?" is answered by
            // the paragraphs below, not by a question on its own screen.
            if nativeScript != nil {
                Picker("Read in", selection: $readInNative) {
                    Text(LanguageCatalog.endonym(appState.targetLanguage)).tag(false)
                    Text(LanguageCatalog.endonym(appState.nativeLanguage)).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 28)
            }

            Text(nativeScript == nil
                 ? "Read it naturally. Mistakes are fine — just keep going."
                 : "Read whichever one feels natural — we're capturing your voice, not your reading.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(activeScript.enumerated()), id: \.offset) { _, para in
                        Text(para)
                            .font(.title3.weight(.medium))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
            .mask(softEdges)

            Text(explain("1 minute. Vary your pitch a little."))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .transition(.opacity)
    }

    // Recording — the teleprompter.
    private var recordingContent: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(activeScript.enumerated()), id: \.offset) { _, para in
                        Text(para)
                            .font(.title3.weight(.medium))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            }
            .mask(softEdges)

            if !recorder.inputDescription.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: isBadMic ? "exclamationmark.triangle.fill" : "mic.fill")
                    Text(isBadMic
                         ? explain("Bluetooth mic — disconnect AirPods for a faithful clone")
                         : recorder.inputDescription)
                }
                .font(.caption)
                .foregroundStyle(isBadMic ? Color.orange : Color(.tertiaryLabel))
            }
        }
        .transition(.opacity)
    }

    /// Soft top/bottom fade for scrolling text — no hard cuts.
    private var softEdges: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // Review.
    private var reviewingContent: some View {
        VStack(spacing: 18) {
            if let q = quality {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: q.rating.symbol)
                            .foregroundStyle(ratingTint(q.rating))
                        Text(q.rating.label)
                            .font(.callout.weight(.semibold))
                    }
                    ForEach(q.issues, id: \.self) { issue in
                        Text(issue)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
            }

            Button {
                togglePreview()
            } label: {
                Label(player.isPlaying ? "Stop" : "Listen to your recording",
                      systemImage: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text(explain("No need to be loud — just be clear."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .transition(.opacity)
    }

    // The becoming.
    private var uploadingContent: some View {
        VStack(spacing: 12) {
            Text(becomingLine)
                .font(.title3)
                .foregroundStyle(.secondary)
                .id(becomingLine)
                .transition(.opacity)
            Text(explain("About half a minute."))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .transition(.opacity)
    }

    // Meet: greeting + theme pick.
    private var meetContent: some View {
        VStack(spacing: 22) {
            stepHeader(explain("It's you — fluent."),
                       explain("Pick how your fluent self looks."))

            HStack(spacing: 14) {
                ForEach(FutureselfTheme.allCases) { theme in
                    let selected = storedTheme == theme.rawValue
                    Button { pick(theme) } label: {
                        VStack(spacing: 5) {
                            Futureself(mode: .speaking,
                                       level: selected ? 0.75 : 0.3,
                                       theme: theme)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(
                                    selected ? theme.tint : Color(.separator).opacity(0.5),
                                    lineWidth: selected ? 2 : 0.5))
                            Text(theme.label)
                                .font(.caption2)
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(minHeight: 70)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(Text("\(theme.label) theme"))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            VStack(spacing: 14) {
                if greetingData != nil {
                    Button {
                        playGreeting()
                    } label: {
                        Label("Hear it again", systemImage: "arrow.clockwise")
                            .font(.footnote)
                    }
                }

                // The verdict belongs here, not one screen earlier: at review
                // they judged their own raw take, here they judge the CLONE.
                // "It doesn't sound like me" with no way back is the one exit
                // this act can't afford.
                // Opens the A/B, not the re-record dialog. Asking "record
                // again?" here made the learner rule on a likeness they had
                // heard once, against a memory of their own voice — the one
                // recording everyone finds strange. The comparison answers it
                // in ten seconds, and the re-record decision lives inside it.
                Button {
                    player.stop()
                    comparingVoice = true
                } label: {
                    Label("Doesn't sound like you?", systemImage: "waveform")
                        .font(.footnote)
                }

                // Offered to EVERYONE who has accents to choose from, not just
                // native-language takes. The old rule was that a
                // target-language reader had already given the clone their own
                // accent and so had nothing to pick — true, and beside the
                // point: wanting to sound American or British is a wish about
                // the fluent self, and this screen is the one moment the
                // learner is actually listening to it. Hiding the choice here
                // meant they had to know it exists in Me → Voice to ever find
                // it. Still optional, still reversible from Me → Voice.
                if !VoiceAccentCatalog.options(for: appState.targetLanguage).isEmpty {
                    Button {
                        player.stop()
                        pickingAccent = true
                    } label: {
                        Label("Choose your accent", systemImage: "globe")
                            .font(.footnote)
                    }
                }
            }

            // The code they typed on the Welcome screen actually landed. Said
            // once, here, on the last screen before the first call: the grant
            // itself is a number on a settings page they have no reason to
            // open, so without this line the invite simply never happened.
            if let plan = auth.redeemedCompPlanId {
                Label(explain("\(AccountStatus.tierName(plan)) applied · 1 month"),
                      systemImage: "gift.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else if auth.redeemedInviteBalance != nil {
                Label(explain("Invite applied · \(ReferralService.bonusMinutes) min of talk time"),
                      systemImage: "gift.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
        .transition(.opacity)
        .confirmationDialog("Record your voice again?", isPresented: $confirmReRecord,
                            titleVisibility: .visible) {
            Button("Record again", role: .destructive) { beginReRecordFromMeet() }
            Button("Keep this voice", role: .cancel) {}
        } message: {
            // Free, and said out loud — a user who suspects a retake costs
            // them credits will settle for a voice that isn't theirs.
            Text(explain("You'll read the script once more, about a minute. Recording again during setup is free, and this voice is replaced only if you keep the new one."))
        }
    }

    private func ratingTint(_ r: AudioSampleQuality.Rating) -> Color {
        switch r {
        case .good: return .green
        case .okay: return .orange
        case .poor: return .red
        }
    }

    /// Where Next goes from the intro, and where Back returns to from the mic.
    ///
    /// The consent step is SKIPPED once both answers are on record — a
    /// re-record builds a new model from a new take, but it's the same
    /// permission and the same person, and re-showing the screen would mean
    /// either asking twice for one thing or (worse) showing pre-ticked boxes,
    /// which isn't a consent at all.
    private var stepAfterIntro: Status {
        let consent = ConsentStore.shared
        return consent.hasVoiceConsent && consent.isAgeVerified ? .mic : .consent
    }

    // MARK: - Action bar

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 8) {
            switch status {
            case .intro:
                // Cross-stage back: reopen the persona cards. The published
                // persona is only nil-ed — the store keeps the data, and the
                // intake reopens pre-filled from it.
                wizardBar(next: chrome("Next"), onBack: { appState.persona = nil }) {
                    agreedToVoiceCloning = false
                    status = stepAfterIntro
                }

            case .consent:
                // Next is dead until the toggle is on — the whole point of an
                // explicit consent is that it can't be walked past.
                wizardBar(next: chrome("Next"),
                          nextDisabled: !agreedToVoiceCloning,
                          backTo: .intro) {
                    ConsentStore.shared.confirmAge()
                    ConsentStore.shared.recordVoiceConsent()
                    status = .mic
                }

            case .mic:
                wizardBar(next: chrome("Next"), backTo: stepAfterIntro) { handleMicPermission() }

            case .spot:
                wizardBar(next: chrome("Next"), backTo: .mic) { status = .script }

            case .script:
                // Re-recording from the meet act: Back means "never mind,
                // keep the voice I have", not "walk the wizard backwards".
                if isReRecordingClone {
                    wizardBar(next: chrome("Record my voice"), nextIcon: "mic.fill",
                              onBack: { cancelReRecord() }) {
                        startRecording()
                    }
                } else {
                    wizardBar(next: chrome("Record my voice"), nextIcon: "mic.fill", backTo: .spot) {
                        startRecording()
                    }
                }

            case .recording:
                // No early submit: every beta take that stopped short of the
                // minimum produced a "doesn't sound like me" clone. Before
                // minSeconds the only exit is starting over — a flubbed take
                // never traps the user, but a short one can't proceed either.
                if elapsedSeconds >= Self.minSeconds {
                    Button(action: stopAndReview) {
                        Label("Stop & review", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(elapsedSeconds >= Self.recommendedSeconds ? .green : .red)
                } else {
                    Button(action: abortRecording) {
                        Label("Start over", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(elapsedSeconds < 1)
                }

                recordingFooter

            case .reviewing:
                HStack(spacing: 12) {
                    Button {
                        reRecord()
                    } label: {
                        Label("Re-record", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Button {
                        useThisVoice()
                    } label: {
                        Label("Use this voice", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // Escape hatch for the second pass — including after a failed
                // re-clone, where the live voice is still intact.
                if isReRecordingClone {
                    Button("Keep my current voice") { cancelReRecord() }
                        .font(.footnote)
                }

            case .account:
                HStack(spacing: 12) {
                    Button {
                        error = nil
                        // Back to whatever this step interrupted: the voice
                        // they just met, or the take waiting to become one.
                        status = appState.voiceCloneId == nil ? .reviewing : .meet
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    // `.continue` label — this is a first-time sign-UP moment,
                    // not a returning-user sign-in (Welcome handles those).
                    SignInWithAppleButton(
                        .continue,
                        onRequest: { auth.configure($0) },
                        onCompletion: { auth.handle(result: $0) }
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .clipShape(Capsule())
                }

            case .uploading:
                Button {} label: {
                    Label("Cloning your voice…", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)

            case .meet:
                // Two exits, one button. With an account behind the session
                // this is onboarding's last tap, straight into the first call;
                // on the anonymous session it hands over to the sign-up, which
                // now asks about a voice they've heard rather than a promise.
                if auth.isSignedIn || authBypassed {
                    Button(action: finishMeet) {
                        Text("Start talking")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        player.stop()
                        status = .account
                    } label: {
                        Text("Save this voice")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// Shared wizard bar: optional Back (bordered) + Next (prominent) — the
    /// same grammar SetupFlowView uses, so onboarding reads as one flow.
    @ViewBuilder
    private func wizardBar(next: String, nextIcon: String? = nil,
                           nextDisabled: Bool = false,
                           backTo: Status? = nil, onBack: (() -> Void)? = nil,
                           action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            if backTo != nil || onBack != nil {
                // Compact Back — the primary action keeps the room it needs
                // ("Record my voice" must never wrap). `backTo` steps within
                // this wizard; `onBack` handles cross-stage exits.
                Button {
                    error = nil
                    if let backTo { status = backTo } else { onBack?() }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button(action: action) {
                if let nextIcon {
                    Label(next, systemImage: nextIcon)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(next)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // Only the primary — Back must stay live, or a step that gates
            // its Next (the consent toggle) becomes a wall.
            .disabled(nextDisabled)
        }
    }

    @ViewBuilder
    private var recordingFooter: some View {
        if elapsedSeconds < Self.minSeconds {
            Text("Keep going — \(Int(Self.minSeconds - elapsedSeconds))s more")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if elapsedSeconds < Self.recommendedSeconds {
            Text("Good. \(Int(Self.recommendedSeconds - elapsedSeconds))s more for the best result")
                .font(.footnote)
                .foregroundStyle(.green)
        } else {
            Text("That's enough — stop whenever you're ready")
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }

    // MARK: - Helpers

    private var elapsedText: String {
        let s = Int(elapsedSeconds)
        return String(format: "%01d:%02d", s / 60, s % 60)
    }

    private var isBadMic: Bool {
        recorder.inputDescription.lowercased().contains("bluetooth")
    }

    // MARK: - Script language

    /// Below B2, reading English aloud for 90 seconds is work — the take
    /// comes out halting and the clone inherits it. At B2 and up the English
    /// take wins instead, so it stays the default there. Self-rating is
    /// noisy, which is exactly why the switch sits next to the text.
    private static func prefersNativeScript(_ level: CEFRLevel) -> Bool {
        switch level {
        case .a1, .a2, .b1: return true
        case .b2, .c1, .c2: return false
        }
    }

    private func prepareNativeScript() async {
        let code = appState.nativeLanguage
        guard code != appState.targetLanguage, nativeScript == nil else { return }
        // Hand-authored languages resolve synchronously; the rest cost one
        // Gemini call, once per device, cached forever.
        var script = CloneScriptStore.shared.script(for: code)
        if script == nil { script = await CloneScriptStore.shared.ensure(for: code) }
        guard let script else { return }
        nativeScript = script
        // Only pre-select while the choice is still ahead of them — never
        // swap the text out from under someone mid-read.
        if status.rawValue < Status.script.rawValue,
           Self.prefersNativeScript(appState.proficiency) {
            readInNative = true
        }
    }

    /// What the take was read in — the funnel needs it to tell whether the
    /// native script actually cuts re-records.
    private var scriptLanguageCode: String {
        readInNative && nativeScript != nil ? appState.nativeLanguage : appState.targetLanguage
    }

    // MARK: - Actions

    /// Mic step's Next: ask for the permission right here — its own moment,
    /// with the Bluetooth warning still on screen — then move to the
    /// quiet-spot finder (which needs the mic to listen to the room).
    private func handleMicPermission() {
        Task {
            let granted = await recorder.requestPermission()
            if granted {
                error = nil
                // Warm the audio session NOW (background) so the spot step's
                // meter is alive almost as soon as the page lands.
                AudioRecorder.prewarmMonitoringSession()
                status = .spot
            } else {
                error = explain("Microphone access denied. Enable it in Settings.")
            }
        }
    }

    /// The ONLY way recording starts: the explicit "Record my voice" tap on
    /// the script step.
    private func startRecording() {
        Task {
            do {
                // Permission was granted on the mic step; re-check is free and
                // covers the Settings-revoked edge.
                let granted = await recorder.requestPermission()
                guard granted else {
                    error = explain("Microphone access denied. Enable it in Settings.")
                    return
                }
                error = nil
                elapsedSeconds = 0
                try recorder.start(quality: .voiceCloneHigh)
                startedAt = Date()
                startTicker()
                status = .recording
            } catch {
                self.error = error.localizedDescription
                status = .script
                stopTicker()
            }
        }
    }

    private func togglePreview() {
        if player.isPlaying {
            player.stop()
            return
        }
        guard let url = recordedSampleURL, let data = try? Data(contentsOf: url) else { return }
        try? player.play(data)
    }

    /// Confirm the reviewed recording and build the voice.
    ///
    /// Onboarding runs account-free all the way through the MEET act now: the
    /// sign-up used to sit here, in front of a voice the user had never heard,
    /// which asked them to open an account for a promise. What the server
    /// actually needs is a session, not an account — so an anonymous one is
    /// opened silently here, the clone speaks, and the account is asked for
    /// afterwards, to KEEP the voice they just heard. See `AuthService`.
    private func useThisVoice() {
        guard recordedSampleURL != nil else { return }
        player.stop()
        if auth.session == nil && !authBypassed {
            status = .uploading
            Task {
                do {
                    try await auth.startAnonymousSession()
                    performClone()
                } catch {
                    // Anonymous sessions unavailable — the project setting is
                    // off, or there's no network. Fall back to the ORIGINAL
                    // order (sign up, then clone) rather than stranding the
                    // user on a take they can't use: this screen is the only
                    // way into the app, so it can never depend on a server
                    // setting being right.
                    status = .account
                }
            }
            return
        }
        performClone()
    }

    #if DEBUG
    private var authBypassed: Bool { UserDefaults.standard.bool(forKey: "debugSkipAuth") }
    #else
    private var authBypassed: Bool { false }
    #endif

    /// Persist the raw sample for later re-generation, clone, then synthesize
    /// the clone's first words so the meet act can play them.
    /// `holdVoiceOnboarding` keeps RootView from swapping away the moment the
    /// voice id lands.
    private func performClone() {
        guard let url = recordedSampleURL else { return }
        status = .uploading
        appState.holdVoiceOnboarding = true
        // Keep the original so the clone can be regenerated later without
        // recording again (Settings → Voice).
        VoiceSampleStore.shared.save(from: url)
        Task {
            do {
                try await appState.regenerateVoiceClone(fromSampleAt: url,
                                                        scriptLanguage: scriptLanguageCode)
                UserDefaults.standard.removeObject(forKey: Self.pendingTakeKey)
                // First words in the user's own voice. Best-effort: a failed
                // synthesis never blocks the flow — the act just opens silent.
                if let voiceId = appState.voiceCloneId {
                    // Fidelity model, deliberately, even though this line is
                    // never cached: it fires ONCE per user in their lifetime,
                    // it's the free greeting, and it is the single moment the
                    // user decides whether the clone sounds like them. The 2x
                    // character cost of one short line is the cheapest thing
                    // we spend money on. The extra latency lands inside the
                    // "Becoming…" act, which is already a wait.
                    greetingData = try? await ElevenLabsClient.shared.synthesize(
                        voiceId: voiceId, text: greetingLine,
                        modelId: ElevenLabsClient.fidelityModelId, purpose: "greeting")
                }
                HapticEngine.success()
                isReRecordingClone = false
                status = .meet
                openMeet()
            } catch {
                self.error = error.localizedDescription
                status = .reviewing
                // Only release the hold when there's no voice to fall back to.
                // On a failed re-clone the old voice is still live, and letting
                // go here would drop the user into the tabs mid-flow.
                if !isReRecordingClone { appState.holdVoiceOnboarding = false }
            }
        }
    }

    /// Entry bloom for the meet act: a full-level burst (the smoother's slow
    /// release handles the exhale), then the greeting takes over the orb.
    private func openMeet() {
        meetBurst = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            meetBurst = false
            playGreeting()
        }
    }

    private func playGreeting() {
        guard let data = greetingData else { return }
        player.stop()
        try? player.play(data, forceSessionReset: true)
    }

    /// After an accent pick replaces the voice, the stored greeting still
    /// speaks with the OLD voice — re-synthesize so "Hear it again" and the
    /// theme-pick replay speak with the voice the user just chose. Same
    /// fidelity-model reasoning as the original greeting: fires at most once
    /// per accent adoption, at the exact moment the user judges the voice.
    private func refreshGreetingForNewVoice() {
        greetingData = nil
        guard let voiceId = appState.voiceCloneId else { return }
        Task {
            greetingData = try? await ElevenLabsClient.shared.synthesize(
                voiceId: voiceId, text: greetingLine,
                modelId: ElevenLabsClient.fidelityModelId, purpose: "greeting")
            playGreeting()
        }
    }

    private func pick(_ theme: FutureselfTheme) {
        storedTheme = theme.rawValue
        // The study widgets wear the same theme — repaint them at once.
        StudyWidgetRefresher.refresh()
        HapticEngine.light()
        // Feel the choice: the big orb re-speaks the greeting in this palette.
        playGreeting()
    }

    private func finishMeet() {
        player.stop()
        appState.holdVoiceOnboarding = false   // RootView moves on to the tabs
    }

    /// Abandon the take mid-recording (before the minimum) and return to the
    /// script step. The partial file is discarded — it must never reach review.
    private func abortRecording() {
        stopTicker()
        if let url = recorder.stop() { try? FileManager.default.removeItem(at: url) }
        elapsedSeconds = 0
        error = nil
        status = .script
    }

    /// Meet act → straight back to the script. The existing clone stays live
    /// the whole way (`regenerateVoiceClone` only stages the old voice for
    /// deletion once a NEW one succeeds), and `holdVoiceOnboarding` stays on
    /// so RootView doesn't swap to the tabs the moment we leave this act.
    private func beginReRecordFromMeet() {
        isReRecordingClone = true
        meetBurst = false
        appState.holdVoiceOnboarding = true
        // greetingData survives on purpose — cancelling or a failed re-clone
        // returns to this act with the current voice still able to speak.
        reRecord()
    }

    /// Abandon the second pass and go back to the voice they already have.
    private func cancelReRecord() {
        player.stop()
        if let url = recordedSampleURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: Self.pendingTakeKey)
        recordedSampleURL = nil
        quality = nil
        elapsedSeconds = 0
        error = nil
        isReRecordingClone = false
        status = .meet
    }

    private func reRecord() {
        player.stop()
        if let url = recordedSampleURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: Self.pendingTakeKey)
        recordedSampleURL = nil
        quality = nil
        elapsedSeconds = 0
        error = nil
        status = .script
    }

    /// Stop recording and move to the review step. Shared by the manual
    /// Stop tap and the automatic stop at `maxSeconds`.
    private func stopAndReview() {
        stopTicker()
        guard let rawURL = recorder.stop() else { status = .script; return }
        // Don't clone yet — let the user listen and see the quality check
        // first, then confirm with "Use this voice".
        recordedSampleURL = rawURL
        quality = AudioSampleQuality.analyze(url: rawURL)
        // Remember the take so a relaunch reopens review, not step one.
        UserDefaults.standard.set(rawURL.lastPathComponent, forKey: Self.pendingTakeKey)
        status = .reviewing
    }

    /// Relaunch landing: if a reviewed-but-never-cloned take is still on
    /// disk, resume straight at review — the user's 90 seconds are not lost.
    /// The app died between "keep this voice" and the sign-up — reopen on the
    /// account step instead of walking a finished voice through the wizard
    /// again. Without this the flow would either restart from the intro or,
    /// worse, wave the user through into the app on an anonymous session that
    /// can never be signed back into (see `RootView`'s gate).
    private func resumeUnclaimedVoice() {
        guard status == .intro, appState.voiceCloneId != nil,
              auth.isAnonymous, !authBypassed else { return }
        appState.holdVoiceOnboarding = true
        status = .account
    }

    private func restorePendingTake() {
        guard status == .intro, recordedSampleURL == nil,
              let name = UserDefaults.standard.string(forKey: Self.pendingTakeKey) else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: Self.pendingTakeKey)
            return
        }
        recordedSampleURL = url
        quality = AudioSampleQuality.analyze(url: url)
        status = .reviewing
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let started = startedAt else { return }
                elapsedSeconds = Date().timeIntervalSince(started)
                if status == .recording, elapsedSeconds >= Self.maxSeconds {
                    HapticEngine.success()   // cue that recording auto-stopped at the cap
                    stopAndReview()
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Becoming loop

    /// While uploading: advance the palette every beat and the narration every
    /// other beat. `.task(id:)` cancels this the moment the act ends.
    private func runBecoming() async {
        var step = 0
        while status == .uploading, !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.6)) {
                becomingTheme = FutureselfTheme.allCases[step % FutureselfTheme.allCases.count]
                becomingLine = Self.becomingLines[min(step / 2, Self.becomingLines.count - 1)]
            }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            step += 1
        }
    }

    // MARK: - Debug capture seam

    /// Screenshot harness: `-cloneStage <intro|spot|mic|script|recording|`
    /// `reviewing|uploading|meet>` jumps straight to an act with stand-in
    /// data — no mic, no network.
    private func debugSeed() {
        #if DEBUG
        // `-cloneScript native` forces the native-language script on stage —
        // the level default only applies before the script step, which a
        // stage jump lands past.
        if UserDefaults.standard.string(forKey: "cloneScript") == "native" {
            readInNative = true
        }
        guard let stage = UserDefaults.standard.string(forKey: "cloneStage") else { return }
        switch stage {
        case "spot":      status = .spot
        case "consent":   status = .consent
        case "mic":       status = .mic
        case "script":    status = .script
        case "recording":
            elapsedSeconds = 47
            status = .recording
        case "reviewing":
            elapsedSeconds = 78
            status = .reviewing
        case "account":   status = .account
        case "uploading": status = .uploading
        case "meet":      status = .meet
        default:          status = .intro
        }
        #endif
    }
}
