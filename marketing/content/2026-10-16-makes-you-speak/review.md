# Review · 2026-10-16-makes-you-speak · 2026-10-16 (round 2)
Verdict: PASS

All 10 FIX items from round 1 are closed. I checked each one against the new renders (ko and renders/en/).

1. card 06 first frame (designer): closed. Frame 0 is the 스피치 / Speech list with 면접 자기소개 / Interview intro visible. The leftover challenge result and the gauge at 0 are gone (ko and en @0, 0.3 s).
2. card 06 gauge colour (mkt-web, designer): closed. 86 now draws green, which matches `SpeechScoreColor` (≥85 green). The 76 frame in the count-up is green too. That is right, because the app tints by the final score and the count-up is our motion.
3. card 06 fifth row (designer): closed. On the final hold (@10, 11.8 s) the 목소리 안정감 / Steady voice row and its sub-label sit fully inside the card in both languages.
4. card 04 legibility (designer): closed. The screen is at full size during the target and the take. The target line and karaoke can now be read at feed size.
5. card 04 length (designer): closed. ko and en are both 12.0 s.
6. cards 02/03 first-frame jump (designer): closed. Frames @0 and @0.3 s show the same settled layout. The only motion is the next line entering, which is intended.
7. "Future self" on ko (mkt-web, designer): closed. ko cards 02 and 03 now say 미래의 나, which matches card 05 and the app. en still says Future self.
8. Threads en length (copywriter): closed. It is 484 chars, and the duplicated "Start where you are" is gone.
9. Threads ko opener (copywriter): closed. It now reads "이번엔 다섯 가지를 한 번에 묶어 봤어요."
10. en renders (designer): closed. renders/en/ has 01–07 at 1080×1350. The en text blocks fit and the en outro is correct.

## The designer's card 04 trade-off (accepted)
At full size, the red record button sits below the window during the take. I accept it:
- The 3·2·1 countdown is on screen, and so is the karaoke moving with the take, so the card still reads as "now you say it".
- The result card with 들린 내용 / What I heard is in frame, and that is the claim the desc makes.
- Legibility of the line matters more than showing the button.

## Suggestions (non-blocking)
- card 04: the loop ends zoomed out (.9, on the result) and restarts at 1.0 on the bare target, so each loop visibly jumps. The jump lands on the loop seam, so it reads as a restart. Leave it as is, or add a 300 ms ease back to 1.0 in the last beat.
- card 04: if the founder misses the red button, a small red-record sticker beside the phone during the take would give the cue without shrinking the screen.
- card 06 ko desc "프롬프터로 보며" → "프롬프터에 띄워 놓고" (taste, carried from round 1).
- Desktop export is still to do (publisher step).

Checked frames: renders/02.mp4 03.mp4 04.mp4 05.mp4 06.mp4 and renders/en/ same set, each @0 0.3 2 4 6 8 10 s, plus 04 and 06 @11.8 s; ko and en bottom crops of 06 @11.8 s; 01.png, en/01.png, en/07.png.
