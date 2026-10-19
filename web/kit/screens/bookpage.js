/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* ═══════════════════════════ <nw-bookpage> — a talk's review book ═══════════════════════════
 * ConversationDetailView inside BookmarkedPage (BookmarkPage.swift): one white page (left 44 →
 * right 16 of the screen, top 6 under the bar, bottom 10, corners 0·16·16·16) and the ribbon
 * bookmarks down its leading edge — 40pt wide, 10pt corners on the outside, 4pt apart; the
 * selected one is the page's own paper, the rest the same paper at 55%. A ribbon swaps the page's
 * content in place (no navigation). Chapters: the cover (avatar, title, date · turns, the progress
 * bar, Continue/Replay, Say it again, the score), Words, Expressions, Drill (StudyIcon.grammar) and
 * Shadow, in that order. Every size below is from real/talkdetail*.png (iPhone 17, ko) and the
 * Text heights are UIFont.lineHeight (body 20.33, subheadline 17.9, footnote 15.5, caption 14.3).
 *
 *   await page.open("words" | "expressions" | "drill" | "shadow" | "cover")   ribbon tap + page swap
 *   await page.tapLine(i)                                                      presses row i of the open chapter
 *   await page.shadowTake(i, score)                                            a take scored: Shadow row i shows its best, checks at 80+
 *   await page.drillDone(i)                                                    Drill row i mastered: green check, ribbon count, cover bar
 *   await page.sayItAgain(coverEl?) / closeCover(coverEl)                      press "Say it again"; slide a laid-over <nw-sayagain> up / down
 *   page.browsing = true    the bar a book pushed from Review has: back · title · ⋯ (and Continue on the cover)
 *   page.book = {...}       swap the book's material (see JOB below for the shape) */

