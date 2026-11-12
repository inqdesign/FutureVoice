# Program rules — the one source

Every page, mail, admin label and line of code must agree with this file. A rule changes
here first, with the date and who decided. Founder = 이응규.

## Cohort 1 (1기)

- Applications: 2026-11-12 → 2026-11-19. Starts **2026-12-01**, day 100 is **2027-03-10**.
  **Every date is PLANNED and is always written with "예정"** (founder, 2026-11-12: never say
  "12월 1일에 시작합니다" as settled); it may move with the number of applicants.
- While they wait, every surface tells the applicant to USE THE APP now (not "you may").
- Months are 30-day blocks from the first day, not calendar months:
  month 1 = Dec 1–Dec 30 · month 2 = Dec 31–Jan 29 · month 3 = Jan 30–Feb 28 ·
  the last 10 days (Mar 1–Mar 10) are on the house and are not judged.
- Korean only. A day is counted by the date where the participant lives (the page says so;
  the application keeps their country and time zone). The cohort's own dates are Seoul's.

## Creator (크리에이터)

- Studies for 100 days and posts the proof on their own SNS, on the days they agreed.
- nawana is free meanwhile: a standing comp code (Plus by default), made in the admin.
- No format, no review of posts, the app need not appear. Teaching content is not the concept.
- Checks in each posting day with that day's post link.
- At day 100 each one is ended in the admin by hand (the comp does not end by itself).

## Challenger (챌린저)

- Posts nothing. No limit on how many.
- Buys the **100-day package once, on the web**, when applying (prepaid, no renewal).
  **Light is where everyone starts**; the payment page (`/pay`) offers Light · Plus · Max as
  tabs, Light picked. Priced by where they live, in that country's currency: three months of
  the web's monthly price (App Store price minus 10%). Light: **₩40,500** in Korea, **¥4,050**
  in Japan, **€26.97** where the euro is money, **$26.97** in the US and anywhere without its
  own App Store price; 38 more currencies. The tables: `MONTHLY` in web/creators-pay.html and
  supabase/functions/challenge-upgrade, `LOCAL_FEE` in web/creators.html and creator-apply/mail.ts.
- Moving up later (founder, 2026-11-12: by hand for cohort 1): the difference is the months
  still to come × the difference of the two monthly prices; a month that has begun is not
  counted. The admin makes the checkout link (`challenge-upgrade`), the founder sends it, the
  payment changes the package. He can also change a size or give minutes with no payment.
- Said to participants as (founder, 2026-11-12): "3개월 구독료를 먼저 내요. 마지막 10일은
  나와나가 무료로 드려요. 100일이 끝난 다음 날부터, 지킨 달 수만큼 이어서 무료로 써요." It is NOT a refund, and every surface that
  mentions the reward says the free months come AFTER the three paid ones.
- The app works from the day of payment; the 100 days are counted from the cohort's first day.
- A day = 4+ minutes of talk AND one speech.
- A month is kept when at most ONE of its 30 days is missed.
- **Each month kept = one free month** (0–3). Fail / keep / fail = 1 month. Given once, in
  the last 10 days, by lengthening the package.
- Someone already subscribed in the App Store or Play: handled by hand, later. New customers
  first. The pay step tells them not to pay and to write instead.
- Refund (founder, 2026-11-12): in full before the cohort starts; after that the terms' 14
  days from payment. Asked by mail.
- Light is the low doorstep on purpose: start light, move up when it runs short.

## Privacy and promises

- Talk text and audio stay on the phone. The server sees daily talk seconds, and for a paid
  challenger each local day's talk seconds and number of speech takes (with the time zone,
  platform and app version). The consent line and the privacy policy must say so before the
  build that sends it ships.
- Applications are deleted when the cohort ends or when the person asks.
- Sample videos on the page carry no titles or captions written by us.

## Writing

- Page and app: 해요체. Mail from the founder: 합니다체. No em dash. “당신” is fine on the
  creators page (founder, 2026-11-12: it doesn't matter there); still not in mails or the app.
- Written in Korean, never translated. Start with what to do or what they get.
- One line, no rationale. Never praise over a mistake, never scold.
