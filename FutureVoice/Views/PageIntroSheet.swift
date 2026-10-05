import SwiftUI

/// "What is this page for, and how do I use it?" — one guide per tab, raised
/// the FIRST time the learner opens that tab and never again (2026-10-03).
///
/// Three pages each, and the order is the point (2026-10-04, founder: the
/// first cut listed feature names — "pick a person", "tap the circle" — and
/// said nothing about WHY any of it exists):
///   1. the PROBLEM the tab answers, in the learner's own terms, then how
///      this tab answers it;
///   2. the SCREEN, drawn as a wireframe with numbered callouts, each
///      explained underneath — the real tab is often still empty for a new
///      learner (no books, no level), so a picture of the real screen would
///      show nothing;
///   3. what happens NEXT — the call, the scene, the card, the first level —
///      and where it leads in the rest of the app.
///
/// The wireframes are illustrations, not UI: grey bars stand in for text so
/// they read the same in every language, and only the labels that name a
/// control are real words.
enum PageIntro {
    enum Page: String, Identifiable, CaseIterable {
        case talk, speech, watch, review, progress
        /// Not a tab: My routine, reached from the Talk header's streak.
        /// Its marks (a green day, a grey ring, a bare number) carry a rule
        /// nobody can guess, so it explains itself on the first visit.
        case routine
        var id: String { rawValue }
    }

    /// The four tabs, in tab order — what `RootTabView` raises guides for.
    static let tabs: [Page] = [.talk, .speech, .watch, .review, .progress]

    static func symbol(_ page: Page) -> String {
        switch page {
        case .talk:     return "waveform"
        case .speech:   return "music.mic"
        case .watch:    return "play.circle.fill"
        case .review:   return "book.fill"
        case .progress: return "chart.bar.fill"
        case .routine:  return "flame.fill"
        }
    }

    static func tabName(_ page: Page) -> String {
        switch page {
        case .talk:     return explain("Talk")
        case .speech:   return explain("Speech")
        case .watch:    return explain("Watch")
        case .review:   return explain("Review")
        case .progress: return explain("Progress")
        case .routine:  return explain("My routine")
        }
    }

    /// The problem each tab answers — the guide's opening line, and the
    /// row's subtitle in Me → App guide.
    static func problem(_ page: Page) -> String {
        switch page {
        case .talk:     return explain("You know the words. You just never get to speak.")
        case .speech:   return explain("Chatting is one thing. Presenting is another.")
        case .watch:    return explain("In a new situation, you don't know what to say")
        case .review:   return explain("What you learn today is gone in a few days")
        case .progress: return explain("Am I actually getting better?")
        case .routine:  return explain("Studying every day is easy to plan and hard to keep")
        }
    }

    struct Callout: Identifiable {
        let title: String
        let detail: String
        var id: String { title }
    }
}

/// Which introductions this install has seen. Device-local on purpose: a
/// second device is a second first look.
enum PageIntroStore {
    /// `v2` (1.1.4, founder: "every user sees the guide cards once, the first
    /// time"): the guides were finished for this release, so everyone gets
    /// each tab's guide once — existing learners included, and installs that
    /// flipped through an earlier cut on TestFlight start over. The old
    /// rule marked every tab seen for anyone who had already talked, on the
    /// theory that they knew the pages; that hid the guides from exactly the
    /// people the pages changed under.
    private static func key(_ page: PageIntro.Page) -> String {
        "futurevoice.pageIntro.seen.v2.\(page.rawValue)"
    }

    static func isDue(_ page: PageIntro.Page) -> Bool {
        !UserDefaults.standard.bool(forKey: key(page))
    }

    static func markSeen(_ page: PageIntro.Page) {
        UserDefaults.standard.set(true, forKey: key(page))
    }

    /// Me → App guide's "show them again": each tab opens with its guide
    /// the next time it is opened.
    static func resetAll() {
        PageIntro.Page.allCases.forEach {
            UserDefaults.standard.removeObject(forKey: key($0))
        }
    }
}

// MARK: - Me → App guide

/// Every tab's guide in one place, for whenever the learner wants it again.
/// Reached from Me, the one page that is always a tap away.
struct AppGuideView: View {
    @State private var open: PageIntro.Page?
    @State private var willShowAgain = false

    var body: some View {
        List {
            Section {
                ForEach(PageIntro.Page.allCases) { page in
                    Button {
                        open = page
                    } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: PageIntro.symbol(page))
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(PageIntro.tabName(page))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(PageIntro.problem(page))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Each guide explains what the tab is for, then walks through its screen.")
            }

            Section {
                Button {
                    PageIntroStore.resetAll()
                    willShowAgain = true
                } label: {
                    Label("Show each guide again when I open its tab",
                          systemImage: "arrow.counterclockwise")
                }
                .disabled(willShowAgain)
            } footer: {
                if willShowAgain {
                    Text("Done. Each tab will open with its guide next time.")
                }
            }
        }
        .navigationTitle("App guide")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { PageIntroSheet(page: $0) }
    }
}

// MARK: - The sheet

