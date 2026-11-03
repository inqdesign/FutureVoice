import Foundation

/// How the learner PRONOUNCED a take — per phoneme, against a native model —
/// from the `pronunciation` edge function (Azure Speech, scripted assessment).
///
/// Until 2026-11-03 every speaking score in the app was a transcript compared
/// with the target. A transcriber writes the word the learner was reaching for
/// whenever it can tell what that was, so an accent that stays intelligible
/// scored 100: the number measured whether a machine could understand them,
/// not how they said it. This is the one reader that hears the SOUNDS, and it
/// is an UPGRADE on every surface that uses it, never a requirement — a nil
/// here leaves the take scored exactly as before.
///
/// What it is NOT: part of `ShadowAttempt.overallScore` or
/// `SpeechMetrics.overall` (yet). Those numbers decide mastery and a public
/// board, so folding a new reader into them is a decision taken after the
/// probe (`scripts/pronunciation-probe.sh`), not before.
struct PronunciationResult: Codable, Hashable {
    /// Azure's `PronScore`, 0–100: accuracy, fluency, completeness (and
    /// prosody where assessed) weighted together.
    var score: Int
    /// How closely the phonemes matched a native speaker's, 0–100.
    var accuracy: Int
    /// Silent breaks between words, as a native would place them, 0–100.
    var fluency: Int
    /// Share of the reference text that was said, 0–100.
    var completeness: Int?
    /// Stress, intonation, speaking speed and rhythm — Azure assesses it for
    /// en-US only; nil everywhere else.
    var prosody: Int?
    /// The locale the take was judged against ("en-GB").
    var locale: String
    /// Azure's own read of the audio, for the record.
    var recognized: String
    var words: [Word]

    struct Word: Codable, Hashable {
        var word: String
        /// nil for a word Azure never heard (an Omission).
        var accuracy: Int?
        /// "None" · "Mispronunciation" · "Omission" · "Insertion" ·
        /// "UnexpectedBreak" · "MissingBreak" · "Monotone".
        var error: String
        var offsetMs: Int
        var durationMs: Int
        var phonemes: [Phoneme]

        var isInsertion: Bool { error == "Insertion" }
        var isOmission: Bool { error == "Omission" }
        /// The weakest SOUND in the word. Measured 2026-11-03: Azure's word
        /// score is lenient and the accent lives in the phonemes — a
        /// Korean-accented "think" scored 94 as a word with θ at 32 — so a
        /// mark built on word scores alone underlined almost nothing.
        var worstPhoneme: Int? { phonemes.compactMap(\.accuracy).min() }
        /// Red: Azure's own Mispronunciation, a word under 50, or a sound
        /// under 35. Orange: a word under 70 or a sound under 45. Set from
        /// the probe (scripts/pronunciation-probe.sh): native voices scored
        /// every word 100 in English, but a native German and Korean take
        /// each had one word at 45–55, so the bars sit below that and a
        /// native slip reads orange at worst, never red.
        /// (Azure's own `Mispronunciation` tag fires under 60, which caught a
        /// native Korean word at 55 — so it is not used as the red line.)
        var isMispronounced: Bool {
            (accuracy ?? 100) < 50 || (worstPhoneme ?? 100) < 35
        }
        var isShaky: Bool {
            !isMispronounced && !isOmission
                && ((accuracy ?? 100) < 70 || (worstPhoneme ?? 100) < 45)
        }
        /// The sounds that let the word down, worst first. Azure names
        /// phonemes in IPA for English only; other locales send the score
        /// with an empty name, which is kept out of anything shown.
        var weakPhonemes: [Phoneme] {
            phonemes.filter { !$0.phoneme.isEmpty && ($0.accuracy ?? 100) < 60 }
                .sorted { ($0.accuracy ?? 0) < ($1.accuracy ?? 0) }
        }
    }

    struct Phoneme: Codable, Hashable {
        var phoneme: String
        var accuracy: Int?
    }

    /// Reference words only (an Insertion is something the learner added and
    /// has no place on the target line), in reference order.
    var referenceWords: [Word] { words.filter { !$0.isInsertion } }

    /// The words worth telling the learner about, worst first.
    var weakWords: [Word] {
        referenceWords.filter { $0.isMispronounced || $0.isShaky }
            .sorted { ($0.accuracy ?? 0) < ($1.accuracy ?? 0) }
    }

    /// A word's mark as the beat's colour scale: 0 red · 1 orange · 2 fine.
    static func grade(_ word: Word) -> Int {
        word.isMispronounced ? 0 : (word.isShaky ? 1 : 2)
    }
}

enum PronunciationAssessor {

    /// The REST endpoint assesses up to ~30 s; a longer take is the caller's
    /// to cut (the speech take is read in ~12 s pieces already).
    static let maxSeconds: Double = 30
    /// 16 kHz mono PCM16 — 32,000 bytes a second, plus the header.
    static let maxWAVBytes = 44 + Int(maxSeconds) * 32_000

    enum Outcome: String {
        case scored        // a result
        case silent        // Azure heard no speech
        case unconfigured  // server has no key yet
        case capped        // daily cap
        case failed        // network / server error
        case skipped       // nothing to send (no file, too long, unsupported language)
    }

