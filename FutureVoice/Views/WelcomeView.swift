import AuthenticationServices
import SwiftUI

/// First screen — a swipeable, auto-playing carousel that shows the app's value
/// through small animated mockups of the real UI (not generic icons), with a
/// pill Sign in with Apple pinned below.
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
                subtitle: "Real conversations in your own voice — fluent, natural, unmistakably you."),
        Feature(title: "Watch yourself with real people",
                subtitle: "See your fluent self handle real moments with the actual people in your life."),
        Feature(title: "Make the words yours",
                subtitle: "Shadow the exact expressions in your own voice, at any speed, until they stick."),
        Feature(title: "AI that targets your gaps",
                subtitle: "Every conversation is analyzed into the precise corrections and phrases you need next.")
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
        .background(Color(.systemBackground).ignoresSafeArea())
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
        VStack(spacing: 28) {
            Spacer()
            mock(i)
                .frame(height: 250)
            VStack(spacing: 12) {
                Text(f.title)
                    .font(.system(size: 26, weight: .bold))
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
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mockups (animated, real-UI-flavored)

    @ViewBuilder
    private func mock(_ i: Int) -> some View {
        switch i {
        case 0: talkMock
        case 1: watchMock
        case 2: shadowMock
        default: analysisMock
        }
    }

    private var talkMock: some View {
        card {
            Text("Free talk").font(.caption2).foregroundStyle(.secondary)
            chatBubble("So — how'd the launch go?", mine: false, label: "Future self")
            chatBubble("Honestly? It went really well.", mine: true, label: "You")
            chatBubble("That's huge. What surprised you most?", mine: false, label: "Future self")
        }
    }

    private var watchMock: some View {
        card {
            HStack(spacing: 10) {
                avatar("Y", "You")
                Image(systemName: "arrow.left.arrow.right").font(.caption).foregroundStyle(.secondary)
                avatar("S", "Sarah")
                Spacer()
            }
            .padding(.bottom, 2)
            chatBubble("Wait — it's been forever!", mine: false, label: "Sarah")
            chatBubble("I know! Let's actually catch up.", mine: true, label: "You")
        }
    }

    private var shadowMock: some View {
        card {
            Text("Target line").font(.caption2).foregroundStyle(.secondary)
            (Text("I really ")
             + Text("appreciate").foregroundColor(.accentColor)
             + Text(" your help."))
                .font(.subheadline.weight(.semibold))

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)).frame(height: 34)
                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.2))
                        .frame(width: w * 0.34, height: 34).offset(x: w * 0.33)
                    ForEach(0..<10, id: \.self) { k in
                        Rectangle().fill(Color.secondary.opacity(0.3))
                            .frame(width: 1.5, height: 12).offset(x: w * (0.06 + Double(k) * 0.092))
                    }
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        // Sawtooth: sweep forward across the loop region, then
                        // jump back to the start and repeat (looping playback).
                        let p = (t / 2.2).truncatingRemainder(dividingBy: 1.0)
                        let frac = 0.33 + p * 0.34
                        Capsule().fill(Color.primary).frame(width: 2.5, height: 40)
                            .offset(x: w * frac)
                    }
                }
                .frame(height: 34)
            }
            .frame(height: 34)

            HStack(spacing: 14) {
                Label("0.75×", systemImage: "gauge.with.dots.needle.50percent")
                Label("Loop", systemImage: "repeat")
            }
            .font(.caption2).foregroundStyle(.tint)
        }
    }

    private var analysisMock: some View {
        card {
            HStack {
                Text("Last talk").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("78").font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(.green)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            }
            Text("What to work on").font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.right.circle.fill").font(.footnote).foregroundStyle(.orange).padding(.top, 1)
                (Text("make a interview ").strikethrough().foregroundColor(.secondary)
                 + Text("do an interview").foregroundColor(.primary))
                    .font(.subheadline)
            }
            VStack(spacing: 7) {
                axisRow("Vocabulary", 82)
                axisRow("Grammar", 71)
                axisRow("Fluency", 68)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Mock building blocks

    @ViewBuilder
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(width: 300, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }

    /// Real chat-bubble: counterpart on the left (gray), you on the right
    /// (accent) — iMessage-style, for the marketing mock only.
    private func chatBubble(_ text: String, mine: Bool, label: String) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(mine ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(mine ? Color.accentColor : Color(.tertiarySystemFill))
                )
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private func axisRow(_ name: String, _ score: Int) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(Color(.tertiarySystemFill))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor)
                            .frame(width: g.size.width * CGFloat(score) / 100)
                    }
            }
            .frame(height: 5)
            Text("\(score)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
        }
    }

    private func avatar(_ initial: String, _ name: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 44, height: 44)
                Text(initial).font(.headline).foregroundStyle(.tint)
            }
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
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

