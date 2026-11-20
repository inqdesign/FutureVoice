# Review — 2026-11-20-invite-half-price — 2026-11-20 (round 2)
Verdict: PASS

No FIX items.

## Round-1 FIX 1 (monthly plans only): resolved
- ko Threads: `친구 한 명마다 반값 한 달이고, 몇 명이든 초대할 수 있어요. 반값은 월간 구독에 한 달씩 차례로 적용돼요.` Present, as specified.
- en Threads: `One half-price month for each friend, and you can invite as many as you like. The half-price months apply to monthly plans, one month at a time.` Present, as specified.
- Card small print (carousel.html l.77 / l.87, and both renders): ko `구독 중일 때 초대할 수 있어요 · 친구 한 명마다 한 달씩 · 월간 구독`, en `You can invite while subscribed · One month per friend · Monthly plans`. One line each at 27px, no wrap, inside the 83px margins (en runs ~x143–937).

## What the fix touched, re-checked
- Hooks now use the round-1 suggestion: ko `같이 공부할 친구가 있다면, 둘 다 다음 달을 반값으로 낼 수 있어요.`, en `Studying with a friend? You can both get next month at half price.` Both read natively; no implication that having a friend alone is enough.
- Machine count (Python len over the posted text in copy.md): ko 251 chars, en 487 chars (≤500, 13 to spare). No em dash in either text or in carousel.html. No hashtags.
- Truth of the rest unchanged from round 1 (50% from `invite_event.percent`, one month per friend with no cap, first-time subscribers only, inviting needs a subscription, 설정 → 친구 초대 is the real place, "무료" only for the first 20 minutes).
- Pixel font: grep of carousel.html for pixel|Geist|Galmuri finds only the "NO pixel font" comment; renders show heavy sans throughout.
- Visual: title 2 lines in both; "50%" on both boards, 나/친구 and You/Friend labels under the right people; steps, small print and foot all inside the card; palette matches the brand blue/ink/cream. 1080×1350 both.

## Posting gate (not a FIX)
The event is not live (`invite_event` absent in prod, switch off, banner build not in the store, Android owed). Post only after `scripts/invite-event-rollout.sh` has run and the store build is out; re-check the live percent is 50 that day. Founder decides whether to wait for Android.

## Suggestions (non-blocking)
- en title line 2 ends at ~x992 against the 997 margin. It fits, but do not enlarge it.
- Keep a one-line reply ready for "왜 자동이 아니에요?" (the App Store subscriber taps 반값 받기 and confirms with Apple).

Checked frames: renders/01.png (1080×1350, viewed), renders/01-en.png (1080×1350, viewed). No MP4s in this piece.
