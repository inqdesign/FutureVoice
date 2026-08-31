import Foundation

// Golden-vector generator — runs the REAL Swift implementations over fixed
// fixtures and dumps inputs + outputs as JSON. Re-run after changing any of
// the vector'd algorithms: scripts/android/gen-vectors.sh.

let iso = ISO8601DateFormatter()
func d(_ s: String) -> Date { iso.date(from: s)! }
func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
let NOW = d("2026-08-31T12:00:00Z")

func turn(_ n: Int, _ role: TurnRole, _ text: String, suggestion: TurnSuggestion? = nil,
          fluency: FluencyStats? = nil, durationMs: Int = 0, excluded: Bool = false) -> Turn {
    Turn(id: uuid(n), role: role, audioURL: nil, transcript: text, durationMs: durationMs,
         timestamp: NOW, suggestion: suggestion, fluency: fluency, excludedFromScoring: excluded)
}

var out: [String: Any] = [:]

// ── 1. normalization / fragments / meta-rule ─────────────────────────────
let fragCases: [[String: String]] = [
    ["source": "Well I think, you know, we went to the market early because my sister said the bread sells out, and then we had coffee at the small place near the station and talked about her new job for a long time which was nice", "target": "We went to the market early because the bread sells out"],
    ["source": "short one", "target": "anything"],
    ["source": String(repeating: "no separators here just words ", count: 8), "target": "totally unrelated phrase"],
]
out["relevant_fragment"] = fragCases.map { c in
    ["source": c["source"]!, "target": c["target"]!,
     "result": DrillStore.relevantFragment(of: c["source"]!, matching: c["target"]!)]
}
let coreCases: [[String: String]] = [
    ["target": "I went to the bank yesterday. Then I met my friend for lunch and we talked about the trip we are planning for the autumn holidays together. It was fun.", "source": "I go to bank yesterday"],
    ["target": "Did you finish the report? I stayed up late to get it done and sent it before the morning meeting started because the deadline was moved up.", "source": "you finish report?"],
    ["target": "One short sentence.", "source": "whatever"],
]
out["core_sentence"] = coreCases.map { c in
    ["target": c["target"]!, "source": c["source"]!,
     "result": DrillStore.coreSentence(of: c["target"]!, pairedWith: c["source"]!)]
}
let metaCases = [
    "using articles correctly", "I went to the bank yesterday", "subject-verb agreement",
    "Remember to use the past tense", "It depends on the weather", "using 'a', 'the', 'in', 'on'",
    "Try to use more vocabulary", "I'd rather stay in tonight", "", "  ",
]
out["is_drillable"] = metaCases.map { ["phrase": $0, "result": DrillStore.isDrillable($0)] }
out["carryover_normalized"] = [
    ["text": "I'm in a GOOD mood — today!", "result": CarryoverDetector.normalized("I'm in a GOOD mood — today!")],
    ["text": "  Don't   worry,  it's fine.  ", "result": CarryoverDetector.normalized("  Don't   worry,  it's fine.  ")],
]
out["is_creditable"] = [
    "thanks a lot", "it slipped my mind", "how are you", "push back", "end up staying home",
].map { ["phrase": $0, "result": CarryoverDetector.isCreditable($0)] }

// ── 2. carryover detect (cards + suggestions + expressions; no lemma paths) ─
let cards: [DrillCard] = [
    DrillCard(id: uuid(101), sourcePhrase: "I go bank", targetPhrase: "I went to the bank yesterday",
              reason: "past tense", createdAt: d("2026-08-20T09:00:00Z"), lastReviewedAt: nil,
              nextReviewAt: d("2026-08-21T09:00:00Z"), box: 1, timesSeen: 1, timesCorrect: 0,
              sourceSessionId: uuid(900), sourceTurnId: nil, enrichment: nil),
    DrillCard(id: uuid(102), sourcePhrase: "", targetPhrase: "I'm in a sweet mood today",
              reason: "", createdAt: d("2026-08-20T09:00:00Z"), lastReviewedAt: nil,
              nextReviewAt: NOW, box: 0, timesSeen: 0, timesCorrect: 0,
              sourceSessionId: uuid(900), sourceTurnId: nil, enrichment: nil),
    DrillCard(id: uuid(103), sourcePhrase: "", targetPhrase: "It slipped my mind",
              reason: "", createdAt: d("2026-08-30T09:00:00Z"), lastReviewedAt: nil,
              nextReviewAt: NOW, box: 0, timesSeen: 0, timesCorrect: 0,
              sourceSessionId: uuid(901), sourceTurnId: nil, enrichment: nil),   // born THIS session → never credited
    DrillCard(id: uuid(104), sourcePhrase: "", targetPhrase: "at the end of the day",
              reason: "", createdAt: d("2026-08-25T09:00:00Z"), lastReviewedAt: nil,
              nextReviewAt: NOW, box: 2, timesSeen: 2, timesCorrect: 1,
              sourceSessionId: uuid(902), sourceTurnId: nil, enrichment: nil),
]
let detectTurns: [Turn] = [
    turn(1, .fluentSelf, "Hey, how was the errand?"),
    turn(2, .user, "So yesterday morning I went to the bank yesterday to sort out the card", suggestion:
        TurnSuggestion(alternative: "I'd rather just stay in tonight", reason: "more natural")),
    turn(3, .user, "I'm in a really good mood today because everything worked"),
    turn(4, .user, "honestly at the end of the day it worked out and I'd rather just stay in tonight, honestly"),
    turn(5, .user, "it slipped my mind completely", excluded: false),
]
let detected = CarryoverDetector.detect(
    in: detectTurns, cards: cards,
    curriculumItems: [CarryoverDetector.CurriculumItem(id: uuid(201), text: "sort out the card", isWord: false)],
    studyingExpressions: ["because everything worked"],
    studyingWords: [],
    sessionId: uuid(901), sessionStartedAt: d("2026-08-31T11:00:00Z"), now: NOW)
