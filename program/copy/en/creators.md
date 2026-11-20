# /en/creators: English copy for web/creators.html

Written in English from program/RULES.md and what each section is for, not translated line by
line. Page order. Each entry: where it goes (selector, id, or the Korean string it replaces),
then the English. HTML inside the English (`<br>`, `<mark>`, `<b>`, `<a>`) is meant to be kept.
No em dash anywhere; keep it that way when editing.

## Open for the founder

Decide these before the page goes live.

1. **Disclosure line for creators (new; the Korean page has none today).** CLAUDE.md says the
   page asks creators to say the app was given to them, but no such line is on web/creators.html
   right now. I added one in two places on the English page (the creator note in the form, and a
   creator FAQ), worded for any country:
   "Say in your posts that you got nawana for free, the way your country asks (for example
   "I got nawana for free" or #ad)." Approve it, and decide whether the Korean page gets its own
   Korean line back.
2. **Consent line says more than the Korean one.** RULES.md ("Privacy and promises") says that
   for a paid challenger the server also sees each local day's number of speech takes, and that
   the consent line must say so. The Korean consent line mentions only daily talk time. The
   English line below says both. Approve, and decide whether the Korean line gets the same fix.
3. **"리뷰" in the "자유" row.** The Korean list of things that don't matter ends with "리뷰".
   I read it as "nobody checks your posts first" (RULES: no review of posts) plus "you don't have
   to review the app". If it meant only one of those, tell me which and I'll cut the other.
4. **"English on your commute" idea note.** The nawana Podcast is English only, so the note says
   English. Someone on this page may be learning Korean, Spanish, German or Japanese. Keep it, or
   rewrite it around something every language has?
5. **Mail banner.** The applicant mail starts with /mail/creator-banner.jpg; if that image has
   Korean text on it, English mails need an English banner (see mail.md).
6. **Deadline time zone.** The form closes at 2026-11-20 00:00 Seoul time (code: APPLY_UNTIL),
   so the English says "November 19". For someone in the Americas that is the
   morning of the 19th. Fine to say it this way, or do you want a different cut-off line?
7. **Terms page.** The challenger refund FAQ links to /terms.html. Please confirm the English
   terms cover the 100-day package (full refund before the start, 14 days from payment after).

## Builder notes (not copy decisions)

- `<html lang="en">`. The kit screens (`nw-call`, `nw-voice`, ...) pick their chrome from the
  nearest `lang`, so they come out in English with no other change.
- Country list: `new Intl.DisplayNames(["en"], ...)` and `localeCompare(..., "en")`.
- `syncFee()` falls back to `"krw"` when no country is picked. On the English page fall back to
  `"usd"` ($26.97, the price "anywhere without its own App Store price").
- Links: canonical and og:url `https://nawana.app/en/creators`; mark links `/en/creators`;
  footer privacy `/privacy.html`; terms `/terms.html`. Add hreflang pairs with `/creators`.
- The pen font file (Nanum Pen Script subset) holds only the Hangul on the Korean page; check the
  English h2s and notes render in a hand that has Latin.
- `show(ITEMS.findIndex((it) => it.name === "자유 대화"))` becomes `"Free talk"`.
- `WEEK` and the checkbox `value`s stay 월 화 수 목 금 토 일; only the labels change.
- The application must send `page_lang: "en"` (RULES.md).
- Google Play badge on this page and the pay page: `/badges/google-play-en.png`.

---

## head

- `<title>` and `og:title` · KO "나와나 크리에이터 프로그램 1기"
  → `nawana Creator Program · Cohort 1`
- `meta description` and `og:description` · KO "100일 동안 미친듯이 언어를 공부하고, 그 증거를 공유해요. 앱은 무료로 드릴게요."
  → `Study a language like crazy for 100 days and share the proof. nawana is free while you do.`

## header (fixed bar)

- `.mark` aria-label "nawana creators" → `nawana creators` (unchanged)
- `.crumb` "creators" → `creators` (unchanged)
- `.top-gen` · KO `<b>1기</b>우리의 가장 뜨거울 100일` → `<b>Cohort 1</b>100 days, all in`
- `.top .btn` · KO "지원하기" → `Apply`

## opening: the YouTube watch page (#ytw)

- `.yt-search span` · KO "검색" → `Search`
- `.yt-title` · KO "미래의 나와 100일 동안 말하기 | Day 1" → `100 days of talking to my future self | Day 1`
- `.yt-who b` · KO "내 채널" → `Your channel`
- `.yt-who small` · KO "나와나 크리에이터 1기" → `nawana Creators · Cohort 1`
- `.yt-sub` · KO "구독" → `Subscribe`
- `.yt-acts` second button · KO "공유" → `Share`
- `.yt-next li b` (four) · KO "미래의 나와 100일 동안 말하기 | Day 2…5" → `100 days of talking to my future self | Day 2` (… Day 3, Day 4, Day 5)
- `.yt-next li small` (four) · KO "내 채널" → `Your channel`

## opening: film and title (#film, #story-copy)

- `#broll` aria-label · KO "나와나를 쓰는 장면들" → `Moments of people using nawana`
- `p.gen` · KO "1기 모집" → `Cohort 1 is open`
- `p.hot` · KO "우리의 가장 뜨거울 100일" → `100 days, all in`
- `h1` → `nawana <span id="creator-word">Creator</span> program` (unchanged)
- `h1 + p` · KO "100일 꾸준히 공부하고,<br>그 기록으로 크리에이터가 되세요!"
  → `Study every day for 100 days,<br>and become a creator by sharing it!`
- `.btn[data-track=hero]` · KO "지원하기" → `Apply`

