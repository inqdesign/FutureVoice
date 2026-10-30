# Review — add-your-own (1.2.2 / build 118) — 2026-10-22

Verdict: FIX

1. [channel] captions/threads — the "sound on for card 5" line is still in every posted
   surface while the MP4 export is silent (no audio stream; copy.md's own open-Q #3 and the
   e13 precedent confirm the record.mjs export carries no sound). Remove it from: IG ko caption
   ("5번째 장은 소리 켜고 들어 보세요.", copy.md L97), IG en caption ("Turn the sound on for card 5.",
   L114), Threads ko ("소리 켜고 5번째 장 들어 보세요.", L126), Threads en ("Sound on for card 5.", L136),
   and the unused card-05 hint lines (L72–73). → delete those lines; the loop reads fine without them.

2. [truth] card 05 — the Vocabulary widget sticker badges **commute = B1**, but the app's own
   `FutureVoice/Resources/cefr_words.tsv` lists `commute → B2`. The piece's whole thesis is "each
   word carries its true CEFR level," so a wrong level on a named real word contradicts the app
   (substantial B1 and deadline B1 in the same sticker are both correct). → change commute's badge
   to **B2**, or swap commute for a genuine B1 word so all three widget levels match the wordlist.

3. [fidelity] cards 02–03 — the hand-built AddToListSheet draws the input as a grey search pill
   with a magnifier-glass icon. The real `AddToListSheet.swift` field is a plain Form `TextField`
   (no search icon), and its matches sit under an "Already there" section header (the brief's
   sanctioned fallback is an *honest minimal* element, not an invented control). The magnifier
   makes it read as a search box rather than an add field. → drop the magnifier so the field reads
   as the app's plain input, and label the match rows with the app's "이미 있어요 / Already there"
   header.

## Verified clean (no change)
- Hero word **substantial = B1** (cefr_words.tsv L7235) — faithful; matches the kit cloud and the
  task note. deadline B1, guarantee B1 all correct. Side panel correctly states levels are the
  WORD's, not the learner's; card titles ("새 단어엔 레벨이 붙어요") never imply "we read your level".
- The shared-library message stays warm and is NOT a privacy ask: card 04 warm line
  "그 단어가 다음 학습자에게도 도움이 돼요" / "Your word helps the next learner too", caption
  "그 단어가 다음 사람에게도 도움이 돼요." Nothing claims who-added is shared, no community count/size claimed.
- Feature claims true to HEAD: `AddToListSheet.swift` ("+" on Words/Expressions/Sentences, type in
  either language, find-as-you-type "Already there" opening the card not a copy), `SharedLibrary.swift`
  / `library-add` (checked once → CEFR level → one shared `library_terms`), clone-voice pronounce on
  the word card. sheet title "단어 추가" = app's "Add a word". Honest-floor and "typos/made-up words
  turned away" stated plainly in caption, not as a wall on a slide.
- Prices/limits: only free-time claim is "첫 20분은 무료예요 / First 20 minutes free" (outro) — matches
  BRAND facts. No trial claim, no plan numbers.
- Voice: ko reads as native Korean, 해요체 throughout, no 당신, positive-first (limits in parentheses,
  second); en reads native. No translationese.
- No em dash in any posted text (titles, descs, captions, threads, community body). The em dashes in
  copy.md/carousel.html are all in headers, designer notes and JS comments; carousel.html runs a live
  undash sweep over app strings.
- Frames open non-blank, ko fits 2-line layout; card order/numbers consistent 01–06.

## Release-gate reminders (not reviewer-verifiable; founder/publisher checkpoint)
- Server: migration `20261022140000` (`library_terms`) + the `library-add` function must be deployed
  to prod before this ships, or an add of a word not already in the library is blocked
  ("사전에 연결하지 못했어요") and cards 03–04 don't tell the truth.
- Community series id still `TODO` (copy proposes e22). Assign before the community entry deploys;
  founder approval for the community post/news per BRAND.

## Suggestions (non-blocking)
- copy.md "For the designer" + the card 02/03 screen notes still name hero word "leverage" / B2 while
  the piece correctly uses "substantial" / B1 — align the doc so it can't mislead a future reviewer
  (unposted, harmless).
- card 05: the example line ("They made a substantial offer." / "상당한 금액을 제안했다.") is partly
  hidden behind the widget sticker; nudging the widget down a touch would free it, but the headword,
  meaning and pronounce button stay clear, so it's optional.

Checked frames: renders/01.png–06.png (full); renders/02.mp4 @0.1s 2s, 03.mp4 @0.1s 3s, 04.mp4 @0.1s,
05.mp4 @0.1s (opening frames non-blank, ko text fits).

---

# Review (round 2) — add-your-own (1.2.2 / build 118) — 2026-10-22

Verdict: PASS

All 3 round-1 FIX items resolved; nothing else regressed.

1. [channel] RESOLVED — no "sound on" line survives in any posted surface. IG ko (L97),
   IG en (L114), Threads ko (L126), Threads en (L136) and the card-05 hint (L72–73) now read
   the in-app pronounce ("그 단어, 누르면 내 목소리로 읽어 줘요" / "Tap the word and it reads aloud
   in your own voice" / hint "내 목소리로 읽어 줘요"). The only remaining "소리 켜" strings are in the
   internal brief.md L109 and copy.md's Open-Questions L172–173 (the note to drop it) — not posted.
2. [truth] RESOLVED — every CEFR level now matches `cefr_words.tsv`: substantial B1 (L7235),
   deadline B1 (L1877), commute **B2** (L1419, re-rendered widget on 05.png shows B2), substitute
   B1 (L7238, card 03 pool row shows B1). No wrong level on any named real word.
3. [fidelity] RESOLVED — re-rendered 02.png / 03.png / 03.mp4@4s show the add field as the app's
   plain filled input with NO magnifier, and matches sit under the real "이미 있어요 / Already there"
   section header. The unused `.af-g` CSS and `SV.search` glyph remain in source but are never
   rendered.

No new issues: no em dash in posted text, ko reads as native Korean (해요체, no 당신), en native,
only free-time claim is "첫 20분은 무료예요 / First 20 minutes free" (correct), frames open non-blank
and ko fits the 2-line layout. Round-1 "Suggestions" still stand (non-blocking): the widget on
card 05 partly covers the EXAMPLE line, and copy.md's "For the designer" + screen notes still name
the old hero "leverage"/B2 while the piece correctly uses "substantial"/B1.

Release-gate reminders from round 1 unchanged and still founder/publisher checkpoints (not
reviewer-verifiable): deploy `library_terms` migration + `library-add` to prod before ship, and
assign the community series id (TODO → likely e22) with founder approval.

Checked frames: renders/02.png, 03.png, 05.png (re-rendered 17:03); 03.mp4 @4s, 05.mp4 @5s
(plain field + "이미 있어요" header, commute B2, non-blank, text fits).
