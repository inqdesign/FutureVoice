# 2026-11-03-pronunciation — status

- **Stage:** failed (blocked on a capture)
- **Version/build:** 1.2.9 (127), phase upload
- **Request:** autopilot — tell 1.2.9's new feature
- **Owner:** lead

## One message
섀도잉과 스피치에서 내 녹음을 원어민 발음과 비교해 소리 단위로 점수를 매기고,
어긋난 단어에 밑줄을 긋고, 어느 소리를 고치면 되는지 코치가 알려 줘요.

## Why blocked
1.2.9's only tellable feature is **pronunciation assessment** (Azure, per-sound).
Its UI is a NEW visual:
- a dotted underline under words Azure faulted (text colour already means "wrong word", the dot below means the beat),
- a "Pronunciation" line (score + weak words) under the shadow diff,
- a coach bullet that names the word and the sound.

Neither the kit nor a capture shows it:
- `web/kit/screens/shadow.js` / `speech.js` render only the old Target/You/Pace + score + diff + beat-dots.
- `marketing/captures/shadow.png`, `speech-result.png` are from Oct 11 — before the feature.

Autopilot cannot draw a screen, and may only build a kit screen when a capture already exists.
No valid capture exists, so this piece is parked.

## To unblock
Add a `-capture` harness case for the shadow result AND the speech result WITH the
pronunciation underline + line + coach, save to `marketing/captures/`, then rebuild
(mkt-web adds the UI to `shadow.js`/`speech.js` per FIDELITY.md → full pipeline).

## Rest of 1.2.9 (no carousel)
- fix(say-again): script card background / conversation showing through — visual fix.
- fix(gateway): German calls re-transcribe per line — server fix.
