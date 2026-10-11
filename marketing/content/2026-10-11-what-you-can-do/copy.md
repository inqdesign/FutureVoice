# 나와나로 할 수 있는 것들 — copy (v2, 10 cards)

Series cover carousel, **10 cards** (brief v2, 2026-10-11: the 6-card version was "너무 빈약하다";
Speech is dropped from this piece and becomes its own episode later).
Cards 02–04 and the outro are the founder-approved v1 text, unchanged except for the card
number. The cover (eight chips), 05 Watch, 06 Review, 07 Say it again (다시 말하기), 08 Daily call
and 09 Week + test are new. Each one was written in Korean first and then separately in English,
not translated. Captions, Threads and the community tagline are rewritten for 10 cards and need
the founder's approval again (brief risk 14).

Length target for the new descriptions: the approved cards 02/04 run about 58–62 Korean
characters and about 130–150 English characters, and the reviewer measured them at 2 lines on
the render. Every new description stays at or under that.

**For the designer (v2 changes to `carousel.html` / the kit):**
- Every eyebrow number → `NN / 10` (cover 01 / 10 … outro 10 / 10).
- Cover: eight chips instead of four (text below). At the current `.chips` metrics (34px, gap 20,
  top 772) eight rows run to about 1,260px, which is tight. Brief risk 13 says to shorten labels
  rather than shrink type. The labels below are already cut to ≤ 13 Hangul / ≤ 27 Latin
  characters. If they still crowd, cut the gap to ~12px or move the block up. Don't go below 30px.
- Cover alt text: "02~05장" → "02~09장".
- The old card 05 (Speech, `nw-speech nochallenges`) is **removed** from this piece. Keep it in
  `renders-v1/` only.
- New cards 05–09 use the screens and beats named in the brief (`nw-watch`, `nw-review`,
  `nw-sayagain`, `nw-ring` → `nw-call`, `nw-weekreport` + `nw-weeklytest`). Copy-dependent
  constraints:
  - **05 Watch:** the "Your own situation" door only (dictation → scene → "Shadow this"). Don't cut
    in the café `scene` pose (the other door). No attachment chips, because the desc doesn't
    claim it reads a file.
  - **06 Review:** the desc names words, expressions and the fixed sentences answered out loud.
    It does **not** name shadowing, so the Shadow chapter (`nw-bookpage open("shadow")`) is not
    needed. Leave the PDF export out.
  - **07 Say it again:** the desc carries "the whole call, start to finish". Please start on the
    `intro` pose (its text "이 대화를 처음부터 다시 해요…대답은 그때 그대로") long enough to read,
    because the 2-turn demo alone looks like a corrections drill (brief risk 4).
  - **08 Daily call:** an alarm screen, never drawn or captioned as an incoming call. The 13:00
    "rings anyway" beat is fine, but no missed-call banner or "I'll call again" anywhere.
  - **09 Week + test:** the report's streak flame stays on the report half. The test half shows no
    flame and no gauge. Suggested cut: report beat 1 (cover) + beat 3 (coach over your own lines),
    then test beat 3 (the mistake rebuilt from tiles) + beat 4 (result).
    **Round 3 fix (review item 6):** the desc's second sentence changed — ko "이어지는 테스트도
    전부 내 대화에서 나와요." · en "Then a short test, made from your own talks." Update
    `carousel.html`, check the desc still fits 2 lines (both are no longer than before), and
    re-render 09.mp4 + 09.png.
- Outro: unchanged except its number (10 / 10).

---

## 01 — Cover: series title, futureself mosaic speaking, eight chapters slide in
eyebrow: 나와나로 할 수 있는 것 · 01 / 10
title (ko): 나와나로\n할 수 있는 것들
desc (ko):  유창한 나와 말해보는 외국어 앱, 나와나.\n할 수 있는 걸 하나씩 보여드릴게요.
chips (ko):
  02 유창한 나와 대화
  03 왜 내 목소리일까
  04 Talk · 원하는 대화
  05 Watch · 미리 겪어 보기
  06 Review · 대화가 교재로
  07 다시 말하기
  08 매일 통화 · 알람처럼
  09 한 주 돌아보기 · 테스트
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): What you can do with nawana · 01 / 10
title (en): What you can\ndo with nawana
desc (en):  A language app where you talk with the fluent you.\nHere's what it does, one card at a time.
chips (en):
  02 Talk with the fluent you
  03 Why your own voice
  04 Talk · what you want
  05 Watch · before it happens
  06 Review · your own book
  07 Say it again
  08 Daily call · like an alarm
  09 Your week · and a test
