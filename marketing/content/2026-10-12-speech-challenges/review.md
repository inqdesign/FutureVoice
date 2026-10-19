# Review — 2026-10-12-speech-challenges — 2026-10-12 (round 2)

Verdict: PASS

Round-2 re-review after the designer re-recorded cards 04 and 05. The round-1
blocker (04/05 opened and loop-seamed on a half-faded double-exposure) is FIXED.
The round-1 EN-render item was out of scope for this pass (autopilot registers
one ko slide set; DB has no per-language slides) and is not held against the piece.

Verified this pass (actual frames extracted, not the designer's claim):

- (a) 04.mp4 — first frame (n=0) and last frame are the SAME settled single
  screen: orange gauge at 81, coach line "이 원고를 지금까지 읽은 것 중 가장
  또렷하고 안정적이에요.", tip row, 챌린지 "41명 중 14위로 올라갔어요", 내 녹음
  듣기, 측정 결과. No overlapping/half-faded screens at the seam. The middle of
  the loop is a clean vertical scroll that reveals the 측정 결과 rows
  (정확도 94% · 말하기 속도 148단어 · 쉼 4/5 · 군말 2 · 목소리 안정감 76) and
  settles back. 8.0 s, 240 frames, 30 fps, 1080×1350.
- (b) 05.mp4 — first frame and last frame are the SAME settled rank-up sheet:
  green up-arrow, "14위 → 8위", "7위까지 1점 남았어요", rows 7 Camille 88 /
  8 Jiwoo 나 87 / 9 Yuna 85, 리더보드 보기, 완료. Static hold throughout (mid
  frame identical). No overlap. 8.0 s, 240 frames, 30 fps, 1080×1350. (The dim
  "41명 중 14위로 올라갔어요" strip peeking above the sheet is the parent screen
  behind an iOS modal sheet — correct app fidelity, identical at both ends, not
  the round-1 crossfade bug.)
- (c) No founder real name "Eunggyu" on card 05 or any extracted frame — only
  kit sample names (Camille, Jiwoo·나, Yuna).
- (d) Score on 04 is still 81, orange (<85), unaltered.
- (e) Posters 04.png / 05.png match the settled state exactly (04 = the 81
  result screen, 05 = the 14위 → 8위 sheet).

Everything else carried its round-1 PASS (truth, claims, voice, cards 01/02/03/06
unchanged). No new FIX items.

Checked frames: renders/04.mp4 @0s 4s 8s (first/mid/last); renders/05.mp4 @0s 4s 8s
(first/mid/last); renders/04.png; renders/05.png.
