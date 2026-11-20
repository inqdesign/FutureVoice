/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc } from "../core.js";

/* ═══════════════════════════ <nw-tutorbot> ═══════════════════════════
 * The Talk tab's tutor bot (TutorBotViews.swift, TutorTodayRows.swift, TutorBot.swift,
 * TutorAgent.swift). The Talk home underneath is the kit's own <nw-home tabbar>, not a redraw.
 *
 * Poses (static, no animation):
 *   home          Talk home with the bot's face, no bubble
 *   bubble        the bot's bubble above the face
 *   note          the day's note over the softened page
 *   chat          the chat sheet, opening thread
 *   answer        chat after the "why the same mistake" chip: question, then the tutor's reply
 *   answer-five   the same after the "I only have 5 minutes" chip
 *   looking       the thinking row, mid-lookup ("Going over your mistakes…")
 *
 * Script (each step awaitable; bot.run(async s => { await s.openNote(); … })):
 *   await s.showBubble()   await s.hideBubble()
 *   await s.openNote()     await s.closeNote()     await s.tapLater()    await s.tapAskMe()
 *   await s.tapFace()      opens the chat (TutorBotButton)
 *   await s.openChat()     await s.closeChat()
 *   await s.ask("mistake" | "five" | { question, lookup, reply, actions })
 *        chip question → pressed in the row (scrolled to first if off screen); any other text is
 *        typed in the box and sent. Then the real status line: Thinking… → the lookup's own line
 *        (TutorTools.progressLine) → Writing… → the answer. No lookup = Thinking… alone.
 * demo() beats: 1 note · 2 note folds, the bubble · 3 chat opens · 4 the question · 5 the answer.
 *
 * Sample content is DATA: bot.sample = {…} (merged over the defaults, top level only), or a JSON
 * `sample` attribute. Everything optional:
 *   greeting "Did you sleep well?"   initial "A"     today "2026-11-09"
 *   hello    the note's first line (TutorCopy.greeting)
 *   routine  { things: 3, minutes: 40 }                  → "Your routine today: 3 things, about 40 minutes."
 *   why      { label: "past tense", talks: 3 } | "any line" | null     (TutorCopy.why)
 *   now, next  { kind, title, detail, tag }              kind picks glyph + colour (KIND below)
 *   more     2                                           → "2 more today"; 0 hides the fold
 *   goal     null (default) | true (a generic interview, D-12) | { kind, title, place, date: "YYYY-MM-DD" }
 *            A goal adds its row to the note and the chat, and (unless `now`/`next` are set) its
 *            reading becomes Now, as TutorToday.ranked does.
 *   bubble   { text, action }                            action null → a lone OK
 *   exchanges { mistake: { question, lookup, reply, actions }, five: { … } }
 *            lookup: a TutorTools name (talks talk search mistakes notebook cards progress goals
 *            routine scenarios) or null. actions: real TutorAction kinds, 0–2, each only opens
 *            something: { type, topic?, id?, text?, label? }; lesson needs topic, book/goal/goalReading/
 *            goalAnswer need id, word/expression need text, or the button is dropped, as isValid does.
 *   The default reply is an obvious placeholder: the tutor's words come from a real model run.
 * Numbers are illustrative sample data. */

const T = {
  ko: {
    tutor: "튜터", title: "개인 튜터", you: "나", now: "지금", next: "다음", more: n => `오늘 할 일 ${n}개 더`,
    later: "나중에", askMe: "물어보기", add: "목표 추가", ask: "뭐든 물어보세요…", start: "시작", notNow: "지금은 안 할래요", ok: "확인",
    intro: "연습에 관해 뭐든 물어보세요. 지금까지의 대화와 카드, 루틴을 보고 답해 드릴게요.",
    noGoal: "준비하는 일이 있어요? 면접, 시험, 발표 같은 거요. 무엇을 언제 하는지 알려 주면 매일 거기에 맞춰 준비시켜 줄게요.",
    routine: (n, m) => `오늘 루틴은 ${n}가지, ${m}분쯤이면 돼요.`,
    focus: (l, n) => `요즘은 ${l} 연습 중이에요. 대화 ${n}번에서 나왔거든요.`,
    hello: "좋은 아침이에요.", locale: "한국어",
    chips: ["지금 뭐 하면 좋을까요?", "왜 자꾸 같은 실수를 할까요?", "5분밖에 없어요", "실력이 늘고 있나요?", "다음 레벨로 가려면 어떻게 해요?"],
    thinking: "생각하는 중…", writing: "쓰는 중…",
    lookups: { talks: "지난 대화를 찾아보고 있어요…", talk: "그 대화를 읽고 있어요…", search: "내가 한 말을 찾아보고 있어요…", mistakes: "자주 하는 실수를 살펴보고 있어요…",
      notebook: "단어장을 열어 보고 있어요…", cards: "카드를 확인하고 있어요…", progress: "실력이 어떻게 변했는지 보고 있어요…", goals: "목표를 읽고 있어요…", routine: "루틴을 확인하고 있어요…", scenarios: "상황을 살펴보고 있어요…" },
    actions: { talk: "통화 시작하기", talkTopic: "이 주제로 대화하기", lesson: "튜터와 말해 보기", book: "교재 열기", goal: "목표 보기", goalReading: "오늘의 읽기", goalAnswer: "모범 답변",
      word: "단어 보기", expression: "표현 보기", review: "복습 시작하기", shadow: "섀도잉 시작하기", sayItAgain: "다시 말하기", listen: "듣기", speech: "스피치 열기", test: "테스트 풀기", quiz: "퀵 퀴즈", routine: "나의 루틴", settings: "통화 설정", purposes: "왜 배워요?" },
    defaults: { talk: "대화 10분", review: "복습", anytime: "언제든", why: "과거 시제", bubble: "복습 끝, 잘했어요. 다음 할 일: 섀도잉 2문장", tagReading: "읽기", focus: "자기소개와 지원 동기", placeholder: "[튜터의 실제 답변이 여기 들어갑니다]" },
  },
  en: {
    tutor: "Tutor", title: "Personal tutor", you: "You", now: "Now", next: "Next", more: n => `${n} more today`,
    later: "Later", askMe: "Ask me", add: "Add a goal", ask: "Ask me anything…", start: "Start", notNow: "Not now", ok: "OK",
    intro: "Ask me anything about your practice. I answer from your own talks, cards and routine.",
    noGoal: "Preparing for something? An interview, an exam, a presentation. Tell me what and when, and every day I'll prepare you for it.",
    routine: (n, m) => `Your routine today: ${n} things, about ${m} minutes.`,
    focus: (l, n) => `We're working on ${l}. It came up in ${n} of your talks.`,
    hello: "Good morning.", locale: "English",
    chips: ["What should I do now?", "Why do I keep making the same mistake?", "I only have 5 minutes", "Am I getting better?", "How do I reach the next level?"],
    thinking: "Thinking…", writing: "Writing…",
    lookups: { talks: "Looking through your talks…", talk: "Reading that talk…", search: "Searching what you've said…", mistakes: "Going over your mistakes…",
      notebook: "Opening your notebook…", cards: "Checking your cards…", progress: "Looking at your progress…", goals: "Reading your goals…", routine: "Checking your routine…", scenarios: "Looking at your scenarios…" },
    actions: { talk: "Start a talk", talkTopic: "Talk about this", lesson: "Practise it with the tutor", book: "Open the book", goal: "Open the goal", goalReading: "Today's reading", goalAnswer: "Model answer",
      word: "Open the word", expression: "Open the expression", review: "Start review", shadow: "Start shadowing", sayItAgain: "Say it again", listen: "Listen", speech: "Open Speech", test: "Take the test", quiz: "Quick quiz", routine: "My routine", settings: "Call settings", purposes: "Why are you learning?" },
    defaults: { talk: "Talk 10 min", review: "Review", anytime: "Anytime", why: "past tense", bubble: "Nice, review done. Next up: Shadowing 2 lines.", tagReading: "Reading", focus: "Introducing yourself and why this job", placeholder: "[The tutor's real answer goes here]" },
  },
};

