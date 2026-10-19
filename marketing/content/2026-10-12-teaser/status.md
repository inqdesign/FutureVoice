# 티저 영상 — 업데이트된 앱 화면 전부

- **Stage:** brief
- **Request (founder, 2026-10-12):** "지금 업데이트된 모든 UI 컴포넌트로 마케팅 비디오를 만들어 볼 수 있을까 티져비디오로"
- **Owner:** lead
- **Lead defaults (founder can change):** one continuous vertical video 1080×1920 (Reel/Story/Shorts), ~30–40 s, light theme, Korean first (EN variant later), every web/kit screen appears (call, home, watch, people, review, book, bookpage, words, shadow, sayagain, speech (no challenges), routine, ring/daily call, weeklytest, weekreport, progress). No posting.
- **Open questions:** music/sound (none by default); EN version.

## 2026-10-12 design — Korean cut rendered
- **Stage:** design done → review.
- `teaser.html`: a new 1080×1920 page (the carousel template's ground, grid and pixel title, in 9:16; text block at y≈262–520, clear of the Reels header). One `nw-phone` per screen, all stacked in one place; a cut is a 0.26 s crossfade of the screen. `?lang=en` swaps in the English beats (05 "It rings at the time I set.", 13 "Then say it after the fluent me."); only Korean was rendered. Sets `data-scene` and starts its clock 1.2 s later (= record.mjs warmup), so t=0 is the MP4's first frame.
- **renders/teaser-ko.mp4**: 39.0 s, H.264 1080×1920 30 fps + AAC. Audio = `2026-10-11-what-you-can-do/audio/3-clone.mp3` laid at 0.4 s (pill lights from 0.43 s, measured off the frames), nothing else. **renders/teaser-ko.png**: poster at 35.5 s (Act 3, the call with the correction card and the reply).
- Timeline (s): 0 voice pill + caption · 2.6 call (02/03/04, correction lands 300 ms into the reply) · 9.6 ring · 11.4 home · 12.8 people · 14.2 watch (playing, material none) · 16.0 review: book arrives (09) → tapped (10) → Drill chapter (11), one continuous take · 20.0 words · 21.4 shadow · 23.0 say it again (92) · 25.2 speech nochallenges (81, no board) · 27.0 routine (flame) · 28.8 week report (grammar page) · 30.4 weekly test (translate, right) · 32.0 progress (B2) · 33.4 back on the call · 36.0 end card (last 1.3 s held at a fixed level).
- Departures from the brief: 09–11 run as one nw-review take (book lands → tap → drill), not three cuts, because the arrival has to come before the tap. Week report uses its `grammar` page (the brief's "coach" pose means the grammar point; `?report=coach` switches it). 39 s, not 38.

## 2026-10-12 review FIX applied (designer) — items 3–8
- 3: the pill opens already speaking (level 0.35), and the caption is readable from frame 0 (unlit words in --sub, lit in ink).
- 4: the old title fades out (0.12 s) before the new one fades in (delay 0.14 s), so two titles never overlap. The end card fades in 0.3 s after the call phone is gone.
- 5: 08 is now "실제로 겪기 전에<br>미리 봐요" and 13 is "유창한 나를<br>따라 말해요".
- 6: the speech result starts at the cut and 81 rests from ~26.5 s (cut 27.2). The speech beat runs 2.2 s, and home was trimmed to 1.2 s.
- 7: the weekly test's tiles are laid from 0.45 s before its cut, so the right-answer state (정답 · 계속) holds from ~31.3 s to the cut at 32.2.
- 8: the words beat ticks one word, then opens "substantial" on the word card, and the card's check turns into the kit's filled green check. The whole state holds 0.6 s.
- Re-rendered: renders/teaser-ko.mp4 is 39.2 s with the audio at 0.4 s. renders/teaser-ko.png is the poster at 35.7 s. Frames checked right after every cut.
- Item 9 (English chrome on the Korean screens) is with the lead (an app fix), so it isn't in this render.

## 2026-10-12 lead
- Review round 2: PASS. Preview: https://claude.ai/artifact/2JsgxzgpqBY4bzvQ5WhGrL
- Known open (app bug, not fixed here): Korean screens show English labels ("Future self"/"You", "Watching", Progress tab names, "7 more days") — app passes plain Strings (ConversationView.swift:4688, WatchView.swift:430, ProgressTab.swift:149/1074/1130). Reported to founder.
- Waiting for founder: approval / changes, sound (clone line only vs Korean cold open), music, EN render.