const SVG = (vb, body, w, h, cls = "") => `<svg ${cls ? `class="${cls}" ` : ""}viewBox="${vb}" width="${w}" height="${h}" aria-hidden="true">${body}</svg>`;
const ST = 'fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"';
/* SF Symbols, traced at the size the page draws them */
const SF = {
  bookClosed: (w = 13, h = 16) => SVG("0 0 13 16", `<path ${ST} stroke-width="1.45" d="M2.7.9h8.2c.8 0 1.3.5 1.3 1.3v9.6H2.9c-1 0-1.9.8-1.9 1.8s.9 1.7 1.9 1.7h9.3M1 13.6V2.6C1 1.6 1.7.9 2.7.9M12.2 11.8v3.3"/>`, w, h),
  words: (w = 12.7, h = 16) => SVG("0 0 17 21", '<path fill="currentColor" fill-rule="evenodd" d="M3.4 0h11.4c1 0 1.7.7 1.7 1.7v14.4c0 .8-.6 1.4-1.4 1.4H3.6c-.7 0-1.3.5-1.3 1.2s.6 1.2 1.3 1.2h12c.5 0 .9.4.9.9s-.4.8-.9.8H3.5C1.6 21.6 0 20.1 0 18.4V3.4C0 1.5 1.5 0 3.4 0zm.9 1.8c-.3 0-.5.2-.5.5v13.3c0 .3.2.5.5.5h.2c.3 0 .5-.2.5-.5V2.3c0-.3-.2-.5-.5-.5zm3.4 2.6c-.4 0-.6.3-.6.6s.2.6.6.6h5.6c.4 0 .6-.3.6-.6s-.2-.6-.6-.6zm0 3c-.4 0-.6.3-.6.6s.2.6.6.6h5.6c.4 0 .6-.3.6-.6s-.2-.6-.6-.6z"/>', w, h),
  quote: (w = 16.2, h = 15.2) => SVG("0 0 22 21", '<path fill="currentColor" fill-rule="evenodd" d="M4 0h14c2.2 0 4 1.8 4 4v8.3c0 2.2-1.8 4-4 4H9.6l-4.4 3.9c-.6.5-1.4.1-1.4-.6v-3.3C1.7 16 0 14.3 0 12.3V4c0-2.2 1.8-4 4-4zm4.3 4.6c-1.3 0-2.2.9-2.2 2.1 0 1.1.8 2 1.9 2 .2 0 .4 0 .5-.1-.3.9-1 1.6-2 2-.3.1-.4.4-.3.6.1.3.4.4.7.3 2-.7 3.4-2.4 3.4-4.4 0-1.5-.8-2.5-2-2.5zm5.7 0c-1.3 0-2.2.9-2.2 2.1 0 1.1.8 2 1.9 2 .2 0 .4 0 .5-.1-.3.9-1 1.6-2 2-.3.1-.4.4-.3.6.1.3.4.4.7.3 2-.7 3.4-2.4 3.4-4.4 0-1.5-.8-2.5-2-2.5z"/>', w, h),
  check: (w = 16.2, h = 15.2) => SVG("0 0 22 21", '<path fill="currentColor" fill-rule="evenodd" d="M4 0h14c2.2 0 4 1.8 4 4v8.3c0 2.2-1.8 4-4 4H9.6l-4.4 3.9c-.6.5-1.4.1-1.4-.6v-3.3C1.7 16 0 14.3 0 12.3V4c0-2.2 1.8-4 4-4zm11.7 3.3c-.4-.3-.9-.2-1.2.2l-4.6 6.9-2.5-2.7c-.3-.4-.9-.4-1.2 0-.4.3-.4.8-.1 1.2l3.3 3.6c.4.4 1 .3 1.3-.1l5.2-7.9c.3-.4.2-.9-.2-1.2z"/>', w, h),
  shadow: (w = 17.2, h = 16.3) => SVG("0 0 22 22", '<g fill="none" stroke="currentColor" stroke-linecap="round"><path stroke-width="1.6" d="M1 8.6v4.8M4.2 5.4v11.2M7.4 1v20M10.6 4.4v13.2M13.8 2.6v9.4"/></g><g fill="currentColor"><rect x="15.6" y="9.6" width="4" height="7.6" rx="2"/><path d="M14 14.6c0-.4.3-.7.7-.7s.7.3.7.7c0 1.4 1.1 2.5 2.4 2.5s2.4-1.1 2.4-2.5c0-.4.3-.7.7-.7s.7.3.7.7c0 1.9-1.4 3.5-3.1 3.8v1.6h1.6c.4 0 .7.3.7.7s-.3.7-.7.7h-4.7c-.4 0-.7-.3-.7-.7s.3-.7.7-.7h1.6v-1.6C15.4 18.1 14 16.5 14 14.6z"/></g>', w, h),
  bubbles: (w = 22, h = 18) => SVG("0 0 28 23", '<g fill="currentColor"><path d="M4.4 0h11.1c2.2 0 4 1.7 4.1 3.9h-6.8c-2.9 0-5.2 2.3-5.2 5.2v5.2H6.3l-2.6 2.6c-.5.5-1.3.1-1.3-.5v-2.3C.9 13.7 0 12.3 0 10.6V4.4C0 2 2 0 4.4 0z"/><path d="M12.9 5.5h10.7c2.4 0 4.4 2 4.4 4.4v6.3c0 1.7-1 3.2-2.4 3.9v2.3c0 .7-.8 1-1.3.5l-2.6-2.6h-8.8c-2.4 0-4.4-2-4.4-4.4V9.9c0-2.4 2-4.4 4.4-4.4z"/></g>', w, h),
  play: SVG("0 0 14 16", '<path fill="currentColor" d="M1.6 1.1c0-.8.9-1.3 1.6-.9l10.3 6.3c.7.4.7 1.4 0 1.8L3.2 14.6c-.7.4-1.6-.1-1.6-.9z"/>', 13, 15),
  viewfinder: SVG("0 0 18 17", `<g ${ST} stroke-width="1.5"><path d="M1 5V3.2C1 1.9 1.9 1 3.2 1H5M13 1h1.8C16.1 1 17 1.9 17 3.2V5M17 12v1.8c0 1.3-.9 2.2-2.2 2.2H13M5 16H3.2C1.9 16 1 15.1 1 13.8V12M5.6 5.6h6.8M5.6 8.5h6.8M5.6 11.4h4.4"/></g>`, 17, 16),
  chartBar: SVG("0 0 18 12", `<g fill="none" stroke="currentColor" stroke-width="1.35"><rect x=".9" y="5.6" width="4.2" height="5.7" rx="1"/><rect x="6.9" y="2.9" width="4.2" height="8.4" rx="1"/><rect x="12.9" y=".7" width="4.2" height="10.6" rx="1"/></g>`, 17.6, 12),
  seal: (() => {
    let d = ""; for (let i = 0; i <= 96; i++) { const a = i / 96 * Math.PI * 2, r = 8.05 + .95 * Math.cos(a * 8); d += `${i ? "L" : "M"}${(10 + r * Math.sin(a)).toFixed(2)} ${(10 - r * Math.cos(a)).toFixed(2)}`; }
    return SVG("0 0 20 20", `<path ${ST} stroke-width="1.45" d="${d}Z"/><path ${ST} stroke-width="1.6" d="M6.6 10.3l2.3 2.4 4.6-5.3"/>`, 19, 19);
  })(),
  quoteO: SVG("0 0 20 19", `<path ${ST} stroke-width="1.45" d="M4 1h12c1.7 0 3 1.3 3 3v7.4c0 1.7-1.3 3-3 3H9l-4.2 3.5c-.4.3-.9 0-.9-.4v-3.1C2.3 14.2 1 12.9 1 11.4V4c0-1.7 1.3-3 3-3z"/><g fill="currentColor"><path d="M7.4 4.8c-1.1 0-1.8.8-1.8 1.8 0 .9.7 1.6 1.6 1.6l.4-.1c-.2.7-.8 1.3-1.6 1.6-.3.1-.4.4-.3.6.1.2.3.3.6.2 1.7-.6 2.8-2 2.8-3.7 0-1.2-.7-2-1.7-2zM12.4 4.8c-1.1 0-1.8.8-1.8 1.8 0 .9.7 1.6 1.6 1.6l.4-.1c-.2.7-.8 1.3-1.6 1.6-.3.1-.4.4-.3.6.1.2.3.3.6.2 1.7-.6 2.8-2 2.8-3.7 0-1.2-.7-2-1.7-2z"/></g>`, 18.6, 17.6),
  metronome: SVG("0 0 20 18", `<g ${ST} stroke-width="1.45"><path d="M8.6 1.6c.6-.9 1.9-.9 2.5 0l7.4 13.2c.5.9-.1 2.1-1.2 2.1H2.6c-1.1 0-1.7-1.2-1.2-2.1zM4.2 12.3h11.6M3.4 16.9l9.4-12"/></g>`, 19, 17),
  chevR: SVG("0 0 8 13", `<path ${ST} stroke-width="2" d="M1.6 1.4l5 5.1-5 5.1"/>`, 8, 13),
  chevL: SVG("0 0 12 20", `<path ${ST} stroke-width="2.6" d="M10 1.8L1.9 10l8.1 8.2"/>`, 12, 20),
  circle: SVG("0 0 20 20", '<circle cx="10" cy="10" r="7.7" fill="none" stroke="currentColor" stroke-width="1.25"/>', 20, 20),
  circleOn: SVG("0 0 20 20", '<circle cx="10" cy="10" r="8.3" fill="currentColor"/><path d="M6.4 10.3l2.5 2.5 4.7-5.4" fill="none" stroke="#fff" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>', 20, 20),
  checkFill: SVG("0 0 20 20", '<circle cx="10" cy="10" r="9.3" fill="currentColor"/><path d="M6 10.4l2.8 2.8 5.3-6" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>', 12.5, 12.5),
  sparkles: SVG("0 0 20 20", '<g fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M8.6 5.4c.6 3.6 2.3 5.3 5.9 5.9-3.6.6-5.3 2.3-5.9 5.9-.6-3.6-2.3-5.3-5.9-5.9 3.6-.6 5.3-2.3 5.9-5.9z"/></g><g fill="currentColor"><path d="M14.2 1c.3 1.7 1.1 2.5 2.8 2.8-1.7.3-2.5 1.1-2.8 2.8-.3-1.7-1.1-2.5-2.8-2.8 1.7-.3 2.5-1.1 2.8-2.8z"/><path d="M4.3 2.2c.2.9.6 1.3 1.5 1.5-.9.2-1.3.6-1.5 1.5-.2-.9-.6-1.3-1.5-1.5.9-.2 1.3-.6 1.5-1.5z"/></g>', 14.6, 14.6),
  ellipsisC: SVG("0 0 24 24", '<circle cx="12" cy="12" r="10.2" fill="none" stroke="currentColor" stroke-width="1.9"/><g fill="currentColor"><circle cx="7.4" cy="12" r="1.55"/><circle cx="12" cy="12" r="1.55"/><circle cx="16.6" cy="12" r="1.55"/></g>', 25, 25),
  lightbulb: SVG("0 0 14 18", '<g fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round"><path d="M7 1.2a5.2 5.2 0 0 0-3.1 9.4c.7.5 1.1 1.2 1.1 2V13h4v-.4c0-.8.4-1.5 1.1-2A5.2 5.2 0 0 0 7 1.2z"/><path d="M5 15.1h4M5.6 17h2.8"/></g>', 11.6, 15),
  /* the cover's report, below the score: target · text.bubble · scope · checkmark.seal.fill ·
     waveform.badge.mic · play.circle.fill · bookmark · rectangle.stack · arrow.right */
  target: SVG("0 0 20 20", '<g fill="none" stroke="currentColor" stroke-width="1.45"><circle cx="10" cy="10" r="8.2"/><circle cx="10" cy="10" r="4.9"/></g><circle cx="10" cy="10" r="1.7" fill="currentColor"/>', 15, 15),
  textBubble: SVG("0 0 20 19", `<path ${ST} stroke-width="1.45" d="M4 1h12c1.7 0 3 1.3 3 3v7.4c0 1.7-1.3 3-3 3H9l-4.2 3.5c-.4.3-.9 0-.9-.4v-3.1C2.3 14.2 1 12.9 1 11.4V4c0-1.7 1.3-3 3-3zM5.6 5.6h8.8M5.6 8.4h8.8M5.6 11.2h5.4"/>`, 15.5, 14.7),
  scope: (s = 15) => SVG("0 0 20 20", `<g ${ST} stroke-width="1.5"><circle cx="10" cy="10" r="6.6"/><path d="M10 .9v4M10 15.1v4M.9 10h4M15.1 10h4"/></g><circle cx="10" cy="10" r="1.6" fill="currentColor"/>`, s, s),
  sealFill: (() => {
    let d = ""; for (let i = 0; i <= 96; i++) { const a = i / 96 * Math.PI * 2, r = 8.7 + .95 * Math.cos(a * 8); d += `${i ? "L" : "M"}${(10 + r * Math.sin(a)).toFixed(2)} ${(10 - r * Math.cos(a)).toFixed(2)}`; }
    return SVG("0 0 20 20", `<path fill="currentColor" d="${d}Z"/><path d="M6.5 10.3l2.4 2.4 4.7-5.3" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`, 22, 22);
  })(),
  micWave: SVG("0 0 20 18", `<g ${ST} stroke-width="1.5"><path d="M1 7.5v3M4 5v8M7 2.5v13M10 5.5v7"/><rect x="13.2" y="1.6" width="3.6" height="7.4" rx="1.8"/><path d="M11.6 7.4a3.4 3.4 0 0 0 6.8 0M15 10.9v2.4"/></g>`, 18, 16),
  playCircle: SVG("0 0 24 24", '<circle cx="12" cy="12" r="11" fill="currentColor" opacity=".18"/><path d="M9.6 7.6v8.8c0 .6.6.9 1.1.6l7-4.4c.5-.3.5-.9 0-1.2l-7-4.4c-.5-.3-1.1 0-1.1.6z" fill="currentColor"/>', 24, 24),
  bookmark: SVG("0 0 12 16", `<path ${ST} stroke-width="1.4" d="M2.4 1h7.2c.8 0 1.4.6 1.4 1.4V15l-5-3.3L1 15V2.4C1 1.6 1.6 1 2.4 1z"/>`, 8.6, 11.5),
  bookmarkFill: SVG("0 0 12 16", '<path fill="currentColor" d="M2.4 .6h7.2c1 0 1.8.8 1.8 1.8v12.4c0 .5-.6.8-1 .5L6 12.4l-4.4 2.9c-.4.3-1 0-1-.5V2.4C.6 1.4 1.4.6 2.4.6z"/>', 7.6, 10.2),
  stackO: SVG("0 0 20 18", `<g ${ST} stroke-width="1.5"><rect x="1.5" y="6" width="17" height="10.8" rx="2.4"/><path d="M3.8 3.5h12.4M6.2 1h7.6"/></g>`, 12.4, 11.2),
  arrowR: SVG("0 0 12 10", `<path ${ST} stroke-width="1.7" d="M1 5h9.4M6.6 1.2 10.4 5 6.6 8.8"/>`, 9.4, 7.8),
  stack: SVG("0 0 20 20", '<g fill="currentColor"><rect x="1.5" y="6.4" width="17" height="12.3" rx="2.6"/><rect x="3.4" y="3.4" width="13.2" height="1.6" rx=".8"/><rect x="5.3" y=".9" width="9.4" height="1.4" rx=".7"/></g>', 18, 18),
};

