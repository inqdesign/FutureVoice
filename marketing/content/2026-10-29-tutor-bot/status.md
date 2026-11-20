# 2026-10-29-tutor-bot

- **Stage:** brief + kit screen in progress (2026-11-09). Founder asked for this piece directly ("튜터 봇에 관한 기능을 만들어줘"), new centred template. Was: failed (needs capture), autopilot upload, 1.2.6 (123).
- **Captures (2026-11-09):** `marketing/captures/tutor-bot-{plan,bubble,chat}.png`, taken with `-capture tabs -tutorShow <state>` on the installed dev build, no app change. The kit screen is `web/kit/screens/tutorbot.js`.
- **Feature:** the Talk-tab tutor bot — a daily note that lays out today's plan (picks beyond
  the routine) and a chat you can ask anything about your practice. The headline of 1.2.6.
  Commits: `87bda8d6` feat(tutor bot): a daily plan…, `2ff90516`, `7a0f3e0f`.
- **Why it couldn't be built:** no `-capture` harness case and no `web/kit` screen for this
  surface. The kit's tutor states (`call.tutor`/`tutorTick`/`tutorDone`) are the IN-CALL
  lesson strip — tutor *mode*, already told by `2026-10-25-tutor-goal`. Autopilot may not
  draw a screen from imagination.
- **To unblock:** add a simulator `-capture` case for the Talk-tab daily coach (note + chat),
  drop the PNG in `marketing/captures/`, then this piece can go through the pipeline.
- **2026-11-09:** brief.md done, kit screen `nw-tutorbot` built (bubble/note/chat matched to captures; answer states from source). Default routine sample = 3 things, 40 min (a 10-min talk + two 15-min blocks is what the app computes). Waiting on founder: outline OK, goal row on the cover (lead recommends none). Then: real tutor answers from `scripts/tutor-agent-probe.py` for cards 4 and 5, copy, design, review.