    /// Score `wav` (16 kHz mono PCM16, ≤ `maxSeconds`) against `reference`.
    /// nil on any failure — the caller's take is scored by words as before.
    static func assess(
        wav: Data,
        reference: String,
        language: String,
        surface: String,
        timeout: TimeInterval = 15
    ) async -> (result: PronunciationResult?, outcome: Outcome) {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty, wav.count > 1_000, wav.count <= maxWAVBytes,
              supports(language) else { return (nil, .skipped) }

        struct Request: Encodable {
            let audio_b64: String
            let language: String
            let reference: String
            let accent: String?
            let surface: String
        }
        struct Wire: Decodable {
            struct Word: Decodable {
                let word: String
                let accuracy: Int?
                let error: String?
                let offset_ms: Int?
                let duration_ms: Int?
                let phonemes: [Phoneme]?
            }
            struct Phoneme: Decodable { let phoneme: String; let accuracy: Int? }
            let locale: String?
            let score: Int?
            let accuracy: Int?
            let fluency: Int?
            let completeness: Int?
            let prosody: Int?
            let recognized: String?
            let words: [Word]?
        }

        let request = Request(
            audio_b64: wav.base64EncodedString(),
            language: LanguageCatalog.language(language)?.code ?? language,
            reference: reference,
            accent: UserDefaults.standard.string(forKey: VoiceAccentCatalog.storedAccentKey),
            surface: surface
        )
        guard let body = try? JSONEncoder().encode(request),
              let base = Secrets.string(for: .supabaseURL),
              let url = URL(string: base)?.appendingPathComponent("/functions/v1/pronunciation"),
              let headers = try? await SupabaseProvider.authorizedHeaders() else {
            return (nil, .failed)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        do {
            // Its own connection: the take's base64 must not sit in front of
            // the transcribe call it runs beside.
            let (data, response) = try await URLSession.edgeFunctionsBackground.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200: break
            case 204: return (nil, .silent)
            case 429: return (nil, .capped)
            case 503: return (nil, .unconfigured)
            default: return (nil, .failed)
            }
            let wire = try JSONDecoder().decode(Wire.self, from: data)
            guard let score = wire.score, let accuracy = wire.accuracy, let fluency = wire.fluency else {
                return (nil, .failed)
            }
            let result = PronunciationResult(
                score: score, accuracy: accuracy, fluency: fluency,
                completeness: wire.completeness, prosody: wire.prosody,
                locale: wire.locale ?? "",
                recognized: wire.recognized ?? "",
                words: (wire.words ?? []).map {
                    .init(word: $0.word, accuracy: $0.accuracy, error: $0.error ?? "None",
                          offsetMs: $0.offset_ms ?? 0, durationMs: $0.duration_ms ?? 0,
                          phonemes: ($0.phonemes ?? []).map { .init(phoneme: $0.phoneme, accuracy: $0.accuracy) })
                }
            )
            return (result, .scored)
        } catch {
            return (nil, .failed)
        }
    }

    /// Reads the file (any format AVAudioFile opens) and assesses it.
    static func assess(audioURL: URL, reference: String, language: String,
                       surface: String, timeout: TimeInterval = 15)
    async -> (result: PronunciationResult?, outcome: Outcome) {
        let wav = await Task.detached { AudioLoudness.wav16kMono(fromFileAt: audioURL) }.value
        guard let wav else { return (nil, .skipped) }
        return await assess(wav: wav, reference: reference, language: language,
                            surface: surface, timeout: timeout)
    }

    /// Every target language the app ships has a GA Azure locale.
    static func supports(_ language: String) -> Bool {
        let code = LanguageCatalog.language(language)?.code ?? language
        return ["en", "de", "ja", "ko", "es"].contains(code)
    }

    // MARK: - Placing the verdict on a target line

    /// The result's reference words mapped onto the target line's own word
    /// split (`WordSplitter.timingWords`): target index → the Azure word.
    /// Azure tokenizes the reference its own way (punctuation off, a hyphen
    /// sometimes a split), so the two lists are aligned by edit distance the
    /// way the rhythm card's timings are, and nothing is drawn when fewer
    /// than half the words anchor — a mark on the wrong word is worse than
    /// no mark. Unspaced languages (Japanese) are not mapped: Azure's words
    /// and the line's are cut in different places, and the score alone is
    /// shown.
    static func wordMarks(_ result: PronunciationResult, targetWords: [String])
    -> [Int: PronunciationResult.Word] {
        guard WordSplitter.spaced, !targetWords.isEmpty else { return [:] }
        let reference = result.referenceWords
        guard !reference.isEmpty else { return [:] }
        let pairing = LocalAlignment.align(
            expected: targetWords.map(LocalAlignment.normalized),
            heard: reference.map { LocalAlignment.normalized($0.word) }
        )
        let anchored = pairing.compactMap { $0 }.count
        guard Double(anchored) / Double(targetWords.count) >= 0.5 else { return [:] }
        var out: [Int: PronunciationResult.Word] = [:]
        for (i, j) in pairing.enumerated() {
            if let j, reference.indices.contains(j) { out[i] = reference[j] }
        }
        return out
    }
}

// MARK: - The learner's standing

/// The pronunciation axis as a READ over recent takes, for the scorecard: a
/// talk's transcript cannot judge sounds, so the row shows what the shadow,
/// say-it-again and weekly-test takes measured in the last month. Computed
/// where it is shown, never stored on a talk.
enum PronunciationRead {
    static let windowDays = 30
    /// Fewer takes than this and one bad morning IS the number.
    static let minTakes = 3

    static func recentAxis(now: Date = Date()) -> AxisScore? {
        let since = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let scores = ShadowAttemptStore.shared.load()
            .filter { $0.createdAt >= since }
            .compactMap { $0.assessment?.score }
        guard scores.count >= minTakes else { return nil }
        let mean = scores.reduce(0, +) / scores.count
        return AxisScore(score: mean,
                         note: explain("Measured per sound over \(scores.count) recent shadow takes."))
    }
}