/* Chrome strings: Localizable.xcstrings (ko) and the English source keys. The words footer has no ko
   entry in the catalog, so the app shows it in English in every language — so does this page. */
const L = {
  ko: { book: "복습 교재", done: "완료", words: "단어", expressions: "표현", drill: "드릴", shadow: "섀도잉",
    turns: (d, n) => `${d} · 말한\u00a0턴\u00a0${n}`, mastered: (a, b) => `${a} / ${b} 완료`, cont: "계속", replay: "다시 듣기", again: "다시 말하기",
    score: "점수", overall: "전체", pron: "발음", focus: "이번 통화 초점", note: "코치 노트", carried: "연습한 걸 실제로 썼어요",
    focusClean: "이번 통화에선 한 번도 안 나왔어요", focusBack: n => `${n}번 다시 나왔어요. 다음 통화에서도 이어가요`,
    fCarry: "화면에 카드도 힌트도 없이, 스스로 꺼내 쓴 표현들이에요. 실제 대화에서 나온 카드는 복습 순서에서 앞당겨져요.",
    src: { drillCard: "복습 카드", curriculumItem: "내 책", studyingExpression: "표현 노트", studyingWord: "단어장", suggestion: "통화 중 제안", knownWord: "안다고 한 단어", knownExpression: "안다고 한 표현" }, firstWords: "내가 처음 쓴 단어", fromSelf: "유창해진 내가 쓴 말", youSaid: "내가 쓴 말", better: "더 낫게 말하기",
    reviewTalk: "이 대화 복습하기", practice: "연습 대화",
    practiceNote: "예시 문장을 보면서 연습한 대화예요. 레벨은 코치 모드 없이 한 대화로 측정해요.",
    fWords: "Tap a word for its card: meaning, pronunciation, your sentences. It's mastered once you use it in a talk or mark it known.",
    fExpr: "이번 대화에서 나온, 다시 쓸 만한 표현들이에요. 유창해진 내가 꺼낸 말과 내가 직접 쓴 말이요. 누르면 뜻과 예문, 어디서 나왔는지가 담긴 카드가 열려요.",
    fShadow: "이 대화에서 유창해진 내가 한 말을 따라 말해 보세요.",
    fDrill: "각 쌍은 내가 말한 문장과 고친 문장이에요. 누르면 카드로 공부해요. 예문, 바꿔 쓸 수 있는 표현, 외우는 요령까지요. 그다음 아래 복습에서 고친 문장을 기억만으로 다시 말해 보게 해요.",
    fRun: "이 대화의 핵심 문장만 빠르게 복습해요. 나머지는 복습 탭에서 다시 만나요.",
    context: "B1 레벨 설정을 기준으로 매겼어요. 이번 대화 자체는 ≈B1로 읽혔고요.", slips: n => `이 대화의 문법 포인트 ${n}개 복습`, abc: "가나다" },
  en: { book: "Review book", done: "Done", words: "Words", expressions: "Expressions", drill: "Drill", shadow: "Shadow",
    turns: (d, n) => `${d} · ${n} turns spoken`, mastered: (a, b) => `${a} of ${b} mastered`, cont: "Continue", replay: "Replay", again: "Say it again",
    score: "Score", overall: "Overall", pron: "Pronunciation", focus: "This call's focus", note: "Coach's note", carried: "You used what you practiced",
    focusClean: "It didn't come back this call", focusBack: n => `Came back ${n} times. It stays your focus`,
    fCarry: "No prompt, no card on screen. You reached for these yourself. Cards you produce live jump ahead in the review queue.",
    src: { drillCard: "Review cards", curriculumItem: "Your books", studyingExpression: "Expression notebook", studyingWord: "Word notebook", suggestion: "In-call suggestions", knownWord: "Words you marked known", knownExpression: "Expressions you marked known" }, firstWords: "Words you used first", fromSelf: "From your fluent self", youSaid: "You said these", better: "Say it better",
    reviewTalk: "Review this talk", practice: "Practice call",
    practiceNote: "You practiced with suggestions on screen. Calls without coach mode are the ones that measure your level.",
    fWords: "Tap a word for its card: meaning, pronunciation, your sentences. It's mastered once you use it in a talk or mark it known.",
    fExpr: "The reusable phrases this talk produced: the ones your fluent self reached for, and the ones you said yourself. Tap for the card: meaning, examples, and where it came up.",
    fShadow: "Repeat your fluent self's lines from this talk.",
    fDrill: "Each pair is what you said and its corrected form. Tap one to study it as a card: examples, variants, a memory hook. The run below then asks you to produce the fix from memory.",
    fRun: "A quick run through this talk's key phrases. Anything left comes back in Review.",
    context: "Scored against your B1 level setting. This talk itself read as ≈B1.", slips: n => `Review ${n} grammar slips from this talk`, abc: "abc" },
};

