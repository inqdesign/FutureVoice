# 무조건 말하게 만들어요 · copy (series 08, 7 cards)

Written 2026-10-16 from brief.md. Korean written as Korean, English as English; they agree in
meaning, not wording. 해요체, no 당신, no em dash anywhere. Silent first: no sound lines.
Lead's framing applied: 1-0 is for people who can already hold a conversation ("대화가 되면" /
"If you can chat"), 1-1 is for people whose words don't come out yet ("말이 막혀도" /
"Words won't come?"). Neither card names a level or grades the reader; no 왕초보/beginner.

Eyebrow on every card: `nawana · NN / 07`. Mode label sits in front of the title, small, same
style on all five and on the cover chips.

## For the designer

- **Titles:** every title is 2 short lines (ko 4 to 8 chars a line). Descs are 2 lines, one
  idea, one bold phrase.
- **Mode labels:** ko `1-0 프리토킹 · 1-1 코치 모드 · 2 섀도잉 · 3 다시 말하기 · 4 스피치`;
  en `1-0 Free talk · 1-1 Coach mode · 2 Shadowing · 3 Say it again · 4 Speech`.
  The app's own label is **섀도잉**, so the copy uses that, not the founder's 쉐도잉 (see Open questions).
- **App labels stay the app's own:** 이렇게 말해 보세요 · 써 볼 단어 · 썼어요 · 섀도잉 · 원본 문장 ·
  다시 말하기 · 고친 대로 말해 보세요 · 스피치 · 원고 · 내 원고 · 정확도 · 말하기 속도 · 쉼 · 군말 ·
  목소리 안정감 (en: Try saying · Try using · Used it · Shadowing · Say it again · Say it the fixed
  way · Speech · Scripts · My script · Accuracy · Pace · Pauses · Fillers · Steady voice).
- **Conversation lines are material: English on both versions.** Scores are kit sample data.

---

## 01 · Cover: the problem in the learner's words, then the promise; five chips as contents
eyebrow (ko): nawana · 01 / 07
title (ko): 몇 년 공부했는데\n말해 본 적은 없어요
desc (ko):  **나와나는 무조건 말하게 만들어요.**\n어디서 시작하든, 결국 내 입으로 소리 내 말해요.
chips (ko):
  1-0 프리토킹
  1-1 코치 모드
  2 섀도잉
  3 다시 말하기
  4 스피치
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): nawana · 01 / 07
title (en): Years of study,\nbarely a word spoken
desc (en):  **nawana makes you speak. No matter what.**\nFive ways in, and every one ends with you saying it out loud.
chips (en):
  1-0 Free talk
  1-1 Coach mode
  2 Shadowing
  3 Say it again
  4 Speech
footer (en): Swipe → · nawana.app

