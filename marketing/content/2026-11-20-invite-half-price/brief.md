# Brief: 친구초대 이벤트 카드 (Threads, one card)

## One message

친구가 구독하면 둘 다 다음 달이 반값이에요.
(en) When a friend subscribes, you both get next month half price.

## Who it's for

나와나를 이미 구독 중인 사람, 같이 공부하는 친구나 동료가 한 명쯤 떠오르는 순간.
두 번째 독자는 그 친구: 초대 코드를 받고 "이게 뭔데?" 하고 들어온 사람.

## Why now

The event shipped in code on 2026-11-19 (3da39ac1, 984b7c30), and the app now shows it under
Settings' subscription row. **Not live yet**: `invite_event` does not exist in prod (checked
2026-11-20), the event starts OFF, the store build with the banner is not out, Android is owed.
Make the card now, post only after `scripts/invite-event-rollout.sh` has run and the build is in
the store (see Risks).

## Card decision: type-led, with the app's own drawing

`web/kit` has no invite banner or sheet, and `marketing/captures` has no invite screen. Do not
draw one. The card is type-led and carries the one real visual the app uses: the two friends
holding boards (`FutureVoice/Resources/Assets.xcassets/InviteArt.imageset/invite-art.png`,
1100×870, cut out of its paper). The boards are EMPTY in the drawing; the app writes "50%" on
them in white heavy sans (`InviteArt`, board rects in `InviteEventViews.swift`), so the card does
the same, at the same positions. Labels under the two people: 나 / 친구 (en: You / Friend).

## The card (1080×1350, PNG, ko and en versions)

Layout per BRAND.md carousel text block, phone replaced by the drawing; no pixel font anywhere.

- Top line: `친구 초대` (left) · `nawana` (right). en: `Invite a friend`.
- Title (heavy sans, 2 lines): `친구가 구독하면 / 둘 다 다음 달 반값`
  en: `When a friend subscribes, / you both get next month half price`
- Middle: the drawing on its cream paper (#FCF9F0), "50%" on both boards, 나 / 친구 under them.
- Three steps, numbered, from the in-app sheet:
  1. 초대 코드를 보내요
  2. 친구가 코드를 넣고 구독을 시작해요
  3. 둘 다 다음 달이 반값이에요
  (en: Send your invite code / Your friend enters it and subscribes / Next month is half price for both of you)
- Small print, one line: `구독 중일 때 초대할 수 있어요 · 친구 한 명마다 한 달씩`
  (en: `You can invite while you are subscribed · One month for each friend`)
- Foot: `설정 → 친구 초대` · nawana.app. Check the exact place against the build before render
  (banner sits under the subscription row in Me/Settings).

## Threads text (≤500 chars, conversational, not an IG caption)

Outline, ko first:
1. Hook: 같이 공부할 친구 있으면, 다음 달 반값이에요.
2. How: 구독 중이면 설정에서 내 초대 코드를 보낼 수 있어요. 친구가 그 코드를 넣고 구독을 시작해서
   첫 결제가 끝나면, 친구도 나도 다음 달 결제가 50% 할인돼요.
3. Rules in one breath: 친구 한 명마다 반값 한 달, 몇 명이든 초대할 수 있어요 (반값은 결제 한 번에 한 달씩
   적용).
4. Close: 나와나 첫 20분은 무료예요. nawana.app

en version follows the same four beats with the en strings above.

## Risks

- **Timing**: the event is not live (no `invite_event` table in prod, switch OFF, banner build not
  in the store, Android todo). Posting earlier promises something nobody can use. Gate: founder
  confirms rollout done + store build live. If Android is still owed, say nothing about the
  platform but expect Android subscribers to ask; ask the founder whether to wait for Android.
- No dates, deadlines, "기간 한정", or any percentage but 50%. The percentage lives on the server
  (`invite_event`): re-check it is 50 the day we post.
- Never mention the old "30분씩" invite. Never say "무료" about the half-price month.
- "몇 명이든" is true (no cap) but one half-price month is applied per billing period; keep the
  parenthetical so nobody expects three friends = one cheap month ×3 at once.
- Annual plans get no offer (not built). Do not say "모든 요금제"; if asked, it's monthly plans.
- First-time subscribers only: a friend who subscribed before doesn't count. Covered by
  "구독을 시작해요"; don't write "가입하면".
- Copy is written, not translated; ko in 해요체, no em dash.

## Success signal

Threads: reposts and replies asking "코드 어디서 봐요?". In data, after rollout: `invite_rewards`
rows (earned) and new subscriptions that carry a redeemed code in the 2 weeks after the post.