/* SF Symbols, traced. `currentColor` is the glyph's own colour. */
const GLYPH = {
  chevR: [7, 12, `<path d="M1.2 1.2 5.8 6l-4.6 4.8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`],
  chevD: [12, 7, `<path d="M1.2 1.2 6 5.8l4.8-4.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`],
  xmark: [18, 18, `<path d="M2 2l14 14M16 2 2 16" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"/>`],
  plus: [14, 14, `<path d="M7 1.2v11.6M1.2 7h11.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`],
  bubble: [18, 17, `<path d="M9 1.3c4.3 0 7.8 2.8 7.8 6.3S13.300 13.900 9 13.900c-.8 0-1.500-.1-2.200-.2l-3 2.100c-.5.300-1 0-.9-.6l.4-2.700C1.900 11.300 1.200 9.500 1.200 7.600 1.200 4.100 4.700 1.300 9 1.300z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>`],
  mic: [14, 20, `<rect x="3.900" y=".6" width="6.200" height="12" rx="3.100" fill="currentColor"/><path d="M1.100 8.800a5.900 5.900 0 0 0 11.800 0M7 14.800v3.400M3.800 18.900h6.400" fill="none" stroke="currentColor" stroke-width="1.700" stroke-linecap="round"/>`],
  updown: [9, 15, `<path d="M1 5.200 4.500 1.500 8 5.200M1 9.800l3.500 3.700L8 9.800" fill="none" stroke="currentColor" stroke-width="1.600" stroke-linecap="round" stroke-linejoin="round"/>`],
  arrowUp: [16, 18, `<path d="M8 16.500v-15M1.800 7.600 8 1.500l6.200 6.100" fill="none" stroke="currentColor" stroke-width="2.100" stroke-linecap="round" stroke-linejoin="round"/>`],
  /* the goal row: person.text.rectangle.fill, the card white and the marks in the tile's colour */
  idcard: [20, 15, `<rect width="20" height="15" rx="3.200" fill="#fff"/><g fill="currentColor"><circle cx="6.300" cy="5.700" r="2.100"/><path d="M2.700 11.700c.3-2 1.800-3.200 3.600-3.200s3.300 1.200 3.600 3.200z"/><rect x="11.600" y="4" width="5.800" height="1.300" rx=".65"/><rect x="11.600" y="6.900" width="5.800" height="1.300" rx=".65"/><rect x="11.600" y="9.800" width="4" height="1.300" rx=".65"/></g>`],
  checklist: [18, 16, `<g fill="none" stroke="currentColor" stroke-width="1.800" stroke-linecap="round" stroke-linejoin="round"><path d="M1 3l1.600 1.600L5.500 1.200M1 11.500l1.600 1.600 2.900-3.400M8.500 3.200H17M8.500 8H17M8.500 12.800H17"/></g>`],
  personWave: [20, 16, `<g fill="currentColor"><circle cx="10" cy="4.800" r="3.100"/><path d="M4.700 15.200c0-3.300 2.400-5.300 5.300-5.300s5.300 2 5.300 5.300c0 .5-.3.8-.8.8H5.500c-.5 0-.8-.3-.8-.8z"/></g><path d="M2.800 1.800a8 8 0 0 0 0 8.400M17.200 1.800a8 8 0 0 1 0 8.400" fill="none" stroke="currentColor" stroke-width="1.500" stroke-linecap="round"/>`],
  house: [18, 16, `<path fill="currentColor" d="M8.200.7c.5-.4 1.100-.4 1.600 0l7.600 6.500c.6.500.2 1.500-.6 1.500H15v5.900c0 .8-.6 1.400-1.400 1.400H4.400C3.600 16 3 15.400 3 14.600V8.700H1.200C.4 8.700 0 7.700.6 7.200z"/>`],
  airplane: [18, 18, `<path fill="currentColor" d="M16.500 1.500c.8.800.5 2.100-.4 3l-3 3 1.800 8c.1.300 0 .7-.3.900l-.6.700c-.3.300-.8.200-1.100-.2L9.400 10 6.500 12.900l.3 2.400c0 .3-.1.500-.3.700l-.5.500c-.3.200-.7.200-.9-.1l-1.600-2.700-2.700-1.600c-.3-.2-.3-.6-.1-.9l.5-.5c.2-.2.400-.3.700-.3l2.400.3L7.200 7.800 .3 4.300C-.1 4-.2 3.500.1 3.200l.7-.6c.2-.3.600-.4.900-.3l8 1.800 3-3c.9-.9 2.200-1.200 3-.4z"/>`],
  star: [18, 17, `<path fill="currentColor" d="M9 .8l2.500 5.300 5.800.8-4.200 4 1 5.800L9 14l-5.100 2.700 1-5.800-4.200-4 5.800-.8z"/>`],
  /* the rows and the buttons */
  phone: [18, 18, `<path fill="currentColor" d="M4.800 1.200c.5-.2 1 0 1.300.4l1.700 3.100c.3.400.2 1-.2 1.300L6.300 7.300c.8 1.800 2.300 3.400 4.200 4.300l1.300-1.300c.3-.3.900-.4 1.300-.1l3.100 1.700c.4.300.6.800.4 1.300l-.7 2c-.4 1-1.300 1.600-2.400 1.500C7.700 15.900 2.100 10.300 1.400 4.600c-.1-1.100.5-2 1.500-2.400z"/>`],
  stack: [18, 18, `<g fill="currentColor"><rect x="4" y=".8" width="10" height="1.500" rx=".75"/><rect x="2.400" y="3.800" width="13.200" height="1.700" rx=".85"/><rect x="1" y="7" width="16" height="10.200" rx="2.400"/></g>`],
  textbook: [16, 20, `<path fill="currentColor" fill-rule="evenodd" d="M3.500.7h9.700c1 0 1.800.8 1.800 1.800v12c0 .6-.4 1-1 1H3.700c-.8 0-1.300.5-1.300 1.200s.5 1.200 1.300 1.200h10.600c.4 0 .7.300.7.700s-.3.700-.7.700H3.500C2 19.300 1 18.200 1 16.800V3.200C1 1.800 2.100.7 3.500.7zM5 4.100c-.3 0-.5.200-.5.500v.6c0 .3.200.5.500.5h7c.3 0 .5-.2.500-.5v-.6c0-.3-.2-.5-.5-.5zm0 3.400c-.3 0-.5.200-.5.500v.5c0 .3.200.5.500.5h4.500c.3 0 .5-.2.500-.5V8c0-.3-.2-.5-.5-.5z"/>`],
  book: [15, 19, `<path fill="currentColor" d="M3 .8h10c.8 0 1.400.6 1.400 1.400v11.600c0 .5-.4.900-.9.900H3.200c-.7 0-1.200.5-1.200 1.100s.5 1.100 1.200 1.100h10.300c.5 0 .9.400.9.800s-.4.800-.9.800H3C1.700 18.500.7 17.400.7 16.100V3.100C.7 1.800 1.700.8 3 .8z"/>`],
  grad: [22, 17, `<g fill="currentColor"><path d="M10.300 1 .9 5.400c-.5.200-.5.900 0 1.100l9.400 4.400c.4.200.9.200 1.300 0l9.500-4.400c.5-.2.500-.9 0-1.100L11.600 1c-.4-.2-.9-.2-1.300 0z"/><path d="M4.600 10.200v3.300c0 1.700 2.900 3.200 6.400 3.200s6.400-1.500 6.400-3.200v-3.300l-5.300 2.400c-.7.300-1.500.3-2.200 0z"/></g>`],
  flag: [15, 18, `<path fill="currentColor" d="M1.700.8c.5 0 .9.400.9.900v.5c1.100-.6 2.200-.9 3.500-.9 2.500 0 3.800 1.400 5.800 1.400.8 0 1.600-.2 2.300-.6.300-.1.600.1.600.4v8.400c0 .2-.1.400-.3.500-.9.500-1.800.8-2.800.8-2.200 0-3.500-1.400-5.700-1.400-1.200 0-2.400.3-3.400 1v5c0 .5-.4.900-.9.900s-.9-.4-.9-.9V1.700c0-.5.400-.9.900-.9z"/>`],
  charbook: [15, 19, `<path fill="currentColor" fill-rule="evenodd" d="M3 .8h10c.8 0 1.400.6 1.400 1.400v11.600c0 .5-.4.900-.9.900H3.200c-.7 0-1.200.5-1.200 1.100s.5 1.100 1.200 1.100h10.300c.5 0 .9.400.9.800s-.4.800-.9.800H3C1.700 18.500.7 17.400.7 16.100V3.100C.7 1.800 1.700.8 3 .8zm5.100 2.800c-.1-.3-.3-.5-.6-.5s-.5.200-.6.500L4.700 9.900c-.1.400.1.700.5.700.3 0 .5-.2.600-.5l.4-1.300h2.600l.4 1.300c.1.300.3.500.6.500.4 0 .6-.3.500-.7zm-.6 1.700.9 2.400H6.600z"/>`],
  musicMic: [18, 18, `<g fill="currentColor"><circle cx="12.600" cy="5.400" r="4.300"/><path d="M9.200 6.900l2.100 2.100.9.800-7.100 6.400c-.6.500-1.500.5-2-.1l-1-1c-.6-.6-.6-1.500 0-2.100z"/></g>`],
  wave: [20, 16, `<path d="M1.500 6.500v3M5.500 3.500v9M10 .8v14.400M14.500 3.500v9M18.500 6.500v3" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>`],
  ccw: [17, 19, `<g fill="none" stroke="currentColor" stroke-width="1.900" stroke-linecap="round" stroke-linejoin="round"><path d="M6.500 4.600h2a7 7 0 1 1-7 7"/><path d="M9.600 1.200 6.300 4.600l3.300 3.300"/></g>`],
  headphones: [19, 18, `<path fill="none" stroke="currentColor" stroke-width="1.900" stroke-linecap="round" d="M2 11.800V9a7.500 7.500 0 0 1 15 0v2.800"/><rect x="1" y="10" width="4.400" height="7" rx="1.900" fill="currentColor"/><rect x="13.600" y="10" width="4.400" height="7" rx="1.900" fill="currentColor"/>`],
  seal: [18, 18, `<path fill="currentColor" fill-rule="evenodd" d="M9 .6l2.300 1.600 2.800-.2 1 2.600 2.300 1.600-.8 2.700.8 2.700-2.300 1.600-1 2.600-2.800-.2L9 17.400l-2.300-1.600-2.800.2-1-2.600L.6 11.800l.8-2.700-.8-2.700 2.300-1.600 1-2.600 2.800.2zm3.500 5.700c-.3-.3-.8-.3-1.100 0L8 9.800 6.600 8.400c-.3-.3-.8-.3-1.100 0s-.3.800 0 1.100l2 2c.3.300.8.300 1.100 0l3.900-4.100c.3-.3.300-.8 0-1.100z"/>`],
  textformat: [20, 14, `<g fill="currentColor"><path d="M5.200 1.700c.2-.5.700-.8 1.200-.8s1 .3 1.200.8l4 10.300c.2.500-.2 1.100-.8 1.100-.4 0-.7-.2-.8-.6l-1-2.700H4.400l-1 2.700c-.1.400-.4.600-.8.600-.6 0-1-.6-.8-1.100zM5 8.200h2.800L6.400 4.400z"/><path d="M16 4.500c2 0 3.300 1 3.300 2.900v5c0 .4-.3.700-.7.700s-.7-.3-.7-.7v-.5c-.5.800-1.400 1.300-2.500 1.300-1.600 0-2.700-1-2.700-2.500s1.100-2.400 3-2.500l2.100-.1v-.7c0-1-.7-1.600-1.800-1.600-.8 0-1.400.3-1.800.9-.2.200-.4.300-.6.300-.4 0-.7-.3-.7-.7 0-.1 0-.3.100-.4.500-.9 1.700-1.400 3.200-1.400zm-1.100 7.700c1.300 0 2.300-.9 2.300-2V9.500l-1.900.1c-1 .1-1.600.6-1.600 1.300s.5 1.300 1.200 1.300z"/></g>`],
  quote: [18, 17, `<path fill="currentColor" fill-rule="evenodd" d="M9 1.300c4.300 0 7.800 2.800 7.800 6.300S13.300 13.900 9 13.900c-.8 0-1.500-.1-2.200-.2l-3 2.100c-.5.300-1 0-.9-.6l.4-2.700C1.900 11.300 1.200 9.500 1.200 7.600 1.200 4.100 4.700 1.300 9 1.300zM6.700 5.400c-1 0-1.700.8-1.700 1.700 0 1 .6 1.600 1.500 1.700-.1.500-.5 1-1 1.300-.2.100-.3.300-.2.500.1.200.3.300.5.200 1.600-.7 2.600-2 2.600-3.500 0-1.100-.7-1.900-1.700-1.900zm4.800 0c-1 0-1.700.8-1.700 1.700 0 1 .6 1.600 1.500 1.700-.1.500-.5 1-1 1.300-.2.100-.3.300-.2.500.1.200.3.300.5.200 1.600-.7 2.600-2 2.600-3.500 0-1.100-.7-1.900-1.700-1.900z"/>`],
  qcircle: [18, 18, `<circle cx="9" cy="9" r="7.900" fill="none" stroke="currentColor" stroke-width="1.500"/><path d="M6.700 7c.1-1.300 1-2.100 2.400-2.100s2.300.8 2.300 2c0 .9-.5 1.500-1.300 2-.6.400-.9.700-.9 1.300v.3" fill="none" stroke="currentColor" stroke-width="1.500" stroke-linecap="round"/><circle cx="9.100" cy="13" r="1" fill="currentColor"/>`],
  calendar: [18, 16, `<path fill="currentColor" fill-rule="evenodd" d="M3 .5h12c1.500 0 2.600 1.100 2.600 2.600v9.800c0 1.500-1.100 2.600-2.600 2.600H3C1.500 15.500.4 14.400.4 12.900V3.100C.4 1.600 1.500.5 3 .5zM2.800 4.500c-.6 0-1 .4-1 1v7.400c0 .7.500 1.200 1.200 1.200h12c.7 0 1.200-.5 1.200-1.200V5.500c0-.6-.4-1-1-1z"/>`],
  sliders: [18, 15, `<g fill="none" stroke="currentColor" stroke-width="1.500" stroke-linecap="round"><path d="M.9 2.300h7M11.900 2.300h5.200M.9 7.500h2.400M7.300 7.500h9.800M.9 12.700h7M11.900 12.700h5.200"/><circle cx="9.900" cy="2.300" r="1.800"/><circle cx="5.300" cy="7.500" r="1.800"/><circle cx="9.900" cy="12.700" r="1.800"/></g>`],
  target: [18, 18, `<g fill="none" stroke="currentColor" stroke-width="1.500"><circle cx="9" cy="9" r="7.900"/><circle cx="9" cy="9" r="4.700"/></g><circle cx="9" cy="9" r="1.800" fill="currentColor"/>`],
  trophy: [18, 18, `<path fill="currentColor" d="M4.600 1h8.800v1.200H16c.5 0 .9.400.9.900v1.600c0 2.200-1.700 3.900-4 4.100-.6 1.200-1.700 2-3 2.300v2.600h2.300c.7 0 1.300.6 1.300 1.300v1.100c0 .3-.2.500-.5.500H5c-.3 0-.5-.2-.5-.5v-1.100c0-.7.600-1.300 1.300-1.300h2.300v-2.600c-1.300-.3-2.400-1.100-3-2.300-2.300-.2-4-1.900-4-4.100V3.100c0-.5.400-.9.900-.9h2.600z"/>`],
  newspaper: [20, 18, `<path fill="currentColor" fill-rule="evenodd" d="M5.600.9H17c1.100 0 2 .9 2 2v11.400c0 1.500-1.300 2.800-2.900 2.800H3.800C2.200 17.100 1 15.900 1 14.300V6.700c0-.6.500-1.200 1.200-1.200h1.500V2.900c0-1.100.8-2 1.900-2zM3.700 7.300h-1v7c0 .500.400.900 1 .900s.900-.4.900-.9V7.300zM7.200 4v4h4.100V4zm5.600.4v1.300h3.400V4.400zm0 2.700v1.300h3.400V7.100zm-5.600 3v1.300h9v-1.300zm0 2.700v1.300h9v-1.300z"/>`],
};
const sf = (n, w, h) => { const g = GLYPH[n]; if (!g) return ""; return `<svg viewBox="0 0 ${g[0]} ${g[1]}" width="${w ?? g[0]}" height="${h ?? g[1]}" aria-hidden="true">${g[2]}</svg>`; };

