import SwiftUI
import AuthenticationServices
import AVFoundation

/// The first screen (2026-11-16, founder): the teaser plays (each person
/// with their challenge's category, saying their opening), and as everyone
/// gathers at the end, "Your turn." and the button come in under them at the
/// same moment (the crowd stays where the video draws it; founder: no
/// slide). From then on only the crowd's band of the video shows, so the
/// teaser's own end line ("Everyone has a line.") never appears while the
/// video and its sound play to the end; then the page's still takes over in
/// the same place. Aimed at people who speak in
/// public for work, and at anyone with a talk coming up.
struct SpeechWelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage { case teaser, gathering, page }
    @State private var stage: Stage = .teaser

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let screen = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                                    height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
                // Where the video (aspect fit) draws the still's y 340, the
                // top of the page's crowd band, so the crowd never moves.
                let fit = min(screen.width / 720, screen.height / 1280)
                let bandTop = (screen.height - 1280 * fit) / 2 + 340 * fit - geo.safeAreaInsets.top
                ZStack {
                    // The teaser's own ground (black under its film grain),
                    // so the video has no visible frame.
                    Color(white: 10 / 255).ignoresSafeArea()
                    if stage != .page && !reduceMotion {
                        SpeechTeaserPlayer(
                            onGather: { stage = .gathering },
                            onHandOff: { stage = .page }
                        )
                        // Once the crowd gathers, only its band shows (faded
                        // like the page's still): the teaser's own end line
                        // sits above it and never appears, while the video
                        // and its sound play to the end.
                        .mask(alignment: .top) {
                            if stage == .teaser {
                                Color.black
                            } else {
                                SpeechWelcomeTurn.bandMask
                                    .frame(width: 720 * fit, height: 600 * fit)
                                    .padding(.top, (screen.height - 1280 * fit) / 2 + 340 * fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }
                    // Above the video: its ground is transparent, so the
                    // text comes in under the gathering crowd.
                    SpeechWelcomeTurn(
                        textShown: stage != .teaser || reduceMotion,
                        crowdShown: stage == .page || reduceMotion,
                        crowdTop: max(0, bandTop),
                        crowdWidth: 720 * fit
                    )
                    if stage == .teaser && !reduceMotion {
                        Button("Skip") {
                            withAnimation(.easeInOut(duration: 0.4)) { stage = .page }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }
        }
    }
}

/// The page (2026-11-16, founder: the first cut was "too bad"): the crowd
/// from the teaser's last frame where the video drew it, "Your turn." right
/// under it, one line on what it is for and one on what it does, and the
/// button at the bottom. The four use-case cards were cut; the subtitle
/// already says it.
private struct SpeechWelcomeTurn: View {
    let textShown: Bool
    let crowdShown: Bool
    /// Where the video draws its crowd, so the still takes over in place.
    let crowdTop: CGFloat
    let crowdWidth: CGFloat

    /// The band's fade, shared with the video's mask so the hand-off from
    /// the playing video to the still has the same edges.
    static var bandMask: LinearGradient {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.14),
            .init(color: .black, location: 0.93),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// The crowd's band in the 720×1280 still (y 340–940), faded at its top
    /// and bottom so the frame's film grain never shows an edge.
    private var crowd: some View {
        Color.clear
            .aspectRatio(720 / 600, contentMode: .fit)
            .overlay {
                Image("SpeechTeaserEnd")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .mask(Self.bandMask)
            .accessibilityHidden(true)
    }

    var body: some View {
        VStack(spacing: 0) {
            crowd
                // Exactly the video's size: left to the stack, the band
                // shrank to fit and the hand-off read as the picture shrinking.
                .frame(width: crowdWidth, height: crowdWidth * 600 / 720)
                .layoutPriority(1)
                .padding(.top, crowdTop)
                // Takes over from the video in the same place: no fade.
                .opacity(crowdShown ? 1 : 0)

            VStack(spacing: 10) {
                Text("Your turn.")
                    .font(.system(size: 48, weight: .regular, design: .serif))
                    .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
                Text("Bring the script for the talk you have coming up.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("A prompter that follows your voice. A score for every take.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .opacity(textShown ? 1 : 0)
            .offset(y: textShown ? 0 : 12)
            .animation(.easeOut(duration: 0.7).delay(0.4), value: textShown)

            Spacer(minLength: 24)

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
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .opacity(textShown ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(1.0), value: textShown)
            .allowsHitTesting(textShown)
        }
    }
}

/// The teaser (marketing/content/2026-11-14-speech-teaser), full screen,
/// no controls, once. Its crowd gathers from 22.1 s and is whole at 24.2 s;
/// it plays to its end (26.6 s) so the sound is never cut, and the page hides
/// everything but the crowd from the gathering on.
private struct SpeechTeaserPlayer: UIViewRepresentable {
    let onGather: () -> Void
    let onHandOff: () -> Void

    static let gatherAt = 22.1

    func makeCoordinator() -> Coordinator { Coordinator(onGather: onGather, onHandOff: onHandOff) }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        // Transparent: the page's ground is the screen's, so moving the video
        // never shows its edge.
        view.backgroundColor = .clear
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.videoGravity = .resizeAspect
        guard let url = Bundle.main.url(forResource: "speech_teaser", withExtension: "mp4") else {
            DispatchQueue.main.async { onGather(); onHandOff() }
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
        let onGather: () -> Void
        let onHandOff: () -> Void
        private weak var player: AVPlayer?
        private var boundary: Any?
        private var endToken: NSObjectProtocol?
        private var gathered = false
        private var handedOff = false

        init(onGather: @escaping () -> Void, onHandOff: @escaping () -> Void) {
            self.onGather = onGather
            self.onHandOff = onHandOff
        }

        func observe(_ player: AVPlayer) {
            self.player = player
            let at = [NSValue(time: CMTime(seconds: SpeechTeaserPlayer.gatherAt, preferredTimescale: 600))]
            boundary = player.addBoundaryTimeObserver(forTimes: at, queue: .main) { [weak self] in
                self?.gather()
            }
            endToken = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem, queue: .main
            ) { [weak self] _ in self?.handOff() }
        }

        private func gather() {
            guard !gathered else { return }
            gathered = true
            onGather()
        }

        private func handOff() {
            gather()
            guard !handedOff else { return }
            handedOff = true
            onHandOff()
        }

        func stop() {
            if let boundary { player?.removeTimeObserver(boundary) }
            boundary = nil
            if let endToken { NotificationCenter.default.removeObserver(endToken) }
            endToken = nil
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
