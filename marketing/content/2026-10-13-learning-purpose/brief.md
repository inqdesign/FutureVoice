# Brief — 왜 배워요: 목적을 고르면 Talk 탭이 그 이야기로 채워진다

> Autopilot upload run (1.1.8 build 95 · no founder input). `status.md` fixes the feature and
> the showability constraint; this brief keeps them and fills audience, the card-by-card
> outline, the exact kit call per card, channels, facts to keep true, success.
> Final slide copy is the copywriter's — nothing here is final wording.

## One message

왜 배우는지 한 번만 고르면, Talk 탭이 처음부터 **네 이야기**로 채워져요.
(면접이면 면접 질문, 시험이면 시험 주제, 여행이면 여행 상황 — "뭘 말하지?"가 없어져요.)

If a card can't trace back to this one line, it's the wrong card.

## Who it's for

막 앱을 깔고 목소리를 만든 직후, 통화 버튼 앞에서 **"그래서 뭘 말하지?"** 하고 멈추는 사람.
특히 목적이 또렷한 쪽 — 다음 달 **면접**이 잡힌 취준생, **IELTS·OPIc·토익 스피킹**을 앞둔 수험생,
**해외살이·유학**로 당장 집주인·관공서·아이 학교와 말해야 하는 사람, 곧 **여행** 가는 사람.
이들은 "영어 전반"이 아니라 **지금 필요한 그 상황**만 연습하고 싶은데, 보통 앱은 첫 화면이
남의 뉴스·일상이라 자기 목적을 직접 찾아 들어가야 한다. 나와나는 온보딩에서 이유를 한 번
물어보고, Talk 탭 첫 화면을 그 목적으로 깔아 준다 — 그 틈을 노린다.

Honest floor: 완전 초보가 아니다. 더듬어도 문장을 만들 수 있는 사람. 제로-투-유창 약속 금지(BRAND).

## Why now

- **1.1.8 build 95에 새로 들어간 기능** (`feat/learning-purpose`, merge `b222bcce`). 온보딩에서
  "왜 배워요?"를 묻고, 그 답이 Talk 탭 칩과 첫 루틴을 정한다. 1.1.8 What's New 카드에도 올랐다.
- 이 기능이 답하는 건 말하기 앱의 **가장 흔한 첫 이탈 지점** — "뭘 말해야 할지 몰라서 안 켠다".
  소재 자체가 "시작의 마찰을 없앤다"는 명확한 약속이라 신규 유입에 바로 쓰기 좋다.
- **시리즈 관계:** `나와나로 할 수 있는 것` 피처 시리즈의 **start** 카테고리. e01(한눈에)이
  "통화·교재·복습"을 보여줬다면, 이 조각은 그 통화를 **처음 켤 때 무엇으로 채워지는가** —
  시리즈의 사실상 0번째 단계. e01과 중복 아님(그 쪽은 앱 전체 개요), 이 쪽은 온보딩→Talk
  단 하나의 흐름.

## Proof in the app

출처: `FutureVoice/Services/LearningPurpose.swift`, `PurposeTopicEngine.swift`,
`StarterSituations.swift`, `NewsTopicSection.swift` / `ConversationHome.swift`.

- **보여줄 수 있는 유일한 앱 화면 = Talk 탭** → kit `nw-home` (`web/kit/screens/home.js`,
  `real/home.png`·`real/home-scenarios.png`에서 측정). 헤더(언어 칩·Activity·아바타 링),
  픽셀 인사, "Let's talk" 링, "Tell me more about you" 행, 그리고 **칩 행 + 주제 리스트**.
  디자이너가 `home.lists = { … }`로 리스트를 목적에 맞게 채운다.
- **온보딩 "왜 배워요?" 피커는 캡처가 없다 → 앱 화면으로 그리지 말 것.** 선택지는 **글/타이포로만**
  전달(아래 카드 02). 가짜 온보딩 화면이나 가짜 칩 UI 금지(BRAND Visual).
- 목적별로 Talk 탭이 실제로 보여주는 것(코드 그대로, 리스트는 전부 **실제 앱 콘텐츠**):

  | 목적(picked) | 첫 칩(lead chip) | 주제 리스트(제목 · 캡션) — 전부 `StarterSituations`/`ExamTopics`에서 |
  |---|---|---|
  | 취준(job) | **Interview** | "Tell me about yourself" · 상대: 면접관 / "Why do you want this job?" / "Strengths and weaknesses" / "A project you're proud of" / "Talking about salary" · 상대: 채용 담당자 |
  | 시험(exam, IELTS) | **Exam** | "Describe a skill you learned as an adult" · IELTS · Part 2 / "Your hometown" · Part 1 / "Should children have smartphones?" · Part 3 / "Describe a time you helped a stranger" · Part 2 / "Work or study" · Part 1 |
  | 여행(travel) | **Travel** | "At the check-in desk" · 상대: 항공사 직원 / "When something goes wrong" · 상대: 프런트 직원 / "At a hotel" / "At the train station" / "On the street" |
  | 해외살이(abroad) | **Life** | "Calling your landlord" · 상대: 집주인 / "At the town hall" · 상대: 담당 직원 / "Your child's teacher" · 상대: 선생님 / "Calling a clinic" |
  | 말문 트기(start) | **Everyday** | kit 기본 everyday 리스트 그대로(카페·식당·길·이웃…) |
  | 재미(hobby) | **News** | kit 기본 news 리스트 그대로 |

  칩 순서는 항상 `[고른 목적들의 칩] → News → Scenarios` (`LearningPurpose.chips(level:)`).
  주제 **제목은 MATERIAL이라 영어가 맞다**(배우는 언어); 칩 라벨·캡션(상대:…, Part 2)은
  chrome라 **한국어** — 정확한 ko 문자열은 `Localizable.xcstrings`에서 그대로 뽑을 것(지어내지 말 것).

