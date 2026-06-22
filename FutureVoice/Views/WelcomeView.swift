import AuthenticationServices
import SwiftUI

/// First screen — a swipeable feature carousel that shows what the app does,
/// with Sign in with Apple pinned below so the user can start any time. No
/// separate sign-in page.
struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0
    @State private var autoplay = true

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
    }

    private static let features: [Feature] = [
        Feature(icon: "person.wave.2.fill",
                title: "Talk with a fluent you",
                subtitle: "Real conversations in your own voice — fluent, natural, unmistakably you."),
        Feature(icon: "person.2.wave.2.fill",
                title: "Watch yourself with real people",
                subtitle: "See your fluent self handle real moments with the actual people in your life."),
        Feature(icon: "waveform.badge.mic",
                title: "Make the words yours",
                subtitle: "Shadow the exact expressions in your own voice, at any speed, until they stick."),
        Feature(icon: "sparkles",
                title: "AI that targets your gaps",
                subtitle: "Every conversation is analyzed into the precise corrections and phrases you need next.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(Self.features.enumerated()), id: \.offset) { i, f in
                    featurePage(f).tag(i)
                }
            }
            // Built-in dots render a white active dot on light backgrounds
            // (invisible), so we draw our own with explicit colors.
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Any manual swipe stops auto-play — the user is driving now.
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in autoplay = false })

            pageDots
                .padding(.top, 4)
                .padding(.bottom, 8)

            signInArea
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task {
            // Auto-advance the carousel until the user takes over.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if !autoplay { break }
                withAnimation(.easeInOut(duration: 0.5)) {
                    page = (page + 1) % Self.features.count
                }
            }
        }
    }

    private func featurePage(_ f: Feature) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 124, height: 124)
                Image(systemName: f.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
            }
            Text(f.title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            Text(f.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
            Spacer()
            Spacer()   // bias content above the page dots
        }
        .frame(maxWidth: .infinity)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Self.features.indices, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == page ? 20 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
    }

    private var signInArea: some View {
        VStack(spacing: 8) {
            SignInWithAppleButton(
                onRequest: { request in auth.configure(request) },
                onCompletion: { result in auth.handle(result: result) }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(Capsule())
            .padding(.horizontal, 32)

            if auth.isWorking {
                ProgressView().padding(.top, 4)
            }
            if let err = auth.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }
}
