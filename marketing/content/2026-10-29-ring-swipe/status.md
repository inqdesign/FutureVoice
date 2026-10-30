# 2026-10-29-ring-swipe

- **Stage:** failed (needs capture) — autopilot upload, 1.2.6 (123).
- **Feature:** swipe the Home ring to switch between free talk, tutor and pronunciation.
  Commit `d3a28206` feat(talk): the home ring swipes between free talk, tutor and pronunciation.
- **Why it couldn't be built:** no capture, and `web/kit/screens/home.js` renders the ring
  only as "Let's talk" — it has no mode labels and no swipe. Autopilot may not add that to the
  kit from imagination (that is drawing a screen).
- **To unblock:** capture the three ring states (free talk / tutor / pronunciation) from the
  simulator, or add them to `nw-home` from such a capture; then a before→after swipe piece
  can be built.
