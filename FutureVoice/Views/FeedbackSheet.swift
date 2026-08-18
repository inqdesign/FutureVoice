import SwiftUI
import Supabase

/// The ONE feedback modal — shown at milestone moments (first conversation
/// ended, first Watch listen-through), always the same shape so it's instantly
/// recognisable: the question, a text box, send.
///
/// **Named for the beta until 2026-08-18, kept for the public build.** Asking
/// someone what felt off right after their first call is worth as much at
/// launch as it was in testing — what had to go was the word "beta", which
/// told a paying user they'd wandered into someone else's test. Two things
/// deliberately did NOT get renamed with it:
///
/// - **The `beta_reviews` table.** Nobody sees a table name, and renaming it
///   means a migration that has to land in production BEFORE the build does —
///   ship them out of order and every piece of feedback is silently dropped
///   on insert. Not a trade worth making for a cosmetic rename.
/// - **The `futurevoice.betaFeedback.*` UserDefaults keys.** They're the
///   record of who has already been asked. New keys would read as "never
///   asked" and re-prompt every existing user on their next call.
///
/// **No star row** (removed 2026-08-17). A 1–5 row right after the first call
/// reads like an App Store review prompt, and a score is the one answer that
/// tells us nothing actionable while the product is still stabilising — a 2
/// with no sentence is unusable, and a 5 hides the thing that felt off. What
/// we need is the sentence. The `rating` column is nullable, so rows simply
/// carry no score; bringing stars back is a UI-only change.
///
/// Presentation is once-per-milestone, tracked in UserDefaults via
/// `FeedbackPrompt.shouldShow` / `markShown` — callers decide the moment,
/// this file decides the look.
struct FeedbackSheet: View {
    /// The milestone that triggered the ask. Raw values are the `context`
    /// column in `beta_reviews` — never rename one, it would split the
    /// history of a question that didn't change.
    enum Context: String, Identifiable {
        case firstTalk = "first_talk"
        case firstWatch = "first_watch"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .firstTalk:  return explain("How was your first conversation?")
            case .firstWatch: return explain("How was your first Watch?")
            }
        }

        var subtitle: String {
            switch self {
            case .firstTalk:
                return explain("You just talked with your future voice. What felt right — and what felt off?")
            case .firstWatch:
                return explain("You just heard yourself handle a real situation. Did it sound like you?")
            }
        }
    }

    let context: Context

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.title)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(context.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }

                Section("Your feedback") {
                    TextEditor(text: $feedbackText)
                        .frame(minHeight: 110)
                }

                if let sendError {
                    Section {
                        Label(sendError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await submit() } }
                            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(sending)
            .alert("Thank you", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: {
                Text(explain("Your feedback goes straight to the person building this."))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        guard let session = try? await SupabaseProvider.shared.auth.session else {
            sendError = explain("You need to be signed in.")
            return
        }
        sending = true
        sendError = nil

        // No `rating` — the column is nullable and the sheet no longer asks
        // for a score (see the type doc).
        struct Row: Encodable {
            let user_id: String
            let context: String
            let body: String
        }
        do {
            try await SupabaseProvider.shared
                .from("beta_reviews")     // see the type doc — name kept on purpose
                .insert(Row(
                    user_id: session.user.id.uuidString,
                    context: context.rawValue,
                    body: feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                .execute()
            sent = true
        } catch {
            sendError = explain("Couldn't send — please try again. (\(error.localizedDescription))")
        }
        sending = false
    }
}

/// Once-per-milestone bookkeeping. Callers check `shouldShow` at the moment
/// the milestone completes, then `markShown` before presenting.
enum FeedbackPrompt {
    /// Key prefix is the beta-era one on purpose — it's the record of who has
    /// already been asked, and a new prefix would re-prompt everyone.
    private static func key(_ c: FeedbackSheet.Context) -> String {
        "futurevoice.betaFeedback.\(c.rawValue)"
    }

    static func shouldShow(_ c: FeedbackSheet.Context) -> Bool {
        !UserDefaults.standard.bool(forKey: key(c))
    }

    static func markShown(_ c: FeedbackSheet.Context) {
        UserDefaults.standard.set(true, forKey: key(c))
    }
}
