# Series 06 · 위클리 테스트 (Weekly test)

- **Stage:** design done 2026-10-14 (renders + Desktop export, silent) → next: review, then founder approval of captions; Audio A on 06 later
- **Request (founder, 2026-10-13):** "커뮤니티에 이미 좋은 섹션들이 있긴한데, 이걸 비디오로 만드는거야." Source: community e16 (drops build slide + monthly test), turned into animated kit scenes.
- **Carry-overs (piece 01 + shadowing):** light theme, kit screens only, Pixelify wordmark, eyebrow "nawana · NN / total", cover = a problem in the learner's words → the answer, ONE story (the interview talk), AI tutor vs my own voice only as a pointer, no em dash, captions + Threads REPLY in the series thread + Desktop export for manual upload, audio only where it proves the point.
- **Audio:** reuse shadowing Audio A on card 06; no new take.
- **Open for the founder:** community entry (replace the old one or add new); founder's own voice in public where a learner take is used.
- **Kit gaps:** see brief.md "Kit gaps" (mkt-web before design).

## 2026-10-14 design — renders done (designer)
- carousel.html: piece 01's card system (fixed text block, light, #0A5CF5, Pixelify wordmark, eyebrow `nawana` + `NN / 08`, same outro, `?solo=N`, `data-scene` for `--wait-for`, `?lang=en` text check). Copy exactly as copy.md; card 06's hint "소리 켜고 들어 보세요" left out (silent for now).
- Screens: 02 `nw-review` (header face with its dot pressed via `openTest("word")`, the sheet's test is `sample="interview"`, 1/7, host looks around, sheet back down). 03–07 `nw-weeklytest sample="interview"`: 03 meaning "perspective" → right, happy. 04 gap → took the initiative → right. 05 translate "어제 면접관이 다시 전화했어." tiles laid, "call"/"calls" left in the tray → right → 과거 시제 + 지난번엔 이렇게 말했어요 it go → it went + 함정 단어 · 내 실수에서 나온 말. 06 listen: play pressed (silent), tiles laid in order → right. 07 result 6 / 7 잘한 한 주예요, missed "took the initiative", footer line (no flame, no gauge) → next week's paper 1/8 with the 다시 badge, answered right.
- **Illustrative:** the translate item (prompt, answer, decoys call/calls) is the kit's placeholder, kept on the series' past-tense slip; it is NOT the engine's output (brief Risk 2). Swap before posting if the founder wants the real sentence. The listen tiles and meaning decoys are kit sample data too.
- renders/ (record.mjs HQ: 2x supersample, CRF 12, BT.709; 1080×1350, 30 fps, silent; each MP4 = one loop cut from a two-loop take at the measured period, starting on the scene's fresh state; seams checked end→start): 01.png · 02.mp4 8.57 s · 03.mp4 7.73 s · 04.mp4 7.97 s · 05.mp4 11.63 s · 06.mp4 10.00 s · 07.mp4 10.03 s · 08.png; posters 02–07.png (02 opened paper · 03/04 right · 05 explanation state · 06 rebuilt · 07 result).
- Desktop export: ~/Desktop/nawana-carousel-06-weekly-test/ (01.png, 02–07.mp4, 08.png, posters/, captions.txt: IG ko/en + Threads ko verbatim from copy.md, minus the "6번째 장은 소리 켜고…" / "Sound on for card 6." lines while silent).
- Not done: Audio A on 06 (later); the en set (text only via `?lang=en`); UI answer sounds (founder's call).

## 2026-10-14 review FIX 1–4 applied (designer)
- copy.md + Desktop captions.txt: Threads "이번 주 통화 교재의 단어, …"; en IG "…, each with a blank to fill."; card 06 ko desc "이번 주에 유창한 내가 …"; card 03 en desc "…, words you haven't mastered first." (carousel.html too).
- Card 07: a push-in (2.3x) on the caption line when next week's paper opens, so the 다시 badge reads at phone size, then back out before the answer.
- Re-rendered (HQ recorder): 06.mp4 10.00 s, 07.mp4 11.73 s, posters 06/07; seams checked. Desktop export 06/07 mp4 + posters overwritten.

## 2026-10-14 design — Korean clarity pass (copy.md) applied
- carousel.html ko: cover desc line 1 (이번 주에 공부한 걸로만), chips 04/05, 02 title + desc, 04 title + desc, 05 desc, 06 title, side index 02/04/06. English untouched. Every ko title and desc renders in 2 lines.
- Re-rendered HQ (two-loop raw take, loop 2 cut at `loopStarts` + 0.034 s, length = one measured period, CRF 12 BT.709, load < 8, one at a time): 01.png · 02.mp4 8.47 s · 04.mp4 7.97 s · 05.mp4 11.50 s · 06.mp4 9.93 s + posters 02/04/05/06 at the same moments (opened paper · right · explanation · rebuilt). Seams checked end → start. 03/07/08 untouched.
- Desktop export: 01.png, 02/04/05/06.mp4, posters 02/04/05/06 overwritten; captions.txt left as the lead updated it.

## 2026-10-14 design: English set rendered (?lang=en)
- carousel.html `EN` block brought in line with copy.md's English clarity pass (every en title, desc and cover chip; bold spans as copy.md's **…**). Korean untouched.
- Every en title and desc measured at 2 lines (DOM line count). App chrome checked in frames: English throughout (kit reads the page lang); sample coaching text shows its en version. Card 05's prompt stays Korean on purpose (it is the native sentence to translate; the item, not chrome).
- Renders (record.mjs HQ settings, two-loop take, loop 2 cut at `loopStarts` + 0.2 s, length = one measured period, one render at a time under caffeinate): 01.png · 02.mp4 8.47 s · 03.mp4 7.73 s · 04.mp4 7.97 s · 05.mp4 11.50 s · 06.mp4 9.97 s · 07.mp4 11.70 s · 08.png; posters 02–07 (07 on the settled result 6 of 7, A good week). Seams checked (start/end frames match the ko renders' start/end states); frames checked at start, thirds, end.
- Stored in renders/en/ (cards + posters/) and exported to ~/Desktop/nawana-carousel-06-weekly-test-en/ (cards in upload order + posters/); captions-en.txt untouched.
