import SwiftUI

/// The take screen: the script rolls up on top like a teleprompter, the
/// camera (or a quiet mic panel) fills the bottom half, one red button.
/// When the take is scored the same cover turns into its result.
struct SpeechPrompterView: View {
    @StateObject private var session: SpeechTakeSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speech.textSize") private var textSize: Double = 28
    @State private var showingScript = false
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
        .onDisappear { session.tearDown() }
        .interactiveDismissDisabled()
    }

    private func close() {
        session.tearDown()
        dismiss()
    }

    // MARK: - Screen

    private var prompterScreen: some View {
        // No header row: every point above the camera is prompter, so the
        // line being read sits right under the lens and the reader's eyes
        // look into the camera. The controls live on the camera card.
        VStack(spacing: 0) {
            SpeechTeleprompter(track: session.track, cursor: session.cursor,
                               language: session.script.language, textSize: textSize)
                .frame(maxHeight: .infinity)
            progressStrip
            bottomHalf
                .frame(maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .overlay { overlay }
    }

    private var isRecording: Bool { session.phase == .recording }
    private var cameraShowing: Bool { session.cameraOn && session.camera.isRunning }

    private var topBar: some View {
        HStack {
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Close"))

            Spacer()
            if isRecording {
                Label(SpeechFormat.duration(session.elapsed), systemImage: "record.circle")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
            }
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
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(isRecording)
            .accessibilityLabel(Text("Prompter settings"))
            }
        }
        .padding(.horizontal, 12)
        .sheet(isPresented: $showingScript) { SpeechScriptSheet(script: session.script) }
        .sheet(isPresented: $showingTakes) { SpeechTakesSheet(scriptId: session.script.id) }
    }

    private func cornerButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(isRecording)
        .accessibilityLabel(label)
    }

    /// How far through the script, as a thin bar — the one number a reader
    /// glances at mid-sentence.
    private var progressStrip: some View {
        ProgressView(value: Double(session.cursor), total: Double(max(1, session.track.words.count)))
            .progressViewStyle(.linear)
            .tint(isRecording ? .red : .accentColor)
            .padding(.horizontal)
            .padding(.vertical, 6)
    }

    private var bottomHalf: some View {
        ZStack(alignment: .bottom) {
            Group {
                if cameraShowing {
                    SpeechCameraPreview(session: session.camera.session)
                } else {
                    micPanel
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 12)

            controls
                .padding(.bottom, 20)
        }
        .overlay(alignment: .top) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 10)
        }
        .padding(.bottom, 8)
    }

    private var micPanel: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 14) {
                Image(systemName: session.camera.denied && session.cameraOn ? "video.slash" : "mic.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(isRecording ? .red : .secondary)
                    .scaleEffect(1 + CGFloat(isRecording ? session.level : 0) * 0.35)
                    .animation(.easeOut(duration: 0.12), value: session.level)
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
            Button {
                session.cameraOn.toggle()
            } label: {
                Image(systemName: session.cameraOn ? "video.fill" : "video.slash.fill")
                    .font(.title3)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(isRecording)
            .accessibilityLabel(session.cameraOn ? Text("Turn camera off") : Text("Turn camera on"))

            Button {
                Task { isRecording ? await session.stop() : await session.start() }
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

            Button {
                session.followVoice.toggle()
            } label: {
                Image(systemName: session.followVoice ? "waveform" : "speedometer")
                    .font(.title3)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(isRecording)
            .accessibilityLabel(session.followVoice ? Text("Scrolling follows your voice") : Text("Scrolling at a steady speed"))
        }
    }

    @ViewBuilder private var overlay: some View {
        switch session.phase {
        case .countdown(let n):
            Text("\(n)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 8)
                .transition(.opacity)
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

    @StateObject private var scroller = PrompterScroller()

    /// One line of text plus its spacing, and a little air above it.
    private var readingLine: CGFloat { textSize * 1.75 + 8 }

    struct WordFrame: Equatable {
        var minX: CGFloat = 0
        var minY: CGFloat = 0
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
                                                        snap: cursor == 0)
                                 })
                .equatable()
                // The reading line is the SECOND line from the top: as close
                // to the lens as it gets, with the line just read still
                // visible above it.
                .offset(y: readingLine - scroller.position)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                )
        }
        .onAppear { scroller.start() }
        .onDisappear { scroller.stop() }
    }
}

/// Moves the prompter on the display clock. Pure motion, no layout.
@MainActor
final class PrompterScroller: NSObject, ObservableObject {
    /// How far the column has risen, in its own points.
    @Published private(set) var position: CGFloat = 0

    private var target: CGFloat = 0
    private var lastTarget: CGFloat = 0
    /// The reader's pace in points per second — a slow average, so words
    /// arriving in bursts still read as one steady speed.
    private var pace: CGFloat = 0
    private var velocity: CGFloat = 0
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    /// Seconds over which the pace is averaged, and over which the speed
    /// changes. Long on purpose: a teleprompter that speeds up and slows down
    /// with every word is unreadable.
    private let paceWindow: CGFloat = 2.5
    private let speedWindow: CGFloat = 0.6
    /// How hard the text is pulled toward the reader when it lags.
    private let pull: CGFloat = 0.35

    func setTarget(_ y: CGFloat, snap: Bool) {
        // Moving the column by a fraction of a point re-rounds the layout to
        // the pixel grid, which moves the measured word by that fraction,
        // which moved the column again — an endless loop the moment the
        // prompter opened (measured: 0.067 pt back and forth). Changes under
        // a point are not movement.
        guard abs(y - target) >= 1 || (snap && abs(y - position) >= 1) else { return }
        target = y
        if snap {
            position = y
            lastTarget = y
            pace = 0
            velocity = 0
        }
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

        // The reader's pace: how fast the target is moving, averaged.
        let instant = max(0, target - lastTarget) / dt
        lastTarget = target
        pace += (instant - pace) * min(1, dt / paceWindow)

        let gap = target - position
        // Their pace, plus a gentle pull toward where they are: behind, it
        // speeds up a little; ahead, it slows down — easing, never a halt.
        let wanted = max(0, pace + pull * gap)
        velocity += (wanted - velocity) * min(1, dt / speedWindow)
        let next = position + velocity * dt
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
    let onCurrentWord: (SpeechTeleprompter.WordFrame) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.cursor == b.cursor && a.textSize == b.textSize && a.width == b.width
            && a.language == b.language && a.track.words.count == b.track.words.count
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
                            .foregroundStyle(color(for: word.id))
                            .background {
                                if word.id == currentWord {
                                    Color.clear.onGeometryChange(for: SpeechTeleprompter.WordFrame.self) { proxy in
                                        let f = proxy.frame(in: .named(Self.space))
                                        return .init(minX: f.minX, minY: f.minY, height: f.height)
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

    private func color(for id: Int) -> Color {
        if id < cursor { return .secondary.opacity(0.55) }
        if id == cursor { return .accentColor }
        return .primary
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
