# Applicant mail in English: copy for supabase/functions/creator-apply/mail.ts

**Founder must approve before any of this is sent.** Both mails are from Eunggyu, in his first
person. Sent once, to an application with `page_lang: en`. Keyed by the fields of the `Copy`
interface, then the strings that are hard-coded in `html()` / `text()` / `sendReceived()`.
Written in English from program/RULES.md, not translated. No em dash anywhere.

## Constants

- `FROM` · KO "이응규 · nawana <hello@nawana.app>" → `Eunggyu Lee · nawana <hello@nawana.app>`
- `SUBJECT` (creator) → see creator `subject` below

## Fee labels for `fee()`

The Korean labels add 원/엔/유로/달러 and a particle trick (`label.endsWith(" ")`). In English
every country uses the symbol form, so the trick isn't needed and the note line below reads the
same with any currency:
- KR (and no country) · KO "40,500원" → `₩40,500`
- JP · KO "4,050엔" → `¥4,050`
- euro countries · KO "26.97유로" → `€26.97`
- everywhere else without its own price · KO "26.97달러" → `$26.97`
- countries in `LOCAL_FEE`: the `Intl.NumberFormat("en-US", …)` label as it is today, without the trailing space.

## Shared lines (`common`)

- `hi` · KO "${name}님, 안녕하세요. 나와나를 만드는 이응규입니다." → `Hi ${name}, I'm Eunggyu, and I make nawana.`
- `scheduleHead` · KO "다음 일정" → `What happens next`
- `scheduleNote` · KO "지원 인원에 따라 일정이 변경될 수 있습니다. 바뀌면 이 메일 주소로 먼저 알려드리겠습니다."
  → `These dates are planned and may change with the number of applicants. If they do, I'll tell you at this address first.`
- `useHead` · KO "기다리는 동안 할 일" → `While you wait`
- `askHead` · KO "궁금한 점이 있다면" → `Questions?`
- `ask` · KO "이 메일에 답장하시거나 스레드, 인스타그램 DM으로 편하게 보내주세요. 제가 직접 읽고 답합니다."
  → `Just reply to this email, or send me a DM on Threads or Instagram. I read and answer every one myself.`
- `sign` · KO "이응규 드림" → `Eunggyu`

## Creator mail

- `subject` · KO "지원서 잘 받았습니다" → `I got your application`
- `body`:
  1. KO "크리에이터 프로그램 1기 지원서 잘 받았습니다. 적어주신 내용은 제가 전부 직접 읽습니다."
     → `Thank you for applying to cohort 1 of the nawana Creator Program. I read every word of every application myself.`
  2. KO "읽고 나서 이 메일 주소나 남겨주신 연락처로 다시 연락드리겠습니다."
     → `Once I've read yours, I'll get back to you here or at the handle you left.`
- `button` · `null` (unchanged)
- `use`:
  1. KO "기다리는 동안 나와나를 꼭 써보세요. 어떤 100일을 보낼지는 직접 써봐야 보입니다."
     → `Start using nawana now, while you wait. You'll only see what your 100 days could look like once you've tried it.`
  2. KO "오늘 첫 통화부터 해보세요. 처음 20분은 무료입니다."
     → `Make your first call today. Your first 20 minutes are free.`
- `after`:
  1. KO "지원서에서 고치고 싶은 부분이 있으면 11월 19일까지 같은 연락처로 한 번 더 보내주시면 됩니다. 제가 읽기 전이라면 새 내용으로 바뀝니다. 그 뒤에는 이 메일에 답장해 주세요."
     → `Want to change something in your application? Send the form again with the same email address by November 19. If I haven't read it yet, the new one replaces it. After that, just reply to this email.`