/* The capture's book (DebugCaptureHarness seeds it). Material stays English; notes are the learner's
   native language, so they carry both. `fix` marks the changed words with <b>. */
const JOB = {
  title: "Job interview",
  date: { ko: "2026년 10월 10일 오후 11:45", en: "Oct 10, 2026 at 11:45 PM" }, turns: 2, mastered: 1, total: 13,
  /* Chapter rows carry the item's state: "used" (said in a talk), "known" (the learner's claim), or
     nothing (still studying). The BOOK draws both used and known with ONE mark — masteryMark(true),
     checkmark.circle.fill in green, the word in secondary — because TalkCurriculum's `masteredAt` is
     "known OR used"; the plain-check / filled-check split exists only in the library lists
     (ExpressionsView.row, VocabularyView). "here" = credited by THIS talk (ingestExpressions), which a
     coach-mode call never does (SessionSummarizer: practice credits nothing), so it stays open there. */
  words: [["initiative", "used"], ["perspective"], ["that", "known"], ["compelling"], ["prioritize"]],
  /* "Words you used first" chips (wordChip): bookmark.fill = studying · green check = known · outline = untouched */
  mine: [["prepared", ""], ["relaxed", "known"], ["interview", "studying"]],
  offered: [["What mattered most"], ["Looking back on it", "known"], ["Put me at ease"]], used: [["Felt prepared", "here"]],
  /* Shadow chapter: TalkCurriculum.shadowPicks splits a fluent-self turn into SENTENCES (4–28 words each),
     so the one turn is two rows. [text, best take score]; a whole-line take at or above 80
     (ScenarioCurriculum.shadowMasteryScore) masters the row. */
  shadow: [["That's a compelling perspective."], ["You clearly took the initiative and prioritized what mattered."]],
  drill: [
    { was: "Honestly, it go really well. I felt prepared.", now: "Honestly, it <b>went</b> really well. I felt prepared.", why: { ko: "지난 일이라 과거형이에요", en: "It already happened, so past tense" } },
    { was: "How relaxed I stayed, even on hard question.", now: "How relaxed I stayed, even on <b>the</b> hard <b>questions.</b>", why: { ko: "the를 붙이고 복수형으로", en: "Add “the” and make it plural" } },
    { was: "it go really well", now: "it <b>went</b> really well", why: { ko: "지난 일이라 과거형이에요", en: "It already happened, so past tense" } },
  ],
  tabs: { words: [2, 5], expressions: [2, 4], drill: [0, 3], shadow: [0, 2] },
  overall: 75,
  /* top_line and the axis notes are coaching — written in the learner's native language (ConversationEngine
     summary schema); the axis NAMES stay English, as the app draws them (ScorecardView.axisRow label: String) */
  topLine: { ko: "자신감 있고 자연스러운 대화였어요. 관사만 조금 다듬어 봐요.", en: "Confident, natural talk. Tighten a few articles." },
  axes: [
    ["abc", "Vocabulary", 82, { ko: "정확하고 구체적인 단어를 골라 썼어요.", en: "Reached for precise, specific words." }],
    ["seal", "Grammar", 71, { ko: "관사와 시제 실수가 몇 개 있었어요.", en: "A few article and tense slips to tidy." }, 2],
    ["quoteO", "Expressiveness", 68, { ko: "표현이 점점 자연스러워지고 있어요.", en: "Getting more natural and idiomatic." }],
    ["metronome", "Fluency & pace", 74, { ko: "속도가 고르고, 길게 멈추는 일이 줄었어요.", en: "Steady pace, fewer long pauses." }],
  ],
  /* ScorecardView.pronunciationRow: label "Pronunciation" IS localized (a Text literal), no bar */
  pron: [80, { ko: "또렷하고, 단어를 자연스럽게 이어 말했어요.", en: "Clear, with good linking." }],
  /* Session.grammarFocus — only a coach-mode call carries one (ConversationView.loadGrammarFocus) */
  focus: { label: { ko: "과거 시제", en: "Past tense" }, was: "…it go really…", now: "…it went really…", repeats: 1 },
  /* summary.overall_note — coaching, native language */
  note: { ko: "면접 이야기를 처음부터 끝까지 순서대로 잘 풀어냈어요. 이미 지난 일을 말할 땐 go 대신 went처럼 과거형을 챙겨 보세요.",
          en: "You told the whole interview story in a clear order. When something already happened, reach for the past tense: went, not go." },
  /* summary.carryovers — what they'd been studying and said unprompted (CarryoverRow) */
  carry: [
    { item: "took the initiative", quote: "So I took the initiative and set up the team meeting myself.", src: "studyingExpression" },
    { item: "walk someone through", quote: "Then I walked them through my last project, step by step.", src: "drillCard" },
  ],
  cards: 0,
};
const SRC_ICON = { drillCard: SF.stackO, studyingExpression: SF.bookmark, studyingWord: SF.bookmark, curriculumItem: SF.bookmark, suggestion: SF.lightbulb, knownWord: SF.circle, knownExpression: SF.circle };
const SHADOW_BAR = 80;   // ScenarioCurriculum.shadowMasteryScore
const ORDER = ["cover", "words", "expressions", "drill", "shadow"];
const ICONS = { cover: SF.bookClosed, words: SF.words, expressions: SF.quote, drill: SF.check, shadow: SF.shadow };

