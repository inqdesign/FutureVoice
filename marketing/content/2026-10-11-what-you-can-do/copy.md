# 몇 년 뒤의 나에게 배워요 · copy (v4, 9 cards, the core flow only)

Rewritten 2026-10-13 for the founder's cut (status.md, "this piece = the CORE FLOW only"). One
story about talking and nothing else: the problem (입이 안 떨어진다) → the answer (몇 년 뒤의 나에게
배워요) → it's my own voice → I tell it what's on my mind, at ease → it fixes what I said → it
offers what I could say → the call becomes a book → its chapters make it mine → next time, it
remembers what I told it. Watch, Talk topics, Say it again, the daily call and the weekly
report/test are gone from every line (they are later episodes).

Every Korean line was written as Korean from the intent, every English line separately as
English. 해요체, no 당신, no em dash in any post text.

**Eyebrow decision: "nawana · NN / 09" on every card.** No single stage word fits all nine
(02 is the voice, 06 to 08 happen after the call), and the cover's chips already index the story.

Length: ko descs 45 to 60 characters, en descs 95 to 140, inside the band measured at 2 lines.
Titles at or under ~9 Hangul per line.

**Korean clarity pass (2026-10-14, founder: "무슨 말인지 모르겠는 말이 많아").** Korean only; every
English line is unchanged. Re-render ONLY these ko cards: **01** (chips 03, 05, 07, 08), **02**
(desc), **03** (title, desc), **05** (title, desc), **07** (title, desc), **08** (desc). 04, 06, 09
unchanged. Captions, Threads and the community tagline were rewritten too.

**English clarity pass (2026-10-14, founder wants an English version of every piece).** English
only; Korean untouched. Plain spoken English, same claims as the Korean after its clarity pass,
titles ≤ ~22 chars a line, descs ≤ ~110 chars. Re-render ONLY these en cards: **01** (title, desc
line 2, chips 03, 05, 06, 07), **02** (title, desc), **03** (title, desc), **05** (title, desc),
**07** (title, desc), **08** (desc). 04, 06, 09 unchanged. IG caption (en) rewritten; Threads (en)
added as the root post of the English series thread.

**For the designer (v4 changes to `carousel.html`):**
- **Card count 10 → 9.** Every eyebrow becomes `nawana · NN / 09` (cover `nawana · 01 / 09`).
- **Old → new mapping:**
  - old 01 cover → **new 01** (title and desc unchanged; seven new chips for 02 to 08, new alt)
  - old 02 two voices → **new 02** (eyebrow, plus the v4.2 changes below)
