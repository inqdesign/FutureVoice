import SwiftUI
import UIKit

/// Beta "invite & credits" screen: your remaining quota, your shareable code,
/// and a box to redeem a friend's code. No subscription during beta — credits
/// come from the starting grant and from inviting people.
struct InviteView: View {
    @State private var referral = ReferralStatus.empty
    @State private var balance = 0
    @State private var codeInput = ""
    @State private var redeeming = false
    @State private var redeemMessage: String?
    @State private var redeemError: String?
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Talk time left", systemImage: "bolt.fill")
                    Spacer()
                    Text("\(Int(Double(balance) / AccountStatus.creditsPerMinute)) min")
                        .font(.headline).monospacedDigit()
                        .foregroundStyle(balance > 0 ? Color.primary : Color.orange)
                }
            } footer: {
                Text(explain("Minutes are talk time with your fluent self. There's no subscription during the beta — invite friends to earn more."))
            }

            Section {
                if let code = referral.code {
                    HStack {
                        Text(code)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .tracking(3)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    ShareLink(item: shareText(code)) {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                    }
                    HStack {
                        Label("Friends joined", systemImage: "person.2.fill")
                        Spacer()
                        Text("\(referral.invitesUsed) / 10")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    HStack { Text("Your code"); Spacer(); ProgressView() }
                }
            } header: {
                Text("Your invite code")
            } footer: {
                Text(explain("You and your friend each get about an hour of talk time when they join with your code — for up to 10 friends."))
            }

            Section {
                TextField("Enter invite code", text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Button {
                    Task { await redeem() }
                } label: {
                    HStack {
                        Text("Redeem")
                        if redeeming { Spacer(); ProgressView() }
                    }
                }
                .disabled(redeeming || codeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if let m = redeemMessage {
                    Label(m, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.footnote)
                }
                if let e = redeemError {
                    Label(e, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.footnote)
                }
            } header: {
                Text("Have a code?")
            } footer: {
                Text(explain("Enter a friend's code once for about an hour of bonus talk time."))
            }
        }
        .navigationTitle("Invite & talk time")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !loaded { loaded = true; await reload() }
        }
    }

    private func shareText(_ code: String) -> String {
        "I'm practicing speaking with my own AI voice on nawana. Join with my code \(code) and we both get bonus talk time."
    }

    private func reload() async {
        referral = await ReferralService.fetchMine()
        balance = await AccountStatus.fetch().creditBalance
    }

    private func redeem() async {
        redeeming = true
        redeemError = nil
        redeemMessage = nil
        defer { redeeming = false }
        do {
            balance = try await ReferralService.redeem(code: codeInput)
            redeemMessage = "Redeemed — about an hour of talk time added."
            codeInput = ""
            referral = await ReferralService.fetchMine()
        } catch let err as ReferralService.RedeemError {
            redeemError = err.errorDescription
        } catch {
            redeemError = "Couldn't redeem that code."
        }
    }
}
