#if DEBUG
import Foundation

/// A finished free trial to look at (`-trialreport 1 -trialdemo 1`): a Korean
/// speaker practising English for work, three talks over two days, twenty
/// minutes, a test taken, a level read. The coach's read and the level are
/// written here because a capture run can't reach the model; everything else
/// in the deck draws from them exactly as it would from a real trial.
@MainActor
enum TrialReportDemo {
    static func seed(now: Date = Date()) {
        TrialReportStore.reset()
        let cal = Calendar.current
        let day1 = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now))!.addingTimeInterval(20 * 3600)
        let day2 = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!.addingTimeInterval(8 * 3600)
        let day3 = cal.startOfDay(for: now).addingTimeInterval(8 * 3600 + 900)

        let coach = WeekRecap.Coach(
            headline: "하고 싶은 말은 끝까지 했어요. 이제 시제만 잡으면 돼요.",
            insight: "문장을 짧게 끊어 말해서 실수는 적은 편이에요. 다만 설명이 길어지면 and로만 이어 붙여요.",
            insightQuote: "We have a meeting and we talk about the app and then we decide.",
            grammar: [
                .init(rule: "과거부터 지금까지 이어지는 일 (현재완료)",
                      examples: [.init(was: "I am working here since three years",
                                       now: "I've been working here for three years"),
                                 .init(was: "We use this tool since March",
                                       now: "We've been using this tool since March")],
                      tip: "since나 for가 나오면 am 대신 have been을 떠올려 보세요."),
                .init(rule: "explain 뒤에 사람을 바로 쓰지 않기",
                      examples: [.init(was: "He explained me the plan", now: "He explained the plan to me"),
                                 .init(was: "Can you explain me why", now: "Can you explain to me why")],
                      tip: "explain 다음엔 내용이 먼저, 사람은 to와 함께 와요.")
            ],
            upgrades: [
                .init(instead: "good", count: 9, better: "solid",
                      original: "It's a good plan.", rewritten: "It's a solid plan.",
                      note: "계획이나 근거가 믿을 만할 때 써요."),
                .init(instead: "busy", count: 5, better: "swamped",
                      original: "I'm very busy this week.", rewritten: "I'm swamped this week.",
                      note: "일이 몰려 정신없을 때 회화에서 자주 써요.")
            ],
            plan: ["다음 대화에서 I've been ...ing for ...로 내 일 소개하기",
                   "회의 이야기를 할 때 push back on을 한 번 써 보기",
                   "고친 문장 5개 복습하기"])

        let recap = WeekRecap(
            start: cal.startOfDay(for: day1), end: now,
            activeDays: [true, true, true, false, false, false, false],
            streak: 3, talkSeconds: 20 * 60, previousTalkSeconds: 0,
            talks: [.init(title: "Meeting your future self", day: day1, minutes: 8, kind: "free"),
                    .init(title: "Pitching a new feature to my team", day: day2, minutes: 7, kind: "scenario"),
                    .init(title: "A four-day work week", day: day3, minutes: 5, kind: "news")],
            usedCount: 2,
            used: [.init(item: "get back to you", quote: "Let me get back to you on the budget tomorrow."),
                   .init(item: "in charge of", quote: "I'm in charge of the new onboarding.")],
            cardsCleared: 6, wordsKnown: 4, expressionsKnown: 2,
            shadowTakes: 3, shadowAverage: 78, previousShadowAverage: nil, scenes: 0,
            nowYours: ["deadline", "get back to you", "in charge of", "figure out", "on the same page", "budget"],
            sentencesGot: ["I've been working here for three years."],
            newExpressionCount: 6,
            newExpressions: [.init(item: "push back on", quote: "If they push back on the timeline, just ask what they'd cut."),
                             .init(item: "walk someone through", quote: "Can you walk me through how it works?"),
                             .init(item: "a good fit", quote: "Honestly, it sounds like a good fit for your team."),
                             .init(item: "keep it short", quote: "Keep it short, two slides at most.")],
            newCards: 5,
            stumbles: [.init(was: "I am working here since three years", now: "I've been working here for three years", count: 2),
                       .init(was: "He explained me the plan", now: "He explained the plan to me", count: 2)],
            shakyLines: [], testScore: nil, testTotal: nil, coach: coach)

        let test = demoTest(start: recap.start, now: now)
        WeeklyTestStore.shared.save(test)

        var report = TrialReport(recap: recap, targetLanguage: "en", builtAt: now)
        report.testId = test.id
        report.level = CEFRLevel.b1.rawValue
        report.levelRationale = "말하는 속도가 분당 98단어로 B1 범위이고, 100단어당 실수가 4개 정도로 안정적이에요. 다만 문장 대부분이 한 절이라 복잡한 구조는 아직 드물어요. 업무 이야기를 끝까지 설명할 수 있어서 B1으로 봤어요."
        TrialReportStore.save(report)

        LearningPurposeStore.purposes = [.work]
        UserDefaults.standard.set(false, forKey: LearningPurposeStore.routineAppliedKey)
    }

    // MARK: - Live: the real model over realistic talks

    /// `-triallive 1`: the same learner, but only the TALKS are written here.
    /// The coach, the level and the test are made by the real model through
    /// the signed-in account (`-devEmail` / `-devPassword`), exactly as on a
    /// phone whose free minutes just ran out.
    static var liveStarted = false

    static func seedLiveTalks(now: Date = Date()) {
        TrialReportStore.reset()
        for s in SessionStore.shared.load() { SessionStore.shared.delete(id: s.id) }
        let uid = UUID()
        let cal = Calendar.current
        func day(_ back: Int, _ hour: Int) -> Date {
            cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now))!.addingTimeInterval(Double(hour) * 3600)
        }
        typealias Line = (role: TurnRole, text: String, seconds: Int, fixes: [TurnFix], better: String?)
        func u(_ t: String, _ sec: Int, _ fixes: [TurnFix] = [], better: String? = nil) -> Line { (.user, t, sec, fixes, better) }
        func f(_ t: String) -> Line { (.fluentSelf, t, max(3, t.count / 14), [], nil) }
        let talks: [(start: Date, origin: SessionOrigin, topic: String?, offered: [String], lines: [Line])] = [
            (day(2, 20), .free, nil, ["what you do day to day", "walk me through"], [
                f("Hey, it's you, a few years from now. I just want to hear about your days. What do you do?"),
                u("Uh, I am working in a startup since three years. I am product manager.", 9,
                  [TurnFix(was: "I am working in a startup since three years", now: "I've been working at a startup for three years", why: "지금까지 이어지는 일은 현재완료 진행형과 for를 써요."),
                   TurnFix(was: "I am product manager", now: "I'm a product manager", why: "직업 앞에는 a가 필요해요.")],
                  better: "I've been working at a startup for three years. I'm a product manager."),
                f("Oh nice, three years is a long time at a startup. Walk me through what you do day to day."),
                u("Every day I have many meetings. And I talk with the developers, and then I write the plan, and then we decide.", 14),
                f("That sounds like a lot of talking. Which meeting do you like least?"),
                u("The weekly meeting. It is very long and very boring. My boss explained me the plan again and again.", 12,
                  [TurnFix(was: "My boss explained me the plan", now: "My boss explained the plan to me", why: "explain 뒤에는 내용이 먼저 오고, 사람은 to와 함께 와요.")],
                  better: "The weekly meeting. It's long and pretty boring, and my boss explains the plan to me again and again."),
                f("Ha, the same plan every week. What would you change about that meeting?"),
                u("I want to make it short. Maybe thirty minutes. It is good for everyone.", 9),
            ]),
            (day(1, 8), .scenario, "Pitching a new feature to my team", ["push back on", "a good fit", "keep it short"], [
                f("Okay, I'm your teammate. You wanted to pitch the new onboarding feature?"),
                u("Yes. I think new users are confused in the first day. So I want to make a guide.", 10),
                f("Makes sense. But what if the developers push back on the timeline?"),
                u("I will explain them why it is important. The users leave the app very fast.", 9,
                  [TurnFix(was: "I will explain them why", now: "I'll explain to them why", why: "explain 다음에 사람을 바로 쓰지 않고 to를 붙여요.")],
                  better: "I'll explain to them why it matters. Users are leaving the app really fast."),
                f("Good point. Do you have numbers to show them?"),
                u("Yes, we lost forty percent of users in the first week. It is very bad number.", 10,
                  [TurnFix(was: "It is very bad number", now: "That's a really bad number", why: "셀 수 있는 명사 앞에는 a가 필요해요.")],
                  better: "Yes, we lost forty percent of users in the first week. That's a really bad number."),
                f("That's a strong argument. Honestly, it sounds like a good fit for this quarter. Keep it short, two slides at most."),
                u("Okay, I will make two slides. Thank you, it is good advice.", 7),
            ]),
            (now.addingTimeInterval(-3 * 3600), .news, "A four-day work week", ["the trade-off", "I'm all for it"], [
                f("Did you see the news? Some companies are trying a four-day work week."),
                u("Yes, I saw it yesterday. I think it is good idea but it is difficult for startups.", 10,
                  [TurnFix(was: "it is good idea", now: "it's a good idea", why: "idea 앞에 a가 빠졌어요.")],
                  better: "Yes, I saw it yesterday. I think it's a good idea, but it's hard for startups."),
                f("Why harder for startups? What's the trade-off for you?"),
                u("Because we have small team. If one person is not there, the work stops. I am working here since three years and it was always like this.", 15,
                  [TurnFix(was: "I am working here since three years", now: "I've been working here for three years", why: "지금까지 이어지는 일은 현재완료 진행형과 for를 써요.")],
                  better: "Because we're a small team, so if one person is out, the work stops. I've been working here for three years, and it's always been like that."),
                f("That's real. If you could choose, would you take Fridays off?"),
                u("Of course! I will go hiking with my family. My daughter likes the mountain very much.", 10),
            ]),
        ]
        for talk in talks {
            var t = talk.start
            var turns: [Turn] = []
            for line in talk.lines {
                var turn = Turn(id: UUID(), role: line.role, audioURL: nil, transcript: line.text,
                                durationMs: line.seconds * 1000, timestamp: t, suggestion: nil)
                if let better = line.better {
                    turn.suggestion = TurnSuggestion(alternative: better, reason: "", fixes: line.fixes)
                }
                turns.append(turn)
                t = t.addingTimeInterval(Double(line.seconds) + 25)
            }
            var summary = SessionSummary(phrasesUsed: [], newPatternsDetected: [], suggestedDrills: [],
                                         overallNote: "", scorecard: nil)
            summary.expressionsOffered = talk.offered
            SessionStore.shared.save(Session(
                id: UUID(), userId: uid, targetLanguage: "en", mode: .conversation,
                topic: talk.topic, startedAt: talk.start, endedAt: t,
                turns: turns, summary: summary, origin: talk.origin))
        }
        for r in WeeklyReportStore.shared.load() { WeeklyReportStore.shared.delete(id: r.id) }
        LearningPurposeStore.purposes = [.work]
    }

    /// Debug sign-in with the dev account, so the model calls are real.
    static func signIn() async -> Bool {
        let d = UserDefaults.standard
        guard let email = d.string(forKey: "devEmail"), let password = d.string(forKey: "devPassword") else { return false }
        do {
            try await SupabaseProvider.shared.auth.signIn(email: email, password: password)
            return true
        } catch {
            print("TRIAL LIVE sign-in failed:", error)
            return false
        }
    }

    private static func demoTest(start: Date, now: Date) -> WeeklyTest {
        func item(_ kind: WeeklyTestItem.Kind, _ prompt: String, _ answer: String, _ options: [String],
                  rule: String? = nil, note: String? = nil) -> WeeklyTestItem {
            WeeklyTestItem(id: UUID(), kind: kind, prompt: prompt, answer: answer, options: options,
                           note: note, rule: rule)
        }
        let items = [
            item(.meaning, "마감, 기한", "deadline", ["deadline", "budget", "timeline", "meeting"]),
            item(.gap, "If they ___ the timeline, just ask what they'd cut.", "push back on",
                 ["push back on", "get back to", "figure out", "walk through"]),
            item(.translate, "나 여기서 3년째 일하고 있어.", "I've been working here for three years.",
                 ["I've", "been", "working", "here", "for", "three", "years.", "since", "am"],
                 rule: "현재완료 진행형 + for", note: "과거부터 지금까지 이어지는 일은 have been -ing와 for를 써요."),
            item(.meaning, "책임지고 있는, 담당하는", "in charge of", ["in charge of", "on the same page", "a good fit", "keep it short"]),
            item(.gap, "Can you ___ me ___ how it works?", "walk me through",
                 ["walk me through", "get back to", "push back on", "figure out"]),
            item(.translate, "그가 나한테 계획을 설명해 줬어.", "He explained the plan to me.",
                 ["He", "explained", "the", "plan", "to", "me.", "me"],
                 rule: "explain + 내용 + to 사람", note: "explain 다음엔 내용이 먼저 와요."),
            item(.upgrade, "It's a good plan.", "solid", ["solid", "huge", "busy", "short"]),
            item(.meaning, "알아내다, 해결하다", "figure out", ["figure out", "push back on", "get back to", "deadline"])
        ]
        let wrong: Set<Int> = [2, 5]
        let answers = items.enumerated().map { i, it in
            WeeklyTestAnswer(itemId: it.id, given: wrong.contains(i) ? it.options.last ?? "" : it.answer,
                             correct: !wrong.contains(i), at: now.addingTimeInterval(Double(i) * 20 - 400))
        }
        var test = WeeklyTest(id: UUID(), targetLanguage: "en", periodStart: start, periodEnd: now,
                              createdAt: now.addingTimeInterval(-500), items: items)
        test.startedAt = now.addingTimeInterval(-500)
        test.finishedAt = now.addingTimeInterval(-200)
        test.answers = answers
        test.bestStreak = 3
        test.appliedAt = now.addingTimeInterval(-200)
        return test
    }
}
#endif
