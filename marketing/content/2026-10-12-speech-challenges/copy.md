# 같은 원고, 하나의 순위표 — copy (speech challenges, 6 cards)

Autopilot run for 1.1.8 (93). The one message: **모두 같은 원고를 읽고 점수로 겨뤄요 — 카메라 켠
기록만, 순위엔 이름과 점수만.** Every card traces to it. Each card was written in Korean first and
then separately in English, not translated. Script/UI lines on screen stay English (the kit's own
sample, "Why practise out loud?"); every label and description around them is 해요체. Never "당신".

Length target (matching the approved sibling pieces): ko descriptions ~40–58 characters, en ~90–140
characters, 2 lines on the render. Titles 2 lines, ~8–10 characters a line.

**For the designer (screens + beats per brief):**
- Eyebrow number → `NN / 06` (01 / 06 … 06 / 06).
- Cover (01): `nw-speech` default `list` state (= `build()`: "챌린지" 섹션 · "41명 도전 중" · 상단
  3명 이니셜 얼굴 · 샘플 챌린지 행). Must hold as a still in the grid. No price, no outro line here.
- Cards 02–05: `nw-speech` as 8–12 s MP4 loops.
  - **02:** `open`→`prompter` (or `demo()`): the prompter scrolls a line at a time. Sample script
    "Why practise out loud?". Do NOT run into the score here.
  - **03 (privacy):** the challenge flow with the **camNote visible** on the prompter — camera OFF,
    challenge mode, so the micb note reads "카메라를 켜야 순위에 올라가요. 영상은 내 폰에만 남아요.",
    then `camera(true)` flips the camera ON. The note IS the privacy line — no extra sticker.
  - **04:** `result(81)` — the gauge counts 0→81 (orange, under 85, honest), the coach line
    ("Steady and clear…") and the 5-row "측정 결과" (94% · 148 words/min …). The gauge may be lifted
    as a sticker. NEVER present 81/94%/148 as a user's real result (brief fact 10).
  - **05 (payoff):** `rankUp(14, 8)` — the SpeechChallengeMomentSheet rises (green arrow · "14위 → 8위"
    · 순위 행 이름+점수+"나"). Keep the rank-up for the end only; don't fire it mid-carousel.
- Outro (06): the fixed series outro — Futureself pill speaking (clipped, light), wordmark, one offer
  line, nawana.app. No plan prices.
- **Risk 1 (founder name):** the fidelity capture `speech-challenge.png` has the real name "Eunggyu"
  on a leaderboard row. Every render MUST use kit sample names (Camille · Yuna · Minji · Jiwoo), never
  that capture image, and never the `challenge` "1위" podium unless its name renders as a kit sample.
- Numbers/names on every screen are kit sample data (brief fact 10). Futureself mosaic clipped inside
  the pill only. Board = top 10 + your own row (brief fact 8) — don't render a full ranking.

---

## 01 — Cover: the board exists now (list state, 41명 도전 중)
eyebrow (ko): 스피치 챌린지 · 01 / 06
title (ko): 같은 원고,\n하나의 순위표
desc (ko):  같은 언어를 배우는 사람들이\n같은 원고를 읽고 **점수로 겨뤄요.**
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): Speech challenges · 01 / 06
title (en): Same script,\none board
desc (en):  Everyone learning your language reads\nthe same script and **races on score.**
footer (en): Swipe → · nawana.app

screen: `nw-speech` default `list` (챌린지 섹션 · 41명 도전 중 · 상단 3명 얼굴 · 샘플 챌린지 행)
alt (ko): Speech 탭의 챌린지 순위표 표지예요. "41명 도전 중"과 상위 참가자들이 보여요. 숫자와 이름은 샘플이에요.
alt (en): Cover: the Speech tab's challenge board, "41 competing" and the top entrants. The numbers and names are kit samples.

## 02 — 같은 원고를, 다 같이 (prompter, no levels)
eyebrow (ko): 스피치 챌린지 · 02 / 06
title (ko): 레벨 구분 없이\n모두 한 보드
title (en): No levels,\none board
desc (ko):  공개된 같은 원고를 프롬프터로 읽어요.\n레벨 나눔 없이 **모두 한 보드**에서요.
desc (en):  Read the same public script on a prompter.\nNo levels, **everyone on one board.**

