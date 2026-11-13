import XCTest
@testable import FutureVoice

/// French as a TARGET language (2026-11-13). The wordlist's headwords and the
/// form table come out of the same Lexique rules (scripts/build-fr-wordlist.py),
/// and `FrenchMorph` reads a word in its sentence; these pin that speech and
/// the list meet, and that the two context readings hold.
final class FrenchTargetTests: XCTestCase {
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        UserDefaults.standard.set("fr", forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    func testFrenchIsSelectable() {
        XCTAssertTrue(LanguageCatalog.selectableTargets.contains { $0.code == "fr" })
    }

    func testPoolLoadsWithEveryBand() {
        XCTAssertGreaterThan(CoreVocabulary.total, 8000)
        for level in CEFRLevel.allCases {
            XCTAssertGreaterThan(CoreVocabulary.total(at: level), 500, "\(level)")
        }
        // The hand core caps what subtitles bury.
        XCTAssertEqual(CoreVocabulary.level(of: "décembre"), .a1)
        XCTAssertEqual(CoreVocabulary.level(of: "cuisine"), .a1)
        XCTAssertEqual(CoreVocabulary.level(of: "sœur"), .a1)
        // Left out on purpose, never graded.
        XCTAssertNil(CoreVocabulary.level(of: "être"))
        XCTAssertTrue(CoreVocabulary.isUngraded("être"))
    }

    func testSpeechLemmasLandOnHeadwords() {
        let said = [
            "Hier j'ai mangé une pomme avec ma grand-mère et après on est allés au marché.",
            "Mes frères habitent dans une petite ville près de la plage.",
            "Tu peux m'expliquer comment aller à la gare ?",
            "Je cherche un appartement moins cher parce que le loyer a augmenté.",
        ]
        let lemmas = VocabStore.lemmas(in: said)
        for word in ["manger", "pomme", "grand-mère", "marché", "frère", "habiter",
                     "petit", "ville", "plage", "expliquer", "gare", "chercher",
                     "appartement", "cher", "loyer", "augmenter"] {
            XCTAssertTrue(lemmas.contains(word), "lemma \(word) not produced")
            XCTAssertNotNil(CoreVocabulary.level(of: word), "\(word) not in the pool")
        }
        XCTAssertFalse(lemmas.contains("l'"))
    }

    /// The two readings the table can't decide alone.
    func testContextReadings() {
        func lemmas(_ s: String) -> [String] { FrenchMorph.analyze(s).compactMap { $0.entry?.lemma } }
        XCTAssertTrue(lemmas("L'été dernier, il faisait chaud.").contains("été"))
        XCTAssertFalse(lemmas("J'ai été malade.").contains("été"))
        XCTAssertTrue(lemmas("Je suis fatigué.").contains("fatigué"))
        XCTAssertTrue(lemmas("J'ai aimé le film.").contains("aimer"))
        // "suis" is être, never suivre (Apple's tagger says suivre).
        XCTAssertEqual(FrenchMorph.lemma(of: "suis"), "être")
        // Elision and words that keep their apostrophe or hyphen.
        XCTAssertEqual(FrenchMorph.words(in: "l’école").map(\.word), ["l’", "école"])
        XCTAssertEqual(FrenchMorph.words(in: "aujourd'hui").map(\.word), ["aujourd'hui"])
        XCTAssertEqual(FrenchMorph.words(in: "dis-moi").map(\.word), ["dis", "moi"])
        // Lexique writes soeur; speech writes sœur.
        XCTAssertEqual(FrenchMorph.lemma(of: "soeurs"), "sœur")
    }

    func testFormsReachHeadwordsWithoutATagger() {
        XCTAssertEqual(VocabStore.lookupKey(for: "Mangé"), "manger")
        XCTAssertEqual(VocabStore.lookupKey(for: "fatiguées"), "fatigué")
        XCTAssertEqual(CoreVocabulary.level(ofSurface: "frères"), .a1)
        let off = VocabStore.offListContentWords(in: ["Mon amie Camille travaille comme plombière à Marseille."])
        XCTAssertNil(off["camille"])
        XCTAssertNil(off["marseille"])
    }

    func testWordClassesComeFromTheTable() {
        XCTAssertTrue(WordClass.classes(of: "manger", language: "fr").contains(.verb))
        XCTAssertTrue(WordClass.classes(of: "pomme", language: "fr").contains(.noun))
        XCTAssertTrue(WordClass.classes(of: "rouge", language: "fr").contains(.adjective))
    }

    /// Two accents, Parisian the default; the server reads them from the words.
    func testFrenchAccentsAreOfferedAndReadableByTheServer() {
        let options = VoiceAccentCatalog.options(for: "fr")
        XCTAssertEqual(options.map(\.id), ["fr-FR", "fr-CA"])
        XCTAssertEqual(VoiceAccentCatalog.defaultAccent(for: "fr")?.id, "fr-FR")
        XCTAssertTrue(options[0].prompt.lowercased().contains("parisian french"))
        XCTAssertTrue(options[1].prompt.lowercased().contains("canadian french"))
    }

    func testFrenchPresetsSpeakFrench() {
        let slot = VoicePreset.catalog[0].id
        XCTAssertNotEqual(VoicePreset.speaking(slot, in: "fr"), slot)
        XCTAssertEqual(VoicePreset.catalog[0].name(in: "fr"), "Emmanuelle")
    }

    func testNumbersReadTheFrenchWays() {
        let r = ShadowEngine.readings(of: "97", language: "fr")
        XCTAssertTrue(r.contains("quatre vingt dix sept"))
        XCTAssertTrue(r.contains("nonante sept"))
        XCTAssertTrue(ShadowEngine.readings(of: "21", language: "fr").contains("vingt et une"))
        XCTAssertTrue(ShadowEngine.readings(of: "1985", language: "fr").contains("dix neuf cent quatre vingt cinq"))
    }

    func testSampleScriptAndExams() {
        XCTAssertNotNil(SpeechLibrary.builtIn(for: "fr"))
        XCTAssertEqual(ExamKind.options(for: "fr"), [.delf, .tcf, .tef, .opic])
        for exam in ExamKind.options(for: "fr") {
            XCTAssertFalse(ExamTopics.topics(for: exam, language: "fr").isEmpty, exam.name)
        }
    }
}