class NwBookPage extends NwScreen {
  static poses = ["cover", "words", "expressions", "shadow", "drill"];
  constructor() {
    super(`
      :host{background:#F2F2F7;--ac:#0A5CF5;--sec:#8A8A8E;--ter:#C4C4C6;--gr:#34C759;--fill:#E4E4E5}
      .s{letter-spacing:0}
      .navt{position:absolute;left:70px;right:70px;top:71px;height:22px;text-align:center;font-family:var(--pixel);font-size:17px;line-height:22px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;z-index:6}
      .gl{position:absolute;top:62px;height:44px;border-radius:22px;background:#FDFDFE;color:var(--ac);display:flex;align-items:center;justify-content:center;z-index:6;
        box-shadow:0 0 0 .5px rgba(0,0,0,.025),0 6px 22px rgba(0,0,0,.065)}
      .done{right:17px;padding:0 15.5px;font-size:17px;font-weight:600}
      .more{right:17px;width:44px}
      .back{left:16px;width:44px;color:#000}
      .gl[hidden]{display:none}
      /* the book */
      .rib{position:absolute;left:4px;top:122px;width:40px;display:flex;flex-direction:column;gap:4px;z-index:2}
      .rb{position:relative;border-radius:10px 0 0 10px;background:rgba(255,255,255,.55);padding:10px 0;display:flex;flex-direction:column;align-items:center;gap:4px;color:var(--sec);transition:background .15s ease-out,color .15s ease-out}
      .rb .ig{height:18.7px;display:grid;place-items:center}
      .rb .ig svg{display:block}
      .rb small{font-size:11px;line-height:13.3px;font-variant-numeric:tabular-nums;letter-spacing:.1px;transition:color .15s ease-out}
      .rb.on{background:#fff;color:var(--ac)}
      .rb.on small{color:#000}
      .rb .ok{color:var(--gr)}
      .pg{position:absolute;left:44px;top:122px;width:342px;height:706px;background:#fff;border-radius:0 16px 16px 16px;overflow:hidden;z-index:1}
      .pc{position:absolute;left:0;top:0;width:342px;transition:opacity .18s ease,transform .5s cubic-bezier(.3,.8,.2,1)}
      .pc.out{opacity:0}
      .press{background:rgba(0,0,0,.06)}
      .row,.ch,.cv{transition:background .15s}
      /* cover */
      .cv{padding:20px 20px 0}
      .hd{display:flex;gap:14px;align-items:flex-start}
      .av{width:56px;height:56px;border-radius:50%;background:#DBE7FE;color:var(--ac);display:grid;place-items:center;flex:0 0 auto}
      .av svg{margin:1px 0 0 1px}
      .tt{display:flex;flex-direction:column;gap:3px;min-width:0}
      .tt b{font-size:20px;line-height:23.9px;font-weight:600;letter-spacing:-.3px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
      .tt span{font-size:15px;line-height:19.8px;color:var(--sec);letter-spacing:-.2px;word-break:keep-all}
      .pr{margin-top:16px;height:4px;border-radius:2px;background:var(--fill);overflow:hidden}
      .pr i{display:block;height:100%;border-radius:2px;background:var(--ac);transition:width .8s}
      .pn{margin-top:6px;font-size:12px;line-height:14.3px;color:var(--sec)}
      .bts{margin-top:19.3px;display:flex;flex-direction:column;gap:17.4px}
      .bts .two{display:flex;gap:10px}
      .bts .two .bt{flex:1}
      .bt{flex:none;height:50.3px;border-radius:26px;background:#D3E2FD;color:var(--ac);display:flex;align-items:center;justify-content:center;gap:8.5px;font-size:17px;letter-spacing:-.4px;transition:filter .15s}
      .bt.pro{background:var(--ac);color:#fff}
      .bt svg{display:block}
      .bt.press{filter:brightness(.88)}
      .dv{height:.33px;background:#C6C6C8;margin-left:20px}
      .gp{display:flex;align-items:center;gap:7px;padding:16px 20px 4px;font-size:13px;line-height:15.5px;font-weight:600;color:var(--sec)}
      .gp svg{display:block;flex:0 0 auto}
      .pnote{padding:0 20px 8px;font-size:15px;line-height:20px;color:var(--sec);letter-spacing:-.25px;word-break:keep-all}
      .sc{padding:2px 20px 8px}
      .ov{display:flex;align-items:center;justify-content:space-between;height:23.9px}
      .ov span{font-size:15px;font-weight:600}
      .ov b{font-size:20px;font-weight:700;color:var(--ac);font-variant-numeric:tabular-nums}
      .cx{margin-top:10.4px;font-size:12px;line-height:16px;color:var(--sec);letter-spacing:-.1px;word-break:keep-all}
      .tl{margin-top:10.6px;font-size:16px;line-height:21px;letter-spacing:-.3px}
      .ax{margin-top:10.4px;display:flex;flex-direction:column;gap:6px}
      .ax.f1{margin-top:15px}
      .ax .h{display:flex;align-items:center;gap:8px;height:17.9px;font-size:15px;font-weight:500;letter-spacing:-.25px}
      .ax .h .gi{width:18px;display:flex;justify-content:center;color:var(--ac)}
      .ax .h .gi.t{width:auto;font-size:15px;font-weight:400;white-space:nowrap;letter-spacing:-.3px}
      .ax .h .n{margin-left:auto;font-weight:600;font-variant-numeric:tabular-nums}
      .ax .h .cr{color:var(--ter);margin-left:4px;display:flex}
      .ax .bar{height:4px;border-radius:2px;background:var(--fill);overflow:hidden}
      .ax .bar i{display:block;height:100%;border-radius:2px}
      .ax .nt{font-size:13px;line-height:15.5px;color:var(--sec);letter-spacing:-.1px}
      .ax .lk{font-size:13px;line-height:15.5px;font-weight:500;color:var(--ac)}
      /* the report under the score (introPage): pronunciation, focus, coach's note, carryovers */
      .ax .h.ps .gi,.ax .h.ps>span:nth-child(2){color:var(--sec)}
      .dv.t{margin-top:8px}
      .cn{padding:2px 20px 8px;font-size:15px;line-height:23px;color:var(--sec);letter-spacing:-.25px;word-break:keep-all}
      .fo{display:flex;gap:12px;align-items:flex-start;padding:2px 20px 10px}
      .fo .fi{flex:0 0 auto;color:var(--ac);margin-top:-1px}
      .fo .fi.ok{color:var(--gr)}
      .fo .fi svg{display:block}
      .fo .fv{display:flex;flex-direction:column;gap:3px;min-width:0}
      .fo .fv b{font-size:15px;line-height:17.9px;font-weight:600;letter-spacing:-.25px}
      .fo .pair{display:flex;align-items:center;gap:5px;font-size:12px;line-height:14.3px;white-space:nowrap}
      .fo .pair s{color:var(--sec);text-decoration-thickness:1px}
      .fo .pair i{color:var(--ter);display:flex}
      .fo .rs{font-size:12px;line-height:14.3px;color:var(--sec);letter-spacing:-.1px}
      .fo .rs.ok{color:var(--gr)}
      .co{padding:10px 16px;display:flex;flex-direction:column;gap:6px}
      .co .ci{display:flex;align-items:flex-start;gap:8px;font-size:15px;line-height:17.9px;font-weight:500;letter-spacing:-.25px}
      .co .ci span:first-child{color:var(--gr);flex:0 0 auto;margin-top:.5px}
      .co .ci svg{display:block;width:18px;height:18px}
      .co .q{padding-left:26px;font-size:12px;line-height:14.3px;color:var(--sec);letter-spacing:-.1px}
      .co .og{padding-left:26px;display:flex;align-items:center;gap:10px}
      .co .og span{display:flex;align-items:center;gap:4px;font-size:11px;line-height:13.3px;color:var(--sec)}
      .co .og span svg{display:block}
      .co .og i{margin-left:auto;color:var(--ac);display:flex}
      .co .og i svg{display:block}
      /* chapter pages */
      .ttl{padding:18px 20px 6px;font-size:17px;line-height:20.33px;font-weight:600;letter-spacing:-.4px}
      .ft{padding:10px 20px 6px;font-size:13px;line-height:18.5px;color:var(--sec);letter-spacing:-.1px;word-break:keep-all}
      .mk{display:block;flex:0 0 auto;color:var(--ter)}
      .mk svg,.cr2 svg{display:block}
      .mk.on{color:var(--gr)}
      .cr2{color:var(--ter);display:flex;flex:0 0 auto}
      .w{display:flex;align-items:center;gap:12px;padding:11px 16px;height:42.33px}
      .w .x{flex:1;font-size:17px;line-height:20.33px;letter-spacing:-.4px}
      .w .x.m{color:var(--sec)}
      .w .mk{width:20px;height:20px}
      .wd{height:.33px;background:#C6C6C8;margin-left:44px}
      .wd.f{margin-left:16px}
      .gl2{padding:12px 16px 0;font-size:13px;line-height:15.5px;font-weight:600;color:var(--sec);letter-spacing:-.1px}
      .chips{display:flex;flex-wrap:wrap;gap:8px;padding:10px 16px}
      .chips span{height:29.3px;padding:0 12px;border-radius:15px;display:flex;align-items:center;gap:5px;font-size:15px;font-weight:500;letter-spacing:-.3px;box-shadow:inset 0 0 0 1px #E2E2E4}
      .chips span.k{box-shadow:none;background:#EEEEEF}
      .chips span .bm{color:var(--ac);display:flex}
      .chips span .bm svg{color:var(--ac)}
      .chips span svg{color:var(--gr);display:block}
      .e{display:flex;align-items:flex-start;gap:8px;padding:8px 16px}
      .e .mk{margin-top:1px}
      .e .x{flex:1;font-size:15px;line-height:17.9px;letter-spacing:-.25px;padding-top:1px}
      .e .cr2{margin-top:2.5px}
      .sl{display:flex;align-items:flex-start;gap:12px;padding:9.7px 20px}
      .sl .mk{margin-top:-.5px}
      .sl .x{flex:0 1 226px;margin-right:auto;font-size:15px;line-height:19.9px;letter-spacing:-.25px}
      .sl.ln .x{padding-top:.6px}
      .sl .cr2{margin-top:3px}
      .sl .bs{flex:0 0 auto;margin-top:2.5px;font-size:12px;line-height:16px;font-weight:600;font-variant-numeric:tabular-nums;color:var(--sec)}
      .sl .bs.on{color:var(--gr)}
      .sl .x .was{display:block;color:var(--sec);text-decoration:line-through;text-decoration-thickness:1px}
      .sl .x .now{display:block;margin-top:2px}
      .sl .x .now b{color:var(--ac);font-weight:600}
      .sl .x .why{display:block;margin-top:2.6px;font-size:12px;line-height:14.3px;color:var(--sec);letter-spacing:-.1px}
      .gpd{padding-top:16px}
      .run{margin:16px 20px 0;height:50.3px;border-radius:26px;background:var(--ac);color:#fff;display:flex;align-items:center;justify-content:center;gap:8px;font-size:17px;letter-spacing:-.4px;transition:filter .15s}
      .run.press{filter:brightness(.85)}
      .dvr{height:.33px;background:#C6C6C8;margin:12px 0 0 20px}
      .tapc{position:absolute;width:56px;height:56px;margin:-28px 0 0 -28px;border-radius:50%;background:rgba(0,0,0,.12);transform:scale(.4);opacity:0;z-index:9;pointer-events:none;transition:transform .3s,opacity .3s}
      .tapc.on{transform:scale(1);opacity:1}
    `, `
      <div class="gl back" hidden>${SF.chevL}</div><div class="navt"></div><div class="gl done"></div><div class="gl more" hidden>${SF.ellipsisC}</div>
      <div class="rib"></div>
      <div class="pg"><div class="pc"></div></div>
      <div class="tapc"></div>`);
    this._book = JOB; this._browsing = false; this._pushed = false; this._ch = "cover"; this._runRow = false;
  }
  get L() { return this.t === STR.ko ? L.ko : L.en; }
  get lang() { return this.t === STR.ko ? "ko" : "en"; }
  /* the book's material; a partial object is merged over the capture's book */
  set book(b) { this._book = { ...JOB, ...b }; if (this._built) this._render(); }
  get book() { return this._book; }
  /* pushed from Review (browsing): back · the talk's title · ⋯, and Continue beside Replay.
     Off = post-talk (the capture's cover): "Review book" · Done. */
  set browsing(v) { this._browsing = !!v; if (this._built) this._render(); }
  get browsing() { return this._browsing; }
  /* the Drill chapter's "Review this talk" run — only when the talk minted cards (the capture's had none) */
  /* the back button: the page was pushed (from Review's shelf); the captures open it at the root */
  set pushed(v) { this._pushed = !!v; if (this._built) this._nav(); }
  /* a coach-mode call (`Session.coached`): ConversationDetailView draws practiceBlock in place of the
     score, and the shelf card drops its score ring. Attribute `coached`, or `book.coached`. */
  get coached() { return this.hasAttribute("coached") || !!this._book.coached; }
  /* is a chapter item mastered? Credited-by-this-talk ("here") items are not, on a coached call */
  _on(state) { return !!state && !(state === "here" && this.coached); }
  /* a Shadow row: "text" or [text, best]; mastered at the shadow bar */
  _shOn(x) { return Array.isArray(x) && x[1] >= SHADOW_BAR; }
  /* the Words / Expressions ribbon counts and the cover's bar, from the items' states */
  _tabs() {
    const b = this._book, t = { ...b.tabs }, on = a => a.filter(x => this._on(Array.isArray(x) ? x[1] : false)).length;
    const ex = [...b.offered, ...b.used];
    t.words = [on(b.words), b.words.length]; t.expressions = [on(ex), ex.length];
    t.shadow = [b.shadow.filter(x => this._shOn(x)).length, b.shadow.length];
    t.drill = [b.drill.filter(d => d.done).length, b.drill.length];   // a correction's card at the top box, or a passing Say-it-again read
    const done = Object.values(t).reduce((n, c) => n + c[0], 0), total = Object.values(t).reduce((n, c) => n + c[1], 0);
    return { t, done, total };
  }
  set showRun(v) { this._runRow = !!v; if (this._built) this._render(); }
  build() { this._render(); }

