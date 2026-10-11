# 나와나로 할 수 있는 것들 — series cover carousel

- **Stage:** v2 (10 cards) renders done (2026-10-11) — next: review, then captions re-approval and packaging
- **Request (founder):** "나와나로 할 수 있는 것들" 시리즈 캐러셀 — 글자 레이아웃은 고정, UI는 애니메이션. 라이트 테마.
- **Cards:** 01 cover · 02 유창한 나와 대화를 한다고? (nw-call) · 03 왜 원어민 말고 내 목소리일까? (compare) · 04 Talk (nw-home) · 05 Speech (nw-speech) · 06 outro
- **Founder decisions so far:** light theme; Futureself mosaic as in the app (shader port, inner shadow); native-voice reaction "따라 하면 연기하는 것 같아. 나 같지가 않아".
- **Preview:** https://claude.ai/artifact/VxWfH6CHaV2tjJa399PmmY
- **Open:** copy.md (extract from carousel.html), captions, review, renders.

## 2026-10-11 founder decisions (after brief + copy)
- Card 05: show up to the SCORE only — no rank-up sheet, no leaderboard wording (challenges not shipped yet). Captions/Threads drop the challenge sentence.
- Cover description → "유창한 나와 말해보는 외국어 앱, 나와나."
- Community: a NEW entry (keep e01 as is).
- Captions and Threads text: approved as written (minus the challenge sentence).
- Kit: the founder's real name removed from the speech rank sheet and the ring caller (sample name "Jiwoo").
- Stage: copy → design.

## 2026-10-11 design — renders done
- carousel.html: final copy.md applied (cover desc, card 02 learner line “It was a busy week. I go to…”, card 05 desc); card 05 uses `<nw-speech nochallenges>`, the rankUp/leaderboard step is removed and the scene ends on the score (81); the kit draws the mic-only result (play row + 측정 결과), and after the score lands the phone pans up 250 px so the measured rows sit under the score.
- renders/: 01.png · 02.mp4 13.4 s + 02.png · 03.mp4 9.8 s + 03.png · 04.mp4 12.6 s + 04.png · 05.mp4 12.4 s + 05.png (re-rendered on the updated kit; poster = score + measured rows) · 06.png — each MP4 is one full loop (last frame ≈ first frame).

## 2026-10-11 review FIX applied (designer)
- Card 02: the reply now starts first and the correction card lands ~300 ms into it — never during "생각하는 중" (frames 6.0–8.4 s checked).
- carousel.html `--blue` → #0A5CF5 (BRAND accent, same as the kit).
- Kit changes picked up in the re-render: card 04 neutral news headline (folding phone), card 05 Korean result lines.
- Suggestion 1 (card 05 desc) NOT applied — copy kept as approved.
- All six re-rendered: 01.png · 02.mp4 13.3 s + 02.png · 03.mp4 9.8 s + 03.png · 04.mp4 12.6 s + 04.png (News tab) · 05.mp4 12.4 s + 05.png · 06.png. Every MP4 is one loop (last frame ≈ first).

## 2026-10-11 review
- Round 1 FIX (4): correction before voice, English coaching on ko screen, real company in news row, wrong blue → all fixed (kit speech.js/home.js + carousel.html), all six re-rendered.
- Round 2: PASS. Preview updated (v10) at the same URL. Waiting for founder approval to upload media and schedule (12h veto).

## 2026-10-11 founder: "너무 빈약하다" → 10 cards
- One carousel, 10 cards: 01 cover · 02 call with the fluent self · 03 why your own voice · 04 Talk · 05 Watch · 06 Review (the talk becomes a book) · 07 Say it again · 08 Daily call · 09 Weekly report + test · 10 outro.
- Speech dropped from this piece (own episode later, with challenges once shipped). Old 6-card renders kept in renders-v1/.
- Checked: Android daily call also rings through silent mode (alarm stream, DailyCallRingService + full-screen ring) → card 08 claim holds on both platforms.

## 2026-10-11 design — v2 (10 cards) renders done
- carousel.html rebuilt for 10 cards (v1 file kept as renders-v1/carousel.html). Eyebrows NN / 10. Speech card removed.
  Text block exactly as copy.md; `?lang=en` swaps in the English copy (check only, not rendered as a set).
- Cover: 8 chips at 32px (not below 30), 14px gap, block moved up (title 212, desc 492, chips 650–1100); mosaic beside the list.
- 05 Watch: "Your own situation" door only — dictation into the box, CTA, "대화를 쓰는 중…", interview plays, "이 문장 섀도잉" tapped. Attachment chip + files note hidden (the app draws them only when material is attached; the kit always draws them).
- 06 Review: shelf → book cover → 단어 → 표현 → 드릴 → "이 대화 복습" → card answered aloud, revealed, filed into 내일, next card. No Shadow chapter, no PDF.
- 07 Say it again: intro held 3.0 s, then the run (92, 61 + 들린 말), finish "2문장 중 2문장 읽음 · 평균 76점". EN title "the same call, done right" fits one line — fallback not needed.
- 08 Daily call: AlarmKit alarm screen → 받기 → call opens with "Morning! You had the interview yesterday…" → answer → follow-up → back to the alarm screen. No decline beat, no banner.
- 09 Week + test: report cover (streak flame here only) → 자주 틀리는 문법 (past tense over own lines) → last card → test: translate item (Korean prompt → tiles) → result 6/7, missed "I ended up carrying…". No flame, no gauge on the test half.
- renders/ (1080×1350, H.264 30 fps; each MP4 is exactly one loop, cut from a two-loop recording at the measured period):
  01.png · 02.mp4 13.27 s · 03.mp4 9.70 s · 04.mp4 12.33 s · 05.mp4 13.63 s · 06.mp4 13.87 s · 07.mp4 13.80 s · 08.mp4 11.97 s · 09.mp4 13.90 s · 10.png
  posters 02–09.png: 02 correction + reply · 03 winning row · 04 News tab · 05 interview playing · 06 Drill chapter (struck → fixed) · 07 prompter "it **went** really well" · 08 alarm ringing · 09 report grammar card.
