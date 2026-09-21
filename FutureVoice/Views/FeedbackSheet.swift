import SwiftUI
import Supabase

/// The ONE feedback modal, asked ONCE: two scores and a sentence, after a call
/// that actually happened, from someone who came back to have it.
///
/// **It used to fire on the first call and the first Watch, and that was the
/// wrong moment twice over** (changed 2026-09-14). It interrupted the single
/// experience the whole product is selling, at the exact second the learner
/// had just done the thing — and it asked for a verdict from someone who had
/// nothing to compare it to. A first impression is not an opinion. What
/// replaced both is one ask at the first moment a learner has actually
/// decided something: they had a call, they left, they CAME BACK, and they
/// have just finished another real one (`FeedbackPrompt.shouldShowReturningTalk`).
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
/// **Stars, on ONE of the three asks** (2026-08-17 removed them, 2026-09-14
/// brought them back for `returningTalk` only). The original objection was
/// about the MOMENT, not the control: a 1–5 row right after someone's very
/// first call reads as an App Store review prompt, and a score given before
/// there is anything to score tells us nothing — a 2 with no sentence is
/// unusable and a 5 hides what felt off. That still holds for the first call
/// and the first Watch, which stay words-only. By the second call on a return
/// visit it doesn't: they have used the thing, and two numbers across many
/// people is the one signal a pile of sentences cannot give. They are asked
/// separately — the APP and the CALLS — because someone can love the calls
/// and find everything around them confusing, which is precisely the feedback
/// worth having, and a single score blurs it.
///
/// Presentation is once-per-milestone, tracked in UserDefaults via
/// `FeedbackPrompt.shouldShow` / `markShown` — callers decide the moment,
/// this file decides the look.
struct FeedbackSheet: View {
    /// The milestone that triggered the ask. Raw values are the `context`
    /// column in `beta_reviews` — never rename one, it would split the
    /// history of a question that didn't change.
    enum Context: String, Identifiable {
        /// A learner who came BACK and had another real call. The only ask
        /// there is — see the type doc for the two it replaced, whose rows
        /// (`first_talk`, `first_watch`) stay in the table under their own
        /// names.
        case returningTalk = "returning_talk"

        var id: String { rawValue }

        var title: String { explain("How is it going so far?") }

        var subtitle: String {
            explain("You've been back for another call. Two quick questions, and anything you want to say.")
        }
    }

    let context: Context

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""
    @State private var appRating = 0
    @State private var callRating = 0
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

                Section {
                    StarRow(title: explain("The app overall"), rating: $appRating)
                    StarRow(title: explain("Talking to your future self"), rating: $callRating)
                }

                Section(explain("Anything you want to say")) {
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
                            .disabled(!canSend)
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

    /// A score on its own is a complete answer, and so is a sentence on its
    /// own. Demanding both is how a form gets neither.
    private var canSend: Bool {
        if !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return appRating > 0 || callRating > 0
    }

    private func submit() async {
        guard let session = try? await SupabaseProvider.shared.auth.session else {
            sendError = explain("You need to be signed in.")
            return
        }
        sending = true
        sendError = nil

        // `rating` is the APP score and `call_rating` the CALLS score; both
        // are omitted when unset (a nil Optional encodes to no key at all, so
        // the column keeps its null). `first_talk` / `first_watch` rows still
        // carry neither, exactly as before.
        struct Row: Encodable {
            let user_id: String
            let context: String
            let body: String
            let rating: Int?
            let call_rating: Int?
            let app_version: String?
            let app_build: String?
        }
        let info = Bundle.main.infoDictionary
        do {
            try await SupabaseProvider.shared
                .from("beta_reviews")     // see the type doc — name kept on purpose
                .insert(Row(
                    user_id: session.user.id.uuidString,
                    context: context.rawValue,
                    body: feedbackText.trimmingCharacters(in: .whitespacesAndNewlines),
                    rating: appRating > 0 ? appRating : nil,
                    call_rating: callRating > 0 ? callRating : nil,
                    app_version: info?["CFBundleShortVersionString"] as? String,
                    app_build: info?["CFBundleVersion"] as? String
                ))
                .execute()
            sent = true
        } catch {
            sendError = explain("Couldn't send — please try again. (\(error.localizedDescription))")
        }
        sending = false
    }
}

/// One line of the rating section: a label and five taps.
///
/// Built from `Button` + SF Symbols rather than a control of its own — the
/// house rule is iOS-native elements only, and a star row has no system
/// control. Tapping the star you already chose clears it: a score given by
/// accident must be takeable back, and both scores are optional.
private struct StarRow: View {
    let title: String
    @Binding var rating: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        rating = (rating == value) ? 0 : value
                    } label: {
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(value <= rating ? AnyShapeStyle(.tint)
                                                             : AnyShapeStyle(.secondary))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value)")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(rating == 0 ? explain("Not rated")
                                        : explain("\(rating) out of 5"))
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

    /// The one moment worth asking a learner what they think: they had a call,
    /// they came BACK, and they have just finished another real one.
    ///
    /// Three conditions, and each rules out a kind of answer that would be
    /// noise:
    ///
    /// - **A minute of call.** Under that nothing happened — an accidental
    ///   tap, a call abandoned on the greeting — and an opinion about it is an
    ///   opinion about nothing. The clock is the call's own elapsed time, the
    ///   figure the screen was showing them.
    /// - **At least their second finished call**, counted across languages
    ///   (the current one is already saved by the time this is asked, so two
    ///   means this one plus an earlier one).
    /// - **They came back.** The first call has to be on an EARLIER DAY than
    ///   today. Two calls in one sitting is still a first impression; coming
    ///   back tomorrow is the first evidence the thing is worth returning to,
    ///   and it is the only point where "how is it going" is a real question.
    ///
    /// Asked once, ever — the same UserDefaults record as the other two.
    static func shouldShowReturningTalk(callSeconds: TimeInterval) -> Bool {
        guard callSeconds >= 60, shouldShow(.returningTalk) else { return false }
        let ended = SessionStore.shared.loadAcrossLanguages()
            .filter { $0.endedAt != nil }
        guard ended.count >= 2,
              let first = ended.min(by: { $0.startedAt < $1.startedAt })
        else { return false }
        return !Calendar.current.isDateInToday(first.startedAt)
    }
}
