// Measures what `VocabSophistication` is calibrated on, per speaker of the
// NICT JLE corpus (SST interviews, 1,277 Japanese learners of English at nine
// levels + 20 native speakers doing the same task). Same tokenizer and word
// list as the app. Writes a per-speaker TSV on stdout and every speaker's
// lemma tokens on stderr (for summarize.py).
//
// Corpus (free for research, not redistributed here):
//   curl -o jle.zip https://alaginrc.nict.go.jp/nict_jle/src/NICT_JLE_4.1.zip && unzip jle.zip
// usage: swift calibrate.swift FutureVoice/Resources/cefr_words.tsv NICT_JLE_4.1/Native NICT_JLE_4.1/LearnerOriginal > speakers.tsv 2> lemmas.tsv
import Foundation
import NaturalLanguage

let args = CommandLine.arguments
let list = try! String(contentsOfFile: args[1], encoding: .utf8)
var level: [String: Int] = [:]   // 0=a1 … 5=c2
let order = ["a1", "a2", "b1", "b2", "c1", "c2"]
for line in list.split(whereSeparator: \.isNewline) {
    let p = line.split(separator: "\t")
    guard p.count >= 2, let i = order.firstIndex(of: p[1].lowercased()) else { continue }
    level[p[0].lowercased()] = i
}

func strip(_ s: String) -> String {
    var t = s
    for tag in ["F", "R", "SC", "SC\\?", "nvs", "JP", "H", "\\?\\?", "ctxt"] {
        t = t.replacingOccurrences(of: "<\(tag)[^>]*>.*?</\(tag)>", with: " ", options: .regularExpression)
    }
    t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    return t
}

func mtldPass(_ toks: [String]) -> Double {
    var factors = 0.0, types = Set<String>(), n = 0
    for w in toks {
        n += 1; types.insert(w)
        if Double(types.count) / Double(n) <= 0.72 { factors += 1; types = []; n = 0 }
    }
    if n > 0 {
        let ttr = Double(types.count) / Double(n)
        factors += (1 - ttr) / (1 - 0.72)
    }
    return factors > 0 ? Double(toks.count) / factors : Double(toks.count)
}
func mtld(_ toks: [String]) -> Double { (mtldPass(toks) + mtldPass(toks.reversed())) / 2 }

func appRule(_ lemmas: Set<String>) -> Int {
    var counts = [Int](repeating: 0, count: 6); var total = 0
    for l in lemmas { if let i = level[l] { counts[i] += 1; total += 1 } }
    guard total >= 15 else { return -1 }
    let th = [6, 6, 8, 10, 12, 15]
    var est = 0
    for i in 0..<6 where counts[i] >= th[i] { est = i }
    return est
}

let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
print("file\tgroup\tsst\twords\tgraded\tb2plus_tok\tc1plus_tok\tb2plus_type\tc1_types\tc2_types\tmtld\tapp")
for dir in args.dropFirst(2) {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.sorted() ?? []
    for f in files where f.hasSuffix(".txt") {
        guard let raw = try? String(contentsOfFile: dir + "/" + f, encoding: .utf8)
             else { continue }
        let sst = raw.range(of: "<SST_level>(\\d+)", options: .regularExpression)
            .map { String(raw[$0]).replacingOccurrences(of: "<SST_level>", with: "") } ?? "N"
        // Interviewee = <B> lines
        let re = try! NSRegularExpression(pattern: "<B>(.*?)</B>", options: [.dotMatchesLineSeparators])
        let ns = raw as NSString
        let text = re.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            .map { strip(ns.substring(with: $0.range(at: 1))) }.joined(separator: " ")
        var surf: [String] = [], lemmaToks: [String] = []
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, r in
            let w = String(text[r]).lowercased()
            guard w.rangeOfCharacter(from: .letters) != nil else { return true }
            surf.append(w)
            let l = (tag?.rawValue ?? w).lowercased()
            if l.count > 1 { lemmaToks.append(l) }
            return true
        }
        let graded = lemmaToks.compactMap { level[$0] }
        let g = Double(max(graded.count, 1))
        let types = Set(lemmaToks.filter { level[$0] != nil })
        let tl = types.map { level[$0]! }
        let row = [f, sst == "N" ? "native" : "learner", sst, "\(surf.count)", "\(graded.count)",
                   String(format: "%.4f", Double(graded.filter { $0 >= 3 }.count) / g),
                   String(format: "%.4f", Double(graded.filter { $0 >= 4 }.count) / g),
                   String(format: "%.4f", Double(tl.filter { $0 >= 3 }.count) / Double(max(tl.count, 1))),
                   "\(tl.filter { $0 == 4 }.count)", "\(tl.filter { $0 == 5 }.count)",
                   String(format: "%.1f", mtld(surf)), "\(appRule(Set(lemmaToks)))"]
        print(row.joined(separator: "\t"))
        FileHandle.standardError.write((f + "\t" + sst + "\t" + lemmaToks.joined(separator: " ") + "\n").data(using: .utf8)!)
    }
}