## Showability resolution (디자이너가 먼저 읽을 것)

1. **피커는 copy-only.** 8개 이유는 타이포 리스트로. 폰 프레임 안에 넣지 말고, 가짜 칩으로도
   만들지 말 것. (색/글리프를 꼭 쓰고 싶으면 `LearningPurpose.tint`/`.symbol`이 실제 값이지만,
   앱 UI처럼 보이면 반려 — 기본은 글자.)
2. **목적 Talk 탭은 "새 앱 상태"다.** kit 기본 탭은 News/Everyday/Scenarios(측정값)지만, 목적을
   고른 실제 앱은 첫 칩이 Interview/Exam/Travel/Life로 바뀐다. 이걸 충실히 그리려면 **(a)** 시뮬레이터에서
   해당 목적으로 온보딩을 끝낸 Talk 탭을 캡처해 fidelity 확인(`marketing/FIDELITY.md`) 후, home.js에
   칩 라벨을 넘길 작은 수단(예: `home.chips=[…]`)을 더하는 게 정석. **(b)** 이번 헤드리스 런에서
   캡처를 못 만들면: 측정된 탭 구조를 유지하되 **첫 탭의 리스트를 목적 주제로 채우고**, 칩이
   바뀐다는 사실은 카피로 전달(약함, 차선). 어느 쪽이든 **리스트 콘텐츠는 위 표 그대로** — 실제 앱 문구.
3. 일부 주제 행 아이콘(questionmark.bubble, chart.bar, banknote, key.fill, building.columns 등)은
   kit에 없다 → 그 행만 kit에 SF 글리프를 트레이스해 추가(소규모 kit 변경·fidelity). 없으면
   kit에 있는 아이콘(person·briefcase·cross·house·bag·tram 등)으로 가장 가까운 걸로.

## Outline — 6 cards (cover → 4 feature → outro)

> 커버/아웃트로 = PNG 스틸. 기능 카드 = `carousel.html?solo=N` → `record.mjs` 8–12초 MP4 또는 스틸.
> 모든 기능 카드의 앱 화면은 `nw-home`(Talk 탭) 하나.

| # | Card | The one point | Screen / kit call | Sticker·compare |
|---|---|---|---|---|
| 01 | **Cover (still)** | 왜 배우는지 한 번만 고르면, Talk 탭이 네 이야기로 채워져요 | 앱 화면 없이 타이포 중심. 뒤에 `nw-home`을 아주 옅게 깔아도 됨(그리드 스틸로 성립해야). | — |
| 02 | **왜 배워요? (copy-only)** | 처음에 딱 한 번 물어봐요 — 하나만 골라도, 여러 개 골라도 돼요 | **앱 화면 금지.** 8개 이유를 타이포 리스트로: 말문 트기 · 재미 · 시험 · 전공 · 취준 · 회사 · 해외살이 · 여행 (ko chrome 문자열은 카탈로그에서). 부제(예: "시험 — IELTS·OPIc·토익 스피킹")는 선택 | 지어낸 온보딩 UI 금지 |
| 03 | **취준이면 → 면접 질문이 깔려요** (payoff, 라이브 권장) | Talk 첫 화면이 바로 면접 — 탭 한 번이면 면접관과 통화 | `nw-home`, 첫 칩 **Interview** + 위 표 면접 리스트. 모션: 칩 행을 스와이프해 Interview→News→Scenarios로 바뀌는 걸 보여주기(= `home.tab` 애니), 그 뒤 `tapRow(0)` | **before/after 비교**가 강함: 기본(남의 뉴스/일상) ↔ 면접으로 채워진 화면 |
| 04 | **시험이면 → 시험 주제가 깔려요** | 같은 Talk 탭, 이번엔 IELTS 주제 — Part 2·Part 1·Part 3 그대로 | `nw-home`, 첫 칩 **Exam** + IELTS 리스트(캡션 "IELTS · Part 2" 등이 시각적으로 03과 달라 반복감 없음). 스틸 또는 짧은 스크롤 | 캡션(Part 2…)이 "시험에 맞춰졌다"를 스스로 말함 |
| 05 | **여행·해외살이도 똑같이** | 뭘 고르든 그 상황으로 — 공항·호텔, 집주인·관공서·아이 학교 | `nw-home`, 첫 칩 **Travel**(또는 Life) + 해당 리스트. 아이콘이 03·04와 달라 변화가 또렷 | "여러 개 고르면 칩이 다 생겨요"를 캡션으로(루틴 언급은 가볍게, 화면 금지 — Risk 7) |
| 06 | **Outro (still)** | 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 · nawana.app | 표준 아웃트로(Futureself 발화 · 워드마크) | — |