footer (en): Swipe → · nawana.app

screen: no phone. `nw-futureself` (speaking) + chip list
alt (ko): ‘나와나로 할 수 있는 것들’ 제목 아래 미래의 나 모자이크가 말하고, 02~09장 목차가 하나씩 나타나는 표지예요.
alt (en): Cover titled "What you can do with nawana": the fluent-self mosaic speaks while the contents for cards 02 to 09 appear one by one.

## 02 — The call: the fluent self asks, the learner answers, the correction lands  (v1, approved)
eyebrow: 나와나로 할 수 있는 것 · 02 / 10
title (ko): 유창한 나와\n대화를 한다고?
desc (ko):  내 목소리로 외국어를 유창하게 하는 **몇 년 뒤의 나**와 전화하듯 이야기해요. 어색한 말은 통화 중에 바로 고쳐줘요.

title (en): Talk with\na fluent… you?
desc (en):  It's a phone call with **you, a few years on**: your voice, already fluent. Anything that comes out awkward gets fixed during the call.

screen: `nw-call` (as scripted in carousel.html)
material on screen (stays English in both versions):
- fluent self: "Hey, it's you, a few years from now. So, how was your week?"
- try-saying hint: "It was a busy week, honestly." · ko gloss: 솔직히 바쁜 한 주였어.
- learner: "It was a busy week. I go to three meetings a day."
- correction: "It was a busy week. I **went** to three meetings a day." · note (ko): 지난 일이라 과거형이에요 · note (en): It already happened, so past tense.
- fluent self: "Three a day? No wonder you sound tired. Which one went best?"
- goal chips: busy week · catch up · no wonder
alt (ko): 통화 화면에서 미래의 내가 영어로 한 주가 어땠는지 묻고, 학습자의 답 아래에 과거형으로 고친 문장이 떠요.

## 03 — Why your own voice: one sentence, two voices  (v1, approved)
eyebrow: 나와나로 할 수 있는 것 · 03 / 10
title (ko): 왜 원어민 말고\n내 목소리일까?
desc (ko):  원어민을 따라 하면 연기하는 것 같아요. 내 목소리로 들으면 **‘나도 이렇게 말할 수 있구나’**가 돼요.
prompt (ko): 같은 문장을 두 목소리로 / “I'd love to tell you about my project.”
row A (ko): AI 원어민 음성 · 남의 목소리. Reaction: 따라 하면 연기하는 것 같아. 나 같지가 않아
row B (ko): 유창한 나 · 내 목소리. Reaction: 어? 이거 나잖아. 나도 되겠는데?

title (en): Why your voice,\nnot a native's?
desc (en):  Copying a native speaker feels like acting. Hear it in your own voice and it becomes **“I can say it like that too.”**
prompt (en): One sentence, two voices / “I'd love to tell you about my project.”
row A (en): AI native voice · someone else's. Reaction: Copying this feels like acting. It's not me.
row B (en): Fluent you · your voice. Reaction: Wait, that's me. I could actually do this.

screen: compare rows (wave + reaction bubbles), no phone
alt (ko): 같은 영어 문장을 AI 원어민 음성과 내 목소리로 차례로 들려주고, 내 목소리 쪽에 ‘어? 이거 나잖아’ 반응이 떠요.

## 04 — Talk: the ring, then news / everyday / your situations  (v1, approved)
eyebrow: 나와나로 할 수 있는 것 · 04 / 10
title (ko): Talk\n하고 싶은 대화로
desc (ko):  링을 누르면 자유 대화, 아래에선 **오늘의 뉴스**, **카페·병원 같은 일상**, **내가 만든 상황**으로 시작해요.

title (en): Talk\nabout what you want
desc (en):  Tap the ring to just talk. Below it, start from **today's news**, **everyday spots like a café or a clinic**, or **a situation you set up**.

