// Per speaker of the NICT JLE corpus (SST interviews: 1,277 Japanese learners
// of English at nine levels + 20 natives doing the same task), every word as
// `lemma|LexicalClass` — the tagger and the tokens `VocabSophistication`
// reads on device. summarize.py turns it into the calibration.
//
// Corpus (free for research, not redistributed here):
//   curl -o jle.zip https://alaginrc.nict.go.jp/nict_jle/src/NICT_JLE_4.1.zip && unzip jle.zip
// usage: swift calibrate.swift NICT_JLE_4.1/Native NICT_JLE_4.1/LearnerOriginal > speakers.tsv
import NaturalLanguage
func strip(_ s: String) -> String {
    var t = s
    for tag in ["F", "R", "SC", "SC\\?", "nvs", "JP", "H", "\\?\\?", "ctxt"] {
        t = t.replacingOccurrences(of: "<\(tag)[^>]*>.*?</\(tag)>", with: " ", options: .regularExpression)
    }
    return t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
}
let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
for dir in CommandLine.arguments.dropFirst() {
    for f in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() where f.hasSuffix(".txt") {
        guard let raw = try? String(contentsOfFile: dir + "/" + f, encoding: .utf8) else { continue }
        let sst = raw.range(of: "<SST_level>(\\d+)", options: .regularExpression).map { String(raw[$0]).replacingOccurrences(of: "<SST_level>", with: "") } ?? "N"
        let re = try! NSRegularExpression(pattern: "<B>(.*?)</B>", options: [.dotMatchesLineSeparators])
        let ns = raw as NSString
        let text = re.matches(in: raw, range: NSRange(location: 0, length: ns.length)).map { strip(ns.substring(with: $0.range(at: 1))) }.joined(separator: " . ")
        var out: [String] = []
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        let opts: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .omitOther]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: opts) { cls, r in
            let lemma = tagger.tag(at: r.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? String(text[r])
            out.append(lemma.lowercased() + "|" + (cls?.rawValue ?? "?"))
            return true
        }
        print("\(f)\t\(sst)\t\(out.joined(separator: " "))")
    }
}
