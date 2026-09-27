import Foundation

/// One finished talk — or a Watch book's scene — turned into a script the
/// learner can run AGAIN, speaking their own side of it. For a talk, their
/// lines are replaced by the corrected versions; a scene was written fluent,
/// so its lines are read as they are.
///
/// Pure and derived, like everything else a talk book shows: nothing here is
/// persisted, so a talk re-summarized (or a correction the learner later
/// edits) changes the script the next time it is opened.
///
/// What a learner reads on their turn, in order of preference:
///
/// 1. **The turn's own correction** (`Turn.suggestion.alternative`) — a whole
///    sentence, rewritten. This is the one case that is review MATERIAL: it
///    carries the book's correction id, so a passing read masters the Drill
///    chapter exactly as a shadow take on that line does.
/// 2. **The summary's phrase fixes spliced in** (`SessionSummary.phrasesUsed`).
///    Those are PHRASES, not lines — `userSaid` is a verified quote from this
///    turn — so the fix is put back where it was said and the rest of the
///    sentence stands. It carries no attempt id: a summary correction's
///    curriculum item is minted with a fresh UUID on every build, so no
///    shadow attempt could ever be matched to it (only its drill card can
///    master it).
/// 3. **What they said.** A turn nobody corrected is a turn they got right,
///    and reading it back is what keeps the run a CONVERSATION rather than a
///    list of fixes (user decision, 2026-09-27).
///
/// A turn flagged as misheard is dropped outright — its transcript is the
/// recognizer's mistake, and putting it on a prompter would ask the learner
/// to say something they never said. The fluent self's answer to it stays:
/// it is still what happened next.
enum TeleprompterScript {

    struct Step: Identifiable, Hashable {
        /// The source turn's id — also the key `TurnAudioStore` holds the
        /// fluent self's recording under.
        let id: UUID
        let isSpoken: Bool
        /// What is on the prompter (a learner step) or on screen (a
        /// fluent-self step).
        let text: String
        /// What the learner actually said, for the word-level diff. Empty
        /// unless this line was corrected.
        let said: String
        /// The correction's reason, already in the learner's native language
        /// (coaching text — see "Two languages"). Empty when uncorrected.
        let note: String
        /// Where a passing take is filed. Non-nil only for case 1 above —
        /// everything else is practice, not material.
        let attemptId: UUID?

        var isCorrected: Bool { !said.isEmpty }
    }

    /// `@MainActor` for `TalkCurriculum.correctionId` alone — the id a
    /// passing read is filed under has to be the book's own.
    @MainActor
    static func build(session: Session) -> [Step] {
        let fixes = session.summary?.phrasesUsed ?? []
        var out: [Step] = []
        for turn in session.turns {
            let transcript = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { continue }
            guard turn.role == .user else {
                if turn.role == .fluentSelf {
                    out.append(Step(id: turn.id, isSpoken: false, text: transcript,
                                    said: "", note: "", attemptId: nil))
                }
                continue
            }
            guard !turn.excludedFromScoring else { continue }
            if let s = turn.suggestion {
                let alternative = s.alternative.trimmingCharacters(in: .whitespacesAndNewlines)
                if !alternative.isEmpty {
                    out.append(Step(id: turn.id, isSpoken: true, text: alternative,
                                    said: transcript, note: s.reason,
                                    attemptId: TalkCurriculum.correctionId(for: turn.id)))
                    continue
                }
            }
            let spliced = applyPhraseFixes(to: transcript, fixes: fixes)
            out.append(Step(id: turn.id, isSpoken: true,
                            text: spliced.text,
                            said: spliced.changed ? transcript : "",
                            note: spliced.note,
                            attemptId: nil))
        }
        return out
    }

    /// A Watch book's scene, run again with the learner on their own side.
    ///
    /// A scene has no corrections — every line of it was written fluent — so
    /// the prompter shows the "user" lines as they are, which is the scene's
    /// whole point: they are the fluent self's words, and reading them aloud
    /// in the flow of the scene is saying them as the fluent self would. The
    /// counterpart's lines are the answers that play in between.
    ///
    /// Each learner line carries the id of the book's own Shadow-chapter
    /// item for that sentence (the chapter IS the learner's side of the
    /// scene, `ScenarioCurriculumEngine` extracts it that way), so a passing
    /// read masters it through `refreshScenarioMastery` exactly as a take in
    /// `ShadowDrillView` does. Matched by normalized text — the same mapping
    /// `ScenarioDetailView` hands `WatchView` for its "Shadow this" taps.
    static func build(scene: [DialogueEngineTurn],
                      shadowLines: [ScenarioCurriculum.Item]) -> [Step] {
        let lineIds = shadowLines.reduce(into: [String: UUID]()) { map, item in
            map[CarryoverDetector.normalized(item.text)] = map[CarryoverDetector.normalized(item.text)] ?? item.id
        }
        return scene.compactMap { turn in
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let isLearner = turn.speaker == "user"
            return Step(id: turn.id, isSpoken: isLearner, text: text,
                        said: "", note: "",
                        attemptId: isLearner ? lineIds[CarryoverDetector.normalized(text)] : nil)
        }
    }

    /// Put each verified phrase fix back where it was said. A quote that
    /// isn't in this line belongs to another turn; a fix that changes
    /// nothing is dropped, so a run can't claim a correction it didn't make.
    static func applyPhraseFixes(to line: String,
                                 fixes: [PhraseFeedback]) -> (text: String, changed: Bool, note: String) {
        var text = line
        var note = ""
        for fix in fixes {
            let said = fix.userSaid.trimmingCharacters(in: .whitespacesAndNewlines)
            let better = fix.fluentAlternative.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !said.isEmpty, !better.isEmpty,
                  CarryoverDetector.normalized(said) != CarryoverDetector.normalized(better),
                  let range = text.range(of: said, options: [.caseInsensitive, .diacriticInsensitive])
            else { continue }
            text.replaceSubrange(range, with: better)
            if note.isEmpty { note = fix.reason }
        }
        return (text, text != line, note)
    }
}
