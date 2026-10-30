# brief — routine-your-way

**Piece:** IG/Threads carousel + community series entry · 1.2.1 (112) release
**Series:** 나와나로 할 수 있는 것 (feature series) · 루틴 편
**Stage:** brief → copy. Autopilot, no founder gate.

## The one message

> **루틴은 내가 만든다.** 셋업에서 연습할 수 있는 걸 카드로 하나씩 보여주고, 원하는 것만
> 담으면 그게 내 하루 루틴이 돼요. (EN: You build your own routine — in setup nawana
> shows you what you can practice, one card at a time, and you keep only the ones you want.)

Everything on every slide serves that one sentence. If a card doesn't push "내가 고른다 →
내 루틴이 된다", it's the wrong card.

## Who it's for, and the moment

전에 영어 앱을 한두 번 깔았다가 "매일 이거 하세요"라고 정해주는 플랜과 스트릭 압박에
질려서 지운 직장인. 지금 나와나에서 목소리를 막 만들고 난 참이고, 다음에 "매일 뭘 할지"를
처음으로 **스스로 고르는** 화면 앞에 서 있는 사람.

- Honest floor (BRAND): 완전 초보 아님 — 문장을 더듬거리며 만들 수 있는 사람부터.
- Never grade them (BRAND): "초보용/상급용" 금지. 루틴은 각자가 짜는 것이지, 등급이 아님.

## Why now

1.2.1 (112) 릴리스. 온보딩이 이제 루틴을 **카드 하나씩** 짜게 만들어요
(`RoutineOnboardingView`, 2026-10-18, 카드 UI 2026-10-20), 그리고 **섀도잉과 듣기가 각각
자기 자리를 가진 블록**이 됐어요 (2026-10-20). 둘 다 이번 빌드의 새 소식이라 릴리스에
딱 맞는 피스.

## Proof in the app (real behaviour only)

- **Onboarding builds the routine** (CLAUDE.md "Onboarding builds the routine", 2026-10-18 /
  2026-10-20): 마지막 온보딩 단계에서 Talk 탭 위로 카드가 한 장씩 떠요 — 통화(전화) ·
  다시 말하기 · 복습 · 섀도잉 · 듣기 · 스피치. 카드마다 한 줄 설명 + **"내 루틴에 추가"**
  또는 **"관심 없어요"**. 전화 카드는 알림 권한을, 나머지는 알림 권한을 물어요. 전부
  넘기면 "나중에 만들어도 돼요"로 끝나고 아무것도 울리지 않아요. 담은 건 My routine 그리드에
  자리를 잡고 (spotlight), Done을 누르면 Talk 헤더의 Activity 칩으로 접혀요.
- **The routine IS the promise** (CLAUDE.md "The routine IS the promise, from onboarding"):
  내가 담은 루틴이 곧 내가 나에게 한 약속이고, 스트릭은 그 약속을 지킨 날을 세요. 아무것도
  안 담으면 약속도 없음 — 압박이 아니라 선택.
- **Shadowing & listening are blocks** (CLAUDE.md "Shadowing and listening are blocks",
  2026-10-20): 섀도잉이 다시 독립 블록. 듣기는 플레이어(나와나 팟캐스트 + 내가 Watch한
  상황) — 한 편이라도 들으면 그 블록 완료, 양을 세지 않아요.
- **Kit screen — `routine.js` (My routine)**: 요일 스트립(지킨 날 초록, 오늘 진행, 쉬는 날,
  예정 점선), 약속 스트릭("오늘 지키면 1일째" / "N일째 지키는 중", 지킨 날은 불꽃),
  블록 목록(통화 10분 · 다시 말하기 · 주간 테스트 · 복습 20개 · 섀도잉 5문장), 공유 카드 풋터.

## Load-bearing honesty note (do not break)

- **온보딩 카드 빌더 화면은 키트에 없고 캡처도 없어요 → 그리면 안 돼요.** 앱 화면 슬라이드는
  전부 **`routine.js`(나의 루틴 페이지)만** 사용. 우리는 빌더가 아니라 **결과(루틴 페이지)**
  를 보여주고, "카드 하나씩 고른다"는 아이디어는 **카피로** 전달해요.
- **듣기 블록은 `routine.js`에 안 그려져요** (키트 KIND에 talk/again/test/review/shadow만
  있음). 듣기는 **말로만** 언급, 화면에서 듣기 블록을 가리키지 말 것. 스피치 블록 타일도
  이 화면엔 없음 — 마찬가지로 말로만.
- 블록으로 쓸 수 있는 실제 키트 스티커 타일: 통화(파랑) · 다시 말하기(민트) · 복습(초록) ·
  섀도잉(노랑) · 주간 테스트(주황). 이 다섯 외의 타일(듣기 시안 · 스피치 보라)은 **만들지 말 것.**
- 화면의 숫자(통화 10분, 복습 20개, 섀도잉 5문장, N일째)는 키트 샘플값 — 유저 통계처럼
  쓰지 말 것 (BRAND).
- 약속 스트릭의 불꽃은 **루틴 페이지의 것**(정당함). 주간 테스트 화면엔 불꽃/게이지 없음 —
  둘을 섞지 말 것.
- No paywall anywhere. 아웃트로의 "첫 20분은 무료예요"는 BRAND 표준 문구라 허용.

