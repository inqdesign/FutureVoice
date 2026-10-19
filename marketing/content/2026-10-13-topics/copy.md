# 내 얘기로 통화해요 · copy (series 04, 7 cards)

Written 2026-10-13 from `brief.md`. Same story: the learner preparing for the interview. Korean
written as Korean, English written as English. 해요체, no 당신, no em dash anywhere in this file.
Card 06 (Talk settings, added 2026-10-14) now shows the "왜 배워요?" rows: the lead asked for it.
`learning-purpose` covers WHY the purposes exist; this card only shows where they are set.

Eyebrow on every card: `nawana · NN / 07`.

**Korean clarity pass + new card 06 (2026-10-14).** "칩" is gone from every Korean line on cards
02 to 05 (no chip label says 칩 on those screens); card 06's own screen footer uses it, the card copy
still doesn't. Re-render: **01** (title, desc line 2, all chips, eyebrow, new chip 06; en: new chip
06 + eyebrow), **02** (desc, eyebrow), **03** (title, desc, eyebrow), **04** (title, desc, eyebrow),
**05** (title, desc, eyebrow), **06 NEW** (ko + en), **07** outro (was 06; eyebrow only if the layout
shows one). English lines on 02 to 05 are unchanged apart from the eyebrow.

**English clarity pass (2026-10-14).** English only; Korean untouched. The en cover title now
matches the Korean meaning ("someone else's topics"), and "chip" is gone from every English card
line too. Re-render ONLY these en cards: **01** (title, desc, chips 02, 03, 04, 05), **02** (desc),
**03** (title, desc), **04** (title, desc), **05** (title, desc), **06** (desc). 07 unchanged. IG
caption (en) rewritten; Threads (en) added as a reply in the English thread. All silent.

## For the designer

- **Card count 7** (ring card cut 2026-10-14, Talk settings card added the same day).
  `nawana · 01 / 07` … `06 / 07`, then the outro.
- **Chips on the home (chrome):** 면접 · 뉴스 · 상황 / Interview · News · Scenarios (kit gap 1).
- **Card 03 sample role:** "backend developer". Field topic titles are MATERIAL (English on both
  versions) and must be the app's real output for that role (brief Risk 2). Do not use the
  brief's two example titles unless the app writes them.
- **Card 04 sample interest:** neutral ("the job market" or "technology"), no real company or
  person; news rows to match (kit gap 5).
- **Card 05:** scenario row "Job interview · panel round · with Interviewer"; the call header
  names the interviewer, preset voice (not the clone); chips e.g. took the initiative · walk you
  through · prioritize.
- **Card 06 (NEW), `<nw-discover sheet over="prev">` over `<nw-home>`:** `openFrom(home)` (Talk's
  sliders button) → `togglePurpose("job")` (badge 1, the role field opens) → `togglePurpose("travel")`
  (badge 2) → `typeRole("backend developer")` → `addInterest("the job market")` (the page scrolls to
  Interests, the chip lands, 2 / 6) → `save()` → sheet goes down → the home's chips now lead with
  the two purposes in that order, then 뉴스 · 상황 (`LearningPurposeStore.chips`: picked purposes'
  chips first, in the order tapped, then News, then Scenarios). Poster = the sheet with 1 and 2 on
  the rows and the role filled. Labels are the page's own: 대화 설정 · 왜 배워요? · 관심사 · 저장
  (en: Talk settings · Why are you learning? · Interests · Save).
- If `DiscoverSettingsSheet` can't be built from a capture (kit gap 2), cards 03 and 04 start on
  the list already filled; the copy still holds ("적어 두면").

---

## 01 · Cover: problem, then the answer
eyebrow (ko): nawana · 01 / 07
title (ko): 남이 정한 주제론\n할 말이 없어요
desc (ko):  **내 얘기로 통화해요.**\n내 면접, 관심 있는 뉴스, 내가 겪을 상황으로 말해요.
chips (ko):
  02 대화 탭엔 내 주제부터
  03 내 직무 면접 질문
  04 관심 있는 뉴스
  05 만들어 둔 내 상황
  06 대화 설정에서 정해요
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): nawana · 01 / 07
title (en): Someone else's topics?\nNothing to say.
desc (en):  **Talk about your own life.**\nYour interview, news you care about, situations you'll face.
chips (en):
  02 Your topics, first on Talk
  03 Questions for your job
  04 News you care about
  05 Situations you saved
  06 Set it in Talk settings
footer (en): Swipe → · nawana.app

