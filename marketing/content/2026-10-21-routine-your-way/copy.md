# 루틴은 내가 만든다 · copy (series 루틴 편, 6 cards)

Written 2026-10-21 from brief.md. Korean written as Korean, English as English; they agree in
meaning, not wording. 해요체 in descs and captions, no 당신, no em dash anywhere. The one message
on every card: 내가 고른다 → 내 루틴이 된다.

## For the designer

- **Titles:** 2 short lines (ko ~4 to 8 chars a line). Descs are 2 lines, one idea, at most one
  bold phrase. The cover's pixel title is the campaign line exactly as the brief set it:
  `루틴은 내가 만든다` (a slogan, not 해요체 by design).
- **App screens = `routine.js` only** (the My routine page). The onboarding card-by-card builder
  has no capture, so it is NEVER drawn. The "고른다 → 담긴다" idea lives in the COPY and the motion;
  the screen shows the DESTINATION.
- **Listening and speech are copy-only.** `routine.js` draws five kind tiles and no more:
  통화(파랑 #0088FF) · 다시 말하기(민트 #00C3D0) · 주간 테스트(주황 #FF8D28) · 복습(초록 #34C759) ·
  섀도잉(노랑 #FFCC00). Do not build a 듣기(listening) or 스피치(speech) tile; mention them in words,
  never point a screen label at them.
- **App labels stay the app's own** (from the kit): 나의 루틴 · 대화 10분 · 다시 말하기 · 주간 테스트 ·
  복습 20개 · 섀도잉 5문장 · 오늘 지키면 1일째 · N일째 지키는 중 · 통화 시간 · 통화 · 카드 공유
  (en: My routine · Talk 10 min · Say it again · Weekly test · Review 20 items · Shadowing 5 lines ·
  Keep it today for day 1 · Kept for N days · Talk time · Talks · Share card).
- **Every number on screen is kit sample data** (10분, 20개, 5문장, N일째) — never a user statistic.
  No title or desc restates them; they stay inside the pictured page.
- **The flame + "N일째 지키는 중" belongs to the routine page only.** The weekly-test screen has no
  flame and no gauge; don't mix them (card 5 uses the routine page, not the test).

---

## 01 · Cover: the one message, over the finished routine page
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 01 / 06
title (ko): 루틴은\n내가 만든다
desc (ko):  앱이 정해주는 플랜이 아니에요.\n**내가 고른 것만** 모여 내 하루가 돼요.
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): nawana · Routine · 01 / 06
title (en): You build\nyour routine
desc (en):  Not a plan the app hands you.\n**Only what you pick** becomes your day.
footer (en): Swipe → · nawana.app

screen: `nw-routine` pose `day-plan` (static) — the My routine page with blocks laid out. Works as a feed still.
alt (ko): ‘루틴은 내가 만든다’ 아래 ‘앱이 정해주는 플랜이 아니에요, 내가 고른 것만 모여 내 하루가 돼요’가 있고, 통화·다시 말하기·주간 테스트·복습·섀도잉 블록이 깔린 나의 루틴 페이지가 보이는 표지예요.
alt (en): Cover: "You build your routine" over "Not a plan the app hands you. Only what you pick becomes your day." Below, the My routine page with its talk, Say it again, weekly test, review and shadowing blocks laid out.

## 02 · Setup shows what you can practice, one card at a time
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 02 / 06
title (ko): 셋업에서\n하나씩 보여줘요
desc (ko):  연습할 수 있는 걸 **카드 한 장씩** 보여줘요.\n통화 · 다시 말하기 · 복습 · 섀도잉 · 듣기 · 스피치.

eyebrow (en): nawana · Routine · 02 / 06
title (en): Setup shows them\none at a time
desc (en):  Everything you can practice, **one card at a time**.\nCalls · Say it again · review · shadowing · listening · speech.

screen: `nw-routine` `day-plan`, MOTION = the block rows appear one by one, in order (each row reads as a card you just added). Listening/speech are named in the desc only, never a row.
alt (ko): 나의 루틴 페이지에 통화, 다시 말하기, 주간 테스트, 복습, 섀도잉 블록이 한 줄씩 차례로 나타나며 쌓여요.
alt (en): On the My routine page, the blocks appear one row at a time, in order: talk, Say it again, weekly test, review, shadowing.

## 03 · Keep what you want, pass the rest; no nag
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 03 / 06
title (ko): 담을 것만 담고\n나머진 넘겨요
desc (ko):  원하는 것만 추가하고 나머진 넘겨요.\n**하나도 안 담아도 괜찮아요.** 나중에 만들어도 돼요.

eyebrow (en): nawana · Routine · 03 / 06
title (en): Add what you want,\npass the rest
desc (en):  Keep the ones you want, skip the rest.\n**Add nothing if you like**, and set it up later.

screen: `nw-routine` `day-plan`. STICKER help: a few real kit block tiles (통화 · 다시 말하기 · 복습 · 섀도잉 · 주간 테스트) float around the phone, some tagged 추가 ✓, some 넘김, to show the choosing. Build no 듣기/스피치 tile.
sticker tags:
  ko: 추가 ✓ / 넘김
  en: Added ✓ / Passed
alt (ko): 나의 루틴 페이지 둘레로 통화, 다시 말하기, 복습, 섀도잉, 주간 테스트 블록 타일이 떠 있고 일부엔 ‘추가’, 일부엔 ‘넘김’ 표시가 붙어, 원하는 것만 고르는 모습을 보여줘요.
alt (en): Around the My routine page, block tiles for talk, Say it again, review, shadowing and weekly test float, some marked "Added" and some "Passed", showing you pick only the ones you want.

## 04 · Shadowing and listening each have their own spot (the 1.2.1 detail)
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 04 / 06
title (ko): 섀도잉도 듣기도\n각자 자리예요
desc (ko):  섀도잉은 이제 **따로 한 자리**예요.\n듣기는 한 편만 들으면 그날 몫이 끝이에요.

eyebrow (en): nawana · Routine · 04 / 06
title (en): Shadowing and listening,\neach its own spot
desc (en):  Shadowing is **its own block** again.\nListening: hear one piece and that block is done.

screen: `nw-routine` `day-plan`, the 섀도잉 row (노랑 wave) highlighted with a soft pulse. Listening is spoken in the desc only and is NOT drawn as a row.
alt (ko): 나의 루틴 페이지에서 노란 섀도잉 블록이 살짝 밝아지며 강조돼요. 듣기 블록은 화면에 그리지 않고 글로만 이야기해요.
alt (en): On the My routine page, the yellow shadowing block pulses to stand out. Listening is described in words only, not drawn as a row.

## 05 · Keep it, and it's a promise to yourself (the payoff)
eyebrow (ko): 나와나로 할 수 있는 것 · 루틴 · 05 / 06
title (ko): 지키면 내가\n나에게 한 약속
desc (ko):  내가 담은 루틴이 곧 내 약속이에요.\n지킨 날이 쌓이고, 그건 **내가 고른 거예요.**

eyebrow (en): nawana · Routine · 05 / 06
title (en): Keep it, it's\nyour own promise
desc (en):  The routine you built is your own promise.\nThe days add up, and **you chose them.**

screen: `nw-routine` pose `day-kept`, MOTION = the block rings fill, the flame lights, and the streak reads "N일째 지키는 중" / "Kept for N days" (kit sample N). Routine page only, no weekly-test flame/gauge.
alt (ko): 나의 루틴 페이지에서 블록마다 초록 링이 차고 불꽃이 켜지며 ‘N일째 지키는 중’이 떠요. 약속을 지킨 하루의 모습이에요. (N은 샘플 숫자예요.)
alt (en): On the My routine page, each block's green ring fills, the flame lights, and the streak reads "Kept for N days" — a day the promise was kept. (N is sample data.)

## 06 · Outro (BRAND standard) + closing line above it
eyebrow: none (06 / 06 if the layout shows one)
closing (ko): 내 루틴은,\n내가 정해요.
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app

closing (en): Your routine\nis yours to set.
tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app

screen: `nw-futureself`, no phone.
alt (ko): ‘내 루틴은, 내가 정해요.’ 아래 nawana 워드마크와 ‘유창한 나에게 언어를 배우세요.’, ‘첫 20분은 무료예요’, nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: "Your routine is yours to set." above the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

매일 뭘 할지 앱이 정해주는 게 싫었다면.

나와나는 셋업에서 연습할 수 있는 걸 카드로 하나씩 보여줘요. 통화, 다시 말하기, 복습, 섀도잉, 듣기, 스피치. 원하는 것만 담으면 그게 내 루틴이 되고, 하나도 안 담아도 괜찮아요. 나중에 만들어도 되거든요.

담은 루틴은 곧 내가 나에게 한 약속이에요. 지킨 날이 쌓여요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #루틴 #nawana

## Instagram caption (en)

Tired of an app deciding what you do every day?

In setup, nawana shows you what you can practice one card at a time: calls, Say it again, review, shadowing, listening, speech. Keep only the ones you want, and that's your routine. Add nothing and that's fine too, you can set it up later.

The routine you keep becomes a promise to yourself, and the days you keep it add up.

Your first 20 minutes are free · link in bio

#languagelearning #learnenglish #speakingpractice #studyroutine #nawana

## Threads (ko) · a reply in the series thread

루틴을 앱이 정해주는 게 싫어서 앱을 지운 적 있다면, 이번엔 반대예요.

나와나는 셋업에서 연습할 수 있는 걸 카드로 하나씩 보여줘요. 통화, 다시 말하기, 복습, 섀도잉, 듣기, 스피치. 원하는 것만 담고 나머진 넘겨요. 하나도 안 담아도 괜찮고요.

섀도잉도 듣기도 이제 각자 자리가 있어요.

담은 루틴은 내가 나에게 한 약속이에요. 지킨 날이 쌓이고, 그건 내가 고른 거예요.

(≈ 250자, no hashtags)

## Threads (en) · a reply in the English series thread

Ever deleted a language app because it kept deciding your day for you? This flips it.

In setup, nawana shows what you can practice one card at a time: calls, Say it again, review, shadowing, listening, speech. Keep what you want, pass the rest. Add nothing and that's fine.

Shadowing and listening each get their own spot now.

The routine you keep is a promise to yourself. The days add up, and you chose them.

(≈ 420 chars, no hashtags)

## Community series entry (new; the 루틴 편)

cat: start
ko: { title: "내가 짜는 루틴", tagline: "앱이 정해주지 않아요. 담은 것만 내 하루가 돼요" }
en: { title: "Your own routine", tagline: "The app doesn't decide. What you keep becomes your day" }

(Proposed id e20, next free after e19. Slides 720×900, ko/en title+tagline above. Mirrors the IG carousel the same day. Publisher confirms id + cat with the lead before it goes live.)

---

## Open questions (for the lead)

1. **Cover title register.** The pixel title `루틴은 내가 만든다` is a declarative slogan (not 해요체),
   kept exactly as the brief set it as the campaign's one message. Everything else is 해요체. Flag if
   the founder wants the cover in 해요체 too (e.g. `루틴은 내가 만들어요`).
2. **Card 2 lists six choices, the screen draws five.** The desc names 통화·다시 말하기·복습·섀도잉·
   듣기·스피치 (the onboarding choices); the pictured `routine.js` has no listening/speech tile, so the
   motion shows only the five real kit blocks. This is intended per the honesty note. Confirm the
   wording fits with the row animation.
3. **Sample N on card 5.** The streak reads the kit's "N일째 지키는 중" sample; alt text marks it as
   sample data. If the designer wants a specific N drawn, keep it clearly illustrative, not a stat.
4. **Community id/cat.** Proposed e20 / `start`; publisher to confirm with the lead before deploy.
