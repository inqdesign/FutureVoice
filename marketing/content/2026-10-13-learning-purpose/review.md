# Review — 왜 배워요 (learning-purpose) — 2026-10-13

Verdict (round 2): FIX (1 item)
Verdict (round 1): FIX (3 items) — all three resolved, see below.

App: 1.1.8 build 95 · feature `feat/learning-purpose` (merge b222bcce). Round 2 re-reviewed
copy.md, carousel.html, and the re-rendered 01/02/03/05 stills + 03/05 MP4s (04/06 unchanged),
against BRAND.md, CHANNELS.md, brief.md.

## Round-2 FIX

1. [fidelity|visual] cards 03 & 05 (feature MP4s) — designer —
   The re-rendered `03.mp4` and `05.mp4` now OPEN on the un-panned Talk-tab header and hold it
   ~0.3–0.4 s before panning up — and because the clips loop, this recurs at every loop restart.
   What that opening frame shows is a state the app never produces: the **뉴스 (News) chip is
   highlighted as the active chip**, with the PURPOSE list beneath it — interview questions
   (자기소개 해 주세요 · 상대: 면접관 …) under News in 03, travel situations (체크인 카운터에서 ·
   상대: 항공사 직원 …) under News in 05. In the real app the News chip lists news headlines; the
   purpose topics live under an Interview/면접 (or Travel/여행) chip the kit can't draw, which is
   exactly why the whole chip row was supposed to stay cropped above the mask (brief Showability
   2(b), Facts #2; round-1 "verified clean" rested on it).
   This is a REGRESSION from round 1: the unchanged `04.mp4` still opens already-panned (cropped,
   no chip row) at t=0, and the 03/05 PNG stills are correctly cropped too — only the two
   re-rendered MP4s regressed. Fix: re-render 03.mp4 / 05.mp4 so the phone is panned to the
   resting LIST position on the FIRST recorded frame (match 04.mp4 and the stills — apply the
   instant pan-to-LIST before frame 0 / before record.mjs starts capturing), so the 뉴스 chip row
   never appears and the loop restarts seamlessly.
   (No real-data concern: even with the header showing, the phone is scrolled past the top app
   header, so no avatar, greeting or name is exposed.)

## Round-1 items — all resolved

1. [fidelity] Korean topic titles — RESOLVED. Cards 03 & 05 now render the exact ko catalog
   titles paired with their Korean captions: 03 = 자기소개 해 주세요 / 지원 동기 / 강점과 약점 /
   자랑하고 싶은 프로젝트 / 연봉 이야기 (상대: 면접관 · 채용 담당자); 05 = 체크인 카운터에서 /
   문제가 생겼을 때 / 호텔에서 / 기차역에서 / 길에서 (상대: 항공사 직원 · 프런트 직원 · 매표소
   직원 · 지나가는 사람). Card 01 faint bg shows Korean rows (자랑하고 싶은 프로젝트 / 연봉 이야기).
   Card 04 (exam) correctly stays English title + English "IELTS · Part N" caption. No row
   anywhere shows an English title with a Korean caption. `T(ko,en)` in carousel.html drives the
   interview/travel titles in ko; exam list is bare English literals.

2. [truth] IG caption — RESOLVED. The false "주제는 영어로, 설명은 한국어로" line is gone;
   copy.md now reads "화면은 한국어로, 대화는 배우는 언어로." — true to the app (chrome Korean,
   material in the target language). The old line survives only in this review's round-1 text and
   in brief.md's facts list, not in copy.md.

3. [voice] em dashes in posted copy — RESOLVED. IG caption (copy.md: 공항·호텔이요. 통화 첫
   화면이…, comma/period now), Threads (면접·시험·여행, 셋 중 뭐예요?, comma now) and EN card 02
   desc (carousel.html:188 "…your're learning. One reason or a few, your call.", period now) are
   all de-dashed. Remaining "—" sit only in the HTML `<title>` / side-panel `<h1>` (hidden under
   `html.solo` when record.mjs captures — not rendered, not posted) and in code comments / md
   section headers — not posted copy. Non-blocking.

## Re-confirmed clean (no regression)

- Exam = practice, never scoring: card 04 + caption + Threads say only 연습 / "Practise … out
  loud". No score/grade/점수. Exam name is real (IELTS).
- One-or-many + editable: card 02 + caption "하나만 골라도, 여러 개 골라도 돼요. 나중에 바꿔도
  되고요." Not "pick one, done."
- "첫 20분은 무료예요" / "Your first 20 minutes are free" (card 06 + caption) = `freeGrantSeconds`
  1200 s = 20 min. No "무료 체험" / "free trial" anywhere (no trial exists).
- No real names/data on screen: headers cropped on the stills; even on the regressed MP4 opening
  the top app header (avatar/greeting/name) is scrolled out of the window. No prices, no stats.
- Cards 01, 02, 04, 06: clean — no overflow/clipping, titles ≤ 2 lines, grid + ink + app blue
  #0A5CF5 palette only, mosaic clipped in the outro pill, numbering 01–06 consistent.
- Channel fit unchanged: 6×1080×1350; 03/05 MP4s 8 s (≤ 60 s); caption < 2,200 with 5 hashtags;
  Threads < 500.

## Suggestions (non-blocking)

- When re-rendering 03/05, the near-static read noted in round 1 could be improved in the same
  pass (a clearer row-tap landing or a short scroll), but it does not block on its own.
- Card 01 "네 이야기" register wobble vs 해요체 — optional.

Checked frames: renders/03.mp4 @0s 0.5s 1.2s 3.5s 6.5s · renders/05.mp4 @0s 3.5s 6.5s ·
renders/04.mp4 @0s (control, cropped/clean) · stills 01.png 02.png 03.png 04.png 05.png 06.png
