import SwiftUI
import UIKit

/// "Invite & talk time": what this account can still speak, the code to share,
/// and — only for an account that never used one — a box to enter a friend's
/// code.
///
/// The code's real home is the Welcome screen: `WelcomeView` captures it
/// before sign-in and `AuthService.redeemPendingInviteIfAny` redeems it the
/// moment there's a session. This page's box exists for the one case that
/// misses, someone who signed up first and was given a code afterwards — so
/// it disappears once a code has been used, instead of asking a settled
/// account for something it can no longer do.
struct InviteView: View {
    @State private var referral = ReferralStatus.empty
    @State private var account = AccountStatus.empty
    @State private var codeInput = ""
    @State private var redeeming = false
    @State private var redeemMessage: String?
    @State private var redeemError: String?
    @State private var loaded = false

    private var bonusMinutes: Int { ReferralService.bonusMinutes }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Talk time", systemImage: "bolt.fill")
                    Spacer()
                    Text(account.talkTimeLabel)
                        .font(.subheadline).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } footer: {
                // Invite minutes are spent BEFORE the plan's monthly pool
                // (20260821100000), so a subscriber sees them immediately —
                // this line used to have to apologise that they wouldn't.
                Text(account.isEntitled
                     ? explain("Invite minutes are used before your monthly time, so they come off the top. Reviewing is always free.")
                     : explain("Minutes buy talk time with your fluent self. Reviewing is always free."))
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
                    // The LINK is the item and the sentence rides along as the
                    // message: shared that way the recipient gets a tappable
                    // App Store card, not a paragraph they have to act on.
                    ShareLink(item: ReferralService.appStoreURL,
                              subject: Text("nawana"),
                              message: Text(shareText(code))) {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                    }
                    HStack {
                        Label("Friends joined", systemImage: "person.2.fill")
                        Spacer()
                        Text("\(referral.invitesUsed) / \(ReferralService.rewardedInviteCap)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    HStack { Text("Your code"); Spacer(); ProgressView() }
                }
            } header: {
                Text("Your invite code")
            } footer: {
                Text(explain("Your friend enters this code when they sign up, and you both get \(bonusMinutes) minutes. You're rewarded for your first \(ReferralService.rewardedInviteCap) friends."))
            }

            if let joined = referral.redeemedCode {
                Section {
                    HStack {
                        Label("Joined with a code", systemImage: "checkmark.seal.fill")
                        Spacer()
                        Text(joined)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(explain("A code counts once per account, so this one is done."))
                }
            } else {
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
                    Text("Didn't use a code when you signed up?")
                } footer: {
                    Text(explain("Enter it here instead — \(bonusMinutes) minutes, once."))
                }
            }
        }
        .navigationTitle("Invite & talk time")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !loaded { loaded = true; await reload() }
        }
    }

    private func shareText(_ code: String) -> String {
        explain("I'm practicing speaking with my own AI voice on nawana. Enter my code \(code) when you sign up and we both get \(bonusMinutes) minutes of talk time.")
    }

    private func reload() async {
        referral = await ReferralService.fetchMine()
        account = await AccountStatus.fetch()
    }

    private func redeem() async {
        redeeming = true
        redeemError = nil
        redeemMessage = nil
        defer { redeeming = false }
        do {
            let result = try await ReferralService.redeem(code: codeInput)
            redeemMessage = result.isComp
                ? explain("Redeemed — \(AccountStatus.tierName(result.compPlanId)) is on your account.")
                : explain("Redeemed — \(bonusMinutes) minutes added.")
            codeInput = ""
            await reload()
        } catch let err as ReferralService.RedeemError {
            redeemError = err.errorDescription
        } catch {
            redeemError = explain("Couldn't redeem that code.")
        }
    }
}
