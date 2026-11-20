# 친구초대 이벤트 카드 (Threads)

- stage: review PASS (round 2), waiting for founder approval
- request (founder, 2026-11-20): "친구초대 이벤트 카드를 쓰레드에 올릴걸 하나 만들어줘"
- owner: lead
- facts: invite event 3da39ac1 / 984b7c30 (2026-11-19) — a subscriber invites; when the friend's first payment goes through, both get next month half price (one month per friend, no cap, one per billing period). Words: scripts/invite-event-texts.json.
- open questions:
  - invite_event table does NOT exist in prod yet (checked 2026-11-20): the event is not live. Post only after the migration + rollout + the app build with the banner are out (iOS; Android is todo).

- 2026-11-20 founder: more room at the bottom, add the label 나와나 구독자 이벤트 (en: nawana subscriber event). Done by lead: label pill top-left, art and steps moved up ~50px, fine print now ~70px above the foot. Re-rendered.
- 2026-11-20 founder: remove the illustration's background. Cream paper box removed (the art PNG is transparent); people stand on the card's grid. Re-rendered.
