import XCTest
@testable import FutureVoice

/// Captures the end-of-talk SUMMARY request exactly as `SessionSummarizer`
/// builds it — same prompt function, transcript format, metrics and client
/// settings — for `scripts/purpose-probe.py summary` (2026-10-21), which runs
/// it on 3.6-flash and Claude Haiku side by side. Nothing is sent: the
/// client's DEBUG capture writes the body and stops. Does nothing unless the
/// runner passes `TEST_RUNNER_CAPTURE_DIR`.
final class SummaryCaptureTests: XCTestCase {

    private typealias Line = (role: TurnRole, text: String)

    /// Short real-shaped talks, learner errors included, one per target.
    private let talks: [(target: String, native: String, level: CEFRLevel, lines: [Line])] = [
        ("en", "ko", .a2, [
            (.fluentSelf, "Hey! How was your day?"),
            (.user, "Um, it was okay. I go to the office and I have many meeting."),
            (.fluentSelf, "Many meetings, huh? That sounds tiring. Were they long?"),
            (.user, "Yes, very long. My boss explain the new project for two hours."),
            (.fluentSelf, "Two hours! What's the project about?"),
            (.user, "It is about a app for the customer. We must finish until next month."),
            (.fluentSelf, "A month isn't much time. Are you excited or stressed?"),
            (.user, "A little bit stressed. But I think it will be fine, I'm working hard."),
            (.fluentSelf, "That's the spirit. What do you do to relax after work?"),
            (.user, "I usually watch Netflix. Yesterday I watched a korean drama until 2 am."),
        ]),
        ("en", "ko", .b1, [
            (.fluentSelf, "So, did you end up talking to your landlord?"),
            (.user, "Not yet. I am planning to, but every time I want to bring it up he is busy."),
            (.fluentSelf, "That's annoying. What do you want to say to him?"),
            (.user, "The heating is broken since three weeks and he didn't fix it. It's getting really cold."),
            (.fluentSelf, "Three weeks is a long time. Have you put it in writing?"),
            (.user, "Not yet, I think I will send him an email today and explain him the situation."),
            (.fluentSelf, "Good idea. A written record helps. Anything else going on this week?"),
            (.user, "My sister visits me on Saturday, so I need to clean my apartment. It's a mess honestly."),
        ]),
        ("ko", "en", .a2, [
            (.fluentSelf, "주말에 뭐 했어?"),
            (.user, "어... 친구랑 카페를 갔어. 그리고 영화를 봤어."),
            (.fluentSelf, "오, 무슨 영화 봤어?"),
            (.user, "한국 영화. 제목 잘 모르겠어. 근데 너무 재미있었어요."),
            (.fluentSelf, "재밌었구나. 무서운 영화였어?"),
            (.user, "아니, 슬픈 영화. 나는 많이 울었어. 친구는 안 울었어서 조금 부끄러웠어."),
            (.fluentSelf, "하하, 그럴 수 있지. 다음 주말에는 뭐 할 거야?"),
            (.user, "다음 주말에 부산에 갈 거야. 바다를 보고 싶어."),
        ]),
        ("ja", "ko", .a2, [
            (.fluentSelf, "最近どう？忙しい？"),
            (.user, "うん、ちょっと忙しい。毎日会社を行って、夜遅く帰る。"),
            (.fluentSelf, "大変だね。週末は休めた？"),
            (.user, "土曜日は友達と寿司が食べた。すごくおいしかったです。"),
            (.fluentSelf, "いいね！どこのお店？"),
            (.user, "駅の近くの店。安いし、おいしい。また行きたいだ。"),
            (.fluentSelf, "今度一緒に行こうよ。日曜日は何してた？"),
            (.user, "日曜日は家で寝た。疲れたから、何もしなかった。"),
        ]),
        ("de", "ko", .b1, [
            (.fluentSelf, "Na, wie war dein Wochenende?"),
            (.user, "Es war gut. Ich habe nach Berlin gefahren, um meine Freundin zu besuchen."),
            (.fluentSelf, "Schön! Was habt ihr gemacht?"),
            (.user, "Wir sind in ein Museum gegangen und danach wir haben gegessen in einem koreanischen Restaurant."),
            (.fluentSelf, "Koreanisch in Berlin, cool. War es gut?"),
            (.user, "Ja, aber es war nicht so authentisch. Meine Freundin hat gesagt, dass sie mag es trotzdem."),
            (.fluentSelf, "Und wie bist du zurückgekommen?"),
            (.user, "Mit dem Zug. Der Zug hatte eine Verspätung von eine Stunde, das war nervig."),
        ]),
        ("es", "ko", .a2, [
            (.fluentSelf, "¿Qué tal tu día?"),
            (.user, "Bien. Hoy yo trabajé mucho y estoy muy cansada."),
            (.fluentSelf, "Uf, ¿qué hiciste en el trabajo?"),
            (.user, "Tuve muchas reuniones. Mi jefe es muy exigente, siempre quiere todo para ayer."),
            (.fluentSelf, "Entiendo. ¿Y después del trabajo?"),
            (.user, "Fui al supermercado y compré frutas. Después cociné una sopa para mi familia."),
            (.fluentSelf, "¡Qué bien! ¿Te gusta cocinar?"),
            (.user, "Sí, me gusta mucho. Pero no tengo mucho tiempo durante la semana."),
        ]),
    ]

    @MainActor
    func testCaptureSummaryRequests() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTURE_DIR"] else {
            throw XCTSkip("CAPTURE_DIR not set")
        }
        let dir = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("summary")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        GeminiClient.captureDirectory = dir
        defer { GeminiClient.captureDirectory = nil }

        for talk in talks {
            var at = Date(timeIntervalSince1970: 1_792_000_000)
            let turns: [Turn] = talk.lines.map { line in
                at += 12
                return Turn(id: UUID(), role: line.role, audioURL: nil, transcript: line.text,
                            durationMs: line.role == .user ? 4000 : 0, timestamp: at, suggestion: nil)
            }
            let profile = LearnerProfile(id: UUID(), userId: UUID(), targetLanguage: talk.target,
                                         proficiencyLevel: talk.level, recurringMistakes: [],
                                         weakVocabAreas: [], strongPatterns: [], totalSessions: 3,
                                         totalSpeakingSeconds: 600, lastSessionAt: nil, summaryEmbedding: nil)
            // As SessionSummarizer.summarize builds it.
            let system = ConversationEngine.summarySystemPrompt(
                targetLanguage: talk.target, nativeLanguage: talk.native, profile: profile,
                expressionBudget: ConversationEngine.expressionBudget(
                    fluentTurns: turns.filter { $0.role == .fluentSelf }.count),
                talkDate: turns.last?.timestamp)
            let user = """
            transcript:
            \(ConversationEngine.formatTranscript(turns))

            metrics:
            \(ScorecardMetrics.compute(turns: turns).promptJSON())
            """
            do {
                let _: ClaudeSummaryPayload = try await GeminiClient.longRunning.sendJSONStreamAccumulating(
                    system: system,
                    messages: [GeminiClient.Message(role: .user, content: user)],
                    maxTokens: 8192, purpose: "summary",
                    idempotencyKey: "summary:capture:\(talk.target)-\(talk.level.rawValue)",
                    onPartial: { _ in })
                XCTFail("capture should stop the request")
            } catch is GeminiClient.CaptureStop {
                // written
            }
        }
    }
}