/* iOS 26 system colours (purple and green read off the captures; the rest are the system's values). */
const C = { blue: "#0088FF", green: "#34C759", teal: "#00C3D0", yellow: "#FFCC00", cyan: "#00C0E8", purple: "#CB30E0", orange: "#FF8D28", pink: "#FF2D55", brown: "#AC7F5E", red: "#FF3B30" };
/* StudyPlan.Kind (symbol, color) and TutorPick.Kind (symbol, TutorPickRows.color) */
const KIND = {
  talk: ["phone", C.blue], review: ["stack", C.green], sayItAgain: ["ccw", C.teal], words: ["textformat", C.purple], expressions: ["quote", C.pink],
  shadow: ["wave", C.yellow], test: ["seal", C.orange], speech: ["musicMic", C.purple], listen: ["headphones", C.cyan],
  rankDrop: ["trophy", C.red], newEpisode: ["headphones", C.cyan], firstSpeech: ["musicMic", C.purple], readScript: ["textbook", C.brown], readNews: ["newspaper", C.brown],
  goalReading: ["textbook", C.purple], goalSpeech: ["musicMic", C.purple], goalDrill: ["grad", C.purple],
};
/* UpcomingGoal.Kind (symbol, tint) */
const GOAL_KIND = { interview: ["idcard", C.purple], exam: ["checklist", C.orange], presentation: ["personWave", C.teal], move: ["house", C.green], trip: ["airplane", C.cyan], other: ["star", C.blue] };
/* TutorAction.symbol */
const ACTION = {
  talk: "phone", lesson: "grad", book: "book", goal: "flag", goalReading: "textbook", goalAnswer: "musicMic", word: "charbook", expression: "charbook",
  review: "stack", shadow: "wave", sayItAgain: "ccw", listen: "headphones", speech: "musicMic", test: "seal", quiz: "qcircle", routine: "calendar", settings: "sliders", purposes: "target",
};
/* TutorAction.isValid, as far as a page can ask it: the field the button needs must be there. */
const actionOK = a => {
  if (!a || !ACTION[a.type]) return false;
  if (a.type === "lesson") return !!a.topic;
  if (["book", "goal", "goalReading", "goalAnswer"].includes(a.type)) return !!a.id;
  if (["word", "expression"].includes(a.type)) return !!a.text;
  return true;
};

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAYS = { ko: ["일", "월", "화", "수", "목", "금", "토"], en: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] };
const ymd = s => { const [y, m, d] = String(s).split("-").map(Number); return { y, m, d, t: Date.UTC(y, m - 1, d), w: new Date(Date.UTC(y, m - 1, d)).getUTCDay() }; };
/* date.formatted(date: .abbreviated, time: .omitted) */
const longDate = (s, ko) => { const a = ymd(s); return ko ? `${a.y}년 ${a.m}월 ${a.d}일` : `${MONTHS[a.m - 1]} ${a.d}, ${a.y}`; };
/* .dateTime.weekday(.abbreviated).month().day() */
const threadDate = (s, ko) => { const a = ymd(s); return ko ? `${a.m}월 ${a.d}일 (${DAYS.ko[a.w]})` : `${DAYS.en[a.w]}, ${MONTHS[a.m - 1]} ${a.d}`; };
/* UpcomingGoal.countdown */
const countdown = (date, today) => { const n = Math.round((ymd(date).t - ymd(today).t) / 864e5); return n < 0 ? null : n === 0 ? "D-day" : `D-${n}`; };