out["carryover_detect"] = [
    "turns": detectTurns.map { ["idx": Int($0.id.uuidString.suffix(2)) ?? 0, "role": $0.role.rawValue, "text": $0.transcript, "suggestion": $0.suggestion?.alternative as Any] },
    "cards": cards.map { ["id": Int($0.id.uuidString.suffix(3))!, "target": $0.targetPhrase, "createdAt": iso.string(from: $0.createdAt), "sourceSessionIdx": Int($0.sourceSessionId!.uuidString.suffix(3))!] },
    "curriculum": ["sort out the card"], "studyingExpressions": ["because everything worked"],
    "sessionIdx": 901, "sessionStartedAt": "2026-08-31T11:00:00Z", "now": iso.string(from: NOW),
    "result": detected.map { ["source": $0.source.rawValue, "item": $0.item, "quote": $0.quote, "turnIdx": Int($0.turnId.uuidString.suffix(2))!, "sourceIdx": $0.sourceId.map { Int($0.uuidString.suffix(3))! } as Any] },
]

// The sweet/good content-word case must NOT match:
out["carryover_content_word_guard"] = [
    "item": "I'm in a sweet mood today",
    "turn": detectTurns[2].transcript,
    "matched": CarryoverDetector.firstMatch(of: "I'm in a sweet mood today", in: [detectTurns[2]]) != nil,
]

// ── 3. drill ingest ──────────────────────────────────────────────────────
let ingestDir = LanguageScope.activeDirectory
try? FileManager.default.removeItem(at: ingestDir)
try? FileManager.default.createDirectory(at: ingestDir, withIntermediateDirectories: true)
let store = DrillStore()
let ingestTurns: [Turn] = [
    turn(11, .user, "I go to bank yesterday and it was closed so I come back home", suggestion:
        TurnSuggestion(alternative: "I went to the bank yesterday", reason: "past tense")),
    turn(12, .user, "It's depend on weather", suggestion: nil),
]
let summary = SessionSummary(
    phrasesUsed: [PhraseFeedback(id: uuid(301), userSaid: "It's depend on weather",
                                 fluentAlternative: "It depends on the weather", reason: "third-person s"),
                  PhraseFeedback(id: uuid(302), userSaid: "I go to bank yesterday",
                                 fluentAlternative: "I went to the bank, yesterday!", reason: "dup of suggestion")],
    newPatternsDetected: [LearnerPattern(id: uuid(303), mistake: "I come back home",
                                         correction: "I came back home", context: "past tense",
                                         frequency: 2, lastSeenAt: NOW)],
    suggestedDrills: ["Could you give me a hand with this?", "using articles correctly"],
    overallNote: "note", scorecard: nil)
let minted = store.ingest(summary: summary, turns: ingestTurns, sessionId: uuid(901), now: NOW)
out["drill_ingest"] = [
    "turns": ingestTurns.map { ["idx": Int($0.id.uuidString.suffix(2))!, "text": $0.transcript, "suggestion": $0.suggestion?.alternative as Any, "reason": $0.suggestion?.reason as Any] },
    "summary": ["phrases": summary.phrasesUsed.map { ["userSaid": $0.userSaid, "alt": $0.fluentAlternative, "reason": $0.reason] },
                "patterns": summary.newPatternsDetected.map { ["mistake": $0.mistake, "correction": $0.correction, "context": $0.context] },
                "drills": summary.suggestedDrills],
    "mintedCount": minted,
    "cards": store.load().sorted { $0.targetPhrase < $1.targetPhrase }.map {
        ["source": $0.sourcePhrase, "target": $0.targetPhrase, "reason": $0.reason,
         "box": $0.box, "turnIdx": $0.sourceTurnId.map { Int($0.uuidString.suffix(2))! } as Any] },
]

