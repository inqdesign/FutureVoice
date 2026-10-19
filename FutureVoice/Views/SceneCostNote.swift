import SwiftUI

/// What the next Watch scene costs, said where the button that starts one is
/// (2026-10-19). Since that day a scene costs five minutes of talk time for
/// anyone who subscribes from then on, and a learner must read that before
/// tapping, the same way the Speech voiceover's button shows its price.
///
/// Reads `BillingGate`'s snapshot so it never adds a fetch of its own. Draws
/// nothing until the account is known, and nothing for the admin account.
struct SceneCostNote: View {
    @ObservedObject private var gate = BillingGate.shared

    var body: some View {
        Group {
            if let text = Self.text(gate.account) {
                Label(text, systemImage: "play.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { gate.warm() }
    }

    static func text(_ account: AccountStatus?) -> String? {
        guard let account, !account.unlimited else { return nil }
        if !account.isEntitled {
            // A spent sample answers with the plans at the tap; nothing to say.
            guard let cap = account.freeScenesCap, account.freeScenesUsed < cap else { return nil }
            return explain("Your free scene · it takes no talk time")
        }
        if account.scenesCostTalk {
            // Short of a whole scene: say what it needs before the tap, which
            // answers with the spent-pool sheet.
            if account.sceneTalkShort {
                return [explain("A scene needs \(account.sceneTalkMinutes) min of talk time"),
                        ScriptVoiceover.remainingLabel(account)].compactMap { $0 }.joined(separator: " · ")
            }
            return ScriptVoiceover.priceLine(minutes: account.sceneTalkMinutes, account: account)
        }
        if let cap = account.monthlyScenesCap {
            return explain("\(account.scenesRemaining) of \(cap) scenes left")
        }
        return nil
    }
}
