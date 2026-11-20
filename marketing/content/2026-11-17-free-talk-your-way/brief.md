# brief — free-talk-your-way (1.3.6 / build 149)

- **stage:** brief → copy
- **channels:** IG carousel (5 cards) + Threads (first 5) + community series entry (cat `talk`)
- **series:** "나와나로 할 수 있는 것" — a Talk-category piece, extends the Talk run (e02 전화 한 통, e03 통화 설정, e04 교정, e05 통화가 교재로, e06 튜터 모드, + coach-suggestion/accent-words in flight). This is NEW, not a repeat:
  - 교정(e04) / coach-suggestion = the app offering help *you didn't ask for* (a correction after you speak, a "try saying" line when you pause). THIS piece is the opposite direction: **YOU ask, it does** — you drive the call.
  - 튜터 모드(e06, tutor-goal) = a structured lesson with a checklist the app runs. THIS is **free talk**, no lesson, no checklist — you just say what you want and the conversation bends to it.
  - **Episode id:** next free is likely `e23`, but `e20–e22` are claimed by in-flight pieces and a sibling piece `2026-11-17-free-talk-remembers` is in the same run. Lead to assign + deconflict ids before the publisher drafts the series entries.

## The one message (fixed by the release note — do not re-derive)

자유 대화는 내가 끌어가요. "표현 하나 알려줘", "틀린 데 있으면 짚어줘" 하고 **말로 부탁하면 그대로** 해줘요 — 정해진 수업이 아니라, 내가 하고 싶은 쪽으로 흐르는 통화예요.

(EN intent, for the en column — copywriter renders natively, never translates: In free talk, you run the call. Ask out loud — "teach me an expression," "point out my mistakes" — and it does exactly that. Not a fixed lesson: a conversation that bends to what you want.)

If the piece can only land one thing: **the free call is YOURS to run — just ask for what you want out loud, and your fluent self does it.**

Founder's own approved release-note words (anchor the copy to these, don't over-promise beyond them):
- ko: "자유 대화에서 하고 싶은 걸 말로 부탁해 보세요. 표현을 알려 달라거나 틀린 곳을 짚어 달라고 하면 그렇게 해요."
- en: "In free talk, just ask for what you want out loud. Ask it to teach you an expression or point out your mistakes, and it will."

## Who it's for

The learner who can hold a basic call but wants it to *do more than small talk* — someone mid-call who thinks "there must be a better way to say this" or "did I just get that wrong?" and wishes they could just ask. Concretely: 영어로 자유 대화를 하다가, 적당히 아는 표현 말고 **자연스러운 표현을 하나 배우고 싶거나**, 내가 방금 틀렸는지 **집어서 알려줬으면** 하는 중급 학습자. They already know chat-with-an-AI ("Claude한테 말하듯"); this says your language call works the same way, in your own voice.

Honest floor respected: this is someone who can already carry a stumbling free-talk call and wants to steer it — not an absolute beginner. Never promise fluency.

## Why now

1.3.6 (build 149) ships it — CLAUDE.md "Free talk has a character brief (2026-11-17)", specifically the **"The call is the learner's to run"** paragraph (gateway `OPEN_TALK_BRIEF`). From this build a free talk is no longer a model doing whatever it likes with no brief: it's told the call is the learner's to run — whatever they ask for on any turn they get (a subject, an explanation, an opinion, their mistakes pointed out), and an expression they name is taught in one sentence, used once about a life like theirs, then handed back with a question.

## Proof in the app