- Kit gaps (not edited — mkt-web): nw-watch always draws the "Job posting.pdf" chip + files note in the box (worked around in the carousel); nw-weeklytest `grammar` item shows its rule in English on a ko screen (used the `translate` item instead); kit demos for watch/review/sayagain/weekreport+test run 16–20 s, so the carousel scripts its own shorter scenes with the kit API.

## 2026-10-11 review round 3 — designer fixes applied
- carousel.html: card 09 desc per copy.md ("이어지는 테스트도 전부 내 대화에서 나와요." / "Then a short test, made from your own talks.", 2 lines); say-it-again STEPS[2] = "Nice! What surprised you most?"; report active days [1,1,0,0,1,1,1]; Watch uses `<nw-watch material="none">` (hand-hiding removed); Review deals the next card the moment the filed one leaves (no blank phone); the 05 "이 문장 섀도잉" tap now shows a touch circle + press dim, with the camera at 300 px so it sits inside the card.
- Re-rendered on the updated kit (two-loop cut, seams checked): 05.mp4 13.60 s · 06.mp4 13.70 s · 07.mp4 13.77 s · 08.mp4 11.97 s · 09.mp4 13.93 s, + 05–09.png. 01–04 and 10 unchanged.
- scripts/marketing/record.mjs: `--wait-for <js>` (poll until truthy before the warmup — the carousel sets `data-scene` when its scene starts, so no blank lead frame) and the MP4 is capped at exactly `--seconds` (late screencast frames dropped + `-t`). Exact loop seams still come from recording two loops and cutting at the measured period.
- Round 4: one FIX (가나다 overlap) fixed in kit bookpage.js:161; 06.mp4 re-rendered 23:24 (13.77 s), checked. All review items closed. Preview v11. Waiting for founder OK on the 10-card captions before upload + schedule.

## 2026-10-11 card 03 redesign — two options for the founder (03.mp4 untouched)
- `carousel.html?solo=3&v03=A` (stacked rows) / `&v03=B` (two columns); the default card is unchanged until one is picked.
- Voice-memo waveform (rounded bars, playhead fills while that voice plays — grey native, #0A5CF5 mine), grey person circle vs Futureself in a circle (lit while speaking), reactions inside their own row after each voice, the "me" row outlined at the end.
- renders/03-A.mp4 10.37 s + 03-A.png · renders/03-B.mp4 10.33 s + 03-B.png (two-loop cut, seam checked).

## 2026-10-12 card 03 with sound (founder)
- Layout B (two columns). Audio: 1 founder's own voice (web recording 1:09.5–1:15.3, "다만 제가 하고 싶었던 말을, 하고 싶었던 방식으로는 못 했어요.") → 2 native (Mark preset, take 3) → 3 founder's clone (take 3), line "Now I can say what I mean, the way I mean it." Files in audio/ (made by scripts/marketing/voice-compare.sh). Founder OK'd his own voice in public.
- Still open: the cover title / series framing (founder rejected all title options; picked '몇 년 뒤의 나에게 배워요' then said '말이 떨어지지 않는다' + the speak-again video — unresolved).

## 2026-10-12 card 03 — variant B with real audio (founder pick)
- carousel.html: card 03 now defaults to B (`?v03=A` still shows A). Sentence → "Now I can say what I mean, the way I mean it." Beat 1 "지금의 나" strip plays audio/1-my-voice.mp3 with a word-timed Korean subtitle; beat 2 native column (2-native.mp3) → reaction; beat 3 "유창한 나" (3-clone.mp3) with the mosaic lit by the clone's own loudness envelope → reaction + win. Bars are each file's measured envelope and move only over that file's real duration. Quiet "소리 켜고 들어보세요" + speaker glyph on the sentence line. The preview page plays the files; the recorder is muted.
- renders/03.mp4 14.07 s (one loop, two-loop cut, AAC audio muxed at the visual onsets 0.62 / 6.98 / 10.55 s, checked frame by frame) · renders/03.png (clone speaking, mosaic lit, native reaction shown). 03-A/03-B kept as the options record.

## 2026-10-12 card 03 — founder layout (native strip on top, 지금의 나 | 유창한 나 below)
- Order follows the layout: native strip (2-native.mp3, the English line, reaction one line) → 지금의 나 (1-my-voice.mp3, Korean subtitle broken at the comma) → 유창한 나 (3-clone.mp3, mosaic lit by the clone envelope and kept lit on the win, reaction broken at the sentence). Both columns tagged "내 목소리"; "소리 켜고 들어보세요" above the strip; bottom margin ~72 px.
- renders/03.mp4 14.40 s (one loop, AAC muxed at 0.41 / 4.08 / 10.42 s, matched to the visual onsets) · renders/03.png = end state (reaction + highlight, mosaic lit).

## 2026-10-12 card 03 — stripped to two voices (founder)
- Sentence once, then two cards: AI 원어민 음성 (남의 목소리) | 유창한 나 (내 목소리). A pulsing ring around the speaking avatar is the only motion; mosaic lit by the clone's envelope and kept lit; blue border on 유창한 나 at the end. No waveforms, 지금의 나, reactions or hints.
- renders/03.mp4 8.60 s (one loop; AAC: 2-native at 0.53 s, 3-clone at 3.80 s, matched to the visual onsets) · renders/03.png = end state.
