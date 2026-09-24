import XCTest
@testable import FutureVoice

/// `WordClass` groups headwords by the class a learner could read off the
/// word alone — the weekly test's meaning decoys are picked by it. The
/// tables (`word_classes_<code>.tsv`) answer for listed words; the rules
/// answer for the rest.
@MainActor
final class WordClassTests: XCTestCase {

    // MARK: Tables

    /// English comes from the CEFR-J/Octanove profiles — including the
    /// words the lone-word tagger gets wrong (abandon → "Interjection").
    func testEnglishTable() {
        XCTAssertEqual(WordClass.classes(of: "abandon", language: "en"), [.verb])
        XCTAssertEqual(WordClass.classes(of: "kitchen", language: "en"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "run", language: "en"), [.noun, .verb])
        XCTAssertEqual(WordClass.classes(of: "quickly", language: "en"), [.adverb])
        XCTAssertEqual(WordClass.classes(of: "beautiful", language: "en"), [.adjective])
        XCTAssertEqual(WordClass.classes(of: "Kitchen", language: "en"), [.noun], "lookup is case-blind")
    }

    /// German is orthography: capital = noun, -en = verb, else adjective,
    /// with the -en adjectives listed by hand.
    func testGermanTable() {
        XCTAssertEqual(WordClass.classes(of: "Haus", language: "de"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "verstehen", language: "de"), [.verb])
        XCTAssertEqual(WordClass.classes(of: "bitten", language: "de"), [.verb], "the tagger called this an adverb")
        XCTAssertEqual(WordClass.classes(of: "offen", language: "de"), [.adjective])
        XCTAssertEqual(WordClass.classes(of: "zufrieden", language: "de"), [.adjective])
        XCTAssertEqual(WordClass.classes(of: "schnell", language: "de"), [.adjective])
        XCTAssertEqual(WordClass.classes(of: "gestern", language: "de"), [.adjective], "adverbs share the adjective class")
        XCTAssertEqual(WordClass.classes(of: "erfahren", language: "de"), [.verb, .adjective])
        XCTAssertEqual(WordClass.classes(of: "unbeholfen", language: "de"), [.adjective], "participle adjective")
        XCTAssertEqual(WordClass.classes(of: "angesehen", language: "de"), [.adjective])
        XCTAssertEqual(WordClass.classes(of: "überlegen", language: "de"), [.verb, .adjective])
        XCTAssertEqual(WordClass.classes(of: "unterbrechen", language: "de"), [.verb], "unter- is not un-")
    }

    /// Japanese comes from JMdict: the deverbal nouns in い that the shape
    /// rule can't tell from an i-adjective, な-adjectives, suru-nouns.
    func testJapaneseTable() {
        XCTAssertEqual(WordClass.classes(of: "行く", language: "ja"), [.verb])
        XCTAssertEqual(WordClass.classes(of: "高い", language: "ja"), [.adjective])
        XCTAssertEqual(WordClass.classes(of: "違い", language: "ja"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "願い", language: "ja"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "静か", language: "ja"), [.naAdjective])
        XCTAssertTrue(WordClass.classes(of: "嫌い", language: "ja").contains(.naAdjective))
        XCTAssertEqual(WordClass.classes(of: "勉強", language: "ja"), [.noun], "a suru-noun is a noun")
        XCTAssertTrue(WordClass.classes(of: "一つ", language: "ja").contains(.noun))
        XCTAssertEqual(WordClass.classes(of: "犬", language: "ja"), [.noun])
    }

    /// Korean: 다 is a predicate, minus the nouns that end in 다.
    func testKoreanTable() {
        XCTAssertEqual(WordClass.classes(of: "가다", language: "ko"), [.predicate])
        XCTAssertEqual(WordClass.classes(of: "예쁘다", language: "ko"), [.predicate])
        XCTAssertEqual(WordClass.classes(of: "학교", language: "ko"), [.other])
        XCTAssertEqual(WordClass.classes(of: "바다", language: "ko"), [.other])
        XCTAssertEqual(WordClass.classes(of: "해마다", language: "ko"), [.other])
        XCTAssertEqual(WordClass.classes(of: "가다", language: "ko-KR"), [.predicate], "script-qualified codes read by base")
    }