- **Screen:** `web/kit/screens/call.js` (`nw-call`). Script the transcript directly — the designer drives it, NO app capture needed. Methods: `call.say("…")` (fluent self speaks), `call.user("…")` (the learner's words land in the feed), `call.listen()` (empty Listening bubble).
- **`call.other` stays UNSET** → the other side is the fluent self ("미래의 나" / "Future self"). Free talk only — do NOT set a counterpart name or a scenario role. The whole point is it's a line *you* could say, in your own voice.
- **NO `fix(...)` correction card and NO `coach(...)` "try saying" card in this piece.** Those are the app volunteering help; this message is you *asking*. The exchange is carried entirely by the plain dialogue lines (`say` / `user`). A correction card on screen would tell the opposite story (교정 is e04's job).
- **Behaviour shown is real** (CLAUDE.md): a named expression is taught in one sentence, used once about a life like yours, then handed back with a question; a request to point out mistakes is answered by naming the slip and carrying on. Both are exactly what the gateway brief instructs.

### Scripted exchanges (English target, Korean learner) — pick these

**A — "teach me an expression"** (the headline exchange):
- `call.user("Teach me a natural way to say I'm really busy at work.")`
- `call.say("You'd say 'I'm swamped.' I've been swamped all week getting the new feature out. What's got you swamped these days?")`
- This single exchange shows all three moves: taught in one sentence ("You'd say 'I'm swamped.'") → used once about a life like yours ("I've been swamped all week…") → handed back with a question ("What's got you swamped these days?"). Lean on it.

**B — "point out my mistakes"** (the second ask, shows breadth):
- `call.user("I go to the gym yesterday. Tell me when I get something wrong.")`
- `call.say("Sure. Just there — 'I went to the gym yesterday,' not 'I go.' So how was it?")`
- Keep it light: it names the slip inline and keeps the conversation going. The "and it will" of the release note.

## Outline (5 cards)

**Card 1 — Cover** (still PNG; must read in the grid)
- Says: 자유 대화는 내가 끌어가요 — 말로 부탁하면 돼요. / Free talk is yours to run — just ask.
- Screen: none (cover layout). Series eyebrow + pixel title. Optional sticker: a single learner bubble peeking in — "Teach me a natural way to say…" — from the bottom edge.

**Card 2 — Just ask out loud** (`nw-call`, exchange A, the ask landing)
- Says: "표현 하나 알려줘" 하고 말해 보세요. 유창한 내가 자연스러운 한마디를 알려줘요. / Say "teach me an expression." Your fluent self gives you the natural one.
- Screen: `call.user("Teach me a natural way to say I'm really busy at work.")` then `call.say("You'd say 'I'm swamped.' …")`. Show the ask → the taught line. The continuity (your request, its answer) is the proof.

**Card 3 — It hands it back to you** (`nw-call`, exchange A full, emphasis on the closing question)
- Says: 알려주고 끝이 아니에요. 내 얘기처럼 한 번 써 보이고, 나한테 질문으로 넘겨줘요 — 그래서 내가 말하게 돼요. / It doesn't stop at telling you. It uses it once about a life like yours, then turns it back with a question — so *you* say it.
- Screen: the full A exchange, the fluent self's line ending on "What's got you swamped these days?" visible. This is the differentiator card (BRAND: the line is in *my* voice, so it reads "I could actually say that"). Any emphasis on the closing question is a **sticker outside the phone frame** or in the top text block — never drawn onto the app screen.

**Card 4 — Or "point out my mistakes"** (`nw-call`, exchange B)
- Says: "틀린 데 있으면 짚어줘" 라고 해도 돼요. 뭘 부탁하든, 통화가 그쪽으로 흘러가요. / Or say "point out my mistakes." Whatever you ask, the call bends to it.
- Screen: exchange B — `call.user("I go to the gym yesterday. Tell me when I get something wrong.")` → `call.say("Sure. Just there — 'I went…' not 'I go.' So how was it?")`. Shows it's not one trick: the call is yours to run.
- **No `fix` card** — the correction lives in the fluent self's spoken line, because *you asked for it*.

**Card 5 — Outro** (standard outro)
- Wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" · nawana.app. No price claims beyond the free-minutes line.

## Risks / things to check before ship

- **Free talk ONLY.** Every card is a plain call with the fluent self (`call.other` unset). Do not drift into a scenario, a cast person, or tutor mode — those are other pieces and other episodes.
- **It's YOU asking, not the app volunteering.** No `fix(...)` and no `coach(...)` card anywhere. The teaching and the correction both arrive as the fluent self's *spoken reply to your request*.
- **Do NOT claim pronunciation.** The free-talk reply gets TEXT, not audio — it cannot judge how a word sounds. No "fix my accent / my pronunciation" copy. Keep requests to expressions, mistakes (grammar/word choice), explanations, opinions, a part to play.
- **Stay inside the release note.** Don't promise it will do *anything*; anchor to the founder's two sentences (teach an expression, point out mistakes, ask for what you want). "Like talking to Claude" is a fine *angle* but don't name Claude on a slide.
- **Don't grade the reader.** No "초보자용 / for beginners / for advanced". Present it as *there when you ask*.
- **Keep the demo in English** (target default). Any native-language gloss would be Korean, but these exchanges carry the meaning in-line, so a gloss isn't needed — don't fake a non-English target.
- **Numbers / clock / level on screen are illustrative** kit sample data, never a user result.
- **Threads text** written fresh (conversational), not the IG caption pasted. Hook: that moment on a call when you think "there's got to be a better way to say this" — now you just ask.

## Success signal

Afterwards look at: **saves** on the carousel ("oh, I can just *ask* it" is a reveal that saves well) and comments/DMs from learners naming a thing they'd ask for (demand signal); community series views; profile visits / installs attributed around the post. Secondary, a 2-week read, not launch-day: any uptick in free-talk length or return calls if the telemetry exists (CLAUDE.md names `openTalk` on the gateway) — informational only, never a public stat.

## Community series entry (for publisher, draft only)

- `id:` lead to assign (likely `e23`; deconflict with in-flight `e20–e22` and the sibling `free-talk-remembers`), `cat: "talk"`, `slides: 5`
- ko: title ≈ "말로 부탁해요", tagline ≈ "자유 대화는 내가 끌어가요 — 알려줘, 짚어줘 하면 그대로"
- en: title ≈ "Just ask", tagline ≈ "Free talk is yours to run — teach me, correct me, and it does"
- (Copywriter finalizes titles/taglines in copy.md; these are placeholders.)