  _nav() {
    const L = this.L, b = this._book, post = !this._browsing;
    this.$(".navt").textContent = post && this._ch === "cover" ? L.book : b.title;
    this.$(".back").hidden = post || !this._pushed;
    this.$(".done").hidden = !post || this._ch !== "cover"; this.$(".done").textContent = L.done;
    this.$(".more").hidden = !this.$(".done").hidden;
  }
  _ribbons() {
    const t = this._tabs().t;
    this.$(".rib").innerHTML = ORDER.map(id => {
      const c = t[id], on = id === this._ch;
      const cnt = !c ? "" : c[0] === c[1] ? `<small class="ok">✓</small>` : `<small>${c[0]}/${c[1]}</small>`;
      return `<div class="rb${on ? " on" : ""}" data-id="${id}"><span class="ig">${ICONS[id]()}</span>${cnt}</div>`;
    }).join("");
  }
  _render() { this._nav(); this._ribbons(); this.$(".pc").innerHTML = this._page(this._ch); }

  _page(id) {
    const L = this.L, b = this._book, lg = this.lang, mk = on => `<span class="mk${on ? " on" : ""}">${on ? SF.circleOn : SF.circle}</span>`;
    const chev = `<span class="cr2">${SF.chevR}</span>`;
    if (id === "words") {
      return `<div class="ttl">${L.words}</div>` +
        b.words.map(([w, m], i) => { const on = this._on(m); return (i ? `<div class="wd"></div>` : "") + `<div class="w row">${mk(on)}<span class="x${on ? " m" : ""}">${esc(w)}</span>${chev}</div>`; }).join("") +
        (b.mine.length ? `<div class="wd f"></div><div class="gl2">${L.firstWords}</div><div class="chips">${b.mine.map(([w, s]) => `<span class="${s ? "k" : ""}">${s === "studying" ? `<i class="bm">${SF.bookmarkFill}</i>` : s ? SF.checkFill : ""}${esc(w)}</span>`).join("")}</div>` : "") +
        `<div style="height:6px"></div><div class="ft">${esc(L.fWords)}</div>`;
    }
    if (id === "expressions") {
      const row = e => { const [x, st] = Array.isArray(e) ? e : [e]; return `<div class="e row">${mk(this._on(st))}<span class="x">${esc(x)}</span>${chev}</div>`; };
      return `<div class="ttl">${L.expressions}</div>` +
        (b.offered.length ? `<div class="gl2">${L.fromSelf}</div>${b.offered.map(row).join("")}` : "") +
        (b.used.length ? `${b.offered.length ? `<div class="wd f"></div>` : ""}<div class="gl2">${L.youSaid}</div>${b.used.map(row).join("")}` : "") +
        `<div style="height:8px"></div><div class="ft">${esc(L.fExpr)}</div>`;
    }
    if (id === "shadow") {
      return `<div class="ttl">${L.shadow}</div>` +
        b.shadow.map(x => this._shRow(x)).join("") +
        `<div style="height:4px"></div><div class="ft">${esc(L.fShadow)}</div>`;
    }
    if (id === "drill") {
      return `<div class="ttl">${L.drill}</div><div class="gp" style="padding-bottom:6px">${SF.sparkles}<span>${L.better}</span></div>` +
        b.drill.map(d => `<div class="sl row">${mk(!!d.done)}<span class="x"><span class="was">${esc(d.was)}</span><span class="now">${d.now}</span><span class="why">${esc(d.why[lg])}</span></span>${chev}</div>`).join("") +
        `<div class="ft" style="padding-top:7.6px">${esc(L.fDrill)}</div>` +
        (this._runRow ? `<div class="dvr"></div><div class="run">${SF.stack}<span>${L.reviewTalk}</span></div><div class="ft">${esc(L.fRun)}</div>` : "") +
        `<div style="height:4px"></div>`;
    }
    /* the cover */
    const col = s => s >= 80 ? "var(--gr)" : "var(--ac)";
    const pron = b.pron ? `<div class="ax"><div class="h ps"><span class="gi">${SF.micWave}</span><span>${L.pron}</span><span class="n" style="color:${col(b.pron[0])}">${b.pron[0]}</span></div>
      <div class="nt">${esc(b.pron[1]?.[lg] ?? b.pron[1])}</div></div>` : "";
    const ax = ([ic, name, s, note, slips], i) => `<div class="ax${i ? "" : " f1"}"><div class="h">${ic === "abc" ? `<span class="gi t">${L.abc}</span>` : `<span class="gi">${SF[ic]}</span>`}<span>${name}</span><span class="n" style="color:${col(s)}">${s}</span>${slips ? `<span class="cr">${SF.chevR}</span>` : ""}</div>
      <div class="bar"><i style="width:${s}%;background:${col(s)}"></i></div><div class="nt">${esc(note?.[lg] ?? note)}</div>${slips ? `<div class="lk">${L.slips(slips)}</div>` : ""}</div>`;
    return `<div class="cv"><div class="hd"><span class="av">${SF.bubbles(30.7, 25.2)}</span><div class="tt"><b>${esc(b.title)}</b><span>${esc(L.turns(b.date[lg], b.turns))}</span></div></div>
        ${(() => { const { done, total } = this._tabs(); return `<div class="pr"><i style="width:${done / total * 100}%"></i></div><div class="pn">${L.mastered(done, total)}</div>`; })()}
        <div class="bts">${this._browsing ? `<div class="two"><span class="bt pro">${SF.bubbles(19, 15.6)}${L.cont}</span><span class="bt rp">${SF.play}${L.replay}</span></div>` : `<span class="bt rp">${SF.play}${L.replay}</span>`}
          <span class="bt">${SF.viewfinder}${L.again}</span></div></div>
      <div class="dv" style="margin-top:20px"></div>
      ${this.coached ? `<div class="gp">${SF.lightbulb}<span>${L.practice}</span></div><div class="pnote">${esc(L.practiceNote)}</div>` : `<div class="gp">${SF.chartBar}<span>${L.score}</span></div>
      <div class="sc"><div class="ov"><span>${L.overall}</span><b>${b.overall}</b></div><div class="cx">${esc(L.context)}</div>
        <div class="tl">${esc(b.topLine?.[lg] ?? b.topLine)}</div>${b.axes.map(ax).join("")}${pron}</div>`}
      ${this.coached && b.focus ? `<div class="dv t"></div><div class="gp">${SF.scope()}<span>${L.focus}</span></div>
        <div class="fo"><span class="fi${b.focus.repeats ? "" : " ok"}">${b.focus.repeats ? SF.scope(21) : SF.sealFill}</span><div class="fv"><b>${esc(b.focus.label?.[lg] ?? b.focus.label)}</b>
          <span class="pair"><s>${esc(b.focus.was)}</s><i>${SF.arrowR}</i><span>${esc(b.focus.now)}</span></span>
          <span class="rs${b.focus.repeats ? "" : " ok"}">${b.focus.repeats ? L.focusBack(b.focus.repeats) : L.focusClean}</span></div></div>` : ""}
      ${b.note ? `<div class="dv t"></div><div class="gp">${SF.textBubble}<span>${L.note}</span></div><div class="cn">${esc(b.note?.[lg] ?? b.note)}</div>` : ""}
      ${b.carry?.length ? `<div class="gp">${SF.target}<span>${L.carried}</span></div>${b.carry.map(c => `<div class="co"><div class="ci"><span>${SF.circleOn}</span><span>${esc(c.item)}</span></div>
        <div class="q">“${esc(c.quote)}”</div><div class="og"><span>${SRC_ICON[c.src] ?? ""}${esc(L.src[c.src] ?? c.src)}</span><i>${SF.playCircle}</i></div></div>`).join("")}
        <div class="ft">${esc(L.fCarry)}</div>` : ""}
      <div style="height:16px"></div>`;
  }

