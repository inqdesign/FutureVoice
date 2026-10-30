# brief — coach-suggestion (1.2.2 / build 117)

- **stage:** brief → copy
- **channels:** IG carousel (6 cards) + Threads (first 5) + community series entry (new `e21`, cat `talk`)
- **series:** "나와나로 할 수 있는 것" — a Talk-category piece. Extends the Talk run (e02 전화 한 통, e03 통화 설정, e04 교정, e05 통화가 교재로, e06 튜터 모드). Nothing in the run covers coach mode's **"이렇게 말해 봐"** suggestion — this is new, not a repeat of 교정(e04) (a correction fixes what you *said*; this hands you a line *before* you speak) or 튜터 모드(e06) (that runs a lesson; this is the hint above the pill while you think).
  - Episode id note: `e20` is claimed by the accent-words piece (in progress). This is **e21**. Lead to confirm no collision before the publisher drafts the series entry.

## The one message

통화하다 답이 막히면 위에 **"이렇게 말해 봐"** 한 문장이 떠요 — 이제 그 문장이 지금까지 나눈 대화랑 내 얘기를 알아요. 아무 예문이 아니라, 방금 받은 질문에 딱 맞고 내가 이미 한 말과 어긋나지 않는, **내가 진짜 할 만한 한 문장**. 밑줄 친 곳은 내 얘기예요.

(EN intent, for the en column — copywriter renders natively, never translates: When you freeze mid-call, a "Try saying" line appears up top — and now it reads the whole conversation and the things you've told it. Not a textbook example: a line that answers the question you were just asked, never contradicts what you already said, and sounds like something *you* would actually say. The underlined part is a fact about you.)

If the piece can only land one thing: **the suggested line is built from YOUR conversation and YOUR facts — so it's a sentence you'd actually say, in your own voice, not a generic example.**

Do NOT overclaim: it is a *suggestion of how to answer*, never a correction. Your own sentence always counts.

## Who it's for

The learner who can start a sentence but goes blank the moment a question comes back at them on a call — "…어떻게 답하지?" Concretely: 초·중급 학습자가 영어로 전화하다 "What did you do this weekend?" 같은 질문을 받고 머릿속이 하얘질 때, 위에 내 레벨에 맞는 한 문장이 떠서 숨통이 트이는 사람. Coach mode is on by default when you're starting out, so this is exactly the moment many learners meet first.

Honest floor respected: this is someone who can build a stumbling sentence and needs a scaffold, not an absolute beginner. The piece shows a prompt that helps you answer — it never promises fluency.

**BRAND note (never grade the reader):** do NOT write "초보자용 / for beginners". Present the suggestion as *there when you need it* — appears when you pause, turned on in call settings. The A1/A2-default-on fact is real but internal; don't label the reader.

## Why now

1.2.2 (build 117) ships it — commit `6d8b4f56`, CLAUDE.md "Coach mode" (`CoachSuggester`, `Turn.coachLine`). The "이렇게 말해 봐" line existed before, but was written per-line with little context, so it could drift off-topic or suggest something that contradicted what the learner just said. From this build the suggestion reads the **recent lines of the call** and the learner's **own facts** (their profile + what the fluent self has remembered about them), so it fits the thread and stays consistent with you. Where it uses one of your own facts, that part is **underlined** (drawn faded, like the app's `[brackets]`).

## Proof in the app

- **Screen:** `web/kit/screens/call.js` (`nw-call`), the **coach pose** only. It already renders the "이렇게 말해 보세요 / Try saying" line above the pill with `<u>…</u>` marking the learner's own fact (faded underline). Capture reference: `marketing/captures/call-coach.png`.
- **Behaviour shown is real:** `call.coach({ line, gloss, word })` draws the suggestion (target-language line), its native-language gloss below it, and optionally a "써 볼 단어 / Try using" word chip. The `<u>…</u>` span is the learner's own fact. The kit's default `pose("coach")` already stages the whole thing: two prior turns, the fluent self asking "Do you have a specific place in mind?", the pill on *listening*, and the suggestion **"Yes, I want to try `<u>`the one in Sinjeon`</u>`."** with the ko gloss "응, `<u>`신전떡볶이`</u>` 먹어보고 싶어." — i.e. the suggested answer fits the question AND the underlined place is the learner's own fact. That single pose IS the feature; lean on it.
- **The native gloss is in the reader's language** (Korean, for a Korean audience learning English) and is hidden when native == target. The underline is the ONLY thing the app marks — do not invent any other highlight.
- `call.other` stays unset → the other side is the fluent self ("미래의 나" / "Future self"). The suggestion is a line *you* could say, in your own voice — that's the whole point.
- **Do NOT show a profile / "remembered notes" screen.** There is no such screen in the kit, and those facts are private. The "it knows you" idea lives entirely in the underline on the call screen + the top text block.

## Outline (6 cards)