- `schedule` ([when, what]):
  1. KO ["11월 19일까지", "지원서 접수"] → [`By Nov 19`, `Applications close`]
  2. KO ["11월 중", "제가 읽고 연락"] → [`During November`, `I read yours and get in touch`]
  3. KO ["11월 말", "올릴 일정 정하고 코드 전달"] → [`Late November`, `We set your posting days, and I send your code`]
  4. KO ["12월 1일 (예정)", "100일 시작"] → [`Dec 1 (planned)`, `Day 1 of 100`]
  5. KO ["3월 10일 (예정)", "100일 끝"] → [`Mar 10 (planned)`, `Day 100`]
- `thanks` · KO "지원해주셔서 고맙습니다." → `Thank you for applying.`
- `foot` · KO "이 메일은 크리에이터 프로그램에 지원하셨을 때 한 번 발송됩니다."
  → `You get this email once, when you apply to the nawana Creator Program.`

## Challenger mail

- `subject` · KO "100일 챌린지, 가입과 결제를 마쳐주세요" → `Finish signing up: join the app and pay`
- `body`:
  1. KO "100일 챌린지 1기 신청서 잘 받았습니다." → `I got your form for cohort 1 of the 100-day challenge.`
  2. KO "신청은 아래 두 가지를 마쳐야 완료됩니다." → `Two steps below, and you're in.`
- `button` `null`, `after` `[]`, `use` `[]` (unchanged)
- `finish.head` · KO "신청을 마치려면" → `To finish signing up`
- `finish.one` · KO "나와나 앱을 받고 가입합니다. 이미 쓰고 계시다면 넘어가셔도 됩니다."
  → `Get the nawana app and sign up. If you already use it, skip this step.`
- `finish.two` · KO "앱에서 가입한 방법(Apple 또는 Google)으로 로그인해 결제합니다."
  → `Sign in the way you signed up in the app (Apple or Google), and pay.`
- `finish.pay[0]` · KO "결제하러 가기" → `Go to payment` (the link stays `${SITE}/pay?id=…&cur=…`; the builder adds whatever tells /pay to be English)
- `finish.notes`:
  1. KO `참가비는 Light 3개월 구독료 ${…}, 한 번만 결제됩니다. 결제 화면에서 Plus나 Max도 고르실 수 있습니다. 마지막 10일은 제가 무료로 드립니다.`
     → `The fee is three months of Light, ${price.label}, charged once. You can pick Plus or Max on the payment page instead. The last 10 days are on me.`
  2. KO "결제하신 날부터 앱을 쓰실 수 있습니다. Light는 한 달에 통화 150분입니다. 시작 전에 꼭 써보세요."
     → `You can use the app from the day you pay. Light gives you 150 minutes of calls a month. Start using it now, before day 1.`
  3. KO "시작하기 전에는 전액 환불해 드립니다. 시작한 뒤에도 결제하신 날부터 14일 안에는 취소하실 수 있습니다. 이 메일에 답장해 주세요."
     → `Before day 1, you can get a full refund. After that, you can still cancel within 14 days of paying. Just reply to this email.`
  4. KO "이미 나와나를 구독하고 계시다면 결제하지 마시고 이 메일에 답장해 주세요."
     → `If you already subscribe to nawana, please don't pay. Reply to this email instead.`
- `schedule` ([when, what]):
  1. KO ["11월 19일까지", "가입과 결제"] → [`By Nov 19`, `Join the app and pay`]
  2. KO ["12월 1일 (예정)", "100일 시작"] → [`Dec 1 (planned)`, `Day 1 of 100`]
  3. KO ["3월 10일 (예정)", "100일 끝"] → [`Mar 10 (planned)`, `Day 100`]
  4. KO ["그다음 날부터", "지킨 달 수만큼 이어서 무료"] → [`From the next day`, `Free months, one for each month you kept`]
- `thanks` · KO "신청해 주셔서 고맙습니다." → `Thanks for taking this on with me.`
- `foot` · KO "이 메일은 100일 챌린지에 신청하셨을 때 한 번 발송됩니다."
  → `You get this email once, when you sign up for the 100-day challenge.`