/* iOS ProgressView: eight spokes, the leading one darkest, turning in steps */
const SPIN = `<span class="spin">${[...Array(8)].map((_, i) => `<i style="transform:rotate(${i * 45}deg);opacity:${(.25 + .75 * (8 - i) / 8).toFixed(2)}"></i>`).join("")}</span>`;

/* What the page behind has to do for the note, and where the capture says the dock sits. Added to
   the nested <nw-home>'s shadow root; home.js itself is untouched. */
const HOME_PATCH = `
  :host([tabbar]) .dock{top:715px}
  .dock .qz i{top:24.7px;transition:top .28s ease}
  :host([tb-happy]) .dock .qz i{top:21.7px;animation:tb-flutter .8s linear 1 both}
  @keyframes tb-flutter{0%,12%{transform:scaleY(1)}20%,24%{transform:scaleY(.45)}34%,45%{transform:scaleY(1)}53%,57%{transform:scaleY(.45)}67%,78%{transform:scaleY(1)}86%,90%{transform:scaleY(.45)}100%{transform:scaleY(1)}}
  .tb-mat{position:absolute;inset:0;z-index:5;pointer-events:none;opacity:0;transition:opacity .35s ease-in-out;
    background:rgba(236,236,240,.5);backdrop-filter:blur(17px) saturate(1.2);-webkit-backdrop-filter:blur(17px) saturate(1.2)}
  :host([tb-note]) .tb-mat{opacity:1}
  .tbar{padding:4px 8.33px}
  .tbar span{font-weight:500;font-size:10.4px;gap:4px;padding-top:2px}
  .tbar span.on{background:none;position:relative}
  .tbar span.on::before{content:"";position:absolute;inset:0 -4px;border-radius:27px;background:rgba(120,120,128,.14);z-index:-1}
  .tbar span svg{width:auto;height:22.5px}
  .dock .pl,.dock .tp{transition:filter .3s ease-out,opacity .3s ease-out,transform .15s}
  :host([tb-note]) .dock .pl,:host([tb-note]) .dock .tp{filter:blur(6px);opacity:.5}
`;