메모: payoff를 03에서 before/after로 한 번 세게 보여주고, 04·05는 "다른 목적도 똑같다"의 반복
증거 — 세 카드가 전부 같은 Talk 탭인데 콘텐츠·칩·캡션·아이콘이 달라 단조롭지 않게. 루틴("첫 한 주도
목적에 맞춰 짜 줘요")은 **화면이 없으니** 05 캡션 한 줄로만, 절대 루틴 화면을 그리지 말 것.

## Channels (standard)

- **Instagram carousel** (main): 6 items, 1080×1350. 01·06 PNG, 03–05 MP4/스틸, 02 PNG(타이포).
  캡션 훅 = "뭘 말하지? 가 없어진다" 류 한 줄, 그 뒤 카드별 한 줄, 끝에 "하나만 골라도 되고,
  나중에 바꿔도 돼요". 해시태그 3–5 (#영어회화 #영어공부 #스피킹 #면접영어 …).
- **Threads**: 같은 앞 5–6장, 더 짧고 대화체(IG 캡션 복붙 금지). "영어 왜 배우세요? 셋 중 뭐예요 —
  면접·시험·여행?" 처럼 리플 유도.
- **Community series**: 같은 날 엔트리, `cat: start`, `web/community/series.json`에 추가(720×900 JPG,
  가능하면 비디오 슬라이드). e01과 별개 에피소드. 라이브 사이트 반영 = 대표 승인.
- 그 외 없음(Reel/Story 미설정).

## Facts that must stay true (check before copy & before packaging)

1. **피커는 앱 화면으로 그리지 않는다** — 캡처 없음. 글/타이포만. 가짜 UI = 반려(BRAND).
2. **목적 Talk 탭 = 새 상태 → fidelity 캡처 필요** (Showability resolution 2). 캡처 없이 칩 라벨을
   임의로 그리면 fidelity 위반 소지 — 차선(리스트만 교체 + 카피)로 내려갈 것.
3. **화면의 모든 이름·숫자·아바타는 kit 샘플 데이터.** 대표 본인 이름("Eunggyu") 등 실명 금지(BRAND).
   렌더 전 kit 샘플명/이니셜인지 확인.
4. **주제 제목은 영어가 맞다**(MATERIAL=배우는 언어). 한국어로 번역해 보여주지 말 것. 칩·캡션만 한국어.
5. **시험 칩은 "연습"이지 "채점"이 아니다.** 코드상 미래의 나가 시험 질문을 그 형식으로 물어보고
   말을 끌어낼 뿐, **절대 점수를 매기지 않는다**("Never score them"). "IELTS 점수 올려줘요/평가해줘요"
   금지. "시험에 나오는 주제를 그 형식으로 말로 연습" 정도로.
6. **시험 이름은 실제 옵션만**: 영어 IELTS·TOEFL·OPIc·토익 스피킹 / 독일어 Goethe·telc·OPIc /
   한국어 TOPIK·OPIc / 일본어 OPIc·BJT. 없는 시험 지어내지 말 것. 시험 날짜·목표 점수는 묻지 않는다(기능 아님).
7. **목적은 Talk 칩 + 첫 루틴 두 가지만 바꾼다**(그 외 아무것도). 루틴은 화면 없음 → 카피로만, 가볍게.
   별도 섹션·목표 점수·밴드 채점 같은 건 이 기능이 아니다(`learning-goal-feature-on-hold` 메모).
8. **하나 이상 선택 가능 + 나중에 수정 가능**(Discover 설정 시트). "딱 하나만/한 번 정하면 끝" 금지.
9. **"첫 20분은 무료예요"** — 게시일에 `freeGrantSeconds`(1200초) 재확인. "무료 체험" 금지(체험 없음).
10. 숫자/통계로 제시 금지 — 화면 수치는 전부 샘플.

## Success signal

- **Instagram**: reach 대비 saves·프로필 방문·nawana.app 링크 탭(게시 후 72h), 게시물발 팔로우.
  이 조각은 "시작 마찰 제거"라 **신규 설치→온보딩 시작**이 핵심(커뮤니티/IG 리퍼러로 들어온 온보딩 시작 수, 전주 대비).
- **Threads**: 리플 — "면접만 연습돼요?" "시험 주제 뭐 나와요?" 류 질문(다음 조각 재료).
- **Community**: 엔트리 조회수.
- **내부(참고만)**: 게시 후 온보딩에서 목적을 고르고 **첫 통화까지 간 비율**이 소재의 약속과 맞는지.
  공개물엔 어떤 유저 데이터도 쓰지 않음.
