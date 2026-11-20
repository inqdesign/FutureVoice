# 2026-11-09 · Speech Season 2

- **stage:** ready (reviewer PASS, 6 slides in R2) — awaits the `release` phase to schedule
- **version:** 1.3.2 (138) · phase: upload (autopilot)
- **owner:** lead
- **request (autopilot):** 1.3.2 headline — English speech challenges move to Season 2. A take
  is scored against a NATIVE reading of the same script (speed · rhythm · pauses · accuracy ·
  pronunciation), and the score earns a nickname. New result page: the score over the learner's
  own video, with the details on a pull-up sheet. Season 1 stays practisable; closing a season
  never retires it.

## Facts (from release notes + CLAUDE.md)
- Season 2 is **English first** (per language; opens wider after Android).
- Scored against a native reading of the **same script** → speed, rhythm, pauses, accuracy, pronunciation.
- Score earns a **nickname**.
- Result page is new: **score over your own video**, details on a sheet you pull up (`SpeechResultSheetPage`).
- Mic-only take shows the audio row + "Measured" instead of video.
- Score strip = `SpeechResultView.scoreStrip` (the kit's speech screen renders it).

## Kit / captures
- Kit screen: `web/kit/screens/speech.js` — result pose renders the Season 2 score strip + video/audio.
- Captures predate Season 2 (2026-10-11); autopilot uses the kit screen, does not draw a new one.

## Open questions
- (none blocking — building from existing kit)

## Log
- run_start logged; piece created at stage idea → brief.
- brief → copy → design (6 cards rendered) → review PASS (0 fixes).
- media uploaded to R2, slides + alt text registered; captions (ko/en) + threads set.
- staged `ready`; local renders pruned. run_end logged. Autopilot upload complete.
