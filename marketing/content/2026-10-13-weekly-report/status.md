# Series 07 · 위클리 리포트 (Your week)

- **Stage:** design done 2026-10-13 (renders + Desktop export) → next: review, then founder approval of captions
- **Request (founder, 2026-10-13):** "커뮤니티에 이미 좋은 섹션들이 있긴한데, 이걸 비디오로 만드는거야." Source: community none (kit nw-weekreport; piece 01 v2 card 09 as head start), turned into animated kit scenes.
- **Carry-overs (piece 01 + shadowing):** light theme, kit screens only, Pixelify wordmark, eyebrow "nawana · NN / total", cover = a problem in the learner's words → the answer, ONE story (the interview talk), AI tutor vs my own voice only as a pointer, no em dash, captions + Threads REPLY in the series thread + Desktop export for manual upload, audio only where it proves the point.
- **Audio:** none.
- **Open for the founder:** community entry (replace the old one or add new); founder's own voice in public where a learner take is used.
- **Kit gaps:** see brief.md "Kit gaps" (mkt-web before design).

## 2026-10-13 design — renders done (designer)
- carousel.html: piece 01's card system (fixed text block, light, #0A5CF5, Pixelify wordmark, eyebrow `nawana · NN / 08`, same outro, `?solo=N`, `data-scene` for `--wait-for`, `?lang=en` text check). Copy exactly as copy.md. Screens: `nw-weekreport sample="interview"`, `nw-weeklytest sample="interview"` laid over on 07, `nw-home` under the sheet on 02.
- Scenes: 02 Talk tab → the deck slides up by itself → days light → summary held → slides down. 03 cover → Next → talks → Next → used (compelling, prioritize with the learner's lines). 04 practice → Next → new from the fluent self, camera down to "표현 목록에 담아뒀어요". 05 where you got stuck → Next → grammar (go/tell/call struck → fixed + tip). 06 words to level up (very happy ×4 → thrilled) → Next → coach (headline, quote, 3-step plan). 07 coach → Next → test card → notice offered and tapped → "이번 주 테스트 풀기" pressed → grammar item "…tell a real story." rebuilt with told → 정답. Test half: no flame, no gauge.
- 07 shows the grammar item as 1/7 (the engine shuffles the paper, so the slip can come first) rather than jumping to 5/7.
- renders/ (1080×1350, H.264 30 fps, silent; each MP4 = loop 2 of a two-loop recording, cut at the measured period, seams checked): 01.png · 02.mp4 8.17 s · 03.mp4 9.90 s · 04.mp4 9.07 s · 05.mp4 8.97 s · 06.mp4 9.83 s · 07.mp4 12.73 s · 08.png; posters 02–07.png (02 summary · 03 used · 04 fresh with the note · 05 grammar · 06 coach · 07 test card with the notice on).
- Desktop export: ~/Desktop/nawana-carousel-07-weekly-report/ (01.png, 02–07.mp4, 08.png, posters/, captions.txt with IG ko/en + Threads ko verbatim + upload order).
- Not rendered: the en set (text block only checkable via `?lang=en`).

## 2026-10-14 review FIX applied (designer)
- Item 1: caption back-pointer replaced in copy.md + Desktop captions.txt (IG ko/en, Threads) with review.md's exact lines; copy.md note on 06/07 swap updated to match.
- Item 3: card 02 desc → "…지난 돌아보기도 언제든 다시 볼 수 있어요." in copy.md + carousel.html; still 2 lines.
- Item 2 (kit by mkt-web: prioritize line, newCount 3): re-rendered 02.mp4 8.20 s · 03.mp4 9.90 s · 04.mp4 9.07 s (loop 2 of a 22 s recording, cut at measured period; seams return to first frame), posters 02–04 (02 summary "새 표현 3개" · 03 used · 04 fresh 3 with the note). Desktop export: only 02–04 mp4 + posters/02–04 overwritten, byte-identical to renders/.
- Stage: back to review (re-check of 02–04 + captions).

## 2026-10-14 HQ re-render (designer)
- record.mjs default (2× supersampled PNG frames → lanczos, CRF 12, BT.709 tv range; posters downscaled from 2×), all 8 cards. Method unchanged: period measured from `dataset.loopStarts`, recording starts at loop 2 (`--wait-for dataset.loopMs --warmup 0`) for exactly one period. 02.mp4 8.17 s · 03.mp4 9.93 s · 04.mp4 9.07 s · 05.mp4 8.97 s · 06.mp4 9.87 s · 07.mp4 12.73 s; 01.png · 08.png; posters 02–07 at the same moments as before (summary · used · new 3 with the note · grammar · coach · test card). Frames checked at start, thirds, end; cadence ≥ 92% of the previous renders' unique frames. renders/ and ~/Desktop/nawana-carousel-07-weekly-report/ (cards + posters/) overwritten; captions.txt untouched.

## 2026-10-14 design — Korean clarity pass (copy.md) applied
- carousel.html ko: cover chips 04/07, 02 desc, 03 desc, 04 title + desc, 05 title, 06 desc, side index 04/05. English untouched. Every ko title and desc renders in 2 lines (06 desc now wraps to 2).
- Re-rendered HQ (two-loop raw take, loop 2 cut at `loopStarts` + 0.034 s, length = one measured period, CRF 12 BT.709, load < 8, one at a time): 01.png · 02.mp4 8.20 s · 03.mp4 9.90 s · 04.mp4 9.10 s · 05.mp4 9.00 s · 06.mp4 9.87 s + posters 02–06 at the same moments (summary · used · new 3 with the note · grammar · coach). Seams checked end → start. 07/08 untouched.
- Desktop export: 01.png, 02–06.mp4, posters 02–06 overwritten; captions.txt left as the lead updated it.

## 2026-10-14 design: English set rendered (?lang=en)
- carousel.html `EN` block brought in line with copy.md's English clarity pass (every en title, desc and cover chip; bold spans as copy.md's **…**). Korean untouched. Cover title: en line 1 "You put in the work." wrapped to 3 lines at 110px, so the en cover title is 96px (`.wrap:lang(en) .c-cover .ttl`, the piece 02 precedent); words unchanged.
- Every en title and desc measured at 2 lines (DOM line count). App chrome checked in frames: English throughout (kit reads the page lang); sample coaching text shows its en version.
- Renders (record.mjs HQ settings, two-loop take, loop 2 cut at `loopStarts` + 0.2 s, length = one measured period, one render at a time under caffeinate): 01.png · 02.mp4 8.20 s · 03.mp4 9.93 s · 04.mp4 9.07 s · 05.mp4 8.97 s · 06.mp4 9.87 s · 07.mp4 12.73 s · 08.png; posters 02–07 (03 on the settled Used card, not mid-swipe like the ko poster; 05 on the grammar card). Seams checked (start/end frames match the ko renders' start/end states); frames checked at start, thirds, end.
- Stored in renders/en/ (cards + posters/) and exported to ~/Desktop/nawana-carousel-07-weekly-report-en/ (cards in upload order + posters/); captions-en.txt untouched.
