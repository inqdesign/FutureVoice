import SwiftUI

/// A newer build is out. Two temperaments in one sheet, because the two cases
/// are not the same request:
///
///   * OPTIONAL — a notice. It can be closed, and it is shown once per build
///     (`AppUpdateService.markSeen`). Nagging is how a notice stops being read.
///   * REQUIRED — the server has moved somewhere this build misreports it, so
///     there is no dismiss and no swipe. That is not a growth device; it is
///     reserved for the case that actually happened here, when the billing
///     model changed under builds already on phones and an old client kept
///     describing allowances that no longer existed.
///
/// The notes come from the release notes shipped to the App Store, so they are
/// a paragraph plus a bullet list — not a sentence. They used to be rendered as
/// one centre-aligned block inside a fixed detent, which ran off the top AND
/// the bottom of the sheet on the very first release that had real notes. The
/// body now SCROLLS under a compact header with the buttons pinned below, and
/// the bullets are parsed out (`ReleaseNotes`) so what's new reads as a list of
/// things rather than a wall of prose.
struct UpdateAvailableSheet: View {
    let update: AppUpdateService.AppUpdate
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .medium

    private var notes: ReleaseNotes { ReleaseNotes(update.notes) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        if let lead = notes.lead {
                            Text(lead)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !notes.bullets.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("What's new")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                ForEach(Array(notes.bullets.enumerated()), id: \.offset) { _, line in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 5))
                                            .foregroundStyle(.tint)
                                        Text(line)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 12)
            // A required update carries no notes, so its content is the header
            // alone — top-aligned it leaves a hole above the button. Only ever
            // applied to content that is demonstrably shorter than the sheet;
            // pinning a tall stack to the container height would clip it
            // instead of letting it scroll.
            .centeredWhenShort(notes.isEmpty)
        }
        // Pinned, so the one thing the sheet asks for can never be scrolled
        // off — however long the notes are.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                // Names the store the tap will actually open. A TestFlight
                // install sent to the App Store reads as a broken link, not
                // as an update.
                Button {
                    openURL(AppUpdateService.updateURL)
                } label: {
                    Group {
                        if AppUpdateService.isTestFlight {
                            Text("Open TestFlight")
                        } else {
                            Text("Open the App Store")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // A required update has no way past. Everything else does.
                if !update.required {
                    Button("Later") {
                        onDismiss()
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            // NO background of its own. A sheet's ground is a material, so
            // anything opaque here — a bar, systemBackground — draws a band
            // the eye reads as a second surface pasted under the notes. The
            // button keeps the sheet's own glass, exactly as a toolbar does.
        }
        // A one-line note fits the half sheet; a real release note is a
        // paragraph plus five bullets, and opening THAT at medium puts the
        // list — the part that answers "what changed?" — below the fold.
        .presentationDetents([.medium, .large], selection: $detent)
        .onAppear { detent = notes.bullets.isEmpty ? .medium : .large }
        // Both are set from the same flag so a required sheet can't be escaped
        // by dragging it away — the one gap an `if` around the button leaves.
        .interactiveDismissDisabled(update.required)
        .presentationDragIndicator(update.required ? .hidden : .visible)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: update.required ? "exclamationmark.arrow.circlepath" : "arrow.down.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(update.required ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))

            Text(update.required ? "Update to keep going" : "There's a new version")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(buildLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    /// Always names the build being offered. "A new version is available" with
    /// no number can't be checked against what the App Store then shows.
    private var buildLine: String {
        let current = "\(AppUpdateService.currentVersion) (\(AppUpdateService.currentBuild))"
        guard let latest = update.latestVersion else {
            return explain("Build \(AppUpdateService.currentBuild) → \(update.latestBuild)")
        }
        // Numbers and an arrow: nothing here to translate.
        return "\(current) → \(latest) (\(update.latestBuild))"
    }
}

/// Release notes as written for the App Store: a paragraph, then a dash list.
/// Splitting them lets the sheet lay the list out as rows instead of letting a
/// hyphen wrap into the middle of a centred block.
struct ReleaseNotes {
    let lead: String?
    let bullets: [String]

    var isEmpty: Bool { lead == nil && bullets.isEmpty }

    init(_ raw: String?) {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lead = nil
            bullets = []
            return
        }

        var leadLines: [String] = []
        var items: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                // A blank line inside the lead is a paragraph break; keep it,
                // but never let it open the block with one.
                if !leadLines.isEmpty, items.isEmpty { leadLines.append("") }
                continue
            }
            if let marker = ["- ", "• ", "· ", "* "].first(where: { trimmed.hasPrefix($0) }) {
                items.append(String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
            } else if items.isEmpty {
                leadLines.append(trimmed)
            } else {
                // Prose after the list is a wrapped bullet, not a new section.
                items[items.count - 1] += " " + trimmed
            }
        }

        let joined = leadLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        lead = joined.isEmpty ? nil : joined
        bullets = items
    }
}

#Preview("Optional") {
    Text("host").sheet(isPresented: .constant(true)) {
        UpdateAvailableSheet(update: .init(latestBuild: 26, latestVersion: "1.0",
                                           notes: """
                                           nawana를 시작합니다.

                                           말이 늘지 않는 이유는 하나 — 충분히 말하지 않아서예요. 60초 녹음으로 유창해진 미래의 내 목소리를 만들고, 매일 통화하세요.

                                           - 내 관심사에서 시작하는 매일 통화
                                           - 매 턴 돌아오는 유창한 버전
                                           - 통화가 끝나면 자동으로 만들어지는 나만의 교재
                                           - 내 목소리로 하는 섀도잉, 입으로 답하는 복습
                                           - 실제로 말한 것들로만 측정되는 레벨
                                           """,
                                           required: false), onDismiss: {})
    }
}

#Preview("Required") {
    Text("host").sheet(isPresented: .constant(true)) {
        UpdateAvailableSheet(update: .init(latestBuild: 15, latestVersion: "1.0.1",
                                           notes: nil, required: true), onDismiss: {})
    }
}

private extension View {
    @ViewBuilder
    func centeredWhenShort(_ active: Bool) -> some View {
        if active {
            containerRelativeFrame(.vertical, alignment: .center)
        } else {
            self
        }
    }
}
