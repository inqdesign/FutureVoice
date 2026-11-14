# App Store first three screenshots: alternative directions (2026-11-11)

Stage: drafts shown to the founder, waiting for a pick. Nothing uploaded.
Request (founder): "앱스토어 첫 3장의 스크린샷을 만들어줘. 지금 direction과는 다르게. 몇가지 안을 나한테 줘봐"

- A-ink / B-blue / C-panorama: 1320x2868, Korean only. Screens are web/kit poses rendered at 4x.
- gen.py rebuilds them (needs the kit renders in ./k next to it; see the harness in web/kit/_harness.html).
- Open: which direction, then copy pass (mkt-copywriter), other 7 language sets, reviewer.

## 2026-11-13 — E (D direction on the current app)
Founder: D's clean direction is right; ring 2/3 full with the bottom UI showing, tutor with goals (exam + interview), latest Speech.
Raw captures from the current Debug build on an "ASC 17 Pro Max" simulator (own device, not the shared one):
`-capture tabs` (ring at 6:40 of 10 min), `-capture tabs -tutorShow chat` with two seeded goals (오픽 IH D-27, 외국계 회사 면접 D-21), `-capture speech-season2`.
Output: E-latest/E1–E3.png, E_sheet.jpg, gen_e.py. Copy provisional. Nothing uploaded.
- 11-13 later: founder — "the speech's real face is the key". Speech shot now uses the founder's own screen recording
  (~/Downloads/ScreenRecording_11-09-2026 15-03-23_1.MP4): the 92 result over his face (E3) and prompter + result as two phones (E4).
  Recording dot painted out of the island pill.
- 11-13 late: founder — speech changed a lot, prepare the whole set. Rebuilt the app at HEAD + working tree,
  re-captured on the ASC 17 Pro Max sim (raw3/). F-set/01–10 + F_sheet.jpg via gen_f.py:
  home · tutor goals · speech (face split) · fix · coach · challenges · pronunciation · watch · book · routine.
  Progress/level left out of the 10. Copy provisional (no pixel font). Nothing uploaded.
- 11-14: founder notes → G-set/ + G_sheet.jpg (gen_g.py). 01 languages (no icon, language chips), 03 = the live
  App Store speech screen (camera split, from ASC 1.3.3 ko) + challenge illustration cards (03 and 06 merged),
  04–06 call screens = founder's own device screenshots (11-12 22:44, 11-08 20:02, 11-04 12:07) with the
  simulator's 9:41 status bar, 07 = map with a profile photo on 나 + composer box ("any situation"), 10 = level.
- 11-14: 03 redone without a phone: script as live text on the ground, the store screenshot's camera card cut on its own edge, the challenge cards cut on their own edges (no padding).
- 11-14: 03 aligned: script and camera card share x 130–1190, card ends at the phones' baseline (2760), two cards symmetric on the card's top corners.
- 11-14: 01 = '유창해진 미래의 나와 통화해요' with a language row where ONE is picked; 02 = voice clone (recording + meet act); level dropped. Order: future self · voice · tutor · speech · fix · coach · pron · situation · book · routine.
- 11-14: 02 retitled (founder: the point is copying yourself, not natives): 원어민 흉내 말고 / 유창한 나를 따라 해요.
- 11-14: founder approved 02's wording: 원어민 흉내 말고 / 유창한 나를 따라 해요.
- 11-14: founder: keep the live store opener (hand photo) as 01, replace the rest; shadowing in place of pronunciation (07, scored take captured with a temporary DEBUG seed, reverted).
- 11-14: committed 77732a4e. ASC: created version 1.3.4 (PREPARE_FOR_SUBMISSION); ko APP_IPHONE_67 (1320×2868) + APP_IPHONE_65 (1242×2688) replaced with the 10 new shots. Goes live with 1.3.4's approval.
- 11-14 (founder: "own this, finish until all screens are updated"): the G design in every other language.
  `gen_lang.py <lang> [--ipad|--android]` builds the ten from raw captures; copy per language in `copy_lang.py`
  (written in each language). Raw iPhone/iPad captures: `cap.sh <lang> <locale>` in the session scratchpad,
  from the Debug build with new staged screens (`-capture call-seed-fix|call-seed-coach`, `-shadowResult 1`,
  texts in `CaptureCallSeed.swift`). Out: sets/ios/<lang> (en ja zh-Hans zh-Hant es fr de, 1320x2868),
  sets/ipad/<lang> (those + ko, 2064x2752: one headline over one full iPad screen; the app's iPad layouts are sparse).
  English keeps the live hand opener (en 01); other languages open on the future-self + language-row design.
- 11-14: NOT uploaded yet. Apple locks screenshots while 1.3.4 is waiting for review (409 STATE_ERROR).
  When the next version exists: `python3 asc_upload.py <version>` (dry run) then `--send`: iPhone 6.9/6.5 + iPad 13
  for ko en-GB en-US ja zh-Hans zh-Hant es-ES es-MX fr-FR de-DE.
- 11-14: Android (Play, 7 languages) in progress: emulator captures, then `gen_lang.py <lang> --android acap/<lang>`
  (9:16 page, 1080x1920) into the Android repo's fastlane folders, then `play-listing.py --send --images`.
