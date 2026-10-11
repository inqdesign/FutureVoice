# Brief — 나와나로 할 수 있는 것들 (series cover)

> Written after the fact. The message and the outline below (v2, ten cards, 2026-10-11) were shaped by the
> founder over many rounds and are FIXED; this brief records them and fills the gaps
> (audience, why now, proof, channels, risks, success). Nothing here redesigns the piece.

## One message

나와나에서는 내 목소리로 유창하게 말하는 '몇 년 뒤의 나'와 통화하며 외국어를 연습해요.
그 밖에 할 수 있는 건 이 시리즈에서 하나씩 보여 줘요.

## Who it's for

The person scrolling Instagram on the subway home who already studies English on and off —
can build a sentence, stumbles out loud, has tried a phone-English service or a chat app
and felt like they were performing for a stranger. They see "유창한 나와 대화를 한다고?"
and stop because it sounds strange. They don't know nawana yet; this is their first look.
Honest floor: not absolute beginners (the call card shows someone forming whole sentences
and getting one tense fixed — keep it that way).

## Why now

It is the cover of the feature series "나와나로 할 수 있는 것" — the first post on
Instagram/Threads and the head of the series on the community page. Every later piece
(each card 05–09 can grow into its own episode; Speech + challenges is its own episode — see backlog) points back to it,
so it has to say what the app is in ten cards, and introduce the series format (fixed
text block, live screen below) the following pieces reuse.

Relation to the community archive: `web/community/series.json` already has e01 "나와나 한눈에"
and e02–e19 (older screenshot renders). This piece is the new-format restart of that
series, not a repeat of e01 — the publisher must decide with the founder whether it
replaces e01 or sits as a new entry (see Risks).

## Outline (fixed, v2 — 10 cards) and proof in the app

> 2026-10-11 founder: the 6-card version was "너무 빈약하다". Ten cards, one carousel; Speech is
> dropped (its own episode later, with challenges once shipped). Cards 02–04 are unchanged from
> v1 (copy, kit script and renders in `renders-v1/` are reusable). Every pose/beat named below is
> one the kit actually renders (`web/kit/screens/*.js`: `static poses` + `demo()` beats). No final copy here.

The one message is unchanged. 05–09 follow the loop the app is built on: before a situation
(05 Watch) → after a talk (06 Review, 07 Say it again) → every day (08 Daily call) → every week
(09 Report + test). Each card should land on "it came out of YOUR talk, in YOUR voice".

