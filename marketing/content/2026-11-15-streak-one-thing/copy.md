# 하루에 하나만 해도, 그날은 지켜져요 · copy (series 루틴 편, 6 cards)

Written 2026-11-15 from brief.md. Korean written as Korean, English as English; they agree in
meaning, not wording. 해요체 in descs and captions, no 당신, no em dash anywhere. The one message
on every card: 계획한 것 중 하나만 시작해도 그날은 지켜진다 → 스트릭이 이어진다. Honest edges:
"하나"는 **계획한 블록 중 하나**이고, 계획한 날에 아무것도 안 하면 그날은 여전히 끊겨요. 쉬는 날은
**아무것도 계획하지 않은 날**뿐이에요.

## For the designer

- **Titles:** 2 short lines (ko ~8 to 10 chars a line). Descs are 2 lines, one idea, at most one
  bold phrase. No pixel font anywhere — titles in a heavy sans.
- **App screens = `nw-routine` only** (the My routine page). No new screen, no invented state.
- **Card 3 (hero) needs a pose the kit doesn't have yet.** The message is "하나만 해도", so the
  still must show **ONE block with a green check (#34C759), today's circle filled (kept), and the
  flame lit (#FF8D28)** — the other blocks still open. `day-kept` shows every block finished, which
  reads as "do it all" and contradicts the card. This state is real in the app
  (`Entry.kept = touched >= 1`), so it is not a fake screen: add a `day-one` pose to `routine.js`.
  If it can't land, fall back to a `demo()` clip that stops at one block + kept, but the cover/grid
  still needs a static version. Flagged to design/web per the brief.
- **Card 4 draws the weekly circle strip** — green kept circles with a grey rest circle between
  them. The brief says `day-plan`/reset already draws this; no new state needed. Don't draw a
  skipped-but-planned day as a rest day — rest is only a day with nothing planned.
- **App labels stay the app's own** (from the kit): 나의 루틴 · 대화 10분 · 다시 말하기 · 주간 테스트 ·
  복습 20개 · 섀도잉 5문장 · 오늘 지키면 1일째 · N일째 지키는 중
  (en: My routine · Talk 10 min · Say it again · Weekly test · Review 20 items · Shadowing 5 lines ·
  Keep it today for day 1 · Kept for N days).
- **Every number on screen is kit sample data** (10분, 20개, N일째, 3일째). No title or desc
  restates them; they stay inside the pictured page and are never a user statistic.
- **The flame + "N일째 지키는 중" is the routine page's own streak** — the learner's personal
  promise, NOT the Core club. No seal, no rank, no badge anywhere in this piece.
- Colours: flame orange #FF8D28, kept check green #34C759 — app as it is.

---

## 01 · Cover: the one message, over the finished routine page
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 01 / 06
title (ko): 하루에 하나만 해도\n그날은 지켜져요
desc (ko):  바쁜 날, 통화 하나만 했어도\n**그날의 기록이 이어져요.**
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): nawana · Routine · 01 / 06
title (en): Do just one thing,\nthe day still counts
desc (en):  On a packed day, one call is enough\nto **keep your streak going.**
footer (en): Swipe → · nawana.app

screen: `nw-routine` pose `day-plan` (static) — the My routine page with blocks laid out, the week
circles and the flame. Works as a feed still.
alt (ko): ‘하루에 하나만 해도 그날은 지켜져요’ 아래 ‘바쁜 날, 통화 하나만 했어도 그날의 기록이 이어져요’가 있고, 통화·다시 말하기·주간 테스트·복습·섀도잉 블록과 주간 동그라미, 불꽃이 보이는 나의 루틴 페이지가 깔린 표지예요.
alt (en): Cover: "Do just one thing, the day still counts" over "On a packed day, one call is enough to keep your streak going." Below, the My routine page with its blocks, the week circles and the streak flame.

## 02 · This is your own routine, your promise to yourself
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 02 / 06
title (ko): 내가 짠 루틴,\n나와의 약속이에요
desc (ko):  온보딩에서 내가 고른 블록들이에요.\n앱이 시킨 게 아니라, 내가 정했어요.

eyebrow (en): nawana · Routine · 02 / 06
title (en): Your routine,\nyour own promise
desc (en):  The blocks you picked in onboarding.\nNot the app's rules, yours.

screen: `nw-routine` `day-plan`, MOTION = the block list reads down, then zoom in on the streak line
"N일째 지키는 중" / "Kept for N days" (kit sample N).
alt (ko): 나의 루틴 페이지에서 내가 고른 블록 목록이 보이고, ‘N일째 지키는 중’ 스트릭으로 줌인해요. (N은 샘플 숫자예요.)
alt (en): The My routine page shows the blocks you chose, then zooms in on the streak reading "Kept for N days." (N is sample data.)

## 03 · (hero) Start one block, the day turns green
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 03 / 06
title (ko): 하나만 시작하면\n그날은 초록불
desc (ko):  계획한 것 중 하나만 해도\n오늘 동그라미가 초록으로 차요.

eyebrow (en): nawana · Routine · 03 / 06
title (en): Start one block,\nthe day turns green
desc (en):  Do one of the things you planned,\nand today's circle fills green.

screen: `nw-routine` pose `day-one` (NEW — see For the designer): ONE block with a green check,
today's circle kept, the flame lit. The other blocks stay open.
sticker help: a small lit flame piece and one green check tile from the kit beside the phone, so the
"하나만" reads at a glance.
sticker tags:
  ko: 하나면 충분 ✓
  en: One is enough ✓
alt (ko): 나의 루틴 페이지에서 블록 하나에만 초록 체크가 뜨고, 오늘 동그라미가 초록으로 차며 불꽃이 켜져요. 나머지 블록은 아직 그대로예요. 옆에 작은 불꽃과 초록 체크 조각이 붙어 있어요.
alt (en): On the My routine page, just one block gets a green check, today's circle fills green and the flame lights, while the other blocks stay open. A small lit flame and a green check sit beside the phone.

## 04 · A day with nothing planned is a rest day
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 04 / 06
title (ko): 계획 없는 날은\n쉬어 가도 돼요
desc (ko):  아무것도 계획하지 않은 날은 쉬는 날이에요.\n**세지도, 끊기지도 않아요.**

eyebrow (en): nawana · Routine · 04 / 06
title (en): A blank day\nis a rest day
desc (en):  A day with nothing planned is a rest day.\n**It neither counts nor breaks.**

screen: `nw-routine` `day-plan` / reset, zoom on the weekly circle strip — green kept circles with a
grey rest circle between them. No new state needed.
alt (ko): 나의 루틴 페이지의 주간 동그라미 스트립을 확대해, 지킨 초록 동그라미들 사이에 쉬는 날 하루가 동그라미 없이 회색 날짜 숫자로만 보여요.
alt (en): A zoom on the weekly circle strip of the My routine page: green kept circles, and between them one plain grey date number with no circle, the rest day.

## 05 · So the flame keeps going
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 05 / 06
title (ko): 그래서 불꽃이\n계속 이어져요
desc (ko):  하루에 하나로도 충분해요.\n압박 없이 습관이 이어져요.

eyebrow (en): nawana · Routine · 05 / 06
title (en): So the flame\nkeeps going
desc (en):  One thing a day is enough.\nThe habit holds, no pressure.

screen: `nw-routine` pose `day-kept`, MOTION = the flame lights orange and the week run reads lit,
"N일째 지키는 중" / "Kept for N days" (kit sample N). Routine page only.
alt (ko): 나의 루틴 페이지에서 불꽃이 주황으로 켜지고 한 주의 동그라미가 이어져 ‘N일째 지키는 중’이 떠요. (N은 샘플 숫자예요.)
alt (en): On the My routine page the flame lights orange, the week's circles connect and the streak reads "Kept for N days." (N is sample data.)

## 06 · Outro (BRAND standard) + closing line above it
eyebrow: none (06 / 06 if the layout shows one)
closing (ko): 하루에 하나,\n그거면 돼요.
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app

closing (en): One thing a day\nis enough.
tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app

screen: `nw-futureself`, no phone.
alt (ko): ‘하루에 하나, 그거면 돼요.’ 아래 nawana 워드마크와 ‘유창한 나에게 언어를 배우세요.’, ‘첫 20분은 무료예요’, nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: "One thing a day is enough." above the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

출근길 통화 한 번. 그거면 오늘은 지켜졌어요.

나와나의 루틴은 내가 온보딩에서 직접 고른 블록들이에요. 그중 하나만 시작해도 오늘 동그라미가 초록으로 차고, 불꽃이 이어져요. 열 개를 다 못 해도 괜찮아요.

계획이 아예 없는 날은 쉬는 날이라, 세지도 끊기지도 않고요.

하루에 하나, 그거면 돼요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #루틴 #nawana

## Instagram caption (en)

One call on the way to work. That's enough to keep today.

Your nawana routine is the blocks you picked yourself in onboarding. Start just one of them and today's circle fills green, and the flame keeps going. You don't have to finish all ten.

And a day with nothing planned is a rest day, so it neither counts nor breaks.

One thing a day is enough.

Your first 20 minutes are free · link in bio

#languagelearning #learnenglish #speakingpractice #studyroutine #nawana

## Threads (ko) · a reply in the series thread

하루라도 빠지면 다 끊긴다는 압박 때문에 습관 앱을 지워 본 적 있다면.

나와나는 이번에 바를 낮췄어요. 내가 짠 루틴에서 하나만 시작해도 그날은 지켜져요. 출근길 통화 한 번이면 동그라미가 초록으로 차고 불꽃이 이어져요. 열 개를 다 못 해도 괜찮아요.

계획이 없는 날은 쉬는 날이라 세지도 끊기지도 않고요.

하루에 하나, 그거면 돼요.

(≈ 240자, no hashtags)

## Community series entry (new; the 루틴 스트릭 편)

cat: progress
ko: { title: "하나만 해도", tagline: "루틴에서 하나만 시작해도 그날의 기록이 이어져요" }
en: { title: "Just one thing", tagline: "Start one block from your routine and the day still counts" }

(Next free id after e19 — proposed e20, but the 2026-10-21 routine piece also proposed e20, so the
publisher assigns the actual id with the lead. Slides 720×900, ko/en title+tagline above. Mirrors
the IG carousel the same day.)

---

## Open questions (for the lead)

1. **Hero still is not in the kit.** Card 3 needs a `day-one` pose (one block green + today kept +
   flame lit) added to `routine.js` before this can be drawn as a still/cover. It's a real app state,
   not a fake screen. Design/web to add it, or we fall back to a motion clip (which still leaves the
   cover/grid without a static hero). This is the one blocking item.
2. **Community id/cat.** Proposed e20 / `progress`, but e20 is also proposed by the 2026-10-21
   routine piece. Publisher to confirm the real next id and whether this sits under `progress` or a
   new `routine` category, with the lead, before deploy.
3. **"하나" nuance.** Copy says "계획한 것 중 하나" / "one of the things you planned" so it never reads
   as "any day counts". A planned day with nothing started still breaks. Confirm the wording is
   strict enough for the reviewer.
4. **Rest day scope.** Card 4 is "아무것도 계획하지 않은 날" / "a day with nothing planned", never a
   planned day skipped. The screen draws a grey rest circle between kept ones. Confirm the still
   can't be misread as "skip a planned day for free".
5. **Sample N.** Cards 2 and 5 show the kit's "N일째 지키는 중" sample; alt text marks it as sample
   data. If the designer wants a concrete N drawn (e.g. 3), keep it clearly illustrative, not a stat.
6. **Streak ≠ Core.** This is the personal routine/promise streak only. No Core seal, rank or badge
   appears anywhere in the piece — flag if any sneaks into the render.