## opening: the five posts (#social)

- `.stage-copy p.hot` · KO "소셜 미디어에서<br>언어 크리에이터가 되어보세요."
  → `Become a language creator<br>on social media.`
- `#center-video` aria-label · KO "만든 사람이 직접 찍은 스피치 영상" → `A speech video I filmed myself`
- `#snd` aria-label (start, and in script when muted) · KO "소리 켜기" → `Turn sound on`
- `#snd` aria-label (script, when playing) · KO "소리 끄기" → `Turn sound off`

Platform chrome drawn by the script (REELS_FRAME, PLATFORM, feedPost):
- Reels top · KO "릴스" → `Reels`
- Reels follow pill · KO "팔로우" → `Follow`
- Reels caption `.rcap` · KO "오늘의 스피치 연습 ${CENTER_DAY}/100" → `Today's speech practice ${CENTER_DAY}/100`
- Reels audio · KO "♫ 오리지널 오디오" → `♫ Original audio`
- TikTok tabs · KO "팔로잉" / "추천" → `Following` / `For You`
- TikTok audio · KO "♫ 오리지널 사운드" → `♫ original sound`
- YouTube Shorts pill · KO "구독" → `Subscribe`
- Facebook actions · KO "좋아요" / "댓글" / "공유" → `Like` / `Comment` / `Share`

## #deal

- `h2` · KO "나와나 크리에이터 1기 모집" → `nawana Creators, cohort 1`
- `p.big` · KO "100일 동안 미친듯이 공부하고,<br>그 증거를 올려주세요.<br><mark>나와나는 무료로 드릴게요.</mark>"
  → `Study like crazy for 100 days,<br>and post the proof.<br><mark>nawana is on me.</mark>`
- `p.app-line` · KO "나와나는 내 목소리로 이미 유창하게 말하는 ‘미래의 나’와 통화하며 언어를 배우는 앱이에요. 영어, 독일어, 일본어, 스페인어, 한국어."
  → `nawana is an app where you learn a language by calling your future self, who already speaks it fluently, in your own voice. English, German, Japanese, Spanish and Korean.`

`dl.terms`, four rows (dt / dd b / dd span):
1. KO "드려요" / "100일 동안 나와나 무료" / "받은 코드를 앱에 넣으면 바로 써요."
   → `You get` / `nawana free for 100 days` / `Enter the code I send you in the app, and you're in.`
2. KO "약속" / "정한 날마다 공부한 증거를 올려요" / "매일이 제일 좋고, 어려우면 나만의 일정도 괜찮아요. 대신 정한 만큼은 꼭 지켜요."
   → `You promise` / `Post proof of your study on the days you pick` / `Every day is best. If that's too much, your own schedule is fine. Just keep the days you set.`
3. KO "자유" / "나머지는 전부 상관없어요" / "형식, 길이, 퀄리티, 올릴 곳, 팔로워 수, 앱이 나오는 양, 리뷰. 대충 찍어도, 망해도 괜찮아요."
   → `Up to you` / `Everything else is up to you` / `Format, length, polish, where you post, how many followers you have, how much of the app shows up. Nobody checks your posts first, and you don't have to review the app. Rough is fine. Flops are fine.` (see Open item 3)
4. KO "소유" / "콘텐츠는 전부 당신 거예요" / "저는 툴만 드려요."
   → `It's yours` / `Everything you make belongs to you` / `I only bring the tool.`

- `p.closer` · KO "주인공은 매일 올리는 바로 당신이에요.<br>저는 옆에서 같이 갈게요. 의지가 약하면 <mark>멱살 잡고 끌고 갈게요.</mark> 이걸 제가 잘해요."
  → `The star is you, showing up every day.<br>I'll be right there with you. If your willpower slips, <mark>I'll drag you to the finish line.</mark> I'm good at that.`

## #samples

- `h2` · KO "형식은 뭐든 괜찮아요" → `Any format works`
- `p.lead` · KO "제가 직접 만들어본 것들이에요. 이렇게 따라 해도 되고, 전혀 다르게 해도 돼요. 여러분들이 크리에이터예요."
  → `I made these myself. Copy them, or do something completely different. You're the creator.`
- gallery `video` aria-label (script) · KO "샘플 영상 ${i + 1}" → `Sample video ${i + 1}`
- The sample videos get no title or caption.

## #pantry

- `h2` · KO "나와나로 할 수 있는 것들" → `What you can do with nawana`
- `p.lead` · KO "하나씩 눌러보면 앱 화면이 나와요. 마음에 드는 걸 섞으면 나만의 100일이 돼요."
  → `Tap one to see it in the app. Mix the ones you like, and that's your 100 days.`
- viewer video aria-labels (script) · KO "${it.name} 영상" → `${it.name} video`; KO "${it.name} 화면 녹화" → `${it.name} screen recording`

`PANTRY` (shelf, then [name, line]). Names follow the app's own English labels.

Shelf KO "대화" → `Talk`
- KO "내 목소리" → `Your voice` · `Record once, and your future self speaks in your voice.`
- KO "자유 대화" → `Free talk` · `Chat with your future self about anything. Each time you speak, a more natural way to say it comes back.`
- KO "매일 전화" → `Daily call` · `At the time you set, your future self rings you, like an alarm.`
- KO "튜터 모드" → `Tutor mode` · `Pick a topic and practice it step by step until you can say it.`
- KO "코치 모드" → `Coach mode` · `When you're stuck, it shows one line you could say.`
- KO "발음 통화" → `Pronunciation call` · `Read a sentence and it points to the word, and the sound, that slipped. It costs half the call minutes.`
- KO "오늘의 뉴스" → `Today's news` · `Pick one of today's stories under News in Find a topic and start talking about it.`
- KO "튜터 봇" → `Tutor bot` · `Picks the one thing worth doing today. You can ask it anything.`
- KO "팟캐스트" → `Podcast` · `Listen to the nawana Podcast and repeat the lines you like.`

