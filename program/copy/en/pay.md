# /pay in English: copy for web/creators-pay.html

Shown to an applicant whose application came from the English page (`page_lang: en`). Written
in English from program/RULES.md, not translated. Page order. Each entry: where it goes
(selector, id, or the Korean string it replaces), then the English. No em dash anywhere.

The amount is computed by `money()` in the applicant's own currency; nothing below names a
currency, so every line reads right with any of them.

## Builder notes

- `<html lang="en">`.
- Links: `.brand` and the foot's program link → `/en/creators`; terms → `/terms.html`.
- Google Play badge: `/badges/google-play-en.png`.
- `money()` already formats KRW as `₩40,500`; that reads fine in English.
- How the page knows to be English (a `lang` in the mail's link, or the application's
  `page_lang`) is the builder's call; the mail's pay link is in mail.md.

---

## head

- `<title>` · KO "100일 챌린지 결제 · 나와나" → `Pay for the 100-day challenge · nawana`

## top

- `.brand` · KO "nawana 100일 챌린지" → `nawana 100-day challenge` (img alt stays empty)

## #pay

- `h1` · KO "참가비 결제" → `Your fee`
- `.tabs` aria-label · KO "요금제" → `Plan`
- tab labels `Light` / `Plus` / `Max` (unchanged)
- `#amount` filled by script
- `.what` · KO `<span id="tier_name">Light</span> 3개월 구독료` → `Three months of <span id="tier_name">Light</span>`

`TIERS` (script; shown in `#tier_talk`, `#tier_day`, `#tier_hint`; the HTML defaults are Light's):
- Light · KO "한 달에 통화 150분" / "하루 5분꼴" / "가볍게 시작하기 좋아요. 하다가 모자라면 그때 올려도 돼요."
  → `150 minutes of calls a month` / `About 5 minutes a day` / `A light place to start. If it runs short, move up then.`
- Plus · KO "한 달에 통화 450분" / "하루 15분꼴" / "매일 넉넉하게 통화하고 싶을 때요."
  → `450 minutes of calls a month` / `About 15 minutes a day` / `For a long call every day.`
- Max · KO "한 달에 통화 600분" / "하루 20분꼴" / "100일을 통화로 꽉 채우고 싶을 때요."
  → `600 minutes of calls a month` / `About 20 minutes a day` / `For filling all 100 days with calls.`

`ul`:
- KO "복습, 섀도잉, 스피치 연습은 어느 요금제든 마음껏 해요." → `Review, shadowing and speech practice are unlimited on every plan.`
- KO "한 번만 결제되고, 자동으로 다시 결제되지 않아요." → `You're charged once. Nothing renews.`
- KO "마지막 10일은 나와나가 무료로 드려요." → `The last 10 days are on nawana.`
- KO "결제한 날부터 앱을 쓸 수 있어요." → `You can use the app from the day you pay.`
- KO "시작하기 전에는 전액 환불해 드려요. 시작한 뒤에도 결제한 날부터 14일 안에는 취소할 수 있어요. <a>hello@nawana.app</a>으로 알려주세요."
  → `Full refund before we start. After that, you can cancel within 14 days of paying. Write to <a href="mailto:hello@nawana.app">hello@nawana.app</a>.`

`.mind`:
- KO "<b>나와나 앱에서 가입한 방법으로 로그인해 주세요.</b><br>앱에서 Apple로 가입했다면 Apple, Google로 가입했다면 Google이에요. 결제가 그 계정에 적용돼요."
  → `<b>Sign in the same way you signed up in the nawana app.</b><br>If you joined with Apple, use Apple; if with Google, use Google. Your payment goes to that account.`

Buttons:
- `[data-pay=apple]` · KO "Apple로 로그인하고 결제" → `Sign in with Apple and pay`
- `[data-pay=google]` · KO "Google로 로그인하고 결제" → `Sign in with Google and pay`

`#ask` (signed in with an account that never used the app). In Korean the account name leads the sentence; in English too:
- `p` · KO `<b id="ask_who"></b> 계정으로는 나와나 앱에 가입한 기록이 없어요.`
  → `<b id="ask_who"></b> hasn't been used to sign up in the nawana app.`
- `accountLabel()` fallback when there is no provider or email · KO "이" → `This account`
- `.note` · KO "앱에서 다른 방법으로 가입했다면, 그 방법으로 로그인해야 결제가 앱에 적용돼요."
  → `If you signed up in the app another way, sign in with that one, or the payment won't reach your app.`
- `#ask_switch` · KO "다른 방법으로 로그인" → `Sign in another way`
- `#ask_go` · KO "아직 앱에 가입 전이에요. 이 계정으로 결제" → `I haven't signed up in the app yet. Pay with this account`

`#status` messages (script):
- going to checkout · KO "결제창으로 가는 중이에요" → `Opening checkout`
- checking sign-in · KO "로그인을 확인하는 중이에요" → `Checking your sign-in`
- `already_subscribed` · KO "이 계정은 이미 결제했어요. 더 하실 일은 없어요." → `This account has already paid. You're all set.`
- `store_subscription_active` · KO "이 계정은 이미 앱에서 구독 중이에요. 결제하지 말고 hello@nawana.app으로 알려주세요."
  → `This account already has a subscription in the app. Please don't pay here. Write to hello@nawana.app instead.`
- checkout failed · KO "결제창을 열지 못했어요. 다시 눌러주세요." → `Couldn't open checkout. Please tap again.`
- after "Sign in another way" · KO "가입할 때 쓴 방법으로 다시 로그인해 주세요." → `Sign in again the way you signed up.`
- sign-in failed to open · KO "로그인을 열지 못했어요. 다시 눌러주세요." → `Couldn't open sign-in. Please tap again.`
- back from a cancelled checkout · KO "결제가 끝나지 않았어요. 다시 눌러 이어서 할 수 있어요." → `Your payment didn't finish. Tap again to pick up where you left off.`
- sign-in didn't come back · KO "로그인이 끝나지 않았어요. 다시 눌러주세요." → `Sign-in didn't finish. Please tap again.`

## #paid (after payment)

- `h1` · KO "신청과 결제,<br>모두 끝났어요" → `Signed up and paid.<br>You're all set.`
- `.what` · KO "12월 1일(예정)에 같이 시작해요." → `We start together on December 1 (planned).`
- `.note` · KO "<b>앱은 지금부터 쓸 수 있어요. 시작 전에 꼭 써보세요.</b><br>결제한 계정으로 로그인하면 돼요."
  → `<b>Start using the app now, before day 1.</b><br>Sign in with the account you paid with.`
- App Store badge · KO `<small>App Store에서</small><b>다운로드</b>` → `<small>Download on the</small><b>App Store</b>`
- Google Play badge alt · KO "Google Play에서 다운로드" → `Get it on Google Play`

After an upgrade (`?checkout=upgraded`, script):
- `#paid h1` · KO "요금제를 올렸어요" → `Your plan is upgraded`
- `#paid .what` · KO "앱을 다시 열면 바로 적용돼 있어요." → `Open the app again and it's already there.`

## foot

- KO "이미 나와나를 구독하고 있다면 결제하지 말고 <a>hello@nawana.app</a>으로 알려주세요."
  → `Already subscribe to nawana? Please don't pay here. Write to <a href="mailto:hello@nawana.app">hello@nawana.app</a> instead.`
- links · KO "100일 챌린지 안내 보기" · "이용약관" → `About the 100-day challenge` · `Terms`