/* RootTabView's five symbols as the captures draw them (waveform, music.mic, play.circle.fill,
   book.fill, chart.bar.fill); the nested home's own traces predate them. */
const TAB_GLYPHS = [
  `<svg viewBox="0 0 21 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M1.4 9.2v5.6M5.3 4.6v14.8M9.2 1v22M13.1 7.4v9.2M17 3v18M19.700 9.700v4.600"/></svg>`,
  `<svg viewBox="0 0 24 24"><circle cx="18" cy="6.1" r="5.2" fill="currentColor"/><path fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" d="M13.8 8.800 5 18.300M15.700 11 7 20M5 18.300l2 1.700M2.200 21.300l3-2.900M11.300 14.100l.5 8.700"/></svg>`,
  `<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="11.6" fill="currentColor"/><path d="M9.300 7.200v9.600l7.600-4.800z" fill="#fff"/></svg>`,
  `<svg viewBox="0 0 28 22"><g fill="currentColor"><path d="M13.200 3.500C10.500 1.300 7.300.4 3.900.4 1.700.4.700 1.300.7 3v15.500c0 1.300.8 1.900 1.900 1.700 3.900-.9 7.800-.2 10.600 1.800z"/><path d="M14.800 3.500C17.500 1.300 20.700.4 24.100.4c2.200 0 3.200.9 3.200 2.600v15.500c0 1.300-.8 1.900-1.900 1.700-3.900-.9-7.800-.2-10.600 1.800z"/></g></svg>`,
  `<svg viewBox="0 0 29 22"><g fill="currentColor"><rect x=".5" y="8" width="8" height="13.5" rx="2"/><rect x="10.500" y="4" width="8" height="17.500" rx="2"/><rect x="20.500" y=".5" width="8" height="21" rx="2"/></g></svg>`,
];

const SHEET_TOP = 62, FEED_TOP = 69.6, BAR_TOP = 589;   // sheet coordinates: where the scroll starts, and the composer's top edge

