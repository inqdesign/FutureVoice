import Foundation

// MARK: - Reading the take

/// The words of a speech take, from the audio. Same rule as
/// `ShadowTranscriber`: the reader is never shown the script — it could only
/// copy it, and a word it supplies is a mark the speaker did not earn. Unlike
/// the shadow reader it WRITES fillers down, because counting them is part of
/// the grade. Sent as AAC: a three-minute take is ~6 MB of WAV and ~0.7 MB of
/// 32 kbps AAC, which is the talk path's own trade.
enum SpeechReader {
    struct Reading {
        let text: String
        /// True when the audio was read; false = the live recognizer's text.
        let audioGrounded: Bool
    }

    static func read(audioURL: URL, liveText: String, language: String) async -> Reading {
        let aac = await Task.detached { AudioLoudness.aacADTS16kMono(fromFileAt: audioURL) }.value
        guard let aac, !aac.isEmpty, aac.count <= 1_800_000 else {
            return Reading(text: liveText, audioGrounded: false)
        }
        struct Payload: Decodable { let transcript: String? }
        do {
            let payload: Payload = try await GeminiClient.shared.sendJSON(
                system: prompt(language: language),
                messages: [.init(role: .user, content: "Transcribe the attached audio.",
                                 inlineAudio: .init(mimeType: "audio/aac",
                                                    base64Data: aac.base64EncodedString()))],
                model: .flash36,
                maxTokens: 4096,
                purpose: "transcribe",
                requestTimeout: 60,
                fastThinking: true
            )
            let text = payload.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? Reading(text: liveText, audioGrounded: false)
                                : Reading(text: text, audioGrounded: true)
        } catch {
            return Reading(text: liveText, audioGrounded: false)
        }
    }

    /// One piece of a take, read while the rest is still being spoken.
    /// "" when the piece held no speech; nil when the read FAILED — the
    /// caller then reads the whole take instead.
    static func readPiece(audioURL: URL, language: String) async -> String? {
        let aac = await Task.detached { AudioLoudness.aacADTS16kMono(fromFileAt: audioURL) }.value
        guard let aac, !aac.isEmpty, aac.count <= 600_000 else { return nil }
        struct Payload: Decodable { let transcript: String? }
        do {
            let payload: Payload = try await GeminiClient.shared.sendJSON(
                system: prompt(language: language),
                messages: [.init(role: .user, content: "Transcribe the attached audio.",
                                 inlineAudio: .init(mimeType: "audio/aac",
                                                    base64Data: aac.base64EncodedString()))],
                model: .flash36,
                maxTokens: 1024,
                purpose: "transcribe",
                requestTimeout: 25,
                fastThinking: true
            )
            return payload.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return nil
        }
    }

    private static func prompt(language: String) -> String {
        let target = LanguageCatalog.englishName(language)
        let fillers = SpeechLibrary.fillers(language).joined(separator: ", ")
        return """
        You transcribe ONE recorded speech practice — or one consecutive piece
        of it — a language learner reading a prepared text aloud in \(target).
        A piece may begin or end mid-sentence; write exactly what it holds. Output STRICT JSON only — no prose,
        no code fences: { "transcript": "..." }

        The AUDIO is the only source. You are not told what text they were
        reading and must not reconstruct one — write the words in the audio.

        - VERBATIM, in \(target), in the order spoken. Every word you hear.
        - Write hesitation sounds as they occur, spelled one of: \(fillers).
          They are counted, so never drop them and never invent them.
        - A repeated word or a restarted phrase is written as many times as it
          was said.
        - If a word came out as a different word, write what was produced.
          Never fix grammar, never complete a sentence.
        - Silent or unintelligible audio: "transcript": "".
        """
    }
}

// MARK: - Notes on a take

