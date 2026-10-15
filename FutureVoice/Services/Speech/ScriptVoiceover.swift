import AVFoundation
import CryptoKit
import Foundation
import Supabase

/// "Hear it in my voice" (2026-10-14, founder decision): a Speech script read
/// whole in the learner's own cloned voice, which they can then shadow from.
/// There is deliberately NO native or preset voice option.
///
/// PRICE — talk minutes, 3x the audio length, rounded UP to whole minutes:
///     minutes = ceil(audioSeconds × 3 / 60)
/// (60 s → 3 min, 40 s → 2 min, 80 s → 4 min, 41 s → 3 min). The button shows
/// it BEFORE the tap, from the script's estimated length, and the learner is
/// never charged more than that number: the final charge is
///     min(minutes(actual audio), minutes shown)
/// — the server enforces the same cap (`charge_script_voiceover`). Charged
/// once per (account, script text, voice); every replay after is free, and
/// a failed synthesis is never charged.
///
/// Every place a price appears (the Script sheet's button, the composer's
/// "also make it in my voice", the own-script editor's estimate) reads it
/// from HERE, so two screens can never quote two numbers.
enum ScriptVoiceover {
    static let multiplier = 3
    /// The longest voiceover sold: the server meters at most an hour of talk
    /// time per charge.
    static let maxMinutes = 60

    // MARK: - Price

    /// Talk minutes for `audioSeconds` of voiceover.
    static func chargeMinutes(audioSeconds: Double) -> Int {
        guard audioSeconds > 0 else { return 0 }
        return Int((audioSeconds * Double(multiplier) / 60).rounded(.up))
    }

    /// What is actually charged once the voiceover exists: the real price,
    /// never more than what was shown, never less than a minute.
    static func cappedChargeMinutes(actualAudioSeconds: Double, quotedMinutes: Int) -> Int {
        max(1, min(chargeMinutes(audioSeconds: actualAudioSeconds), quotedMinutes))
    }

    /// The audio a text is expected to come out as — the Speech tab's own
    /// reading-length basis (`SpeechLibrary.estimatedSeconds`).
    static func estimatedAudioSeconds(text: String, language: String) -> Int {
        SpeechLibrary.estimatedSeconds(text, language: language)
    }

    /// The price shown for a text.
    static func quoteMinutes(text: String, language: String) -> Int {
        max(1, chargeMinutes(audioSeconds: Double(estimatedAudioSeconds(text: text, language: language))))
    }

    /// The price shown for a length not yet written (the composer).
    static func quoteMinutes(targetSeconds: Int) -> Int {
        max(1, chargeMinutes(audioSeconds: Double(targetSeconds)))
    }

    /// "Hear it in my voice · 3 min"
    static func buttonLabel(minutes: Int) -> String {
        explain("Hear it in my voice · \(minutes) min")
    }

    /// "Uses 3 min of talk time"
    static func costLabel(minutes: Int) -> String {
        explain("Uses \(minutes) min of talk time")
    }

    /// "42 min of talk time left" — nil where nothing is counted (an
    /// uncapped plan) or the account isn't known yet.
    static func remainingLabel(_ account: AccountStatus?) -> String? {
        guard let minutes = remainingMinutes(account) else { return nil }
        return explain("\(minutes) min of talk time left")
    }

    /// Talk minutes this account could put toward a voiceover now: the
    /// plan's pool plus invite minutes, or the balance with no plan.
    static func remainingMinutes(_ account: AccountStatus?) -> Int? {
        guard let account else { return nil }
        if account.unlimited || account.isUncappedTalk { return nil }
        let seconds = account.isEntitled ? account.secondsRemaining + account.bonusSeconds
                                         : max(0, account.secondsBalance)
        return seconds / 60
    }

    // MARK: - Keys