struct PageIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    let page: PageIntro.Page
    @State private var step: Int

    init(page: PageIntro.Page, initialStep: Int = 0) {
        self.page = page
        _step = State(initialValue: initialStep)
    }

    /// Talk walks the home, its header, the call, the call's settings and
    /// coach mode; Watch adds people and "making it yours".
    private var stepCount: Int {
        switch page {
        case .talk:  return 6
        case .speech: return 4
        case .watch: return 5
        case .review: return 4
        default:     return 3   // progress, routine
        }
    }
    private var isLast: Bool { step == stepCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Room for the drag indicator. There is no corner button: the
            // way out early is "Later", beside "Next", where it can say what
            // it does (2026-10-04 — a floating "Skip" up here read as
            // skipping a step, and sat in empty space).
            Color.clear.frame(height: 28)

            TabView(selection: $step) {
                ForEach(0..<stepCount, id: \.self) { i in
                    // Each page owns its scrolling: a screen page pins its
                    // picture and scrolls only the explanations under it.
                    pageContent(i)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.accentColor : Color(.tertiaryLabel))
                        .frame(width: i == step ? 18 : 7, height: 7)
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "\(step + 1) / \(stepCount)"))

            HStack(spacing: 10) {
                if !isLast {
                    Button {
                        dismiss()
                    } label: {
                        Text("Maybe later")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button {
                    if isLast {
                        dismiss()
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) { step += 1 }
                    }
                } label: {
                    Text(isLast ? "Let's go" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Text("You can see these again anytime in Me → App guide.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private func pageContent(_ i: Int) -> some View {
        switch (page, i) {
        // MARK: Talk
        case (.talk, 0):
            IntroWhyPage(
                hero: .futureself,
                eyebrow: explain("Talk"),
                problem: PageIntro.problem(.talk),
                detail: explain("Grammar and vocabulary don't turn into speaking until you actually speak. In front of a native speaker you worry about mistakes, and booking a tutor every day is hard to keep up."),
                answer: explain("Here you call yourself: the version of you who already speaks fluently, in a voice cloned from yours. There's no one to be embarrassed in front of, and you can call any time."))
        case (.talk, 1):
            IntroScreenPage(
                title: explain("Starting a call"),
                subtitle: explain("Everything on the Talk page leads to a call."),
                callouts: [
                    .init(title: explain("Tap the circle"),
                          detail: explain("A free talk starts right away. Your fluent self speaks first.")),
                    .init(title: explain("The ring is today's goal"),
                          detail: explain("The whole ring is the daily talk goal you set, 10 minutes unless you change it in Me. The coloured part fills as you talk today, and the ring closes when you reach it.")),
                    .init(title: explain("Not sure what to say?"),
                          detail: explain("Scroll down for situations like ordering at a café or a job interview, and for today's news. Tap one and the call starts on that topic.")),
                ]) { TalkRingMock() }
        case (.talk, 2):
            IntroScreenPage(
                title: explain("The buttons at the top"),
                subtitle: explain("Three things you'll reach for often."),
                callouts: [
                    .init(title: explain("Switch language"),
                          detail: explain("Change the language you're practicing, or add another one. Your fluent self speaks it in the same voice.")),
                    .init(title: explain("Your streak"),
                          detail: explain("The days you studied add up here. Tap it to see your routine and the days behind you.")),
                    .init(title: explain("Your profile"),
                          detail: explain("Opens Me: your profile, voice, daily goal, plan and this guide. The ring around your picture shows how much of this month's talk time you've used.")),
                ]) { TalkHeaderMock() }
        case (.talk, 3):
            IntroScreenPage(
                title: explain("During the call"),
                subtitle: explain("Talk the way you would on the phone. There's no button to hold down."),
                callouts: [
                    .init(title: explain("Talk, then pause"),
                          detail: explain("When you stop speaking, your fluent self answers. Take your time to think.")),
                    .init(title: explain("A more natural way to say it"),
                          detail: explain("Under what you said, you'll see how a native speaker would put it and what to fix. It arrives with the answer, so the conversation keeps going.")),
                    .init(title: explain("Why words show up at the top"),
                          detail: explain("These are the words and expressions due for review today. Nobody remembers mid-sentence what they saved last week, so the call keeps them in front of you. Say one in the conversation and it gets a check. A word you've used in a real talk counts as learned and leaves your review. Tap a chip to see what it means and an example.")),
                ],
                note: explain("When you hang up, the words you used and the sentences you fixed become your own study book in Review.")) { TalkCallMock() }
        case (.talk, 4):
            IntroScreenPage(
                title: explain("Call settings"),
                subtitle: explain("Set the call up the way that works for you, even mid-call."),
                callouts: [
                    .init(title: explain("The settings button"),
                          detail: explain("The slider button next to the mic opens them. The call keeps going while you change things.")),
                    .init(title: explain("Speaking speed"),
                          detail: explain("Normal, Relaxed or Slow. It's how fast your fluent self speaks, and it changes from the next thing it says.")),
                    .init(title: explain("Coach mode"),
                          detail: explain("Extra help while you answer. The next page explains it.")),
                    .init(title: explain("What's on screen"),
                          detail: explain("Hide the subtitles, the corrections or the words to use if they distract you. Nothing is lost: your talk's book keeps every correction.")),
                ]) { CallSettingsMock() }
        case (.talk, _):
            IntroScreenPage(
                title: explain("Coach mode"),
                subtitle: explain("For when you know what you want to say but can't find the words. It starts out on at A1 and A2."),
                callouts: [
                    .init(title: explain("Try saying"),
                          detail: explain("Each time your fluent self speaks, a short answer you could give appears above the button, at your level, with its meaning in your language. A blank (___) is where only you know the answer.")),
                    .init(title: explain("Try using"),
                          detail: explain("Now and then it asks something you can answer with a word you're studying, and shows you the word. Use it and it gets a check.")),
                    .init(title: explain("This call's grammar focus"),
                          detail: explain("The mistake you make most, like the past tense, is pinned at the top. Your fluent self asks questions that need it, and if the same mistake comes back, its correction is marked.")),
                ],
                note: explain("A coached call counts as a practice call. Your minutes, streak and book all count, but it isn't used to measure your level, and words you use in it aren't marked as learned.")) { CoachMock() }

        // MARK: Speech
        case (.speech, 0):
            IntroWhyPage(
                hero: .symbol("music.mic"),
                eyebrow: explain("Speech"),
                problem: PageIntro.problem(.speech),
                detail: explain("A presentation at work, a pitch, introducing yourself at a meeting. Saying prepared words clearly, at a steady pace, with pauses in the right places, is its own skill, and most people only find that out on the day."),
                answer: explain("Speech is a teleprompter. Read a script aloud while it scrolls with your voice, with your camera on or off, and get scored on what you said, your pace and your pauses. Every script teaches you something worth knowing, too."))
        case (.speech, 1):
            IntroScreenPage(
                title: explain("Recording a take"),
                subtitle: explain("Read the script out loud, like a presenter."),
                callouts: [
                    .init(title: explain("The script follows your voice"),
                          detail: explain("It scrolls as you read and slows down when you pause. The line to read sits right under the camera, so your eyes stay near the lens.")),
                    .init(title: explain("Your camera"),
                          detail: explain("Turn it on to film yourself, or off to practice with your voice only.")),
                    .init(title: explain("Record"),
                          detail: explain("Recording starts after 3, 2, 1. While you record, ✕ throws the take away and ↺ starts it over.")),
                ]) { SpeechPrompterMock() }
        case (.speech, 2):
            IntroScreenPage(
                title: explain("After each take"),
                subtitle: explain("Your score comes a few seconds after you stop."),
                callouts: [
                    .init(title: explain("Your score"),
                          detail: explain("Accuracy, pace, pauses, filler words and how steady your voice stays, all measured from your recording. Then a coach tells you what to try next time.")),
                    .init(title: explain("Your video"),
                          detail: explain("The script and your face together in one vertical video. Save it to Photos to share, or delete it.")),
                    .init(title: explain("Your takes"),
                          detail: explain("Every take of a script is kept, so you can watch yourself get better.")),
                ]) { SpeechResultMock() }
        case (.speech, _):
            IntroStepsPage(
                title: explain("Where scripts come from"),
                subtitle: explain("Every script teaches you something while you practice."),
                steps: [
                    .init(symbol: "doc.text",
                          title: explain("Start with the sample"),
                          detail: explain("Every account can practice the built-in script.")),
                    .init(symbol: "sparkles",
                          title: explain("Write one with AI"),
                          detail: explain("Pick a type, like an explainer, a person or the news, then a topic and a length. The facts are checked and the words fit your level. Plus and Max.")),
                    .init(symbol: "pencil.line",
                          title: explain("Add your own"),
                          detail: explain("Paste the presentation or speech you actually have to give. Plus and Max.")),
                ])

        // MARK: Watch
        case (.watch, 0):
            IntroWhyPage(
                hero: .symbol("play.circle.fill"),
                eyebrow: explain("Watch"),
                problem: PageIntro.problem(.watch),
                detail: explain("A job interview, a call to your landlord, dinner with your partner's parents. You know enough of the language. What you don't know is what to say first, what to ask, and how to get through the awkward moment."),
                answer: explain("Watch shows that situation played out by your fluent self, in your voice. You come away with ideas: how to open, what to ask, which expressions work. Then you practice them until they're yours."))
        case (.watch, 1):
            IntroConceptPage(
                title: explain("People: your own cast"),
                sections: [
                    .init(symbol: "person.crop.circle",
                          title: explain("What it is"),
                          body: explain("A person you describe once: someone real in your life, someone famous, or someone you invent. Save who they are, how the two of you know each other and how you talk, and they become a character you can bring back.")),
                    .init(symbol: "questionmark.bubble",
                          title: explain("Why it matters"),
                          body: explain("What you say depends on who you say it to. Asking for a day off is a different conversation with your boss than with a coworker, and a generic stranger can't show you that difference. With a specific person, every scene sounds like the real thing.")),
                    .init(symbol: "sparkles",
                          title: explain("How you use it"),
                          body: explain("The more you save about them, the more they sound like themselves. Then put them in any situation and watch the two of you talk it through. One person can be in as many scenes as you like, and the app suggests situations that fit them.")),
                ]) { CastMock() }
        case (.watch, 2):
            IntroScreenPage(
                title: explain("Setting up a scene"),
                subtitle: explain("Decide who it's with and what's happening."),
                callouts: [
                    .init(title: explain("Pick a person"),
                          detail: explain("Tap someone in your people row. Or leave it empty and the scene finds a fitting person for the situation.")),
                    .init(title: explain("Write your own situation"),
                          detail: explain("Describe what's coming up in as much detail as you can. Attach a job posting or your CV and it reads them first.")),
                    .init(title: explain("Pick a common situation"),
                          detail: explain("No time to write? Tap your way down: café, ordering, the order came out wrong.")),
                ]) { WatchHomeMock() }
        case (.watch, 3):
            IntroScreenPage(
                title: explain("Watching for ideas"),
                subtitle: explain("Notice how it's done, not just what's said."),
                callouts: [
                    .init(title: explain("Your fluent self, in your voice"),
                          detail: explain("The lines play one after another, and the one playing is outlined. Your lines are in your voice. Watch how it opens, what it asks and how it gets through the tricky part.")),
                    .init(title: explain("Keep what you'd use"),
                          detail: explain("Under every line: shadow it right there, or save it to your expressions.")),
                    .init(title: explain("Watch again, or study it"),
                          detail: explain("The left button plays the scene once more. The right one opens the scene's book in Review, with its words and expressions. Tap the same situation in Watch again for a new take with new ideas.")),
                ]) { WatchSceneMock() }
        case (.watch, _):
            IntroStepsPage(
                title: explain("Making it yours"),
                subtitle: explain("An idea is only yours once you've said it."),
                steps: [
                    .init(symbol: "eye.fill",
                          title: explain("Get the idea"),
                          detail: explain("Watch the scene and notice the moves you'd never have thought of.")),
                    .init(symbol: "bookmark.fill",
                          title: explain("Keep it"),
                          detail: explain("Save the expressions you want, and shadow the lines.")),
                    .init(symbol: "book.fill",
                          title: explain("Learn it in Review"),
                          detail: explain("The scene's book brings its words and expressions back to you as cards.")),
                    .init(symbol: "phone.fill",
                          title: explain("Say it yourself"),
                          detail: explain("Start a talk from the scene's book: your fluent self plays the other person, and the scene's words wait at the top for you to use. Or tap Say it again to speak your lines from the scene yourself.")),
                ])

        // MARK: Review
        case (.review, 0):
            IntroWhyPage(
                hero: .symbol("book.fill"),
                eyebrow: explain("Review"),
                problem: PageIntro.problem(.review),
                detail: explain("A phrase you heard in a call, a sentence that got corrected. Without seeing them again they fade, and making flashcards yourself takes time nobody has."),
                answer: explain("Review fills itself. After every talk and scene, the words, expressions and corrected sentences worth learning are gathered into a book, and come back right before you'd forget them."))
        case (.review, 1):
            IntroScreenPage(
                title: explain("Your study books"),
                subtitle: explain("One talk, one book. The newest is on top."),
                callouts: [
                    .init(title: explain("A book"),
                          detail: explain("Every talk and scene you finish becomes one. It's done when you've learned everything inside.")),
                    .init(title: explain("Chapters"),
                          detail: explain("Words, expressions, shadowing and grammar. Tap one to practice just that part, card by card.")),
                    .init(title: explain("Your library"),
                          detail: explain("Everything you've collected from every book, in one place.")),
                ]) { ReviewHomeMock() }
        case (.review, 2):
            IntroScreenPage(
                title: explain("How a card works"),
                subtitle: explain("You decide when you see it again."),
                callouts: [
                    .init(title: explain("Say it, then check"),
                          detail: explain("Say the word out loud first. Then tap the card to see its meaning and an example.")),
                    .init(title: explain("Not sure yet?"),
                          detail: explain("Drag the card onto 10 min, Tomorrow or 3 days. It comes back then.")),
                    .init(title: explain("Know it?"),
                          detail: explain("Drop it on Got it and it stops coming back.")),
                ],
                note: explain("Best of all, say it in a call: a word you use in a real talk counts as learned. Each week there's also a short test made from that week's own talks.")) { ReviewCardMock() }
        case (.review, _):
            IntroScreenPage(
                title: explain("Your week, at the top"),
                subtitle: explain("The three buttons in the header are about the whole week, not just today."),
                callouts: [
                    .init(title: explain("Cards you put off"),
                          detail: explain("Every card you sent to 10 min, Tomorrow or 3 days waits here, in the order it comes back. An orange dot means some are due now.")),
                    .init(title: explain("Your week"),
                          detail: explain("When a new week starts, a short report on the last one comes up once: the days you studied, your streak, how long you talked, and what became yours. Every past week stays here, and a dot marks one you haven't opened.")),
                    .init(title: explain("Weekly test"),
                          detail: explain("Once a week, a test made only from that week's own talks: what a word means, the missing phrase, rebuilding a corrected sentence, writing down what you hear, saying a line out loud, and the grammar from your weekly report. A dot means it's open.")),
                ],
                note: explain("What you get wrong comes back in the next weeks' tests until you get it right. The test day is Saturday at 10:00 unless you change it.")) { ReviewWeekMock() }

        // MARK: Progress
        case (.progress, 0):
            IntroWhyPage(
                hero: .symbol("chart.bar.fill"),
                eyebrow: explain("Progress"),
                problem: PageIntro.problem(.progress),
                detail: explain("It's hard to keep going when you can't tell whether it's working. And a test score doesn't tell you how well you speak."),
                answer: explain("Progress never asks you to sit a test. It measures the words, sentence structures and fluency you actually used in your calls, and shows them as a CEFR level."))
        case (.progress, 1):
            IntroScreenPage(
                title: explain("Reading your level"),
                subtitle: explain("From A1 to C2, measured from what you said."),
                callouts: [
                    .init(title: explain("Your overall level"),
                          detail: explain("Where you are between A1 and C2. The ≈ means it's an estimate, and it gets sharper the more you talk.")),
                    .init(title: explain("Skill by skill"),
                          detail: explain("Vocabulary, grammar and fluency each have their own level, with what to work on to reach the next one.")),
                    .init(title: explain("Your effort"),
                          detail: explain("How much you talked and reviewed over the last two weeks.")),
                ]) { ProgressHomeMock() }
        case (.progress, _):
            IntroStepsPage(
                title: explain("When does my level appear?"),
                subtitle: explain("It needs a little of your speech first."),
                steps: [
                    .init(symbol: "phone.fill",
                          title: explain("Talk for about 10 minutes"),
                          detail: explain("That's enough of your speech to measure.")),
                    .init(symbol: "chart.bar.fill",
                          title: explain("Your first level appears"),
                          detail: explain("Each skill gets its own level.")),
                    .init(symbol: "arrow.up.forward",
                          title: explain("It moves as you talk"),
                          detail: explain("Every call measures again, and when you move up a level, you'll hear about it.")),
                ])

        // MARK: My routine
        case (.routine, 0):
            IntroWhyPage(
                hero: .symbol("flame.fill"),
                eyebrow: explain("My routine"),
                problem: PageIntro.problem(.routine),
                detail: explain("A plan in your head slips the first busy day."),
                answer: explain("Plan your week once here. Each day then shows whether you did it."),
                answerHeading: "Here's how this page helps")
        case (.routine, 1):
            IntroScreenPage(
                title: explain("Plan on the timeline"),
                subtitle: explain("Tap Edit at the top right. Days run across, hours run down."),
                callouts: [
                    .init(title: explain("Tap an empty spot to add"),
                          detail: explain("Pick what to do there: talk, words, review and more.")),
                    .init(title: explain("Hold and drag to move"),
                          detail: explain("Up and down changes the time, sideways changes the day.")),
                    .init(title: explain("Set it once, it repeats"),
                          detail: explain("The same plan comes back every week. Leave a day empty to rest.")),
                ]) { RoutineTimelineMock() }
        case (.routine, _):
            IntroScreenPage(
                title: explain("Done it all? It turns green"),
                subtitle: explain("Each date at the top shows how that day went."),
                callouts: [
                    .init(title: explain("Green: you did it all"),
                          detail: explain("Everything planned for that day is done. Your streak grows by one.")),
                    .init(title: explain("Today fills as you go"),
                          detail: explain("Any time that day counts. The times are a plan, not a deadline.")),
                ],
                note: explain("An empty day is a rest day, so it doesn't break your streak.")) { RoutineDaysMock() }
        }
    }
}

// MARK: - Page 1: the problem, then the answer

private struct IntroWhyPage: View {
    enum Hero { case futureself, symbol(String) }

    let hero: Hero
    let eyebrow: String
    let problem: String
    let detail: String
    let answer: String
    /// The answer box's heading. My routine is a page, not a tab.
    var answerHeading: LocalizedStringKey = "Here's how this tab helps"

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            heroView
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(problem)
                    .font(.title.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(answerHeading, systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(answer)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var heroView: some View {
        switch hero {
        case .futureself:
            Futureself(mode: .speaking, level: 0.35, virtualHeight: 64)
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .accessibilityHidden(true)
        case .symbol(let name):
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 88, height: 88)
                .overlay {
                    Image(systemName: name)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Page 2/3: the screen, with numbered callouts

private struct CalloutFocusKey: EnvironmentKey {
    static let defaultValue = 0
}

private extension EnvironmentValues {
    var calloutFocus: Int {
        get { self[CalloutFocusKey.self] }
        set { self[CalloutFocusKey.self] = newValue }
    }
}

private struct IntroScreenPage<Mock: View>: View {
    let title: String
    let subtitle: String
    let callouts: [PageIntro.Callout]
    var note: String? = nil
    @ViewBuilder let mock: () -> Mock

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which numbered spot is lit. It walks 1 → 2 → 3 by itself so the eye
    /// is led from the picture to its explanation, and stops for good the
    /// moment the learner taps a row — after that they are steering.
    @State private var focus = 1
    @State private var steered = false

    var body: some View {
        VStack(spacing: 0) {
            // The picture stays put; the explanations scroll under it, so
            // the lit spot and its row can always be seen together.
            mock()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
                .background(Color(.systemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5))
                .environment(\.calloutFocus, focus)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 14)

            ScrollViewReader { proxy in
                ScrollView {
                    explanations
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: focus) { _, n in
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(n) }
                }
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                if steered || Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    focus = focus % max(callouts.count, 1) + 1
                }
            }
        }
    }

    private var explanations: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(callouts.enumerated()), id: \.element.id) { index, callout in
                    let n = index + 1
                    Button {
                        steered = true
                        withAnimation(.easeInOut(duration: 0.25)) { focus = n }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            CalloutBadge(number: n, lit: focus == n)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(callout.title)
                                    .font(.headline)
                                Text(callout.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(n)
                }
            }

            if let note {
                Label {
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            }
        }
    }
}

private struct CalloutBadge: View {
    let number: Int
    let lit: Bool

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.accentColor))
            .opacity(lit ? 1 : 0.5)
            .scaleEffect(lit ? 1.08 : 1)
            .accessibilityHidden(true)
    }
}

/// Marks one spot on a wireframe: a numbered badge always, and a soft fill
/// while it is the lit one. No outline (2026-10-04, founder: too much blue).
/// The fill's corner is CONCENTRIC with what it wraps — `corner` is the
/// wrapped content's own radius, and the fill adds its padding to it, so a
/// capsule gets a capsule and a 12 pt card a 17 pt halo.
private struct CalloutMark: ViewModifier {
    let number: Int
    let corner: CGFloat
    /// Where the badge sits — moved off the default corner when two marks
    /// nest (the ring and the circle inside it).
    var trailing = false
    @Environment(\.calloutFocus) private var focus

    private let inset: CGFloat = 5

    /// The halo is drawn OUTSIDE the content's frame and takes no layout
    /// space: a mark must never move what it marks, or the picture stops
    /// matching the screen it was drawn from (the header capsule grew
    /// around its two marked icons and outsized the face beside it).
    func body(content: Content) -> some View {
        let lit = focus == number
        content
            .background(RoundedRectangle(cornerRadius: corner + inset, style: .continuous)
                .fill(Color.accentColor.opacity(lit ? 0.12 : 0))
                .padding(-inset))
            .overlay(alignment: trailing ? .topTrailing : .topLeading) {
                CalloutBadge(number: number, lit: lit)
                    .offset(x: trailing ? 9 + inset : -9 - inset, y: -9 - inset)
            }
    }
}

private extension View {
    func callout(_ number: Int, corner: CGFloat = 12, trailing: Bool = false) -> some View {
        modifier(CalloutMark(number: number, corner: corner, trailing: trailing))
    }
}

// MARK: - Page 3 for Progress: a short timeline

private struct IntroStepsPage: View {
    struct Step: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { symbol }
    }

    let title: String
    let subtitle: String
    let steps: [Step]

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 0) {
                            Image(systemName: step.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.accentColor.opacity(0.14)))
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.3))
                                    .frame(width: 2)
                                    .frame(minHeight: 28, maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.headline)
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 22)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Wireframe parts