// ── 4. scorecard metrics ─────────────────────────────────────────────────
let metricTurns: [Turn] = [
    turn(21, .user, "It go well. I commute almost one hour today, so I am little tired.",
         fluency: FluencyStats(speakingSeconds: 8, totalSeconds: 10, pauseCount: 2, pauseSeconds: 2, longestPauseSeconds: 1.2),
         durationMs: 10_000),
    turn(22, .fluentSelf, "An hour each way? That adds up."),
    turn(23, .user, "I usually read a news or, um, listen podcast. I mean I sleep sometimes.",
         suggestion: TurnSuggestion(alternative: "I usually read the news", reason: "article"),
         fluency: FluencyStats(speakingSeconds: 6, totalSeconds: 7, pauseCount: 1, pauseSeconds: 1, longestPauseSeconds: 1),
         durationMs: 7_000),
    turn(24, .user, "this one is excluded", excluded: true),
]
let metrics = ScorecardMetrics.compute(turns: metricTurns)
out["scorecard_metrics"] = [
    "turns": metricTurns.map { ["role": $0.role.rawValue, "text": $0.transcript, "durationMs": $0.durationMs,
                                "excluded": $0.excludedFromScoring, "hasSuggestion": $0.suggestion != nil,
                                "fluency": $0.fluency.map { ["speakingSeconds": $0.speakingSeconds, "totalSeconds": $0.totalSeconds, "pauseCount": $0.pauseCount, "pauseSeconds": $0.pauseSeconds] } as Any] },
    "promptJSON": metrics.promptJSON(),
]

// ── 5. profile absorb ────────────────────────────────────────────────────
var profile = LearnerProfile(id: uuid(400), userId: uuid(401), targetLanguage: "en",
    proficiencyLevel: .b1,
    recurringMistakes: [LearnerPattern(id: uuid(402), mistake: "I go yesterday", correction: "I went yesterday",
                                       context: "past", frequency: 3, lastSeenAt: d("2026-08-01T00:00:00Z"))],
    weakVocabAreas: ["cooking verbs", "phone-call phrases"],
    strongPatterns: [], totalSessions: 4, totalSpeakingSeconds: 600,
    lastSessionAt: d("2026-08-01T00:00:00Z"), summaryEmbedding: nil)
let absorbSummary = SessionSummary(
    phrasesUsed: [], newPatternsDetected: [
        LearnerPattern(id: uuid(403), mistake: "i go YESTERDAY ", correction: "I went yesterday (fixed)",
                       context: "tense again", frequency: 2, lastSeenAt: NOW),
        LearnerPattern(id: uuid(404), mistake: "It's depend", correction: "It depends", context: "3rd person",
                       frequency: 1, lastSeenAt: NOW),
    ],
    suggestedDrills: [], overallNote: "", scorecard: nil,
    weakVocabAreas: ["Cooking Verbs", "airport phrases", " ", "startup vocabulary"])
profile.absorb(summary: absorbSummary, speakingSeconds: 123.6, now: NOW)
out["profile_absorb"] = [
    "before": ["recurring": [["mistake": "I go yesterday", "correction": "I went yesterday", "context": "past", "frequency": 3, "lastSeenAt": "2026-08-01T00:00:00Z"]],
               "weak": ["cooking verbs", "phone-call phrases"], "totalSessions": 4, "totalSpeakingSeconds": 600],
    "incoming": ["patterns": [["mistake": "i go YESTERDAY ", "correction": "I went yesterday (fixed)", "context": "tense again", "frequency": 2],
                              ["mistake": "It's depend", "correction": "It depends", "context": "3rd person", "frequency": 1]],
                 "weak": ["Cooking Verbs", "airport phrases", " ", "startup vocabulary"],
                 "speakingSeconds": 123.6, "now": iso.string(from: NOW)],
    "after": ["recurring": profile.recurringMistakes.map { ["mistake": $0.mistake, "correction": $0.correction, "context": $0.context, "frequency": $0.frequency, "lastSeenAt": iso.string(from: $0.lastSeenAt)] },
              "weak": profile.weakVocabAreas, "totalSessions": profile.totalSessions,
              "totalSpeakingSeconds": profile.totalSpeakingSeconds, "lastSessionAt": iso.string(from: profile.lastSessionAt!)],
]

let json = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
let dest = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "vectors.json"
try json.write(to: URL(fileURLWithPath: dest))
print("wrote \(dest) (\(json.count) bytes)")