Shelf KO "상황연습" → `Watch`
- KO "내 상황 만들기" → `Your own situation` · `A job interview, a first date, a call with your landlord. Your future self goes first and shows you how.`

Shelf KO "복습" → `Review`
- KO "교재" → `Books` · `Every call you finish turns into a book.`
- KO "단어와 표현" → `Words and expressions` · `The words and phrases your future self used collect on their own.`
- KO "문장 카드" → `Sentence cards` · `Flip through your corrected sentences and answer out loud.`
- KO "섀도잉" → `Shadowing` · `Repeat after your future self's voice and compare even the rhythm.`
- KO "다시 말하기" → `Say it again` · `Do the call you just had again from the start, this time with the corrected lines.`
- KO "워크북" → `Workbook` · `Turn a book into a PDF workbook and work through it by hand.`
- KO "주간 테스트" → `Weekly test` · `A test made only from what you studied that week.`
- KO "한 주 돌아보기" → `Your week` · `Your week arrives as a report you swipe through like stories.`

Shelf KO "스피치" → `Speech`
- KO "스피치 챌린지" → `Speech challenges` · `Everyone reads the same script and climbs the leaderboard.`
- KO "내 원고" → `Your scripts` · `Interview answers, a presentation, a toast. Put your own script on the teleprompter and read it. Here: a cabin crew interview, about me.`
- KO "스피치 점수" → `Speech score` · `Pace, pauses, even pronunciation, all scored.`

Shelf KO "성장" → `Progress`
- KO "레벨" → `Level` · `Your level, measured from how you speak: vocabulary, grammar and pronunciation, each on its own.`
- KO "나의 루틴" → `My routine` · `Put calls, listening, shadowing, speech and review into your own timetable.`
- KO "발음 분석" → `Pronunciation report` · `Gathers the sounds that keep slipping.`
- KO "오늘의 카드" → `Day card` · `A card with today's study numbers over a photo you took. Post it as it is.`
- KO "위젯" → `Widgets` · `Today's words flip by on your Home Screen.`

`MOCK` screens (strings inside the mock phones; the English material in them stays as is):
- pron: KO "발음" → `Pronunciation`; KO "지난 30일" → `Last 30 days`; KO "소리 정확도 · 테이크 47개" → `Sound accuracy · 47 takes`; KO "약한 소리" → `Weak sounds`; KO "좋아진 소리" → `Sounds that got better`; KO "여러 번 약했던 단어" → `Words that slipped more than once`
- daycard: KO "닫기" / "오늘의 카드" / "공유" → `Close` / `Day card` / `Share`; KO "사진 고르기" / "정사각형" → `Choose photo` / `Square`
- news: KO "주제" → `Topics`; KO "아이디어" → `Ideas`; chips KO "뉴스" / "일상" / "상황" → `News` / `Everyday` / `Situations`; card tags KO "AI / 테크" → `AI / Tech`, KO "요리" → `Cooking`; KO "내가 정한 주제로" → `My own topic`
- widget: KO "대화하기" → `Talk`; KO "단어" → `Word`; KO "문장" → `Sentence`

## #ideas (the sticky-note pad)

- `h2` · KO "100일 챌린지<br>아이디어" → `Ideas for<br>your 100 days`
- `.peel-copy p` · KO "그냥 아이디어예요. 뭐든 여러분에게 맞는 공부를 찾아서 하세요."
  → `Just ideas. Find the kind of study that fits you.`
- `.peel-count` "1 / 10" (unchanged)

Notes (h3 / p):
1. KO "공부 타임랩스" → `Study timelapse` / `Set a timer and film yourself studying, sped up. You don't have to say a word, and anyone watching wants to study too.`
2. KO "매일 5분 자유 대화" → `5 minutes of free talk a day` / `Post 5 minutes of chatting with your future self, who speaks fluently in your voice. On day 100, play day 1. You'll be the most surprised.`
3. KO "면접 D-100" → `100 days to the interview` / `With a real interview coming up, clear one topic a day in tutor mode. Show whether you got the job, and your 100 days has an ending.`
4. KO "친구와 스피치 경쟁" → `Speech battle with a friend` / `Read the same challenge script as a friend and see who scores higher. The leaderboard flips back and forth every day.`
5. KO "미래의 나 따라 하기" → `Copy your future self` / `Call for 5 minutes, then shadow what your future self just said. Copying your own voice with your own mouth is strangely fun.`
6. KO "출근길 영어공부" → `English on your commute` / `Play the nawana Podcast on the way to work and repeat the lines you like. One stop, one sentence.` (see Open item 4)
7. KO "하루를 영어로 읽기" → `Read your day out loud` / `Write today as a short script in the language you're learning and read it out loud. After 100 days, you have a 100-day diary.`
8. KO "매일 단어" → `A word a day` / `Flip through today's word cards, then use them in that day's call. Words you use in a call get checked off.`
9. KO "나만의 루틴으로" → `Your own routine` / `Mix just the parts you enjoy. Put calls, listening, shadowing, speech and review into My routine in the app, and plan your own 100 days.`
10. KO "여러분 마음대로" → `Whatever you like` / `You're the creator, so there are no limits. Mix the ones above, or do something completely different.`

## growing together (5th section)

