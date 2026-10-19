# Brief — 스피치 챌린지: 같은 원고, 하나의 순위표

> Autopilot upload run (1.1.8 · no founder input). The message, audience intent and screens
> are fixed in `status.md`; this brief keeps them and fills the gaps — audience, outline
> (6 cards), the exact kit screen call per card, channels, facts to keep true, success.
> No final slide copy here — that's the copywriter's.

## One message

스피치 챌린지 — 모두 같은 원고를 읽고 점수로 겨뤄요. 카메라 켠 기록만 올라가고,
순위엔 이름과 점수만 보여요.

If a card can't trace back to this one line, it's the wrong card.

## Who it's for

혼자 영어를 공부하는 직장인·대학생. 문장은 만들지만 소리 내 읽으면 버벅이고,
발음과 전달력을 올리고 싶은데 혼자 하면 재미도 동기도 안 붙는 사람. 지하철에서 IG를
넘기다 **이름과 점수가 줄 세워진 순위표**를 보고 "나도 읽으면 몇 점 나오지?" 하고
멈추는 그 순간이 노림수 — 혼자 하던 말하기 연습에 처음으로 "다른 사람들도 같은 걸
하고 있다"가 보인다. 나와나를 아직 모르는 사람의 첫 접점.

Honest floor: 완전 초보가 아니다. 원고 한 문단을 소리 내 읽을 수 있는 사람. 제로-투-유창
약속 금지(BRAND).

## Why now

1.1.8(Speech 탭)에 새로 들어간 기능. 목소리 클론 앱에 **공개 순위표**가 붙은 건 흔치
않고, 순위표는 본질적으로 공유된다("내 점수 봐") — 신규 유입을 끌기 좋은, 그 자체로
퍼지는 소재다. Speech 탭엔 프롬프터+점수가 이미 있었고, 챌린지는 그 위에 얹힌 **사회적
레이어**라 "혼자 하는 앱"이라는 인상을 처음으로 깬다.

Series 관계: `2026-10-11-what-you-can-do`(시리즈 커버, 진행 중)가 Speech+챌린지를
"별도 에피소드"로 미뤄 뒀다 — 이 조각이 그 에피소드. 커버와 중복되지 않는 독립 캐러셀.

## Proof in the app (CLAUDE.md "Speech challenges — one script, one leaderboard")

- **Kit:** `nw-speech` (`web/kit/screens/speech.js`), SpeechTab / SpeechPrompterView /
  SpeechResultView / SpeechChallengeViews에서 측정. Poses:
  `list` · `open` · `camera` · `prompter` · `result` · `challenge` · `rank-up`;
  메서드 `open()` `camera(true)` `record()` `result(81)` `rankUp(14,8)` `demo()`.
- **Fidelity capture:** `marketing/captures/speech-challenge.png` — 실제 앱의 결과 게이지(81,
  주황) + "챌린지" 섹션 + SpeechChallengeMomentSheet(메달 · "N위예요" · 순위 행)과 kit이 일치.
- CLAUDE.md "Speech challenges — one script, one leaderboard (2026-10-10)"의 모든 규칙.

## Outline — 6 cards (cover → 4 feature → outro)

> 각 카드: 한 줄 목적 + 정확한 kit 스크린 호출. 커버/아웃트로는 PNG 스틸, 기능 카드는
> `carousel.html?solo=N` → `record.mjs` 8–12초 MP4 루프.

| # | Card | The one point | Exact kit screen call | Sticker/compare |
|---|---|---|---|---|
| 01 | **Cover (still)** | 같은 원고로 모두가 겨루는 순위표가 Speech 탭에 생겼어요 | `nw-speech`, 기본 list 상태(= `build()` 그대로: "챌린지" 섹션 · "41명 도전 중" · 상단 3명 이니셜 얼굴 · 샘플 챌린지 행 · 보드 안내). 그리드에서 스틸로 읽혀야 함 | — |
| 02 | **같은 원고를, 다 같이** | 공개된 같은 원고를 프롬프터로 읽어요 — 레벨 구분 없이 모두 하나의 보드 | `nw-speech`, demo 또는 pose `open`→`prompter`: 프롬프터가 한 줄씩 스크롤(`record()` 비트). 샘플 원고 "Why practise out loud?" | — |
| 03 | **카메라 켜고 읽으면 순위에** (privacy) | 카메라 켠 기록만 올라가요. 영상은 내 폰에만 남고, 순위엔 이름과 점수만 보여요 | `nw-speech`, demo 챌린지 플로우에서 **camNote 보이는 프롬프터**(카메라 OFF, 챌린지 모드 → micb 노트 "카메라를 켜야 순위에 올라가요. 영상은 내 폰에만 남아요." 가독), 그 뒤 `camera(true)`로 카메라 ON 전환 | 노트 자체가 프라이버시 문구 — 스티커 불필요 |
| 04 | **점수는 앱이 매겨요** | 읽자마자 점수 — 정확도·속도·쉼·군말·목소리 안정감 다섯 항목, 가장 잘한 기록이 남아요 | `nw-speech`, `result(81)`: 게이지 0→81 카운트업 + 코치 한 줄("Steady and clear…") + "측정 결과" 5행(94% · 148 words/min 등) | 게이지 스티커로 떼어 써도 됨 |
| 05 | **순위를 올려요** (payoff) | 가장 잘한 기록이 보드에 올라가 순위가 바뀌어요 — 상위 10명 + 내 줄, 레벨 구분 없이 한 보드 | `nw-speech`, `rankUp(14, 8)`: SpeechChallengeMomentSheet 올라옴(초록 화살표 · "14위 → 8위" · 순위 행 이름+점수+"나") | 순위표 자체가 공유 포인트 |
| 06 | **Outro (still)** | 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 · nawana.app | 표준 아웃트로(Futureself 발화 · 워드마크) | — |

