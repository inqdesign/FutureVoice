import XCTest
@testable import FutureVoice

final class SpeechAnalyzerTests: XCTestCase {

    func testPaceInsideBandIsFullMarks() {
        XCTAssertEqual(SpeechAnalyzer.paceScore(rate: 140, band: 120...160), 100)
        XCTAssertEqual(SpeechAnalyzer.paceScore(rate: 0, band: 120...160), 0)
        // 10% too fast → 80.
        XCTAssertEqual(SpeechAnalyzer.paceScore(rate: 176, band: 120...160), 80)
    }

    func testSentenceBreaksExcludeTheLastSentence() {
        XCTAssertEqual(SpeechAnalyzer.sentenceBreaks(in: "One. Two! Three?"), 2)
        XCTAssertEqual(SpeechAnalyzer.sentenceBreaks(in: "Wait... what?"), 1)
        XCTAssertEqual(SpeechAnalyzer.sentenceBreaks(in: "音は波です。耳に届きます。"), 1)
    }

    func testFillersAreCountedAndRemoved() {
        let said = "So um sound is uh a wave"
        XCTAssertEqual(SpeechAnalyzer.countFillers(in: said, script: "So sound is a wave.", language: "en"), 2)
        XCTAssertEqual(SpeechAnalyzer.removingFillers(said, language: "en"), "So sound is a wave")
        // Japanese has no spaces: substrings.
        XCTAssertEqual(SpeechAnalyzer.countFillers(in: "えっと音はえー波です", script: "音は波です", language: "ja"), 2)
    }

    func testFillerInTheScriptIsNotTheReadersFault() {
        XCTAssertEqual(SpeechAnalyzer.countFillers(in: "Er hat hm gesagt", script: "Er hat hm gesagt.", language: "de"), 0)
    }

    func testPerfectReadScoresHigh() {
        let script = "Sound is a wave. It travels through the air."
        let env = SpeechAnalyzer.Envelope(firstVoice: 0, lastVoice: 4, silences: [0.4],
                                          phrases: [(-20, -21), (-20, -22)])
        let m = SpeechAnalyzer.analyze(script: script, transcript: "Sound is a wave it travels through the air",
                                       language: "en", envelope: env)
        XCTAssertEqual(m.accuracy, 100)
        XCTAssertEqual(m.breaks, 1)
        XCTAssertEqual(m.pausesAtBreaks, 1)
        XCTAssertEqual(m.fillers, 0)
        XCTAssertTrue(m.missed.isEmpty)
        // 9 words in 4 s = 135 wpm.
        XCTAssertEqual(m.rate, 135)
        XCTAssertGreaterThanOrEqual(m.overall, 95)
    }

    func testSkippedWordsAreListedInScriptOrder() {
        let m = SpeechAnalyzer.analyze(script: "Sound is a wave of tiny changes in pressure.",
                                       transcript: "Sound is a wave in pressure",
                                       language: "en", envelope: nil)
        XCTAssertEqual(m.missed, ["of tiny changes"])
        XCTAssertLessThan(m.accuracy, 100)
    }

    func testStallsCostThePauseScore() {
        let script = "One. Two. Three."
        let calm = SpeechAnalyzer.Envelope(firstVoice: 0, lastVoice: 3, silences: [0.5, 0.5], phrases: [])
        let stalled = SpeechAnalyzer.Envelope(firstVoice: 0, lastVoice: 6, silences: [0.5, 2.5], phrases: [])
        let a = SpeechAnalyzer.analyze(script: script, transcript: "one two three", language: "en", envelope: calm)
        let b = SpeechAnalyzer.analyze(script: script, transcript: "one two three", language: "en", envelope: stalled)
        XCTAssertEqual(a.pauseScore, 100)
        XCTAssertEqual(b.hesitations, 1)
        XCTAssertLessThan(b.pauseScore, a.pauseScore)
    }