screen: `nw-home` (tap ring → scroll → 뉴스 / 일상 / 상황 tabs)
alt (ko): Talk 탭에서 링을 누른 뒤 아래로 내려가 뉴스, 일상, 상황 목록을 차례로 넘겨요.

## 05 — Watch: your own situation, dictated, then the scene plays before it happens  (NEW)
eyebrow: 나와나로 할 수 있는 것 · 05 / 10
title (ko): Watch\n일어나기 전에 미리
desc (ko):  곧 있을 면접을 적어 두면 **유창한 내가 먼저 해내는 장면**을 보여줘요. 마음에 드는 문장은 바로 따라 해요.

title (en): Watch\nbefore it happens
desc (en):  Write down what's coming, like next week's interview, and watch **the fluent you get through it first**. Like a line? Shadow it right there.

screen: `nw-watch` demo. Beat 1: the "내 상황" box, dictated ("다음 주 목요일 디자인 직무 패널 면접…"), CTA tapped. Beat 2: "대화를 쓰는 중…", then the interview plays line by line. Beat 3: "이 문장 섀도잉" tapped. Poster: pose `playing`.
material on screen: the scene's lines stay English. The dictated situation is the learner's own note (Korean on ko, English on en, as the kit does).
sticker / reaction text: none
alt (ko): Watch의 ‘내 상황’ 칸에 다음 주 디자인 직무 면접을 말로 적고 나면, 면접관과 유창한 내가 주고받는 영어 대화가 한 줄씩 재생되고 ‘이 문장 섀도잉’을 눌러요.
alt (en): In Watch, the learner dictates next week's design interview into "Your situation"; an English interview between the interviewer and the fluent self then plays line by line, and "Shadow this" is tapped.

## 06 — Review: the talk becomes a book  (NEW)
eyebrow: 나와나로 할 수 있는 것 · 06 / 10
title (ko): Review\n대화가 교재가 돼요
desc (ko):  통화가 끝나면 그 대화가 **나만의 교재**가 돼요. 단어와 표현을 익히고, 고친 내 문장은 소리 내어 복습해요.

title (en): Review\nevery talk, a book
desc (en):  When a call ends, it turns into **your own book**: its words and phrases, and the sentences you fixed, reviewed out loud.

screen: `nw-review` demo. Beat 1: Studying shelf → the talk's book → cover. Beat 2: Words, then Expressions ribbons. Beat 3: Drill (said line struck → fixed line). Beat 4: "이 대화 복습" → sentence card answered aloud, revealed, filed into 내일. Poses as in the brief.
material on screen: words, expressions and sentence cards stay English. Chapter names, why-notes and buttons are Korean on ko.
sticker / reaction text: none
alt (ko): 복습 탭에서 지난 대화의 교재를 열어 단어, 표현, 고친 문장 장을 차례로 넘기고, 문장 카드를 소리 내어 답한 뒤 ‘내일’로 넘겨요.
alt (en): On the Review tab, a past talk's book opens to its words, expressions and fixed-sentence chapters; a sentence card is answered out loud and filed for tomorrow.

## 07 — Say it again (다시 말하기): the same call, from the start, the right way  (NEW)
eyebrow: 나와나로 할 수 있는 것 · 07 / 10
title (ko): 다시 말하기\n같은 통화를 제대로
desc (ko):  했던 통화를 **처음부터 끝까지** 다시 해요. 내 차례엔 고친 대로 말하고, 유창한 나는 그때 그대로 대답해요.

title (en): Say it again\nthe same call, done right
desc (en):  Go through a past call again, **start to finish**. Your lines come up the way they should go; the fluent you answers just as it did.

screen: `nw-sayagain`. Intro (held long enough to read), beat 1 fluent-self line, beat 2 prompter "고친 대로 말해 보세요" with "it **went** really well" read → 92, beat 3 next answer, second line → 61 with "들린 말", beat 4 finish. Poster: pose `reading`.
material on screen: the lines stay English. Prompter label, "들린 말" and the finish line are Korean on ko.
sticker / reaction text: none (the prompter's highlight carries the fix. Add a "내가 한 말 → 고친 말" sticker only if it's unreadable at feed size, per the brief.)
alt (ko): 다시 말하기 화면에서 지난 통화가 처음부터 다시 흘러가고, 프롬프터에 뜬 고친 문장을 소리 내어 읽으면 점수가 나와요.
alt (en): In Say it again, a past call runs again from the top; the learner reads the corrected line on the prompter out loud and gets a score.