커버는 보드의 "활동"(41명 · 얼굴)을 보여주는 list가 가장 "이게 뭔지"가 빠르게 읽힘.
payoff(순위 오름)는 끝에서 한 번 — 중간에 미리 터뜨리지 말 것.
`challenge` pose("1위예요" 포디엄, 캡처의 그 화면)는 **founder 이름이 캡처에 박혀 있어
위험** — 05엔 `rankUp`(이름이 kit 샘플)로 가고, 1위 포디엄을 꼭 쓰려면 렌더에서 이름이
"Jiwoo" 등 kit 샘플인지 먼저 확인(Risk 1).

## Channels (standard)

- **Instagram carousel** (main): 6 items, 1080×1350. 01·06 PNG(커버는 그리드 스틸로 성립),
  02–05 MP4 루프(`carousel.html?solo=N`). 캡션 훅 = 순위표의 낯섦/당김
  ("같은 원고를 읽고 점수로 겨뤄요"), 그 뒤 카드별 한 줄, 끝에 프라이버시 한 줄
  ("순위엔 이름과 점수만"); 해시태그 3–5(#영어회화 #영어공부 #스피킹 …).
- **Threads**: 같은 6 아이템, 더 짧고 대화체(IG 캡션 복붙 금지). "몇 점 나올 것 같아요?"로
  리플 유도.
- **Community series**: 같은 날 시리즈 엔트리(720×900 JPG, 가능하면 비디오 슬라이드),
  `cat: practice`. 새 엔트리(what-you-can-do 커버와 별개 에피소드). 라이브 사이트 =
  대표 승인.
- 그 외 없음(Reel/Story 미설정).

## Facts that must stay true (check before copy & before packaging)

1. **founder 이름 유출** — 캡처(`speech-challenge.png`)의 순위표에 실명 "Eunggyu"가 박혀
   있다. 공개물에 대표 본인 이름 금지(BRAND Never). kit 기본 샘플명은 "Jiwoo"이고
   `rankUp` 기본 행은 Camille/Yuna. **모든 렌더가 kit 샘플명인지 확인**, 캡처 이미지를
   그대로 슬라이드에 쓰지 말 것.
2. **레벨 구분 없음 · 모두 한 보드** — 밴드/매칭/레벨별 리그 암시 금지("그냥 하는 거야").
   단, 보드는 **배우는 언어(target)별**이다: "같은 언어를 배우는 사람들"이 맞고 "전 세계
   모두"가 아니다.
3. **프라이버시는 문구 그대로, load-bearing** — 폰을 떠나는 건 **이름과 점수뿐**, 영상·오디오는
   폰에만. 카메라 ON 필수. "비공개로 지켜요"처럼 뭉개지 말고, **나가는 것/남는 것**을 그대로.
   긍정 먼저: "카메라 켜고 읽으면 순위에 올라가요" → "영상은 폰에만 남아요".
4. **점수는 코드가 계산**(SpeechAnalyzer), LLM 심사 아님. "앱이 점수를 매겨요"는 OK,
   "AI가 말하기를 평가/심사" 식으로 LLM이 판정한다는 뉘앙스 금지. 다섯 항목(정확도·속도·
   쉼·군말·목소리 안정감).
5. **가장 잘한 기록이 남고 시도 횟수는 센다** — "한 번에 끝"이 아니라 여러 번 도전 가능.
   Retry 있음. 81점은 주황(85 미만)으로 **완벽 점수 자랑 아님** — 그대로 정직하게.
6. **유저는 챌린지를 '만들지' 않는다** — 발행은 admin 플래그(대표 전용). 누구나 **참여는
   무료**지만 "원고 올려서 챌린지 만들어요"를 일반 유저에게 약속 금지.
7. **이름 시트는 첫 참여 때 한 번**(페르소나 이름 프리필), 한 유저 한 이름이 모든 보드에.
   사진은 선택(안 켜면 이니셜). "실명/사진 강제" 아님.
8. **보드 = 상위 10 + 내 줄**, 상위 3명은 메달 태그로 크게. 전체 랭킹 노출 아님.
9. **첫 챌린지는 번들 샘플**("Why practise out loud?", 2026-10-10부터 라이브) — 가입 즉시
   바로 할 게 있다.
10. **화면의 숫자·이름은 전부 kit 샘플 데이터**(81 / 94% / 148 wpm / "41명 도전 중" /
    Camille·Yuna·Minji·Jiwoo). 유저 통계·실적으로 제시 금지.
11. **"첫 20분은 무료예요"** — 게시일에 `freeGrantSeconds`(1200초) 재확인. "무료 체험" 금지
    (체험 없음).

## Success signal

- **Instagram**: reach 대비 saves·shares(순위표는 캡처해 공유되는 소재 — 공유가 핵심 지표),
  프로필 방문·nawana.app 링크 탭(게시 후 72h), 게시물발 팔로우.
- **Threads**: 리플 — 특히 "몇 점 나와요?/어떻게 겨뤄요?" 류 질문(다음 조각의 재료).
- **Community**: 엔트리 조회수; 게시 후 일주일 nawana.app/community·IG 리퍼러로 들어온
  온보딩 시작 수(전주 대비).
- **내부(참고만)**: 게시 후 Speech 챌린지 첫 참여(camera take) 증가 — 소재가 실제 행동으로
  이어졌는지. 공개물엔 어떤 유저 데이터도 쓰지 않음.