  /* ConversationDetailView.shadowPage: mark · the line (primary, mastered or not) · best score (green at
     the bar, secondary under it) · chevron */
  _shRow(x) {
    const [text, best] = Array.isArray(x) ? x : [x], on = this._shOn(x);
    const mk = `<span class="mk${on ? " on" : ""}">${on ? SF.circleOn : SF.circle}</span>`;
    return `<div class="sl ln row">${mk}<span class="x">${esc(text)}</span>${best != null ? `<span class="bs${on ? " on" : ""}">${best}</span>` : ""}<span class="cr2">${SF.chevR}</span></div>`;
  }
  /** A take on Shadow row i scored `score` (back from <nw-shadow>): the row takes its best score and,
   *  at 80 or more, the green check; the ribbon count and the cover's bar follow. */
  async shadowTake(i, score) {
    const b = this._book, x = b.shadow[i]; if (x == null) return;
    const [text, best] = Array.isArray(x) ? x : [x];
    const sh = b.shadow.slice(); sh[i] = [text, Math.max(best ?? 0, score)];
    this._book = { ...b, shadow: sh };
    this._ribbons();
    if (this._ch === "shadow") { const row = this.$$(".pc .row")[i]; if (row) row.outerHTML = this._shRow(sh[i]); }
    else if (this._ch === "cover") this.$(".pc").innerHTML = this._page("cover");
    await this.sleep(300);
  }