## 08 — Daily call: it rings like an alarm, the call opens with a question  (NEW)
eyebrow: 나와나로 할 수 있는 것 · 08 / 10
title (ko): 매일 통화\n알람처럼 울려요
desc (ko):  정해 둔 시간이 되면 무음 모드여도 알람처럼 울려요. 받으면 **지난 대화에서 이어지는 질문**으로 통화가 시작돼요.

title (en): Daily call\nrings like an alarm
desc (en):  Set a time and it rings like an alarm, even on silent. Answer, and the call opens with **a question from your last talk**.

screen: `nw-ring`. Beat 1 alarm screen ringing ("Future Jiwoo", 8:00, 받기 + slide to stop). Beat 2 Answer → `nw-call`. Beat 3 "Morning! You had the interview yesterday, right? How did it go?" → answer → follow-up. Beat 4 another morning slid away, 13:00 rings. Poster: pose `ring`.
material on screen: the call lines stay English. "받기" and the call chrome are Korean on ko. "Future Jiwoo" is kit sample data.
sticker / reaction text: none
alt (ko): 잠긴 화면에 8시 알람이 울리고, ‘받기’를 누르면 미래의 내가 어제 면접은 어땠는지 영어로 물으며 통화가 시작돼요.
alt (en): An 8:00 alarm rings on the lock screen; tapping Answer starts a call where the fluent self asks, in English, how yesterday's interview went.

## 09 — Your week, then a test made from your own talks  (NEW, desc fixed round 3)
eyebrow: 나와나로 할 수 있는 것 · 09 / 10
title (ko): 한 주 돌아보기\n그리고 테스트
desc (ko):  한 주가 끝나면 그 주에 한 말과 **자꾸 하는 실수**를 돌아봐요. 이어지는 테스트도 전부 내 대화에서 나와요.

title (en): Your week,\nthen a test
desc (en):  When the week wraps up, look back at what you said and **the slip you keep making**. Then a short test, made from your own talks.

screen: top half `nw-weekreport` (cover → coach "Past tense drops out halfway through a story" over your own lines), then `nw-weeklytest` (the mistake rebuilt from tiles from a Korean prompt → result 6/7 with the miss listed). Streak flame on the report cover only. No flame, no gauge on the test.
material on screen: the learner's lines and test answers stay English. Report prose, coach notes and the test's Korean prompt are Korean on ko.
sticker / reaction text: none
alt (ko): 한 주 리포트에서 내 문장 위로 자꾸 빠지는 과거형을 짚어 주고, 이어지는 주간 테스트에서 그 실수를 타일로 바로잡은 뒤 결과가 나와요.
alt (en): The weekly report points out the past tense dropping out of the learner's own lines; the weekly test that follows has them rebuild that sentence from tiles, then shows the result.

## 10 — Outro  (v1, approved)
eyebrow: none (number 10 / 10 if the layout shows one)
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app

tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app

screen: `nw-futureself` (speaking), no phone
alt (ko): nawana 워드마크 아래 ‘유창한 나에게 언어를 배우세요.’와 ‘첫 20분은 무료예요’, nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

내 목소리로, 이미 유창한 나와 통화해요.

나와나로 할 수 있는 걸 한 장씩 담았어요.
02 몇 년 뒤의 나와 전화하듯 이야기해요. 틀린 말은 통화 중에 고쳐줘요.
03 원어민 대신 내 목소리로 들으면 ‘나도 되겠는데?’ 싶어져요.
04 Talk: 뉴스, 일상, 내가 만든 상황으로 대화를 시작해요.
05 Watch: 다가올 면접을 유창한 내가 먼저 해내는 걸 봐요.
06 Review: 끝난 통화가 나만의 교재가 돼요.
07 다시 말하기: 같은 통화를 처음부터, 이번엔 제대로 말해요.
08 정해 둔 시간엔 알람처럼 울리고, 받으면 통화가 시작돼요.
09 한 주를 돌아보고, 내 대화에서 나온 문제로 테스트를 봐요.

하나씩 시리즈로 더 자세히 올릴게요.
첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #외국어공부 #nawana

(≈ 420 chars)

