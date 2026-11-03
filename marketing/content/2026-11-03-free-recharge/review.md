# Review — 2026-11-03-free-recharge — 2026-11-03

## Round 2 (final)

Verdict: PASS (0 FIX items)

All three round-1 FIX items verified as landed, in the files AND the re-rendered assets
(renders re-made 13:27–13:28):

1. **Accent #0A5CF5 — fixed.** `carousel.html` line 10 now `--blue:#0A5CF5`. Pixel-counted
   the eyebrow square region in every re-rendered PNG: the dominant ink is exactly
   RGB(10,92,245) on cards 01–05 (06 is the outro, no eyebrow — its url/wordmark render
   from the same var). Round 1's #0A84FF is gone.
2. **Card 03 no longer claims the correction is spoken — fixed.** ko desc "틀린 문장은 그
   자리에서 바로 고쳐져요." (copy.md line 62, carousel.html line 108, visible in every
   03.mp4 frame), en "A slip comes back put right, on the spot." The EN caption's same
   claim is also "put right" now. The ko caption's "그 자리에서 고쳐지고" was already
   claim-free.
3. **Re-engagement promise removed — fixed.** "업데이트하고 열어보세요 / 리포트가
   기다려요" is gone from the card-05 `.note` (the element itself removed from
   carousel.html), both IG captions, and both Threads texts; its only remaining
   occurrence is the resolved open-question note in copy.md's meta section, which is not
   posted. The piece is pure acquisition; the Threads ko third paragraph now closes on
   "첫 20분은 무료예요. nawana.app".

Re-render regression check, frames pulled fresh:

- **Card 04**: 2 fps filmstrip over the full 11.5 s — still used → fresh → grammar →
  words → clean loop; deck header panned out; no "이번 주 / this week" in any frame,
  including mid-slides (the skipped week-framed "review" card still teleports with its
  transition off).
- **Card 05**: 15 frames over 7.7 s — the Talk ring only, start to loop. No offer UI, no
  button, no report last card. Text block is now eyebrow + title + 2-line desc exactly
  (the third line went with fix 3), no overflow.
- **Cards 01/02/03/06**: unchanged scenes, no clipping, titles ≤ 2 lines, cover holds as
  a still, outro carries the exact fixed lines. All six items 1080×1350, 30 fps, 6–12 s.
- Banned-word sweep on the updated files: 체험 / trial / 무제한 / 당신 / em dash — zero in
  postable text.

Publish-day conditions for the publisher (not blockers on the piece):
- Confirm `billing_config.free_recharge_seconds` is live at 1200 before posting
  (migration `20261103150000_free_recharge.sql` defaults it to 1200; applying it to prod
  is a human step). 0 would mean the button the copy describes isn't drawn.
- 1.2.9 must be live on the store before posting — the recharge card exists only there.
- Captions, Threads, and the `e20` series entry still need the founder's OK / veto
  window, per BRAND.md.

Suggestion (non-blocking, carried from round 1): card 05's kit greeting "What's on your
mind this evening?" under a 09:41 status bar — a morning line would read cleaner if the
kit offers one.

Checked frames (round 2): renders/03.mp4 2 fps strip @0–12 s · renders/04.mp4 2 fps
strip @0–11.5 s · renders/05.mp4 2 fps strip @0–7.7 s (15 frames) · all six PNGs ·
exact-color histogram of the eyebrow region in 01–06.png (dominant 10,92,245).

---

## Round 1 — 2026-11-03 (superseded)

Verdict was FIX (3):

1. [visual] page accent was `#0A84FF` (BRAND: #0A5CF5), verified in renders.
2. [truth|voice] card 03 "고쳐 들려줘요 / said right" claimed the correction is spoken;
   it is a card.
3. [truth] "업데이트하고 열어보세요. 리포트가 기다려요" conflicted with the deck's
   `maxOffers (2)` / `finished` gate (`RootTabView.offerTrialReport`, CLAUDE.md "at most
   maxOffers (2) openings, then never again").

Round-1 passes that still stand: card 05 hard constraint (no offer UI in any frame),
card 04 week-framing exclusion, kit-only screens with sample data, channel fit, 해요체 /
no 당신 / positive-first, alt texts on all six cards in both languages, "한 번 더" always
beside "계정당 한 번", community id `e20` free, no real user data.