## Hard-coded strings outside `Copy`

`html()`:
- store pills · KO "아이폰에서 받기" / "안드로이드에서 받기" → `Get it on iPhone` / `Get it on Android`
- contact row · KO "이 메일에 답장" → `Reply to this email` (the Threads and Instagram DM rows stay as they are)
- banner `alt` · KO "nawana Creator program 1기 · 우리의 가장 뜨거울 100일" → `nawana Creator Program · Cohort 1 · 100 days, all in`
- banner image `/mail/creator-banner.jpg`: if it has Korean text on it, English mails need an English banner (open item for the founder).
- footer line `Dear RoRo · Munich` (unchanged)

`text()`:
- KO "아이폰:" / "안드로이드:" → `iPhone:` / `Android:`
- KO "이 메일에 답장:" → `Reply to this email:`

`sendReceived()`:
- name fallback when the applicant left none · KO "신청자" (challenger) / "지원자" (creator) → `there` for both, so `hi` reads `Hi there, I'm Eunggyu, and I make nawana.`

## Fixes 2026-11-12

Apply these to mail.ts if it was already built from the earlier version. The entries above
already carry the new wording.

1. Creator mail, `after[0]` (an application is matched by EMAIL, not handle)
   - old: `Want to change something in your application? Send the form again with the same handle by November 19. If I haven't read it yet, the new one replaces it. After that, just reply to this email.`
   - new: `Want to change something in your application? Send the form again with the same email address by November 19. If I haven't read it yet, the new one replaces it. After that, just reply to this email.`
2. Challenger mail, `body[0]` and `body[1]` (the pair said "thank you for signing up" and then "you're signed up once…")
   - old: `Thank you for signing up for cohort 1 of the 100-day challenge.` / `You're signed up once you've done the two steps below.`
   - new: `I got your form for cohort 1 of the 100-day challenge.` / `Two steps below, and you're in.`