/// A line of text, as a wireframe draws it.
private struct TextBar: View {
    var width: CGFloat
    var height: CGFloat = 7
    var accent = false

    var body: some View {
        Capsule()
            .fill(accent ? Color.accentColor.opacity(0.45) : Color(.tertiaryLabel).opacity(0.45))
            .frame(width: width, height: height)
    }
}

private let mockCard = Color(.secondarySystemGroupedBackground)

private struct TalkRingMock: View {
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                TextBar(width: 150, height: 9)
                TextBar(width: 96, height: 9)
            }
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: 0.62)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Futureself(mode: .idle, level: 0, virtualHeight: 64)
                    .frame(width: 98, height: 98)
                    .clipShape(Circle())
                    .callout(1, corner: 49, trailing: true)
            }
            .frame(width: 136, height: 136)
            .callout(2, corner: 68)
            HStack(spacing: 8) {
                tile("cup.and.saucer.fill", "Scenarios")
                tile("newspaper.fill", "News")
            }
            .callout(3)
        }
    }

    private func tile(_ symbol: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(label).font(.caption.weight(.bold))
            TextBar(width: 64, height: 6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mockCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TalkHeaderMock: View {
    var body: some View {
        VStack(spacing: 22) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "globe").font(.caption2.weight(.bold))
                    Text(verbatim: "EN").font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Capsule().fill(mockCard))
                .callout(1, corner: 16)
                Spacer()
                Label {
                    Text(verbatim: "5")
                } icon: {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                }
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Capsule().fill(mockCard))
                .callout(2, corner: 16)
                Spacer()
                ZStack {
                    Circle().fill(mockCard)
                    Circle()
                        .trim(from: 0, to: 0.35)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(3)
                    Circle()
                        .fill(Color.accentColor.opacity(0.25))
                        .padding(8)
                        .overlay(Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.tint))
                }
                .frame(width: 44, height: 44)
                .callout(3, corner: 22)
            }
            VStack(spacing: 6) {
                TextBar(width: 150, height: 9)
                TextBar(width: 96, height: 9)
            }
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                .frame(width: 84, height: 84)
                .overlay(Circle().fill(Color.accentColor.opacity(0.12)).padding(10))
                .opacity(0.6)
        }
        .padding(.top, 6)
    }
}

