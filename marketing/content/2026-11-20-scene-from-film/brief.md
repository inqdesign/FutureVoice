# Brief — 좋아하는 장면을 같이 연기해요 (영화·드라마 장면 연습)

- **piece:** IG/Threads carousel, 5 cards, 1080×1350
- **version:** 1.3.8 (151), shipped · commit 03ab3204 · release note under 개선/Improved
- **series:** 나와나로 할 수 있는 것 (cat: watch) — this **extends** e08 "나만의 상황", it does not repeat it

## One message

좋아하는 영화·드라마 장면을, 유창한 내가 상대역이 되어 그 장면 안에서 같이 연기해요.

(If it takes two sentences to say, it's two pieces. This is one: the composer box already does "나만의 상황"; the news is that "상황" can now be *a scene from a story you love*.)

## Who it's for

좋아하는 영화 한 장면, 드라마 한 대사가 머리에 박혀 있는 사람 — 그리고 Watch에서 카페·면접 같은 "진짜 내 상황"만 연습하다 조금 지루해진 사람. 구체적인 순간: 시리즈를 막 정주행하고, "저 장면 영어로 저렇게 말해보고 싶다" 싶은 밤. 정직한 하한선은 지킴 — 완전 초보가 아니라, 문장을 더듬더듬 만드는 사람.

## Why now

- 1.3.8에 **딱 이 동작**이 들어감: Watch 컴포저 박스("나만의 상황")에 영화·드라마·연극·책 장면을 연기하고 싶다고 쓰면, 이제 그 장면 안에서 대본이 써짐 — 상대는 그 캐릭터를, 나는 맞은편 인물을, 그 이야기 결의 대사로, 리허설/메타 말("대본 좀 볼게") 없이. 전에는 같은 요청이 "두 배우가 리허설 잡는" 장면으로 나왔는데(상황 프롬프트가 늘 학습자의 실제 삶이라고 가정했기 때문), 이제 연기 장면 하나만 예외.
- Watch 시리즈(e07 미리 보기 · e08 나만의 상황 · e09 사람과 연습)가 돌아가는 중. 이건 e08의 즐거운 확장편 — 기능 소개가 아니라 "오, 저렇게도 쓰네" 한 편.

## Proof in the app (real behaviour only)

- **Watch 탭 / 컴포저 박스** — `Mode.custom`("나만의 상황"), `SpeakOrTypeField`. 여기에 장면 요청을 씀. (`CLAUDE.md`: "Watch · 나만의 상황 박스", "Material on a situation, and the two doors into Watch")
- **장면 재생** — `DialogueLine` 행들: 상대(캐릭터) · 장소 · 제목 · 블러브. 미래의 나가 맞은편 인물을 연기. (`ScenarioCurriculumEngine` → `SceneWatchView`)
- **공부로 남음** — 장면 대사에 "Shadow this" / "Save phrase", 한 권의 교재로. (Review 책 흐름)
- **kit 화면:** `nw-watch`(people map, `Mode.custom` 컴포저 박스, `DialogueLine` 장면 재생). **디자인은 이 세 상태만 씀 — 없는 화면 요청 금지.**

## Outline (cover → 3 cards → outro)

1. **커버** — 훅: "좋아하는 그 장면, 영어로 직접 연기해봐요." 화면: `nw-watch` — people map 또는 컴포저 박스. 스틸로 그리드에서 읽혀야 함.
2. **컴포저 박스에 쓰기** — 박스에 장면 요청 한 줄이 들어가 있는 상태(가상의 중립적 장면: 예 "작은 카페에서 오래된 친구를 다시 만나는 장면"). 화면: `nw-watch` `Mode.custom`, `SpeakOrTypeField`. 카드가 말하는 것: 상황 자리에 *이야기 속 장면*을 쓴다. 화면이 하는 것: 박스에 텍스트가 채워짐.
3. **장면이 재생됨** — `DialogueLine` 행들, 상대가 캐릭터를 연기, 나는 맞은편. 카드가 말하는 것: 리허설이 아니라 장면 *안*이다 — 그 이야기 결의 대사. 화면: `nw-watch` 장면 재생. (스티커 도움 지점: `DialogueLine` 한 줄을 폰 옆에 빼서 보여주면 "이게 그 장면의 대사" 가 바로 읽힘.)
4. **공부로 남아요** — 그 대사에 Shadow this / Save phrase → 한 권의 교재. 카드가 말하는 것: 연기하고 끝이 아니라, 그 장면의 표현이 내 교재가 된다. 화면: `nw-watch` 장면 재생 + 작은 UI 스티커(표현/라인).
5. **아웃트로** — 템플릿 아웃트로: 워드마크 · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" · nawana.app.

*비교(전/후) 슬라이드는 넣지 않음:* 처음 보는 사람은 "전"을 본 적이 없어서 "두 배우가 리허설 잡던 걸 고쳤다"는 안 읽힘. 개선 서사는 브리프에만 두고, 카드는 지금 되는 것만 보여줌.

## Channels

IG carousel + Threads(앞 5장, 짧은 대화체 텍스트) + 커뮤니티 시리즈(watch cat, e08 확장으로 같은 날). 기본값대로. 추가 채널 없음.

## Risks (check before ship)

- **실제 영화를 특정하지 말 것.** 특정 작품명·실제 대사를 화면/카피에 넣지 않음 — 저작권/상표 문제이고, 앱은 어떤 작품도 그대로 재현하지 않음. 카피는 "좋아하는 장면" 같은 일반 표현, 화면 예시는 중립적인 가상의 장면으로.
- **대사는 생성된 것 — 영화의 원문 인용이 아님.** "그 영화의 대사를 외운다"로 읽히면 거짓. 그 *장면*을, 내 레벨의 말로 다시 쓴 것. 과장 금지("어떤 영화든 완벽 재현").
- **지원 언어 안에서만.** 학습 재료(대사)는 목표 언어(기본 영어). "한국어로 연기"가 아님.
- **Watch 장면 비용.** 영화 장면도 평범한 Watch 장면 — 구독자는 통화 5분, 무료 계정은 무료 시간에서 5분 차감(`CLAUDE.md` "A Watch scene costs FIVE talk minutes"). 카피가 "무제한/무료로 영화 장면"으로 읽히지 않게. 아웃트로의 "첫 20분 무료"는 그대로 사실.
- **없는 화면 금지.** `nw-watch` 세 상태만. 새 화면 그리지 말 것.
- **BRAND:** 픽셀폰트 금지, 한국어는 해요체, "당신" 금지, AI 튜터·원어민 깎아내리기 금지.

## Success signal

저장(save) — "재밌다, 저장" 결의 콘텐츠라 saves가 1차 지표 · 프로필 방문 · 커뮤니티 watch 편 조회. 앱 쪽에선 Watch `Mode.custom` 작성·장면 재생 추세(PostHog)로 뒷받침 가능하면 참고.
