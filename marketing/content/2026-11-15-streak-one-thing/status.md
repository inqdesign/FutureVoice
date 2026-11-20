# 2026-11-15-streak-one-thing

- **Stage:** ready (2026-11-17 autopilot, upload 1.3.6/145 — review round 1 FIX×4 → round 2 PASS; 6 slides + alts in R2, captions/threads set, local renders pruned; posts after the release phase schedules it)
- **Phase:** upload (autopilot) · 1.3.6 (145) — adopted from the 1.3.5 run; the streak change landed after iOS build 144 and ships to iPhone in 145
- **Note:** copy.md done; `day-one` pose exists in web/kit/screens/routine.js (copy's one blocker cleared)
- **Owner:** lead
- **Request (founder's words / release note):** "나의 루틴에 넣은 것 중 하나만 시작해도 그날의 연속 기록이 이어져요." / "Start just one thing from My routine, and the day keeps your streak."

## The feature (from commit 558b666b, CLAUDE.md "The streak is the learner's OWN promise")
The promise-streak rule was lowered on 2026-11-14. A promise day used to need **every** planned block *started* (9 of 10 words already counted) — now **one started block is enough** (`Entry.kept` = `touched >= 1`), and a day with nothing planned is a rest day that neither counts nor breaks. Days already on file were re-read upward. The routine intro now reads "Did any of it? It turns green."

## Screen
`nw-routine` kit screen (built from `marketing/captures/activity-week.png`): poses `day`, `day-plan`, `day-kept` — a routine day with planned blocks, the week circles, and the streak flame that lights orange (#FF8D28) when the day is kept. Shows the day circle filling and the flame going lit.

## Design (2026-11-17, autopilot)
- `carousel.html` built on the 2026-11-09 template (heavy sans, no pixel font; grep clean), ko primary,
  `?lang=en` carries copy.md's EN block. Cards: cover (day-plan still) · promise (rows read down, then
  zoomed on the streak line) · one (HERO: `day-one` — one block checks green, today's arc starts, streak
  ticks to 4일째; sticker "하나면 충분 ✓" in the blank lower screen area, moved there after a first render
  covered the streak line) · rest (수 kept · 목 rest · 금 kept · 토 today; 금 turns kept across the grey day,
  flame never flickers) · flame (day-kept: all blocks fill, today's circle turns solid, flame pops) · outro
  (closing "하루에 하나, 그거면 돼요." above the BRAND block; eyebrow empty, 06/06 kept, per copy).
- Scene motion uses only the screen's own `_fill/_mark/_streak` states + two injected emphasis styles
  (iOS pressed-row highlight, a one-beat flame scale pop) — no invented UI.
- Deviations from copy.md: ① card 4's rest day draws as the kit/app draws it — a bare grey number, not a
  "grey circle" with a ring; the copy's alt text says 동그라미, reviewer may want the alt softened.
  ② card 2's "zoom on the streak line" is the template's whole-phone zoom (phone is never cropped); the
  row highlight walks the list and the flame pops to land the eye on the streak line.
- Renders (1080×1350, ffprobe-verified): 01.png · 02.mp4 10.6s + 02.png · 03.mp4 10.4s + 03.png ·
  04.mp4 9.5s + 04.png · 05.mp4 11.5s + 05.png · 06.png. Frames extracted and checked per MP4.

## Review fixes (2026-11-17, autopilot, after FIX verdict — review.md)
- Item 1 (card 03): `day-one` in `web/kit/screens/routine.js` now marks today `kept` (solid green)
  instead of a 1/5 arc, per PlannerDayView.mark (one-line fix as directed by the lead). In PLAY.one
  today flips SOLID GREEN + streak 4일째 + flame pop the moment the first fill step lands; the block's
  own ring then steps .4/.8/1. No partial day-arc anywhere in the card. New loop 9.5 s.
- Items 2+3 (card 04): 금 starts `kept` from the first frame (dashed is future-only now — no replay
  beat), streak 3일째 lit from the start; the closing beat is one block done + today `kept` + streak
  4일째 (the impossible done-but-not-green state is gone). New loop 9.7 s; PNG taken after the beat.
- Card 05 (my call, same yardstick as items 1–2): the mid-motion partial day-arc while blocks were
  being touched was the same impossible state, so today flips kept at the first touch there too and
  the blocks fill behind it. Loop stays 11.5 s. Re-rendered alongside.
- Item 4's chrome slip in MY file (viewer side list "초록 사이 회색 동그라미") reworded to
  "초록 동그라미 사이 회색 날짜"; copy.md untouched (copywriter owns the alt fix).
- Re-rendered + ffprobe-verified (all 1080×1350): 03.mp4 9.5s + 03.png · 04.mp4 9.7s + 04.png ·
  05.mp4 11.5s + 05.png. Frames checked: 04 first frame (금 kept, no dash), 04 loop seam, 03 mid
  (today solid while ring fills), 05 mid (kept at first touch).

## Open questions
- none blocking (autopilot: decide and record)
