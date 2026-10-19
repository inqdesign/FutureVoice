# 나와나로 할 수 있는 것들 — series cover carousel

- **Stage:** v4 (core flow, 9 cards) renders done 2026-10-13 — next: review, then founder approval of captions + cover
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

## 2026-10-13 rethink (lead) — story order + new cover
Founder: "아무 생각없이 만든 순서", "제목이 별로", series OPENER (interview-week story = next piece), picked "몇 년 뒤의 나에게 배워요", then "말이 떨어지지 않는다".
- Cover: the problem in the founder's words (말이 안 떨어진다) → the answer (몇 년 뒤의 나에게 배워요). No more "나와나로 할 수 있는 것들".
- Order by the learner's experience, eyebrow = stage (no repeated series name):
  01 cover · 02 만나기 — 몇 년 뒤의 나 = my voice (the two-voice card, audio) · 03 말하기 — talk with it (call + correction) · 04 말하기 — about anything (Talk home) · 05 말하기 — before it happens (Watch) · 06 남기기 — the talk becomes a book · 07 남기기 — same call, said right · 08 이어가기 — it calls you every day · 09 이어가기 — your week + test · 10 outro.
- Next piece queued: 면접까지 일주일 (backlog).

## 2026-10-13 design — v3 copy applied, renders done
- carousel.html: copy.md v3 applied. Card swap (two voices = 02 `data-k="compare"`, call = 03); eyebrows = stage · NN / 10 (만나기 · 말하기 · 다지기 · 이어가기; cover "nawana · 01 / 10"), the series name is gone everywhere (title tag, aria-label, side panel). New cover (title, bold first desc line, 8 chips), every title, descs 02/03/04/08/09, card 04 one bold, side index list follows the titles. `?lang=en` carries each card's own stage + the v3 English. Layout, light theme and #0A5CF5 untouched; two-voice on-card labels unchanged.
- Fit (ko, rendered): every title 2 lines, every desc 2 lines, cover title fits at 110px. EN (check only, not rendered): 05 and 09 descs wrap to 3 lines ("…Shadow it right / there.", "…and past / misses come back.") — copywriter to trim if the en set is ever rendered.
- renders/ (two-loop recording, second loop cut at the measured period, seams checked; posters at the same moments as before):
  01.png · 02.mp4 8.60 s (two voices; the original AAC track copied over unchanged, cut placed so the visual onsets match it exactly: native ring 0.80 s, clone 3.77 s, same as the old 03.mp4) · 03.mp4 13.27 s (call) · 04.mp4 12.33 s · 05.mp4 13.60 s · 06.mp4 13.77 s · 07.mp4 13.77 s · 08.mp4 11.97 s · 09.mp4 13.93 s · 02–09.png · 10.png unchanged (outro has no number).
- 03-A / 03-B option renders removed.

## 2026-10-13 founder: this piece = the CORE FLOW only (talking)
"여기서는 그냥 말하기만. Watch는 빼고, 코어 플로." Core = (1) tell the story in my head to myself, as comfortably as possible (2) it corrects what I said (3) it suggests what I could say (4) the talk becomes a book (5) words · sentences · expressions · grammar · shadowing make it mine (6) it remembers what I said.
New outline (9 cards): 01 cover (problem → 몇 년 뒤의 나에게 배워요) · 02 my own voice (two-voice card, audio, kept) · 03 talk to myself comfortably (call) · 04 corrects what I said (correction card) · 05 suggests what I could say (call coach "이렇게 말해 보세요") · 06 the talk becomes a book · 07 words/sentences/expressions/grammar/shadowing → mine · 08 it remembers what I said (the next call opens on what I said before) · 09 outro.
Dropped from this piece: Talk topics home, Watch, Say it again, daily call, weekly report/test.
Series order (founder): 1 core (this) → 2 Speech → 3 Watch → 4 Routine (daily call, weekly report/test, streak).

