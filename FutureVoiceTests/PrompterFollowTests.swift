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
}
