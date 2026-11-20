# Review — 2026-11-15-streak-one-thing — 2026-11-17

## Round 2 (final): Verdict: PASS

All four round-1 FIX items verified fixed, in the code and in the re-rendered pixels
(1080×1350 confirmed on all three new MP4s):

1. ✔ Card 03 hero — `routine.js` `day-one` now `_mark(3, "kept")`; in `PLAY.one` today's
   circle flips SOLID GREEN at the first touch of the block (`r._fill(0, .4);
   r._mark(3, "kept"); r._streak(kept(4), true)`), which is exactly
   `PlannerDayView.mark`'s behaviour (a kept today returns `.kept`, never a partial arc
   once anything is touched). Checked 03.png and 03.mp4 @0s 4s 6s 8.5s: one block checked,
   today solid green with white number, 4일째 + flame, other blocks open, loop seam
   returns to the clean day-plan start. The card now shows what the title says.
2. ✔ Card 04 closing beat — ends on one block done + today solid green + 4일째
   (04.png, 04.mp4 @6s). No more "one done but not green" state anywhere in the piece.
3. ✔ Card 04 opening — 금 9 is kept from frame one (04.mp4 @0s and the @9s loop seam);
   dashed rings appear only on future days (일 11 · 월 12 · 화 13). The rest day 목 8 is a
   bare grey date between greens, which is the app's own drawing.
4. ✔ Card 04 alt (ko/en) rewritten to "동그라미 없이 회색 날짜 숫자로만" / "one plain grey
   date number with no circle" — now describes what is drawn.

Also checked: card 05's re-render follows the same first-touch rule (05.mp4 @3s 5s 10s —
today kept the moment the first block starts, the rest filling behind it; 05.png
unchanged day-kept, a real state). No regression on cards 01/02/06 (untouched,
timestamps confirm). Pixel-font/em-dash/당신 greps still clean.

On the two leftovers the coordinator flagged: copy.md card 04's `screen:` line and open
question 4 still say "grey rest circle" — those are designer-facing production notes that
reach no published surface (alt, titles, descs, captions are all correct), so they do
NOT block. Listed under Suggestions.

### Suggestions (non-blocking)
- copy.md card 04 `screen:` line + open question 4: update "grey rest circle" to "grey
  date number" so the production notes match what shipped (copywriter, whenever touched
  next).
- `routine.js` `demo()` (not used by this piece) still animates the old-rule partial day
  arc (`_mark(3, "today", p*.2)` … `(i+1)/5`) before kept — the kit's generic demo now
  contradicts 1.3.5; fix before any other piece leans on `demo()` (designer/web).
- Carried from round 1: don't publish the zoom-state PNG stills of 02–05 on their own
  (no title text); Threads "바를 낮췄어요" → "기준을 낮췄어요" reads more natural; the e20
  community-series id collision still needs publisher + lead before deploy.

Checked frames (round 2): renders/03.mp4 @0s 4s 6s 8.5s · 04.mp4 @0s 3s 6s 9s ·
05.mp4 @3s 5s 10s · stills 03.png 04.png 05.png (01/02/06 unchanged from round 1).

---

# Round 1 — 2026-11-17 (superseded)

Verdict: FIX (4 items)

Facts verified against the app first: since 558b666b (1.3.5), `Entry.kept = touched >= 1`,
and in `PlannerDayView.mark` **a kept TODAY returns `.kept` — a solid green circle fill**;
the partial progress arc (`.today(done/planned)`) is only reachable while nothing is
touched. A rest day draws as a bare grey date number, no circle (`case .rest:
number.foregroundStyle(.tertiary)`). That is the yardstick for the items below.

1. [fidelity|truth] card 03 (hero) — the key moment contradicts both the card's own copy
   and the app. After 대화 10분 checks green, today's circle (토 10) stays a ~20% partial
   arc for the whole card (03.png; 03.mp4 @5s, @7s, @9s) under the title "하나만 시작하면
   그날은 초록불" and the desc "오늘 동그라미가 초록으로 차요". In the app, one started
   block makes the day kept and **today's circle fills solid green at once**; the drawn
   combination (streak ticked to 4일째 + flame lit + circle NOT kept) is a state the app
   cannot produce. → In `web/kit/screens/routine.js`, `day-one` pose: replace
   `this._mark(3, "today", 1/5)` with `this._mark(3, "kept")`. In `carousel.html`
   `PLAY.one`: the block's own ring may step (.4/.8/1), but the DAY circle must flip to
   `_mark(3, "kept")` together with `_streak(kept(4), true)` — drop the
   `r._mark(3, "today", p / 5)` steps. Re-render 03.png + 03.mp4. Owner: designer.