## 2026-10-13 design — v4 (core flow, 9 cards) renders done
- carousel.html rebuilt per copy.md v4: eyebrow "nawana · NN / 09" on every card, 7 new cover chips, side index follows the titles, `?lang=en` carries the v4 English. Light theme, #0A5CF5, text layout untouched. Fit (ko, rendered): every title 2 lines, every desc 2 lines.
- Scenes: 03 nw-call opener → learner's busy-week line → thinking (no correction) · 04 same call from the sent line: reply starts speaking, the correction card lands 0.7 s into the voice, held · 05 the reply line → listening → "이렇게 말해 보세요 · The last one, honestly. We finally agreed on ___." + "써 볼 단어 · finally" → typed answer, chip + hint tick to "썼어요" the moment "finally" is said, held 1.5 s, then thinking · 06 Studying page: the call's book lands on top (`nw-book.arrive`), tapped → cover · 07 cover → 단어 → 표현 → 섀도잉 → 드릴 (struck → fixed, the grammar slips) → "이 대화 복습하기" → card answered aloud, checked, filed into 내일, next card dealt · 08 new nw-call opening on "Hey! Last time you had three meetings a day…" → answer → follow-up. 02 two-voice card unchanged except the eyebrow.
- renders/ (sequential recording, second loop cut at the measured period): 01.png · 02.mp4 8.60 s (original AAC copied over unchanged, frames aligned to the old 02.mp4 at offset 0) · 03.mp4 9.13 s · 04.mp4 8.57 s · 05.mp4 9.07 s · 06.mp4 8.67 s · 07.mp4 15.23 s · 08.mp4 11.90 s · 09.png (outro) · posters 02 end state, 03 line sent, 04 correction + reply, 05 suggestion line + word hint, 06 book cover, 07 Drill chapter, 08 the full remembered exchange.
- The v3 set (10 cards: Talk home, Watch, Say it again, daily call, week + test) moved to renders-v3/ with its carousel.html, for the later episodes.
- Gaps: (1) the book page has no separate Grammar chapter — the kit (and the app's ribbons) carry Words · Expressions · Drill (grammar icon) · Shadow; the Drill chapter is shown as "고친 문장 + 문법". (2) 06/07 use the kit's sample book, the interview talk ("Honestly, it went really well. I…"), not this piece's busy-week call — a busy-week book needs material from the copywriter and the kit's review/book sample swapped (mkt-web). (3) Card 05's learner answer "The last one, honestly. We finally agreed on the budget." is not in copy.md (needed to show the tick) — copywriter to confirm. (4) No Me → Profile remembered-line beat on 08 (needs a kit capture).

## 2026-10-13 design — v4.1 continuity fix (lead)
- Calls 03/04/05/08 are now the kit's sample book's talk (the job interview): 03 "…So, how did the interview go?" → "Honestly, it go really well. I felt prepared." · 04 reply "Nice, you sound relieved! Which question was the hardest?" + the book's first Drill fix (went) · 05 Try saying "The one about [my weak points]. I took the initiative there." + Try using · took the initiative (a book expression) → Used it · 08 "Hey! Last time you had that interview. Did you hear back?" → "Yes! They call me yesterday. I got the job." → "No way, congrats! So when do you start?". Chips: felt prepared · took the initiative · what mattered most. Lines written into copy.md ("For the designer" v4.1 + per-card material); ALT texts / captions still mention the busy week → copywriter. Gaps (2) and (3) above are closed by this.
- 03/08 seam: the opener line is laid down the moment the loop starts (no lead wait), so no blank phone between loops.
- Re-rendered: 03.mp4 8.93 s · 04.mp4 8.07 s · 05.mp4 9.73 s · 08.mp4 10.70 s + their PNGs. 01, 02, 06, 07, 09 unchanged.

## 2026-10-13 design — final pass (wordmark, Cartesia clone, round-5 copy, coached book)
- Wordmark face: "nawana" in every eyebrow, the cover footer and outro url "nawana.app", and the outro wordmark now use Pixelify Sans (the app's WelcomeView wordmark). `@font-face` tries `PixelifySans.woff2` beside the page (preview), then `../../../web/` and `/web/` (record.mjs serves the repo root); the page awaits the face before the first scene, so `--wait-for` renders never open on the fallback. Titles and the "NN / 09" number keep Geist Pixel.
- 02 audio: `audio/3-clone.mp3` is the founder's Cartesia take (3.12 s). Ring/play span and the mosaic envelope re-measured from the file (24 bins, the mid pause at 1.76–1.99 s shows as a dip). Muxed: native file at 0.85 s (voice 0.87–2.91, ring from 0.87), clone at 3.86 s (voice 3.97–6.85, ring 3.93–~6.9), checked frame by frame. Also closes review suggestion i (native ring now lights with the voice).
- Copy (copy.md round 5): 05 desc (코치 모드를 켜면…), 07 desc (four chapters, 문장 카드는…), 08 new five-line call (timeless opener, the interview surfaces in the reply), 04 correction "…really well. I felt prepared." on 04/05/07. ko descs 05/07 fit 2 lines (rendered).
- 06/07: `<nw-review coached>` — the cover shows 연습 대화 + practice note instead of a score; book titled "How the interview went".
- No em dash on screen: the kit's Words-chapter footer ("Tap a word for its card — …") was visible on 07; the carousel now sweeps the screens' text and draws it as a colon (en) or full stop (ko). The kit strings themselves (bookpage.js fWords/fExpr/fDrill/fRun/context) are mkt-web's to fix.
- renders/ (two-loop recording, second loop cut at the page's own loop timestamps): 01.png · 02.mp4 8.60 s (AAC) · 03.mp4 8.97 s · 04.mp4 8.03 s · 05.mp4 9.70 s · 06.mp4 8.63 s · 07.mp4 15.23 s · 08.mp4 13.53 s · 09.png · posters 02–08.png.

## 2026-10-13 handed to founder for MANUAL upload
- Exported to ~/Desktop/nawana-carousel-01-core/ (01.png, 02–08.mp4, 09.png, posters/, captions.txt). Founder posts by hand; no scheduler. Latest review round (5) FIX items all applied by copy/kit/design; not re-reviewed after the final pass.

## 2026-10-13 design — 06/07 fill (founder: empty cover, show shadowing, checks)
- `coached` removed from 06/07: the book is an ordinary call (score, checks).
- 06: shelf → book lands → cover, then the cover scrolls slowly (bp.scrollTo): score 75 with axes + 발음 80 → 코치 노트 → 연습한 걸 실제로 썼어요 (took the initiative, walk someone through). Poster 06.png = 코치 노트 + both carryovers.
- 07: 단어 → 표현 (green checks, held 1.2 s) → 섀도잉 chapter → line tapped → `<nw-shadow>` slides up over the book: target plays (karaoke) → 3·2·1 → take → match 96 → closes → 드릴 → 이 대화 복습하기 → sentence card answered aloud, flipped. Poster 07.png = the shadow result (96, match + heard).
  The shadow screen carries the book's Shadow line ("That's a compelling perspective…"), set through nw-shadow's own `_words`/`_color`; no beat dots and no rhythm figure (a call line's timings are estimated, the app grades no rhythm there). Durations cells (5.7s / 6.5s / 1.13x) stay the kit's sample.
- renders: 06.mp4 12.73 s · 07.mp4 17.13 s (two-loop recording, second loop cut at the scene-change seam) + 06.png · 07.png. Frames checked.
- Gaps (kit, mkt-web): nw-shadow has no `line` input (its LINE is hard-coded); during the take the mic sits below the visible window, so recording reads only by the 3·2·1 and the karaoke; after a passing take the Shadow chapter row/ribbon still reads 0/1.

## 2026-10-13 design — 02 audio retimed (tempo-adjusted takes)
- New files: audio/2-native.mp3 2.77 s (voice 0.02–2.31) · audio/3-clone.mp3 2.57 s, founder's new Cartesia take (voice 0.11–2.42). carousel.html: AUD durations 2.765 / 2.571 (at 0.6 / 3.86, end 8.6 unchanged), nat + cl envelopes re-measured (24 bins, RMS^0.6, the clone's mid pause shows as the dip at bins 13–14).
- renders/02.mp4 8.60 s re-recorded (second loop cut at the page's own reset), both files muxed at the visual onsets, checked frame by frame: native ring 0.833 s = voice 0.832 s, clone ring 3.833 s = voice 3.833 s; win state held ~2.4 s to the seam. 02.png = win state (8.3 s).
- Copied to ~/Desktop/nawana-carousel-01-core/02.mp4 and posters/02.png (only those two overwritten).

## 2026-10-13 card 02 sentence (founder pick, short version)
"Keep talking with me, a little every day. The words will come. One day, you'll sound just like this." — AI 튜터 (Mark via voice-compare.sh) vs the founder's Cartesia take; waiting for both takes.

## 2026-10-13 design — card 02 v4.2 final (AI tutor, three-sentence line)
- carousel.html: left label "AI 튜터" / "AI tutor" (sub unchanged) in both places; ko + en desc per copy.md v4.2; sentence "Keep talking with me, a little every day. / The words will come. / One day, you'll sound just like this." broken at sentence ends (3 lines, desc stays 2 lines, cards not crowded).
- Audio: audio/2-native.mp3 (AI tutor, 6.78 s, voice 0.09–6.45) at 0.8 s · audio/3-clone.mp3 (founder's Cartesia, 6.88 s, voice 0.15–6.67) at 8.0 s · end 16.2 s (~1.5 s win hold). AUD now carries each file's voice span, and the ring pulses only over it; the pulse starts at its peak so it lights on the voice's first frame. nat + cl envelopes re-measured (24 bins, RMS^0.6).
- renders/02.mp4 16.23 s (first loop of a two-loop recording: loop 2+ showed the tutor ring ~0.23 s late, loop 1 matched the timeline), both files muxed: tutor ring 0.867–7.233 s = voice 0.877–7.244 s, clone ring 8.133–14.633 s = voice 8.136–14.68 s. Seam: ends on the win (blue outline, mosaic lit), restarts plain. 02.png = end state.
- Copied to ~/Desktop/nawana-carousel-01-core/02.mp4 and posters/02.png (only those two).

## 2026-10-14 design — HQ re-render (record.mjs: 2× supersample → lanczos, CRF 12, BT.709 tv range)
- All nine re-rendered on the current carousel.html, same per-card method: raw 2× frames dumped, one loop cut at the page's own `loopStarts` (03–08 loop 2, 02 loop 1) and encoded once with record.mjs's settings; 01/09 via record.mjs `--png-at 1`; posters 02–08 = the 2× frame closest to the previous poster, lanczos to 1080×1350.
- Durations / total bitrate: 02 16.17 s 438 kb/s (incl. AAC 192k) · 03 8.93 s 423 · 04 8.07 s 626 · 05 9.70 s 654 · 06 12.77 s 1060 · 07 17.17 s 787 · 08 13.53 s 575 kb/s. Seams checked (first ≈ last frame), 4 frames per card looked at.
- 02 audio: at 2× the capture runs ~3% slow against the page clock (clone ring/mosaic ~0.2 s later than in the old file), so the files are placed by the new visuals: 2-native at 0.787 s (ring 0.867), 3-clone at 8.150 s (ring 8.267, mosaic 8.2); end of each voice within ~0.1–0.3 s of its ring's last pulse. Win hold to the seam ~1.2 s.
- Copied to ~/Desktop/nawana-carousel-01-core/ (01.png, 02–08.mp4, 09.png, posters/02–08.png; captions.txt untouched).
- 2026-10-14: 07.mp4 + 07.png re-rendered (HQ, same method) on the fixed kit shadow karaoke (sung words dark, current word blue, rest grey); Desktop 07.mp4 + posters/07.png overwritten.
- 2026-10-14: kit loop tiles. carousel.html shadowLine() now keeps every word selected (`sel`, was stripped), so the whole line wears the light-blue tile, as the app opens the trimmer; 07.mp4 + 07.png re-rendered (HQ), Desktop copies overwritten.

## 2026-10-14 design — Korean clarity pass
- ko text from copy.md applied (cover chips 03 · 05 · 07 · 08, desc 02, 03 title + desc, 05 title + desc, 07 title + desc, 08 desc, side list); en unchanged. Every ko title/desc fits 2 lines (03 desc fits one).
- Re-rendered (HQ record.mjs, periods re-measured): 01.png · 02.mp4 16.20 s (loop 1, as before) · 03.mp4 8.93 s · 05.mp4 9.77 s · 07.mp4 17.18 s · 08.mp4 13.56 s (loop 2, one period) + posters 02 (win) · 03 (answer, thinking) · 05 (Try saying + took the initiative) · 07 (shadow result 96) · 08 (congrats line). 04, 06, 09 untouched. Frame cadence ≥ the previous renders (mpdecimate).
- 02 audio re-muxed by the new visuals (AAC 192k): 2-native at 0.853 s (tutor ring 0.933, voice 0.947), 3-clone at 8.050 s (clone ring 8.167, voice 8.203): the same ring→voice gaps as the previous file (+0.014 / +0.036 s); win hold ~1.45 s to the seam.
- Desktop ~/Desktop/nawana-carousel-01-core/: 01.png, 02/03/05/07/08.mp4 and posters 02/03/05/07/08 overwritten; captions.txt untouched.

## 2026-10-14 design — English set (`?lang=en`)
- carousel.html en strings set to copy.md's English clarity pass (cover title/desc/chips, 02 title + desc, 03 title + desc, 05 title + desc, 07 title + desc, 08 desc, page title). en cover title "You just can't say it." wrapped to 3 lines at 110 px → en-only override 94 px (`#wrap[lang=en] .c-cover .ttl`); ko untouched. Every en title/desc renders in 2 lines. Kit screens all English (no Korean chrome or coaching seen).
- renders-en/ (HQ, two-loop recording, one loop cut at the page's loopStarts, one render at a time, caffeinate): 01.png · 02.mp4 16.20 s (loop 1, AAC 192k) · 03 8.93 · 04 8.06 · 05 9.71 · 06 12.77 · 07 17.14 · 08 13.51 s · 09.png + posters 02 win · 03 answer/thinking · 04 correction + reply · 05 Try saying + Try using · 06 coach note + carryovers · 07 shadow result 96 · 08 congrats line. Frame cadence (mpdecimate) matched to the ko renders (06, 08 re-rendered once for dropped frames).
- 02 audio: 2-native at 0.887 s, 3-clone at 8.050 s (en tutor ring lands 0.034 s later than ko; clone ring identical). Voice 0.981 vs ring 0.967; clone voice 8.203, same gap as the ko file.
- Exported to ~/Desktop/nawana-carousel-01-core-en/ (01.png, 02–08.mp4, 09.png, posters/); captions-en.txt untouched.