class NwTutorBot extends NwScreen {
  static poses = ["home", "bubble", "note", "chat", "answer", "answer-five", "looking"];
  constructor() {
    super(`
      :host{background:#F2F2F7;--blue:#0A5CF5;--soft:#D5E2F9;--sec:rgba(60,60,67,.6);--ter:rgba(60,60,67,.3);--sepc:rgba(60,60,67,.29)}
      nw-home{z-index:0}
      p{margin:0}
      .note,.bub,.sheet{word-break:keep-all;overflow-wrap:break-word}
      .nt,.nt *{transition:none!important}
      /* SoftChipStyle */
      .c{display:inline-flex;align-items:center;gap:11px;height:39.4px;padding:0 16px;border-radius:20px;background:#fff;font-size:15px;line-height:18px;font-weight:500;letter-spacing:-.1px;white-space:nowrap;transition:opacity .12s}
      .c.on{background:var(--soft);color:var(--blue)}
      .c.pr{opacity:.6}
      .c .ic{display:flex;align-items:center;justify-content:center;width:18px;flex:0 0 18px}
      /* the note */
      .note{position:absolute;left:12px;right:12px;bottom:163.2px;z-index:8;filter:drop-shadow(0 8px 20px rgba(0,0,0,.18));
        opacity:0;transform:scale(.6);transform-origin:100% 100%;pointer-events:none;transition:opacity .3s ease,transform .3s ease}
      .note.on{opacity:1;transform:none}
      .note::before{content:"";position:absolute;left:0;right:0;top:0;bottom:12px;background:#fff;border-radius:24px}
      .note .tail{position:absolute;right:27px;bottom:0;display:block}
      /* SwiftUI's .shadow falls on every child of the card too: that is the halo round the pills */
      .nc{position:relative;padding:16px 16px 28px;display:flex;flex-direction:column;gap:14px;filter:drop-shadow(0 8px 20px rgba(0,0,0,.18))}
      .hd{display:flex;flex-direction:column;gap:4px}
      .hd b{font-size:17px;line-height:22px;margin:-1px 0;font-weight:600;letter-spacing:-.18px}
      .hd span{font-size:15px;line-height:20px;margin:-1px 0;letter-spacing:-.1px}
      .hd small{font-size:13px;line-height:17.6px;margin:-1px 0;color:var(--sec);letter-spacing:.05px}
      .foot{display:flex;align-items:center;justify-content:space-between;gap:10px}
      /* UpcomingGoalRow */
      .g{display:flex;align-items:center;gap:6px}
      .g .gr{flex:1;min-width:0;display:flex;align-items:center;gap:12px}
      .g .gi{flex:0 0 30px;width:30px;height:30px;border-radius:7px;display:grid;place-items:center}
      .g .gt{flex:1;min-width:0;max-width:192px;display:flex;flex-direction:column;gap:2px}
      .g .gt b{font-size:17px;line-height:22px;margin:-1px 0;font-weight:400;letter-spacing:-.18px}
      .g .gt small{font-size:13px;line-height:17.6px;margin:-1px 0;color:var(--sec);letter-spacing:.05px}
      .g .dd{margin-left:auto;font-size:15px;line-height:20px;font-weight:600;font-variant-numeric:tabular-nums;letter-spacing:-.1px}
      .cv{flex:0 0 auto;display:block;color:rgba(60,60,67,.3)}
      .g .cv{margin-left:3.2px}
      .cv.tint{color:var(--blue)}
      /* TutorTodayRows */
      .rows{display:flex;flex-direction:column}
      .nc .rows{margin-top:2px}
      .cap{font-size:11px;line-height:13px;font-weight:600;color:var(--sec);text-transform:uppercase;padding:6px 0 0 40px;letter-spacing:.14px}
      .rw{display:flex;align-items:center;gap:12px;padding:8px 0}
      .rw.big{padding:10px 0}
      .rw .i{flex:0 0 28px;width:28px;display:flex;align-items:center;justify-content:center}
      .rw .tx{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
      .rw .tg{font-size:11px;line-height:13px;font-weight:600;letter-spacing:.14px}
      .rw .tt{font-size:15px;line-height:20px;margin:-1px 0;letter-spacing:-.1px}
      .rw.big .tt{font-size:17px;line-height:22px;margin:-1px 0;font-weight:600;letter-spacing:-.18px}
      .rw .dt{font-size:12px;line-height:14.3px;color:var(--sec);letter-spacing:.18px}
      .dv{height:.5px;margin-left:40px;background:var(--sepc)}
      .mo{display:flex;align-items:center;gap:6px;padding:10px 0 10px 40px;color:var(--blue);font-size:13px;line-height:16px;font-weight:600;letter-spacing:.05px}
      /* the bubble */
      .bub{position:absolute;right:16px;bottom:165.4px;width:250px;z-index:8;padding:12px;background:#fff;border-radius:18px 18px 6px 18px;
        filter:drop-shadow(0 6px 14px rgba(0,0,0,.16));opacity:0;transform:translateY(193px);pointer-events:none;transition:opacity .25s ease-out,transform .25s ease-out}
      .bub.on{opacity:1;transform:none;transition:opacity .35s ease-out,transform .35s ease-out}
      .bub p{font-size:15px;line-height:20px;margin:-1px 0;letter-spacing:-.1px}
      .bub .bi{filter:drop-shadow(0 6px 14px rgba(0,0,0,.16))}
      .bub .bb2{display:flex;gap:8px;margin-top:11px}
      /* the sheet */
      .dim{position:absolute;inset:0;z-index:20;background:rgba(0,0,0,.2);opacity:0;pointer-events:none;transition:opacity .4s ease}
      .dim.on{opacity:1}
      .sheet{position:absolute;left:0;right:0;top:${SHEET_TOP}px;bottom:0;z-index:21;background:#fff;border-radius:38px 38px 0 0;overflow:hidden;
        transform:translateY(830px);transition:transform .45s cubic-bezier(.32,.72,0,1)}
      .sheet.on{transform:none}
      .grab{position:absolute;left:183px;top:5px;width:36px;height:5px;border-radius:3px;background:#C7C7CC;z-index:4}
      .close{position:absolute;left:16px;top:16px;width:44px;height:44px;border-radius:22px;background:#fff;color:var(--blue);display:grid;place-items:center;z-index:4;
        box-shadow:0 2px 14px rgba(0,0,0,.08),0 0 0 .5px rgba(0,0,0,.02)}
      .ttl{position:absolute;left:70px;right:70px;top:26.5px;height:24px;text-align:center;z-index:4;font-family:var(--pixel);font-size:17px;line-height:24px;letter-spacing:0;white-space:nowrap}
      .scv{position:absolute;inset:0;overflow:hidden;z-index:1}
      .feed{position:absolute;left:0;right:0;top:${FEED_TOP}px;padding:16px;display:flex;flex-direction:column;gap:14px;transition:transform .38s cubic-bezier(.3,.7,.2,1)}
      /* DialogueLine */
      .ln{display:flex;flex-direction:column;align-items:flex-start;gap:4px;max-width:330px;align-self:flex-start}
      .ln.me{align-self:flex-end;align-items:flex-end}
      .ln.wide{width:330px}
      .ln .nm{font-size:12px;line-height:14.3px;color:var(--sec);letter-spacing:.1px}
      .bb{padding:10px 14px;border-radius:14px;background:#F2F2F7;font-size:17px;line-height:22px;letter-spacing:-.18px;display:flex;flex-direction:column}
      .ln.wide .bb{width:100%}
      .ln.me .bb{background:#D3E2FD}
      .bb .sub{font-size:15px;line-height:20px;letter-spacing:-.1px;color:var(--sec);margin-top:5px}
      .bb .rows{margin-top:10px}
      .bb .g + .c,.bb .tx0 + .c{margin-top:10px}
      .bb .c{align-self:flex-start}
      .acts{display:flex;flex-direction:column;align-items:flex-start;gap:8px}
      .day{align-self:stretch;margin-bottom:-1px;text-align:center;font-size:11px;line-height:13px;color:var(--sec);letter-spacing:.1px}
      .think{display:flex;align-items:center;gap:8px;color:var(--sec)}
      .spin{position:relative;display:inline-block;flex:0 0 20px;width:20px;height:20px;animation:sp .8s steps(8) infinite}
      .spin i{position:absolute;left:45.5%;top:0;width:9%;height:28%;border-radius:9px;background:#8E8E93;transform-origin:50% 178.5%}
      @keyframes sp{to{transform:rotate(360deg)}}
      /* iOS 26 soft scroll edges, top and bottom */
      .ft,.fb{position:absolute;left:0;right:0;z-index:2;pointer-events:none}
      .ft{top:0;height:78px;backdrop-filter:blur(5px);-webkit-backdrop-filter:blur(5px);
        -webkit-mask-image:linear-gradient(#000 55%,transparent);mask-image:linear-gradient(#000 55%,transparent);
        background:linear-gradient(#fff 40%,rgba(255,255,255,0))}
      .fb{top:572px;bottom:0;backdrop-filter:blur(2.2px);-webkit-backdrop-filter:blur(2.2px);
        -webkit-mask-image:linear-gradient(transparent,#000 34px);mask-image:linear-gradient(transparent,#000 34px);
        background:linear-gradient(rgba(255,255,255,0) 14px,rgba(255,255,255,.5) 38px,rgba(255,255,255,.96) 80px,#fff 92px)}
      /* the composer */
      .chw{position:absolute;left:0;right:0;top:597px;z-index:3;overflow:hidden;transition:opacity .2s ease-in-out}
      .chw.off{opacity:0;pointer-events:none}
      .chs{display:inline-flex;gap:10px;padding:4px 16px;transition:transform .5s cubic-bezier(.3,.7,.2,1)}
      .fld{position:absolute;left:12px;right:12px;top:654.800px;height:114.400px;border-radius:24px;background:#F2F2F7;z-index:3}
      .fld .tf{position:absolute;left:14px;right:14px;top:20px;height:22px;font-size:17px;line-height:22px;letter-spacing:-.18px;white-space:nowrap;overflow:hidden}
      .fld .tf.ph{color:var(--ter)}
      .fld .ctl{position:absolute;right:14px;top:56px;height:44px;display:flex;align-items:center;gap:8px}
      .loc{height:36px;border-radius:18px;background:rgba(118,118,128,.12);display:flex;align-items:center;gap:8px;padding:0 15px 0 16px;font-size:15px;line-height:20px;letter-spacing:-.1px;color:var(--sec);white-space:nowrap}
      .loc svg{color:var(--sec)}
      .mc{width:40px;height:40px;border-radius:50%;background:rgba(118,118,128,.12);display:grid;place-items:center;color:#000}
      .snd{width:40px;height:40px;border-radius:50%;background:var(--blue);color:#fff;display:none;place-items:center;transition:opacity .12s}
      .snd.on{display:grid}
      .snd.pr{opacity:.6}
    `, `
      <div class="pg"></div>
      <div class="note"><svg class="tail" width="22" height="14" viewBox="0 0 22 14" aria-hidden="true"><path d="M0 0H22L11 14Z" fill="#fff"/></svg><div class="nc"></div></div>
      <div class="bub"></div>
      <div class="dim"></div>
      <div class="sheet">
        <div class="grab"></div>
        <div class="close">${sf("xmark", 17, 17)}</div>
        <div class="ttl"></div>
        <div class="scv"><div class="feed"><div class="ln wide l-goal"></div><div class="ln wide l-plan"></div><div class="ln l-intro"></div></div></div>
        <div class="ft"></div><div class="fb"></div>
        <div class="chw"><div class="chs"></div></div>
        <div class="fld"><div class="tf ph"></div><div class="ctl"><span class="loc"><span class="lt"></span>${sf("updown", 9, 15)}</span><span class="mc">${sf("mic", 14, 20)}</span><span class="snd">${sf("arrowUp", 16, 18)}</span></div></div>
      </div>`);
    this._sample = {};
    this._msgs = 0;
  }