    // MARK: Rules, for words off the list

    func testEnglishFallsBackToTheTagger() {
        XCTAssertEqual(WordClass.classes(of: "skateboarders", language: "en"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "unhurriedly", language: "en"), [.adverb])
    }

    /// The tagger is asked per language, not assumed English.
    func testTaggerIsAskedPerLanguage() throws {
        try XCTSkipUnless(WordClass.taggerSupports("de"), "no German lexical-class model on this OS")
        XCTAssertEqual(WordClass.lexicalTag("Adresse", language: "de"), "Noun")
        XCTAssertNil(WordClass.lexicalTag("가다", language: "ko"), "no Korean model: never 'OtherWord'")
        XCTAssertNil(WordClass.lexicalTag("行く", language: "ja"))
    }

    func testGermanFallsBackToOrthography() {
        XCTAssertEqual(WordClass.classes(of: "Zwischenbericht", language: "de"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "herumwurschteln", language: "de"), [.verb])
        XCTAssertEqual(WordClass.classes(of: "wehtun", language: "de"), [.verb])
        XCTAssertEqual(WordClass.classes(of: "knallgelb", language: "de"), [.adjective])
        XCTAssertEqual(WordClass.classes(of: "unausgegoren", language: "de"), [.adjective], "un- never starts a verb")
    }

    func testKoreanFallsBackToTheDictionaryForm() {
        XCTAssertEqual(WordClass.classes(of: "뿌리내리다", language: "ko"), [.predicate])
        XCTAssertEqual(WordClass.classes(of: "김치찌개", language: "ko"), [.other])
    }

    /// う-row = verb, い = i-adjective, katakana = loanword; polite set
    /// phrases, numerals in つ, doubled kana and a long-vowel う are not verbs.
    func testJapaneseFallsBackToTheEnding() {
        XCTAssertEqual(WordClass.classes(of: "食べすぎる", language: "ja"), [.verb])
        XCTAssertEqual(WordClass.classes(of: "ぬぐう", language: "ja"), [.verb])
        XCTAssertEqual(WordClass.classes(of: "はなしだす", language: "ja"), [.verb])
        XCTAssertEqual(WordClass.classes(of: "うすぐらい", language: "ja"), [.adjective])
        XCTAssertEqual(WordClass.classes(of: "ドーナツ", language: "ja"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "おまちしてます", language: "ja"), [.other])
        XCTAssertEqual(WordClass.classes(of: "お待ちください", language: "ja"), [.other], "not an い-adjective")
        XCTAssertEqual(WordClass.classes(of: "行っていらっしゃい", language: "ja"), [.other])
        XCTAssertEqual(WordClass.classes(of: "十一つ", language: "ja"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "ひとやつ", language: "ja"), [.noun])
        XCTAssertEqual(WordClass.classes(of: "ぺらぺら", language: "ja"), [.adverb])
        XCTAssertEqual(WordClass.classes(of: "ぬこう", language: "ja"), [.other], "a kana う after an お-row kana is a long vowel")
    }

    func testSameClassMatchesAnySharedClass() {
        XCTAssertTrue(WordClass.sameClass("run", "house", language: "en"))
        XCTAssertTrue(WordClass.sameClass("run", "decide", language: "en"))
        XCTAssertFalse(WordClass.sameClass("kitchen", "decide", language: "en"))
        XCTAssertTrue(WordClass.sameClass("zzqx", "house", language: "xx"), "unknown class allows anything")
    }
}

/// The meaning item's wrong choices: same class before same owner.
@MainActor
final class MeaningDecoyTests: XCTestCase {

