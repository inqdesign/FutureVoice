import SwiftUI

/// The take screen: the script rolls up on top like a teleprompter, the
/// camera (or a quiet mic panel) fills the bottom half, one red button.
/// When the take is scored the same cover turns into its result.
struct SpeechPrompterView: View {
    @StateObject private var session: SpeechTakeSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speech.textSize") private var textSize: Double = 28
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    /// The prompter's width — the video's script wraps at the same width.
    @State private var prompterRect: CGRect = .zero
    private static let screenSpace = "take-screen"
    /// What the drawn script depends on; drawn again only when it changes.
    private var videoKey: String {
        "\(Int(prompterRect.width))|\(textSize)|\(colorScheme == .dark)|\(session.cameraOn)"
    }
    @State private var preparedKey: String?
    @State private var showingScript = false
    /// The reader is holding the prompter still (steady-speed mode).
    @State private var holding = false
    /// A word or two said over the controls when a mode flips.
    @State private var toast: String?
    @State private var showingTakes = false
    @ObservedObject private var store = SpeechStore.shared

    init(script: SpeechScript, native: String, level: CEFRLevel, previewCursor: Int? = nil) {
        let session = SpeechTakeSession(script: script, native: native, level: level)
        #if DEBUG
        if let previewCursor { session.preview(cursor: previewCursor) }
        #endif
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        Group {
            if case .done(let take) = session.phase {
                NavigationStack {
                    SpeechResultView(takeId: take.id, live: take)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { close() }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    session.reset()
                                } label: {
                                    Label("Again", systemImage: "arrow.counterclockwise")
                                }
                            }
                        }
                }
            } else {
                prompterScreen
            }
        }
        .task { await session.appear() }
        // The script is drawn for the video AHEAD of the take — three full
        // column renders took a visible beat when done on the record tap.
        .task(id: videoKey) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, session.phase == .ready else { return }
            prepareVideo()
        }
        .onDisappear { session.tearDown() }
        .interactiveDismissDisabled()
    }

    /// Hands the composer this screen's layout and the script drawn for the
    /// video. Once per take, at the tap, before the countdown hides the cost.
    private func prepareVideo() {
        preparedKey = videoKey
        guard session.cameraOn, prompterRect.width > 0 else {
            session.prepareVideo(layout: .init(canvas: .zero, prompter: .zero, card: .zero,
                                               cardRadius: 0, background: .clear), column: nil)
            return
        }
        let background = UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
        // The video is 9:16 whatever the phone: the take screen's layout in
        // a standard frame, script on the top half, the camera card on the
        // bottom. Its width is the screen's, so the script wraps exactly as
        // the reader saw it.
        let width = prompterRect.width
        let height = (width * 16 / 9).rounded()
        let half = height / 2
        let layout = SpeechVideoComposer.Layout(
            canvas: CGSize(width: width, height: height),
            prompter: CGRect(x: 0, y: 0, width: width, height: half - 6),
            card: CGRect(x: 12, y: half + 6, width: width - 24, height: half - 18),
            cardRadius: 24, background: background)
        let scale = SpeechVideoComposer.scale(for: layout)
        func draw() -> CGImage? {
            let renderer = ImageRenderer(content:
                SpeechPrompterColumn(track: session.track, cursor: 0, language: session.script.language,
                                     textSize: textSize, width: prompterRect.width, measures: false,
                                     onCurrentWord: { _ in })
                    .environment(\.colorScheme, colorScheme))
            renderer.scale = scale
            renderer.isOpaque = false
            return renderer.cgImage
        }
        guard let text = draw() else {
            session.prepareVideo(layout: layout, column: nil)
            return
        }
        session.prepareVideo(layout: layout, column: .init(text: text, scale: scale))
    }

    /// Shows `text` over the controls for a moment.
    private func flash(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            guard toast == text else { return }
            withAnimation(.easeIn(duration: 0.3)) { toast = nil }
        }
    }

    private func close() {
        session.tearDown()
        dismiss()
    }

    // MARK: - Screen

    private var prompterScreen: some View {
        Group {
        // No header row: every point above the camera is prompter, so the
        // line being read sits right under the lens and the reader's eyes
        // look into the camera. The controls live on the camera card.
        VStack(spacing: 0) {
            SpeechTeleprompter(track: session.track, cursor: session.cursor,
                               language: session.script.language, textSize: textSize,
                               composer: session.composer,
                               recording: isRecording,
                               follow: session.followVoice,
                               speed: session.speed,
                               voiceActive: { [session] in session.voiceActive },
                               held: holding)
                // Steady speed: press and hold the text to stop it, let go
                // to carry on (founder, 2026-10-05). Following the voice
                // already stops when the reader does.
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !holding, isRecording, !session.followVoice else { return }
                            holding = true
                            session.holding = true
                            HapticEngine.selection()
                        }
                        .onEnded { _ in
                            guard holding else { return }
                            holding = false
                            session.holding = false
                        }
                )
                .overlay(alignment: .top) {
                    if holding {
                        Label("Paused", systemImage: "pause.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .padding(.top, 4)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: holding)
                .frame(maxHeight: .infinity)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.screenSpace)) } action: {
                    prompterRect = $0
                }
            bottomHalf
                .frame(maxHeight: .infinity)
        }
        .coordinateSpace(.named(Self.screenSpace))
        .background(Color(.systemBackground))
        .overlay { overlay }
        }
    }

    private var isRecording: Bool { session.phase == .recording }
    private var cameraShowing: Bool {
        #if DEBUG
        if Self.fakeCamera { return true }
        #endif
        return session.cameraOn && session.camera.isRunning
    }

    #if DEBUG
    /// `-speechfakecam 1`: a stand-in picture where the camera goes, to see
    /// the on-camera chrome in a simulator (which has no camera).
    private static var fakeCamera: Bool { UserDefaults.standard.bool(forKey: "speechfakecam") }
    #endif

    private var topBar: some View {
        HStack {
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(SpeechChromeButtonStyle(onCamera: cameraShowing))
            .accessibilityLabel(Text("Close"))
            .hiddenWhileRecording(isRecording)

            Spacer()

            HStack(spacing: 8) {
                cornerButton("doc.text", label: Text("Whole script")) { showingScript = true }
                cornerButton("clock.arrow.circlepath", label: Text("Takes")) { showingTakes = true }
                    .overlay(alignment: .topTrailing) {
                        let count = store.takes(for: session.script.id).count
                        if count > 0 && !isRecording {
                            Text("\(count)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor, in: Capsule())
                                .offset(x: 4, y: -4)
                        }
                    }
            Menu {
                Picker("Scrolling", selection: $session.followVoice) {
                    Label("Follow my voice", systemImage: "waveform").tag(true)
                    Label("Steady speed", systemImage: "speedometer").tag(false)
                }
                if !session.followVoice {
                    Picker("Speed", selection: $session.speed) {
                        Text("Slower").tag(0.8)
                        Text("Normal").tag(1.0)
                        Text("Faster").tag(1.2)
                    }
                }
                Picker("Text size", selection: $textSize) {
                    Text("Small").tag(22.0)
                    Text("Medium").tag(28.0)
                    Text("Large").tag(34.0)
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(SpeechChromeButtonStyle(onCamera: cameraShowing))
            .disabled(isRecording)
            .accessibilityLabel(Text("Prompter settings"))
            }
            .hiddenWhileRecording(isRecording)
        }
        // The recording chip sits at the true horizontal centre, whatever
        // widths the corner groups have.
        .overlay {
            if isRecording {
                Label(SpeechFormat.duration(session.elapsed), systemImage: "record.circle")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .sheet(isPresented: $showingScript) {
            SpeechScriptSheet(script: session.script) { updated in
                session.replaceScript(updated)
                preparedKey = nil   // the video's script image is redrawn
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showingTakes) { SpeechTakesSheet(scriptId: session.script.id) }
    }

    private func cornerButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(SpeechChromeButtonStyle(onCamera: cameraShowing))
        .disabled(isRecording)
        .accessibilityLabel(label)
    }

    private var bottomHalf: some View {
        ZStack(alignment: .bottom) {
            Group {
                if cameraShowing {
                    #if DEBUG
                    if Self.fakeCamera {
                        LinearGradient(colors: [Color(white: 0.75), Color(red: 0.55, green: 0.42, blue: 0.35), Color(white: 0.2)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        SpeechCameraPreview(session: session.camera.session)
                    }
                    #else
                    SpeechCameraPreview(session: session.camera.session)
                    #endif
                } else {
                    micPanel
                }
            }
            .clipShape(cardShape)
            .padding(.horizontal, Self.cardInset)

            VStack(spacing: 14) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                controls
            }
            // Clear of the home indicator: the card runs under it, the
            // buttons don't.
            .padding(.bottom, max(20, Self.deviceBottomInset))
        }
        // The count-in sits on the camera card, where the reader is looking
        // to get ready, not over the script.
        .overlay {
            if case .countdown(let n) = session.phase {
                Text("\(n)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(cameraShowing ? Color.white : Color.primary)
                    .shadow(color: .black.opacity(cameraShowing ? 0.35 : 0), radius: 8)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 10)
        }
        .padding(.bottom, Self.cardInset)
        // The card runs to the bottom of the glass: the strip under it was
        // empty space (founder, 2026-10-05).
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Gap between the camera card and the screen's edges.
    private static let cardInset: CGFloat = 8

    /// The home indicator's inset, read once from the window — zero on a
    /// phone with a home button, where the screen corners are square.
    private static var deviceBottomInset: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return window?.safeAreaInsets.bottom ?? 0
    }

    /// The glass's own corner radius, by screen (no public API reports it;
    /// the private one is not worth an App Review question). Measured values
    /// per panel; an unknown panel with a home indicator gets the 55 of the
    /// most common recent ones, a home-button phone square corners.
    private static var displayCornerRadius: CGFloat {
        let height = Int(UIScreen.main.nativeBounds.height)
        switch height {
        case 2622, 2868, 2736:  return 62      // 16 Pro · 16 Pro Max · 17 series
        case 2556, 2796:        return 55      // 14 Pro…16, 14 Pro Max…16 Plus
        case 2532:              return 47.33   // 12 · 13 · 14 · 16e
        case 2778:              return 53.33   // 12/13 Pro Max · 14 Plus
        case 2340:              return 44      // 12/13 mini
        case 2436, 2688:        return 39      // X · XS · 11 Pro (Max)
        case 1792:              return 41.5    // XR · 11
        default:                return deviceBottomInset > 0 ? 55 : 0
        }
    }

    /// Top corners like any card; bottom corners CONCENTRIC with the
    /// display's own rounded corners, less the gap, so card and glass curve
    /// together.
    private var cardShape: UnevenRoundedRectangle {
        let bottom = max(24, Self.displayCornerRadius - Self.cardInset)
        return UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: 24,
                                      style: .continuous)
    }

    private var micPanel: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 14) {
                SpeechMicGlyph(level: session.level, recording: isRecording,
                               symbol: session.camera.denied && session.cameraOn ? "video.slash" : "mic.fill")
                if session.camera.denied && session.cameraOn {
                    Text("Camera access is off. Turn it on in Settings, or practise with the mic only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.bottom, 70)
        }
    }

    private var controls: some View {
        HStack(spacing: 36) {
            if isRecording {
                // Drop this take: nothing saved, back to the top.
                Button {
                    session.cancelTake()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(SpeechChromeButtonStyle(onCamera: cameraShowing))
                .accessibilityLabel(Text("Cancel this take"))
            } else {
                Button {
                    session.cameraOn.toggle()
                } label: {
                    Image(systemName: session.cameraOn ? "video.fill" : "video.slash.fill")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(SpeechChromeButtonStyle(onCamera: cameraShowing))
                .accessibilityLabel(session.cameraOn ? Text("Turn camera off") : Text("Turn camera on"))
            }

            Button {
                Task {
                    if isRecording {
                        await session.stop()
                    } else {
                        if preparedKey != videoKey { prepareVideo() }
                        await session.start()
                    }
                }
            } label: {
                ZStack {
                    Circle().strokeBorder(cameraShowing ? Color.white : Color.secondary.opacity(0.4), lineWidth: 4).frame(width: 76, height: 76)
                    if isRecording {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(.red).frame(width: 62, height: 62)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? Text("Stop") : Text("Record"))

            if isRecording {
                // Start over: this take is dropped and a new one counts in.
                Button {
                    Task { await session.restartTake() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(SpeechChromeButtonStyle(onCamera: cameraShowing))
                .accessibilityLabel(Text("Record again"))
            } else {
                Button {
                    session.followVoice.toggle()
                    flash(session.followVoice ? explain("Follows your voice") : explain("Steady speed"))
                } label: {
                    Image(systemName: session.followVoice ? "waveform" : "speedometer")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(SpeechChromeButtonStyle(onCamera: cameraShowing))
                .accessibilityLabel(session.followVoice ? Text("Scrolling follows your voice") : Text("Scrolling at a steady speed"))
            }
        }
    }

    @ViewBuilder private var overlay: some View {
        switch session.phase {
        case .analyzing:
            VStack(spacing: 12) {
                ProgressView()
                Text("Listening to your take…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Button("Try again") { session.reset() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        default:
            EmptyView()
        }
    }
}

/// The rolling script. A TELEPROMPTER: the text flows up at a steady speed,
/// every frame, and the reader's voice only changes that SPEED — never jumps
/// the text to where they are (2026-10-04: a word-by-word and then a
/// line-by-line version both read as jumping, because they were).
///
/// `PrompterScroller` runs the motion on the display clock. The voice gives
/// it a target (the current word's place, interpolated across its line), and
/// the speed is the reader's own pace — a slow average of how fast that
/// target has been moving — plus a gentle pull toward the target. When the
/// reader stops, the average decays and the text eases to a stop; it never
/// runs ahead of them.
struct SpeechTeleprompter: View {
    let track: SpeechPrompterTrack
    let cursor: Int
    let language: String
    let textSize: Double
    /// Told where the prompter is every frame, so the video scrolls with it.
    var composer: SpeechVideoComposer? = nil
    /// Moving at all: only while a take is being recorded.
    var recording = false
    var follow = true
    /// The steady-speed multiplier.
    var speed: Double = 1
    var voiceActive: () -> Bool = { false }
    /// Pressed and held: the steady scroll eases to a stop.
    var held = false

    @StateObject private var scroller = PrompterScroller()

    /// Where the line being read sits: it enters as the SECOND row and rises
    /// to the top row as the reader crosses it — so it stays right under the
    /// camera and never leaves the screen before its end is read. (At the
    /// very top row it was pushed out mid-line; one row lower and with a
    /// read line kept above, the gaze dropped. This is the band between.)
    private var readingLine: CGFloat { 6 + textSize * 1.55 }

    struct WordFrame: Equatable {
        var minX: CGFloat = 0
        var minY: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    var body: some View {
        GeometryReader { geo in
            let lineWidth = max(1, geo.size.width - 48)
            SpeechPrompterColumn(track: track, cursor: cursor, language: language,
                                 textSize: textSize, width: geo.size.width,
                                 onCurrentWord: { frame in
                                     let across = min(1, max(0, (frame.minX - 24) / lineWidth))
                                     let lineAdvance = frame.height + textSize * 0.35
                                     scroller.setTarget(frame.minY + across * lineAdvance,
                                                        lineTop: frame.minY,
                                                        lineAdvance: lineAdvance,
                                                        snap: cursor == 0)
                                 })
                .equatable()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Points per word: the planned pace, in the column's
                    // own units, is what the prompter starts at.
                    let perWord = height / CGFloat(max(1, track.words.count))
                    scroller.plannedPace = CGFloat(track.wordsPerSecond(language: language)) * perWord
                }
                // The reading line is the SECOND line from the top: as close
                // to the lens as it gets, with the line just read still
                // visible above it.
                .offset(y: readingLine - scroller.position)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.015),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                )
        }
        .onAppear {
            scroller.inputs = { [voiceActive] in
                (recording, follow, CGFloat(speed), voiceActive())
            }
            scroller.start()
        }
        .onChange(of: recording) { _, isRecording in
            scroller.inputs = { [voiceActive] in (isRecording, follow, CGFloat(speed), voiceActive()) }
            // A take that ended (or was cancelled) leaves the script where it
            // stopped until the cursor goes back to the top.
            if !isRecording && cursor == 0 { scroller.snapToTarget() }
        }
        .onChange(of: follow) { _, f in
            scroller.inputs = { [voiceActive] in (recording, f, CGFloat(speed), voiceActive()) }
        }
        .onChange(of: held) { _, h in scroller.held = h }
        .onChange(of: speed) { _, sp in
            scroller.inputs = { [voiceActive] in (recording, follow, CGFloat(sp), voiceActive()) }
        }
        .onDisappear { scroller.stop() }
        .onChange(of: scroller.position) { _, _ in publish() }
    }

    private func publish() {
        guard let composer else { return }
        composer.setPrompter(.init(offset: scroller.position - readingLine))
    }
}

/// Moves the prompter on the display clock. Pure motion, no layout.
@MainActor
final class PrompterScroller: NSObject, ObservableObject {
    /// How far the column has risen, in its own points.
    @Published private(set) var position: CGFloat = 0

    /// Read every frame: recording, following the voice, steady-speed
    /// multiplier, and whether someone is speaking right now.
    var inputs: () -> (recording: Bool, follow: Bool, speed: CGFloat, speaking: Bool) = { (false, true, 1, false) }
    /// The language's ordinary reading pace, in column points per second —
    /// where the prompter starts, and the band the reader's pace is kept in.
    var plannedPace: CGFloat = 0

    private var target: CGFloat = 0
    /// Top of the line being read: the highest the column may rise.
    private var ceiling: CGFloat = .greatestFiniteMagnitude
    private var lastTarget: CGFloat = 0
    private var lineAdvance: CGFloat = 40
    /// The reader's own pace: a LONG average, so a recognizer delivering
    /// words in bursts (and Korean late or not at all) never shows as speed.
    private var pace: CGFloat = 0
    private var velocity: CGFloat = 0
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    /// The reader is holding the text still.
    var held = false
    /// How far behind the reader's spot the text trails, in seconds.
    private let followTime: CGFloat = 0.45
    /// The fastest the text moves when catching up.
    private let maxLinesPerSecond: CGFloat = 2.5
    /// Seconds the reader's pace is averaged over.
    private let paceWindow: CGFloat = 6
    /// Seconds a change of speed takes.
    private let speedWindow: CGFloat = 0.8
    /// The most the text speeds up or slows down to meet the reader: a line
    /// behind is +25%, capped at ±40%. A prompter that lurches is unreadable.
    private let pullPerLine: CGFloat = 0.25
    private let maxPull: CGFloat = 0.4

    func setTarget(_ y: CGFloat, lineTop: CGFloat, lineAdvance: CGFloat, snap: Bool) {
        if lineAdvance > 0 { self.lineAdvance = lineAdvance }
        ceiling = lineTop
        // Moving the column by a fraction of a point re-rounds the layout to
        // the pixel grid, which moves the measured word by that fraction,
        // which moved the column again — an endless loop the moment the
        // prompter opened (measured: 0.067 pt back and forth). Changes under
        // a point are not movement.
        guard abs(y - target) >= 1 || (snap && abs(y - position) >= 1) else { return }
        target = y
        if snap { snapToTarget() }
    }

    /// Back onto the current word, at rest.
    func snapToTarget() {
        position = target
        lastTarget = target
        pace = 0
        velocity = 0
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTick = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTick = now }
        guard lastTick > 0 else { lastTarget = target; return }
        let dt = CGFloat(min(0.05, now - lastTick))
        guard dt > 0 else { return }
        let (recording, follow, speed, _) = inputs()
        let planned = plannedPace > 0 ? plannedPace : lineAdvance / 2

        var next = position
        if !recording {
            // Still between takes.
        } else if !follow {
            // Steady speed: exactly that, whatever is said — eased, so a
            // press-and-hold stops it gently and letting go starts it again.
            let wanted = held ? 0 : planned * speed
            velocity += (wanted - velocity) * min(1, dt / 0.3)
            next = position + velocity * dt
        } else {
            // Follow the voice, nothing more: ease toward where the reader
            // is (their word, and how far across its line), a short lag
            // behind. Speaking moves it, stopping stops it. The versions
            // before ran ahead on a learned pace and then waited at a line,
            // which read as drifting out of step with the voice (founder,
            // 2026-10-05). A long catch-up after the recognizer missed a
            // stretch is speed-capped so it glides rather than jumps.
            let gap = target - position
            var step = gap * (1 - exp(-dt / followTime))
            let cap = max(1, lineAdvance) * maxLinesPerSecond * dt
            step = min(max(step, -cap * 0.5), cap)
            next = position + step
        }
        lastTarget = target
        if abs(next - position) > 0.01 { position = next }
    }
}

/// The words themselves. Its own view with plain inputs, so the offset
/// moving every frame never re-evaluates four hundred `Text`s — only a new
/// cursor or a new size does.
struct SpeechPrompterColumn: View, Equatable {
    let track: SpeechPrompterTrack
    let cursor: Int
    let language: String
    let textSize: Double
    let width: CGFloat
    /// Reports where the current word is (the scroll follows it). Off for
    /// the copy drawn into the video.
    var measures: Bool = true
    let onCurrentWord: (SpeechTeleprompter.WordFrame) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.cursor == b.cursor && a.textSize == b.textSize && a.width == b.width && a.measures == b.measures
            && a.language == b.language && a.track.signature == b.track.signature
    }

    private static let space = "prompter-column"
    private var currentWord: Int { min(cursor, max(0, track.words.count - 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: textSize * 0.9) {
            ForEach(Array(track.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                SpeechWordWrap(spacing: LanguageCatalog.writesSpaces(language) ? textSize * 0.28 : 0,
                               lineSpacing: textSize * 0.35) {
                    ForEach(paragraph) { word in
                        Text(word.text)
                            .font(.system(size: textSize, weight: .semibold))
                            // One colour for every word. Colouring the word
                            // being read (karaoke) was tried and pulled: in
                            // Korean especially the moving colour pulled the
                            // eye off the line (founder, on device). A
                            // prompter just flows; the fades do the rest.
                            .foregroundStyle(.primary)
                            .background {
                                if measures && word.id == currentWord {
                                    Color.clear.onGeometryChange(for: SpeechTeleprompter.WordFrame.self) { proxy in
                                        let f = proxy.frame(in: .named(Self.space))
                                        return .init(minX: f.minX, minY: f.minY, width: f.width, height: f.height)
                                    } action: { frame in
                                        onCurrentWord(frame)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(width: width, alignment: .leading)
        .coordinateSpace(.named(Self.space))
    }

}

/// Lays words out left to right and wraps them — SwiftUI has no flow layout,
/// and the prompter needs each word as its own view to scroll to it.
struct SpeechWordWrap: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// The round buttons on the camera card. Over the camera they go NEUTRAL —
/// a white glyph on glass (Liquid Glass on iOS 26, a blur below it) — so
/// they read on any picture and never tint the face behind them. Without
/// the camera they are the ordinary tinted circles.
struct SpeechChromeButtonStyle: ButtonStyle {
    let onCamera: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChromeLabel(configuration: configuration, onCamera: onCamera)
    }

    private struct ChromeLabel: View {
        let configuration: Configuration
        let onCamera: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let label = configuration.label
                .foregroundStyle(onCamera ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Circle())
            Group {
                if onCamera {
                    // DARK glass: plain glass picks up a bright picture (a
                    // lit wall, a white shirt) and the white glyph vanished
                    // into it (reported on device). A dark tint keeps the
                    // glyph readable on any background.
                    if #available(iOS 26.0, *) {
                        label
                            .glassEffect(.regular.tint(.black.opacity(0.4)).interactive(), in: Circle())
                            .environment(\.colorScheme, .dark)
                    } else {
                        label
                            .background(Color.black.opacity(0.3), in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                } else {
                    label.background(Color.accentColor.opacity(0.15), in: Circle())
                }
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

private extension View {
    /// Out of sight and out of reach while a take is being recorded — the
    /// space is kept, so nothing else moves when it goes.
    func hiddenWhileRecording(_ recording: Bool) -> some View {
        opacity(recording ? 0 : 1)
            .allowsHitTesting(!recording)
            .accessibilityHidden(recording)
            .animation(.easeOut(duration: 0.2), value: recording)
    }
}

/// The mic glyph that breathes with the voice. Its own view observing only
/// the level, so the level never redraws the take screen.
private struct SpeechMicGlyph: View {
    @ObservedObject var level: SpeechLevel
    let recording: Bool
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(recording ? .red : .secondary)
            .scaleEffect(1 + CGFloat(recording ? level.value : 0) * 0.35)
            .animation(.easeOut(duration: 0.12), value: level.value)
    }
}
