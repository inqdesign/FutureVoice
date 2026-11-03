# 무료 20분, 리포트 끝의 한 번 더 · copy, 6 cards

Piece: 2026-11-03-free-recharge (1.2.9 / build 129, commit 37d6cc3f). Series eyebrow:
**나와나로 할 수 있는 것**, community cat `start` (new episode — an extension of e01's
"start" lane, not a repeat of it).

The one message: **무료 20분을 다 쓰면, 리포트 끝에서 한 번 더 20분을 무료로 충전할 수
있어요.** Order on the cards: free 20 → what the minutes buy → corrections ride along →
the report (not a paywall) → the one-time recharge (TEXT ONLY) → outro.

Korean written as Korean, English written as English; same meaning, never a gloss.
Conversation lines on screen are MATERIAL and stay English on both versions.
No em dashes anywhere in posted text. The words 체험 / trial appear NOWHERE.
"한 번 더" never appears without "계정당 한 번" on the same card or in the same breath.

**For the designer (hard constraints from status.md / brief):**
- Card 05 carries the offer in TEXT ONLY. No capture, no kit screen of the report's last
  card, no button mockup, nothing that looks like "구독하기 | 20분 무료 충전" UI. Its
  visual is `nw-home`'s ring (the call you can place again), nothing more.
- Card 04 uses `nw-weekreport` for the deck-card look only; avoid any scene whose text
  says "이번 주 / this week" (the trial report is the same deck in trial mode, but the
  framing line would be false here).
- Numbers on any screen are kit sample data; never present them as a user's results.
- Cards 02–04 as 8–12 s MP4 loops; cover + outro PNG; the cover must hold as a still in
  the grid.

---

## 01 · Cover: the first 20 minutes
eyebrow (ko): 나와나로 할 수 있는 것 · 01 / 06
title (ko): 첫 20분은\n무료예요
desc (ko):  내 목소리로 말하는 **유창한 나**와 통화해요.\n깔자마자, 결제 없이 바로요.
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): What you can do with nawana · 01 / 06
title (en): Your first 20 minutes\nare free
desc (en):  Call your **fluent self**, in your own voice.\nRight after install, no payment first.
footer (en): Swipe → · nawana.app

screen: `nw-phone` + `nw-call` — a live call, a couple of turns already on screen, the pill lit. Must read as a still.
material on screen (English): e.g. `say("So, what's your week looking like?")`, `user("Pretty busy. I have a meeting with my team tomorrow.")`
alt (ko): 통화 화면이에요. 미래의 나 라벨 아래 대화 몇 줄이 영어로 오가고, 아래에 켜진 픽셀 알약이 보여요. 위에는 첫 20분은 무료라는 제목이 있어요.
alt (en): A live call screen: a few English lines back and forth under the "Future self" label, the lit pixel pill below, and the title saying the first 20 minutes are free.

## 02 · What the minutes buy
eyebrow (ko): 나와나로 할 수 있는 것 · 02 / 06
title (ko): 20분 동안\n뭐든 말해요
desc (ko):  자유 대화, 오늘 뉴스, 내가 앞둔 상황까지.\n**탭 한 번**이면 전화가 걸려요.

eyebrow (en): What you can do with nawana · 02 / 06
title (en): Twenty minutes,\nany topic
desc (en):  Free talk, today's news, the situation\nyou're about to face. **One tap** starts the call.

screen: `nw-home` — the Talk tab's ring first, then a slow scroll to the news stories and situations list
motion: ring → scroll down to news cards and scenario rows
alt (ko): Talk 탭이에요. 위에는 통화를 시작하는 큰 링이 있고, 아래로 내리면 오늘 뉴스 카드와 연습할 상황 목록이 이어져요.
alt (en): The Talk tab: a big ring that starts the call on top, then a scroll down to today's news cards and a list of situations to practice.

## 03 · Corrections ride along
eyebrow (ko): 나와나로 할 수 있는 것 · 03 / 06
title (ko): 말하는 동안\n교정이 따라와요
desc (ko):  틀린 문장은 그 자리에서 바로 고쳐져요.\n말한 건 전부 **내 교재**로 남아요.

eyebrow (en): What you can do with nawana · 03 / 06
title (en): Corrections ride\nalong as you talk
desc (en):  A slip comes back put right, on the spot.\nEverything you say becomes **your own book.**

screen: `nw-call` — a learner line with a slip, the fix card blooming under it, the call going on
material on screen (English): `user("I have went there last weekend.")` → fix card `"I went there last weekend."` (was: "have went" → now: "went")
fix card note (native, coaching): ko `지난 일은 went 하나면 돼요.` / en `For last weekend, "went" does it on its own.` (no grammar terms, never "wrong")
sticker option: the correction card as a sticker beside the phone (allowed by the brief)
motion: the fix card blooming in place, the conversation continuing above it
alt (ko): 통화 중에 내가 "I have went there last weekend."라고 말하자, 바로 아래에 고친 문장 "I went there last weekend."가 카드로 떠요. 대화는 그대로 이어져요.
alt (en): Mid-call you say "I have went there last weekend." and a card appears right under it with the line put right, "I went there last weekend." The conversation keeps going.

## 04 · The minutes end in a report
eyebrow (ko): 나와나로 할 수 있는 것 · 04 / 06
title (ko): 다 쓰면\n리포트가 나와요
desc (ko):  어떻게 썼는지, **내가 말한 시간에서 읽은 레벨**,\n볼 수 있는 시험, 이어갈 루틴까지요.

eyebrow (en): What you can do with nawana · 04 / 06
title (en): Spend them all,\nget a report
desc (en):  How the minutes went, **a level read from your\nown speaking**, a test to take, a routine to keep.

