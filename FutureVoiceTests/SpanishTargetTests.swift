import XCTest
@testable import FutureVoice

/// Spanish as a TARGET language (2026-10-15). The wordlist's headwords are
/// whatever NLTagger calls the lemma in context, because that is what
/// `VocabStore.lemmas(in:)` makes of a learner's speech; these pin that the
/// two meet on ordinary sentences.
final class SpanishTargetTests: XCTestCase {
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        UserDefaults.standard.set("es", forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    func testSpanishIsSelectable() {
        XCTAssertTrue(LanguageCatalog.selectableTargets.contains { $0.code == "es" })
    }

    func testPoolLoadsWithEveryBand() {
        XCTAssertGreaterThan(CoreVocabulary.total, 8000)
        for level in CEFRLevel.allCases {
            XCTAssertGreaterThan(CoreVocabulary.total(at: level), 500, "\(level)")
        }
        // The hand core caps what subtitles bury.
        XCTAssertEqual(CoreVocabulary.level(of: "diciembre"), .a1)
        XCTAssertEqual(CoreVocabulary.level(of: "cocina"), .a1)
        // Left out on purpose, never graded.
        XCTAssertNil(CoreVocabulary.level(of: "estar"))
        XCTAssertTrue(CoreVocabulary.isUngraded("estar"))
    }

    func testSpeechLemmasLandOnHeadwords() {
        let said = [
            "Ayer comí una manzana con mi abuela y luego fuimos al mercado.",
            "Mis hermanos viven en una ciudad pequeña cerca de la playa.",
            "¿Me puedes explicar cómo llego a la estación de tren?",
            "Estoy buscando un piso más barato porque el alquiler subió mucho.",
        ]
        let lemmas = VocabStore.lemmas(in: said)
        for word in ["comer", "manzana", "abuela", "mercado", "hermano", "vivir",
                     "ciudad", "pequeño", "playa", "explicar", "llegar", "estación",
                     "tren", "buscar", "piso", "barato", "alquiler", "subir"] {
            XCTAssertTrue(lemmas.contains(word), "lemma \(word) not produced")
            XCTAssertNotNil(CoreVocabulary.level(of: word), "\(word) not in the pool")
        }
    }

    /// iOS has no Spanish lemma model; these go through `SpanishMorph`.
    func testFormsReachHeadwordsWithoutATagger() {
        XCTAssertEqual(VocabStore.lookupKey(for: "Comí"), "comer")
        XCTAssertEqual(VocabStore.lookupKey(for: "cansadas"), "cansado")
        XCTAssertEqual(CoreVocabulary.level(ofSurface: "hermanos"), .a1)
        // -a and -o are two nouns, not one word twice.
        XCTAssertNotNil(CoreVocabulary.level(of: "casa"))
        XCTAssertNotNil(CoreVocabulary.level(of: "caso"))
        // The fluent self's words off the graded list are still found, names aren't.
        let off = VocabStore.offListContentWords(in: ["Mi amiga Lucía trabaja de fontanera en Valencia."])
        XCTAssertNil(off["lucía"])
        XCTAssertNil(off["valencia"])
    }

    func testWordClassesComeFromTheTable() {
        XCTAssertTrue(WordClass.classes(of: "comer", language: "es").contains(.verb))
        XCTAssertTrue(WordClass.classes(of: "manzana", language: "es").contains(.noun))
        XCTAssertTrue(WordClass.classes(of: "rojo", language: "es").contains(.adjective))
    }

    func testSpanishPresetsSpeakSpanish() {
        let slot = VoicePreset.catalog[0].id
        XCTAssertNotEqual(VoicePreset.speaking(slot, in: "es"), slot)
        XCTAssertFalse(VoicePreset.catalog[0].name(in: "es").isEmpty)
    }
}