- `h2` · KO "함께 성장해요" → `Growing together`
- `p.big` · KO "광고 대신, 사람에게 투자해요." → `Instead of ads, I invest in people.`
- `p.lead` · KO "나와나의 마케팅 비용을 광고에 쓰지 않고, 여러 사람에게 조금씩 나눠 투자해요. 저도 처음 해보는 새로운 실험이에요."
  → `nawana's marketing money doesn't go to ads. It goes to many people, a little each. It's a new experiment for me too.`
- `.win` left · KO `<b>여러분은</b>` / "100일 동안 진짜 공부하고, 크리에이터로 시작해서 좋고"
  → `<b>For you</b>` / `100 days of real study, and a start as a creator`
- `.win` right · KO `<b>나와나는</b>` / "그 기록으로 알려지면 더 좋고"
  → `<b>For nawana</b>` / `Getting known through what you share`

## how it works (6th section)

- `h2` · KO "이렇게 진행돼요" → `How it works`
- first `.steps-note` · KO "<mark>일정은 모두 예정이에요. 신청자 수에 따라 바뀔 수 있어요.</mark>"
  → `<mark>All dates are planned and may change with the number of applicants.</mark>`

`ol.steps` (em.when / b / span):
1. KO "11월 19일까지" / "지원서 쓰기" / "아래 지원서를 써주세요. 3분이면 돼요."
   → `By November 19` / `Apply` / `Fill in the form below. It takes 3 minutes.`
2. KO "11월 중" / "제가 읽고 연락" / "전부 직접 읽고 적어주신 곳으로 연락드려요."
   → `During November` / `I read it and get in touch` / `I read every one myself and reach you wherever you told me to.`
3. KO "11월 말" / "일정 정하고 코드 받기" / "얼마나 자주 올릴지 같이 정하고, 코드를 드려요."
   → `Late November` / `Set your days, get your code` / `We decide together how often you post, and I send you your code.`
4. KO "12월 1일 ~ 3월 10일" / "100일 동안 올리기" / "12월 1일에 같이 시작할 예정이에요. 제가 계속 챙겨볼게요."
   → `December 1 to March 10 (planned)` / `100 days of posting` / `We plan to start together on December 1. I'll keep checking in on you.`

- last `.steps-note` · KO "챌린저는 신청하고 바로 결제하면 끝이에요. 12월 1일(예정)에 같이 시작해요."
  → `Challengers just sign up and pay, and that's it. We start together on December 1 (planned).`

## FAQ (7th section)

- `h2` · KO "궁금한 것들" → `Questions`

`details.faq-diff`:
- summary · KO "크리에이터와 챌린저는 뭐가 달라요?" → `What's the difference between a creator and a challenger?`
- p · KO "크리에이터는 100일 동안 공부한 기록을 SNS에 올리고, 그동안 나와나를 무료로 써요. 챌린저는 올리지 않고 공부만 해요. 3개월 구독료를 미리 내고, 100일이 끝난 뒤 지킨 달 수만큼 이어서 무료로 써요."
  → `Creators post their 100 days of study on social media and use nawana free the whole time. Challengers don't post. They just study: you pay for three months up front, the last 10 days are on nawana, and once the 100 days are over you keep using it free, one month for each month you kept.`
- `.fseg` aria-label · KO "누구의 질문인지" → `Questions for`
- tab labels · KO "크리에이터" / "챌린저" → `Creator` / `Challenger`

Creator tab:
- KO "팔로워가 정말 없어도 되나요?" → `Is it really OK to have no followers?`
  · `Yes. In fact, that's who I'm looking for. It's fine if you haven't started yet, or don't have an account at all.`
- KO "어떤 지원을 받나요?" → `What do I get?`
  · `You use nawana free, and I'll stay right beside you so you keep posting. There's no cash.`
- KO "신청하면 모두 되나요?" → `Does everyone who applies get in?`
  · `I read every application myself. Cohort 1 has room for 20, so I can't take everyone. I want as much range as I can get: different languages, levels, countries and jobs. I'll let you know wherever you told me to.`
- KO "꼭 얼굴이 나와야 하나요?" → `Do I have to show my face?`
  · `No, the format is up to you. Film just the screen, or write about it.`
- KO "꼭 스레드나 인스타여야 하나요?" → `Does it have to be Threads or Instagram?`
  · `Anywhere works. YouTube, TikTok or a blog are fine too. Somewhere you can keep posting.`
- KO "하루 빠지면 끝인가요?" → `If I miss a day, am I out?`
  · `No. If something comes up, tell me ahead of time and we'll reschedule together. If you stop for a long time without a word, the free access stops too.`
- KO "이미 구독 중이면요?" → `What if I already subscribe?`
  · `Mention it in the form or send me a DM. We'll work it out together.`
- NEW (no Korean counterpart; Open item 1) → `Do I have to say I got the app for free?`
  · `Yes. Say in your posts that you got nawana for free, the way your country asks (for example "I got nawana for free" or #ad).`

Challenger tab:
- KO "하루는 어떻게 채워요?" → `What counts as a day?`
  · `At least 4 minutes of calls and one speech. Do both and the day checks in by itself. Nothing to post or send.`
- KO "며칠까지 쉴 수 있나요?" → `How many days can I miss?`
  · `One a month. Miss two in the same month and that month doesn't count. A month isn't a calendar month: it's 30 days at a time from the first day.`
- KO "한 달을 실패하면 끝인가요?" → `If I lose a month, is it over?`
  · `No. Each month counts on its own. Miss the first, and you can still keep the second and third.`
- KO "무료는 어떻게 받나요?" → `How do the free months work?`
  · `From the day after day 100, you keep using nawana free, one month for each month you kept. Keep all three and that's 3 more months; keep one and it's 1. It's not money back.`
