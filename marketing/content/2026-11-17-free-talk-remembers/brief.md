# Brief — 자유 대화가 지난 대화를 기억해요

> Autopilot upload run (1.3.6 · build 149 · no founder watching). Feature is release-note
> feature 2, the founder's own approved words — the message is fixed; this brief fills the
> audience, the one scripted exchange, the card outline, channels, facts to keep true.
> Final slide wording is the copywriter's; nothing here is final copy.

## One message

며칠 전에 나눈 얘기를 꺼내면, 유창한 나가 **그때 네가 했던 말을 찾아와 거기서부터 이어 가요.**
(매번 처음 보는 사람이 아니라, 지난 통화를 기억하는 상대랑 계속 이야기하는 느낌.)

If a card can't trace back to this line, it's the wrong card.

## Who it's for

자유 대화를 **며칠 간격으로 꾸준히** 쓰는 사람 — 지난주에 면접·발표·여행 얘기를 한 번 해 놓고,
오늘 다시 통화를 켜는 직장인·취준생. 보통의 AI 대화 상대는 매 통화가 백지라, "저번에 말했던
그거…"를 꺼내면 못 알아듣거나 지어낸다. 그래서 통화가 **일회성**처럼 느껴지고, 어제 한 말을
오늘 또 설명해야 한다. 이들이 원하는 건 "계속되는 관계" — 내가 한 번 말해 둔 걸 기억하고,
다음에 거기서부터 이어 가 주는 상대. 그 틈을 노린다.

Honest floor (BRAND): 완전 초보 아님. 더듬어도 문장을 만드는 사람. 제로-투-유창 약속 금지.

## Why now