| # | Card | The one point | Kit screen · demo beats / poses that show it | Facts to keep true (CLAUDE.md) |
|---|---|---|---|---|
| 01 | Cover | 나와나로 할 수 있는 것들 — series contents, now 02–09 | Futureself mosaic speaking (clipped, light) + chip list arriving one by one. 8 chips instead of 4: needs a tighter list than v1 | — |
| 02 | 유창한 나와 대화를 한다고? (keep v1) | 몇 년 뒤의 나와 전화하듯, 어색한 말은 통화 중에 바로 고쳐 줘요 | `nw-call`: opener, "try saying" coach line, learner says "It was a busy week. I go to…", correction card (went, 과거형) lands just after the reply starts, fluent self answers, goal chips tick | Talk (phone-call mode, `{reply, suggestion}`), "A turn is answered TWICE", correction card shows with the voice, Coach mode "try saying", notebook chips (`TalkGoalChips`) |
| 03 | 왜 원어민 말고 내 목소리일까? (keep v1) | 원어민을 따라 하면 연기 같고, 내 목소리면 '나도 이렇게 말할 수 있구나' | Compare sticker: same sentence, AI native voice vs 유창한 나 (Futureself), two reactions | Voice clone (ElevenLabs), "speaker similarity is the product"; BRAND native-speaker framing |
| 04 | Talk · 하고 싶은 대화로 (keep v1) | 링 = 자유 대화; 뉴스 / 카페·병원 같은 일상 / 내가 만든 상황 | `nw-home`: ring tap, scroll, News · Everyday · Scenarios tabs, a row tapped in each | `ConversationHome`, `NewsTopicSection.Tab` (news/everyday/scenarios), `StarterSituations` (At a café, Calling a clinic …) |
| 05 | Watch · 일어나기 전에 미리 보기 | Describe the real thing coming up (next week's interview) and watch the fluent you handle it first. | `nw-watch` demo — beat 1: the "Your own situation" box, dictated by mic ("다음 주 목요일 디자인 직무 패널 면접…"), CTA lights and is tapped · beat 2: "대화를 쓰는 중…", then the interview scene plays line by line (Interviewer / Future self, current line ringed) · beat 3: bar turns to Watch again · Study this, "Shadow this" tapped. Poster: pose `playing`. Also available: `dictating`, `composer-attached` (box with material chips), `scene` (cafe "The wrong order" — the Common-situations door; don't mix both doors in one card). | Watch = simulate a situation BEFORE it happens; two doors (your own situation / common situations). The fluent self's lines are in your cloned voice; the counterpart is a preset voice, never a clone. Scenes are COUNTED per month on every plan (Light 10, Plus 30). The demo dictates text only — "it reads the posting/CV" only if the card shows an attachment (`composer-attached`). A saved situation replayed writes a fresh take. |
| 06 | Review · 대화가 교재가 돼요 | Every talk becomes your own book: its words and expressions, your sentences fixed into cards, lines to shadow. | `nw-review` demo — beat 1: Studying shelf → tap the talk's book card → book cover (`nw-bookpage`) · beat 2: Words, then Expressions ribbons · beat 3: Drill ribbon (said line struck → fixed line, fix highlighted, why) · beat 4: "Review this talk" → sentence card answered aloud, tapped to reveal, filed into Tomorrow. Shadow chapter only via `nw-bookpage` `open("shadow")` (not in nw-review's demo) — add it only if the card names shadowing. Poses: `studying`, `bookcover`, `words`, `expressions`, `drillchapter`, `card`, `revealed`. | Made automatically from the talk (TalkCurriculum, derived at read time). Four chapters: Words · Expressions · Drill (sentence cards) · Shadow. One card per FIX; a clean turn mints none. Expressions include ones the fluent self used, not only yours. "Got it" retires a card; nothing expires. PDF export exists but isn't on screen — leave it out. |
| 07 | Say it again · 같은 통화를 다시, 제대로 | Do the same call again from the start: your part comes up the right way, you say it, the fluent you answers exactly as it did. | `nw-sayagain` demo — intro dissolves · beat 1: fluent-self line · beat 2: prompter "고친 대로 말해 보세요" with "it **went** really well" → read → scored 92 · beat 3: next answer · second line read → 61 with "들린 말" · beat 4: finish "2문장 중 2문장 읽음 · 평균 76점". Poster: pose `reading`. Also `intro` (its text says "이 대화를 처음부터 다시 해요…대답은 그때 그대로"), `done`. | It is the WHOLE conversation, not a corrections list: corrected turns come up corrected, the rest come up as said. Answers are the original call audio, nothing re-synthesized, not metered (true, but not this card's point). Never stops on a weak read; Retry exists. Watch scenes have the same button (optional). |
| 08 | Daily call · 알람처럼 울려요 | At the time you set, your fluent self calls — it rings through silent mode, and answering opens the call with its question. | `nw-ring` demo — beat 1: locked phone, alarm screen ringing ("Future Jiwoo", 8:00, Answer + slide to stop) · beat 2: Answer → `nw-call` · beat 3: "Morning! You had the interview yesterday, right? How did it go?" → learner answers → follow-up · beat 4: another morning, slid away; the next set time (13:00) rings anyway. Poster: pose `ring`. Also `answered`, `again`. | An AlarmKit ALARM screen and must look like one — never drawn or called an incoming-call screen. Rings through silent mode/Focus on iOS 26.1+ (older iOS: a notification). Opt-in; up to 4 times a day. The first line is written from your last talk and ends in a question (the "it remembers" beat). Declining = just not answering: no scold, no callback, streak untouched, a missed call leaves NO banner. The ring is a phone tone, not your voice; the voice starts when you answer. |
| 09 | 한 주 돌아보기 + 주간 테스트 | Once a week your week comes back: what you said, what became yours, the mistake you keep making — then a short test built only from that week. | Two halves on one phone: `nw-weekreport` demo beats 1–3 (cover: active days + summary → used / became yours → coach "Past tense drops out halfway through a story" over your own lines) and beat 4 (last card hands off to the test), then `nw-weeklytest` demo beats 1–4 (a word from your week → a phrase the fluent self used → your repeated mistake rebuilt from tiles from a Korean prompt → result 6/7 with the miss listed). Both demos in full exceed a 12 s loop — designer cuts, e.g. report 1 + 3, test 3 + 4. Poses: report `week`, `grammar`, `coach`, `test`; test `word-right`, `translate-right`, `result`. | Every test item comes from the learner's own material (talk books, offered expressions, correction cards, the report's coach) — never "a generic bank". Graded in code. The TEST has no streak flame and no gauge (BRAND); the REPORT cover does show a streak flame — keep it on the report half. Report arrives with the test's opening (learner-set day, default Sat 10:00) and slides up once. A thin week (<5 items) has no test. Misses come back in later tests. |
| 10 | Outro | 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 · nawana.app | Futureself speaking, wordmark (keep v1 06) | `AccountStatus.freeGrantSeconds = 1200`; no trial. |

