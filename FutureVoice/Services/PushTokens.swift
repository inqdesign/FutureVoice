import Foundation
import os
import Supabase
import UIKit

/// This install's APNs token, and the three facts the server can't work out
/// without it.
///
/// Registering costs the learner nothing and asks them nothing: a device
/// token is not permission, and `UNUserNotificationCenter` is what decides
/// whether anything is ever DRAWN. So this runs for every signed-in account,
/// including one that has refused notifications — the row is then a token
/// that will be sent to and quietly ignored, which is cheaper than having no
/// way to reach someone the day they change their mind.
///
/// What the row carries beyond the token, and why the server can't infer it:
///
/// - **bundle id** — APNs routes by topic, and the dev build is a different
///   topic from the shipped app.
/// - **environment** — a build signed `aps-environment: development` exists
///   ONLY on Apple's sandbox host, a shipped one only on production, and
///   sending to the wrong host fails outright. It is read from the embedded
///   provisioning profile rather than from `#if DEBUG`, because the Release
///   scheme run from Xcode is a release build signed for development — the
///   exact configuration used to check prices on a real phone.
/// - **app language** — chrome follows the language the LEARNER picked, never
///   the device's ("UI text has ONE language", CLAUDE.md), and a push is
///   chrome. The server has no other way to know it.
@MainActor
enum PushTokens {

    /// Same reason `SyncPush` has one: none of this draws anything, so a
    /// token that never reaches the server and a server that never sends
    /// look identical from the outside. One line per upload, and an upload
    /// happens only when something changed.
    private static let log = Logger(subsystem: "com.roro.futurevoice", category: "push-token")

    /// Asks iOS for a token. Idempotent, prompts nothing, and answers through
    /// `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    static func register() {
        log.notice("asking iOS for an APNs token")
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// iOS handed us a token. Uploaded only when something about it CHANGED —
    /// the token is re-delivered on every launch and the row is otherwise
    /// identical, so an unconditional upsert would be a network write per
    /// launch for a value nobody edited.
    static func store(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let bundle = Bundle.main.bundleIdentifier ?? ""
        let language = UILanguage.chromeLanguage
        let environment = apsEnvironment()
        let fingerprint = [token, bundle, environment, language].joined(separator: "|")
        guard UserDefaults.standard.string(forKey: lastUploadedKey) != fingerprint else { return }

        Task {
            guard let userId = try? await SupabaseProvider.shared.auth.session.user.id else { return }
            do {
                try await SupabaseProvider.shared
                    .from("device_tokens")
                    .upsert([
                        "token": token,
                        "user_id": userId.uuidString.lowercased(),
                        "bundle_id": bundle,
                        "environment": environment,
                        "app_language": language,
                        "updated_at": ISO8601DateFormatter().string(from: Date()),
                    ])
                    .execute()
                UserDefaults.standard.set(fingerprint, forKey: lastUploadedKey)
                log.notice("token uploaded (\(environment, privacy: .public), \(language, privacy: .public), \(bundle, privacy: .public))")
            } catch {
                log.notice("token upload failed: \(error.localizedDescription, privacy: .public)")
                // Left unrecorded on purpose: the next launch re-delivers the
                // token and tries again, and a learner who can't be pushed to
                // loses nothing they can see.
            }
        }
    }

    /// Forget what was uploaded, so the next token lands under the new
    /// account. Sign-out only — the ROW is left alone: a shared iPad's other
    /// account may still want it, and Apple's 410 is what reaps a dead token.
    static func forgetUpload() {
        UserDefaults.standard.removeObject(forKey: lastUploadedKey)
    }

    private static let lastUploadedKey = "futurevoice.push.lastUploaded"

    /// Which APNs host this build exists on, read from the profile it was
    /// actually signed with. A build with no embedded profile is a simulator
    /// build, where `#if DEBUG` is the honest answer.
    private static func apsEnvironment() -> String {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>")
        else {
            #if DEBUG
            return "sandbox"
            #else
            return "production"
            #endif
        }
        let plist = String(text[start.lowerBound..<end.upperBound])
        // The profile's own entitlement, read by NAME — a profile is full of
        // <string>s and matching the value alone would be answered by any of
        // them.
        guard let key = plist.range(of: "<key>aps-environment</key>"),
              let open = plist.range(of: "<string>", range: key.upperBound..<plist.endIndex),
              let close = plist.range(of: "</string>", range: open.upperBound..<plist.endIndex)
        else { return "production" }
        return plist[open.upperBound..<close.lowerBound] == "development"
            ? "sandbox" : "production"
    }
}
