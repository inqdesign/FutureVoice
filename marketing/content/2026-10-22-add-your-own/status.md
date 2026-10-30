# status

- **stage**: ready (reviewer PASS round 2; media in R2; renders pruned; pending release-phase scheduling)
- **owner**: lead (autopilot)
- **version/build**: 1.2.2 (118), phase upload
- **request**: Autopilot upload. Market build 118's add-your-own / shared library — the learner
  adds their own words, expressions and sentences to their lists; as they type, items already in
  the library surface (find-as-you-type, no duplicates); a new item gets a CEFR level and joins
  ONE shared library, then flows through the deck/review/widget like a word from a talk.
- **source**: commits `a3a9ff86`, `ac47da0b`, `70175c26`; `SharedLibrary.swift`, `AddToListSheet.swift`.
- **kit**: `nw-words` (cloud + word card) + a faithful add-sheet authored in the carousel (plain
  field, "이미 있어요 / Already there" header — no new screen). Hero word **substantial** (real
  B1 cloud word, not the brief's "leverage"). CEFR levels verified vs cefr_words.tsv: substantial
  B1, deadline B1, commute B2, substitute B1.

## pipeline
- brief → copy → design → review FIX×3 (round 1) → fixes applied (copywriter: removed the
  silent-video "sound on" line from all posted surfaces; designer: commute B1→B2, sublet→substitute,
  removed the search magnifier, added the "이미 있어요" header) → re-rendered cards 02/03/05
  (lead ran record.mjs; subagent's node was gated) → review PASS round 2.
- Media uploaded to R2 (6 slides), captions/threads/titles set, staged ready.

## open questions (release / publisher phase)
- **RELEASE GATE — server must be LIVE**: migration `20261022140000_shared_library.sql` + the
  `library-add` edge function must be deployed to prod before this posts. Adding a term NOT already
  in the library depends on it; if it isn't live the "leveled + shared" story (cards 03–04) isn't
  true yet. Verify at the release re-check.
- **Community series id**: TODO — likely **e22** (after e20/e21 in flight). Publisher confirms.
- Non-blocking: card-05 widget sticker partly covers the EXAMPLE line; copy.md's designer notes
  still name the old "leverage"/B2 hero (the slides correctly use substantial/B1).
