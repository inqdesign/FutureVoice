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
