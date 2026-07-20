import AuthenticationServices
import SwiftUI

/// First screen — a swipeable, auto-playing carousel that shows the app's value
/// through previews built from the SAME components the real screens use (the
/// VoiceGlow dialer orb, the plain transcript feed, the shadow karaoke
/// timeline, the CEFR level equalizer) — not generic icons or chat bubbles.
/// A pill Sign in with Apple is pinned below.
struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0
    @State private var autoplay = true
    @State private var showInvite = false
    @State private var inviteCode = ""

    private struct Feature: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
    }

    private static let features: [Feature] = [
        Feature(title: "Talk with a fluent you",
                subtitle: "Call your fluent self and just talk — real conversations in your own voice, fluent and unmistakably you."),
        Feature(title: "Watch real situations play out",
                subtitle: "Scenes built from your life and interests — watch, then master every word, expression, and line inside."),
        Feature(title: "Make the words yours",
                subtitle: "Shadow the exact lines in your own voice, at any speed, until they stick."),
        Feature(title: "Grow your word world",
                subtitle: "Every word you speak joins your cloud — tap any one for its meaning and examples.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(Self.features.enumerated()), id: \.offset) { i, f in
                    featurePage(i, f).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in autoplay = false })

            pageDots
                .padding(.top, 4)
                .padding(.bottom, 8)

            signInArea
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_500_000_000)
                if !autoplay { break }
                withAnimation(.easeInOut(duration: 0.5)) {
                    page = (page + 1) % Self.features.count
                }
            }
        }
    }

    private func featurePage(_ i: Int, _ f: Feature) -> some View {
        // One centered column per slide: a fixed-height hero area so the copy
        // never jumps between slides during autoplay, then title + subtitle.
        // maxHeight centers the whole group — no top-heavy void below.
        VStack(spacing: 32) {
            mock(i)
                .frame(height: 440)
                .frame(maxWidth: .infinity)
            VStack(spacing: 12) {
                Text(f.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                Text(f.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mockups — real screenshots of the actual app screens

    /// Each slide is a genuine screenshot of the live screen (captured via the
    /// DEBUG capture harness), shown in a phone frame — not a reconstruction.
    /// welcome_talk · welcome_watch · welcome_shadow · welcome_vocab.
    private static let shots = ["welcome_talk", "welcome_watch", "welcome_shadow", "welcome_vocab"]

    private func mock(_ i: Int) -> some View {
        phoneShot(Self.shots[i])
    }

    /// A real screen screenshot inside a simple phone frame — thin dark bezel,
    /// rounded corners, soft drop shadow. The image is the actual app.
    private func phoneShot(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 35, style: .continuous)
                    .fill(Color(.label).opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 35, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }

    // MARK: - Page dots + sign in

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
                onRequest: { request in
                    // Capture the invite code at the sign-in moment so it's
                    // redeemed as soon as the session lands.
                    savePendingInvite()
                    auth.configure(request)
                },
                onCompletion: { result in auth.handle(result: result) }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(Capsule())
            .padding(.horizontal, 32)

            inviteArea

            if auth.isWorking { ProgressView().padding(.top, 4) }
            if let err = auth.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var inviteArea: some View {
        if showInvite {
            VStack(spacing: 6) {
                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                    .padding(.horizontal, 32)
                    .onChange(of: inviteCode) { _, _ in savePendingInvite() }
                Text("You'll both get 500 credits when you sign in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } else {
            Button("Have an invite code?") {
                withAnimation { showInvite = true }
            }
            .font(.footnote).foregroundStyle(.tint)
            .padding(.top, 2)
        }
    }

    private func savePendingInvite() {
        let clean = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.isEmpty {
            UserDefaults.standard.removeObject(forKey: AuthService.pendingInviteKey)
        } else {
            UserDefaults.standard.set(clean, forKey: AuthService.pendingInviteKey)
        }
    }
}
