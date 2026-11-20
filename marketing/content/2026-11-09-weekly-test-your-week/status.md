# status

- **slug**: 2026-11-09-weekly-test-your-week
- **version/build**: 1.3.2 (137)
- **phase**: upload (autopilot)
- **stage**: ready
- **owner**: lead
- **request (autopilot)**: the weekly-test redesign — the paper is about THAT week's
  material, a right answer counts as "known" in your review cards and books, and "My answer is
  right too" lets you appeal a wrong mark. Release-notes feature. Kit `nw-weeklytest` + the
  `weekly-test-*` captures render the test items and result page.

## open questions
- (none)

## decisions
- **Resumed by the build-137 run.** The build-136 run had left the piece at `design` with
  brief + copy + carousel.html but only 2/6 cards rendered and no review. Build 137 finished
  the renders (all 6), reviewed, and shipped to `ready`.
- Build bumped 136 → 137 (reviewer flagged the metadata mismatch).
- **Review: PASS**, round 1 — the only FIX was Threads EN at 514 chars; copywriter trimmed it
  to 487. No re-render needed (channel text, not a slide).
- **Captions**: hashtags are joined to the CTA line rather than a separate block, because this
  run's shell blocks a newline-immediately-before-`#` in a CLI arg. Body text is 100% the
  approved copy. The founder can restore the block form in the console during the veto window.
- **alt_ko/alt_en** are written in copy.md (and staged in scratchpad/wt-alt.json); not merged
  onto the slides this run (JSON quoting tripped the same shell guard, and alt isn't required
  for `ready`/posting). Mergeable later with `db.py slides-merge`.
- **Second piece: none.** The 1.3.2 headline NEW features (Speech Season 2 native-reading
  comparison + nicknames; the new speech result page) are undrawable — no captures, and the
  kit renders only the old result page. Recorded as a run note; blocked on a `-capture` of the
  Season 2 result page.

## media
- 6 slides in R2 (`nawana-marketing/2026-11-09-weekly-test-your-week/*`): 01 cover PNG,
  02–05 MP4+PNG loops, 06 outro PNG; JPG + web-JPG per card. Local renders pruned.
