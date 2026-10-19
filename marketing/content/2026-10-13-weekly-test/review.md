# Review: series 06 · 주간 테스트 (weekly test), 2026-10-14
Verdict: FIX

The renders, the layout and nearly every claim hold. Four text fixes are needed, all in copy.md, captions.txt or the en text block. No re-render is needed except for fix 3.

1. [truth] Threads (copy.md + ~/Desktop/nawana-carousel-06-weekly-test/captions.txt), paragraph 2:
   "지난번 단어장에 모인 단어, 유창한 내가 쓴 표현이 문제로 나와요."
   The word items are dealt from the week's talk BOOKS' Words chapter (`WeeklyTestEngine`, CLAUDE.md "Word items come from the week's talk BOOKS only"), not from the notebook. Card 03 and the IG caption already say 교재, so the Threads post shouldn't say something different. "지난번 단어장" also reads as "last time's notebook".
   → "이번 주 통화 교재의 단어, 유창한 내가 쓴 표현이 문제로 나와요."
2. [voice] IG caption (en), line 3 (copy.md + captions.txt):
   "Words from this week's call books, and phrases the fluent you used, with the blanks to fill."
   The phrase "with the blanks to fill" dangles; the sentence doesn't read as native.
   → "Words from this week's call books, and phrases the fluent you used, each with a blank to fill."
3. [voice] card 06 desc (ko) (copy.md + carousel.html, then re-record 06):
   "이번 주 유창한 내가 한 말을 …" reads as "this week's fluent me".
   → "이번 주에 유창한 내가 한 말을 **글자 없이 듣고**, 단어 카드를 순서대로 놓아요."
   (It still fits on 1 line at the current width. If it wraps, it's still within 2 lines.)
4. [voice] card 03 desc (en) (copy.md + carousel.html `?lang=en`):
   "They come from **this week's call books**, the ones you haven't mastered first." Here "the ones" points at the books, not the words.
   → "They come from **this week's call books**, words you haven't mastered first."

## Checked and fine
- **Truth:**
  - The kinds shown (meaning, gap, translate, listen) are all dealt today.
  - Nothing shows build, rewrite, a monthly test, a flame, a gauge, confetti, "AI가 채점", or a level test.
  - Card 02: the door is the Review header face with its dot, and it opens at the day and time the learner set. There is no "매주 토요일".
  - Card 03: 교재 words, unmastered first.
  - Card 04: the To-study phrase sits in the fluent self's line.
  - Card 07:
    - "6 / 7" is sample data.
    - The missed row for a gap item shows only the answer, the same as `WeeklyTestView`'s missed list.
    - The footer is the app's own string: "이것들은 복습으로 돌아가서 지금 바로 나와요."
    - The retake carries the app's "다시" capsule (catalog ko of "Again") on the next paper, 1/8.
  - The outro shows 20 free minutes, which matches BRAND.
- **The translate placeholder** fits how the engine works:
  - The prompt is a casual native sentence on the learner's topic ("어제 면접관이 다시 전화했어.") with a one-wording answer.
  - The decoys "call" / "calls" are single words built from the learner's tense slip. They are left in the tray.
  - After the answer, the screen shows the point (과거 시제), its tip, and 지난번엔 이렇게 말했어요 "it go really well → it went really well". That is the same slip as piece 01 card 03, so it's one story.
  - "힌트 보기", "Last time you said" and the trap-word footer all exist in `WeeklyTestView`.
- **Voice:**
  - The Korean uses 해요체 throughout, with no 당신.
  - None of our text has an em dash. The "—" hits in carousel.html are code comments plus a runtime replace on kit text.
  - Titles are positive-first.
- **Visual:**
  - Every title is 2 lines and every desc is 1–2 lines. Nothing overflows.
  - The eyebrow reads 02/08 … 07/08 in the right order.
  - Light palette, kit screens only, and the mosaic is not used as a background.
  - The first frames are fresh and fully drawn (not blank or half-faded).
  - Seams: 02–06 end on their start state. 07 cuts from the answered retake back to the result, which reads as a scene restart.
- **Channel:**
  - Every card is 1080×1350, H.264 at 30 fps. Clips run 7.7–11.6 s, all ≤ 60 s.
  - 06.mp4 has no audio stream. That's correct for the silent build.
  - Threads is 265 chars (≤ 500), posted as a reply under 05 (words), with no hashtags.
  - The IG caption is 270 chars with 5 hashtags.
  - The exported captions say nothing about sound.
- **Safety:** no real user's name or data, no testimonials.

## Suggestions (don't block)
- copy.md still carries "6번째 장은 소리 켜고 들어 보세요." / "Sound on for card 6." and card 06's hint. The export dropped them correctly. Mark them "(only once Audio A is in)" in copy.md so a repackage from copy.md can't put them back while the build is silent.
- Card 07's payoff, the "다시" capsule, is about 8 pt at feed size. A short push-in on the caption line when the retake opens would make it readable. Card 05's "it go → it went" line has the same issue.
- Cards 03 and 04 pan down to the answer, so the host's happy face is out of frame at the moment of "정답". The brief wanted it seen. Optional.
- Before posting, swap the translate item for real engine output, as status.md already notes.

Checked frames:
- renders/02.mp4 @0 2.57 5.14 7.71 end
- renders/03.mp4 @0 2.32 4.64 6.96 end
- renders/04.mp4 @0 2.39 4.78 7.17 end
- renders/05.mp4 @0 3.49 6.98 10.47 end, plus full-res crops @7.5 (explanation, tiles)
- renders/06.mp4 @0 3 6 9 end
- renders/07.mp4 @0 3.01 6.02 9.03 end, plus full-res crop @6.5 (다시 badge)
- 01.png and 08.png size-checked