    func testFadingAtSentenceEndsCostsSteadiness() {
        XCTAssertEqual(SpeechAnalyzer.steadinessScore([(-20, -21), (-21, -22)]), 100)
        XCTAssertLessThan(SpeechAnalyzer.steadinessScore([(-20, -32), (-21, -33)]), 50)
    }

    func testEnvelopeFindsPausesBetweenPhrases() {
        // 1 s voice, 0.5 s silence, 1 s voice, at 10 ms blocks.
        let levels = [Float](repeating: 0.5, count: 100) + [Float](repeating: 0.001, count: 50)
            + [Float](repeating: 0.5, count: 100)
        let env = SpeechAnalyzer.envelope(levels: levels, blockSeconds: 0.01)
        XCTAssertNotNil(env)
        XCTAssertEqual(env?.silences.count, 1)
        XCTAssertEqual(env?.silences.first ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(env?.speakingSeconds ?? 0, 2.5, accuracy: 0.01)
        XCTAssertEqual(env?.phrases.count, 2)
    }

    func testPlannedLengthFollowsTheLanguagesPace() {
        XCTAssertEqual(SpeechLibrary.plannedUnits(seconds: 60, language: "en"), 140)
        XCTAssertEqual(SpeechLibrary.plannedUnits(seconds: 120, language: "ko"), 570)
        XCTAssertEqual(SpeechLibrary.units(in: "음, 소리는 파동입니다.", language: "ko"), 9)
    }

    func testEveryTargetHasABundledScript() {
        for code in ["en", "ko", "ja", "de"] {
            let script = SpeechLibrary.builtIn(for: code)
            XCTAssertNotNil(script, code)
            let seconds = SpeechLibrary.estimatedSeconds(script?.body ?? "", language: code)
            XCTAssertTrue((45...95).contains(seconds), "\(code): \(seconds)s")
        }
    }
}

final class SpeechPrompterTrackTests: XCTestCase {

    func testFollowsTheVoiceForward() {
        let track = SpeechPrompterTrack(script: "Sound is a wave. It travels through the air as tiny changes in pressure.",
                                        language: "en")
        var cursor = 0
        cursor = track.advance(current: cursor, heard: "sound is a")
        XCTAssertEqual(cursor, 3)
        cursor = track.advance(current: cursor, heard: "sound is a wave it travels through")
        XCTAssertEqual(cursor, 7)
    }

    func testNothingNewMeansNoMove() {
        let track = SpeechPrompterTrack(script: "Sound is a wave. It travels through the air.", language: "en")
        XCTAssertEqual(track.advance(current: 4, heard: "hello there"), 4)
        XCTAssertEqual(track.advance(current: 0, heard: ""), 0)
    }

    func testDoesNotJumpPastTheWindow() {
        let filler = Array(repeating: "and then", count: 40).joined(separator: " ")
        let track = SpeechPrompterTrack(script: "Start here. \(filler) the very distant ending words", language: "en")
        // The end of the script matches, but it is far beyond the window.
        XCTAssertEqual(track.advance(current: 0, heard: "the very distant ending words"), 0)
    }

    func testKoreanFollowsBySyllable() {
        let track = SpeechPrompterTrack(script: "소리는 파동입니다. 공기의 압력이 높아졌다 낮아집니다.", language: "ko")
        // The recognizer spaced it its own way.
        let cursor = track.advance(current: 0, heard: "소리는파동 입니다 공기 의")
        XCTAssertEqual(track.words[cursor - 1].text, "공기의")
    }

    func testJapaneseCutsIntoPieces() {
        let track = SpeechPrompterTrack(script: "音は波です。空気の圧力が上がったり下がったりします。", language: "ja")
        XCTAssertGreaterThan(track.words.count, 3)
        XCTAssertEqual(track.words.map(\.text).joined(), "音は波です。空気の圧力が上がったり下がったりします。")
    }

