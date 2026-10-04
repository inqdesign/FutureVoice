import SwiftUI

/// The take screen: the script rolls up on top like a teleprompter, the
/// camera (or a quiet mic panel) fills the bottom half, one red button.
/// When the take is scored the same cover turns into its result.
struct SpeechPrompterView: View {
    @StateObject private var session: SpeechTakeSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speech.textSize") private var textSize: Double = 28

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
        VStack(spacing: 0) {
            topBar
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
            } else {
                Text(session.script.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()

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
        .padding(.horizontal)
        .padding(.vertical, 8)
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

/// The rolling script. Read words fade back, the word being read is
/// emphasised, and the LINE being read sits a third of the way down: the
/// text moves up one line at a time as the reader reaches the next line,
/// like a teleprompter — never a paragraph at a time.
///
/// Not a ScrollView + `scrollTo`: the words live inside a custom layout, and
/// `scrollTo` resolved their ids to the paragraph around them, so the text
/// jumped by whole paragraphs. The current word's own line position is
/// measured instead, and the whole column is offset by it.
struct SpeechTeleprompter: View {
    let track: SpeechPrompterTrack
    let cursor: Int
    let language: String
    let textSize: Double

    /// Top of the line holding the current word, in the column's own space.
    @State private var lineY: CGFloat = 0

    private var currentWord: Int { min(cursor, max(0, track.words.count - 1)) }

    var body: some View {
        GeometryReader { geo in
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
                                        Color.clear.onGeometryChange(for: CGFloat.self) { proxy in
                                            proxy.frame(in: .named(Self.space)).minY
                                        } action: { y in
                                            // Rounding wobble is not a new line.
                                            if abs(y - lineY) > 1 { lineY = y }
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(width: geo.size.width, alignment: .leading)
            .coordinateSpace(.named(Self.space))
            // The animation is scoped to the offset ALONE. Applied to the
            // column, it animated every word's frame too, the measurement
            // above read the in-between frames, and each reading started a
            // new animation — a loop that pinned the main thread.
            .animation(.easeInOut(duration: 0.4)) { view in
                view.offset(y: geo.size.height * 0.3 - lineY)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.14),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private static let space = "prompter-column"

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
