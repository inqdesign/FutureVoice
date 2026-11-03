# 2026-11-03-free-recharge — status

- stage: ready (autopilot upload run done, 2026-11-03)
- review round 2: PASS, 0 fix. 6 slides uploaded to R2 (media.sh --set-slides), alt texts
  merged, captions ko/en + threads_text (ko) + titles set, review_verdict=PASS,
  local renders pruned. Waits for the release run to schedule it.
- publish-day conditions (reviewer, for whoever schedules/posts):
  ① confirm `billing_config.free_recharge_seconds` is live at 1200 (0 removes the button
  and strands the "20분 한 번 더" claim) — the migration is 20261103150000, applying it to
  prod is a human step; ② 1.2.9 must be live on the App Store before posting.
- community series entry e20 (cat start, "무료 20분") proposed in copy.md — series.json
  edit changes the live site, so it waits for the founder; no separate community news
  (beta.sh posts the 1.2.9 release news).
- review round 1 (2026-11-03): FIX 3 — ① page accent was #0A84FF not #0A5CF5 (designer,
  re-render all), ② card 03 said the correction is SPOKEN, it's a text card (copywriter,
  done: "바로 고쳐져요" / "put right", also the EN caption), ③ "리포트가 기다려요"
  re-engagement line overpromises (deck re-raises at most twice per install, verified in
  RootTabView/TrialReport code) — lead decision: line REMOVED everywhere, piece is pure
  acquisition (copywriter, done; designer removes card 05 .note).
- phase: autopilot upload, 1.2.9 (129)
- request: autopilot — build 129's feature commit 37d6cc3f. One message: 무료 20분을 다
  쓰면, 리포트 끝에서 한 번 더 20분을 무료로 충전할 수 있어요 (once per account, beside
  Subscribe, never-subscribed accounts only, no store trial).
- owner: lead (autopilot)
- constraint: the recharge offer card has NO capture and NO kit screen. The piece must be
  built from EXISTING kit screens (the call = what the free minutes buy; the report deck);
  the recharge offer is said in words only. Never draw the button.
- facts (verified against CLAUDE.md "The free minutes end in a REPORT" + release notes):
  - first 20 minutes free, no trial (since 2026-09-26)
  - when they are spent the app shows a report: how you used it, a level read from your
    own speaking, a test you can take, a routine to keep going
  - NEW in 1.2.9: the report's last card offers "Subscribe | Recharge 20 min free" —
    the recharge is free, once per account, only for accounts that never subscribed
  - the store's 3-day trial is gone (don't mention trials at all)
- open questions: none (autopilot decides)