    func testParagraphsSurvive() {
        let track = SpeechPrompterTrack(script: "First paragraph.\n\nSecond one.", language: "en")
        XCTAssertEqual(track.paragraphs.count, 2)
    }
}

final class SpeechOwnScriptTests: XCTestCase {
    func testDefaultTitleIsTheFirstSentence() {
        XCTAssertEqual(SpeechOwnScriptSheet.defaultTitle("Good evening everyone. Tonight I want to talk."),
                       "Good evening everyone")
        XCTAssertEqual(SpeechOwnScriptSheet.defaultTitle("안녕하세요. 오늘은"), "안녕하세요")
        let long = String(repeating: "word ", count: 30)
        XCTAssertTrue(SpeechOwnScriptSheet.defaultTitle(long).hasSuffix("…"))
    }

    func testOwnIsNotOfferedToTheWriter() {
        XCTAssertFalse(SpeechGenre.writable.contains(.own))
        XCTAssertEqual(SpeechGenre.writable.count, 5)
    }
}

import SwiftUI
import CoreImage

final class SpeechVideoComposerTests: XCTestCase {
    /// Draws one frame from a fake camera picture and writes it out, so the
    /// video's layout can be looked at (`[speech-frame] <path>` in the log).
    @MainActor
    func testComposesTheTakeScreen() throws {
        let script = SpeechLibrary.builtIn(for: "en")!
        let track = SpeechPrompterTrack(script: script.body, language: "en")
        let layout = SpeechVideoComposer.Layout(
            canvas: CGSize(width: 402, height: 715),
            prompter: CGRect(x: 0, y: 0, width: 402, height: 351.5),
            card: CGRect(x: 12, y: 363.5, width: 378, height: 339.5),
            cardRadius: 24, background: .white)
        let scale = SpeechVideoComposer.scale(for: layout)
        let renderer = ImageRenderer(content: SpeechPrompterColumn(track: track, cursor: 0, language: "en",
                                                                    textSize: 28, width: 402, measures: false,
                                                                    onCurrentWord: { _ in }))
        renderer.scale = scale
        let column = SpeechVideoComposer.Column(text: try XCTUnwrap(renderer.cgImage), scale: scale)
        let composer = SpeechVideoComposer()
        let cam = CIImage(color: CIColor(red: 0.6, green: 0.45, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 720, height: 1280))
        let prompter = SpeechVideoComposer.Prompter(offset: 20)
        let frame = composer.compose(
            camera: cam, layout: layout,
            column: composer.visible(column, layout: layout, prompter: prompter),
            prompter: prompter)
        let ctx = CIContext()
        let cg = try XCTUnwrap(ctx.createCGImage(frame, from: CGRect(x: 0, y: 0, width: 1080, height: 1920)))
        XCTAssertEqual(cg.width, 1080)
        XCTAssertEqual(cg.height, 1920)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-frame.png")
        try XCTUnwrap(UIImage(cgImage: cg).pngData()).write(to: url)
        print("[speech-frame] \(url.path)")
    }
}

final class ShadowLineEndTests: XCTestCase {
    func testEnglishEndIsHeard() {
        let line = "Soak it all in, right?"
        XCTAssertTrue(ShadowEngine.heardLineEnd(target: line, heard: "soak it all in right", language: "en"))
        XCTAssertFalse(ShadowEngine.heardLineEnd(target: line, heard: "soak it all", language: "en"))
        // A stray word after the end still counts.
        XCTAssertTrue(ShadowEngine.heardLineEnd(target: line, heard: "soak it all in right okay", language: "en"))
    }

    func testDigitsAreSpelledOut() {
        XCTAssertTrue(ShadowEngine.heardLineEnd(target: "Meet me at gate 12", heard: "meet me at gate twelve", language: "en"))
    }

    func testKoreanByCharacters() {
        let line = "오늘은 날씨가 정말 좋네요."
        XCTAssertTrue(ShadowEngine.heardLineEnd(target: line, heard: "오늘은 날씨가 정말좋네요", language: "ko"))
        XCTAssertFalse(ShadowEngine.heardLineEnd(target: line, heard: "오늘은 날씨가", language: "ko"))
    }

    func testTooShortToTell() {
        XCTAssertFalse(ShadowEngine.heardLineEnd(target: "Hi", heard: "hi", language: "en"))
    }
}