private struct TalkCallMock: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                chip(checked: true)
                chip(checked: false)
                chip(checked: false)
            }
            .callout(3, corner: 12)

            HStack {
                bubble([130, 92], mine: false)
                Spacer(minLength: 28)
            }
            HStack {
                Spacer(minLength: 28)
                VStack(alignment: .trailing, spacing: 8) {
                    bubble([118, 70], mine: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("More natural", systemImage: "sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                        TextBar(width: 124, accent: true)
                        TextBar(width: 80, accent: true)
                    }
                    .padding(9)
                    .background(Color.accentColor.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .callout(2, corner: 10)
                }
            }

            VStack(spacing: 6) {
                Futureself(mode: .listening, level: 0.45)
                    .frame(width: 132, height: 48)
                    .clipShape(Capsule())
                Text("Listening…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .callout(1, corner: 24)
        }
    }

    private func chip(checked: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(checked ? Color.green : Color.secondary)
            TextBar(width: 32, height: 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(mockCard))
    }

    private func bubble(_ widths: [CGFloat], mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                TextBar(width: w)
            }
        }
        .padding(11)
        .background(mine ? Color.accentColor.opacity(0.16) : mockCard,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WatchHomeMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Watch")
                .font(.title3.weight(.bold))
            HStack(spacing: 10) {
                person("M")
                person("J")
                person("S")
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.tint))
            }
            .callout(1, corner: 18)
            HStack(spacing: 10) {
                door("square.and.pencil", "Your own situation").callout(2)
                door("square.grid.2x2", "Common situations").callout(3)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Your scenarios")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                HStack {
                    TextBar(width: 130)
                    Spacer()
                    Image(systemName: "play.circle.fill").foregroundStyle(.tint)
                }
                .padding(10)
                .background(mockCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func person(_ initial: String) -> some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay(Text(verbatim: initial).font(.caption.weight(.bold)).foregroundStyle(.tint))
    }

    private func door(_ symbol: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(label)
                .font(.caption.weight(.bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(mockCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Drawn after the real scene screen (`WatchView`): the scene's header,
/// a name label over each line, the action row under every line, the
/// playing line outlined, and the two buttons pinned at the bottom.
private struct WatchSceneMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                TextBar(width: 70, height: 5)
                TextBar(width: 120, height: 10)
                TextBar(width: 170, height: 5)
            }
            line(mine: false, [118], actionsCallout: 2)
            line(mine: true, [150, 72], playing: true, bubbleCallout: 1)
            line(mine: false, [96], actions: false)
            HStack(spacing: 8) {
                Label("Watch again", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                Label("Study this", systemImage: "books.vertical.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.accentColor))
            }
            .padding(.top, 4)
            .callout(3, corner: 17)
        }
    }

    private func line(mine: Bool, _ widths: [CGFloat], playing: Bool = false,
                      actions: Bool = true, actionsCallout: Int? = nil,
                      bubbleCallout: Int? = nil) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
            TextBar(width: 34, height: 5)
            let bubble = VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                    TextBar(width: w)
                }
            }
            .padding(10)
            .background(mockCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if playing {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            if let n = bubbleCallout {
                bubble.callout(n, corner: 14, trailing: mine)
            } else {
                bubble
            }
            if actions {
                let row = HStack(spacing: 10) {
                    Label("Shadow this", systemImage: "waveform")
                    Label("Save phrase", systemImage: "plus.circle")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tint)
                if let n = actionsCallout {
                    row.callout(n, corner: 6)
                } else {
                    row
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

/// Drawn after the real Review page (`PracticeTab.studyingPage`): the
/// title with the week's buttons, the shelf chips, the four library tiles,
/// then the books newest first, each with its four chapter buttons.
private struct ReviewHomeMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReviewHeaderMock()
            HStack(spacing: 6) {
                Text("Studying")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary))
                ForEach([28.0, 40.0, 26.0], id: \.self) { w in
                    TextBar(width: w, height: 6)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(mockCard))
                }
            }
            HStack(spacing: 0) {
                libraryTile("book.closed.fill", "Words")
                libraryTile("quote.bubble.fill", "Expressions")
                libraryTile("rectangle.stack", "Sentences")
                libraryTile("waveform", "Shadowing")
            }
            .padding(.vertical, 8)
            .background(mockCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .callout(3, corner: 14)

            VStack(alignment: .leading, spacing: 9) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11)).foregroundStyle(.tint))
                VStack(alignment: .leading, spacing: 5) {
                    TextBar(width: 60, height: 5)
                    TextBar(width: 150, height: 8)
                }
                HStack(spacing: 6) {
                    chapter("book.closed.fill", 0.6)
                    chapter("quote.bubble.fill", 0)
                    chapter("waveform", 0.8)
                    chapter("checkmark.bubble.fill", 0)
                }
                .callout(2, corner: 10)
            }
            .padding(10)
            .background(mockCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .callout(1, corner: 14)
        }
    }

    private func libraryTile(_ symbol: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.tint)
            TextBar(width: 14, height: 7)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func chapter(_ symbol: String, _ progress: Double) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.tint)
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(Color.accentColor).frame(width: g.size.width * progress)
                    }
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill).opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(progress == 0 ? 0.5 : 1)
    }
}

