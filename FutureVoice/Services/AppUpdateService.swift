import Foundation

/// Whether this install is behind, and how badly.
///
/// The comparison is on BUILD NUMBER, never the version string. The string is
/// a label the team moves for its own reasons — it went 1.1.0 → 1.0 on
/// 2026-08-21 when the first public release was renamed — while the build
/// number is the one value App Store Connect forces upward on every upload.
/// Comparing labels would have told every 1.1.0 tester they were ahead of the
/// build that actually replaced theirs.
@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    /// Set when there is something to say. Nil the rest of the time, which is
    /// almost always — this must never be a screen people learn to dismiss.
    @Published var pending: AppUpdate?

    /// The last build we already showed the optional sheet for. An optional
    /// update is worth saying ONCE; saying it every launch is how a notice
    /// becomes furniture people tap past without reading.
    private static let seenKey = "futurevoice.updateSeenBuild"

    private var checked = false

    /// The app's own App Store page. The numeric id is Apple's (`6792794655`),
    /// permanent per app, and the same one `apple-webhook` verifies production
    /// notifications against. Lives here rather than beside the invite code
    /// that first needed it: the link is about the App Store, not invites.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6792794655")!

    /// The same app, on its TestFlight page. `itms-beta://` is the scheme
    /// TestFlight registers; the path is Apple's per-app beta endpoint keyed
    /// by the same numeric id, so it needs no public-link code to exist.
    static let testFlightURL = URL(string: "itms-beta://beta.itunes.apple.com/v1/app/6792794655")!

    /// Whether THIS install came from TestFlight. A TestFlight build carries
    /// a sandbox receipt (`sandboxReceipt`) where an App Store build carries a
    /// production one. Debug builds read the same way and that is fine: they
    /// are ours, and the sheet is about where a newer build lives.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Where a newer build of THIS install is found. The sheet sent every
    /// tester to the App Store while the app was still in beta — a page that
    /// either did not exist or showed a build older than the one they had —
    /// so beta users read the button as a bug. A TestFlight install updates
    /// in TestFlight; an App Store install updates in the App Store.
    static var updateURL: URL { isTestFlight ? testFlightURL : appStoreURL }

    struct AppUpdate: Identifiable, Equatable {
        let latestBuild: Int
        let latestVersion: String?
        let notes: String?
        /// The server says this build can no longer be trusted to describe it.
        /// The sheet then has no dismiss — see `UpdateAvailableSheet`.
        let required: Bool
        var id: Int { latestBuild }
    }

    /// This install's build number. `CFBundleVersion` is a string in the
    /// plist and an integer everywhere it matters.
    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Asked once per launch, from the foreground. Silent on every failure:
    /// an update notice is the least important thing the app does, and a
    /// network blip must never produce a wrong claim about the build someone
    /// is running.
    func check() async {
        guard !checked else { return }
        checked = true

        struct Row: Decodable {
            let latest_build: Int
            let latest_testflight_build: Int?
            let min_build: Int
            let latest_version: String?
            let notes_ko: String?
            let notes_en: String?
        }
        guard let rows: [Row] = try? await SupabaseProvider.shared
            .from("app_release")
            .select("latest_build,latest_testflight_build,min_build,latest_version,notes_ko,notes_en")
            .eq("platform", value: "ios")
            .limit(1)
            .execute()
            .value,
              let row = rows.first else { return }

        let build = Self.currentBuild
        // A build of 0 means the plist couldn't be read at all. Treat that as
        // "can't tell" rather than "hopelessly old" — locking someone out on a
        // failed lookup is the one outcome worse than a missed notice.
        guard build > 0 else { return }

        // The build this install can actually GO AND GET. A TestFlight
        // install updates from TestFlight, which has every upload; an App
        // Store install can only ever get what App Review has released —
        // `latest_build`, written by `beta.sh released` after the fact.
        // Reading the upload number for both told every App Store user
        // about a version the store didn't have yet (2026-09-11).
        let latest = Self.isTestFlight
            ? max(row.latest_testflight_build ?? 0, row.latest_build)
            : row.latest_build

        let required = build < row.min_build
        guard required || build < latest else { return }

        if !required, UserDefaults.standard.integer(forKey: Self.seenKey) >= latest {
            return
        }

        let notes = LanguageCatalog.currentNative.hasPrefix("ko") ? row.notes_ko : row.notes_en
        pending = AppUpdate(latestBuild: latest,
                            latestVersion: row.latest_version,
                            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                            required: required)
    }

    /// Remember an optional notice as said. A REQUIRED one is never recorded —
    /// there is nothing to remember, because it must come back.
    func markSeen(_ update: AppUpdate) {
        guard !update.required else { return }
        UserDefaults.standard.set(update.latestBuild, forKey: Self.seenKey)
    }
}
