# Review — 2026-10-25-tutor-goal (v2, round 2) — 2026-10-26
Verdict: FIX

1. [fidelity] card 05, ko + en: challenges 2 and 3 open with a bare question and no example line ("Nice! Now, what do you do?", "And what do you like doing?"). In the app, once a challenge is checked off, the next turn is required to "start challenge N: give its example line and ask them to say it about themselves" (`ConversationEngine.tutorNow`, and "HOW YOU RUN A CHALLENGE": "say what it is, give its example line"). Card 03 also promises "과제마다 예시 한 줄을 들려주고 / For each challenge you hear one example line", and card 05 then shows two challenges without one. → In carousel.html set `NEXT1 = "Nice! Now, what do you do? Like: I'm a teacher."` and `NEXT2 = "Got it! What do you like doing? Like: I like cooking."` (the "Got it!" also gives the "short, real 'you got it'" the prompt asks for). `LAST` can stay as it is, because the three lines just heard are its example. Update copy.md's card 05 `screen:` line to match. Re-render 05.mp4 and 05.png in renders/ and renders-en/. If the loop goes over 13 s, cut the closing `s.sleep(900)` rather than speeding up the ticks.

## Round-1 items, re-checked

All files were read fresh. carousel.html is from 13:26, copy.md from 13:30 and newsletter.md from 13:13. The MP4s and the 02–05 PNGs were rendered at 13:26–13:30, after the last carousel edit. 01.png (13:15) and 06.png (13:25) are older than that edit, but they show the current script and colour, so they don't need a re-render.

- R1-1 cover: fixed. The cover lays the opener and "I want to introduce myself.", then the last bubble is GUIDE with its example ("I'm Mina, I'm from Busan."), and the pill is lit. This is the app's real order (NO TOPIC YET → topic → challenge 1). The copy.md alt texts and the "material on screen" line match.
- R1-2 card 05: fixed. Each challenge now gets its own line, the last row is "all of it in one go" answered by the whole introduction, and all four checks are on before "All done." Remaining issue: item 1 above.
- R1-3 accent: fixed. The `--blue` token is now #0A5CF5. I sampled the eyebrow square on renders/01, renders-en/01 and renders/03, and it reads exactly 0a5cf5.
- R1-4 first frames: fixed. At 0 s, 02 shows the opener already laid with the pill listening, and 03/04/05 show the conversation already laid. Neither language has a blank or half-faded first frame.
- R1-5 newsletter (b) ko: fixed. It now reads "틀리면 하신 말을 바르게 고쳐 들려주고 다시 해 보게 하며," and "자기 이야기로 직접 말해 보게 합니다." Both read correctly in 합니다체.

## Card 05 script against tutorBlock (the rest holds)

- A line that is right on the first try may be moved on straight away ("nailed on the very first try with nothing to fix → you may move on"). The app ticks it when the correction call returns no fixes and `TutorJudge.done` is true (`ConversationView.tutorCheck`). So "I'm a nurse." → tick → next challenge is real behaviour, with no "once more".
- Card 04 is also real behaviour. In the app, the slip, then the fix card, then "Almost! … Again?" (the line said back right, no "wrong"), then a clean retry ticks the row at once: no fixes plus done sets `doneAt`, and `tutorJustTicked` stops the tutor asking again.
- The last challenge is answered by the whole introduction, and then the ALL DONE turn comes, which matches the prompt's lesson-finished branch.

## Still clean from round 1

- Truth: same code checks as round 1 (Call settings → Tutor mode, 3–4 challenges with the last one putting it all together, native-language rows, resume, book). No prices. "첫 20분은 무료예요 / first 20 minutes are free" is per BRAND.
- Voice: Korean is native 해요체 on the cards, captions and Threads, and 합니다체 in the newsletter. No 당신. There are 0 em dashes in copy.md and newsletter.md. English reads native.
- Channel: every MP4 is H.264 1080×1350 at 30 fps, lasting 9.6 / 9.7 / 11.6 / 11.9 s. IG captions are ko 314 / en 667 chars, with 5 hashtags each. Threads posts are ko 246 / en 477 chars (≤ 500).
- Visual: every title fits on 2 lines with no clipping. Card numbers run 01–06 in order.
- Safety: the only name shown is the sample name Mina. No real user data.

## Suggestions (non-blocking)

- Card 05 `DONE`: in the app, the lesson-finished turn ends by asking whether to keep going with this topic or try another (`tutorBlock` ALL DONE). "All done. You can introduce yourself now. More of this, or a new topic?" would show the call keeps going. The card's message works without it.
- 01 still: about 200 px of empty call body sits between the chip row and the first bubble. A COVER pan of about 40–60 instead of 84, or one more laid line, would fill it.
- 01: the "뜻 / Meaning" accessory under the GUIDE bubble is still mid-fade in the still. That's harmless, but a 300 ms longer hold before capture would settle it.
- The round-1 clock note is resolved: the clock now runs forward across cards (02 ends at 0:16, 03 starts at 0:18, 04 at 0:30, 05 at 0:55). Carried over from round 1: brief.md's "the app, not the tutor's mood, checks the row off" is now half the story, because since bbeebf81 the checklist also follows the tutor moving on. The newsletter needs its THUMBS entry, and the Android port of bbeebf81 is still `todo` if Android testers get the mail. Posting, the e06 series.json change and the mail all need the founder's OK.

Checked frames: renders/01.png, 05.png and renders-en/01.png at full size; renders/02.mp4, 03.mp4, 04.mp4, 05.mp4 and renders-en/02.mp4, 03.mp4, 04.mp4, 05.mp4 @0s 3s 6s 9s; renders/05.mp4 and renders-en/05.mp4 @10.3s and the last frame; pixel samples of the eyebrow square on renders/01, renders-en/01 and renders/03.
