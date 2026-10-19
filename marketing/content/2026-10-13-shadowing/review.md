# Review · series 02 · Shadowing (silent build) · 2026-10-14
Verdict: FIX (4)

1. [truth] card 07 + captions: the bar is "80 or above" (`best >= ScenarioCurriculum.shadowMasteryScore`, Models.swift:1842 = 80). "80점을 넘으면/넘기면" says a take of exactly 80 does not count. Replace:
   - card 07 title (ko): `80점을 넘으면\n교재에 체크` → `80점 이상이면\n교재에 체크`
   - card 07 desc (ko): `문장 전체로 80점을 넘기면 섀도잉 장에 **체크**가 생겨요.` → `문장 전체로 80점 이상이 나오면 섀도잉 장에 **체크**가 생겨요.` (second sentence unchanged)
   - IG caption (ko), copy.md + captions.txt: `80점을 넘기면 교재에 체크돼요.` → `80점 이상이면 교재에 체크돼요.`
   - Threads (ko): `80점을 넘기면 교재에 체크되고요.` → `80점 이상이면 교재에 체크되고요.`
   - cover chip 07 is fine as is ("교재에 체크"). en is already correct ("at 80 or above", "80 or more").

2. [voice] card 03 desc + IG caption (ko): "그래서 그 차이가 좁힐 수 있는 거리로 들려요" reads translated ("the gap you hear is one you can close"). "그 차이" has no antecedent on the card: nothing has said what differs from what. Replace with a line that cashes in piece 01 card 02 ("닿을 수 없는 목표"):
   - card 03 desc (ko): `들리는 건 몇 년 뒤의 내 목소리예요. 그래서 **나도 닿을 수 있는 목표**로 들려요.`
   - IG caption (ko) line: `들리는 건 내 목소리라, 그 차이가 좁힐 수 있는 거리로 들려요.` → `들리는 건 내 목소리라, 나도 닿을 수 있는 목표로 들려요.`
   - en stays ("so the gap you hear is one you can close" is natural English).

3. [visual] 04.mp4 frame 0 is stale: the first frame (t=0.000, one frame) shows the finished 72 result from the previous loop, then cuts to the fresh shadow screen at 0.033 s. IG shows frame 0 as the video's still before playback, so the card opens on the answer before the countdown. Fix: re-cut 04 starting at the first fresh frame (drop frame 0, e.g. `-ss 0.034`), re-export to renders/ and the Desktop folder. (05/06/07 also open on the 72 result, but there it is the intended opening state.)

4. [visual] 03–07, zoomed camera (scale .76): the top fade cuts the shadow screen's nav bar mid-glyph, so "닫기 · 섀도잉 · bookmark" sit half-erased as grey ghost marks at y≈470–490 (03 @4s, 05 @9s, 06 @3.5s, 07 @2.5s/5s). It reads as broken text right above the line. Fix: on the zoomed camera either move the fade's opaque band down so the nav bar is fully hidden (fade ends above the "원본 문장 · 8/9 64" row, which must stay fully visible: it is 05's metronome score), or pan so the whole nav bar is in view. Either way, no partially drawn glyphs.

## Passed
- Truth: up to 4 lines per talk (`TalkCurriculum.maxShadowLines = 4`), level-banded picks, cloned voice as target, 3·2·1, "일치도" = target coloured / "들린 내용" = transcript (matches `diffSection`), beat dots only on measured words (8/9 shown), loop 0.5×–1.25× (`TLConst.speeds`), "겹쳐 듣기" from first words, two sentence rows (turn split), 72/86 sample data, "첫 20분은 무료예요" only price line. No "발음 점수", no 억양, no trial/unlimited.
- Fidelity: kit screens throughout; book → Shadow chapter → shadow screen → back to chapter → cover flow is the app's; app labels are the app's ko strings; 07 shows the green check + 86, ribbon 0/2 → 1/2, cover 4/14 → 5/14.
- Voice: 해요체, no 당신, no em dash on any card/caption (carousel.html dashes are code comments only), no hype, "몇 년 뒤의 내가 한 말" correctly attributes the line to the fluent self. Tutor comparison stays a feeling, not a knock.
- Visual: cover title 96/110 px, 2 lines, legible at phone size; every title and desc ≤ 2 lines; zoomed line text (~26 px) readable; key moments inside each card; palette #0A5CF5 + app green/orange/red only; mosaic clipped in the pill; eyebrows 01–08 consistent.
- Channel: 1080×1350, MP4s 8.2–15.4 s, Threads ~300 chars as a series reply, no hashtags; IG 5 hashtags. Silent build: "소리 켜고" hint removed from card 06, IG and Threads (restore when audio lands, as status.md says).
- Safety: no real user data or names; founder voice not used yet (silent).

## Suggestions (non-blocking)
- 02: copy/alt say row 2 is tapped, but 02 ends on the static chapter and the tap happens at the top of 03. Either show the press at 02's end or make the alt say "열어요" instead of "눌러요".
- en card 07 title "Pass 80, it's checked off" can read as "above 80"; "80 or above,\nit's checked off" matches the desc.
- "지난 글의 면접 통화" (IG caption): on IG other posts may sit between piece 01 and this one; "시리즈 1편의 면접 통화" survives any posting order. Fine on Threads (it is a reply).
- Only the ko set is rendered; render `?lang=en` too if an English IG post is planned.

Checked frames: 01.png · 08.png (outro matches piece 01) · 02.mp4 @0 2 4.5 6.5 7.5 7.9 8.1 · 03.mp4 @0 1.5 4 6.5 9.2 · 04.mp4 @0 0.05 0.4 0.8 1.1 1.5 2 4.5 7 10.5 12 13.2 · 05.mp4 @0 3 6 9 12 15.2 · 06.mp4 @0 1.5 3.5 6 9.1 · 07.mp4 @0 2.5 5 8 10 12.5 13 15.3 15.4 · first 3 frames of every MP4.