2. [fidelity] card 04, closing beat — the same impossible state two cards after the card
   that denies it: `r._fill(0, 1); r._mark(3, "today", .2)` leaves one planned block done,
   today's circle not green and the streak stuck at 3일째 (04.png shows exactly this:
   대화 checked, arc 20%, "3일째 지키는 중"). → After the fill, `_mark(3, "kept")` +
   `_streak(kept(4), true)` — or cut the today-fill beat and end the card on the rest-day
   strip (the card's subject). Re-render 04.png + 04.mp4. Owner: designer.

3. [fidelity] card 04, opening — 금 9 (the day BEFORE today) is drawn as a dashed
   "planned, coming up" ring (`_mark(2, "ahead")`) for the first ~3 s of each loop
   (04.mp4 @0–3s and again at the loop seam ~@9s). The app draws a dashed ring only on a
   FUTURE day; a past day is kept, missed or rest — this state is invented. → Start 금 as
   `kept` with `_streak(kept(3))` from the first frame (the final/still state already
   does), and let the motion be the zoom plus the (fixed per item 2) today beat. Owner:
   designer.

4. [truth, alt text] card 04 alt misdescribes the picture: "지킨 초록 동그라미들 사이에
   회색 쉬는 날 동그라미가 하나 있어요" / "one grey rest-day circle". What is drawn — and
   what the app draws — is a bare grey **date number with no circle**. → Rewrite the alt
   to match. Same wording slip in the viewer's side list ("초록 사이 회색 동그라미") —
   unpublished chrome, fix with the same stroke. Owner: copywriter.

## Deviation judgments (status.md ①–③)

- ① Rest day as a bare grey number, not a ringed circle: the DRAWING passes — it is
  pixel-what-the-app-does (`.rest` = tertiary number, no shape). Only the alt text is
  wrong → item 4.
- ② Whole-phone zoom instead of a crop of the streak line: passes — BRAND says the phone
  is "never cropped"; the row highlight + flame pop land the eye well enough (02.mp4
  @4s, @8s). No change.
- ③ Today's circle as a partial arc on the hero: does NOT pass → items 1–2. Since
  1.3.5 the partial arc on a promise day effectively never shows once anything is
  started; the arc is the OLD rule's picture, the one this piece announces is gone.

## What passed (round 1, unchanged)

- Truth of the claims: "하나만 시작해도 지켜져요" everywhere qualified as 계획한 것 중
  하나 (cover desc names a call that is a pictured planned block; caption "그중 하나만");
  rest day consistently "아무것도 계획하지 않은 날"; nothing reads as "skip a planned day
  for free" or "any day counts". Free offer "첫 20분은 무료예요" matches BRAND. No Core
  seal/rank/badge anywhere (the orange seal-shaped tile is the weekly test's own block
  icon, inside the phone — correct app UI).
- Voice: 해요체 throughout, no 당신, no em dash in any visible/published text, Korean and
  English both read native, positive-first, no hype, no grading.
- Visual/type: no pixel font in marketing type (grep + eyes clean; `--pixel` appears only
  inside the kit phone's own nav title, which is allowed); heavy sans titles, two lines,
  no overflow or clipping on any card; mosaic only clipped in the outro pill; colours
  #FF8D28 / #34C759 as the app's. First frames of all four MP4s are full wide cards, not
  blank. Card numbers 01–06 consistent.
- Channel: all renders 1080×1350 (ffprobe); MP4s 9.5–11.5 s ≤ 60 s; caption lengths fine,
  5 hashtags; Threads ≈240 chars ≤ 500.
- Safety: kit sample data only (sample N marked in alt), no real names, no testimonials.

Checked frames (round 1): renders/02.mp4 @0s 1s 4s 8s 10s · 03.mp4 @0s 1s 5s 7s 9s ·
04.mp4 @0s 1s 4s 6s 9s · 05.mp4 @0s 1s 5s 9s 11s · stills 01–06.png