/// Two or three lines of coaching in the NATIVE language, anchored to the
/// numbers `SpeechAnalyzer` computed. The model never writes a number of its
/// own.
enum SpeechCoach {
    static func review(script: SpeechScript, transcript: String, metrics: SpeechMetrics,
                       native: String, level: CEFRLevel) async -> SpeechCoaching? {
        struct Payload: Decodable { let headline: String?; let tips: [String]? }
        let target = LanguageCatalog.englishName(script.language)
        let nativeName = LanguageCatalog.englishName(native)
        let unit: String = {
            switch SpeechLibrary.rateUnit(script.language) {
            case .words: return "words"
            case .syllables: return "syllables"
            case .characters: return "characters"
            }
        }()
        let system = """
        You are a speech coach — think a broadcast voice trainer — reviewing ONE
        take of a learner (\(level.rawValue.uppercased())) reading a prepared
        \(target) script aloud like a presenter. Output STRICT JSON only:
        { "headline": "...", "tips": ["...", "..."] }

        \(CoachingLanguage.contract(target: script.language, native: native))

        OUTPUT LANGUAGE, FIELD BY FIELD
        - "headline": \(nativeName). ONE sentence: the single most useful thing
          about this take. Start with what went well if anything did.
        - "tips": \(nativeName), 2 or 3 items, each ONE concrete instruction
          for the next take (where, what to do). When a tip names words from
          the script, quote them in \(target) exactly as in the script.

        RULES
        - The numbers below were MEASURED. Use them; never state a number that
          is not given, never re-score.
        - Pace band: \(metrics.rateLow)–\(metrics.rateHigh) \(unit)/min. Inside
          is right; don't push a learner to go faster inside the band.
        - Prioritise in this order: skipped/changed words, stalls, pace, fading
          at sentence ends, fillers. Skip anything that is already fine.
        - Warm, direct, no filler praise, no scolding.
        """
        let user = """
        SCRIPT:
        \(script.body)

        WHAT THE MIC HEARD:
        \(transcript)

        MEASURED:
        - accuracy \(metrics.accuracy)/100; skipped or changed: \(metrics.missed.isEmpty ? "none" : metrics.missed.joined(separator: " | "))
        - pace \(metrics.rate) \(unit)/min (score \(metrics.paceScore))
        - pauses: \(metrics.pausesAtBreaks) breaths for \(metrics.breaks) sentence breaks; \(metrics.hesitations) stalls over \(String(format: "%.1f", SpeechAnalyzer.hesitationSeconds))s (score \(metrics.pauseScore))
        - fillers: \(metrics.fillers) (score \(metrics.fillerScore))
        - voice steadiness / fading at sentence ends: \(metrics.steadiness)/100
        - overall \(metrics.overall)/100
        """
        do {
            let p: Payload = try await GeminiClient.shared.sendJSON(
                system: system, messages: [.init(role: .user, content: user)],
                model: .flash36, maxTokens: 900, purpose: "speech-review")
            let headline = p.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tips = (p.tips ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !headline.isEmpty else { return nil }
            return SpeechCoaching(headline: headline, tips: Array(tips.prefix(3)))
        } catch {
            return nil
        }
    }
}

// MARK: - Writing a script

/// Writes a script to be READ ALOUD like a presenter, that teaches its reader
/// something true. Search-grounded: a script is something the learner will
/// say out loud as fact, so a made-up figure is worse here than anywhere.
enum SpeechScriptEngine {
    enum WriteError: LocalizedError {
        case empty
        var errorDescription: String? { explain("The script couldn't be written. Try again.") }
    }

