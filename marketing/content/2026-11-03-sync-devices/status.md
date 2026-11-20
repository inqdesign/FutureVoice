# 2026-11-03-sync-devices — status

- stage: ready (autopilot upload run, 1.2.9 build 131 — carried from build 130's design)
- phase: autopilot upload, 1.2.9 (131)
- owner: lead (autopilot)
- outcome: 6 cards rendered (home, routine, review, words, people, outro — all existing
  kit screens, sync surface never drawn), reviewer PASS (0 FIX), slides live in R2,
  captions/titles/threads set, local renders pruned. Scheduler will post after the veto
  window once 1.2.9 is released. Reviewer ruled card 05's letter avatars an acceptable
  proxy (photos sync is said in words; the Devices screen is never drawn).
- request: autopilot — build 130's sync commits (9f838268 feat sync tutor/goal-prep/
  weekly-archive/photos/practice-settings, 697e8317 feat sync routine + rings, 8da7060b
  fix CloudKit Production). Release-notes "New" bullet: "With iCloud sync on, your routine,
  tutor, photos and settings carry across your devices."
- one message: 켜 두면 폰에서 한 연습이 태블릿에도 그대로. 루틴, 튜터, 사진, 설정까지
  내 기기들 사이를 따라와요 (iCloud, 옵트인).
- CONSTRAINT: there is NO capture and NO kit screen for the Me → Devices (sync) surface.
  The piece must be built from EXISTING kit screens (the practice that now travels —
  routine, review book/words, people with faces, home). Sync itself is said in WORDS only.
  Never draw a devices/sync screen. (Same precedent as 2026-11-03-free-recharge.)
- facts (verify against CLAUDE.md "Sync between the learner's own devices" + "Almost
  everything a learner makes syncs" 2026-11-03):
  - iCloud sync is OPT-IN, default OFF, Me → Devices
  - it uses the learner's OWN iCloud — nothing on our servers
  - NEW in 1.2.9: the routine (with ring times), tutor lessons + chat, goal prep, the
    "Your week" archive, people's photos, profile photo, day cards, and practice settings
    (speech speed, voice pick, coach/tutor mode, furigana, exam, weekly-test day/time)
    now sync too — beside the talks, cards and words that already did
  - a phone and a tablet feel like ONE app
  - blob uploads (audio, photos) are Wi-Fi only unless the Me toggle says otherwise
  - NEVER claim it is on by default; never claim anything lands on our servers
- open questions: none (autopilot decides)
