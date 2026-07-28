import SwiftUI
import Supabase

/// The ONE beta feedback modal — shown at milestone moments (first
/// conversation ended, first Watch listen-through, credits depleted), always
/// the same shape so testers learn it instantly: a star row, a text box,
/// send. Writes to `beta_reviews` with the milestone as `context`.
///
/// Presentation is once-per-milestone, tracked in UserDefaults via
/// `BetaFeedback.shouldShow` / `markShown` — callers decide the moment,
/// this file decides the look.
struct BetaFeedbackSheet: View {
    enum Context: String, Identifiable {
        case firstTalk = "first_talk"
        case firstWatch = "first_watch"
        case creditsDepleted = "credits_depleted"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .firstTalk:       return "How was your first conversation?"
            case .firstWatch:      return "How was your first Watch?"
            case .creditsDepleted: return "You've used all your beta credits"
            }
        }

        var subtitle: String {
            switch self {
            case .firstTalk:
                return "You just talked with your future voice. What felt right — and what felt off?"
            case .firstWatch:
                return "You just heard yourself handle a real situation. Did it sound like you?"
            case .creditsDepleted:
                return "That means you really tested it — thank you. Before anything else: what should we fix first?"
            }
        }
    }

    let context: Context

    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
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

                Section("Rating") {
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                rating = star
                            } label: {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(star <= rating ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
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
                Text("Your feedback goes straight to the person building this.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        guard let session = try? await SupabaseProvider.shared.auth.session else {
            sendError = "You need to be signed in."
            return
        }
        sending = true
        sendError = nil

        struct Row: Encodable {
            let user_id: String
            let context: String
            let rating: Int?
            let body: String
        }
        do {
            try await SupabaseProvider.shared
                .from("beta_reviews")
                .insert(Row(
                    user_id: session.user.id.uuidString,
                    context: context.rawValue,
                    rating: rating > 0 ? rating : nil,
                    body: feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                .execute()
            sent = true
        } catch {
            sendError = "Couldn't send — please try again. (\(error.localizedDescription))"
        }
        sending = false
    }
}

/// Once-per-milestone bookkeeping. Callers check `shouldShow` at the moment
/// the milestone completes, then `markShown` before presenting.
enum BetaFeedback {
    private static func key(_ c: BetaFeedbackSheet.Context) -> String {
        "futurevoice.betaFeedback.\(c.rawValue)"
    }

    static func shouldShow(_ c: BetaFeedbackSheet.Context) -> Bool {
        !UserDefaults.standard.bool(forKey: key(c))
    }

    static func markShown(_ c: BetaFeedbackSheet.Context) {
        UserDefaults.standard.set(true, forKey: key(c))
    }
}
