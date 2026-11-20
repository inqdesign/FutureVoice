# Copy: 친구초대 이벤트 카드 (Threads, one card)

Sources: `brief.md`, `scripts/invite-event-texts.json` (the app's own words), `FutureVoice/Views/MeTab.swift`
(banner placement), `FutureVoice/Views/InviteEventViews.swift` (`InviteEventBanner`, `InviteArt`).
The card's title, steps and board labels are the app's own strings, so the card and the screen it
points to say the same thing.

## 01 — 친구 초대 (single card, the two friends holding boards)

top line (ko): 친구 초대 · nawana
title (ko):    친구가 구독하면\n둘 다 다음 달 반값
boards (ko):   50% · 50%            ← white heavy sans, on the two board rects from `InviteArt`
labels (ko):   나 · 친구
steps (ko):
  1. 초대 코드를 보내요
  2. 친구가 코드를 넣고 구독을 시작해요
  3. 둘 다 다음 달이 반값이에요
small print (ko): 구독 중일 때 초대할 수 있어요 · 친구 한 명마다 한 달씩 · 월간 구독
foot (ko):     설정 → 친구 초대 · nawana.app

top line (en): Invite a friend · nawana
title (en):    When a friend subscribes,\nyou both get next month half price
boards (en):   50% · 50%
labels (en):   You · Friend
steps (en):
  1. Send your invite code
  2. Your friend enters it and subscribes
  3. Next month is half price for both of you
small print (en): You can invite while subscribed · One month per friend · Monthly plans
                  (designer: if a line no longer fits, drop it to 24px rather than wrapping)
foot (en):     Settings → Invite a friend · nawana.app

screen: none (type-led card; the drawing `InviteArt.imageset/invite-art.png` on cream #FCF9F0)
sticker / reaction text: none

Foot pointer, checked: the Settings page (`navigationTitle("Settings")`, ko 설정) puts the
`InviteEventBanner` in its own section directly under the Subscription row; its kicker is
`banner_kicker` = 친구 초대 / Invite a friend, button 초대하기 / Invite. So "설정 → 친구 초대" names
the real place. It only shows while the event is on (`phase != .off`).

## Threads text

### ko (≈250자)

같이 공부할 친구가 있다면, 둘 다 다음 달을 반값으로 낼 수 있어요.

구독 중이라면 설정의 친구 초대에서 내 초대 코드를 보낼 수 있어요. 처음 구독하는 친구가 그 코드를 넣고 첫 결제를 마치면, 친구도 나도 다음 달 결제가 50% 할인돼요.

친구 한 명마다 반값 한 달이고, 몇 명이든 초대할 수 있어요. 반값은 월간 구독에 한 달씩 차례로 적용돼요.

코드를 받은 친구라면, 나와나 첫 20분은 무료로 써 볼 수 있어요. nawana.app

### en (≈487 chars, ≤500)

Studying with a friend? You can both get next month at half price.

While you're subscribed, open Invite a friend in Settings and send your code. When a friend subscribing for the first time enters it and their first payment goes through, you both get 50% off next month.

One half-price month for each friend, and you can invite as many as you like. The half-price months apply to monthly plans, one month at a time.

Got a code from a friend? Your first 20 minutes are free. nawana.app

## Community series

Not asked for (single Threads card). Skipped.

## Checks against the brief's flags

- No dates, deadlines or "limited time". Only percentage: 50%.
- "구독을 시작해요" / "처음 구독하는 친구" / "subscribing for the first time": first-time subscribers only; never "가입하면".
- "구독 중일 때 / while you're subscribed": inviting needs a subscription.
- One month per friend, applied one month at a time, in both languages.
- Monthly plans only (review FIX 1: annual plans get no offer, `scripts/invite-event.py`): said on
  the card's small print ("월간 구독" / "Monthly plans") and in both Threads texts.
  No "모든 요금제 / all plans", nothing about the old 30-minute invite.
- "무료" appears only for the first 20 minutes (BRAND fact), never for the half-price month.
- No em dashes anywhere in the copy.

## Open questions for the lead

1. "몇 명이든 / as many as you like" is from the brief and status (no cap); `invite-event-texts.json`
   only implies it (`done_more`: "반값 N개월이 더 남아 있어요"). Confirm against `invite_event` on
   rollout day, together with the 50% figure.
2. en title line 2 ("you both get next month half price", 35 chars) is the app banner's own
   wording but long for the card; designer may need a smaller size. I kept it so card and banner match.
3. Timing gate unchanged from the brief: post only after rollout + store build. If Android is still
   owed, the Threads text says nothing about platform; Android subscribers will look for a banner that isn't there.