- KO "요금제는 뭐예요?" → `Which plan do I get?`
  · `You pick Light, Plus or Max when you pay. Light is the default. You pay for three months at once, and the last 10 days are on nawana. You pay in your own country's currency. Light is ₩40,500 in Korea, ¥4,050 in Japan, €26.97 in euro countries and $26.97 in the US. For anywhere else, choose your country in the form to see your price. Nothing renews.`
- KO "Light로 충분한가요?" → `Is Light enough?`
  · `Start light with Light. It's 150 minutes of calls a month, about 5 minutes a day, so you can do the daily 4 minutes every day. Review, shadowing and speech practice are unlimited on every plan. If you want to call more, pick Plus (450 minutes a month) or Max (600 minutes a month) when you pay, or start with Light and move up if it runs short.`
- KO "결제를 취소할 수 있나요?" → `Can I cancel?`
  · `Before we start, you get a full refund. After that, you can cancel within 14 days of paying. Just email me. The details are in the <a href="/terms.html" target="_blank" rel="noopener">Terms</a>.`
- KO "SNS에 올려야 하나요?" → `Do I have to post on social media?`
  · `No. Challengers just study.`

General:
- KO "몇 명이 함께하나요?" → `How many people take part?`
  · `Up to 20 creators. No limit on challengers.`
- KO "언제 시작하고 언제 끝나요?" → `When does it start and end?`
  · `We plan to start on December 1 and end on March 10, creators and challengers alike. Applications close November 19. All dates are planned and may change with the number of applicants.`
- KO "한국에 살지 않아도 되나요?" → `Can I join from anywhere?`
  · `Yes, wherever you live. Your days start and end on your own local time.`
- KO "그 언어를 하나도 못 해도 되나요?" → `What if I can't speak the language at all?`
  · `If you can put a sentence together, even haltingly, you can start. If you're starting from zero, nawana may be a bit hard for now.`
- KO "중간에 그만둘 수 있나요?" → `Can I stop partway?`
  · `Yes. Just tell me, any time.`

## #apply

- `h2` · KO "해보고 싶다면, 1기에 지원해주세요" → `Want in? Apply for cohort 1`
- first `p.lead` · KO "도전해 보세요!<br>잘 쓰려고 하지 않으셔도 돼요.<br>크리에이터는 부담스럽지만 100일 챌린지에 도전하고 싶다면, 챌린저로 같이 해요."
  → `Go for it!<br>You don't have to write it well.<br>If being a creator feels like too much but you still want the 100 days, join as a challenger.`
- `#deadline` · KO "<b>11월 19일까지 받아요.</b> 12월 1일에 같이 시작할 예정이에요. 신청자 수에 따라 바뀔 수 있어요."
  → `<b>Applications close November 19.</b> We plan to start together on December 1. It may change with the number of applicants.`

`#closed`:
- `h3` · KO "1기 신청은 마감했어요" → `Cohort 1 is closed`
- `p` · KO "12월 1일(예정)에 시작해요. 다음 기수를 기다려 주세요." → `We start on December 1 (planned). Watch for the next cohort.`

Form:
- `.kind` aria-label · KO "지원 종류" → `Join as`
- kind labels · KO "크리에이터" / "챌린저" → `Creator` / `Challenger`

`.kind-note[data-for=creator]`:
- `b` · KO "100일 동안 공부하고, 그 기록을 SNS에 올려요." → `Study for 100 days and post it on social media.`
- li · KO "<b>무료:</b> 100일 동안 나와나를 무료로 써요." → `<b>Free:</b> nawana is free for all 100 days.`
- li · KO "<b>체크인:</b> 올린 글의 링크를 매일 공유해서 체크인해요." → `<b>Check-in:</b> On each posting day, share your post's link to check in.`
- li · KO "<b>인원:</b> 1기는 20명까지 함께해요." → `<b>Spots:</b> Cohort 1 has room for 20.`
- li · KO "<b>시작 예정일:</b> 12월 1일 (신청자 수에 따라 변동 가능)" → `<b>Planned start:</b> December 1 (may change with the number of applicants)`
- li · KO "<b>일정:</b> 챌린저와 같은 날 시작해서, 100일 뒤 같은 날 끝나요." → `<b>Dates:</b> You start on the same day as the challengers and finish together 100 days later.`
- li, NEW (Open item 1) → `<b>Say it:</b> In your posts, say you got nawana for free, the way your country asks (for example "I got nawana for free" or #ad).`

`.kind-note[data-for=challenger]`:
- lead · KO "<b>3개월 구독료를 미리 내고, 100일 동안 매일 공부해요.</b> 마지막 10일은 나와나가 무료로 드리고, 100일이 끝나면 지킨 달 수만큼 이어서 무료로 써요. SNS에 올리지 않아도 되고, 인원 제한도 없어요."
  → `<b>Pay for three months up front, then study every day for 100 days.</b> The last 10 days are on nawana, and once the 100 days are over you keep using it free, one month for each month you kept. You don't post anything, and there's no limit on numbers.`
- `.kn-h` · KO "한 달은 이렇게 지켜요" → `How to keep a month`
- li · KO "<b>하루:</b> 통화 4분 이상과 스피치 1개. 둘 다 채운 날이 자동으로 체크인돼요. 시작과 종료일은 본인이 사는 국가의 시간 기준이에요."
  → `<b>A day:</b> At least 4 minutes of calls and one speech. A day with both checks in by itself. Days start and end on your local time.`
- li · KO "<b>한 달:</b> 시작일부터 30일씩 세요. 쉬는 날은 한 달에 1번만 허용돼요. 2번 쉬면 그 달은 실패예요."
  → `<b>A month:</b> 30 days at a time from the first day. You can miss one day a month. Miss two and that month doesn't count.`