screen: no phone. `nw-futureself` (speaking) in its circle + chip list
alt (ko): ‘남이 정한 주제론 할 말이 없어요’ 제목 아래 ‘내 얘기로 통화해요’가 있고, 미래의 나 모자이크가 말하는 동안 02~06장 목차가 하나씩 나타나는 표지예요.
alt (en): Cover: "Someone else's topics? Nothing to say." over "Talk about your own life." The fluent-self mosaic speaks while the contents for cards 02 to 06 appear one by one.

## 02 · Talk opens on my topics
eyebrow (ko): nawana · 02 / 07
title (ko): 대화 탭을 열면\n내 주제부터
desc (ko):  면접, 뉴스, 상황처럼 **내가 고른 주제**가 순서대로 있어요. 주제 하나를 누르면 바로 통화가 시작돼요.

eyebrow (en): nawana · 02 / 07
title (en): Open Talk,\nyour topics first
desc (en):  **The topics you picked** line up in order: interviews, news, situations. Tap one and the call starts.

screen: `nw-home`, chips 면접 · 뉴스 · 상황, slow scroll from the ring to the list, chips switch once
alt (ko): 대화 탭에서 링 아래로 내려가면 면접, 뉴스, 상황 칩과 그 아래 주제 목록이 보이고, 칩을 바꾸자 목록이 바뀌어요.
alt (en): Scrolling down the Talk tab past the ring shows Interview, News and Scenarios chips with a list of topics; switching chips changes the list.

## 03 · Write the role once, get its questions
eyebrow (ko): nawana · 03 / 07
title (ko): 직무를 적으면\n면접 질문이 나와요
desc (ko):  지원하는 직무를 한 번 적어 두면 면접 목록이 **그 직무에서 나올 질문**으로 채워져요. 새로고침하면 더 나와요.

eyebrow (en): nawana · 03 / 07
title (en): Name the job,\nget its questions
desc (en):  Add the job you're applying for once, and the interview list fills with **its questions**. Refresh for more.

screen: Talk settings, role field "backend developer" → 저장 → "직무에 맞는 주제를 쓰고 있어요…" loading row → eight field topics land
alt (ko): 대화 설정에서 지원 직무에 ‘backend developer’를 적고 저장하면, 면접 칩에 그 직무의 면접 주제 여덟 개가 영어로 채워져요.
alt (en): In Talk settings the role "backend developer" is entered and saved; the Interview chip then fills with eight interview topics for that role.

## 04 · What I follow, in this week's news
eyebrow (ko): nawana · 04 / 07
title (ko): 관심사를 적으면\n그 뉴스로 통화해요
desc (ko):  적어 둔 관심사마다 **최근 기사**가 뉴스에 올라와요. 기사를 누르면 유창한 내가 그 얘기부터 꺼내요.

eyebrow (en): nawana · 04 / 07
title (en): Add an interest,\ntalk about its news
desc (en):  Each interest brings **recent stories** into News. Tap one and the fluent you starts the call on it.

screen: interests field gets the sample interest → News list refreshes (icon spins) → tap a "Did you see …?" row → `nw-call`, fluent self's opener
alt (ko): 관심사를 적자 뉴스 목록이 새로 바뀌고, 기사 하나를 누르면 통화가 열려 유창한 내가 그 얘기부터 꺼내요.
alt (en): After an interest is added the News list refreshes; tapping a story opens a call where the fluent self brings it up first.

## 05 · My saved situation, as often as I like
eyebrow (ko): nawana · 05 / 07
title (ko): 만들어 둔 상황,\n몇 번이고 다시
desc (ko):  저장한 면접 상황을 누르면 **면접관과 통화가 시작돼요**. 화면 위에는 그 상황에서 익히던 표현이 떠요.

eyebrow (en): nawana · 05 / 07
title (en): Your saved situation,\nas often as you like
desc (en):  Tap the interview you saved and **you're on a call with the interviewer**, with its phrases up top.

screen: 상황 chip → "Job interview · panel round" (상대: Interviewer) tapped → `nw-call` with the interviewer's opener and the scenario chips
alt (ko): 상황 칩에서 저장해 둔 면접 상황을 누르면 면접관과 통화가 열리고, 화면 위에 그 상황에서 익히던 표현들이 떠요.
alt (en): From the Scenarios chip, the saved interview is tapped; a call with the interviewer opens, with that situation's phrases as chips at the top.

## 06 · Talk settings: why I'm learning sets the topics (NEW)
eyebrow (ko): nawana · 06 / 07
title (ko): 왜 배우는지 고르면\n주제가 달라져요
desc (ko):  이유를 **세 개까지** 고르면 그 순서대로 대화 탭에 주제가 놓여요. 직무와 관심사도 여기 적고 저장해요.

eyebrow (en): nawana · 06 / 07
title (en): Why you're learning\nsets your topics
desc (en):  Pick **up to three** reasons and their topics come first, in that order. Add your job and interests here too.

