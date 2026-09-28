import XCTest
@testable import FutureVoice

/// A preset id is a SLOT: stored as the English voice, spoken by the target
/// language's own voice where one was picked (`VoicePreset.speaking`).
final class VoicePresetSlotTests: XCTestCase {
    func testKoreanAndJapaneseResolveEverySlot() {
        for lang in ["ko", "ja"] {
            let spoken = VoicePreset.catalog.map { VoicePreset.speaking($0.id, in: lang) }
            XCTAssertEqual(Set(spoken).count, VoicePreset.catalog.count, lang)
            for (slot, voice) in zip(VoicePreset.catalog, spoken) {
                XCTAssertNotEqual(slot.id, voice, "\(lang) \(slot.displayName)")
            }
        }
    }

    func testEnglishAndGermanKeepTheOriginals() {
        for lang in ["en", "de"] {
            for slot in VoicePreset.catalog {
                XCTAssertEqual(VoicePreset.speaking(slot.id, in: lang), slot.id)
            }
        }
    }

    func testNonPresetVoicesPassThrough() {
        XCTAssertEqual(VoicePreset.speaking("someClone123", in: "ko"), "someClone123")
    }

    func testStockIdentityDropsNationalityOnlyWhereRevoiced() {
        let paige = StockPerson.catalog[0]
        XCTAssertTrue(paige.identity(in: "en").contains("American"))
        XCTAssertFalse(paige.identity(in: "ko").contains("American"))
        XCTAssertTrue(paige.identity(in: "ko").hasPrefix("시안 — twenties"))
    }
}

extension VoicePresetSlotTests {
    func testBuiltinPersonIsNamedPerLanguage() {
        let paige = StockPerson.catalog[0]
        XCTAssertEqual(paige.voice.name(in: "en"), "Paige")
        XCTAssertEqual(paige.voice.name(in: "de"), "Paige")
        XCTAssertEqual(paige.voice.name(in: "ko"), "시안")
        XCTAssertTrue(paige.identity(in: "ko").hasPrefix("시안 — twenties"))

        var row = Counterpart(id: paige.localId, name: "Paige", relationship: "",
                              background: paige.identity, conversationStyle: "",
                              voicePresetId: paige.voice.id)
        row.remoteId = paige.remoteKey
        XCTAssertEqual(StockPerson.localized(row, language: "ko").name, "시안")
        XCTAssertEqual(StockPerson.localized(row, language: "en").name, "Paige")

        var mine = row
        mine.remoteId = nil
        XCTAssertEqual(StockPerson.localized(mine, language: "ko").name, "Paige")
    }
}