- li · KO "<b>결제:</b> 신청할 때 세 달 치를 한 번에 결제해요. … 마지막 10일은 나와나가 드려요."
  → `<b>Paying:</b> You pay for three months at once when you sign up. You pick your plan when you pay, in your own country's currency. Light: ₩40,500 in Korea · ¥4,050 in Japan · €26.97 in euro countries · $26.97 in the US. For anywhere else, choose your country below to see your price. The last 10 days are on nawana.`
- `.months .kn-h` · KO "무료는 지킨 달만큼" → `One free month for each month kept`
- `.mrow` aria-label · KO "예: 첫 달 실패, 둘째 달 성공, 셋째 달 실패면 1개월 무료"
  → `Example: miss month 1, keep month 2, miss month 3, and you get 1 free month`
- `.m` cells: KO "1달" ✕ "2번 쉼" → `Month 1` ✕ `2 missed`; KO "2달" ○ "지켰어요" → `Month 2` ○ `Kept`; KO "3달" ✕ "3번 쉼" → `Month 3` ✕ `3 missed`; KO "1개월" "무료" → `1 month` `free`
- `.mfoot` · KO "세 달을 모두 지키면 그 뒤 3개월, 두 달이면 2개월을 무료로 이어서 써요. 돈을 돌려드리는 건 아니에요."
  → `Keep all three and you get 3 more months free after the 100 days; keep two and you get 2. It's not money back.`
- `.kn-foot` · KO "<b>시작 예정일:</b> 12월 1일 (신청자 수에 따라 변동 가능). 크리에이터와 챌린저 모두 같은 날 시작해서, 100일 뒤 같은 날 끝나요."
  → `<b>Planned start:</b> December 1 (may change with the number of applicants). Creators and challengers start on the same day and finish together 100 days later.`

Fields:
- name · label KO "뭐라고 불러드릴까요?" → `What should I call you?` · placeholder KO "이름이나 닉네임" → `Name or nickname` · err KO "이름을 적어주세요." → `Please add a name.`
- email · label KO "이메일을 알려주세요" → `Your email`
  · hint creator KO "선정 안내와 무료 코드를 여기로 보내드려요." → `I'll send the result and your free code here.`
  · hint challenger KO "결제 확인과 시작 안내를 여기로 보내드려요." → `Your payment confirmation and start details go here.`
  · placeholder `name@example.com` (unchanged) · err KO "이메일을 확인해주세요." → `Please check your email address.`
- stage · legend KO "지금 운영 중인 계정이 있어요?" → `Do you run an account now?` · KO "있어요" / "없어요" → `Yes` / `No` · err KO "하나 골라주세요." → `Please pick one.`
- contact · label KO "아이디를 남겨주세요" → `Your handle` · placeholder KO "@아이디 또는 링크" → `@handle or link` · err KO "아이디를 적어주세요." → `Please add your handle.`
- language · legend KO "주로 공부할 언어를 하나 골라주세요" → `Pick the one language you'll mainly study`
  · KO "영어" / "독일어" / "일본어" / "스페인어" / "한국어" → `English` / `German` / `Japanese` / `Spanish` / `Korean` · err `Please pick one.`
- level · legend KO "그 언어, 지금 어느 정도예요?" → `Where are you with it now?`
  · KO "A1 · 아는 말 몇 개" → `A1 · A few words`
  · KO "A2 · 더듬더듬 문장" → `A2 · Halting sentences`
  · KO "B1 · 일상 대화" → `B1 · Everyday conversation`
  · KO "B2 · 웬만한 주제" → `B2 · Most topics`
  · KO "C1 · 자유롭게" → `C1 · Freely`
  · KO "C2 · 원어민 가까이" → `C2 · Close to native`
  · `#level_note` KO "나와나는 듣고 읽을 수는 있어야 쓸 수 있어요. 완전히 처음 배우는 단계라면 아직은 맞지 않을 수 있어요."
    → `nawana works once you can follow what you hear and read. If you're starting from zero, it may not fit yet.`
  · err `Please pick one.`
- device · legend KO "어떤 폰을 쓰세요?" → `Which phone do you use?` · KO "아이폰" / "안드로이드" → `iPhone` / `Android` · err `Please pick one.`
- country · legend KO "어느 나라에 살고 있어요?" → `Which country do you live in?`
  · hint KO "시작과 종료일은 본인이 사는 국가의 시간 기준이에요." → `Your days start and end on your local time.`
  · first option KO "나라를 골라주세요" → `Choose your country`
  · err KO "사는 나라를 알려주세요." → `Please choose where you live.`
- nawana_use · legend KO "나와나를 써보셨나요?" → `Have you tried nawana?` · KO "아직이요" / "조금 써봤어요" / "지금 쓰고 있어요" → `Not yet` / `A little` / `I use it now` · err `Please pick one.`
- fee (challenger) · legend KO "참가비" → `Your fee`
  · `#fee_amount` filled by script (any currency) · span KO "Light 3개월 구독료" → `Three months of Light`
  · `#fee_where` KO "사는 나라에 따라 달라요. 위에서 나라를 고르면 바뀌어요." → `It depends on where you live, and changes when you choose your country above.`
  · hint KO "Light는 한 달에 통화 150분이에요. 3개월 구독료를 먼저 내요. 마지막 10일은 나와나가 무료로 드려요. 100일이 끝난 다음 날부터, 지킨 달 수만큼 이어서 무료로 써요. 신청서를 보내면 바로 결제로 이어지고, 한 번만 결제돼요."
    → `Light gives you 150 minutes of calls a month. You pay for three months up front. The last 10 days are on nawana. From the day after day 100, you keep using it free, one month for each month you kept. After you send this form, I'll email you the link to pay. You're charged once.`
  · hint KO "결제할 때 Plus(한 달 450분)나 Max(한 달 600분)를 고를 수도 있어요. Light로 하다가 모자라면 그때 올려도 돼요."
    → `When you pay, you can pick Plus (450 minutes a month) or Max (600 minutes a month) instead. Or start with Light and move up if it runs short.`