screen: `<nw-discover sheet>` over `nw-home` (see designer notes): job (1) → travel (2) → role "backend developer" → interest "the job market" → 저장 → home chips follow
alt (ko): 대화 탭의 설정을 열어 ‘왜 배워요?’에서 취업·이직 준비와 여행을 차례로 고르고, 지원 직무와 관심사를 적은 뒤 저장하면 대화 탭의 주제가 고른 순서대로 바뀌어요.
alt (en): Talk settings opens; under "Why are you learning?" a job hunt and travel are picked in turn, a role and an interest are added, and after Save the Talk tab's topics follow that order.

## 07 · Outro (unchanged from piece 01)
eyebrow: none (07 / 07 if the layout shows one)
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app
tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app
screen: `nw-futureself` (speaking), no phone
alt (ko): nawana 워드마크 아래 ‘유창한 나에게 언어를 배우세요.’와 ‘첫 20분은 무료예요’, nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

남이 정한 주제로는 할 말이 없어요. 내 얘기가 아니니까요.
그래서 내 얘기로 통화해요.

대화 탭을 열면 내가 고른 주제가 먼저 보여요.
지원하는 직무를 적어 두면 그 직무 면접에서 나올 질문으로 통화해요.
관심사를 적어 두면 그와 관련된 최근 기사로 통화해요.
만들어 둔 상황은 몇 번이고 다시 눌러 그 상대와 통화해요.
왜 배우는지 고르면 그 순서대로 주제가 놓이고, 이건 전부 대화 설정 한 곳에서 정해요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어면접 #영어공부 #스피킹 #nawana

## Instagram caption (en)

Topics someone else picked leave you with nothing to say. They're not about you.
So talk about your own life.

Open Talk and the topics you picked come first.
Add the job you're applying for and you talk through the questions its interviews ask.
Add what you care about and you talk about recent stories on it.
Tap a situation you saved and you're on with that person again, as often as you like.
Pick why you're learning and those topics come first. It's all set in one place: Talk settings.

Your first 20 minutes are free · link in bio

#englishinterview #speakingpractice #learnenglish #languagelearning #nawana

## Threads (ko) · a reply under 03 (say it again)

"고향을 소개해 보세요" 같은 주제 앞에선 할 말이 별로 없죠. 내 얘기가 아니니까요.

지난번엔 같은 통화를 다시 했다면, 이번엔 무슨 얘기로 통화할지 내가 정해요. 지원하는 직무를 적어 두면 그 직무의 면접 질문이, 관심사를 적어 두면 관련된 최근 기사가, 만들어 둔 상황이 있으면 그 상황이 대화 탭에 올라와요. 하나 누르면 그 얘기로 통화가 시작돼요.

왜 배우는지 고르면 그 순서대로 주제가 놓이고, 이건 전부 대화 설정 한 곳에서 정해요.

(≈ 270 chars, no hashtags, first 7 items)

## Threads (en) · a reply under 03 (say it again) in the English thread

Topics like "describe your hometown" don't leave you much to say. They're not your story.

Last time, you ran the same call again. This time, you pick what the call is about. Add the job you're applying for and you get its interview questions. Add what you care about and you get recent stories on it. Save a situation and it's there too. Tap one and the call starts.

Pick why you're learning and those topics come first. It's all set in Talk settings.

(≈ 450 chars, no hashtags, no sound line, first 7 items)

## Community series entry

A NEW entry (no old one matches: e02 is the call, e03 settings); founder approval.
cat: talk
ko: { title: "내가 원하는 토픽", tagline: "내 직무, 내 관심사, 내 상황으로 통화해요" }
en: { title: "Your own topics", tagline: "Talk about your role, your interests, your situations" }

---

## Open questions (for the lead)

1. **Card 03 loading row ko** "직무에 맞는 주제를 쓰고 있어요…" is my guess at the app's string for
   "Writing topics for your field…"; the designer should take the catalog's ko value.
2. **Card 04 en title no longer says "this week's news"** (English pass 2026-10-14): "Add an
   interest, talk about its news" + "recent stories", matching the ko.
3. **Card 06 chip names after Save:** the travel purpose's own chip label (ko/en) must come from
   the kit/catalog; I didn't name it in the copy. If the designer would rather pick only 취업·이직
   준비, the desc still holds (order is said, not shown).
4. **Card 06 overlaps `learning-purpose`** (that piece is about the "왜 배워요" picker). This card only
   shows where it lives; say if the two should not both run.
5. **Cover title ko changed** 교재 주제로는 → 남이 정한 주제론: in this app 교재 means the book a call
   becomes, so "교재 주제" read as the app's own books. en "Textbook topics?" unchanged.
6. **Sample interest and role** need a real capture with those values (kit gaps 1, 2, 5).
