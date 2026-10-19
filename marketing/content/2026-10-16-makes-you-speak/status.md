# Series · 말을 무조건 하게 만드는 앱 (makes you speak)

- **Stage:** brief written (strategist, 2026-10-16) → copy
- **Request (founder, 2026-10-16):** "마케팅 비디오 시리즈로, 이걸 하나 만들어줘. 말을 무조건 하게 만드는 앱 나와나. 1. 자유대화 2. 쉐도잉 3. 다시 말하기 4. 스피치. 이 네가지가 묶음으로 카드를 만들어서 해보자. 이전 카드는 헤더 폰트가 너무 컸어. 자유대화에서는 1-0. 프리토킹 (어드밴스드 유저) 1-1. 코치 모드 (비긴너) 2. 쉐도잉 3. 다시 말하기 4. 스피치."
- **Fixed by the founder:** the one message ("nawana makes you speak, no matter what"); five feature cards in this order: free talk (advanced) · coach mode (beginner) · shadowing · say it again · speech. One carousel (bundle), video cards.
- **Design constraint:** card titles were too big in pieces 01–02 (.ttl 72px, cover 96–110px). Go clearly smaller.
- **Owner:** lead. First pass requested ("일단 한번 작업해줄 수 있을까?").
- **Open questions:** —

## Log
- design (2026-10-16), silent, ko renders: `carousel.html` on the 02/03 card system (light, #0A5CF5, Pixelify wordmark, eyebrow "nawana · NN / 07", same outro + copy.md's closing line above it). Smaller type per founder: card titles 54px/66 (was 72/88), cover 76px/96 (en 72), descs 29px/42 (en 28), mode label (1-0 · 1-1 · 2 · 3 · 4) as a 30px blue line above each title; the window onto the app now starts at 420 (was 470). Copy verbatim from copy.md, ko + `?lang=en`; every title and desc is 2 lines in both (en checked as stills).
- Scenes (kit only): 02 `nw-call` plain (question laid → long answer → follow-up on their project) · 03 `nw-call` coach (two lines laid → question → 이렇게 말해 보세요 + gloss + 써 볼 단어 · prepared → learner's own line → 썼어요 ✓ → turn sent; the learner's part is the kit's faded underline, no sticker) · 04 `nw-shadow` target with karaoke → 3·2·1 → take (compressed ×1.4) → 72 + 들린 내용 · 05 `nw-sayagain sample="interview"` read "went" → 92 → the call's answer → next fixed line · 06 `nw-speech` own script (mkt-web's new `script` API) 면접 자기소개 / Interview intro → prompter → 86 → five rows.
- renders/: 01.png · 02.mp4 11.0 s · 03.mp4 11.0 s · 04.mp4 13.6 s · 05.mp4 10.5 s · 06.mp4 12.5 s · 07.png, posters 02–06 (.png). Each MP4 is one loop recorded from the start of loop 2. Not exported to Desktop yet.
- design round 2 (2026-10-16), review.md FIX items 1, 3–7, 10:
  - 1: card 06 resets and settles the Speech screen before each loop, so frame 0 is the 스피치 list with 면접 자기소개 (no leftover challenge result, no gauge at 0).
  - 3: the final pan on 06 is now 280, so the whole fifth row fits. 2 (kit): the gauge reads 86 in green.
  - 4–5: card 04 runs at full size (pan 150, scale 1) during playback and the take, then steps back to .9 for the result. The take is compressed ×1.7, the result holds ~2.3 s, and the closing re-zoom is gone. 12.0 s. The red record button sits below the window during the take; the 3·2·1 and the karaoke are on screen.
  - 6: cards 02 and 03 finish the laid lines' entry animations and the feed's move before frame 0, so the layout opens settled.
  - 7: the kit now labels the fluent self "미래의 나" on ko (en stays "Future self"); no explicit label is set on the cards.
  - Cover: the futureself and chips moved up 80 px (review suggestion).
  - All MP4s are recorded from loop 2's start + 0.15 s, one loop long.
- ko re-rendered: 01.png · 02.mp4 11.0 s · 03.mp4 11.0 s · 04.mp4 12.0 s · 06.mp4 12.5 s + posters 02 · 03 · 04 · 06. Unchanged: 05.mp4 10.5 s · 05.png · 07.png.
- en rendered (renders/en/): 01.png · 02.mp4 11.0 · 03.mp4 11.0 · 04.mp4 12.0 · 05.mp4 10.5 · 06.mp4 12.5 · 07.png + posters 02–06.
- Frames checked: 0, 0.3 s, 30/55/80 %, end for every MP4, ko and en; 04 also at 5.2 to 11.5 s.

## 2026-10-16 lead — review PASS (round 2), shown to founder
- Artifact (live carousel): https://claude.ai/artifact/CAm1aYPGuvia9bqsKcSsbM
- Stage: founder review. Waiting for approval or changes. Not exported to Desktop, not posted.
