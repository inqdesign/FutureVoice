# 2026-10-12-speech-challenges

- **Stage:** ready (reviewer PASS round 2 · 6 slides in R2 · not yet scheduled — scheduling
  happens on the 1.1.8 release phase)
- **Owner:** — (awaiting release kickoff)
- **Phase:** upload · 1.1.8 (93) · autopilot
- **Request (autopilot):** 1.1.8 added Challenges to the Speech tab — everyone learning a
  language reads the SAME script and competes on score. Only camera-on takes count; the
  leaderboard shows just a name and a score (never the video or audio).

## The message
모두 같은 원고를 읽고 점수로 겨뤄요 — 카메라 켠 기록만, 순위엔 이름과 점수만.

## Carousel (6 cards, all kit `nw-speech`)
01 cover (list, "41명 도전 중") · 02 prompter (no levels, one board) · 03 privacy (camNote,
camera on → board) · 04 score (result 81, orange, 5 rows) · 05 payoff (rankUp 14→8, sample
names) · 06 outro ("첫 20분은 무료예요"). Media + JPEGs live in R2; local renders pruned.

## Review
- Round 1 FIX x2 (designer): #1 blocking — 04/05 mp4 loop-seam double-exposure → re-recorded
  settled (first frame == last frame). #2 EN renders — OUT OF SCOPE (one Korean slide set
  registered; DB schema has no per-language slide set).
- Round 2: **PASS** — seam fixed, no founder name, score honest at 81.

## Decisions (autopilot)
- Voice engine already covered by `2026-10-12-your-voice` (ready). People map (사람 지도)
  DROPPED this run: no capture of the shipped redesign, kit renders the old Watch. One piece.
- `media.sh` needs ABSOLUTE file paths (it cds to admin/ before wrangler; relative `--file`
  fails) — worth fixing in the script.

## Pending (founder / release phase)
- Scheduling: on the 1.1.8 App Store release kickoff, this is re-checked and scheduled.
- Community series entry (copy.md proposes id e20, cat: practice) — a live-site change,
  needs founder approval; NOT done by autopilot.
- Captions/Threads approval before any post (scheduler posts after the veto window).
