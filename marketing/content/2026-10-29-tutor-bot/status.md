# 2026-10-29-tutor-bot

- **Stage:** failed (needs capture) — autopilot upload, 1.2.6 (123).
- **Feature:** the Talk-tab tutor bot — a daily note that lays out today's plan (picks beyond
  the routine) and a chat you can ask anything about your practice. The headline of 1.2.6.
  Commits: `87bda8d6` feat(tutor bot): a daily plan…, `2ff90516`, `7a0f3e0f`.
- **Why it couldn't be built:** no `-capture` harness case and no `web/kit` screen for this
  surface. The kit's tutor states (`call.tutor`/`tutorTick`/`tutorDone`) are the IN-CALL
  lesson strip — tutor *mode*, already told by `2026-10-25-tutor-goal`. Autopilot may not
  draw a screen from imagination.
- **To unblock:** add a simulator `-capture` case for the Talk-tab daily coach (note + chat),
  drop the PNG in `marketing/captures/`, then this piece can go through the pipeline.