- cadence (creator) · legend KO "얼마나 자주 올릴 수 있나요?" → `How often can you post?`
  · hint KO "올릴 요일을 골라주세요. 매일이 제일 좋아요." → `Pick the days you'll post. Every day is best.`
  · day labels (values stay 월…일) KO "월 화 수 목 금 토 일" → `Mon` `Tue` `Wed` `Thu` `Fri` `Sat` `Sun`
  · err KO "하루 이상 골라주세요." → `Pick at least one day.`
- platforms (creator) · legend KO "어디에 올리고 싶으세요? <span>여러 개 골라도 돼요</span>" → `Where do you want to post? <span class="opt-tag">Pick as many as you like</span>`
  · KO "스레드" / "인스타그램" / "유튜브" / "틱톡" / "블로그" / "다른 곳" → `Threads` / `Instagram` / `YouTube` / `TikTok` / `Blog` / `Somewhere else`
  · err KO "하나 이상 골라주세요." → `Pick at least one.`
- persona (creator) · label KO "어떤 100일 챌린지를 해보고 싶으세요?" → `What would your 100 days look like?`
  · hint KO "아직 흐릿해도 괜찮아요. 떠오르는 대로 적어주세요." → `It's fine if it's still fuzzy. Write whatever comes to mind.`
  · placeholder KO "예: 내년 여름 교토에 가기 전에 100일 동안 매일 일본어로 통화하고, 그날 고친 문장을 올릴게요."
    → `e.g. Before I move to Madrid next summer, I'll talk in Spanish every day for 100 days and post the sentence I fixed that day.`
  · err KO "한 줄이라도 적어주세요." → `Even one line is fine. Please write something.`
- reference_link (creator) · label KO "이런 식으로 해보고 싶은 영상이나 크리에이터가 있나요? <span>없어도 돼요</span>" → `Is there a video or creator you'd like to model yours on? <span class="opt-tag">Optional</span>`
  · hint KO "영상 링크나 계정 이름을 적어주세요." → `Add a video link or an account name.`
  · placeholder KO "https:// 또는 @아이디" → `https:// or @handle`
- why (creator) · label KO "이걸 왜 해보고 싶으세요?" → `Why do you want to do this?`
  · placeholder KO "이 언어를 공부하려는 이유, 크리에이터가 되고 싶은 이유, 뭐든 좋아요." → `Why you're learning this language, why you want to be a creator, anything at all.`
  · err `Even one line is fine. Please write something.`
- `.trap` label (hidden honeypot) KO "웹사이트" → `Website`
- rules (challenger) · `ul.agree-list`:
  · KO "매일 통화 4분 이상, 스피치 1개 이상" → `Every day: at least 4 minutes of calls and at least one speech`
  · KO "쉬는 날은 한 달에 한 번만" → `One day off a month, no more`
  · KO "3개월 구독료를 먼저 내요. 마지막 10일은 나와나가 무료로 드려요" → `You pay for three months up front. The last 10 days are on nawana`
  · KO "100일이 끝난 다음 날부터, 지킨 달 수만큼 이어서 무료로 써요 (환불이 아니에요)" → `From the day after day 100, you use it free for one month per month kept (not a refund)`
  · checkbox KO "위 챌린지 규칙에 동의해요." → `I agree to the challenge rules above.`
  · err KO "규칙에 동의해 주세요." → `Please agree to the rules.`
- consent · KO "적어주신 내용을 프로그램 선정과 연락에 쓰는 데 동의해요. 선정되면 앱의 일별 통화 시간으로 활동을 확인해요. 프로그램이 끝나거나 요청하시면 바로 지워요. <a>개인정보 처리방침</a>"
  → `I agree that what I wrote is used to choose participants and to contact me. Once I take part, my activity is checked from my daily call time in the app (for challengers, also how many speech takes I record each day). It's deleted when the program ends, or whenever I ask. <a href="/privacy.html" target="_blank" rel="noopener">Privacy Policy</a>` (see Open item 2)
  · err KO "동의가 필요해요." → `Please tick this to continue.`
- `#send` · creator KO "지원하기" → `Apply`; challenger (script) KO "신청하기" → `Sign up`
- `#send` while sending (script) · KO "보내는 중이에요" → `Sending`
- `#status` errors (script):
  · closed · KO "1기 신청은 마감했어요." → `Cohort 1 is closed.`
  · busy · KO "지금 지원이 몰리고 있어요. 잠시 뒤에 다시 보내주세요." → `A lot of applications are coming in right now. Please send it again in a moment.`
  · other · KO "전송이 안 됐어요. 쓰신 내용은 그대로 있으니 다시 눌러주세요." → `That didn't send. Everything you wrote is still here, so please tap again.`

`#done` (after sending). The Korean sentence ends after the email; in English the email sits at the end of the sentence, so `#done_line` carries everything before it and a `.` follows `#done_mail`:
- `h3` · KO "메일을 확인하세요" → `Check your email`
- `p` · KO `<span id="done_line">신청서는 잘 받았어요. 다음에 할 일을</span> <b id="done_mail">메일</b>로 보내드렸어요.`
  → `<span id="done_line">Got your application. I've sent what happens next to</span> <b id="done_mail">your email</b>.`
