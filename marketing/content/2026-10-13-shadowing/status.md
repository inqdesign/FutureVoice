# Series 02 · Shadowing (섀도잉)

- **Stage:** brief
- **Request (founder, 2026-10-13):** "다음 시리즈는 쉐도잉, 해보자." Series posts go on Threads as ONE thread (each new post a reply to the previous). "그다음도 너가 생각해서 만들어줘" — the lead plans and makes the following pieces.
- **Carry over from piece 01 (founder decisions):** light theme, kit screens only, wordmark in Pixelify Sans, eyebrow "nawana · NN / total", cover = a problem in the founder's own words → the answer; ONE story across the cards (one talk, one line); the comparison is AI tutor vs my own voice; no em dash; 입이 안 떨어져요 (not 말이); captions + Threads + Desktop export folder for manual upload; audio where it proves the point.

## 2026-10-14 design — silent set rendered (founder: "소리 없이 먼저 만들어")
- carousel.html: piece 01's card system (fixed text block, light, #0A5CF5, Pixelify wordmark, eyebrow "nawana · NN / 08", same outro), copy.md as written. Cover title at 96px (110px wrapped line 2, "연기하는 것 같아요"); every title and desc 2 lines (ko, rendered). No em dash on any card.
- "소리 켜고 들어 보세요" / "Sound on for card 6": NOT on card 06 and cut from the captions and the Threads text. **Restore both when audio lands.**
- Kit: `<nw-shadow>` line/take API (sh.line, sh.take, playTarget, record, showResult, both, loop) and `<nw-bookpage>` shadowTake. The review kit still hands its book a ONE-row Shadow chapter; the carousel sets the two sentence rows itself (`book()`), mkt-web to fix `review.js` TALK.shadow.
- Camera: during the take (04, 07), the loop (05), the target playing (03) and the duet (06) the phone steps back (scale .76, pan 150) so the line and the bottom bar (red mic / track) are in view together; a pan alone showed only the red mic under empty white.
- Sample data: the line "You clearly took the initiative and prioritized what mattered." with assumed word times (4.30 s of speech, track 4.44 s, ≈4.5 s at 0.9); take 72 (heard "…prioritize what matter", rhythm 64, late dots on the last three words, 5.0 s / 1.19x); retake 86 (rhythm 81, 4.6 s). When Audio A lands, replace TIMES in carousel.html with its word timestamps and re-render.
- **Audio onsets (seconds from the start of each MP4; the file's voice should begin here):**
  - 03 Audio A (target): playback starts 2.37, first word lit 2.49 (= +0.12, TIMES[0]); line ends ~6.8.
  - 04 Audio B (learner's take): countdown 1.11, red mic 3.06, first word lit 3.20 (karaoke on the learner's clock = TIMES × 1.19); take ends ~8.2, result 9.69.
  - 06 Audio C (duet, both trimmed to the first word): first word lit 1.79 (the voice starts here, no lead), ends ~6.1.
  - 07 Audio B2 (retake, optional): red mic 2.76, first word 2.89 (TIMES × 1.10); result 9.02.
  - 02 and 05 silent.
- renders/ (two-loop recording, second loop cut at the page's own loop timestamps; frames checked at 6 points per MP4; each ends where the next loop starts, hard cut back to the opening state on 04/05/06/07):
  01.png · 02.mp4 8.20 s · 03.mp4 9.33 s · 04.mp4 13.30 s · 05.mp4 15.30 s · 06.mp4 9.20 s · 07.mp4 15.43 s · 08.png
  posters 02 Shadow chapter (two rows) · 03 karaoke mid-line + playhead · 04 result 72 (diff + heard) · 05 dots + "prioritized what mattered" picked · 06 duet playing · 07 row checked 86, ribbon 1/2.
- Exported to ~/Desktop/nawana-carousel-02-shadowing/ (01.png, 02–07.mp4, 08.png, posters/, captions.txt). Not yet reviewed.

## 2026-10-14 design — review FIX 1–4 + HQ re-render (all cards, after the kit's shadow highlight fix)
- Copy (carousel.html, copy.md, Desktop captions.txt): 07 "80점 이상이면 / 80점 이상이 나오면", IG + Threads "80점 이상이면…"; 03 desc + IG "나도 닿을 수 있는 목표로 들려요".
- Nav bar never cut by the top fade: result camera now z .9 / pan 65, wide camera z .72 / pan 48; the shadow screen's nav bar and the "8/9 64" row are fully in view on 03–07.
- Every MP4 is cut 0.034 s after the loop start (one frame), so no card opens on the previous loop's last frame (04 opened on the 72 result). **Audio onsets in the section above move 0.03 s earlier**: 03 A first word 2.45 · 04 B red mic 3.03, first word 3.17 · 06 C 1.75 · 07 B2 red mic 2.73, first word 2.86.
- Re-rendered ALL cards with the HQ record.mjs (2× supersample, BT.709, CRF 12; the MP4s via a lossless two-loop take cut at CRF 12 with the same flags), after web/kit/screens/shadow.js's highlight change (semibold, translucent grey upcoming words). Rendered with the machine's load under 8 (an earlier pass under load ~60 dropped frames and was discarded).
- renders/: 01.png · 02.mp4 8.20 s · 03.mp4 9.30 · 04.mp4 13.27 · 05.mp4 15.30 · 06.mp4 9.17 · 07.mp4 15.43 · 08.png + posters 02–07. Desktop export overwritten (cards, posters, captions.txt).

## 2026-10-14 design — loop tiles (kit shadow.js: the selected range wears light-blue tiles)
- carousel.html never cleared the selection, so the kit's tiles show as the app draws them. One workaround: on 07 the kit's `take` setter rebuilds a graded line's words without their tiles (`_fill` → `_words`), so the carousel re-selects the whole line before the retake (mkt-web: keep `sel` in `_fill`).
- ALL cards re-rendered HQ (two-loop cut, load < 8), tiles checked in frames on 03–07: 02 8.17 s · 03 9.30 · 04 13.23 · 05 15.27 · 06 9.20 · 07 15.40 + 01/08 + posters. Audio onsets unchanged. Desktop export overwritten (cards + posters).

## 2026-10-14 design — Korean clarity pass (copy.md) applied
- carousel.html ko: cover chips 02/05/06/07, 03 desc, 04 title + desc, 06 title + desc, 07 desc, side index 04/06. English untouched. Every ko title and desc renders in 2 lines (07 desc line 1 is the longest, fits).
- Re-rendered HQ (two-loop raw take, loop 2 cut at `loopStarts` + 0.034 s, CRF 12 BT.709, load < 8, one at a time): 01.png · 03.mp4 9.33 s · 04.mp4 13.30 s · 06.mp4 9.23 s · 07.mp4 15.40 s + posters 03/04/06/07 (07 = row checked 86, ribbon 1/2). Seams and frames checked. Audio onsets unchanged. 02/05/08 untouched.
- Desktop export: 01.png, 03/04/06/07.mp4, posters 03/04/06/07 overwritten; captions.txt left as the lead updated it.

## 2026-10-14 design — English set (`?lang=en`)
- carousel.html en per copy.md English clarity pass (cover desc line 2 + chips 05–07, desc 02/03, 04 title + desc, 06 title + desc, 07 title + desc). en cover "Copying someone else" wrapped at 96 px → en-only override 84 px. Every en title/desc 2 lines; kit screens English.
- renders-en/ (HQ, loop 2 cut at loopStarts + 0.034 s, silent): 01.png · 02.mp4 8.23 s · 03 9.33 · 04 13.29 · 05 15.32 · 06 9.23 · 07 15.43 · 08.png + posters 02 Shadow chapter · 03 karaoke · 04 result 72 · 05 dots + phrase loop 0.5× · 06 duet · 07 row checked 86 (1/2). Cadence ≈ ko (05 re-rendered once).
- Exported to ~/Desktop/nawana-carousel-02-shadowing-en/ (cards + posters/); captions-en.txt untouched.