    /// The script's text, hashed — the voiceover follows the words, so an
    /// edited script is a new voiceover and the old file stays where it is.
    static func scriptHash(_ body: String) -> String {
        sha(body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The key the server charges once per account: "sv1:" + 32 hex of
    /// (script hash, voice). Speed is deliberately NOT in it — a learner who
    /// changes the voice speed keeps the voiceover they paid for.
    static func chargeKey(scriptHash: String, voiceId: String) -> String {
        "sv1:" + String(sha("\(scriptHash)|\(voiceId)").prefix(32))
    }

    /// The file on disk: one per (script, voice, speed).
    static func fileKey(scriptHash: String, voiceId: String, speedTag: String) -> String {
        sha("voiceover|\(scriptHash)|\(voiceId)|\(speedTag)")
    }

    static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Lines

    /// What is synthesized, one request each, in order: every sentence of
    /// every paragraph (`PacedSpeech` — a whole paragraph comes back with
    /// almost no breath between sentences), or every paragraph whole for a
    /// Cartesia voice, which already breathes.
    struct Line: Equatable {
        var text: String
        /// Ends a paragraph — a longer pause follows.
        var endsParagraph: Bool
    }

    static func lines(_ body: String, wholeParagraphs: Bool) -> [Line] {
        var out: [Line] = []
        for para in ScriptStudy.paragraphs(body) {
            let parts = wholeParagraphs ? [para] : PacedSpeech.sentences(in: para)
            for (i, p) in parts.enumerated() {
                out.append(Line(text: p, endsParagraph: i == parts.count - 1))
            }
        }
        return out
    }

    static let paragraphGapSeconds = 0.8
}

// MARK: - Store

/// `Documents/ScriptVoiceover/<fileKey>.m4a` + `<fileKey>.json`. Never
/// deleted (produced audio is the learner's): an edited script or a new
/// voice is a new file beside the old one.
enum ScriptVoiceoverStore {
    struct Meta: Codable, Equatable {
        var scriptHash: String
        var voiceId: String
        var speedTag: String
        var seconds: Double
        var timings: [WordTiming]
        var chargeKey: String
        /// Charged and confirmed. False = made, the charge didn't go through
        /// yet; the next tap charges it without making it again.
        var paid: Bool
        var quotedMinutes: Int
        var createdAt: Date
    }

    struct Stored: Equatable {
        var url: URL
        var meta: Meta
    }

    static var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("ScriptVoiceover", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func audioURL(_ fileKey: String) -> URL { dir.appendingPathComponent("\(fileKey).m4a") }
    static func metaURL(_ fileKey: String) -> URL { dir.appendingPathComponent("\(fileKey).json") }

    static func allMetas() -> [(String, Meta)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
            let key = url.deletingPathExtension().lastPathComponent
            guard FileManager.default.fileExists(atPath: audioURL(key).path) else { return nil }
            return (key, meta)
        }
    }

    /// The voiceover to play for this script: the current voice at the
    /// current speed first, then any speed, then the learner's earlier
    /// clones (`PhraseAudioStore.ownVoiceLineage`) — cache first, always.
    static func find(scriptHash: String, voiceId: String, paid: Bool = true) -> Stored? {
        let metas = allMetas().filter { $0.1.scriptHash == scriptHash && $0.1.paid == paid }
        guard !metas.isEmpty else { return nil }
        let voices = [voiceId] + PhraseAudioStore.shared.ownVoiceLineage.filter { $0 != voiceId }
        let tag = SpeechSpeed.current.cacheTag
        for v in (paid ? voices : [voiceId]) {
            let mine = metas.filter { $0.1.voiceId == v }
            if let hit = mine.first(where: { $0.1.speedTag == tag }) ?? mine.max(by: { $0.1.createdAt < $1.1.createdAt }) {
                return Stored(url: audioURL(hit.0), meta: hit.1)
            }
        }
        return nil
    }

    static func save(audio: URL, meta: Meta) throws -> Stored {
        let key = ScriptVoiceover.fileKey(scriptHash: meta.scriptHash, voiceId: meta.voiceId, speedTag: meta.speedTag)
        let dest = audioURL(key)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.moveItem(at: audio, to: dest)
        try JSONEncoder().encode(meta).write(to: metaURL(key), options: [.atomic])
        return Stored(url: dest, meta: meta)
    }

    static func markPaid(_ stored: Stored) -> Stored {
        var meta = stored.meta
        meta.paid = true
        let key = ScriptVoiceover.fileKey(scriptHash: meta.scriptHash, voiceId: meta.voiceId, speedTag: meta.speedTag)
        try? JSONEncoder().encode(meta).write(to: metaURL(key), options: [.atomic])
        return Stored(url: stored.url, meta: meta)
    }
}

// MARK: - Making one

@MainActor
final class ScriptVoiceoverCenter: ObservableObject {
    static let shared = ScriptVoiceoverCenter()

    enum Job: Equatable {
        case making(done: Int, total: Int)
        case failed(String)
    }

    /// By charge key. A job outlives the sheet that started it — the
    /// composer starts one and closes.
    @Published private(set) var jobs: [String: Job] = [:]
    /// Bumped whenever a voiceover lands, so open sheets look again.
    @Published private(set) var revision = 0

    enum VoiceoverError: LocalizedError {
        case failed
        case tooLong
        var errorDescription: String? {
            switch self {
            case .failed: return explain("Couldn't make it in your voice. Nothing was charged.")
            case .tooLong: return explain("This script is too long to make in your voice.")
            }
        }
    }

    func job(for script: SpeechScript, voiceId: String) -> Job? {
        jobs[ScriptVoiceover.chargeKey(scriptHash: ScriptVoiceover.scriptHash(script.body), voiceId: voiceId)]
    }

    func existing(for script: SpeechScript, voiceId: String) -> ScriptVoiceoverStore.Stored? {
        ScriptVoiceoverStore.find(scriptHash: ScriptVoiceover.scriptHash(script.body), voiceId: voiceId)
    }

    /// Could this account pay `minutes` right now? Nil = yes, else the wall
    /// (`ElevenLabsError.wall`). A failure to ask is a yes — the reservation
    /// asks again before anything is made.
    func wall(forMinutes minutes: Int) async -> ElevenLabsError? {
        struct Params: Encodable { let p_quoted_seconds: Int }
        guard let result: RPCResult = try? await SupabaseProvider.shared
            .rpc("script_voiceover_can_pay", params: Params(p_quoted_seconds: minutes * 60))
            .execute().value else { return nil }
        return result.error.map { ElevenLabsError.wall(body: $0) }
    }

    /// Make (or finish paying for) the voiceover. Throws an `ElevenLabsError`
    /// wall when the account can't pay — before anything is synthesized.
    @discardableResult
    func make(script: SpeechScript, voiceId: String, quotedMinutes: Int) async throws -> ScriptVoiceoverStore.Stored {
        let hash = ScriptVoiceover.scriptHash(script.body)
        if let done = ScriptVoiceoverStore.find(scriptHash: hash, voiceId: voiceId) { return done }
        guard quotedMinutes <= ScriptVoiceover.maxMinutes else { throw VoiceoverError.tooLong }
        let key = ScriptVoiceover.chargeKey(scriptHash: hash, voiceId: voiceId)
        if case .making = jobs[key] { throw CancellationError() }

        // Made before, not paid for yet: charge only.
        if let pending = ScriptVoiceoverStore.find(scriptHash: hash, voiceId: voiceId, paid: false) {
            try await charge(key: key, seconds: pending.meta.seconds)
            let paid = ScriptVoiceoverStore.markPaid(pending)
            revision += 1
            return paid
        }

        let lines = ScriptVoiceover.lines(script.body, wholeParagraphs: VoiceMove.isCartesia(voiceId))
        guard !lines.isEmpty else { throw VoiceoverError.failed }
        jobs[key] = .making(done: 0, total: lines.count)
        do {
            try await reserve(key: key, minutes: quotedMinutes, chars: script.body.count)
            let assembled = try await synthesize(lines: lines, voiceId: voiceId, key: key)
            let meta = ScriptVoiceoverStore.Meta(
                scriptHash: hash, voiceId: voiceId, speedTag: SpeechSpeed.current.cacheTag,
                seconds: assembled.seconds, timings: assembled.timings, chargeKey: key,
                paid: false, quotedMinutes: quotedMinutes, createdAt: Date())
            let stored = try ScriptVoiceoverStore.save(audio: assembled.url, meta: meta)
            try await charge(key: key, seconds: assembled.seconds)
            let paid = ScriptVoiceoverStore.markPaid(stored)
            jobs[key] = nil
            revision += 1
            BillingGate.shared.invalidate()
            Analytics.capture("speech_voiceover_made", [
                "seconds": Int(assembled.seconds), "quoted_min": quotedMinutes,
                "charged_min": ScriptVoiceover.cappedChargeMinutes(actualAudioSeconds: assembled.seconds,
                                                                   quotedMinutes: quotedMinutes),
            ])
            return paid
        } catch {
            if let wall = error as? ElevenLabsError {
                jobs[key] = nil
                throw wall
            }
            jobs[key] = .failed((error as? VoiceoverError ?? .failed).localizedDescription)
            Telemetry.log("speech_voiceover_failed", ["error": String(describing: error).prefix(160).description])
            throw error
        }
    }

    func clearFailure(for script: SpeechScript, voiceId: String) {
        let key = ScriptVoiceover.chargeKey(scriptHash: ScriptVoiceover.scriptHash(script.body), voiceId: voiceId)
        if case .failed = jobs[key] { jobs[key] = nil }
    }

    // MARK: Server

    private struct RPCResult: Decodable {
        let status: String?
        let error: String?
        let charged_seconds: Int?
    }

    private func reserve(key: String, minutes: Int, chars: Int) async throws {
        struct Params: Encodable { let p_key: String; let p_quoted_seconds: Int; let p_chars: Int }
        let result: RPCResult = try await SupabaseProvider.shared
            .rpc("reserve_script_voiceover",
                 params: Params(p_key: key, p_quoted_seconds: minutes * 60, p_chars: min(chars, 20000)))
            .execute().value
        try Self.check(result)
    }

    private func charge(key: String, seconds: Double) async throws {
        struct Params: Encodable { let p_key: String; let p_audio_seconds: Int }
        let result: RPCResult = try await SupabaseProvider.shared
            .rpc("charge_script_voiceover",
                 params: Params(p_key: key, p_audio_seconds: min(3600, Int(seconds.rounded(.up)))))
            .execute().value
        try Self.check(result)
    }

    private static func check(_ result: RPCResult) throws {
        guard let error = result.error else { return }
        switch error {
        case "insufficient_credits", "daily_cap_reached", "fair_use_limit":
            throw ElevenLabsError.wall(body: error)
        default:
            throw VoiceoverError.failed
        }
    }

    // MARK: Synthesis

    private struct Take {
        var samples: [Float]
        var rate: Double
        var timings: [WordTiming]
    }

    private func synthesize(lines: [ScriptVoiceover.Line], voiceId: String,
                            key: String) async throws -> (url: URL, seconds: Double, timings: [WordTiming]) {
        var takes = [Take?](repeating: nil, count: lines.count)
        var done = 0
        try await withThrowingTaskGroup(of: (Int, Take).self) { group in
            var next = 0
            func add() {
                guard next < lines.count else { return }
                let i = next
                next += 1
                let text = lines[i].text
                group.addTask {
                    let (data, timings) = try await ElevenLabsClient.shared.synthesizeVoiceoverLine(
                        voiceId: voiceId, text: text, voiceoverKey: key, index: i)
                    guard let (samples, rate) = ScriptVoiceoverAudio.decode(data) else {
                        throw VoiceoverError.failed
                    }
                    return (i, Take(samples: samples, rate: rate, timings: timings))
                }
            }
            for _ in 0 ..< 3 { add() }
            while let (i, take) = try await group.next() {
                takes[i] = take
                done += 1
                jobs[key] = .making(done: done, total: lines.count)
                add()
            }
        }
        let ready = takes.compactMap { $0 }
        guard ready.count == lines.count,
              Set(ready.map(\.rate)).count == 1 else { throw VoiceoverError.failed }
        let joined = ScriptVoiceoverAudio.join(ready.map { ($0.samples, $0.timings) },
                                               rate: ready[0].rate,
                                               endsParagraph: lines.map(\.endsParagraph))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try ScriptVoiceoverAudio.writeM4A(joined.samples, rate: ready[0].rate, to: tmp)
        return (tmp, Double(joined.samples.count) / ready[0].rate, joined.timings)
    }
}

// MARK: - Audio

/// Decoding the takes, trimming their inner edges to the voice, laying them
/// end to end with a fixed breath between (`PacedSpeech`'s rule, a longer one
/// between paragraphs), and writing one AAC file.
enum ScriptVoiceoverAudio {
    /// Mono float samples + sample rate. MP3 from ElevenLabs, WAV from a
    /// Cartesia voice — the file extension is a hint `AVAudioFile` honours, so
    /// it is chosen from the bytes.
    static func decode(_ data: Data) -> ([Float], Double)? {
        let isWAV = data.prefix(4) == Data("RIFF".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(isWAV ? "wav" : "mp3")")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil,
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return (samples, file.processingFormat.sampleRate)
    }

    /// First and last sample of voice on a 10 ms RMS envelope, gated at 3% of
    /// the loudest block — `PacedSpeech.voicedSpan`, on floats.
    static func voicedSpan(_ s: [Float], rate: Double) -> (Int, Int)? {
        let block = max(1, Int(rate / 100))
        guard s.count >= block else { return nil }
        var rms: [Float] = []
        var i = 0
        while i + block <= s.count {
            var sum: Float = 0
            for j in i ..< i + block { sum += s[j] * s[j] }
            rms.append((sum / Float(block)).squareRoot())
            i += block
        }
        guard let loudest = rms.max(), loudest > 0 else { return nil }
        let gate = loudest * 0.03
        guard let first = rms.firstIndex(where: { $0 > gate }),
              let last = rms.lastIndex(where: { $0 > gate }) else { return nil }
        return (first * block, min(s.count, (last + 1) * block))
    }

    /// Joins takes, each take's timings moved to where its audio now sits.
    static func join(_ takes: [([Float], [WordTiming])], rate: Double,
                     endsParagraph: [Bool]) -> (samples: [Float], timings: [WordTiming]) {
        let margin = Int(PacedSpeech.edgeMarginSeconds * rate)
        var out: [Float] = []
        var timings: [WordTiming] = []
        for (i, (s, t)) in takes.enumerated() {
            guard !s.isEmpty else { continue }
            let (on, off) = voicedSpan(s, rate: rate) ?? (0, s.count)
            let from = i == 0 ? 0 : max(0, on - margin)
            let to = i == takes.count - 1 ? s.count : min(s.count, off + margin)
            guard to > from else { continue }
            if !out.isEmpty {
                let gap = (i > 0 && endsParagraph[i - 1]) ? ScriptVoiceover.paragraphGapSeconds
                                                          : PacedSpeech.sentenceGapSeconds
                out.append(contentsOf: [Float](repeating: 0, count: max(0, Int(gap * rate) - 2 * margin)))
            }
            let shiftMs = Int((Double(out.count - from) / rate * 1000).rounded())
            timings.append(contentsOf: t.map {
                WordTiming(word: $0.word, startMs: max(0, $0.startMs + shiftMs),
                           endMs: max(0, $0.endMs + shiftMs), isMeasured: $0.isMeasured)
            })
            out.append(contentsOf: s[from ..< to])
        }
        return (out, timings)
    }

    static func writeM4A(_ samples: [Float], rate: Double, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                         channels: 1, interleaved: false) else { throw ScriptVoiceoverCenter.VoiceoverError.failed }
        let chunk = 1 << 16
        var i = 0
        while i < samples.count {
            let n = min(chunk, samples.count - i)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { break }
            buffer.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress! + i, count: n)
            }
            try file.write(from: buffer)
            i += n
        }
    }
}
