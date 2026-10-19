# status — 2026-10-13-tutor-mode

- **stage:** ready (reviewer PASS, media in R2, captions/titles set) — awaits release phase to schedule
- **version/build:** 1.1.9 (102), phase upload (autopilot)
- **request:** autopilot upload — tell the one strong new feature in 1.1.9: tutor mode (수업).
- **owner:** lead

## The feature (from release notes + CLAUDE.md "Coach mode")
Tutor mode, in call settings. Turn it on and the fluent self runs a lesson: after everything
you say, you hear the right sentence or a more natural way to put it, then a question you can
answer by using it. A mistake is spoken back the right way — you HEAR the correct version.
On by default for A1/A2.

## Decisions
- One piece only. Profile-photo-in-Find-people (also new in 1.1.9) dropped as too thin for a
  carousel. Recorded as a run note.
- Built from the existing `nw-call` kit screen (coach "Try saying" line, fix correction card,
  `demo()` flow, `coach`/`fix` poses). No new screen needed; captures exist (call-coach.png).

## Review history
- Round 1 FIX: piece had conflated tutor mode (new, OFF by default, teaching spoken in the
  fluent self's own reply) with Coach mode (older, A1/A2-default, the Try-saying/Try-using/
  Used-it surfaces). Brief + copy + carousel rebuilt to tell ONLY tutor mode (튜터 모드 toggle).
- Round 2: PASS, 0 fixes.

## Notes
- Slides: cover (01) + outro (06) = image; 02–05 = video (matches sibling convention).
- IG hashtags are inline on the final caption line (an interactive-session shell guard blocks
  newline-then-`#`; the headless autopilot path is unaffected). Content otherwise verbatim from copy.md.
- Community series entry (talk / e06) is prepared in copy.md but NOT added to the live site —
  that needs founder approval (publisher step, release phase).

## Open questions
- none

