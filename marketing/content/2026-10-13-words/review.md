# Review · series 05 단어장 (Words) · 2026-10-14
Verdict: FIX

Checked against CLAUDE.md (learning loop: keepFromTalk / pickupCandidates, autoKept vs practicedStudyingWords, chip row, used outranks known), HEAD code (`VocabularyView`, `ConversationView`, `VocabStore`, Localizable.xcstrings), BRAND.md, CHANNELS.md, series.md, brief.md, copy.md, carousel.html, renders/, and the Desktop export (byte-identical to renders/).

Truth holds overall: words come from the fluent self's lines (02 never says "내가 한 말에서"); the pronounce button is gated on `voiceCloneId` and speaks the clone; deck labels 10분 · 내일 · 3일 · 알아요 match the catalog; filing to 내일 on 04 is also what clears `autoKept`, so the word can legitimately appear as a chip on 05 (story order is correct); 05 is an ordinary call with no coach line; 06's "'알아요'보다 한 단계 위" is used-outranks-known.

1. [visual] card 04, renders/04.mp4 @0.0 s: the deck prompt shows the app string with an em dash, "소리 내어 말해 보세요 — 알고 있나요?". `undash()` runs on a 60 ms interval, so the first frame is captured before the sweep (fixed by 0.3 s). Frame 0 is also the paused state on Instagram. Fix: run `undash(card)` once synchronously at the start of `run()` (after `customElements.whenDefined` and again right after each `PLAY[k]` builds its screen, before its first `sleep`), or swap the interval for a MutationObserver on the shadow roots. Re-render 04 and check that frame 0 reads "소리 내어 말해 보세요. 알고 있나요?".
2. [fidelity] card 05: the other speaker's label reads "Future self" in English on the Korean card. The app writes `chrome("Future self")`, which is "미래의 나" in ko (ConversationView.swift:682/4673, catalog key "Future self"). The kit's `nw-call._otherName` falls back to a hardcoded English string. Fix: in the 05 scene set `call.other = $("#wrap").lang === "en" ? "Future self" : "미래의 나";` before `call.run` (or fix the kit fallback to use its `L` table). Re-render 05. Also correct the status.md note that the app labels it "Future self".
3. [fidelity] card 05: the call header reads "B2 ›" but the same learner's book (02, "B1 레벨 설정을 기준으로…") and word map (03/06, B1) are B1. It's one story with one learner, so the level must match. Fix: `<nw-call level="B1">` in carousel.html. Re-render 05.
4. [visual] card 05, renders/05.mp4 @9.3 s: the key moment (the compelling chip turning green) is a ~5 px green dot on a ~9 pt chip when the 1080 px card is seen at phone width (checked by downscaling to 390 px). The phone is stepped back (.86), and for the first ~3 s the window is an almost empty transcript. Fix: after `k.tick(0)`, zoom the camera onto the chip row and the last line, e.g. `pan(c, 40, false, 1.3);` (origin is 50% 0, so the chips stay in the window), then hold `k.sleep(2600)`. Optionally start with the first exchange already on screen so frame 0 isn't an empty call. Re-render 05 and re-cut its poster on the zoomed tick.
5. [voice] card 01 en desc (copy.md + carousel.html `EN.cover.desc`): "The fluent you's words, learned in your own voice." The possessive on "the fluent you" doesn't read as native English. Replace with: "Words the fluent you used, learned in your own voice."
6. [truth] Threads ko (copy.md + captions.txt), sentence 3: "내 얘기로 통화하다 보면 단어도 내 얘기에서 나와요." This reads as if the words are picked from what I said, which is the brief's named trap (the words come from the fluent self's lines, and mine are excluded). Replace with: "내 얘기로 통화하면, 유창한 내가 쓰는 단어도 내 얘기에 맞는 단어예요."

## Suggestions (non-blocking)
- 06 ko desc "확실히 내 것이에요" leans on a claim. "'알아요'보다 한 단계 위예요." stops at the fact.
- 05 en desc "ride along the call" → "come along on the call as chips at the top".
- 02: the book page's footnote is English on the Korean card ("Tap a word for its card…"). The app really shows it that way (it's an unlocalized `pageFooter(String)`), so it's faithful, but it's an app bug worth a ticket. Same for "MEANING / EXAMPLE / FROM YOUR TALKS" and "Talk" on 03 (verbatim `String`s in VocabularyView / VocabStore).
- 04: the folder counts (내일 1 → 2) are illegible at phone size at scale .78. The tray during the drag reads fine, so the beat survives.
- captions.txt: say which items go on the Threads reply (copy.md says "first 6 items").
- 06's cloud change on "compelling" sits in the top fade and is small. The sheet's green check carries the beat; fine as is.

Channel: 1080×1350, 30 fps, 8.2–11.0 s (≤ 60 s) ✓; IG 5 hashtags each ✓; Threads 261 chars, no hashtags, a reply under 04 that opens on the problem with no re-introduction ✓; captions say nothing about sound ✓; no 당신, no em dash in our text ✓; titles 2 lines, descs ≤ 2 lines ✓; card numbers 01–07 consistent ✓; mosaic only clipped in pills ✓. Safety: sample data only, no real names ✓.

Checked frames: renders/02.mp4 @0 0.3 2.79 5.08 7.20 8.42 · 03.mp4 @0 0.3 3.17 5.76 8.16 9.55 · 04.mp4 @0 0.3 3.63 6.60 9.35 10.95 · 05.mp4 @0 0.3 3.60 6.54 9.27 10.85 · 06.mp4 @0 0.3 2.72 4.94 7.00 8.18 · 01.png · 07.png (phone-width downscale on 04@0, 05@9.27, 06@4.94).
