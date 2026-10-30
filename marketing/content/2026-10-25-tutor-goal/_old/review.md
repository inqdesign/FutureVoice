# Review — 2026-10-25-tutor-goal — 2026-10-25 (round 2)
Verdict: FIX

1. [visual|fidelity] card 01 (designer) — NOT FIXED. The `PLAY.cover` block in `carousel.html` is unchanged from round 1 (still only `pan(c, HIGH)` → `s.goals(GOALS)` → `s.sleep(5000)`; no `s.say(...)` call), and the re-rendered `renders/01.png` is identical: the checklist chip row (order / oat milk / all together) over a large empty white call body, with no fluent-self opening bubble, no "미래의 나" speaker label, and no lit Futureself pill. The cover still loses the own-voice hook and does not hold as a standalone 1080×1350 grid still. → In `PLAY.cover`, speak the opening line before the sleep (e.g. `const p = s.say("Okay, let's work on ordering at a cafe. Ready?"); p.catch(()=>{}); await p;`) and set the camera so BOTH the checklist chip row AND the fluent-self bubble with its "미래의 나" label / lit Futureself pill are in frame (the chips sit at the top and the bubble below; a middle pan, or `pan(c, HIGH)` with the bubble reaching up into view). Then re-render 01.png / 01.mp4 and confirm the bubble actually appears in the exported still.

Note: the round-2 message said the cover now speaks the opening line, but the committed `PLAY.cover` and the delivered `renders/01.png` show no change. The edit did not land (or was not saved/re-rendered). Everything else in the piece is unchanged and remains clean (see round-1 verified list below).

## Verified clean (unchanged from round 1)

- Truth: every tutor fact matches CLAUDE.md "Tutor mode (2026-10-24)" — off by default + in Call settings, you pick the topic, 3–4 challenges with the last = put-it-together, tick is the app's, "once more" on a clean line, checklist pinned above, finished lesson doesn't end the call, ending stays the learner's, switch-goal saves a review book, resume 21 days, level changes WHAT not how much, own cloned voice never a stranger/scold. No grading / no app-assigned level claimed.
- Price/limit: "첫 20분은 무료예요 / first 20 minutes free" = `BillingConfig.freeTalkSeconds` default 1200 s = 20 min. No free-trial language anywhere.
- Fidelity: built only on `nw-call` (bodies) + `nw-futureself` (outro). No drawn screens, no invented states. Sample data only — no real user, result, or founder name.
- Voice: Korean chrome native 해요체, no 당신, no em dash; fluent-self on-screen lines casual English material; coaching note in native language. English native. Positive-first, no hype.
- Channel fit: 6 items 1080×1350; MP4 durations 5 / 11 / 10 / 11 / 11 / 5 s (≤ 60 s); IG caption ko ≈430 / en ≈830 (≤ 2200); hashtags 5 ko / 4 en; Threads ko ≈280 / en ≈480 (≤ 500).
- Visual beats land on 02–05: checklist fill, fix card bloom, green-check tick, full-green checklist, all legible; no bad clipping.

Checked frames: renders/01.png (re-rendered, unchanged) · carousel.html PLAY.cover block (unchanged)