- **v4.2 card 02 (founder, 2026-10-13): the comparison is an AI TUTOR vs me, not a native speaker vs me.**
  - desc ko/en: new (see card 02). Re-check 2 lines.
  - left label: `AI 원어민 음성` → **`AI 튜터`**, sub `남의 목소리` unchanged · en `AI native voice` → **`AI tutor`**, sub `someone else's` unchanged. Right label unchanged (유창한 나 · 내 목소리 / Fluent you · your voice). Both places in `carousel.html` (the static row and the `L` labels).
  - the sentence: “Keep talking with me, a little every day. The words will come. One day, you'll sound just like this.” (in `.q` / `.sent`). Two sentences now: check it fits, break after “English.” if it wraps.
  - **audio must be re-made**: `audio/2-native.mp3` and `audio/3-clone.mp3` say the old sentence only. New takes of the full sentence (tutor voice, then the founder's clone), then re-measure the rings, the mosaic envelope and the mux points; render length will grow.
  - the reactions, if they are still drawn anywhere: “따라 하면 연기하는 것 같아. 나 같지가 않아” / “Copying this feels like acting. It's not me.” still fit a tutor's voice; keep.
  - old 03 call → split into **new 03 / 04 / 05**, all on `nw-call`:
    - **03** the call itself: opener → learner answers at length (cut before the correction lands, or keep it small; the point is the open, easy talk)
    - **04** the correction: the reply starts first, then the correction card under the learner's line (went, 과거형, with its reason). Poster = correction card + reply.
    - **05** the coach (coach mode on, as the desc now says): the "이렇게 말해 보세요" line under the pill while the learner thinks, and the "써 볼 단어 · …" hint ticking to "썼어요" when it's said. Poster = suggestion line showing.
  - old 06 book (`nw-review`) → split into **new 06 / 07**:
    - **06** shelf → tap the talk's book → book cover (`nw-bookpage`). Poster = book cover.
    - **07** the book's four chapters: Words → Expressions → Drill (the grammar fixes, struck → fixed) → Shadow (`open("shadow")`) → a sentence card answered out loud. Poster = Drill chapter or the card answered aloud.
  - **new 08** needs a NEW scene: a new call (`nw-call`) that opens on an ordinary, timeless line (a free talk's opener is never a memory), and the memory shows in the fluent self's REPLY: the learner says they got a call, and the fluent self brings up the interview from 03 to 05 before the learner names it. Lines below (v4.1).
  - old 04 Talk home, 05 Watch, 07 Say it again, 08 daily call, 09 week + test → **removed** (renders kept for the later episodes).
  - old 10 outro → **new 09** (unchanged text).
- The side index list (`data-go`) follows the new titles.
- **v4.1 call lines (designer, 2026-10-13, lead's continuity fix): the calls are the SAME talk as the kit's sample book on 06/07 (the job interview, "Honestly, it went really well…").** Material, English:
  - 03 fluent self: "Hey, it's you, a few years from now. So, how did the interview go?" · learner: "Honestly, it go really well. I felt prepared."
  - 04 correction (the book's first Drill fix): "Honestly, it **went** really well. I felt prepared." · note (ko) 지난 일이라 과거형이에요 / (en) It already happened, so past tense. · fluent self: "Nice, you sound relieved! Which question was the hardest?"
  - 05 Try saying: "The one about [my weak points]. I took the initiative there." · ko gloss: [내 약점]에 대한 질문. 거기선 내가 먼저 나섰어. · Try using · **took the initiative** (one of the book's expressions) → Used it · learner: "The one about my weak points. I took the initiative and tell a real story."
  - 08 fluent self: "Hey! How's your week been?" · learner: "Good! They call me yesterday." · fluent self: "About the interview? Did you get it?" · learner: "Yes! I got the job." · fluent self: "No way, congrats! So when do you start?"
  - Chips on the call: felt prepared · took the initiative · what mattered most.
  - The per-card "material on screen" lines, ALT texts and captions below all match these lines (2026-10-13, round 5 copy fixes). Nothing in this file refers to the old busy-week call any more.

---

## 01 · Cover: the problem, then the answer; mosaic speaking, seven beats slide in
eyebrow (ko): nawana · 01 / 09
title (ko): 머리론 아는데\n입이 안 떨어져요
desc (ko):  **몇 년 뒤의 나에게 배워요.**\n내 목소리로 유창하게 말하는 나와 통화해요.
chips (ko):
  02 내 목소리 그대로
  03 하고 싶은 말을 편하게
  04 한 말은 고쳐 주고
  05 막히면 할 말을 알려 주고
  06 통화가 교재로
  07 소리 내어 익히고
  08 내 얘기를 기억해요
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): nawana · 01 / 09
title (en): You know it.\nYou just can't say it.
desc (en):  **Learn from yourself, a few years from now.**\nGet on a call with a fluent you, in your own voice.
chips (en):
  02 Still your voice
  03 Say what's on your mind
  04 It fixes what you said
  05 Stuck? It gives you a line
  06 Each call becomes a book
  07 Practice it out loud
  08 It remembers your story
footer (en): Swipe → · nawana.app

screen: no phone. `nw-futureself` (speaking) + chip list
alt (ko): ‘머리론 아는데 입이 안 떨어져요’ 제목 아래 ‘몇 년 뒤의 나에게 배워요’가 있고, 미래의 나 모자이크가 말하는 동안 02~08장 목차가 하나씩 나타나는 표지예요.
alt (en): Cover: "You know it. You just can't say it." over "Learn from yourself, a few years from now." The fluent-self mosaic speaks while the contents for cards 02 to 08 appear one by one.

## 02 · One sentence, two voices: an AI tutor, then me (v4.2)
eyebrow (ko): nawana · 02 / 09
title (ko): 몇 년 뒤의 나,\n목소리는 그대로
desc (ko):  AI 튜터 목소리로 들으면 멀게만 느껴져요. 내 목소리로 들으면 **어, 나도 되겠는데?** 싶어요.

eyebrow (en): nawana · 02 / 09
title (en): Years from now,\nstill your voice
desc (en):  In an AI tutor's voice, a line feels far away. In your own, you think: **wait, I could say that.**

screen: two-voice compare (labels and sentence change, see designer notes v4.2)
on-card text: “Keep talking with me, a little every day. The words will come. One day, you'll sound just like this.” · AI 튜터 · 남의 목소리 | 유창한 나 · 내 목소리 (en: AI tutor · someone else's | Fluent you · your voice)
sound: the AI tutor's voice, then the clone, both saying the new sentence (re-recorded)
sticker / reaction text: none
alt (ko): 같은 영어 문장을 AI 튜터 목소리로 한 번, 내 목소리를 닮은 유창한 나로 한 번 들려주고, 끝에 유창한 나 쪽이 파랗게 표시돼요.
alt (en): One English sentence is played twice, first by an AI tutor, then by the fluent you in your own voice, which is highlighted at the end.

## 03 · The call: telling myself what's on my mind
eyebrow (ko): nawana · 03 / 09
title (ko): 상대가 나라서\n편하게 말해요
desc (ko):  통화 상대는 몇 년 뒤의 나예요. 더듬거려도 하고 싶던 얘기를 **끝까지** 해요.

eyebrow (en): nawana · 03 / 09
title (en): It's just you,\nso talk freely
desc (en):  It's you on the other end, a few years from now. Stumble all you like and **get the whole story out**.

screen: `nw-call`, opener → the learner's answer (see designer notes)
material on screen (English in both versions):
- fluent self: "Hey, it's you, a few years from now. So, how did the interview go?"
- learner: "Honestly, it go really well. I felt prepared."
alt (ko): 통화 화면에서 미래의 내가 먼저 자기를 소개하고 면접은 어땠는지 영어로 물어요. 학습자는 잘 봤다고, 준비가 돼 있었다고 영어로 답해요.
alt (en): On a call, the fluent self introduces itself and asks in English how the interview went. The learner answers that it went well and they felt prepared.

## 04 · It fixes what I said (the card arrives with the voice)
eyebrow (ko): nawana · 04 / 09
title (ko): 내가 한 말,\n고쳐서 보여줘요
desc (ko):  대답이 들리면 내가 한 말 아래에 고친 문장이 떠요. 어디를 **왜 고쳤는지**도 알려 줘요.

eyebrow (en): nawana · 04 / 09
title (en): It fixes\nwhat you said
desc (en):  As the answer plays, a better version of your line shows up under it, with **what changed and why**.

screen: `nw-call`, reply first, then the correction card
material on screen:
- correction: "Honestly, it **went** really well. I felt prepared." · note (ko): 지난 일이라 과거형이에요 · note (en): It already happened, so past tense.
- fluent self: "Nice, you sound relieved! Which question was the hardest?"
alt (ko): 미래의 내가 대답하기 시작하면, 학습자가 한 말 아래에 과거형으로 고친 문장과 그 이유가 떠요.
alt (en): As the fluent self starts answering, a past-tense fix of the learner's line appears under it, with the reason.

## 05 · It offers what I could say (the coach line under the pill)
eyebrow (ko): nawana · 05 / 09
title (ko): 말이 막히면\n할 말을 알려 줘요
desc (ko):  코치 모드를 켜면 답을 고민하는 동안 **이렇게 말해 보세요**가 떠요. 외우던 단어도 써 보라고 알려 줘요.

eyebrow (en): nawana · 05 / 09
title (en): Stuck for words?\nIt gives you a line
desc (en):  With coach mode on, a line to **try saying** shows up while you think, plus a word you're learning to use.

screen: `nw-call`, coach beat
material on screen (English in both versions, labels per language):
- fluent self: "Which question was the hardest?"
- 이렇게 말해 보세요 / Try saying: "The one about [my weak points]. I took the initiative there." · ko gloss: [내 약점]에 대한 질문. 거기선 내가 먼저 나섰어.
- 써 볼 단어 / Try using · **took the initiative** → 썼어요 / Used it when the learner says it
- learner: "The one about my weak points. I took the initiative and tell a real story."
alt (ko): 학습자가 답을 생각하는 동안 알약 아래에 ‘이렇게 말해 보세요’ 문장과 써 볼 단어가 뜨고, 그 단어를 말하자 ‘썼어요’로 바뀌어요.
alt (en): While the learner thinks, a "Try saying" line and a word to try appear under the pill; when the word is said, it turns to "Used it".

## 06 · The call becomes a book
eyebrow (ko): nawana · 06 / 09
title (ko): 통화 한 번이\n교재 한 권
desc (ko):  통화가 끝나면 그 대화가 **나만의 교재**가 돼요. 내가 한 말과 유창한 내가 쓴 말이 그대로 담겨요.

eyebrow (en): nawana · 06 / 09
title (en): One call,\none book
desc (en):  When a call ends, it becomes **your own book**, built from what you said and what the fluent you said back.

screen: `nw-review` shelf → book cover (`nw-bookpage`)
alt (ko): 복습 탭의 교재 칸에서 방금 끝난 통화의 교재를 눌러 표지를 열어요.
alt (en): On the Review tab, the book from the call that just ended is tapped open to its cover.

## 07 · Its chapters make it mine, out loud
eyebrow (ko): nawana · 07 / 09
title (ko): 소리 내어\n익혀요
desc (ko):  단어, 표현, 고친 문장, 섀도잉을 하나씩 익혀요. 문장 카드는 **소리 내어 답하면서** 복습해요.

eyebrow (en): nawana · 07 / 09
title (en): Practice it\nout loud
desc (en):  Go through the words, phrases, fixed sentences and shadowing. Review sentence cards by **answering out loud**.

screen: `nw-review` / `nw-bookpage` chapters (see designer notes)
alt (ko): 교재의 단어, 표현, 문법을 고친 문장, 섀도잉 장을 차례로 넘기고, 문장 카드를 소리 내어 답해요.
alt (en): The book's four chapters go by, words, expressions, grammar fixes and shadowing, then a sentence card is answered out loud.

## 08 · It remembers what I told it (a new call opens on it)
eyebrow (ko): nawana · 08 / 09
title (ko): 내 이야기를\n기억해요
desc (ko):  통화에서 한 내 얘기를 기억했다가 **다음 통화에서 꺼내요**. 뭘 기억하는지 직접 보고 고칠 수도 있어요.

eyebrow (en): nawana · 08 / 09
title (en): It remembers\nyour story
desc (en):  It remembers what you share and **brings it up on your next call**. You can see and edit what it keeps.

screen: NEW `nw-call` scene (see designer notes)
material on screen (English in both versions):
- fluent self: "Hey! How's your week been?"
- learner: "Good! They call me yesterday."
- fluent self: "About the interview? Did you get it?"
- learner: "Yes! I got the job."
- fluent self: "No way, congrats! So when do you start?"
alt (ko): 새 통화에서 학습자가 어제 연락을 받았다고 하자, 미래의 내가 지난번 면접 이야기를 먼저 꺼내며 붙었는지 영어로 물어요. 합격했다는 말에 축하하고 언제부터 일하는지 물어요.
alt (en): In a new call, the learner mentions they got a call yesterday, and the fluent self brings up last time's interview before they do, asking if they got it. Told they got the job, it congratulates them and asks when they start.

## 09 · Outro (unchanged)
eyebrow: none (09 / 09 if the layout shows one)
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

머리로는 아는데, 막상 입이 안 떨어져요.
그래서 몇 년 뒤의 나에게 배워요.

목소리는 지금 내 목소리 그대로, 외국어만 유창해진 나예요.
AI 튜터 목소리로 들으면 멀게만 느껴지는데, 내 목소리로 들으면 '어, 나도 되겠는데?' 싶어요. 두 번째 장은 소리 켜고 들어 보세요.
상대가 나라서 하고 싶은 얘기를 편하게 해요.
대답하면서 내가 한 말을 고쳐 주고, 코치 모드를 켜면 막힐 때 할 말도 알려 줘요.
끝난 통화는 교재가 되고, 단어부터 섀도잉까지 하나씩 익혀요.
다음 통화에선 지난번에 한 내 얘기를 기억하고 있어요.

하나씩 시리즈로 더 자세히 올릴게요.
첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #외국어공부 #nawana

(≈ 420 chars)

## Instagram caption (en)

You know the words. You just can't get them out.
So learn from yourself, a few years from now.

Same voice as you, only fluent.
In an AI tutor's voice, a line feels far away. In your own, you think: wait, I could say that. Sound on for card 2.
It's you on the other end, so you can just talk.
It fixes what you said as it answers, and with coach mode on, it gives you a line when you're stuck.
Every call turns into a book you work through out loud, from words to shadowing.
Next call, it remembers what you told it.

More on each of these, one post at a time.
Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #languagelearning #nawana

(≈ 610 chars)

## Threads (ko)

머리로는 다 아는데, 막상 말하려면 입이 안 떨어질 때 있죠.

그럴 땐 몇 년 뒤의 나한테 말해 봐요. 목소리는 지금 내 목소리 그대로, 외국어만 편해진 나예요. AI 튜터 목소리로 들으면 멀게만 느껴지는데, 내 목소리로 들으면 '어, 나도 되겠는데?' 싶어요. 두 번째 장은 소리 켜고 들어 보세요.

상대가 나니까 서툴러도 편하게 끝까지 말하게 돼요. 한 말은 고쳐 주고, 코치 모드를 켜면 막힐 때 할 말도 알려 주고요. 끝난 통화는 교재로 남고, 다음에 걸면 지난번에 한 얘기를 기억하고 있어요.

첫 20분은 무료예요. nawana.app

(≈ 315 chars, no hashtags, under 500)

## Threads (en) · root post of the English series thread

You know the words, but when it's time to speak, nothing comes out.

So call yourself, a few years from now: same voice, just fluent. A line in an AI tutor's voice feels far away. In yours, it sounds like you could say it. Sound on for card 2.

It's you on the other end, so you keep going when it's messy. It fixes what you said, gives you a line when you're stuck (coach mode), turns each call into a book, and remembers what you told it.

Your first 20 minutes are free. nawana.app

(≈ 490 chars, no hashtags; sound line kept, card 02 has sound like the ko post)

## Community series entry

cat: start. A NEW entry (founder 2026-10-11); e01 “나와나 한눈에” stays as is.
ko: { title: "몇 년 뒤의 나에게 배워요", tagline: "편하게 말하면 고쳐 주고, 소리 내어 익혀요" }
en: { title: "Learn from yourself, a few years on", tagline: "Talk freely, get it fixed, make it yours" }

---

## Open questions (for the lead)

1. **Card 05 now names coach mode** (round 5): desc and all three captions say "코치 모드를 켜면" /
   "with coach mode on". It is on by default for A1/A2 and off from B1. Designer: re-check the
   ko desc still fits 2 lines (≈55 chars, inside the band).
2. **Card 07 lists the book's four chapters** (round 5): 단어, 표현, 문법을 고친 문장, 섀도잉.
   The "out loud" line now says 문장 카드 / Sentence cards, which are the ones answered aloud
   (suggestion j). Designer: re-check 2 lines.
3. **Card 08 claim.** True: `about_user` facts go into the next call's prompt and show in the
   fluent self's REPLIES (the opener is a timeless pooled line), and the learner sees and edits
   them in Me → Profile. The card now shows exactly that.
4. **Titles 04 and 08 both start with "내".** "내가 한 말," (04) and "내 이야기를" (08) are close
   but read as cause and effect in the story; say if one should change.
5. **Captions, Threads and the community entry need the founder's approval again** (new order,
   new cards).
6. **Card 02 is AI tutor vs me now** (v4.2). `marketing/BRAND.md` still says "Native-speaker
   comparison" under Voice; the lead may want that rule reworded to match (not this file's to edit).
7. **Card 02's audio has to be re-recorded** for the new two-sentence line (tutor take + the
   founder's clone take). Which voice plays the "AI tutor": keep the Mark preset take, or a new pick?