## Instagram caption (en)

Talk with the fluent you, in your own voice.

Here's what nawana does, one card at a time.
02 Call yourself, a few years on and already fluent. Slips get fixed mid-call.
03 Hear a line in your own voice and it turns into “I could say that too.”
04 Talk: start from today's news, everyday places, or a situation you set up.
05 Watch: see the fluent you handle next week's interview before you do.
06 Review: every finished call becomes your own book.
07 Say it again: the same call from the top, said right this time.
08 Daily call: it rings like an alarm at the time you pick. Answer and you're talking.
09 Your week, looked back on, then a test made from your own talks.

Each one gets its own post in the series.
Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #languagelearning #nawana

(≈ 790 chars)

## Threads (ko)

원어민 발음을 따라 하다 보면 연기하는 기분 들 때 있지 않아요?

나와나에선 그 목소리가 내 목소리예요. 몇 년 뒤, 이미 외국어가 편해진 나랑 전화하듯 이야기하고, 틀린 말은 통화 중에 바로 고쳐줘요.

다음 주 면접은 유창한 내가 먼저 해 보는 걸 보고 갈 수 있어요. 끝난 통화는 교재가 되고, 같은 통화를 처음부터 제대로 다시 해 볼 수도 있어요. 정해 둔 시간엔 알람처럼 울리고, 한 주가 끝나면 내 대화에서 나온 문제로 테스트도 봐요.

열 장에 모아 봤어요. 첫 20분은 무료예요. nawana.app

(≈ 300 chars, no hashtags)

## Community series entry

cat: start. A NEW entry (founder 2026-10-11); e01 “나와나 한눈에” stays as is.
ko: { title: "나와나로 할 수 있는 것들", tagline: "유창한 나와 할 수 있는 걸 열 장에 모았어요" }
en: { title: "What you can do with nawana", tagline: "Everything you can do with your fluent self, in ten cards" }

---

## Open questions (for the lead)

1. **Daily call on Android.** Card 08 and the captions say it rings like an alarm, even on silent.
   That's true on iOS 26.1+ with AlarmKit. Older iOS gets a notification, and I couldn't verify
   Android's daily call. The captions don't name a platform. If Android doesn't ring through
   silent, either add "iPhone" to card 08 or drop "무음 모드여도 / even on silent" (then the desc
   ends "정해 둔 시간이 되면 알람처럼 울려요. …").
2. **Daily call is opt-in, up to 4 times a day.** "정해 둔 시간 / Set a time" carries the opt-in.
   No copy says it rings for everyone or every day without asking. The title "매일 통화" names the
   feature, not a promise.
3. **Card 05 "면접".** The desc uses the demo's own example. Scenes are counted per month on every
   plan (Light 10 / Plus 30), so no wording says "as many as you want".
4. **Card 07 desc "고친 대로 말하고".** A turn with nothing to fix comes up as you said it, and
   "the way it should go" covers that. If the founder wants it explicit, the alternative tail is
   "내 차례엔 고칠 건 고쳐서 말하고…".
5. **Card 09.** The test is generated only when the week has enough material (a thin week has none).
   The copy says "이어지는 / Then a short test" and never "매주 / every week". The weekly notice is
   off by default, so no "알림이 와요". Round 3: "only that week" was dropped, because the test
   also deals back up to 5 misses from the last 4 tests and builds translate items from the
   profile's recurring mistakes. I didn't use the reviewer's "내가 한 말로만": most test items are
   the fluent self's words and lines (meaning, gap, listen, speak), and translate sentences are
   newly written. "내 대화에서 나와요 / made from your own talks" stays true for all of them
   (nothing comes from a generic bank).
6. **Cover chip "06 Review · 대화가 교재로"** and the title "대화가 교재가 돼요" differ on purpose
   (the chip is a label). Say if the founder wants them identical.
7. **Lengths on the render.** The new ko descs are 55–60 characters and the en descs 120–145, the
   same band as the approved 02/04, which rendered in 2 lines. The longest en title line is "the
   same call, done right" (24 characters, card 07), so please check that it doesn't wrap. A fallback
   is "Say it again\nsame call, done right".
8. **Captions and Threads must be re-approved** (brief risk 14). The en IG caption grew to about
   790 characters, still well under 2,200.
