# Review — 2026-10-12-teaser (renders/teaser-ko.mp4) — 2026-10-12, round 2
Verdict: PASS (0 FIX; 1 known open)

## Round-1 items, re-checked on the new render (39.2 s)
1. [voice] 08 — fixed. It now reads "실제로 겪기 전에 / 미리 봐요", with no wake-up reading.
2. [channel] copy.md 05 / 13 (EN) — fixed. They now match teaser.html: "It rings at the time I set." / "Then say it after the fluent me."
3. [visual] first frame — fixed. The pill is speaking at 0.35 from frame 0, and it lights to the audio envelope at 0.5 s.
4. [visual] title overlaps — fixed. The old title reaches 0 before the new one rises (a blank gap frame at each cut, never two titles at once). The call phone is fully gone before the end card fades in (36.2–36.7).
5. [visual] orphans — fixed. The breaks are "실제로 겪기 전에 / 미리 봐요" and "유창한 나를 / 따라 말해요".
6. [visual] Speech — fixed. 81 lands at ~25.8 and holds until the cut at 27.2 (~1.4 s).
7. [visual] weekly test — fixed. 정답 · 계속 (green) shows from ~32.0 and holds until the cut at 32.2. It sits at rest in at least 3 frames at 0.25 s spacing.
8. [visual] words — fixed. "substantial" is tapped, its card opens, and the card's check turns into the filled green check (CLAUDE.md: the filled check = used in a talk), legible at full res @20.9. Its bookmark empties, which is true: a used word leaves the notebook.

## Known open (not blocking — lead reporting to founder)
9. [fidelity] Korean screens show English chrome that the app itself shows: "Future self"/"You" (ConversationView.swift:4688), "Watching" (WatchView.swift:430), Progress chips via `Dim.title` (ProgressTab.swift:149), and "7 more days" (ProgressTab.swift:1074/1130). The kit is faithful. Once the app is fixed, update the kit's ko text and re-render.

## Re-checked for regressions
- Timing shift (home −0.2 s, Speech 2.2 s): every beat's text lands at its cut, and every screen's key moment is inside its beat. The ring → Answer → call, people tap → card, Watch line ringed, book arrive → tap → Drill, and 92 on Say it again are all intact.
- Audio: voice 0.57–2.29 s (silencedetect) under the lit pill. Nothing plays under the call. The correction card still lands after the reply's voice starts.
- Channel: 1080×1920, 30 fps, 39.2 s (≤ 60). The captions and Threads text are unchanged and within limits.

## Suggestions (non-blocking)
- copy.md 08's note says "one line", but the render breaks it in two. Update the note, or keep it to one line if it fits.
- Home still says "this evening" right after the 8:00 alarm. The story's talk (busy week) and the book (interview) are different talks. "나와나" in Threads ko: confirm the Hangul spelling.

Checked frames: renders/teaser-ko.mp4 every 0.25 s from 0.0 to 39.0 (contact sheets), full-res @20.9; audio silencedetect.