/// The Review title and its header buttons, as the page draws them:
/// put-off cards and the week's report together, the test's face apart.
private struct ReviewHeaderMock: View {
    var putOffMark: Int? = nil
    var weekMark: Int? = nil
    var testMark: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text("Review").font(.title2.weight(.bold))
            Spacer()
            HStack(spacing: 4) {
                icon("rectangle.stack", dot: .orange, mark: putOffMark)
                icon("calendar", dot: .accentColor, mark: weekMark)
            }
            .padding(.horizontal, 4)
            .background(Capsule().fill(mockCard))
            face
        }
    }

    @ViewBuilder
    private func icon(_ name: String, dot: Color, mark: Int?) -> some View {
        let view = Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 32, height: 32)
            .overlay(alignment: .topTrailing) {
                Circle().fill(dot).frame(width: 7, height: 7).offset(x: -3, y: 4)
            }
        if let mark { view.callout(mark, corner: 16) } else { view }
    }

    @ViewBuilder
    private var face: some View {
        // The same 32 pt as the capsule beside it: the face fills a 24 pt
        // tile inside a 32 pt circle, so the two read as one row.
        let view = WeeklyTestCharacter(mood: .waiting, since: .distantPast, tile: Color(.tertiarySystemFill))
            .scaleEffect(24 / WeeklyTestCharacter.size)
            .frame(width: 24, height: 24)
            .padding(4)
            .background(Circle().fill(mockCard))
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color.accentColor).frame(width: 7, height: 7).offset(x: -2, y: 3)
            }
        if let testMark { view.callout(testMark, corner: 16, trailing: true) } else { view }
    }
}