3. Challenger mail, `thanks` (same contradiction at the close, before they've paid)
   - old: `Thank you for signing up.`
   - new: `Thanks for taking this on with me.`
4. Challenger mail, `finish.notes[2]`, first sentence
   - old: `Before we start, I'll refund you in full.`
   - new: `Before day 1, you can get a full refund.`

---

## Desk messages (EN)

**Founder must approve before any of this is sent.** English versions of the messages the
founder sends by hand from admin/src/creators.html, for an application with `page_lang: en`
(the desk already tags those rows "EN"). Keyed by the Korean function / variable. Same
`${…}` expressions as the Korean, nothing added except the plural in the upgrade mail.
Written in English from what each message is for, in Eunggyu's first person. DMs are short and
casual; mails open with `Hi ${a.name}, I'm Eunggyu, and I make nawana.` and sign `Eunggyu`.
No em dash.

Builder notes:
- `mailBody()` prefixes KO "제목:"; for an EN mail use `Subject:`.
- The `·` bullets in the paid challenger mail are kept as in the Korean.
- Links: the creators page is `https://nawana.app/en/creators`; every pay link ends `&lang=en`
  (the desk's "copy pay link" already adds it; the mail below carries it in the text).
- In the upgrade mail `${res.quote.label}` is already formatted `en-US` by challenge-upgrade
  (e.g. `$7.50`, `₩13,500`), so it drops in as is.
- In-app labels quoted in `codeDM` are the app's own English strings: "Have an invite code?"
  (first screen) and "Enter invite code" (settings).

### `firstDM` (creator, first contact)

Placeholders: `${a.name}`

```
Hi ${a.name}! Thanks for applying to nawana Creators, cohort 1. I've read your application.
Want to figure out together how often you'll post, and where?
```

### `codeDM` (creator, the free code)

Placeholders: `${a.name}`, `${a.comp_code}`

```
${a.name}, let's do this! Your code is ${a.comp_code}
On nawana's first screen, tap "Have an invite code?" and enter it, and you're in. If you've already signed up, enter it under "Enter invite code" in Settings. Please use it within 30 days.
Cohort 1 runs for 100 days from December 1 (planned). If the date moves, you'll hear it from me first.
Just two promises to keep: post on the days we set, and show that you use nawana.
Since you're getting the app for free, say so clearly in every post, the way your country asks. For example "I got nawana for free" or #ad.
```

### `challengerMail(a)`, `a.paid_at` set (paid)

Placeholders: `${a.name}`

- subject: `Your 100-day challenge: payment received`
- body:

```
Hi ${a.name}, I'm Eunggyu, and I make nawana.

I have both your sign-up and your payment for cohort 1 of the 100-day challenge. I'm glad you're in.

You can use the app from today. Just sign in with the account you paid with. The challenge counts three months from day 1, and the 10 days after that are on me.

The rules are the ones you saw when you signed up:
· A day: at least 4 minutes of calls and one speech
· You can miss one day a month
· From the day after day 100, you keep using nawana free, one month for each month you kept. Keep all three and the next 3 months are free (it's not a refund)

Cohort 1 is planned to start on December 1 and end on March 10. If the dates move, you'll hear it from me first. Start using the app now, before day 1. Any questions, just reply to this email.

Eunggyu
```

### `challengerMail(a)`, no `a.paid_at` (not paid yet)

Placeholders: `${a.name}`, `${a.id}`, `${curOf(a.country)}`

- subject: `Your 100-day challenge: one step left`
- body:

```
Hi ${a.name}, I'm Eunggyu, and I make nawana.

I got your sign-up for cohort 1 of the 100-day challenge. All that's left is the payment, so here's the link.

You pay up front, and we all start together on day 1. Pay at the link below. You're charged once, and it never renews. Sign in with the account you use in the app (Apple or Google), and it goes straight onto that account.
https://nawana.app/pay?id=${a.id}&cur=${curOf(a.country)}&lang=en

If you already subscribe in the app, please don't pay. Reply to this email instead.

Any other questions, just reply here too.

Eunggyu
```

### `laterMail(a)` (creator not taken this time)

Placeholders: `${a.name}`, and the `${APPLY_OPEN() ? `…` : ""}` block kept exactly as in the Korean (shown only while applications are open).

- subject: `Your application to the nawana Creator Program`
- body:

```
Hi ${a.name}, I'm Eunggyu, and I make nawana.

Thank you for applying to cohort 1 of the nawana Creator Program. I read everything you wrote.

Cohort 1 starts small, so I can't bring you in as a creator this time.

${APPLY_OPEN() ? `You can still do the 100 days as a challenger. Challengers don't post anything: you pay for three months up front and study every day. The last 10 days are on me, and once the 100 days are over you keep using nawana free, one month for each month you kept. Sign-ups close November 19.
https://nawana.app/en/creators

` : ""}When I open the next cohort, you'll be the first to know. Thanks again for applying.

Eunggyu
```

### upgrade mail (`const mail = {subject:"요금제 올리기 안내", …}` inside `challengerBox`, the "결제 링크 만들기" button)

Placeholders: `${a.name}`, `${res.quote.from}`, `${res.quote.to}`, `${res.quote.months}`, `${res.quote.label}`, `${res.url}`. The one addition: `${res.quote.months === 1 ? "month" : "months"}`, because English needs the plural and Korean doesn't.

- subject: `Moving up your plan`
- body:

```
Hi ${a.name}, I'm Eunggyu, and I make nawana.

As you asked, your plan is ready to move up from ${res.quote.from} to ${res.quote.to}. For the ${res.quote.months} ${res.quote.months === 1 ? "month" : "months"} still to come, the difference is ${res.quote.label}.

Pay at the link below and it applies right away. The link stays open for about a day.
${res.url}

Once you've paid, reopen the app and you'll have more call time.

Eunggyu
```