    private var rng = WeeklyTestRandom(seed: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!)

    /// A verb's gloss gets verbs beside it even when the learner's own pool
    /// holds only nouns — the graded verbs outrank the own nouns.
    func testEnglishVerbTakesGradedVerbsOverOwnNouns() {
        let decoys = WeeklyTestEngine.meaningDecoys(
            for: "abandon", own: ["kitchen", "table", "onion", "abandon"],
            graded: ["negotiate", "table", "pursue", "chair", "hesitate"],
            language: "en", rng: &rng)
        XCTAssertEqual(decoys.count, 3)
        XCTAssertFalse(decoys.contains("abandon"))
        XCTAssertEqual(Set(decoys), ["negotiate", "pursue", "hesitate"])
    }

    /// Inside the class, the learner's own words lead the graded list.
    func testOwnWordsOfTheSameClassLead() {
        let decoys = WeeklyTestEngine.meaningDecoys(
            for: "decide", own: ["negotiate", "kitchen"],
            graded: ["pursue", "recommend", "table"],
            language: "en", rng: &rng)
        XCTAssertEqual(decoys.count, 3)
        XCTAssertTrue(decoys.contains("negotiate"))
        XCTAssertFalse(decoys.contains("kitchen"))
        XCTAssertFalse(decoys.contains("table"))
    }

    /// A Korean predicate never sits among three nouns — its 다 would answer
    /// the item on its own.
    func testKoreanPredicateGetsPredicates() {
        let decoys = WeeklyTestEngine.meaningDecoys(
            for: "가다", own: ["학교", "가끔", "예쁘다"],
            graded: ["먹다", "책", "보다", "친구"],
            language: "ko", rng: &rng)
        XCTAssertEqual(Set(decoys), ["예쁘다", "먹다", "보다"])
    }

    /// A Japanese い-adjective gets い-adjectives, not the deverbal nouns
    /// that end the same way.
    func testJapaneseAdjectiveSkipsDeverbalNouns() {
        let decoys = WeeklyTestEngine.meaningDecoys(
            for: "高い", own: ["違い", "願い"],
            graded: ["安い", "面白い", "犬", "新しい"],
            language: "ja", rng: &rng)
        XCTAssertEqual(Set(decoys), ["安い", "面白い", "新しい"])
    }

    /// German: an adjective item never draws infinitives.
    func testGermanAdjectiveGetsAdjectives() {
        let decoys = WeeklyTestEngine.meaningDecoys(
            for: "schnell", own: ["laufen", "Haus"],
            graded: ["alt", "offen", "verstehen", "langsam"],
            language: "de", rng: &rng)
        XCTAssertEqual(Set(decoys), ["alt", "offen", "langsam"])
    }

    /// When the class runs dry the row still fills, own words first.
    func testFallsBackToOtherClassesRatherThanShort() {
        let decoys = WeeklyTestEngine.meaningDecoys(
            for: "가다", own: ["학교"], graded: ["책", "친구"],
            language: "ko", rng: &rng)
        XCTAssertEqual(Set(decoys), ["학교", "책", "친구"])
    }

    /// A word of unknown class takes the row as before: own first.
    func testUnknownClassKeepsTheOldOrder() {
        let decoys = WeeklyTestEngine.meaningDecoys(
            for: "zzqx", own: ["house", "car", "tree"],
            graded: ["recommend", "table"], language: "xx", rng: &rng)
        XCTAssertEqual(Set(decoys), ["house", "car", "tree"])
    }

    func testBandsAreLevelThenNeighbours() {
        XCTAssertEqual(WeeklyTestEngine.decoyBands(around: .b1), [.b1, .a2, .b2])
        XCTAssertEqual(WeeklyTestEngine.decoyBands(around: .a1), [.a1, .a2])
        XCTAssertEqual(WeeklyTestEngine.decoyBands(around: .c2), [.c2, .c1])
    }
}