  reset() { this._ch = "cover"; if (this._built) { this._render(); this.$(".pc").classList.remove("out"); this.$(".pc").style.transform = ""; } }
  async pose(name) {
    this.stop();
    this._browsing = name !== "cover"; this._pushed = false; this._runRow = false; this._book = JOB;
    this._ch = name === "cover" ? "cover" : name; this._render();
  }

  async _tap(x, y) { const t = this.$(".tapc"); t.style.left = x + "px"; t.style.top = y + "px"; t.classList.add("on"); await this.sleep(240); t.classList.remove("on"); }
  _center(el) { const r = el.getBoundingClientRect(), me = this.$(".s").getBoundingClientRect(), k = me.width / 402; return [(r.left + r.width / 2 - me.left) / k, (r.top + r.height / 2 - me.top) / k]; }
  /** Tap a ribbon: the ribbon takes the page's paper (0.15 s ease-out, as the app animates the
   *  selection) and the page's content swaps in place. */
  async open(chapter) {
    const id = chapter === "lines" ? "shadow" : chapter === "cards" ? "drill" : chapter === "intro" ? "cover" : chapter;
    const rb = this.$(`.rb[data-id="${id}"]`); if (!rb || id === this._ch) return;
    await this._tap(...this._center(rb));
    this._ch = id;
    this.$$(".rb").forEach(r => r.classList.toggle("on", r.dataset.id === id));
    const pc = this.$(".pc"); pc.classList.add("out");
    await this.sleep(RM ? 0 : 160);
    this._nav(); pc.innerHTML = this._page(id); pc.style.transform = "";
    pc.classList.remove("out");
    await this.sleep(300);
  }
  /** Press row i of the open chapter (word, expression, shadow line, correction — or "run" for
   *  Review this talk, "replay"/"again" on the cover). Resolves after the highlight. */
  async tapLine(i) {
    const el = i === "run" ? this.$(".run") : i === "replay" ? this.$(".bt.rp") : i === "again" ? this.$$(".bt")[this.$$(".bt").length - 1] : this.$$(".pc .row")[i];
    if (!el) return;
    el.classList.add("press"); await this._tap(...this._center(el));
    await this.sleep(120); el.classList.remove("press");
  }
  /** Scroll the open page (points, positive = down). */
  async scrollTo(y, ms = 700) { const pc = this.$(".pc"); pc.style.transition = `transform ${ms}ms cubic-bezier(.3,.8,.2,1)`; pc.style.transform = `translateY(${-y}px)`; await this.sleep(ms); pc.style.transition = ""; }

  /** Drill row i mastered (its card at the top box, or a passing Say-it-again read of that fix —
   *  the book recomputes on the cover's dismiss): the green check, the ribbon count, the cover's bar. */
  async drillDone(i) {
    const b = this._book; if (!b.drill[i] || b.drill[i].done) return;
    const dr = b.drill.slice(); dr[i] = { ...dr[i], done: true };
    this._book = { ...b, drill: dr };
    this._ribbons();
    if (this._ch !== "shadow" && this._ch !== "words" && this._ch !== "expressions") this.$(".pc").innerHTML = this._page(this._ch);
    await this.sleep(300);
  }
  /** Press "Say it again" on the cover. Given `cover` (an element laid over this book in the same
   *  phone, e.g. <nw-sayagain fill>), it is presented the way ConversationDetailView does it, a
   *  fullScreenCover: slides up from the bottom edge. `closeCover(cover)` slides it back down. */
  async sayItAgain(cover) {
    if (this._ch !== "cover") await this.open("cover");
    if (cover) { cover.style.transition = "none"; cover.style.transform = "translateY(100%)"; cover.style.visibility = "hidden"; }
    await this.tapLine("again");
    if (!cover) return;
    void cover.offsetWidth;
    cover.style.visibility = ""; cover.style.transition = RM ? "none" : "transform .5s cubic-bezier(.32,.72,0,1)"; cover.style.transform = "translateY(0)";
    await this.sleep(520);
  }
  async closeCover(cover) {
    if (!cover) return;
    cover.style.transition = RM ? "none" : "transform .42s cubic-bezier(.32,.72,0,1)"; cover.style.transform = "translateY(100%)";
    await this.sleep(440); cover.style.visibility = "hidden";
  }

  async demo() {
    this._browsing = true; this._pushed = true; this._render();
    await this.sleep(1400);
    await this.open("words"); await this.sleep(1600);
    await this.open("expressions"); await this.sleep(1600);
    await this.open("drill"); await this.sleep(1800);
    await this.open("shadow"); await this.sleep(1200);
    await this.tapLine(0); await this.sleep(900);
    await this.open("cover"); await this.sleep(1200);
  }
}

export { NwBookPage };
