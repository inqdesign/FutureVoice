# brief — 주간 테스트는 "내 한 주"다

- **piece**: 2026-11-09-weekly-test-your-week
- **format**: Instagram + Threads carousel, 1080×1350, 6 slides
- **version**: 1.3.2 (136) — release-notes feature (weekly test redesign, 2026-11-08)

## One message

주간 테스트는 그 주에 **내가 실제로 공부한 것**으로만 만들어져요 — 뻔한 문제은행이 아니라, 통화가 가르친 단어·미래의 내가 쓴 표현·교정된 문장으로.

## Who it's for

이미 나와나로 한 주를 보낸 사람 — 통화하고, 복습 카드 넘기고, 교재가 쌓인 학습자. "시험"이라는 말에 식은 문제집을 떠올리는 사람에게, 이건 **네 지난 한 주를 돌려주는 시험**이라는 걸 보여준다. 완전 초보가 아니라, 문장을 더듬더듬 만들며 매주 쌓아 가는 사람.

## Why now

1.3.2에서 주간 테스트가 다시 설계됐다(2026-11-08). 예전엔 "묵혀둔 것 전부"를 끌어왔지만, 이제 시험지는 **그 주의 복습 자료**에서만 짜인다. 릴리스 노트의 대표 개선이고, 기능 시리즈 e16(주간 시험)을 되풀이하지 않고 **그 다음 이야기**로 잇는다 — "주간 테스트가 뭔가"가 아니라 "이제 네 한 주로만 만들어진다".

## Proof in the app

- CLAUDE.md "The weekly test (2026-09-23, redesigned 2026-11-08)" — outranks the older bullets.
- Kit `nw-weeklytest`: item kinds `meaning · gap · translate · grammar · listen · speak`, and the result page with missed items. **No flame, no gauge** (the kit enforces this).
- Captures: `weekly-test-gap`, `weekly-test-grammar`, `weekly-test-listen`, `weekly-test-result`.
- Sample data only — every word/score/count on screen is illustrative, never a user result.

## Outline (6 slides)

1. **Cover** — 제목 "내 한 주로 만든 시험". 한 줄: 그 주에 공부한 것만 나와요. Screen: `weekly-test-gap` (한 문항이 깔끔하게 보이는 입구). Phone moves in, text fades.
2. **그 주 네 통화가 가르친 것** — `weekly-test-gap` (빈칸에 들어갈 표현 = 미래의 내가 통화에서 쓴 말). Say: 문제은행이 아니라, 통화가 가르친 단어와 표현. *(sticker 가능: 작은 gap 문항 카드)*
3. **교정된 문장도, 들을 가치가 있던 줄도** — `weekly-test-grammar` + `weekly-test-listen` 중 하나(디자이너 택1, 혹은 `grammar`를 메인으로 `listen`을 sticker). Say: 교정됐던 문장, 다시 들어 볼 만했던 줄까지 — 한 주가 통째로 들어온다. *(얇은 한 주면 시험 자체가 안 열려요 — 한 줄 보조 카피)*
4. **맞히면, 어디서나 아는 것이 돼요** — `weekly-test-result` (missed items가 보이는 결과 페이지). Say: 맞힌 단어·문장은 복습 카드와 교재에서도 아는 것으로 바뀌어요. 시험·카드·교재가 하나로 이어져요. *(known-everywhere는 카피로 — 전용 화면 없음)*
5. **"제 답도 맞아요"** — `weekly-test-result`를 다시 쓰되(혹은 grammar 문항) 카피로 appeal을 전한다. Say: 틀렸다고 나왔는데 맞았다면, "제 답도 맞아요"로 바로잡으면 맞은 걸로 쳐요. **전용 "이의제기" 버튼 화면을 그리지 말 것** — 앱에 그런 단독 화면은 없다. appeal은 결과/문항 옆 카피로만.
6. **Outro** — wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" · nawana.app.

## Channels

- **IG carousel** (1080×1350) + **Threads** (same renders, Threads takes 4:5 as is).
- **Community**: a short news draft ("주간 테스트가 바뀌었어요") — publisher drafts, founder approves. Do **not** add a new feature-series entry: e16 already covers the weekly test; this is the update, not a catalogue re-run.

## Facts the copywriter must keep true

- **No streak flame, no score gauge** on the weekly test. Never show or imply either.
- A **thin week doesn't open** the test — say it as a feature (네 한 주가 기준), never as "unlocked after N items".
- Known-everywhere (맞히면 복습 카드·교재에서도 아는 것으로) and appeal ("제 답도 맞아요") are told in **copy only** — no dedicated screen for either; use the test/result captures beside them.
- The six item kinds are real: meaning · gap · translate · grammar · listen · speak. Don't invent a seventh.
- Numbers/scores on any slide are illustrative sample data, never a user statistic.
- Korean 해요체; never "당신". The fluent self, if quoted, speaks 반말. Positive first.
- No em dash in posted/caption copy (마침표·쉼표로).

## Success signal

Saves and profile visits on IG; community views on the news draft. The redesign answers a churn-adjacent feeling ("시험 = 지겨운 문제집"); watch whether saves run above the feature-series baseline.