  /* ── sample data ── */
  get sample() { return this._sample; }
  set sample(v) { this._sample = { ...(v || {}) }; if (this._built) { this._syncHome(); this._render(); } }
  get _L() { return this.t === STR.ko ? T.ko : T.en; }
  get _ko() { return this.t === STR.ko; }
  _d() {
    const L = this._L, D = L.defaults, s = this._sample;
    const today = s.today || "2026-11-09";
    const g0 = s.goal === true ? { kind: "interview", title: "Job interview", place: "Berlin", date: "2026-11-21" } : s.goal || null;
    const goal = g0 ? { kind: "interview", title: "", place: "", ...g0 } : null;
    const talk = { kind: "talk", title: D.talk, detail: D.anytime };
    const review = { kind: "review", title: D.review, detail: D.anytime };
    const cd = goal && goal.date ? countdown(goal.date, today) : null;
    const reading = { kind: "goalReading", tag: D.tagReading, title: "Making a Strong First Impression", detail: (cd ? `${cd} · ` : "") + D.focus };
    return {
      today, goal,
      greeting: s.greeting || "Did you sleep well?", initial: s.initial || "A",
      hello: s.hello || L.hello,
      routine: { things: 3, minutes: 40, ...(s.routine || {}) },
      why: s.why === undefined ? { label: D.why, talks: 3 } : s.why,
      now: s.now || (goal ? reading : talk),
      next: s.next || (goal ? talk : review),
      more: s.more ?? 2,
      bubble: { text: D.bubble, action: L.start, ...(s.bubble || {}) },
      exchanges: {
        mistake: { question: L.chips[1], lookup: "mistakes", reply: D.placeholder, actions: [{ type: "lesson", topic: "(topic)" }], ...(s.exchanges?.mistake || {}) },
        five: { question: L.chips[2], lookup: null, reply: D.placeholder, actions: [{ type: "review" }], ...(s.exchanges?.five || {}) },
      },
    };
  }

  /* ── drawing ── */
  _chip(label, on, icon) { return `<span class="c${on ? " on" : ""}">${icon ? `<span class="ic">${icon}</span>` : ""}${esc(label)}</span>`; }
  _whyLine(d) {
    if (!d.why) return "";
    return typeof d.why === "string" ? d.why : this._L.focus(d.why.label, d.why.talks);
  }
  _goalRow(goal, d) {
    const [sym, tint] = GOAL_KIND[goal.kind] || GOAL_KIND.other;
    const parts = []; if (goal.place) parts.push(goal.place); if (goal.date) parts.push(longDate(goal.date, this._ko));
    const cd = goal.date ? countdown(goal.date, d.today) : null;
    return `<div class="g"><div class="gr"><span class="gi" style="background:${tint};color:${tint}">${sf(sym, 19.500, 14.600)}</span>`
      + `<span class="gt"><b>${esc(goal.title)}</b>${parts.length ? `<small>${esc(parts.join(" · "))}</small>` : ""}</span>`
      + `${cd ? `<span class="dd" style="color:${tint}">${esc(cd)}</span>` : ""}</div>${sf("chevR", 6.300, 11).replace("<svg ", '<svg class="cv" ')}</div>`;
  }
  _row(e, big) {
    const [sym, col] = KIND[e.kind] || KIND.talk;
    const box = GLYPH[sym], k = (big ? 17.5 : 13.5) / Math.max(box[0], box[1]) * (big ? 1.1 : 1.05);
    return `<div class="rw${big ? " big" : ""}"><span class="i" style="color:${col}">${sf(sym, box[0] * k, box[1] * k)}</span>`
      + `<span class="tx">${e.tag ? `<span class="tg" style="color:${col}">${esc(e.tag)}</span>` : ""}<span class="tt">${esc(e.title)}</span>${e.detail ? `<span class="dt">${esc(e.detail)}</span>` : ""}</span>`
      + `${sf("chevR", 6.300, 11).replace("<svg ", `<svg class="cv${big ? " tint" : ""}" `)}</div>`;
  }
  _rows(d) {
    const L = this._L;
    let h = "";
    if (d.now) h += `<div class="cap">${esc(L.now)}</div>${this._row(d.now, true)}`;
    if (d.next) h += `${h ? '<div class="dv"></div>' : ""}<div class="cap">${esc(L.next)}</div>${this._row(d.next, false)}`;
    if (d.more > 0) h += `<div class="dv"></div><div class="mo">${esc(L.more(d.more))}${sf("chevD", 10.500, 6)}</div>`;
    return `<div class="rows">${h}</div>`;
  }
  _render() {
    const L = this._L, d = this._d();
    const why = this._whyLine(d), opening = L.routine(d.routine.things, d.routine.minutes);
    /* the note */
    this.$(".nc").innerHTML = `<div class="hd"><b>${esc(d.hello)}</b><span>${esc(opening)}</span>${why ? `<small>${esc(why)}</small>` : ""}</div>`
      + (d.goal ? this._goalRow(d.goal, d) : "") + this._rows(d)
      + `<div class="foot">${this._chip(L.later, false)}${this._chip(L.askMe, true, sf("bubble", 17, 16)).replace('class="c on"', 'class="c on am"')}</div>`;
    /* the bubble */
    const b = d.bubble;
    this.$(".bub").innerHTML = `<div class="bi"><p>${esc(b.text)}</p><div class="bb2">${b.action ? this._chip(b.action, true) + this._chip(L.notNow, false) : this._chip(L.ok, false)}</div></div>`;
    /* the chat's opening thread */
    this.$(".ttl").textContent = L.title;
    const name = `<span class="nm">${esc(L.tutor)}</span>`;
    this.$(".l-goal").classList.toggle("wide", !!d.goal);
    this.$(".l-goal").innerHTML = name + `<div class="bb">${d.goal
      ? this._goalRow(d.goal, d) + this._chip(L.add, false, sf("plus", 13, 13))
      : `<div class="tx0">${esc(L.noGoal)}</div>` + this._chip(L.add, true, sf("plus", 13, 13))}</div>`;
    this.$(".l-plan").innerHTML = name + `<div class="bb"><div>${esc(opening)}</div>${why ? `<div class="sub">${esc(why)}</div>` : ""}${this._rows(d)}</div>`;
    this.$(".l-intro").innerHTML = name + `<div class="bb">${esc(L.intro)}</div>`;
    this.$(".chs").innerHTML = L.chips.map(q => this._chip(q, true)).join("");
    this.$(".lt").textContent = L.locale;
    if (!this._draft) this.$(".tf").textContent = L.ask;
  }
  _syncHome() {
    const h = this._home, d = this._d(); if (!h) return;
    const g = h.$(".greet");
    g.innerHTML = esc(d.greeting).replace(/ (this|today|tonight)/, "<br>$1");
    h.$(".av").textContent = d.initial;
    // the greeting is centred on the same spot however many lines it takes
    g.style.top = `${211 - g.offsetHeight / 2}px`;
  }
  build() {
    const h = this._home = document.createElement("nw-home");
    h.setAttribute("fill", ""); h.setAttribute("tabbar", ""); h.setAttribute("lang", this._ko ? "ko" : "en");
    if (this.hasAttribute("static")) h.setAttribute("static", "");
    this.$(".pg").append(h);
    h.shadowRoot.append(Object.assign(document.createElement("style"), { textContent: HOME_PATCH }));
    h.$(".s").insertBefore(Object.assign(document.createElement("div"), { className: "tb-mat" }), h.$(".tbar"));
    const attr = this.getAttribute("sample");
    if (attr) { try { this._sample = JSON.parse(attr); } catch { /* a bad attribute is the defaults */ } }
    h.$$(".tbar span svg").forEach((g, i) => { g.outerHTML = TAB_GLYPHS[i]; });
    this._syncHome(); this._render(); this.reset();
    document.fonts?.ready?.then(() => { if (this._home) this._syncHome(); });
  }