screen: no phone. `nw-futureself` in its circle + the five chips (they are the carousel's contents)
alt (ko): ‘몇 년 공부했는데 말해 본 적은 없어요’ 아래 ‘나와나는 무조건 말하게 만들어요’가 있고, 미래의 나 모자이크 옆에 프리토킹, 코치 모드, 섀도잉, 다시 말하기, 스피치 다섯 가지가 번호와 함께 나열된 표지예요.
alt (en): Cover: "Years of study, barely a word spoken" over "nawana makes you speak. No matter what." Beside the fluent-self mosaic, five numbered chips: Free talk, Coach mode, Shadowing, Say it again, Speech.

## 02 · 1-0 Free talk: the call after the interview, no coach
eyebrow (ko): nawana · 02 / 07
label (ko): 1-0 프리토킹
title (ko): 대화가 되면\n그냥 말해요
desc (ko):  주제도 대본도 없이 유창한 나와 통화해요.\n**내가 꺼낸 얘기**를 유창한 내가 이어받아요.

eyebrow (en): nawana · 02 / 07
label (en): 1-0 Free talk
title (en): If you can chat,\njust call
desc (en):  No script, no topic. Just a call with your fluent self,\nwho picks up **whatever you bring up**.

screen: `nw-call`, plain (no coach line).
  1. say(): "Hey! So, how did the interview go?"
  2. listen()
  3. user(): "Honestly, better than I expected. They asked about a project I led last year, and I actually had a lot to say."
  4. say(): "Wait, the one you led? What part were you proudest of?"
alt (ko): 유창한 내가 면접이 어땠냐고 묻고, 학습자가 작년에 이끈 프로젝트 얘기를 길게 하자, 유창한 내가 그 프로젝트에서 뭐가 제일 뿌듯했냐고 이어서 물어요.
alt (en): The fluent self asks how the interview went; the learner talks at length about a project they led last year, and the fluent self follows up on that project.

## 03 · 1-1 Coach mode: a line to say is already there
eyebrow (ko): nawana · 03 / 07
label (ko): 1-1 코치 모드
title (ko): 말이 막혀도\n할 말이 떠 있어요
desc (ko):  유창한 내가 물을 때마다 **이렇게 말해 보세요**가 떠요.\n표시된 부분만 내 얘기로 바꿔서 말해요.

eyebrow (en): nawana · 03 / 07
label (en): 1-1 Coach mode
title (en): Words won't come?\nA line is waiting
desc (en):  Each time your fluent self asks, **Try saying** offers an answer.\nSwap the marked part for your own story.

screen: `nw-call` with `coach()`. The word hint comes only after the learner has spoken once, so the card opens on one quick exchange:
  1. say(): "So, how did the interview go?"
  2. user(): "It went well."
  3. say(): "Nice! How did you feel going in?"
  4. coach({ line: "I felt <u>a little nervous</u>, but prepared.", gloss (ko): "<u>좀 떨렸</u>지만, 준비는 돼 있었어.", word: "prepared" })
  5. user(): "I was really nervous, but I felt prepared."
  6. hint ticks: 써 볼 단어 · prepared → 썼어요 (en: Try using · prepared → Used it)
sticker (optional): the coach line enlarged, a small tag on the underlined part:
  ko: 여기는 내 얘기
  en: Your part
alt (ko): 유창한 내가 면접장에 들어갈 때 기분이 어땠냐고 묻자, 통화 버튼 위에 ‘이렇게 말해 보세요’와 뜻, 써 볼 단어 prepared가 떠요. 학습자가 떨렸던 부분을 자기 얘기로 바꿔 말하자 ‘썼어요’로 바뀌어요.
alt (en): The fluent self asks how the learner felt going in; above the call button, "Try saying" appears with the word to try, "prepared". The learner puts their own feeling into the line and says it, and the hint turns to "Used it".

## 04 · 2 Shadowing: one line, after your own voice
eyebrow (ko): nawana · 04 / 07
label (ko): 2 섀도잉
title (ko): 한 문장을\n내 목소리 따라
desc (ko):  유창한 내가 통화에서 한 말을 **내 목소리로** 들어요.\n그대로 따라 말하면 마이크에 들린 말이 보여요.

eyebrow (en): nawana · 04 / 07
label (en): 2 Shadowing
title (en): One line,\nafter your own voice
desc (en):  Hear a line your fluent self said on your call, **in your voice**.\nSay it after it and see what the mic heard.

screen: `nw-shadow`, target "You clearly took the initiative and prioritized what mattered." plays with karaoke → take (red record) → result. Piece 02's cards 03 to 04 compressed.
alt (ko): 유창한 내가 통화에서 한 문장 ‘You clearly took the initiative and prioritized what mattered.’가 단어별로 켜지며 재생되고, 학습자가 따라 말하자 점수와 마이크에 들린 문장이 나와요.
alt (en): The line "You clearly took the initiative and prioritized what mattered." plays word by word; the learner says it after and gets a score with what the mic heard.

## 05 · 3 Say it again: the same call, the fixed way
eyebrow (ko): nawana · 05 / 07
label (ko): 3 다시 말하기
title (ko): 그 통화를\n이번엔 제대로
desc (ko):  방금 그 통화를 처음부터 다시 해요.\n내 차례엔 **고친 말**로, 대답은 그때 그대로예요.

eyebrow (en): nawana · 05 / 07
label (en): 3 Say it again
title (en): That call,\ndone right
desc (en):  Run the whole call again from the top.\nYour turns **the fixed way**, the answers just as they were.

screen: `nw-sayagain sample="interview"` pose `reading`: prompter 고친 대로 말해 보세요 "Honestly, it **went** really well. I felt prepared." → the answer row plays "Nice, you sound relieved! Which question was the hardest?" → next line comes up. Piece 03's card 04.
alt (ko): 프롬프터에 ‘went’가 파랗게 표시된 고친 문장이 뜨고, 학습자가 읽자 유창한 내가 통화 때 했던 대답이 이어지고 다음 문장이 올라와요.
alt (en): The prompter shows the corrected line with "went" in blue; the learner reads it, the fluent self's original reply follows, and the next line comes up.

## 06 · 4 Speech: a whole script, start to finish
eyebrow (ko): nawana · 06 / 07
label (ko): 4 스피치
title (ko): 원고 한 편을\n끝까지
desc (ko):  내가 쓴 원고를 프롬프터로 보며 처음부터 끝까지 읽어요.\n점수는 **다섯 가지로** 나눠서 나와요.

eyebrow (en): nawana · 06 / 07
label (en): 4 Speech
title (en): A whole script,\nstart to finish
desc (en):  Read your own script on a prompter, all the way through.\nYour score comes **in five parts**.

screen: `nw-speech` 원고 list → tap the own-script row → prompter scrolls → `result(…)` gauge counts up + five rows (정확도 · 말하기 속도 · 쉼 · 군말 · 목소리 안정감). No leaderboard, no camera note.
own-script row title:
  ko: 면접 자기소개
  en: Interview intro
own-script text (material, English on both):
  "Hi, thanks for having me. For the past three years, I've worked as a product designer at a small startup. Last year I led the redesign of our app, and I learned to take the initiative when things weren't clear. I'm looking for a team where I can keep growing, and this role feels like a great fit."
alt (ko): 스피치 원고 목록에서 ‘면접 자기소개’를 누르자 프롬프터에 원고가 흘러가고, 다 읽고 나면 점수가 올라가며 정확도, 말하기 속도, 쉼, 군말, 목소리 안정감 다섯 줄이 나와요.
alt (en): In Speech, the learner opens their own script "Interview intro"; it scrolls on a prompter, and when it's read, a score counts up with five rows: accuracy, pace, pauses, fillers and steady voice.

## 07 · Outro (unchanged) + closing line above it
eyebrow: none (07 / 07 if the layout shows one)
closing (ko): 어디서 시작하든,\n결국 말하게 돼요.
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app
closing (en): Wherever you start,\nyou end up speaking.
tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app
screen: `nw-futureself`, no phone
alt (ko): ‘어디서 시작하든, 결국 말하게 돼요.’ 아래 nawana 워드마크와 ‘유창한 나에게 언어를 배우세요.’, ‘첫 20분은 무료예요’, nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: "Wherever you start, you end up speaking." above the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

공부는 몇 년 했는데, 정작 말해 본 적은 별로 없죠.
나와나는 무조건 말하게 만들어요.

1-0 프리토킹 · 대화가 되면, 주제 없이 유창한 나와 통화해요
1-1 코치 모드 · 말이 막혀도 할 말이 떠 있어요. 내 얘기만 넣어 말해요
2 섀도잉 · 내 통화 속 한 문장을, 내 목소리 따라 말해요
3 다시 말하기 · 그 통화를 처음부터, 이번엔 고친 말로 다시 해요
4 스피치 · 내가 쓴 원고 한 편을 끝까지 읽어요

어디서 시작하든, 결국 내 입으로 말하게 돼요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #스피킹 #영어말하기 #영어공부 #nawana

## Instagram caption (en)

Studied for years, but barely said a word out loud?
nawana makes you speak. No matter what.

1-0 Free talk · If you can chat, just call your fluent self, no topic needed
1-1 Coach mode · Words won't come? A line is waiting. Add your own story
2 Shadowing · One line from your call, said after your own voice
3 Say it again · The same call from the top, the fixed way
4 Speech · Your own script, start to finish

Wherever you start, you end up speaking.

Your first 20 minutes are free · link in bio

#speakingpractice #learnenglish #englishconversation #languagelearning #nawana

## Threads (ko) · a reply in the series thread

이번엔 다섯 가지를 한 번에 묶어 봤어요.

공부는 몇 년 했는데 말해 본 적은 별로 없다면, 나와나에서 하는 건 결국 하나예요. 소리 내 말하기.

1-0 프리토킹 · 대화가 되면 주제 없이 그냥 통화해요
1-1 코치 모드 · 말이 막혀도 할 말이 떠 있어요. 내 얘기만 넣어서
2 섀도잉 · 내 통화 속 한 문장을, 내 목소리 따라
3 다시 말하기 · 그 통화를 처음부터, 이번엔 고친 말로
4 스피치 · 내가 쓴 원고 한 편을 끝까지

지금 실력 그대로 시작하면 돼요. 어디서 시작하든 말하게 돼요.

(≈ 260 chars, no hashtags, no sound line, all 7 items)

## Threads (en) · a reply in the English series thread

This one puts them all in one place.

If you've studied for years and barely spoken, everything here comes down to one thing: saying it out loud.

1-0 Free talk · If you can chat, just call. No topic needed
1-1 Coach mode · Words won't come? A line is waiting, you add your own story
2 Shadowing · One line from your call, after your own voice
3 Say it again · That call from the top, the fixed way
4 Speech · Your own script, start to finish

Wherever you start, you end up speaking.

(484 chars by the reviewer's count, no hashtags, no sound line, all 7 items)

## Community series entry (new; an overview, not a replacement of e11/e12)

cat: start
ko: { title: "무조건 말하게", tagline: "다섯 가지 방법, 끝은 모두 내 입으로" }
en: { title: "Made to speak", tagline: "Five ways in, every one out loud" }

---

## Open questions (for the lead)

1. **쉐도잉 vs 섀도잉.** The founder wrote 쉐도잉; the app (kit, book, word card) says 섀도잉,
   and pieces 02/03 used 섀도잉. Copy uses the app's spelling. Swap if the founder wants 쉐도잉.
2. **Coach card choreography (03).** The word hint "써 볼 단어" can't appear before the learner
   has spoken (rationing rule), so the card opens with a one-line exchange ("It went well.")
   before the coached question. If the designer wants it shorter, drop the word hint and keep
   only the coach line + gloss.
3. **Coach line marking.** I wrote "표시된 부분 / the marked part" for the part the learner fills
   (the kit's `<u>`). I didn't confirm how the live app draws it (CLAUDE.md says a faded example
   in brackets). If the kit draws it differently, the desc still holds, but the sticker tag
   should point at whatever is on screen.
4. **Card 02 en title** "If you can chat, / just call" is the reader-side framing of 1-0 (no level
   word). Check it fits at the new 52–56px; fallback "Can hold a chat? / Just call."
5. **Card 06 own script:** row title and text above are for kit gap 1 (own-script input). Script
   text is sample material, no real names.
6. **Threads (en)** is near the 500 limit (484 after review FIX 8). If the thread client counts the mode numbers
   differently, cut "No topic needed".
