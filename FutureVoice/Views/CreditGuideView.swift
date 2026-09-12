import SwiftUI

/// "What uses talk time?" — the transparency page. The rules here MUST stay
/// in sync with the server (talk-tick + elevenlabs-tts routing): a mismatch
/// between what we show and what we meter is a trust-breaker.
///
/// The model in one line: talk minutes are spent by the in-call clock and by
/// NOTHING else; Watch has its own separate pool of scenes; both are monthly
/// and neither has a daily limit. Everything else — review, browsing, tapping
/// around — is free.
///
/// Scenes used to come out of the same daily minutes as talking, which meant
/// buying "5 minutes of talk" and silently getting three on any day you also
/// watched something. Since 2026-08-14 the two allowances are separate, and
/// this page has to say so or the meter and the explanation disagree.
struct CreditGuideView: View {
    /// The viewer's own plan, so the carry-over section can use their real
    /// numbers instead of a generic example. Nil = don't claim anything about
    /// carry-over: not every plan has it, and a rule stated to someone it
    /// doesn't apply to is worse than no rule.
    var account: AccountStatus? = nil

    var body: some View {
        List {
            // The pool sits FIRST: it is the shape of the whole plan, and
            // the question that actually brings people here is "what am I
            // allowed to do?" before "what does it cost me?".
            // Gated on the SCENE cap, not the talk one: Plus has no talk cap
            // any more, and gating on it made this whole section vanish for
            // the tier whose shape most needs explaining.
            if let account, account.monthlyScenesCap != nil {
                Section {
                    plainRow(icon: "calendar",
                             title: account.monthlyCapSeconds.map {
                                 explain("\($0 / 60) minutes a month")
                             } ?? explain("Talk as much as you want"),
                             // States the rule POSITIVELY and stops. The
                             // trailing "there is no daily limit" said the
                             // same thing again as a denial, and a denial
                             // needs the reader to have expected the limit.
                             // No fair-use figure to state any more: talking
                             // is genuinely uncapped, and the honest reason is
                             // worth saying out loud — speaking is its own
                             // limit, which is exactly what watching is not.
                             detail: account.monthlyCapSeconds == nil
                                 ? explain("No limit and no rationing. Talking takes real effort, so there is nothing here to ration.")
                                 : explain("Use them however you like — all in one call today, or spread over the month."))
                    if let scenes = account.monthlyScenesCap {
                        plainRow(icon: "play.circle.fill",
                                 title: explain("\(scenes) Watch scenes a month"),
                                 detail: explain("A separate pool. Watching a scene never takes a minute off your talk time."))
                    }
                } header: {
                    Text("What your plan holds")
                } footer: {
                    // A cancelled plan refills nothing — see PlanPageView.
                    Text(account.renewalLabel.isEmpty
                         ? explain("Scenes refill at the start of each billing period.")
                         : account.cancelAtPeriodEnd
                           ? explain("Your plan ends on \(account.renewalLabel).")
                           : explain("Scenes refill on \(account.renewalLabel)."))
                }
            }

            Section {
                costRow(icon: "phone.fill",
                        title: explain("Talking"), cost: explain("clock time"),
                        detail: explain("The call clock is the meter — a 10-minute call uses 10 minutes. Thinking pauses cost the same as talking, just like a phone call."))
                costRow(icon: "person.wave.2.fill",
                        title: explain("Re-cloning your voice"), cost: explain("~1 min"),
                        detail: explain("Setup is free, including re-records in the first day. Later re-records cost a little."))
            } header: {
                Text("Uses talk time")
            } footer: {
                Text(explain("Only the call clock spends your talk minutes. Watching a scene never takes a second off them."))
            }

            Section {
                costRow(icon: "play.circle.fill",
                        title: explain("Watching a scene"), cost: explain("1 scene"),
                        detail: explain("Watch has its own pool, separate from your talk minutes. A scene costs one whichever way it runs — a long one and a short one cost the same."))
            } header: {
                Text("Watch scenes")
            } footer: {
                Text(explain("Scenes you've already watched replay free forever and never use a new one."))
            }

            Section {
                freeRow(icon: "rectangle.stack.fill", title: explain("All reviewing"),
                        detail: explain("Drills, shadowing (including coach feedback), word and expression playback — every review surface is free."))
                freeRow(icon: "repeat", title: explain("Replays"),
                        detail: explain("Anything already synthesized is cached — loop it, slow it down, replay whole talks."))
                freeRow(icon: "wand.and.stars", title: explain("Summaries & reports"),
                        detail: explain("Session scorecards, weekly reports, and the daily call are on the house."))
                freeRow(icon: "square.grid.2x2", title: explain("Exploring"),
                        detail: explain("Building situations, browsing topics, translations, dictionaries — tap freely, nothing here is metered."))
                freeRow(icon: "text.book.closed.fill", title: explain("Vocabulary & progress"),
                        detail: explain("The word cloud, CEFR estimate, and stats never cost anything."))
            } header: {
                Text("Always free")
            } footer: {
                Text(explain("In short: minutes buy speaking time with your fluent self. Practicing with what already exists is always free."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What uses talk time?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func costRow(icon: String, title: String, cost: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(cost)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
    }

    /// A rule with no price attached — no trailing tag, because there is no
    /// number to put there.
    private func plainRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func freeRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Free")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 2)
    }
}
