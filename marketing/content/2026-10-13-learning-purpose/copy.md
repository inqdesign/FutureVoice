# copy — 왜 배워요: 목적을 고르면 Talk 탭이 그 이야기로 채워진다

Series: `나와나로 할 수 있는 것` · cat `start` · 6 cards (cover → 4 feature → outro).
On-screen app shots are all `nw-home` (Talk 탭) except 02 (copy-only) and 01/06 (stills).
Topic TITLES on screen stay English (material); chip labels + captions are Korean chrome,
pulled from `Localizable.xcstrings` (listed per card, do not invent).

---

## 01 — Cover (still). Typography over a very faint `nw-home`.
eyebrow: 나와나로 할 수 있는 것 · 01 / 06
title (ko): 왜 배우는지\n한 번만 골라요
desc (ko): 그럼 통화 첫 화면이 **네 이야기**로 채워져요.\n"뭘 말하지?"가 없어요.
title (en): Pick why\nyou're learning
desc (en): Your call screen fills up with **your stuff** from the first tap.\nNo more "what do I even say?"
screen: 앱 화면 없이 타이포 중심. 뒤에 `nw-home`을 아주 옅게 깔아도 됨. 그리드 스틸로 성립해야 함.

## 02 — 왜 배워요? (copy-only, no app screen). 8 reasons as a typography list.
eyebrow: 나와나로 할 수 있는 것 · 02 / 06
title (ko): 처음에 딱 한 번\n물어봐요
desc (ko): 왜 배우는지 골라요. **하나만 골라도, 여러 개 골라도** 돼요.\n나중에 바꿔도 되고요.
title (en): We ask once,\nright at the start
desc (en): Pick why you're learning. **One reason or a few**, your call.\nYou can change it anytime.
screen: 앱 화면 금지. 가짜 온보딩 UI·가짜 칩 금지. 8개 이유를 타이포 리스트로(실제 앱 chrome 문자열 그대로):
  말문을 트고 싶어요 · 취미로 · 시험 준비 · 대학·공부 · 취업·이직 준비 · 일에서 써야 해요 · 해외에서 살아요 · 여행 가요
  (시험 준비 줄에 부제 한 줄 선택: "IELTS · OPIc · 토익 스피킹")
sticker / reaction text: 없음 (지어낸 온보딩 화면 금지)

## 03 — 취준이면 → 면접 질문이 깔려요 (payoff, before/after, 라이브 권장)
eyebrow: 나와나로 할 수 있는 것 · 03 / 06
title (ko): 취준이면\n면접이 깔려요
desc (ko): 통화 첫 화면이 **면접 질문**으로 채워져요.\n탭 한 번이면 면접관과 통화해요.
title (en): Job hunting?\nInterviews, ready
desc (en): Your call screen fills with **interview questions**.\nOne tap, and you're on with the interviewer.
screen: `nw-home`, Talk 탭, 첫 칩 「면접」, 주제 리스트(영어 제목 그대로):
  "Tell me about yourself" · 상대: 면접관 / "Why do you want this job?" / "Strengths and weaknesses" /
  "A project you're proud of" / "Talking about salary" · 상대: 채용 담당자
  모션: 칩 행을 스와이프해 면접→News→Scenarios로 바뀌는 걸 보여준 뒤 `tapRow(0)`.
sticker / reaction text: before/after 비교. 기본 화면(남의 뉴스·일상) ↔ 면접으로 채워진 화면.

## 04 — 시험이면 → 시험 주제가 깔려요 (연습, 채점 아님)
eyebrow: 나와나로 할 수 있는 것 · 04 / 06
title (ko): 시험이면\n시험 주제로
desc (ko): 같은 Talk 탭, 이번엔 **IELTS 주제**예요.\nPart 1·2·3 그대로 말로 연습해요.
title (en): An exam?\nExam topics
desc (en): Same Talk tab, now **IELTS topics**.\nPractise Part 1, 2 and 3 out loud.
screen: `nw-home`, Talk 탭, 첫 칩 「시험」, IELTS 리스트(영어 제목 그대로, 캡션은 chrome):
  "Describe a skill you learned as an adult" · IELTS · Part 2 / "Your hometown" · Part 1 /
  "Should children have smartphones?" · Part 3 / "Describe a time you helped a stranger" · Part 2 /
  "Work or study" · Part 1. 스틸 또는 짧은 스크롤.
sticker / reaction text: 캡션(Part 2…)이 "시험에 맞춰졌다"를 스스로 말함. 점수·채점 문구 절대 금지.