/// The week's header buttons, and what two of them open: the week's
/// report card and a test question.
private struct ReviewWeekMock: View {
    var body: some View {
        VStack(spacing: 14) {
            ReviewHeaderMock(putOffMark: 1, weekMark: 2, testMark: 3)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: "5").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(verbatim: "/ 7").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { i in
                            Circle()
                                .fill([2, 5].contains(i) ? Color(.tertiarySystemFill) : Color.accentColor)
                                .frame(width: 11, height: 11)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.orange)
                        TextBar(width: 40, height: 6)
                    }
                    TextBar(width: 80, height: 5)
                    TextBar(width: 64, height: 5)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(mockCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    WeeklyTestCharacter(mood: .waiting, since: .distantPast, tile: Color(.tertiarySystemFill))
                        .scaleEffect(30 / WeeklyTestCharacter.size)
                        .frame(width: 30, height: 30)
                        .frame(maxWidth: .infinity)
                    TextBar(width: 90, height: 7)
                    ForEach([70.0, 54.0, 62.0], id: \.self) { w in
                        TextBar(width: w, height: 6, accent: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(mockCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

/// Drawn after the real deck (`StudyDeckView`): one large accent card —
/// the prompt, the word, "tap to see the meaning" — and, while it is
/// dragged, the four folders it can be dropped on.
private struct ReviewCardMock: View {
    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Capsule().fill(Color.white.opacity(0.55)).frame(width: 120, height: 6)
                Capsule().fill(Color.white).frame(width: 110, height: 13)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.caption2.weight(.semibold))
                    Capsule().frame(width: 60, height: 6)
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .frame(height: 150)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .offset(x: -16, y: 14)
            }
            .callout(1, corner: 18)

            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    folder("clock", "10 min")
                    folder("sunrise", "Tomorrow")
                    folder("calendar", "3 days")
                }
                .callout(2, corner: 12)
                folder("checkmark.circle.fill", "Got it")
                    .frame(maxWidth: 72)
                    .callout(3, corner: 12, trailing: true)
            }
        }
    }

    private func folder(_ symbol: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(mockCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SpeechPrompterMock: View {
    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 9) {
                TextBar(width: 150).opacity(0.5)
                TextBar(width: 190, height: 9)
                TextBar(width: 170, height: 9)
                TextBar(width: 120, height: 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(mockCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .callout(1, corner: 14)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemGray3))
                    .frame(height: 150)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(Color(.systemGray5))
                            .offset(y: 10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                HStack(spacing: 26) {
                    Circle().fill(Color.black.opacity(0.35)).frame(width: 34, height: 34)
                        .overlay { Image(systemName: "video.fill").font(.caption).foregroundStyle(.white) }
                        .callout(2, corner: 17)
                    Circle().strokeBorder(.white, lineWidth: 3).frame(width: 46, height: 46)
                        .overlay { Circle().fill(.red).frame(width: 36, height: 36) }
                        .callout(3, corner: 23, trailing: true)
                    Circle().fill(Color.black.opacity(0.35)).frame(width: 34, height: 34)
                        .overlay { Image(systemName: "waveform").font(.caption).foregroundStyle(.white) }
                }
                .padding(.bottom, 12)
            }
        }
    }
}