    static func write(genre: SpeechGenre, topic: String, seconds: Int,
                      language: String, native: String, level: CEFRLevel,
                      avoidTitles: [String]) async throws -> SpeechScript {
        struct Term: Decodable { let term: String?; let meaning: String? }
        struct Payload: Decodable {
            let title: String?
            let body: String?
            let summary: String?
            let key_terms: [Term]?
            let sources: [String]?
        }
        let target = LanguageCatalog.englishName(language)
        let nativeName = LanguageCatalog.englishName(native)
        let units = SpeechLibrary.plannedUnits(seconds: seconds, language: language)
        let unitName: String = {
            switch SpeechLibrary.rateUnit(language) {
            case .words: return "words"
            case .syllables: return "Hangul syllables"
            case .characters: return "characters (kana + kanji, punctuation not counted)"
            }
        }()
        let scale = ConversationEngine.speechScale(for: level)
        let topicLine = topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "The writer chooses the subject: something specific, surprising and genuinely useful to know — not a generic overview."
            : "Subject, as the learner asked for it (context only — its language never changes yours): \(topic)"
        let avoid = avoidTitles.isEmpty ? "" : "\nDo not repeat these existing scripts: \(avoidTitles.prefix(20).joined(separator: " · "))"

        let system = """
        You write SCRIPTS for presentation practice. A language learner reads
        your script aloud from a teleprompter, like a news anchor or a
        presenter, to practise speaking — and should come away KNOWING
        something worth knowing. Output STRICT JSON only, keys in this order:
        { "title": "...", "body": "...", "summary": "...",
          "key_terms": [{ "term": "...", "meaning": "..." }], "sources": ["..."] }

        \(CoachingLanguage.contract(target: language, native: native))

        OUTPUT LANGUAGE, FIELD BY FIELD
        - "title": \(target), ≤ 8 words. MATERIAL.
        - "body": \(target). MATERIAL — the words they will say.
        - "summary": \(nativeName), ONE sentence: what the listener learns.
        - "key_terms": 3–6 words or phrases FROM the body ("term", \(target),
          exactly as in the body) with "meaning" in \(nativeName), ≤ 10 words.
        - "sources": the sources you relied on, by name (publication or
          organisation, e.g. "NASA", "BBC News"), 1–4 items. No URLs.

        THE GENRE: \(genreBrief(genre))

        THE BODY
        - LENGTH: about \(units) \(unitName) (± 10%) — \(seconds) seconds at a
          clear presenter's pace. Count.
        - Written to be SPOKEN to an audience: open with a hook that makes the
          listener want the rest, then 2–4 points in a clear order, then a
          closing line that lands. Short paragraphs separated by a blank line.
        - FACTS: use search. Every figure, date and claim must be true and
          current; when unsure, leave the detail out rather than guess. No
          invented quotes.
        - Address the audience the way a presenter in \(target) would (a
          neutral, polite broadcast register).
        - Vocabulary for this reader (\(level.rawValue.uppercased())):
          \(scale.vocabulary)
        - Sentence shapes: \(scale.structure)
        - PUNCTUATE FOR BREATH: the reader pauses where you put punctuation.
          A period where the voice falls and finishes, a comma only where a
          presenter would breathe inside a sentence. Prefer sentences a reader
          can say in one breath.
        - Plain text only: no headings, bullets, markdown, emoji or stage
          directions.
        """
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [.init(role: .user, content: topicLine + avoid)],
            model: .flash36,
            maxTokens: 4096,
            searchGrounding: true,
            purpose: "speech-script",
            requestTimeout: 90
        )
        let body = (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !title.isEmpty else { throw WriteError.empty }
        let terms = (payload.key_terms ?? []).compactMap { t -> SpeechKeyTerm? in
            guard let term = t.term?.trimmingCharacters(in: .whitespaces), !term.isEmpty,
                  body.localizedCaseInsensitiveContains(term) else { return nil }
            return SpeechKeyTerm(term: term, meaning: t.meaning?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        return SpeechScript(
            id: UUID(), title: title, genre: genre, topic: topic, body: body,
            summary: payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            keyTerms: terms,
            sources: (payload.sources ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            language: LanguageCatalog.base(language), targetSeconds: seconds,
            createdAt: Date(), isBuiltIn: false
        )
    }

    private static func genreBrief(_ genre: SpeechGenre) -> String {
        switch genre {
        case .explainer:
            return "EXPLAINER — how or why something works (science, technology, the body, money, history). Build from what the listener already knows to the one idea that makes it click."
        case .product:
            return "PRODUCT INTRODUCTION — present a real product, invention or service: the problem it solves, how it works, what makes it different, who it is for. Informative, not an advert: no hype words, include one honest limitation."
        case .person:
            return "PERSON INTRODUCTION — introduce a real person (living or historical): who they are, the one thing they are known for, a telling detail or turning point, and why they matter today."
        case .briefing:
            return "INFORMATION BRIEFING — a practical, useful briefing (a health finding, a travel rule, a how-to, a cultural custom) delivered like a presenter: what it is, what to know, what to do."
        case .own:
            return "A SCRIPT ON THE SUBJECT GIVEN — the shape that fits it best."
        case .news:
            return "NEWS ANCHOR READ — a neutral news-style report on a recent, real development: lead with the headline fact, then context, then what happens next. Neutral tone, no opinion."
        }
    }
}