- `#done_line` for challengers (script) · KO "신청은 가입과 결제를 마쳐야 끝나요. 하는 방법을"
  → `You're signed up once you've joined the app and paid. I've sent the steps to`
- `#done_inbox` · KO "메일 열기" → `Open email`
- `.pay-note` · KO "메일이 안 보이면 스팸함을 봐주세요. 그래도 없으면 <a>hello@nawana.app</a>으로 알려주세요."
  → `Don't see it? Check your spam folder. Still nothing? Write to <a href="mailto:hello@nawana.app">hello@nawana.app</a>.`

`#partner`:
- `h3` · KO "같이 크게 만들어 볼까요?" → `Want to build something bigger together?`
- `p` · KO "이걸 보고 번뜩이는 아이디어가 넘쳐서, 제대로 한번 크게 만들어 보고 싶으신가요?<br>협업, 광고, 스폰서 제안도 받아요. 편하게 보내주세요."
  → `Did this spark an idea you want to do properly, and big?<br>I'm open to collaborations, ads and sponsorships. Just write.`
- button `hello@nawana.app` (unchanged; mail subject `nawana Creator program` unchanged)

## #pile (the tear-off calendar and guestbook)

- `p.big` · KO "유창하게 말하는 날이 오면," → `When the day comes that you speak it fluently,`
- `.btn[data-track=pile]` · KO "1기 지원하기" → `Apply for cohort 1`
- canvas hint (script `draw()`), two lines each:
  · all pages written · KO "바닥의 종이가 다 채워졌어요" / "일력의 ${next}번째 장을 눌러 남겨요"
    → `Every page on the floor is full` / `Tap page ${next} on the pad to write yours`
  · otherwise · KO "떨어진 종이를 눌러 뒷면에 한 줄 남겨요" / "이름이 적힌 종이엔 남긴 글이 있어요 · ${next}번째 장은 맨 마지막에"
    → `Tap a fallen page and write a line on the back` / `Pages with a name have a line on them · Page ${next} comes last`
- `.turn-card` aria-label · KO "달력 뒷면" → `Back of the calendar page`
- `.fday` "DAY" (unchanged)
- `#turn-edit` · KO "고치기" → `Edit`
- `#turn-name` · sr label KO "이름" → `Name` · placeholder KO "이름 · 종이에 보여요" → `Name · shows on the page`
- `#turn-text` · sr label KO "한 줄 남기기" → `Leave a line` · placeholder KO "유창해지면 하고 싶은 일을 한 줄로. 다짐도, 응원도 좋아요."
  → `One line on what you'll do once you're fluent. A promise or a cheer works too.`
- `#turn-band` aria-label · KO "띠 색" → `Band color`
- band names (sr) · KO "검정" / "빨강" / "주황" / "초록" / "분홍" / "보라" → `Black` / `Red` / `Orange` / `Green` / `Pink` / `Purple`
- `#turn-cancel` · KO "닫기" → `Close`
- `#turn-send` · KO "남기기" → `Post`; while editing (script) KO "고치기" → `Save`
- `#turn-prev` / `#turn-next` aria-label · KO "이전 장" / "다음 장" → `Previous page` / `Next page`
- name fallback (script, three places) · KO "익명" → `Anonymous`
- time ago (script `ago`) · KO "방금" / "${m}분 전" / "${h}시간 전" / "${d}일 전"
  → `just now` / `${m} min ago` / `${h} hr ago` / `1 day ago` when d is 1, else `${d} days ago`
- errors (script):
  · `NOTE_ERR.not_yours` KO "이 브라우저에서 쓴 글만 고칠 수 있어요." → `You can only edit lines written in this browser.`
  · `NOTE_ERR.too_many` KO "오늘은 세 장까지 남길 수 있어요." → `You can leave up to three pages a day.`
  · `NOTE_ERR.bad_word` KO "다른 말로 남겨주세요." → `Please say it another way.`
  · `NOTE_ERR.busy` KO "잠시 뒤에 다시 남겨주세요." → `Please try again in a moment.`
  · `NOTE_ERR.taken` KO "방금 다른 사람이 이 장에 썼어요. 다른 장을 골라주세요." → `Someone just wrote on this page. Please pick another one.`
  · no name KO "이름을 써주세요. 종이에 보여요." → `Please add your name. It shows on the page.`
  · no line KO "한 줄 써주세요." → `Please write a line.`
  · edit failed KO "고치지 못했어요. 다시 해주세요." → `Couldn't save your edit. Please try again.`
  · post failed KO "남기지 못했어요. 다시 해주세요." → `Couldn't post it. Please try again.`

## footer

- KO "nawana" / "커뮤니티" / "개인정보 처리방침" → `nawana` / `Community` / `Privacy Policy` (href `/privacy.html`)

## Fixes 2026-11-12

Apply these to the English page if it was already built from the earlier version. The entries
above already carry the new wording.

1. fee (challenger), first hint, last two sentences
   - old: `Sending this form takes you on to paying, and you're charged once.`
   - new: `After you send this form, I'll email you the link to pay. You're charged once.`
   (The form ends on "Check your email"; payment goes through the link in that mail.)
2. reference_link (creator), label
   - old: `Is there a video or creator you'd like to do it like? <span class="opt-tag">Optional</span>`
   - new: `Is there a video or creator you'd like to model yours on? <span class="opt-tag">Optional</span>`
3. #ideas note 7 ("Read your day out loud"), last sentence
   - old: `After 100 days, you have 100 days of diary.`
   - new: `After 100 days, you have a 100-day diary.`
