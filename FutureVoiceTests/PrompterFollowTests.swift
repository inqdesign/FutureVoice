import XCTest
@testable import FutureVoice

/// Feeds a script to the prompter as growing partials, the way the
/// recognizer delivers them, and checks the cursor reaches the end.
final class PrompterFollowTests: XCTestCase {
    private func walk(_ body: String) -> (Int, Int) {
        let track = SpeechPrompterTrack(script: body, language: "en")
        let spoken = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var cursor = 0
        var heard = ""
        for w in spoken {
            heard += (heard.isEmpty ? "" : " ") + w
            cursor = track.advance(current: cursor, heard: heard)
        }
        return (cursor, track.words.count)
    }

    func testScriptsFollow() {
        let yeoh = "Thank you. Thank you.\n\nFor all the little boys and girls who look like me, watching tonight, this is the beacon of hope and possibilities. This is proof that dreams, dream big, and dreams do come true. And ladies, don't let anybody tell you you are ever past your prime. Never give up."
        let cream = "Ladies and gentlemen, before I say anything, look at my face. Up close. No filter, no foundation, nothing. Just my real skin, at the end of a very long day."
        for (name, body) in [("yeoh", yeoh), ("cream", cream)] {
            let (c, n) = walk(body)
            XCTAssertGreaterThan(c, n - 3, name)
        }
    }

    /// Say it again ends a take early on "the last word was heard", so the
    /// cursor must get there on the last word and not one word sooner.
    func testALineReachesItsEndOnItsLastWordOnly() {
        let lines: [(String, String)] = [
            ("en", "I went to the store and then I went to the store."),
            ("en", "I've been working here for two years, and I really like it."),
            ("en", "So what did you end up doing last weekend?"),
            ("ko", "어제 친구랑 저녁을 먹었는데 정말 맛있었어."),
            ("ko", "그래서 나는 회사에 다시 돌아가기로 했어."),
            ("de", "Ich habe gestern mit meinem Bruder telefoniert."),
        ]
        for (language, line) in lines {
            let track = SpeechPrompterTrack(script: line, language: language)
            let spoken = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            var cursor = 0
            var heard = ""
            for (i, word) in spoken.enumerated() {
                heard += (heard.isEmpty ? "" : " ") + word
                cursor = max(cursor, track.advance(current: cursor, heard: heard))
                if i < spoken.count - 1 {
                    XCTAssertLessThan(cursor, track.words.count, "\(line) after \(heard)")
                }
            }
            XCTAssertEqual(cursor, track.words.count, line)
        }
    }

    func testTheFirstWordIsHeardOnItsOwn() {
        let en = SpeechPrompterTrack(script: "So what did you do?", language: "en")
        XCTAssertTrue(en.opensWithFirstWord("So"))
        XCTAssertTrue(en.opensWithFirstWord("so what"))
        XCTAssertFalse(en.opensWithFirstWord(""))
        XCTAssertFalse(en.opensWithFirstWord("Um so"))
        let ko = SpeechPrompterTrack(script: "어제 친구랑 만났어.", language: "ko")
        XCTAssertTrue(ko.opensWithFirstWord("어제"))
        XCTAssertTrue(ko.opensWithFirstWord("어제친구랑"))
        XCTAssertFalse(ko.opensWithFirstWord("어"))
    }

    func testLitCharactersFollowTheLineAsDrawn() {
        let track = SpeechPrompterTrack(script: "Thank you so much.", language: "en")
        XCTAssertEqual(track.characterCount(throughWord: 0, in: "Thank you so much."), 0)
        XCTAssertEqual(track.characterCount(throughWord: 2, in: "Thank you so much."), 9)
        XCTAssertEqual(track.characterCount(throughWord: 4, in: "Thank you so much."), 18)
        XCTAssertEqual(track.characterCount(throughWord: 2, in: "Thank  you so much."), 10)
        // Past the end, or a line that doesn't carry the word: no crash, no overrun.
        XCTAssertEqual(track.characterCount(throughWord: 9, in: "Thank you so much."), 18)
        XCTAssertEqual(track.characterCount(throughWord: 2, in: "Thank them."), 5)
    }
}