Stickers/comparison: card 03 stays the only comparison. Card 07's prompter already shows the
fix highlighted; add a "내가 한 말 → 고친 말" sticker only if it's unreadable at feed size.

## Channels

- **Instagram carousel** (main): 10 items (limit 20), 1080×1350. Cover and outro as PNG (cover must read
  as a still in the grid); 02–09 as 8–12 s MP4 loops from `carousel.html?solo=N`.
  Caption hook = the strangeness ("내 목소리로 유창하게 말하는 나와 통화해요"), then one line
  per card, then "시리즈로 하나씩 올릴게요"; 3–5 hashtags.
- **Threads**: same 10 items (the Threads cap), a shorter conversational text (not the IG caption).
- **Community series**: the series entry for this piece (720×900 JPGs, video slides where the
  page supports them), same day as Instagram, `cat: start`. Founder approval (live site).
- Nothing else; no Reel/Story until that format is set up.

## Risks — check before packaging

1. **Daily call as drawn is iOS** (AlarmKit, iOS 26.1+; older iOS gets a notification). Android's
   daily call was not checked — verify before a caption speaks to Android users. Never write it as
   an incoming call screen ("전화 화면이 떠요"); "알람처럼 울리고, 받으면 통화가 시작돼요" is the true shape.
2. **Daily call is opt-in** (onboarding / Me → Call), max 4 times a day. Copy must not imply it rings
   for everyone after install.
3. **Watch scenes are counted** (Light 10 / Plus 30 a month). Never "무제한" / "원하는 만큼".
4. **Say it again ≠ "틀린 문장만 다시".** The kit's 2-turn demo shows only corrected turns, so the copy
   has to carry "the whole conversation", or readers take it for a corrections drill.
5. **Weekly test: no flame, no gauge** (BRAND). The report's cover streak flame is real; the cut must
   not put it beside the test. No promise of a test every week regardless (thin week = none).
6. **Weekly notice is off by default** — don't write "매주 알림이 와요"; "한 주가 끝나면 열려요" is fair.
7. **Review**: "대화가 끝나면 자동으로 교재가 돼요" is true; stay with the four chapters on screen.
8. **"내 목소리" vs the clone cap** (v1): onboarding can finish on a preset voice when the month's
   voice slots are full. Cards 02/03/05/08 rely on your own voice — true in the normal case; never
   "가입하자마자 바로".
9. **Compare card (03)** — unchanged: about how imitation FEELS, never "native voices are worse".
10. **"첫 20분은 무료예요"** — re-check `freeGrantSeconds` on posting day; never "무료 체험".
11. **Card 02 sample details** (coach line, chips) — v1 risk stands; no "매 턴 답할 말을 알려줘요".
12. **All on-screen numbers and names are kit sample data** (92 / 61 / 76, 6/7, streak, "Future Jiwoo").
13. **Cover chips 4 → 8** — check legibility at feed size; shorten labels rather than shrink type.
14. **Captions / Threads were approved for 6 cards** — must be rewritten for 05–09 and re-approved.
    Threads holds exactly 10 items: nothing can be added to this carousel.
15. **Community**: still a NEW entry (founder decision); `renders-v1/` is not to be published.

## Success signal

- Instagram: saves and shares per reach (a cover is saved to come back to the series),
  profile visits and link taps to nawana.app in the 72 h after posting; follows from the post.
- Threads: replies — especially "내 목소리로 어떻게?" style questions, which feed the next
  pieces.
- Community: views of the series entry; and in PostHog, onboarding starts with a referrer
  from nawana.app/community or the IG link in the week after (compare with the week before).
- Later pieces: does the series' second post keep the cover's reach (series retention).

## Later (suggestions only — not part of this piece)

- Speech (with challenges, once shipped) is its own episode, not a card here.
- Each of 05–09 can later become its own episode that this cover points to.
- The compare card could later become its own episode with real audio (Reel), once that
  format exists.