private struct SpeechResultMock: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color(.tertiaryLabel).opacity(0.3), lineWidth: 6)
                    Circle().trim(from: 0, to: 0.84)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "84").font(.headline.monospacedDigit())
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 7) {
                    TextBar(width: 140)
                    TextBar(width: 110)
                    TextBar(width: 90, accent: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(mockCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .callout(1, corner: 14)

            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    Color(.systemGray5).overlay {
                        VStack(alignment: .leading, spacing: 4) {
                            TextBar(width: 34, height: 4); TextBar(width: 28, height: 4)
                        }
                    }
                    Color(.systemGray3).overlay {
                        Image(systemName: "person.fill").foregroundStyle(Color(.systemGray5))
                    }
                }
                .frame(width: 54, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .callout(2, corner: 8)

                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack {
                            TextBar(width: 80)
                            Spacer(minLength: 0)
                            Text(verbatim: ["84", "76", "69"][i])
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(i == 0 ? Color.green : Color.orange)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(mockCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .callout(3, corner: 8, trailing: true)
            }
        }
    }
}

private struct ProgressHomeMock: View {
    private let ladder = ["A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your level")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(verbatim: "≈ B1")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                HStack(spacing: 3) {
                    ForEach(Array(ladder.enumerated()), id: \.offset) { i, band in
                        Text(verbatim: band)
                            .font(.system(size: 9, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .foregroundStyle(i == 2 ? Color.white : Color.secondary)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(i == 2 ? Color.accentColor
                                      : i < 2 ? Color.accentColor.opacity(0.3)
                                      : Color(.tertiarySystemFill)))
                    }
                }
            }
            .padding(12)
            .background(mockCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .callout(1, corner: 14)

            HStack(spacing: 6) {
                skill("Vocabulary", "B1")
                skill("Grammar", "A2")
                skill("Fluency", "B1")
            }
            .callout(2, corner: 10)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array([0.3, 0.5, 0.2, 0.0, 0.6, 0.8, 0.4, 0.7, 0.5, 0.0, 0.9, 0.6, 0.75, 1.0].enumerated()),
                        id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor.opacity(h == 0 ? 0.15 : 0.7))
                        .frame(height: max(4, 44 * h))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44)
            .padding(10)
            .background(mockCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .callout(3)
        }
    }

    private func skill(_ label: LocalizedStringKey, _ band: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: band)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(mockCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CallSettingsMock: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Spacer()
                Futureself(mode: .idle, level: 0)
                    .frame(width: 112, height: 42)
                    .clipShape(Capsule())
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(mockCard, in: Circle())
                    .callout(1, corner: 19, trailing: true)
                Spacer()
            }
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    speed("Normal", on: false)
                    speed("Relaxed", on: true)
                    speed("Slow", on: false)
                }
                .padding(10)
                .callout(2, corner: 14)
                Divider()
                toggleRow("lightbulb", "Coach mode", on: true)
                    .callout(3, corner: 8)
                Divider()
                VStack(spacing: 0) {
                    toggleRow("captions.bubble", "Subtitles", on: true)
                    toggleRow("sparkles", "Corrections", on: true)
                    toggleRow("text.badge.checkmark", "Words to use", on: false)
                }
                .callout(4, corner: 8)
            }
            .background(mockCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func speed(_ label: LocalizedStringKey, on: Bool) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
    }

    private func toggleRow(_ symbol: String, _ label: LocalizedStringKey, on: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.tint).frame(width: 18)
            Text(label).font(.caption.weight(.semibold))
            Spacer()
            Toggle("", isOn: .constant(on))
                .labelsHidden()
                .scaleEffect(0.75)
                .frame(width: 44, height: 26)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