**Card 1 — Cover** (still PNG; must read in the grid)
- Says: 답이 막혀도 괜찮아요 — 위에 한 문장이 떠요. / Stuck for an answer? One line appears up top.
- Screen: none (cover layout). Series eyebrow + pixel title. Optional sticker: the "이렇게 말해 봐 / Try saying" line peeking from the bottom.

**Card 2 — The moment** (`nw-call`, coach pose; pill on *listening/thinking*)
- Says: 질문을 받고 막히면, "이렇게 말해 봐"가 떠요 — 내 레벨에 맞는 한 문장과, 내 말로 된 뜻. / When a question lands and you freeze, "Try saying" appears — one line at your level, with the meaning in your own language.
- Screen: the coach suggestion visible above the pill, with its gloss. Use the kit's `pose("coach")` as-is or a clean `call.coach({...})`.

**Card 3 — It fits the conversation** (`nw-call`, coach pose showing the prior turn + question)
- Says: 아무 예문이 아니에요. 방금 받은 질문에, 지금까지 한 얘기에 딱 맞춰요. / Not a random example. It answers the exact question, and fits what you've been talking about.
- Screen: keep the fluent self's question in the feed ("Do you have a specific place in mind?") so the suggestion visibly *answers it* ("Yes, I want to try the one in Sinjeon."). The continuity between the question and the line is the proof — don't crop the question out.

**Card 4 — It knows you (the underline)** (`nw-call`, coach pose; emphasis on the `<u>…</u>` span)
- Says: 밑줄 친 곳은 내 얘기예요. 내가 들려준 걸 기억했다가, 그 자리에 넣어줘요. / The underlined part is a fact about you — it remembers what you've told it and drops it in.
- Screen: the suggestion with the underlined own-fact clearly visible (the kit renders it faded/underlined). Emphasis (a circle / arrow on the underline) is a **sticker outside the phone frame** or lives in the top text block — never drawn onto the app screen.
- This is the differentiator card (BRAND: an AI tutor speaks in someone else's voice; the fluent self speaks in *mine*). The line reads "I could actually say that" because it's *my* life, in *my* voice.

**Card 5 — A suggestion, not a rule** (`nw-call`, coach pose; or learner's own turn landing)
- Says: 그대로 말해도 되고, 내 식으로 말해도 돼요. 교정이 아니라 거들어 주는 거예요 — 내가 이미 한 말과도 안 어긋나요. / Say it as is, or say it your way. It's a hand, not a correction — and it never clashes with what you already said.
- Screen: the suggestion still up, or the learner's own answer settling in the feed. Copy must make clear your own sentence counts as the real practice.
- **Guardrail:** no `fix(...)` correction card anywhere in this piece. Coach "Try saying" is NOT a correction; a correction card on screen would say the opposite of the message.

**Card 6 — Outro** (standard outro)
- Wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" · nawana.app. No price claims beyond the free-minutes line.

## Risks / things to check before ship

- **Not a correction.** Every card must frame "이렇게 말해 봐" as help *before* you speak, never as the app marking you wrong. No `fix(...)` card in the render.
- **Your own sentence counts.** Don't imply you must read the suggested line. (CLAUDE.md: making your own sentence is the practice; the suggestion is a scaffold.)
- **Don't grade the reader.** No "초보자용 / for beginners" on any card, even though coach mode is A1/A2-default-on. Present it as there-when-you-pause.
- **The underline is the only app highlight.** `<u>…</u>` = the learner's own fact, drawn faded. Do not invent a colour, a badge, or a "memory" UI. No profile/notes screen.
- **Internal mechanics stay internal.** "recent 8 lines", "profile + remembered notes" are how it works — say it as "the whole conversation + what you've told it", never as a spec/number on a slide.
- **Numbers are illustrative.** Any sample text/score/clock on the screen is kit sample data, never presented as a user result.
- **Keep the demo in English** (target default). The gloss is Korean (reader's language) because native ≠ target; if a card shows a non-English target, don't fake it.
- **Threads text** written fresh (conversational), not the IG caption pasted. Hook: that moment your mind goes blank on a call, and a line you'd actually say shows up.

## Success signal

Afterwards look at: **saves** on the carousel (a "this is exactly my problem" reveal saves well with the stuck-mid-call audience) and comments/DMs from learners describing the freeze moment (demand signal); community `e21` views; profile visits / installs attributed around the post. Secondary, a 2-week read, not launch-day: any uptick in coached-call engagement if a PostHog event exists (`talk_coach`) — informational only, never a public stat.

## Community series entry (for publisher, draft only)

- `id: e21`, `cat: "talk"`, `slides: 6`
- ko: title ≈ "이렇게 말해 봐", tagline ≈ "막히면, 내 얘기에 맞춘 한 문장이 떠요"
- en: title ≈ "Try saying this", tagline ≈ "Freeze up, and a line built from your own story appears"
- (Copywriter finalizes titles/taglines in copy.md; these are placeholders.)
