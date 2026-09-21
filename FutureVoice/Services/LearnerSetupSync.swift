import Foundation
import Supabase

/// What the learner CHOSE in onboarding, mirrored to the server.
///
/// `public.profiles` has had `native_language` / `target_language` /
/// `proficiency` since the first migration and nothing has ever written them:
/// `handle_new_user` inserts `(id)` alone and the three columns take their
/// defaults — `ko` / `en` / `b1`. So on 2026-09-14 all 31 rows read the same
/// three values, and the admin console could only say what somebody had
/// SPOKEN, never what they had picked. Someone who chose German and hadn't
/// talked yet was indistinguishable from someone who chose English, and a
/// console that trusted the column would have reported every learner as an
/// English learner by construction.
///
/// The choice itself happens before there is anywhere to put it: the setup
/// flow (native → target → level) runs ahead of the voice clone, and the
/// anonymous Supabase session only opens at "use this voice". So this is
/// written whenever a session and a completed setup exist at the same time —
/// at setup, at the first session, and once per launch — rather than at the
/// moment of the tap.
///
/// `setup_at` is what separates a real answer from the column default. Null
/// means no build has ever written this row, so the three values are the
/// trigger's and must not be read as a choice.
enum LearnerSetupSync {
    private struct Row: Encodable {
        let id: String
        let native_language: String
        let target_language: String
        let proficiency: String
        let setup_at: String
        let updated_at: String
    }

    /// Skip the round trip when nothing has changed since the last push. The
    /// values change on a language switch or a level move, both rare, so this
    /// is one request per install rather than one per launch.
    private static let lastKey = "futurevoice.profileSync.last"

    /// Mirror the current setup. Silent on every failure — this is a
    /// reporting row, and nothing the learner does may wait on it or fail
    /// because of it.
    @MainActor
    static func push(target: String, native: String,
                     level: CEFRLevel, force: Bool = false) {
        let stamp = "\(target)|\(native)|\(level.rawValue)"
        if !force, UserDefaults.standard.string(forKey: lastKey) == stamp { return }
        Task.detached(priority: .utility) {
            guard let session = try? await SupabaseProvider.shared.auth.session else { return }
            let now = ISO8601DateFormatter().string(from: Date())
            let row = Row(id: session.user.id.uuidString,
                          native_language: native,
                          target_language: target,
                          proficiency: level.rawValue,
                          setup_at: now,
                          updated_at: now)
            do {
                // Upsert, not update: the trigger has already made the row for
                // a signed-up account, but an anonymous session created before
                // this shipped may not have one.
                try await SupabaseProvider.shared
                    .from("profiles")
                    .upsert(row, onConflict: "id")
                    .execute()
                await MainActor.run { UserDefaults.standard.set(stamp, forKey: lastKey) }
            } catch {
                // Next launch tries again; the defaults stay until it lands.
            }
        }
    }
}
