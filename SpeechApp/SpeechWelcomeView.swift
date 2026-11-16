import SwiftUI
import AuthenticationServices
import AVFoundation

/// The first screen (2026-11-16, founder): the teaser plays (each person
/// with their challenge's category, saying their opening, then everyone at
/// once), and the page takes over on its last frame: the crowd stays, "Your
/// turn." comes in where "Everyone has a line." was, and what people bring
/// their own script for comes in under it. Aimed at people who speak in
/// public for work, and at anyone with a talk coming up.
struct SpeechWelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var teaserDone = false

    var body: some View {
        NavigationStack {
            ZStack {
                // The teaser's own ground (black under its film grain), so
                // the video has no visible frame.
                Color(white: 10 / 255).ignoresSafeArea()
                if teaserDone || reduceMotion {
                    SpeechWelcomeTurn()
                        .transition(.opacity)
                } else {
                    SpeechTeaserPlayer {
                        // The page opens on the video's last frame, so the
                        // hand-over is a cut nobody sees.
                        teaserDone = true
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .overlay(alignment: .topTrailing) {
                        Button("Skip") {
                            withAnimation(.easeInOut(duration: 0.4)) { teaserDone = true }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                    }
                }
            }
        }
    }
}

/// After the teaser: its last frame (the crowd), "Your turn." over it, and
/// the kinds of talk people bring under it.
private struct SpeechWelcomeTurn: View {
    private struct UseCase: Identifiable {
        let symbol: String
        let title: LocalizedStringKey
        var id: String { symbol }
    }

    private let cases = [
        UseCase(symbol: "chart.bar.doc.horizontal", title: "Presentations at work"),
        UseCase(symbol: "lightbulb", title: "Pitches and demos"),
        UseCase(symbol: "person.3", title: "Conference talks"),
        UseCase(symbol: "target", title: "Interviews and exams"),
    ]

    @State private var shown = false

    /// Where the teaser's 1080×1920 frame sits on this screen (aspect fit,
    /// the same as the player), so the text lands on the video's places.
    private func videoRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / 1080, size.height / 1920)
        let w = 1080 * scale, h = 1920 * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    var body: some View {
        GeometryReader { geo in
            let full = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                              height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            let video = videoRect(in: full)
            // "Everyone has a line." sat at y 360 of 1920, 80 px tall.
            let headlineTop = video.minY + video.height * (350 / 1920) - geo.safeAreaInsets.top
            // The crowd's feet are at y 1360 of 1920.
            let casesTop = video.minY + video.height * (1390 / 1920) - geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                Image("SpeechTeaserEnd")
                    .resizable()
                    .scaledToFit()
                    .frame(width: full.width, height: full.height)
                    .offset(x: -geo.safeAreaInsets.leading, y: -geo.safeAreaInsets.top)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Your turn.")
                        .font(.system(size: video.width * 88 / 1080, weight: .regular, design: .serif))
                        .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
                    Text("Bring the script for the talk you have coming up.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.35), value: shown)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .offset(y: max(8, headlineTop))
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 14)
                .animation(.easeOut(duration: 0.55), value: shown)

                VStack(spacing: 14) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        ForEach(Array(cases.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                Image(systemName: item.symbol)
                                    // The teaser's read-along blue.
                                    .foregroundStyle(Color(red: 0.435, green: 0.576, blue: 0.949))
                                    .frame(width: 22)
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 12)
                            .animation(.easeOut(duration: 0.45).delay(0.6 + Double(index) * 0.08), value: shown)
                        }
                    }
                    Text("A prompter that follows your voice. A score for every take.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(1.0), value: shown)
                }
                .padding(.horizontal, 20)
                .offset(y: casesTop)

                VStack {
                    Spacer()
                    NavigationLink {
                        SpeechSignInView()
                    } label: {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .accentProminent()
                    .controlSize(.large)
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(1.1), value: shown)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onAppear { shown = true }
    }
}

/// The teaser (marketing/content/2026-11-14-speech-teaser, cut before its
/// "Coming soon" end card), full screen, no controls, once.
private struct SpeechTeaserPlayer: UIViewRepresentable {
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEnd: onEnd) }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = UIColor(white: 10 / 255, alpha: 1)
        view.playerLayer.videoGravity = .resizeAspect
        guard let url = Bundle.main.url(forResource: "speech_teaser", withExtension: "mp4") else {
            DispatchQueue.main.async { onEnd() }
            return view
        }
        let player = AVPlayer(url: url)
        view.playerLayer.player = player
        context.coordinator.observe(player)
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        coordinator.stop()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        let onEnd: () -> Void
        private var token: NSObjectProtocol?
        init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

        func observe(_ player: AVPlayer) {
            token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem, queue: .main
            ) { [weak self] _ in self?.onEnd() }
        }

        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }
}

/// The second step. An account is needed from the start: the leaderboards
/// carry a name, and every score is read on the server.
struct SpeechSignInView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to start")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your scores and ranks stay on this account.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            Spacer(minLength: 24)
            VStack(spacing: 8) {
                SignInWithAppleButton(
                    onRequest: { auth.configure($0) },
                    onCompletion: { auth.handle(result: $0) }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(Capsule())

                GoogleSignInButton(height: 52) { auth.signInWithGoogle() }

                Text("On nawana already? Sign in the same way and your plan comes with you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                if auth.isWorking { ProgressView().padding(.top, 4) }
                if let err = auth.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