## Outline (6 cards · 4:5 1080×1350 · 고정 텍스트 블록 상단 + 라이브 화면 하단)

1. **COVER — "루틴은 내가 만든다"**
   - Text: eyebrow `나와나로 할 수 있는 것 · 루틴` + `1/6`; pixel 타이틀 `루틴은 내가 만든다`;
     2줄 설명 = 정해주는 플랜이 아니라 내가 짠 하루.
   - Screen: `nw-routine` pose **`day-plan`** (정적) — 블록이 깔린 나의 루틴 페이지. 피드
     썸네일로도 서는 스틸. 그 자체가 "destination = 내 약속"을 먼저 보여줌.

2. **"셋업에서 하나씩 보여줘요"** — the headline (card-by-card)
   - Text: 온보딩 마지막, 연습할 수 있는 걸 **카드 한 장씩** 보여줘요 — 통화 · 다시 말하기 ·
     복습 · 섀도잉 · 듣기 · 스피치. (여섯 개를 카피로 나열 — 화면엔 안 그림.)
   - Screen: `nw-routine` `day-plan`, **모션 = 블록 행이 한 줄씩 순서대로 등장**(카드가 한 장씩
     "담기는" 느낌). 여기 깔리는 각 행이 곧 내가 "추가"한 카드라는 걸 모션으로 말함.

3. **"담을 것만 담고, 나머진 넘겨요"** — pick / pass, no nag
   - Text: 원하는 것만 추가, 나머진 "관심 없어요"로 넘겨요. 하나도 안 담아도 괜찮아요 —
     나중에 만들어도 돼요. (차별점: 강요하지 않는 루틴.)
   - Screen: `nw-routine` `day-plan`. **STICKER 도움**: 실제 키트 블록 타일(통화·다시 말하기·
     복습·섀도잉·주간 테스트) 몇 개를 화면 둘레에 띄워 "추가 ✓ / 넘김" 제스처로 — 고르는
     행위를 시각화. (듣기·스피치 타일은 만들지 말 것.)

4. **"섀도잉도, 듣기도 각자 자리예요"** — the 1.2.1 detail
   - Text: 섀도잉은 다시 독립 블록. 듣기는 플레이어 — 나와나 팟캐스트나 내가 Watch한 상황을
     한 편 들으면 끝. (듣기는 화면이 아니라 카피로만.)
   - Screen: `nw-routine` `day-plan`, **섀도잉 행(노랑 wave)을 강조**(살짝 펄스). 듣기는 안 그림.

5. **"지키면, 내가 나에게 한 약속"** — the payoff (promise / streak)
   - Text: 내가 담은 루틴이 곧 내 약속이고, 지킨 날이 쌓여요. 압박이 아니라 내가 고른 것.
   - Screen: `nw-routine` pose **`day-kept`**, **모션 = 링이 차고 불꽃이 켜지며 "N일째
     지키는 중"**. (약속을 지킨 하루.)

6. **OUTRO** — BRAND 표준: wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" ·
   nawana.app. (라이브 화면 없음 또는 작은 나의 루틴 미니.)

## Channels

- **Instagram (main):** 6-card carousel. cover/outro = PNG, 본문 2·5(모션)·3(스티커)·4 =
  MP4 8–12s 루프. 캡션: 첫 줄 훅(= 카드 1 타이틀 톤, "매일 뭘 할지 앱이 정해주는 게 아니라
  내가 고른다"), 2–3문장, 끝에 해시태그 3–5개 (#영어회화 #영어공부 #스피킹 + EN 1–2).
- **Threads:** cover + 카드 2,4,5 (4장)로 줄여서, 대화체 짧은 텍스트(IG 캡션 복붙 금지).
  훅: "루틴을 앱이 정해주는 게 싫어서 지웠다면 — 이번엔 네가 짜."
- **Community series (default):** `web/community/series.json`에 새 엔트리(루틴 편).
  cat 제안 = `start` (셋업에서 일어나는 일) — publisher가 lead와 확정. 슬라이드 720×900,
  ko/en title+tagline. 같은 날 IG와 미러.
- 게시·배포는 autopilot 스케줄러(리뷰 PASS 후 veto 창)가 처리 — 이 브리프는 게시 승인이 아님.

## Risks / things to check before PASS

- 빌더 화면을 그리지 않았는지 (= `routine.js`만 썼는지). 듣기/스피치 블록을 화면에서
  가리키지 않았는지.
- 숫자(10분/20개/5문장/N일째)를 샘플이라 표기/톤 처리했는지, 유저 통계로 안 읽히는지.
- 페이월·"무제한"·체험 문구 없음. "첫 20분은 무료예요"만 아웃트로.
- 한국어는 번역이 아니라 네이티브로 쓰기(해요체, "당신" 금지). EN은 별도로 네이티브.
- 완전 초보 약속("누구나 유창") 금지.

## Success signal (afterwards)

- 저장(saves): "앱이 정해주는 루틴이 싫다"는 공감형 메시지라 저장 유도형 — 1차 지표.
- 프로필 방문 → 설치, 커뮤니티 루틴 엔트리 조회수.
- 참고(마케팅 밖): 이 릴리스로 신규 설치의 온보딩에서 루틴 블록을 실제로 담는지
  (`RoutineOnboardingView`) — 팀이 직접 측정하진 않지만 메시지가 맞았는지의 근거.