screen: `nw-weekreport` — deck cards only (cover card + a numbers card feel); AVOID any scene with "이번 주 / this week" framing text
motion: one card sliding to the next in the deck
alt (ko): 카드 덱으로 된 리포트 화면이에요. 말한 시간과 숫자가 담긴 카드가 한 장씩 넘어가요. 숫자는 예시예요.
alt (en): A report shown as a deck of cards, each card carrying the minutes and numbers from the sample data, sliding one to the next.

## 05 · One more at the report's end (TEXT ONLY — never draw the offer UI)
eyebrow (ko): 나와나로 할 수 있는 것 · 05 / 06
title (ko): 리포트 끝에\n한 번 더 20분
desc (ko):  20분을 한 번 더 **무료로 충전**할 수 있어요.\n계정당 한 번이에요.

eyebrow (en): What you can do with nawana · 05 / 06
title (en): One more twenty,\nat the end
desc (en):  The report ends with **one more free recharge**\nof 20 minutes. Once per account.

screen: `nw-home` — the Talk tab's ring, still or gently breathing (the call you can place again is what the recharge buys). NO offer UI, NO report last card, NO button.
alt (ko): Talk 탭의 큰 링이에요. 전화를 다시 걸 수 있다는 뜻으로, 충전된 20분이 사주는 것을 보여줘요.
alt (en): The Talk tab's big ring, the call you can place again: what the recharged 20 minutes buy.

## 06 · Outro (fixed)
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

무료 20분을 다 쓰면, 리포트 끝에 20분이 한 번 더 있어요.

나와나는 깔자마자 내 목소리로 말하는 유창한 나와 통화해요.
자유 대화도, 오늘 뉴스도, 앞둔 상황도 탭 한 번이면 전화가 걸려요.
틀린 문장은 그 자리에서 고쳐지고, 전부 내 교재로 남아요.
20분을 다 쓰면 리포트가 나와요. 내가 말한 시간에서 읽은 레벨까지요.
그리고 리포트 끝에서 20분을 한 번 더 무료로 충전할 수 있어요. 계정당 한 번이에요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #영어앱 #nawana

(≈ 330 chars)

## Instagram caption (en)

Spend your free 20 minutes, and one more twenty waits at the end of your report.

nawana puts you on a call with your fluent self, in your own voice, right after install.
Free talk, today's news, the situation you're about to face. One tap starts the call.
Slips come back put right, and everything you say becomes your own study book.
When the minutes run out, you get a report: how they went, a level read from your own speaking, a test, a routine.
And at the report's end, you can recharge 20 more minutes free. Once per account.

Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #languagelearning #englishapp #nawana

(≈ 760 chars)

## Threads (ko)

나와나는 첫 20분이 무료예요. 깔자마자 내 목소리로 말하는 유창한 나와 통화해요.

20분을 다 쓰면 리포트가 나와요. 앱을 어떻게 썼는지, 내가 말한 시간에서 읽은 레벨, 볼 수 있는 시험, 이어갈 루틴까지요. 그리고 리포트 끝에서 20분을 한 번 더 무료로 충전할 수 있어요. 계정당 한 번이에요.

첫 20분은 무료예요. nawana.app

(≈ 230 chars)

## Threads (en)

nawana gives you 20 free minutes the moment you install it: a call with your fluent self, in your own voice.

When they run out you get a report, not a blank payment screen. How the minutes went, a level read from your own speaking, a test you can take, a routine to keep going. And at the end of that report, one more free recharge of 20 minutes. Once per account.

Your first 20 minutes are free. nawana.app

(≈ 450 chars)

## Community series entry (new episode)

cat `start`, suggested id `e20` (next free; e06 is the tutor slot). Extends the start
lane: e01 is the whole app at a glance, this one is the free way in. Editing
`series.json` changes the live site → founder approval. No separate community NEWS post:
release news for 1.2.9 is `beta.sh`'s (no duplicates).

ko: { title: "무료 20분", tagline: "다 쓰면 리포트가 나오고, 끝에 한 번 더 있어요" }
en: { title: "20 free minutes", tagline: "They end in a report, with one more at the end" }

one-message line: 무료 20분을 다 쓰면, 리포트 끝에서 한 번 더 20분을 무료로 충전할 수 있어요.
one-message line (en): Spend the free 20 minutes, and the report ends with one more free recharge of 20.

---

## Open questions (for the lead)

1. **Switch check before posting.** The recharge size is `billing_config.free_recharge_seconds`
   (0 = no button). Reviewer must confirm it is live at 1200 (20 min) on publish day, per the
   brief's risk list. The copy hard-codes "20분"; if the value moves, the piece is stale.
2. **Card 05 title says "20분" twice on the slide** (title "한 번 더 20분" + desc "20분을 한 번
   더"). Deliberate: the desc is where "무료로 충전" and "계정당 한 번" live, and the title
   alone must not promise the amount without the once-per-account limit nearby. Trim if the
   designer finds it heavy.
3. **"결제 없이" on the cover.** Second line of the desc, after the gain, so it keeps
   positive-first. It answers the exact objection the primary audience has (apps that open on
   a subscription ask). Say if the reviewer reads it as a loss-first line.
4. **Series id.** I proposed `e20` cat `start`; `series.json` currently ends at e19 and e06 is
   reserved for the tutor refresh. Confirm before the designer names slide files.
5. **Old builds.** RESOLVED (review item 3): the "업데이트하고 열어보세요 / 리포트가 기다려요"
   re-engagement line was removed everywhere — the report re-raises at most twice per install,
   so the promise is false for accounts that already saw it. The piece is pure acquisition now.
6. **Approval.** Captions, Threads, and the series entry need the founder's OK before posting
   (autopilot still routes through the veto window).