private struct CoachMock: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "scope").font(.caption).foregroundStyle(.orange)
                TextBar(width: 54, height: 7)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                TextBar(width: 54, height: 7, accent: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(mockCard, in: Capsule())
            .callout(3, corner: 16)

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    TextBar(width: 140)
                    TextBar(width: 96)
                }
                .padding(11)
                .background(mockCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer(minLength: 28)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Try saying")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    TextBar(width: 64, height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [3]))
                        .frame(width: 40, height: 14)
                    TextBar(width: 40, height: 8)
                }
                TextBar(width: 110, height: 6)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mockCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .callout(1)

            HStack(spacing: 6) {
                Text("Try using")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextBar(width: 52, height: 8, accent: true)
                Image(systemName: "circle").font(.caption2).foregroundStyle(.secondary)
            }
            .callout(2, corner: 10)

            Futureself(mode: .listening, level: 0.4)
                .frame(width: 120, height: 44)
                .clipShape(Capsule())
        }
    }
}

// MARK: - A concept, not a screen

/// For an idea the screen can't show by itself (a persona): a fixed
/// picture of the idea, then what / why / how underneath, scrolling.
private struct IntroConceptPage<Picture: View>: View {
    struct Section: Identifiable {
        let symbol: String
        let title: String
        let body: String
        var id: String { symbol }
    }

    let title: String
    let sections: [Section]
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        VStack(spacing: 0) {
            picture()
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5))
                .accessibilityHidden(true)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(section.title, systemImage: section.symbol)
                                .font(.headline)
                                .labelStyle(TintedIconLabelStyle())
                            Text(section.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(.tint)
            configuration.title
        }
    }
}

/// One person, many scenes: the persona in the middle and the situations
/// it can be put into around it.
private struct CastMock: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                    .overlay(Text(verbatim: "M").font(.title2.weight(.bold)).foregroundStyle(.tint))
                TextBar(width: 56, height: 8)
                VStack(alignment: .leading, spacing: 5) {
                    TextBar(width: 70, height: 5)
                    TextBar(width: 52, height: 5)
                    TextBar(width: 62, height: 5)
                }
                .padding(8)
                .background(mockCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Image(systemName: "arrow.right")
                .font(.headline)
                .foregroundStyle(.tertiary)
            VStack(spacing: 8) {
                scene("briefcase.fill", 76)
                scene("cup.and.saucer.fill", 64)
                scene("airplane", 84)
                scene("gift.fill", 58)
            }
        }
        .padding(.vertical, 6)
    }

    private func scene(_ symbol: String, _ width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.tint).frame(width: 18)
            TextBar(width: width, height: 7)
            Spacer(minLength: 0)
            Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 150)
        .background(mockCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - My routine

/// The weekly plan editor (`WeeklyPlanEditor`): weekday columns, hour rows,
/// a few blocks, an empty spot about to be filled and a block being dragged.
private struct RoutineTimelineMock: View {
    private let rowHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Color.clear.frame(width: 14)
                ForEach(0..<7, id: \.self) { _ in
                    TextBar(width: 10, height: 5).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 12)
            .callout(3, corner: 6, trailing: true)
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { _ in
                        TextBar(width: 10, height: 4)
                            .frame(height: rowHeight, alignment: .top)
                    }
                }
                .frame(width: 14)
                ForEach(0..<7, id: \.self) { day in
                    // The dragged block hangs over the next column.
                    column(day).zIndex(day == 1 ? 1 : 0)
                }
            }
        }
    }

    private func column(_ day: Int) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(mockCard)
            VStack(spacing: 3) {
                if day < 5 { block("phone.fill", .blue) } else { Color.clear.frame(height: 18) }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            if day == 1 {
                block("textformat", .purple)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .callout(2, corner: 5, trailing: true)
                    .offset(x: 6, y: rowHeight * 2.4)
            }
            if day == 3 {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(height: 18)
                    .overlay(Image(systemName: "plus").font(.caption2.weight(.bold)).foregroundStyle(.tint))
                    .padding(.horizontal, 2)
                    .callout(1, corner: 5)
                    .offset(y: rowHeight * 3.6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight * 6)
    }

    private func block(_ symbol: String, _ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(tint.opacity(0.2))
            .frame(height: 18)
            .overlay(Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint))
            .padding(.horizontal, 2)
    }
}

/// The date strip, reduced to the four looks a day can have: done (green),
/// left undone (grey ring), a rest day (just the number), today filling.
private struct RoutineDaysMock: View {
    var body: some View {
        HStack(spacing: 0) {
            day(callout: 1) {
                Circle().fill(Color.green)
                number(14).foregroundStyle(.white)
            }
            day {
                Circle().strokeBorder(Color(.systemGray4), lineWidth: 2)
                number(15).foregroundStyle(.secondary)
            }
            day { number(16).foregroundStyle(.tertiary) }
            day(callout: 2) {
                Circle().strokeBorder(Color(.systemGray5), lineWidth: 3)
                Circle().trim(from: 0, to: 0.55)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
                number(17).foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 18)
    }

    private func number(_ n: Int) -> Text {
        Text(verbatim: "\(n)").font(.callout.weight(.semibold)).monospacedDigit()
    }

    @ViewBuilder
    private func day<C: View>(callout n: Int? = nil, @ViewBuilder _ face: () -> C) -> some View {
        let circle = ZStack { face() }.frame(width: 40, height: 40)
        Group {
            if let n { circle.callout(n, corner: 20) } else { circle }
        }
        .frame(maxWidth: .infinity)
    }
}