## 05 — 여행·해외살이도 똑같이
eyebrow: 나와나로 할 수 있는 것 · 05 / 06
title (ko): 뭘 고르든\n그 상황으로
desc (ko): 공항·호텔, 집주인·관공서·아이 학교까지.\n고른 대로 **Talk 탭이 바뀌어요.**
title (en): Whatever you pick,\nthat situation
desc (en): Airport and hotels, your landlord, the town hall, your kid's school.\nThe Talk tab shifts to match.
screen: `nw-home`, Talk 탭, 첫 칩 「여행」(또는 「생활」), 리스트(영어 제목 그대로):
  여행: "At the check-in desk" · 상대: 항공사 직원 / "When something goes wrong" · 상대: 프런트 직원 /
  "At a hotel" / "At the train station" / "On the street"
  생활: "Calling your landlord" · 상대: 집주인 / "At the town hall" · 상대: 담당 직원 /
  "Your child's teacher" · 상대: 선생님 / "Calling a clinic"
  아이콘이 03·04와 달라 변화가 또렷해야 함.
sticker / reaction text: 여러 개 고르면 칩도 다 생겨요. 첫 한 주 루틴도 그 목적에 맞춰 짜 줘요.
  (루틴은 화면 금지, 이 한 줄로만.)

## 06 — Outro (still). 표준 아웃트로(Futureself 발화 · 워드마크).
eyebrow: 나와나로 할 수 있는 것 · 06 / 06
title (ko): 유창한 나에게\n언어를 배우세요
desc (ko): 첫 20분은 무료예요.\nnawana.app
title (en): Learn a language\nfrom your fluent self
desc (en): Your first 20 minutes are free.\nnawana.app
screen: 표준 아웃트로 레이아웃(워드마크 · 발화 한 줄 · 무료 라인 · nawana.app).

---

## Instagram caption (ko)

통화 버튼은 눌렀는데, "뭘 말하지?"에서 멈춘 적 있죠.

나와나는 시작할 때 딱 한 번 물어봐요. "왜 배워요?"
취준이면 면접 질문, 시험이면 IELTS 주제, 여행이면 공항·호텔이요. 통화 첫 화면이 바로 그 주제로 채워져요.
화면은 한국어로, 대화는 배우는 언어로. 지금 필요한 그 상황만 골라 말해요.

하나만 골라도 되고, 여러 개 골라도 돼요. 나중에 바꿔도 되고요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #면접영어 #아이엘츠

## Threads text (ko)

영어 왜 배우세요? 면접·시험·여행, 셋 중 뭐예요?

나와나는 시작할 때 그걸 딱 한 번 물어봐요. 그럼 통화 첫 화면이 바로 그 주제로 깔려요. 취준이면 면접 질문, 시험이면 IELTS 주제, 여행이면 공항·호텔이요.

"뭘 말하지?" 하고 멈추는 순간이 없어지는 거죠. 하나만 골라도 되고, 여러 개 골라도 돼요.

뭐부터 연습하고 싶어요?

## Community series entry (`web/community/series.json`)

제안 id: `e20` · cat: `start` · slides: 6 (01·06 JPG, 03–05 가능하면 비디오 슬라이드)
```json
{
  "id": "e20",
  "cat": "start",
  "slides": [
    "/community/series/e20-01.jpg",
    "/community/series/e20-02.jpg",
    "/community/series/e20-03.jpg",
    "/community/series/e20-04.jpg",
    "/community/series/e20-05.jpg",
    "/community/series/e20-06.jpg"
  ],
  "ko": {
    "title": "왜 배워요?",
    "tagline": "한 번 고르면 Talk 탭이 그 주제로 채워져요"
  },
  "en": {
    "title": "Why are you learning?",
    "tagline": "Pick once, and the Talk tab fills with your topics"
  }
}
```

## Notes for the lead

- 시험 카피는 전부 "연습"으로만 썼어요 (04 desc, 캡션, Threads). 점수·채점·"올려줘요" 류 없음. 시험 이름은 실제 옵션(IELTS)만.
- 주제 제목은 전부 영어 그대로(material). 한국어로 보이는 건 제 설명·칩·캡션(chrome)뿐이에요.
- "첫 20분은 무료예요"는 `freeGrantSeconds` 1200초(= 20분, 체험 없음)와 일치. 게시일에 한 번 더 확인하면 끝.
- 루틴은 05 sticker 한 줄로만 언급, 화면 없음.
- series id `e20`은 다음 빈 번호로 잡았어요. 이 조각은 시리즈의 사실상 0번째 단계라, 보드 순서상 e01 앞에 두고 싶으면 배열 위치만 옮기면 돼요(라이브 반영은 대표 승인).
- 03의 before/after는 kit 기본 탭(News/Everyday/Scenarios) ↔ 목적 Talk 탭 대비. 목적 Talk 탭은 새 상태라 칩 라벨은 fidelity 캡처 뒤에 넘기는 게 정석(brief Showability 2). 캡처 없이 임의로 그리지 말 것.