- **1.3.6 build 149 새 기능** (CLAUDE.md "A free talk remembers the talks before it, and the
  APP looks one up", `TalkRecall.swift`). 1.3.6 What's New 2번 카드에 오른 창업자 승인 문구:
  ko "자유 대화가 지난 대화를 훨씬 자세히 기억해요. 며칠 전에 나눈 얘기를 꺼내도, 그때 했던
  말을 찾아와 거기서부터 이어 가요." / en "Free talk now remembers past talks in much more
  detail. Bring up one from days ago and it finds what you actually said, then carries on
  from there." — 카피는 이 문장 안에서만. 넘겨짚지 말 것.
- 이 조각이 파는 건 제품의 **차별점 그 자체** — 유창한 나는 "내 목소리"일 뿐 아니라 **나를
  기억하는** 상대다. AI 튜터는 매 세션이 백지인데, 여긴 통화가 쌓인다. (BRAND: AI 튜터 vs 나.)
- 시리즈: `나와나로 할 수 있는 것` 중 **talk** 카테고리의 심화 — "통화한다"를 넘어 "통화가
  이어진다". 자매 조각 `2026-11-17-free-talk-your-way`(자유 대화를 내 맘대로 끌고 간다)와는
  다른 약속(그쪽=통제, 이쪽=기억·연속성). 중복 아님, 같은 기능의 다른 면.

## Proof in the app (what is real, what the designer may show)

출처: CLAUDE.md "Free talk has a character brief (2026-11-17)" 아래 "A free talk remembers the
talks before it, and the APP looks one up" 단락 (`TalkRecall.swift`).

- **실제 동작, 그대로만:** 프롬프트에 지난 통화의 **색인**(최근 통화 한 줄 요약 12개: 언제 + 제목)이
  실려 있고, 학습자가 지난 통화 얘기를 꺼내면 앱이 그 통화를 **찾아와** 실제 오갔던 말(그 통화에서
  뭘 어떻게 말했는지, 24줄/2,400자 분량)을 프롬프트에 끼워 넣는다. 그래서 유창한 나가 **그때
  네가 실제로 한 말**에서부터 이어 간다. (예: 면접관 이름을 물으면, 찾아온 그 통화에서 답한다.)
- **보여줄 화면 = 라이브 통화 하나.** kit `nw-call` (`web/kit/screens/call.js`). 디자이너가 `call.user(…)`
  / `call.say(…)`로 아래 "스크립트"대로 대화를 흘린다. 앱 캡처 불필요 — nw-call이 라이브 통화를 그린다.
- **다른 화면 금지.** 색인·검색은 백그라운드 동작이라 UI가 없다 → "메모리 목록" 같은 가짜 화면을
  그리지 말 것(BRAND Visual). 증거는 **대화 내용**이 전부다 — 유창한 나가 지난 통화의 구체적
  디테일을 집어내는 그 한 줄이 곧 "기억한다"의 증명.

## The one scripted exchange (English target · Korean learner)

디자이너는 nw-call 하나에 아래 대화를 넣고, 카드별로 그 진행의 다른 순간을 보여준다
(learning-purpose에서 같은 nw-home을 콘텐츠만 바꿔 쓴 것과 같은 방식).

```
You:          Remember the interview I told you about last week?
Future self:  The design studio one? You were sweating the portfolio question.
              How'd it go?
You:          I got it. I start in two weeks.
Future self:  No way, that's huge. So the portfolio part landed in the end?
```

왜 이 대화인가: 유창한 나의 두 번째 줄이 **지난 통화에만 있던 디테일**("design studio",
"the portfolio question", "nervous")을 집어낸다 — 색인의 제목 한 줄로는 못 할 말, **찾아온
그 통화**에서만 나오는 말. 이게 "그때 한 말을 찾아와 이어 간다"의 눈에 보이는 증거다.
(디테일은 전부 가상 샘플 — 실 유저 데이터 아님.)

## Outline — 5 cards (cover → 3 beats → close)

> 커버/아웃트로 = PNG 스틸. 기능 카드 = `carousel.html?solo=N` → `record.mjs` 8–12초 MP4.
> 세 기능 카드 전부 같은 `nw-call`, 같은 대화의 다른 순간.

| # | Card | The one point | Screen / kit call | Sticker·compare |
|---|---|---|---|---|
| 01 | **Cover (still)** | 며칠 전 얘기를 꺼내면, 그때 한 말을 찾아와 이어 가요 | 타이포 중심. 뒤에 `nw-call` 한 장면을 아주 옅게 깔아도 됨(스틸로 성립해야) | — |
| 02 | **"저번에 그거, 기억해?" (setup, live)** | 지난주 통화 얘기를 툭 꺼낸다 | `nw-call`: `call.user("Remember the interview I told you about last week?")` 올라가고 `call.listen()`→`call.say` 직전까지 ("생각하는 중") | 학습자 버블 하나를 스티커로 띄워도 됨 |
| 03 | **그때 한 말을 집어내요 (payoff, live)** | 유창한 나가 지난 통화의 **구체적 디테일**을 꺼냄 — 색인 한 줄로는 못 할 말 | `nw-call`: `call.say("The design studio one? You were sweating the portfolio question. How'd it go?")` — 핵심 구절("design studio", "portfolio question") 강조 | 이 한 줄이 "기억한다"의 전부. 가장 세게 보여줄 카드 |
| 04 | **거기서부터 이어 가요 (continuation)** | 설명을 다시 안 해도 돼요 — 어제의 이야기가 오늘 계속됨 | `nw-call`: `call.user("I got it. I start in two weeks.")` → `call.say("No way, that's huge. So the portfolio part landed in the end?")` | "매번 백지인 AI 상대"와의 대비를 캡션으로(화면 비교 금지) |
| 05 | **Outro (still)** | 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 · nawana.app | 표준 아웃트로(Futureself 발화 · 워드마크) | — |

메모: 02→03→04가 **한 통화의 흐름**이라 세 카드가 자연스럽게 이어진다. 03이 payoff(디테일을
집어내는 순간), 04가 그 가치의 결론(연속성). 과장 금지 — 색인·검색 원리는 설명하지 말고,
**대화 그 자체로** 보여줄 것.

## Channels (standard)

- **Instagram carousel** (main): 5 items, 1080×1350. 01·05 PNG, 02–04 MP4. 캡션 훅 =
  "'저번에 말한 그거, 기억해?' — 유창한 내가 진짜 기억해요" 류 한 줄, 그 뒤 카드별 한 줄,
  끝에 "자유 대화에서, 며칠 전 통화도 이어서 할 수 있어요". 해시태그 3–5 (#영어회화 #영어공부
  #스피킹 #전화영어 …).
- **Threads**: 같은 앞 3–4장, 더 짧고 대화체(IG 캡션 복붙 금지). "AI랑 영어 하다 보면 저번에 한
  말을 또 설명하게 되지 않아요? 여긴 지난 통화를 기억해요" 식 리플 유도.
- **Community series**: 같은 날 엔트리, `cat: talk`, `web/community/series.json`에 추가(720×900 JPG,
  가능하면 비디오 슬라이드). 라이브 반영 = 대표 승인.
- 그 외 없음(Reel/Story 미설정).

## Facts that must stay true (check before copy & packaging)

1. **자유 대화 한정.** 이 기억은 free talk(유창한 나와의 자유 통화)에서 동작. 시나리오·Find people
   상대·튜터 통화를 "지난 통화 기억"으로 묶지 말 것.
2. **없던 통화는 지어내지 않는다.** 폰에 없는 통화를 꺼내면("언니 결혼식 기억해?" — 그런 통화를
   한 적 없을 때) 유창한 나는 "그건 기억 안 나, 얘기해 줘"라고 한다. "뭐든 다 기억한다"로 과장 금지.
   카피에서 "말만 하면 다 기억해요" 같은 전지적 약속 금지 — **네가 실제로 한 통화**만.
3. **점수·평가 아님.** 면접 통화를 소재로 쓰되, 유창한 나가 면접을 "채점"하지 않는다. "면접 피드백
   받아요" 금지 — 그냥 이어서 대화할 뿐.
4. **화면의 모든 대화·이름·디테일은 kit 샘플.** 실 유저 데이터·대표 실명("Eunggyu") 금지(BRAND).
   면접 디테일(design studio, portfolio)은 전부 가상 예시 — 통계·실화로 제시 금지.
5. **대화 줄(영어)은 MATERIAL이라 영어가 맞다**(배우는 언어). 한국어로 번역해 버블에 넣지 말 것.
   칩·캡션·설명만 한국어(해요체).
6. **유창한 나는 반말/casual**, 그립다·보고 싶다 류 금지(BRAND·`fluent-self-no-longing` 메모).
   따뜻함 = 관심. 샘플 대화의 "No way, that's huge" 톤 유지.
7. **"첫 20분은 무료예요"** — 게시일에 `freeGrantSeconds`(1200초) 재확인. "무료 체험" 금지(체험 없음).

## Success signal

- **Instagram** (게시 후 72h): reach 대비 saves·프로필 방문·nawana.app 링크 탭. 이 조각은
  "일회성이 아니라 이어진다"는 **차별점**이라, 커뮤니티/IG 리퍼러로 들어온 **설치→온보딩 시작**과
  저장률이 핵심.
- **Threads**: 리플 — "AI는 저번 말 못 알아듣던데" "며칠 전 것도 돼요?" 류(다음 조각 재료).
- **Community**: 엔트리 조회수.
- 공개물엔 어떤 유저 데이터도 쓰지 않음.
