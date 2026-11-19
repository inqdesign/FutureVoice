import XCTest
@testable import FutureVoice

/// Writes the LIVE scene prompt for `scripts/scene-subject-probe.py`
/// (2026-11-19): a situation the learner wrote, played with a person whose
/// profile is about something else. Skips unless
/// `TEST_RUNNER_PROMPT_DUMP_DIR` is set.
final class ScenePromptDumpTests: XCTestCase {

    private var learner: UserPersona {
        var p = UserPersona.empty
        p.displayName = "Minji"
        p.city = "Seoul"; p.country = "Korea"
        p.occupation = "Nurse"
        p.interests = ["climbing", "cooking", "films"]
        return p
    }

    private func climber(own: Bool) -> Counterpart {
        var c = Counterpart.empty
        c.name = "Jinwoo"
        c.relationship = own ? "Friend from the climbing gym" : ""
        c.relationshipKind = own ? "Friend" : nil
        c.background = "Product designer in Seoul. Spends every weekend bouldering and is training for his first outdoor lead climb."
        c.intro = c.background
        c.commonTopics = "climbing, bouldering routes, gym gear"
        c.conversationStyle = "easygoing, jokes a lot"
        if !own { c.remoteId = "pool-jinwoo" }
        return c
    }

    func testDumpScenePrompts() throws {
        guard let dir = ProcessInfo.processInfo.environment["PROMPT_DUMP_DIR"] else {
            throw XCTSkip("PROMPT_DUMP_DIR not set")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let situations = [
            "news": "I read a news story about dementia cases rising in people in their 50s and I want to talk about it",
            "landlord": "Telling him my landlord wants to raise the rent and asking what he would do",
        ]
        for lang in ["en", "ko"] {
            try ScenarioCurriculumEngine.systemPrompt(targetLanguage: lang, proficiency: .b1)
                .write(to: url.appendingPathComponent("scene-\(lang)-system.txt"), atomically: true, encoding: .utf8)
            for own in [false, true] {
                let c = climber(own: own)
                try CommonGround.block(learner: learner, counterpart: c)
                    .write(to: url.appendingPathComponent("scene-ground.txt"), atomically: true, encoding: .utf8)
                for (key, text) in situations {
                    let s = Scenario(environment: text, role: own ? c.relationship : "", notes: "")
                    let user = ScenarioCurriculumEngine.userMessage(
                        scenario: s, persona: learner, counterpart: c,
                        weakVocabAreas: [], recurringMistakes: [], targetLanguage: lang)
                    try user.write(to: url.appendingPathComponent("scene-\(lang)-\(key)-\(own ? "own" : "stranger").txt"),
                                   atomically: true, encoding: .utf8)
                }
            }
        }
    }

    /// The learner's situation is the subject; the common ground is only for
    /// the scenario that asks for it.
    func testWrittenSituationOutranksThePerson() {
        let c = climber(own: false)
        let written = ScenarioCurriculumEngine.userMessage(
            scenario: Scenario(environment: "Talking about a news story on dementia", role: "", notes: ""),
            persona: learner, counterpart: c, weakVocabAreas: [], recurringMistakes: [], targetLanguage: "en")
        XCTAssertFalse(written.contains("COMMON GROUND"))
        XCTAssertTrue(written.contains("THE SUBJECT IS THE SITUATION ABOVE"))
        XCTAssertFalse(written.contains("what they talk about"))

        let meeting = ScenarioCurriculumEngine.userMessage(
            scenario: Scenario(environment: "Talking with someone you've just met", role: "",
                               notes: "Build the scene on the COMMON GROUND given below."),
            persona: learner, counterpart: c, weakVocabAreas: [], recurringMistakes: [], targetLanguage: "en")
        XCTAssertTrue(meeting.contains("COMMON GROUND — start here") || meeting.contains("COMMON GROUND: none"))
    }

    func testCallWithASubjectDoesNotOpenOnThePerson() {
        let c = climber(own: false)
        let name = LanguageCatalog.englishName("en")
        let free = ConversationEngine.characterBlock(c, persona: learner, targetLanguage: "en", languageName: name)
        XCTAssertTrue(free.contains("COMMON GROUND"))
        XCTAssertTrue(free.contains("WHO YOU ARE IS NOT WHAT THE TALK IS ABOUT"))
        let subject = ConversationEngine.characterBlock(c, persona: learner, targetLanguage: "en",
                                                        languageName: name, subject: "environment=A news story about dementia")
        XCTAssertFalse(subject.contains("COMMON GROUND"))
        XCTAssertFalse(subject.contains("come in from something CONCRETE"))
        XCTAssertTrue(subject.contains("THIS CALL ALREADY HAS A SUBJECT"))
    }
}