eyebrow (en): Speech challenges · 02 / 06

screen: `nw-speech` `open`→`prompter` (the prompter scrolls, sample script)
material on screen (stays English): script title "Why practise out loud?"
alt (ko): 프롬프터에 공개된 같은 원고 "Why practise out loud?"가 한 줄씩 올라와요. 레벨 구분 없이 모두 같은 원고를 읽어요.
alt (en): The prompter scrolls the same public script, "Why practise out loud?". No levels — everyone reads the same one.

## 03 — 카메라 켜고 읽으면 순위에 (privacy)
eyebrow (ko): 스피치 챌린지 · 03 / 06
title (ko): 카메라 켜고\n읽으면 순위에
title (en): Camera on,\nyou're on the board
desc (ko):  카메라 켜고 읽은 기록만 순위에 올라가요.\n폰을 떠나는 건 **이름과 점수뿐**이에요.
desc (en):  Only camera-on takes join the board.\nJust a **name and a score** leave the phone.

eyebrow (en): Speech challenges · 03 / 06

screen: `nw-speech` challenge flow, camNote visible → `camera(true)`
material on screen (note around the material, in ko on the ko render):
- camNote (ko): "카메라를 켜야 순위에 올라가요. 영상은 내 폰에만 남아요."
- camNote (en): "Turn the camera on to join the board. Your video stays on this phone."
alt (ko): 챌린지 모드에서 "카메라를 켜야 순위에 올라가요. 영상은 내 폰에만 남아요." 안내가 뜨고, 카메라를 켜면 촬영이 시작돼요.
alt (en): In challenge mode a note reads "Turn the camera on to join the board. Your video stays on this phone.", then the camera turns on.

## 04 — 점수는 앱이 매겨요
eyebrow (ko): 스피치 챌린지 · 04 / 06
title (ko): 읽자마자\n점수가 나와요
title (en): Read, and\nyou're scored
desc (ko):  정확도·속도·쉼·군말·목소리 안정감을\n**앱이 바로** 채점해요.
desc (en):  Accuracy, pace, pauses, fillers, steadiness —\n**the app scores** all five, right away.

eyebrow (en): Speech challenges · 04 / 06

screen: `nw-speech` `result(81)` (게이지 0→81, 주황 · 코치 한 줄 · 측정 결과 5행)
material on screen (stays English): coach line "Steady and clear…" · 94% · 148 words/min
sticker (optional): the score gauge (81) may be lifted out
alt (ko): 읽자마자 점수 게이지가 81점(주황)까지 차오르고, 정확도 94%·148 words/min 같은 다섯 항목이 나와요. 숫자는 샘플이에요.
alt (en): The moment you finish, the score gauge fills to 81 (orange) and five rows appear — 94%, 148 words/min and more. The numbers are kit samples.

## 05 — 순위를 올려요 (payoff)
eyebrow (ko): 스피치 챌린지 · 05 / 06
title (ko): 가장 잘한 기록이\n순위를 올려요
title (en): Your best take\nclimbs the board
desc (ko):  제일 잘한 기록이 보드에 올라가 순위가 바뀌어요.\n**상위 10명과 내 줄**이 보여요.
desc (en):  Your best take moves up and your rank changes.\nYou see the **top 10 and your own row.**

eyebrow (en): Speech challenges · 05 / 06

screen: `nw-speech` `rankUp(14, 8)` (SpeechChallengeMomentSheet: 초록 화살표 · "14위 → 8위" · 순위 행)
material on screen (kit sample names only): Camille · Yuna · Minji · Jiwoo · "나"
alt (ko): 가장 잘한 기록이 올라가 "14위 → 8위"로 순위가 바뀌고, 상위 참가자들과 내 줄이 나란히 보여요. 이름과 숫자는 샘플이에요.
alt (en): Your best take lifts you from 14th to 8th; the top entrants and your own row sit together. The names and numbers are kit samples.

## 06 — Outro
eyebrow: none (06 / 06 if the layout shows one)
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app

tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app

screen: `nw-futureself` (speaking), no phone
alt (ko): nawana 워드마크 아래 "유창한 나에게 언어를 배우세요.", "첫 20분은 무료예요", nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

같은 원고를 읽고, 점수로 겨뤄요.

혼자 하던 말하기 연습에 순위표가 생겼어요.
같은 언어를 배우는 사람들이 같은 원고를 프롬프터로 읽어요.
레벨 나눔 없이 모두 한 보드에서요.

카메라 켜고 읽으면 순위에 올라가요.
폰을 떠나는 건 이름과 점수뿐이에요. 영상은 내 폰에만 남아요.

정확도·속도·쉼·군말·목소리 안정감을 앱이 바로 채점하고,
가장 잘한 기록이 보드에 올라가요. 여러 번 다시 도전해도 돼요.

첫 챌린지는 바로 열려 있어요. 몇 점 나올 것 같아요?

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #발음 #nawana

(≈ 300 chars)

## Instagram caption (en)

Read the same script, and race on score.

Solo speaking practice just got a leaderboard.
Everyone learning your language reads the same script on a prompter —
no levels, everyone on one board.

Read with the camera on and you're on the board.
Only a name and a score leave the phone; your video stays on it.

The app scores five things right away — accuracy, pace, pauses, fillers, steadiness —
and your best take is the one that climbs. Retry as many times as you like.

The first challenge is already open. What do you think you'd score?

Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #languagelearning #pronunciation #nawana

(≈ 560 chars)

## Threads (ko)

혼자 하던 말하기 연습에 순위표가 생겼어요.

같은 언어를 배우는 사람들이 같은 원고를 읽고 점수로 겨뤄요. 레벨 구분은 없어요. 카메라 켜고 읽으면 순위에 올라가고, 폰을 떠나는 건 이름과 점수뿐이에요.

첫 챌린지는 바로 열려 있어요. 몇 점 나올 것 같아요?

첫 20분은 무료예요. nawana.app

(≈ 155 chars)

## Threads (en)

Solo speaking practice just got a leaderboard.

Everyone learning the same language reads the same script and competes on score. No levels. Read with the camera on to join the board — and only a name and a score ever leave your phone.

The first one's already open. What do you think you'd score?

Your first 20 minutes are free. nawana.app

(≈ 330 chars)

## Community series entry

cat: practice. New episode, distinct from `2026-10-11-what-you-can-do` (which deferred Speech +
challenges to a separate episode — this is it). Next free id after e19 is **e20** (confirm with lead).

ko: { title: "스피치 챌린지", tagline: "같은 원고를 읽고 점수로 겨뤄요" }
en: { title: "Speech challenges", tagline: "Everyone reads the same script and races on score" }

---

## Open questions (for the lead)

1. **Founder-name leak (brief risk 1).** My copy never names a person, but the render must use kit
   sample names (Camille · Yuna · Minji · Jiwoo) and must NOT reuse `speech-challenge.png`, which has
   the real name "Eunggyu" on a row. Card 05 uses `rankUp` for this reason — confirm the recorded loop
   shows only kit samples, and avoid the `challenge` "1위" podium unless its name renders as a sample.
2. **Series id.** Entry written as e20 (`cat: practice`). Confirm the id, or map it if the board order
   should differ. Adding it to `series.json` changes the live site → founder approval.
3. **"첫 20분은 무료예요" (brief fact 11).** Re-confirm `freeGrantSeconds` = 1200 on the post date. No
   "무료 체험 / free trial" anywhere (there is no trial).
4. **Kit poses on card 03.** The privacy line is carried by the kit's own camNote; confirm the kit
   draws the camera-OFF challenge note in Korean on the ko render, then flips to camera ON.
5. **Numbers stay samples (brief fact 10).** 81 / 94% / 148 wpm / "41명 도전 중" are illustrative; the
   captions and alt text say so. Confirm no slide presents them as a real user's result.
6. **Captions + Threads need approval** before posting (nawana never posts without the founder's OK).
   All well under limits (IG en ≈ 560, Threads en ≈ 330).