  /* ── state ── */
  _still(fn) {
    const r = this.$(".pg").parentElement; r.classList.add("nt"); fn();
    void r.offsetHeight; r.classList.remove("nt");
  }
  _happy() { return this.$(".note").classList.contains("on") || this.$(".bub").classList.contains("on"); }
  _face() { this._home.toggleAttribute("tb-happy", this._happy()); }
  _clearThread() {
    this.$$(".feed .msg").forEach(e => e.remove());
    this._msgs = 0;
    this.$(".feed").style.transform = "";
    this.$(".chs").style.transform = "";
    this.$(".chw").classList.remove("off");
    this._setDraft("");
  }
  reset() {
    this._still(() => {
      this.$(".note").classList.remove("on"); this.$(".bub").classList.remove("on");
      this.$(".dim").classList.remove("on"); this.$(".sheet").classList.remove("on");
      this._home.removeAttribute("tb-note"); this._face();
      this._clearThread();
    });
  }
  _setDraft(text) {
    this._draft = text;
    const f = this.$(".tf");
    f.classList.toggle("ph", !text);
    f.textContent = text || this._L.ask;
    this.$(".snd").classList.toggle("on", !!text);
  }
  /* scroll to where the last message comes to rest (proxy.scrollTo, clamped at the end of the content) */
  _scrollEnd() {
    const y = Math.max(0, this.$(".feed").offsetHeight - (BAR_TOP - FEED_TOP));
    this.$(".feed").style.transform = y ? `translateY(${-y}px)` : "";
  }
  _append(html) {
    const w = document.createElement("div"); w.innerHTML = html;
    const n = w.firstElementChild; n.classList.add("msg");
    this.$(".feed").append(n); return n;
  }
  _question(q) {
    const L = this._L, d = this._d();
    if (!this._msgs) this._append(`<div class="day">${esc(threadDate(d.today, this._ko))}</div>`);
    this._msgs++;
    this._append(`<div class="ln me"><span class="nm">${esc(L.you)}</span><div class="bb">${esc(q)}</div></div>`);
  }
  _thinkLine(text) {
    return this._append(`<div class="ln"><span class="nm">${esc(this._L.tutor)}</span><div class="bb"><span class="think">${SPIN}<span class="st">${esc(text)}</span></span></div></div>`);
  }
  _reply(ex) {
    const L = this._L;
    this._msgs++;
    const acts = (ex.actions || []).filter(actionOK).slice(0, 2).map((a, i) => {
      const title = a.label && a.label.length <= 28 ? a.label
        : a.type === "talk" ? (a.topic ? L.actions.talkTopic : L.actions.talk)
        : (a.type === "word" || a.type === "expression") && a.text ? a.text
        : L.actions[a.type];
      return this._chip(title, i === 0, sf(ACTION[a.type], 16, 16));
    }).join("");
    return this._append(`<div class="ln"><span class="nm">${esc(L.tutor)}</span><div class="bb">${esc(ex.reply)}</div>${acts ? `<div class="acts">${acts}</div>` : ""}</div>`);
  }
  _exchange(which) { const e = this._d().exchanges; return typeof which === "string" ? e[which] : { ...e.mistake, lookup: null, ...which }; }

  /* ── script ── */
  async _press(el, ms = 200) { if (!el) return; el.classList.add("pr"); await this.sleep(ms); el.classList.remove("pr"); }
  async showBubble() { this.$(".bub").classList.add("on"); this._face(); await this.sleep(400); }
  async hideBubble() { this.$(".bub").classList.remove("on"); this._face(); await this.sleep(300); }
  async openNote() { this.$(".note").classList.add("on"); this._home.setAttribute("tb-note", ""); this._face(); await this.sleep(380); }
  async closeNote() { this.$(".note").classList.remove("on"); this._home.removeAttribute("tb-note"); this._face(); await this.sleep(380); }
  async tapLater() { await this._press(this.$(".foot .c")); await this.closeNote(); }
  async tapAskMe() { await this._press(this.$(".foot .am")); this.$(".note").classList.remove("on"); this._home.removeAttribute("tb-note"); this._face(); await this.openChat(); }
  async tapFace() {
    const q = this._home.$(".dock .qz");
    q.classList.add("tap"); await this.sleep(200); q.classList.remove("tap");
    this.$(".bub").classList.remove("on"); this._face();
    await this.openChat();
  }
  async openChat() { this.$(".dim").classList.add("on"); this.$(".sheet").classList.add("on"); await this.sleep(500); }
  async closeChat() { this.$(".dim").classList.remove("on"); this.$(".sheet").classList.remove("on"); await this.sleep(500); }
  /** One question, through the view's own states. See the header. */
  async ask(which = "mistake") {
    const L = this._L, ex = this._exchange(which);
    const i = L.chips.indexOf(ex.question), chips = this.$$(".chs .c");
    if (i >= 0 && !this.$(".chw").classList.contains("off")) {
      // send(q) from the row: the row is a horizontal scroll, so a chip past the edge is brought in first
      const c = chips[i], over = c.offsetLeft + c.offsetWidth + 16 - 402;
      if (over > 0) { this.$(".chs").style.transform = `translateX(${-over}px)`; await this.sleep(650); }
      await this._press(c);
    } else {
      // typed in the box: the chips leave, the send button comes in
      this.$(".chw").classList.add("off");
      const f = this.$(".tf"); f.classList.remove("ph");
      await this.typeInto(f, ex.question, 34);
      this._setDraft(ex.question);
      await this.sleep(320);
      await this._press(this.$(".snd"));
      this._setDraft("");
      this.$(".chw").classList.remove("off");
    }
    this.beat(4);
    this._question(ex.question); this._scrollEnd();
    await this.sleep(420);
    const line = this._thinkLine(L.thinking); this._scrollEnd();
    const st = line.querySelector(".st");
    if (ex.lookup && L.lookups[ex.lookup]) {
      await this.sleep(900);
      st.textContent = L.lookups[ex.lookup];
      await this.sleep(1500);
      st.textContent = L.writing;
      await this.sleep(1200);
    } else {
      await this.sleep(1900);
    }
    line.remove();
    this.beat(5);
    this._reply(ex); this._scrollEnd();
    await this.sleep(400);
  }

  /* ── poses and the demo ── */
  async pose(name) {
    this.stop();
    this.reset();
    this._syncHome();
    this._still(() => {
      if (name === "bubble") this.$(".bub").classList.add("on");
      else if (name === "note") { this.$(".note").classList.add("on"); this._home.setAttribute("tb-note", ""); }
      else if (["chat", "answer", "answer-five", "looking"].includes(name)) {
        this.$(".dim").classList.add("on"); this.$(".sheet").classList.add("on");
        if (name === "answer" || name === "answer-five") {
          const ex = this._d().exchanges[name === "answer" ? "mistake" : "five"];
          this._question(ex.question); this._reply(ex); this._scrollEnd();
        } else if (name === "looking") {
          const ex = this._d().exchanges.mistake;
          this._question(ex.question);
          this._thinkLine(this._L.lookups[ex.lookup] || this._L.thinking);
          this._scrollEnd();
        }
      }
      this._face();
    });
  }
  async demo() {
    await this.sleep(900);
    this.beat(1); await this.openNote(); await this.sleep(2800);
    this.beat(2); await this.tapLater(); await this.sleep(500);
    await this.showBubble(); await this.sleep(2300);
    this.beat(3); await this.tapFace(); await this.sleep(1200);
    await this.ask("mistake");   // beats 4 and 5
    await this.sleep(2600);
    await this.closeChat(); await this.sleep(300);
  }
}

export { NwTutorBot };
