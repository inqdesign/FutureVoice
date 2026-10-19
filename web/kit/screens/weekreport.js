/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js.
 *
 * <nw-weekreport> — "Your week" (한 주 돌아보기): WeekRecapSheet's story deck and
 * WeekRecapArchiveView's list. Layout in iOS points from the SwiftUI source; the week is
 * DebugCaptureHarness.sampleWeekRecap (the data the simulator captures were taken with).
 *
 *   el.sample = "interview"  (or attribute sample="interview")  the interview week (marketing series 07)
 *   el.week = {...}          merge over the week (shape: WEEK below; `coachKo` = the coaching in Korean,
 *                            `dates` = {ko:{range, range2, arrives, ready}, en:{…}})
 *   await el.next() · el.go(i) · await el.scrollCard(px) · await el.remind() · await el.startTest()
 *   el.pose("week" | "talk" | "used" | … | "test" | "quiet" | "archive") */
import { NwScreen, STR, esc } from "../core.js";

/* SF Symbols, traced in a 24-unit box. */
const SF = {
  calendar: '<rect x="2.6" y="3.6" width="18.8" height="17" rx="3.4" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M2.6 7a3.4 3.4 0 0 1 3.4-3.4h12a3.4 3.4 0 0 1 3.4 3.4v2.2H2.6z" fill="currentColor"/>' +
    [8.2, 11, 13.8, 16.6].map(x => [12.4, 15, 17.6].map(y => (x === 8.2 && y === 12.4) ? "" : `<circle cx="${x}" cy="${y}" r=".95" fill="currentColor"/>`).join("")).join(""),
  check: '<path d="M5.5 12.6l4.2 4.2 8.8-9.6" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>',
  flame: '<path fill="currentColor" fill-rule="evenodd" d="M12.4 1.8c.4 3.1 2.3 4.7 4 6.6 1.6 1.8 3 3.8 3 6.7 0 4.2-3.2 7.1-7.3 7.1S4.6 19.4 4.6 15.4c0-2.5 1.1-4.4 2.5-5.9.3-.3.8-.1.8.3.1 1.2.6 2.3 1.4 2.9-.2-4.5 1-8.3 3.1-10.9zM12.2 13c-1.6 1.6-2.7 3.1-2.7 4.9 0 1.6 1.2 2.8 2.7 2.8s2.7-1.2 2.7-2.8c0-1.8-1-3.3-2.7-4.9z"/>',
  waveform: '<path d="M2.5 10.6v2.8M5.5 8.6v6.8M8.5 5v14M11.5 2.6v18.8M14.5 6.6v10.8M17.5 9v6M20.5 10.8v2.4" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
  seal: (() => { let d = ""; const n = 8; for (let i = 0; i <= n * 2; i++) { const a = Math.PI * i / n - Math.PI / 2, r = i % 2 ? 7.6 : 10; d += `${i ? "L" : "M"}${(12 + r * Math.cos(a)).toFixed(2)} ${(12 + r * Math.sin(a)).toFixed(2)}`; } return d + "Z"; })(),
  stack: '<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><rect x="3" y="9" width="18" height="12" rx="2.6"/><path d="M5.2 6.2h13.6M7.2 3.4h9.6"/></g>',
  sparkles: '<path fill="currentColor" d="M11 6.5c.7 4.6 2.6 6.6 7.3 7.3-4.7.7-6.6 2.6-7.3 7.3-.7-4.7-2.6-6.6-7.3-7.3 4.7-.7 6.6-2.7 7.3-7.3zM5.4 2.6c.3 1.9 1 2.6 2.9 2.9-1.9.3-2.6 1-2.9 2.9-.3-1.9-1-2.6-2.9-2.9 1.9-.3 2.6-1 2.9-2.9zM17.6 1.2c.2 1.2.6 1.6 1.8 1.8-1.2.2-1.6.6-1.8 1.8-.2-1.2-.6-1.6-1.8-1.8 1.2-.2 1.6-.6 1.8-1.8z"/>',
  xmark: '<path d="M5.5 5.5l13 13M18.5 5.5l-13 13" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/>',
  hourglass: '<g fill="currentColor"><rect x="5" y="2.2" width="14" height="2.4" rx="1"/><rect x="5" y="19.4" width="14" height="2.4" rx="1"/><path d="M6.8 4.6h10.4c0 3.4-2.6 5.6-3.8 7.4 1.2 1.8 3.8 4 3.8 7.4H6.8c0-3.4 2.6-5.6 3.8-7.4-1.2-1.8-3.8-4-3.8-7.4zm2.4 1.8c.5 1.8 2.8 3.3 2.8 4.6 0-1.3 2.3-2.8 2.8-4.6zM8.6 18h6.8c-.6-1.8-3.4-3.2-3.4-4.6 0 1.4-2.8 2.8-3.4 4.6z" fill-rule="evenodd"/></g>',
  chevron: '<path d="M9 4.5l7.5 7.5L9 19.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
  person: '<g fill="currentColor"><circle cx="12" cy="7.6" r="4.4"/><path d="M3.6 20.4c.6-4.4 4-7 8.4-7s7.8 2.6 8.4 7c.1.6-.3 1-.9 1H4.5c-.6 0-1-.4-.9-1z"/></g>',
  masks: '<g fill="currentColor"><path d="M2.5 4.5c3-1.4 7-1.4 10 0v6.2c0 3.6-2.2 6.4-5 6.4s-5-2.8-5-6.4z"/><path d="M11.6 9.2c3.2-1.2 7-.9 9.9.7l-.9 6c-.6 3.6-3.2 6-5.9 5.6-1.7-.3-3-1.6-3.6-3.4" opacity=".8"/></g>',
  news: '<g fill="currentColor"><path d="M5 3.5h12.5c.8 0 1.5.7 1.5 1.5v14.5c0 .8.7 1.5 1.5 1.5H5.5c-1.4 0-2.5-1.1-2.5-2.5V5.5c0-1.1.9-2 2-2z"/><path d="M19.6 8.5h.9c.8 0 1.5.7 1.5 1.5v9.5c0 .8-.7 1.5-1.5 1.5"/></g><g fill="#fff"><rect x="6" y="6.5" width="5" height="4.5" rx=".6"/><rect x="12.5" y="7" width="3.8" height="1.3" rx=".6"/><rect x="12.5" y="9.6" width="3.8" height="1.3" rx=".6"/><rect x="6" y="13" width="10.3" height="1.3" rx=".6"/><rect x="6" y="15.8" width="10.3" height="1.3" rx=".6"/></g>',
  stackFill: '<g fill="currentColor"><rect x="3" y="9" width="18" height="12.4" rx="2.6"/><rect x="5" y="5.4" width="14" height="2" rx="1"/><rect x="7" y="2.4" width="10" height="1.8" rx=".9"/></g>',
  waveMic: '<path d="M2.5 10.6v2.8M5.5 8v8M8.5 4.6v14.8M11.5 7.6v8.8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><rect x="15.4" y="9" width="4.6" height="8.6" rx="2.3" fill="currentColor"/><path d="M13.6 15.2a4.1 4.1 0 0 0 8.2 0M17.7 19.3v2.2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  playRect: '<rect x="2.6" y="4.6" width="18.8" height="14.8" rx="3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M10 8.8v6.4l5.4-3.2z" fill="currentColor"/>',
  stackPlus: '<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><rect x="2.6" y="9" width="15.4" height="12" rx="2.6"/><path d="M4.6 6.2h11.4M6.6 3.4h7.4M20 2.6v6.2M16.9 5.7h6.2"/></g>',
  cycle: '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.6 10.4A7.6 7.6 0 0 1 18 7.2M19.4 13.6A7.6 7.6 0 0 1 6 16.8"/><path d="M18.8 3.4v4.4h-4.4M5.2 20.6v-4.4h4.4"/></g>',
  checklist: '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2.8 5.6l1.8 1.8 3.4-3.6M2.8 12.4l1.8 1.8 3.4-3.6M2.8 19.2l1.8 1.8 3.4-3.6M11 6h10.2M11 12.8h10.2M11 19.6h10.2"/></g>',
  textCheck: '<g fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M2.6 6h13M2.6 11h9M2.6 16h6"/></g><circle cx="17" cy="16.4" r="5.4" fill="currentColor"/><path d="M14.6 16.4l1.7 1.7 3.1-3.3" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
  bulb: '<path d="M9 17.6h6M9.8 20.6h4.4M12 2.6a6.4 6.4 0 0 0-3.8 11.6c.6.5 1 1.2 1 2V16h5.6v-.8c0-.8.4-1.5 1-2A6.4 6.4 0 0 0 12 2.6z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
  upFwd: '<circle cx="12" cy="12" r="10.4" fill="currentColor"/><path d="M9 15l6.4-6.4M10 8.6h5.4V14" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>',
  arrowR: '<path d="M3.5 12h16M13.5 5.5l6.5 6.5-6.5 6.5" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>',
  arrowUpR: '<path d="M6 18L18 6M8.4 6H18v9.6" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>',
  quote: '<path fill="currentColor" d="M5.4 2.6h13.2a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3h-7.2l-5 3.8c-.5.4-1.2 0-1.2-.6v-3.2h.2a3 3 0 0 1-3-3v-9a3 3 0 0 1 3-3z"/><path fill="#fff" d="M8.2 7.2h2.4v2.6c0 1.6-.8 2.8-2.2 3.2l-.3-.8c.7-.3 1-.8 1-1.4H8.2zm5 0h2.4v2.6c0 1.6-.8 2.8-2.2 3.2l-.3-.8c.7-.3 1-.8 1-1.4h-.9z"/>',
  checkCircle: '<circle cx="12" cy="12" r="10.6" fill="none" stroke="currentColor" stroke-width=".9"/><path d="M7.4 12.4l3.2 3.2 6-6.6" fill="none" stroke="currentColor" stroke-width=".95" stroke-linecap="round" stroke-linejoin="round"/>',
  bell: '<path d="M12 2.8a6 6 0 0 0-6 6v4.6l-1.8 2.8c-.4.6 0 1.4.8 1.4h14c.8 0 1.2-.8.8-1.4L18 13.4V8.8a6 6 0 0 0-6-6zM9.4 19.4a2.7 2.7 0 0 0 5.2 0" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>',
  bellFill: '<path fill="currentColor" d="M12 2.8a6 6 0 0 0-6 6v4.6l-1.8 2.8c-.4.6 0 1.4.8 1.4h14c.8 0 1.2-.8.8-1.4L18 13.4V8.8a6 6 0 0 0-6-6zM9.2 19.2h5.6a2.8 2.8 0 0 1-5.6 0z"/>',
};
const sf = (n, cls = "sf") => {
  if (n === "sealCheck") return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${SF.seal}" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M8.4 12.2l2.4 2.4 4.8-5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  if (n === "sealFill") return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${SF.seal}" fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M8.4 12.2l2.4 2.4 4.8-5" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${SF[n]}</svg>`;
};

/* ── the week (sampleWeekRecap: Sat Oct 3 – Fri Oct 9) ── */
const WEEK = {
  /* Sat Sun · · Wed Thu Fri — 5 of 7, and the run at the week's end is Wed–Fri, so "3-day streak" is true */
  activeDays: [1, 1, 0, 0, 1, 1, 1], streak: 3, talkMin: 42, prevMin: 28,
  talks: [["Moving flats in Berlin", 0, 12, "waveform"], ["Asking the landlord about the deposit", 1, 7, "masks"],
    ["Why rents keep rising", 4, 9, "news"], ["Catching up with Jenny", 5, 8, "person"], ["The weekend plan", 6, 6, "waveform"]],
  used: [["end up", "I ended up carrying most of the boxes myself."], ["push back on", "I pushed back on the deadline a little."],
    ["chore", "Cleaning the kitchen is my least favourite chore."]], usedCount: 4,
  nowYours: ["deposit", "landlord", "sublet", "boiler", "catch up on", "chore", "exhausting", "end up"],
  sentencesGot: ["I ended up carrying most of the boxes myself.", "I've lived here for two years."],
  shadowTakes: 17, shadowAvg: 81, prevShadowAvg: 74, scenes: 3,
  newCount: 7, newExpr: [["catch up on", "You can always catch up on the unpacking later."],
    ["walk you through", "Let me walk you through what the landlord actually needs."],
    ["give yourself a day off", "Honestly, give yourself a day off after the move."]], newCards: 6,
  stumbles: [["I end up carrying", "I ended up carrying", 3], ["since two years", "for two years", 2]], testScore: 5, testTotal: 7,
  coach: {
    headline: "You tell stories, but in the present tense",
    insight: "When you talk about something that already happened, you slip back into the present as the story goes on. It starts in the past and ends in the present.",
    insightQuote: "Yesterday I went to the flat and the landlord says it's fine.",
    grammar: [
      { rule: "Past tense drops out halfway through a story",
        ex: [["the landlord says it's fine", "the landlord said it was fine"], ["I end up carrying", "I ended up carrying"], ["then she ask me", "then she asked me"]],
        tip: "Once a story starts with “yesterday” or “last week”, every verb stays in the past until it ends." },
      { rule: "“the” before a place you both know", ex: [["went to kitchen", "went to the kitchen"], ["called landlord", "called the landlord"]],
        tip: "If you could point at it, it takes “the”." }],
    upgrades: [
      { instead: "very tired", count: 5, better: "exhausted", original: "I was very tired after the move.", rewritten: "I was exhausted after the move.",
        note: "One word does the work of two. Use it when tired isn't strong enough." },
      { instead: "good", count: 9, better: "decent", original: "The flat is good for the price.", rewritten: "The flat is decent for the price.",
        note: "Good, but not great: exactly what you meant about the flat." }],
    plan: ["Tell the story of the move again, and keep every verb in the past until the end.",
      "Say “exhausted” once in your next talk instead of “very tired”.", "Take this week's test. The two you missed are back."],
  },
};

/* The coach's prose is COACHING, so it is written in the learner's native language (CoachingLanguage);
   the quoted lines and the words stay English — they are the learner's own material. */
const COACH_KO = {
  headline: "이야기는 잘 하는데, 시제가 자꾸 현재로 돌아와요",
  insight: "이미 지난 일을 말할 때 이야기가 길어지면 현재형으로 돌아가요. 과거로 시작해서 현재로 끝나요.",
  rules: [["이야기 중간에 과거형이 빠져요", "“yesterday”나 “last week”로 시작한 이야기는 끝날 때까지 동사를 과거형으로 두세요."],
    ["둘 다 아는 장소 앞에는 “the”", "손가락으로 가리킬 수 있는 곳이면 “the”를 붙여요."]],
  notes: ["두 단어가 하던 일을 한 단어가 해요. tired로는 모자랄 때 쓰세요.", "좋지만 아주 좋지는 않은, 딱 그 집에 대해 하려던 말이에요."],
  plan: ["이사 이야기를 한 번 더 해 보세요. 끝날 때까지 동사는 전부 과거형으로요.",
    "다음 대화에서 “very tired” 대신 “exhausted”를 한 번 써 보세요.", "이번 주 테스트를 풀어 보세요. 틀렸던 두 문제가 다시 나와요."],
};
WEEK.coachKo = COACH_KO;
const coachFor = (ko, w = WEEK) => { const K = w.coachKo; return ko && K ? {
  ...w.coach, headline: K.headline, insight: K.insight, plan: K.plan,
  grammar: w.coach.grammar.map((g, i) => ({ ...g, rule: K.rules[i]?.[0] ?? g.rule, tip: K.rules[i]?.[1] ?? g.tip })),
  upgrades: w.coach.upgrades.map((u, i) => ({ ...u, note: K.notes[i] ?? u.note })),
} : w.coach; };

/* The interview week (marketing series 07): Sat Oct 10 – Fri Oct 16, the week of the book's "How the
 * interview went" talk. Quoted lines are the learner's own from the series (pieces 01/03/05); numbers are
 * sample data. "took the initiative" is NOT in Used: it was said in a coached call, which credits nothing. */
const INTERVIEW = {
  activeDays: [1, 0, 0, 1, 1, 1, 1], streak: 4, talkMin: 42, prevMin: 28, prevDays: 3,
  talks: [["How the interview went", 0, 12, "waveform"], ["Job interview · panel round", 3, 9, "masks"],
    ["Why companies hire for soft skills", 4, 8, "news"], ["Good news", 6, 13, "waveform"]],
  used: [["compelling", "Yes! I got the job. They said my story was compelling."],
    ["prioritize", "I'll prioritize learning the team's tools first."]], usedCount: 2,
  nowYours: ["perspective", "initiative", "compelling", "prioritize", "felt prepared", "walk you through"],
  sentencesGot: ["Honestly, it went really well. I felt prepared.", "I took the initiative and told a real story."],
  shadowTakes: 9, shadowAvg: 84, prevShadowAvg: 76, scenes: 2,
  newCount: 3, newExpr: [["prioritize what matters", "You clearly took the initiative and prioritized what mattered."],
    ["walk you through", "Let me walk you through how the panel round usually goes."],
    ["put me at ease", "The first question really put me at ease."]], newCards: 4,
  stumbles: [["it go really well", "it went really well", 3], ["tell a real story", "told a real story", 2]], testScore: 6, testTotal: 7,
  coach: {
    headline: "You tell the story well, but the past tense slips away",
    insight: "When you talk about something that already happened, the verbs fall back into the present partway through.",
    insightQuote: "They call me yesterday.",
    grammar: [
      { rule: "Past tense drops out of a story",
        ex: [["it go really well", "it went really well"], ["tell a real story", "told a real story"], ["They call me yesterday", "They called me yesterday"]],
        tip: "Once a story is about yesterday or last week, every verb stays in the past until it ends." }],
    upgrades: [
      { instead: "very happy", count: 4, better: "thrilled", original: "I was very happy when they called.", rewritten: "I was thrilled when they called.",
        note: "One word does the work of two, and it sounds like you mean it." }],
    plan: ["Tell the interview story again, and keep every verb in the past until the end.",
      "Say “thrilled” once in your next talk instead of “very happy”.", "Take this week's test. The one you missed comes back."],
  },
  coachKo: {
    headline: "이야기는 잘 풀어내는데, 과거형이 자꾸 빠져요",
    insight: "이미 지난 일을 말하다 보면 중간부터 동사가 현재형으로 돌아가요.",
    rules: [["이야기 중간에 과거형이 빠져요", "어제나 지난주 이야기라면 끝날 때까지 동사를 과거형으로 두세요."]],
    notes: ["두 단어가 하던 일을 한 단어가 해요. 진심으로 기뻤다는 게 들려요."],
    plan: ["면접 이야기를 한 번 더 해 보세요. 끝날 때까지 동사는 전부 과거형으로요.",
      "다음 대화에서 “very happy” 대신 “thrilled”를 한 번 써 보세요.", "이번 주 테스트를 풀어 보세요. 틀렸던 문제가 다시 나와요."],
  },
  dates: {
    ko: { range: "10월 10일 – 10월 16일", range2: "10월 3일 – 10월 9일", arrives: "다음 돌아보기는 10월 24일 (토)에 도착해요", ready: "10월 24일 (토)에 정리돼요" },
    en: { range: "Oct 10 – Oct 16", range2: "Oct 3 – Oct 9", arrives: "Next week's arrives Sat, Oct 24", ready: "Ready Sat, Oct 24" },
  },
};
const SAMPLES = { interview: INTERVIEW };

/* Chrome from Localizable.xcstrings (ko) and the source's English keys. */
const L = {
  ko: {
    title: "한 주 돌아보기", range: "10월 3일 – 10월 9일", wd: ["토", "일", "월", "화", "수", "목", "금"], next: "다음",
    lastWeek: "지난주", of7: "/ 7일", cover: "거의 매일 했어요. 리듬이 생겼어요.", quiet: "쉬어 간 한 주",
    quietSub: "그런 주도 있어요. 대화 한 번이면 다시 시작이에요.", streak: n => `${n}일 연속`,
    sTalk: (m, n) => `${m}분 대화 · ${n}번`, sUsed: n => `공부한 것 ${n}개를 직접 말했어요`,
    sYours: n => `단어·표현 ${n}개가 내 것이 됐어요`, sNew: n => `유창해진 나에게 받은 새 표현 ${n}개`,
    talks: "통화", min: "분", more: n => `지난주보다 ${n}분 더 했어요`, talkSub: (d, m) => `${d} · ${m}분`,
    usedK: "연습한 걸 실제로 썼어요", usedT: "공부했던 걸 실제 대화에서 내 입으로 꺼냈어요.",
    practice: "복습", yoursT: "이번 주에 내 것이 된 단어와 표현이에요.", got: n => `입에 붙은 문장 ${n}개`,
    takes: n => `섀도잉 ${n}번`, avg: n => `평균 ${n}점`, scenes: n => `상황연습 ${n}개를 봤어요`,
    freshK: "유창해진 내가 쓴 새 표현", freshT: "유창해진 나는 말했지만, 나는 아직 안 써본 표현이에요.",
    waiting: "표현 목록에 담아뒀어요.", cards: n => `고친 문장으로 복습 카드 ${n}장이 생겼어요`,
    stuckK: "자주 막힌 곳", stuckT: "같은 부분을 계속 고쳤어요. 한 번만 더 보면 내 것이 돼요.",
    lastTest: (s, t, m) => `지난 테스트 ${s}/${t}. 틀린 ${m}문제는 이번 주에 다시 나와요.`,
    gramK: "자꾸 틀리는 문법", gramT: "문장은 달라도, 틀리는 곳은 같았어요.",
    wordsK: "한 단계 올려볼 단어", wordsT: "자주 쓴 말과, 그 대신 써볼 말이에요.",
    coachK: "코치의 한마디", how: "말하는 습관", plan: "이번 주 할 일",
    testK: "이번 주 테스트", testT: "몇 분이면 끝나요. 지난 한 주에 만난 단어, 표현, 고친 문장으로 만들었어요.",
    remind: "다음 주 돌아보기도 알려 주세요", arrives: "다음 돌아보기는 10월 17일 (토)에 도착해요", start: "이번 주 테스트 풀기",
    done: "완료", inProg: "진행 중", past: "지난 돌아보기", ready: "10월 17일 (토)에 정리돼요", newB: "새로 도착",
    rowSub: (d, m) => `${d}일 · 대화 ${m}분`, range2: "9월 26일 – 10월 2일",
  },
  en: {
    title: "Your week", range: "Oct 3 – Oct 9", wd: ["S", "S", "M", "T", "W", "T", "F"], next: "Next",
    lastWeek: "Last week", of7: "of 7 days", cover: "Most of the week. That's a rhythm.", quiet: "A quiet week",
    quietSub: "It happens. One talk is enough to start again.", streak: n => `${n}-day streak`,
    sTalk: (m, n) => `${m} min of talk · ${n} talk${n === 1 ? "" : "s"}`, sUsed: n => `${n} thing${n === 1 ? "" : "s"} you studied, said out loud`,
    sYours: n => `${n} word${n === 1 ? " or phrase" : "s or phrases"} became yours`, sNew: n => `${n} new phrase${n === 1 ? "" : "s"} from your fluent self`,
    talks: "Talks", min: "min", more: n => `${n} min more than the week before`, talkSub: (d, m) => `${d} · ${m} min`,
    usedK: "You used what you practiced", usedT: "You studied these, then said them yourself in a real talk.",
    practice: "Practice", yoursT: "Words and phrases that became yours this week.", got: n => `${n} sentences you got down`,
    takes: n => `${n} shadowing takes`, avg: n => `average ${n}`, scenes: n => `${n} scenes watched`,
    freshK: "New from your fluent self", freshT: "Things your fluent self said that you haven't said yet.",
    waiting: "They're waiting in your expressions.", cards: n => `${n} new review cards from your corrections`,
    stuckK: "Where you got stuck", stuckT: "The same fix kept coming back. One more look and it's yours.",
    lastTest: (s, t, m) => `Last test ${s}/${t}. The ${m} you missed come back this week.`,
    gramK: "Grammar that keeps slipping", gramT: "The same point, in different sentences.",
    wordsK: "Words to level up", wordsT: "Words you leaned on, and one to reach for next.",
    coachK: "From your coach", how: "How you speak", plan: "This week",
    testK: "This week's test", testT: "A few minutes, made from your own week: the words, the phrases, the corrections.",
    remind: "Tell me when next week's is ready", arrives: "Next week's arrives Sat, Oct 17", start: "Start this week's test",
    done: "Done", inProg: "In progress", past: "Past weeks", ready: "Ready Sat, Oct 17", newB: "New",
    rowSub: (d, m) => `${d} days · ${m} min of talk`, range2: "Sep 26 – Oct 2",
  },
};
const WD_EN = ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"];

/* WeekRecapSheet.cards: every card is dealt for this week. */
const PAGES = ["cover", "talk", "used", "review", "fresh", "stumbles", "grammar", "words", "coach", "test"];
const q = s => `“${esc(s)}”`;

class NwWeekReport extends NwScreen {
  static poses = ["week", "quiet", "archive", ...PAGES.slice(1)];
  constructor() {
    super(`
      :host{background:#F2F2F7}
      .s{background:#F2F2F7}
      .sf{width:1em;height:1em;display:block;flex:0 0 auto;overflow:visible}
      .deck,.arch{position:absolute;inset:0;transition:opacity .4s ease}
      .arch{opacity:0;pointer-events:none}
      .s.archive .deck{opacity:0} .s.archive .arch{opacity:1}
      /* top bar: padding top 20 from the sheet's safe top (62), segments 3pt, spacing 12, header 32 */
      .segs{position:absolute;left:20px;right:20px;top:82px;height:3px;display:flex;gap:4px}
      .segs i{flex:1;border-radius:2px;background:#E3E3E8;position:relative;overflow:hidden}
      .segs i::after{content:"";position:absolute;inset:0;background:var(--blue);transform:scaleX(0);transform-origin:0 50%;transition:transform .35s ease-out}
      .segs i.on::after{transform:scaleX(1)}
      .hdr{position:absolute;left:20px;right:20px;top:97px;height:32px;display:flex;align-items:center;gap:8px}
      .hdr b{font-size:17px;font-weight:600;line-height:22px;letter-spacing:-.4px;white-space:nowrap}
      .hdr span{font-size:15px;line-height:20px;color:#8A8A8E;letter-spacing:-.2px;white-space:nowrap;flex:1}
      .hdr .x{width:32px;height:32px;border-radius:16px;background:#E3E3E8;display:grid;place-items:center;color:rgba(10,92,245,.55);flex:0 0 auto}
      .hdr .x .sf{width:18px;height:18px}
      /* pages: padding 20 × 8 inside the TabView, card radius 24 */
      .stage{position:absolute;left:0;right:0;top:133px;height:632px;overflow:hidden}
      .card{position:absolute;left:20px;right:20px;top:8px;bottom:8px;border-radius:24px;background:#fff;overflow:hidden;
        transform:translateX(0);transition:transform .45s cubic-bezier(.3,.7,.2,1)}
      .card.r{transform:translateX(402px)} .card.l{transform:translateX(-402px)}
      .in{padding:24px;display:flex;flex-direction:column;gap:18px;opacity:0;transform:translateY(14px);transition:opacity .4s ease-out,transform .4s ease-out}
      .card.shown .in{opacity:1;transform:none}
      .btn{position:absolute;left:20px;right:20px;top:765px;height:62px;border-radius:31px;background:var(--blue);color:#fff;
        display:grid;place-items:center;font-size:17px;font-weight:600;letter-spacing:-.4px;transition:transform .15s}
      .btn.press{transform:scale(.97)}
      /* card parts */
      .kick{display:flex;align-items:center;gap:7px;font-size:15px;font-weight:600;line-height:20px;color:var(--blue);letter-spacing:-.2px}
      .kick .sf{width:18px;height:18px}
      .kick.green{color:#34C759} .kick.orange{color:#FF8D28}
      .big{display:flex;align-items:baseline;gap:6px}
      .big b{font-family:ui-rounded,"SF Pro Rounded",-apple-system,sans-serif;font-size:64px;font-weight:700;line-height:74px;letter-spacing:0;font-variant-numeric:tabular-nums}
      .big span{font-size:22px;font-weight:600;color:#8A8A8E;letter-spacing:-.3px}
      .t3{font-size:20px;line-height:25px;letter-spacing:-.4px}
      .t3.sec{color:#8A8A8E}
      .qw{display:grid;width:max-content;max-width:100%;gap:18px} .qs{width:0;min-width:100%}
      .quietT{font-family:ui-rounded,"SF Pro Rounded",-apple-system,sans-serif;font-size:40px;font-weight:700;line-height:48px;letter-spacing:-.4px}
      .dots{display:flex;padding:6px 0}
      .dots div{flex:1;display:flex;flex-direction:column;align-items:center;gap:8px}
      .dots i{width:30px;height:30px;border-radius:15px;background:#EFEFF0;display:grid;place-items:center;color:#fff;transition:background .3s}
      .dots i .sf{width:15px;height:15px;opacity:0;transition:opacity .3s}
      .dots i.on{background:var(--blue)} .dots i.on .sf{opacity:1}
      .dots small{font-size:11px;font-weight:500;line-height:13px;color:#8A8A8E}
      .streak{display:flex;align-items:center;gap:8px;color:#FF8D28;font-size:17px;font-weight:600;line-height:22px}
      .streak .sf{width:20px;height:23px}
      .sum{display:flex;flex-direction:column;gap:10px;padding-top:4px}
      .line{display:flex;align-items:center;gap:8px;font-size:15px;line-height:20px;letter-spacing:-.2px}
      .line .ic{width:22px;display:grid;place-items:center;color:var(--blue);flex:0 0 auto}
      .line .ic .sf{width:19px;height:19px}
      .up{display:flex;align-items:center;gap:6px;color:#34C759;font-size:15px;font-weight:600;line-height:20px}
      .up .sf{width:13px;height:13px}
      .box{background:#F3F3F4;border-radius:14px}
      .tl{padding:4px 12px}
      .tr{position:relative;display:flex;align-items:center;gap:12px;padding:10px 0}
      .tr+.tr::before{content:"";position:absolute;left:40px;right:0;top:0;height:.5px;background:rgba(60,60,67,.29)}
      .tr .ic{width:28px;display:grid;place-items:center;color:var(--blue)} .tr .ic .sf{width:16px;height:16px}
      .tr b{display:block;font-size:15px;font-weight:500;line-height:20px;letter-spacing:-.2px}
      .tr small{display:block;font-size:12px;line-height:16px;color:#8A8A8E;margin-top:2px}
      .ent{display:flex;flex-direction:column;gap:4px}
      .ent b,.hd{font-size:17px;font-weight:600;line-height:22px;letter-spacing:-.4px}
      .ent span,.sub{font-size:15px;line-height:20px;color:#8A8A8E;letter-spacing:-.2px}
      .list{display:flex;flex-direction:column;gap:14px}
      .chips{display:flex;flex-wrap:wrap;gap:8px}
      .chips span{font-size:15px;font-weight:500;line-height:20px;padding:7px 12px;border-radius:17px;background:#F3F3F4;letter-spacing:-.2px}
      .sec{display:flex;flex-direction:column;gap:10px}
      .sec>h6{margin:0;font-size:12px;font-weight:600;line-height:16px;color:#8A8A8E}
      .ck{display:flex;gap:8px;font-size:15px;line-height:20px;letter-spacing:-.2px}
      .ck .sf{width:14px;height:20px;color:#34C759;flex:0 0 auto}
      .stat{display:flex;flex-direction:column;gap:8px}
      .stat .line .g{color:#34C759} .stat .line .d{color:#8A8A8E}
      .pad{padding:14px;display:flex;flex-direction:column;gap:10px}
      .strike{text-decoration:line-through;color:#8A8A8E}
      .rowx{display:flex;align-items:baseline;justify-content:space-between}
      .cnt{font-size:15px;font-weight:600;color:#FF8D28;font-variant-numeric:tabular-nums}
      .lab{display:flex;gap:8px;align-items:flex-start;font-size:15px;line-height:20px;color:#8A8A8E;letter-spacing:-.2px}
      .lab .sf{width:17px;height:20px;flex:0 0 auto}
      .pair{display:flex;flex-direction:column;gap:2px;font-size:15px;line-height:20px;letter-spacing:-.2px}
      .pair .n{font-weight:500}
      .tip{display:flex;gap:8px;font-size:15px;line-height:20px;letter-spacing:-.2px}
      .tip .sf{width:16px;height:20px;color:#FF8D28;flex:0 0 auto}
      .upg{display:flex;align-items:baseline;gap:8px;font-size:17px;line-height:22px;flex-wrap:wrap}
      .upg .w{color:#8A8A8E;font-weight:600}
      .upg small{font-size:12px;font-weight:600;color:#8A8A8E;font-variant-numeric:tabular-nums}
      .upg .sf{width:12px;height:12px;color:var(--blue);align-self:center}
      .upg b{font-weight:600}
      .note{font-size:13px;line-height:18px;color:#8A8A8E}
      .t2{font-size:22px;font-weight:700;line-height:28px;letter-spacing:-.3px}
      .body{font-size:17px;line-height:22px;letter-spacing:-.4px}
      .plan{background:rgba(10,92,245,.12);border-radius:16px;padding:16px;display:flex;flex-direction:column;gap:10px}
      .plan h6{margin:0;font-size:12px;font-weight:600;line-height:16px;color:var(--blue)}
      .plan p{margin:0;display:flex;gap:10px;align-items:baseline;font-size:17px;font-weight:500;line-height:22px;letter-spacing:-.4px}
      .plan p i{font-style:normal;font-size:15px;font-weight:700;color:var(--blue);font-variant-numeric:tabular-nums}
      .bigck{display:grid;place-items:center;padding:12px 0;color:var(--blue)} .bigck .sf{width:72px;height:72px}
      .bord{align-self:flex-start;display:flex;align-items:center;gap:6px;height:34px;padding:0 14px;border-radius:17px;background:rgba(10,92,245,.12);color:var(--blue);font-size:15px;font-weight:500;letter-spacing:-.2px;transition:transform .15s}
      .bord .sf{width:15px;height:15px}
      .bord.press{transform:scale(.96)}
      .onl{display:none;align-items:center;gap:8px;font-size:15px;line-height:20px;color:#8A8A8E}
      .onl .sf{width:15px;height:15px}
      .rem.on .bord{display:none} .rem.on .onl{display:flex}
      /* archive (inset grouped List in a NavigationStack) */
      .navt{position:absolute;left:0;right:0;top:71px;text-align:center;font-family:var(--pixel);font-size:17px;line-height:22px;letter-spacing:0}
      .arch .glass{right:17px;padding:0 16px;color:var(--blue);font-size:17px;font-weight:600;background:rgba(255,255,255,.75)}
      .sh{position:absolute;left:32px;font-size:15px;font-weight:600;line-height:20px;color:#8A8A8E}
      .grp{position:absolute;left:16px;right:16px;background:#fff;border-radius:26px;overflow:hidden}
      .ar{position:relative;display:flex;align-items:center;gap:12px;height:64px;padding:0 16px 0 20px}
      .ar+.ar::before{content:"";position:absolute;left:56px;right:16px;top:0;height:.5px;background:rgba(60,60,67,.22)}
      .ar .ic{width:28px;display:grid;place-items:center;color:var(--blue)} .ar .ic .sf{width:23px;height:23px}
      .ar .ic.g{color:#8A8A8E}
      .ar .tx{flex:1}
      .ar b{display:block;font-size:15px;font-weight:500;line-height:20px;letter-spacing:-.2px}
      .ar small{display:block;font-size:12px;line-height:16px;color:#8A8A8E;margin-top:2px}
      .ar em{font-style:normal;font-size:12px;font-weight:600;color:var(--blue);margin-right:6px}
      .ar .chev{width:12px;height:17px;color:#BDBDC2}
    `, `
      <div class="deck">
        <div class="segs">${PAGES.map(() => "<i></i>").join("")}</div>
        <div class="hdr"><b class="ttl"></b><span class="rng"></span><div class="x">${sf("xmark")}</div></div>
        <div class="stage"></div>
        <div class="btn"></div>
      </div>
      <div class="arch"></div>`);
  }

  get l() { const ko = this.t === STR.ko; return { ...(ko ? L.ko : L.en), ...(this._wk.dates?.[ko ? "ko" : "en"] ?? {}) }; }
  static observedAttributes = ["active", "sample"];
  attributeChangedCallback(n) { if (n === "sample") this.sample = this.getAttribute("sample"); else super.attributeChangedCallback(); }
  /* the week shown: the capture's, a named sample, the page's own merged over either */
  get _wk() { return { ...(SAMPLES[this._sample ?? this.getAttribute("sample")] ?? WEEK), ...(this._week ?? {}) }; }
  get week() { return this._wk; }
  set week(w) { this._week = w; if (this._built) { this.stop(); this.build(); } }
  set sample(name) { this._sample = name; if (this._built) { this.stop(); this.build(); } }

  build() {
    const l = this.l;
    this.$(".ttl").textContent = l.title;
    this.$(".rng").textContent = l.range;
    this.reset();
  }

  /* ── one card's content (WeekRecapSheet.cover / talk / used / …) ── */
  cardHTML(p, quiet = false) {
    const ko = this.t === STR.ko, l = this.l, wk = this._wk, W = { ...wk, coach: coachFor(ko, wk) };
    const kick = (txt, ic, cls = "") => `<div class="kick ${cls}">${sf(ic)}<span>${esc(txt)}</span></div>`;
    const big = (n, unit) => `<div class="big"><b>${n}</b>${unit ? `<span>${esc(unit)}</span>` : ""}</div>`;
    const t3 = (s, c = "") => `<div class="t3 ${c}">${esc(s)}</div>`;
    const wd = i => ko ? l.wd[i] : WD_EN[i];
    switch (p) {
      case "cover": {
        const on = quiet ? [0, 0, 0, 0, 0, 0, 0] : W.activeDays;
        const dots = `<div class="dots">${on.map((a, i) => `<div><i class="${a ? "on" : ""}">${sf("check")}</i><small>${l.wd[i]}</small></div>`).join("")}</div>`;
        if (quiet) // The secondary line wraps at the title's width, as the ScrollView lays it out in the app.
        return kick(l.lastWeek, "calendar") + `<div class="qw"><div class="quietT">${esc(l.quiet)}</div>${t3(l.quietSub, "sec qs")}</div>` + dots;
        const line = (ic, s) => `<div class="line"><span class="ic">${sf(ic)}</span><span>${esc(s)}</span></div>`;
        return kick(l.lastWeek, "calendar") + big(W.activeDays.filter(Boolean).length, l.of7) + t3(l.cover) + dots +
          `<div class="streak">${sf("flame")}<span>${esc(l.streak(W.streak))}</span></div>` +
          `<div class="sum">${line("waveform", l.sTalk(W.talkMin, W.talks.length))}${line("sealCheck", l.sUsed(W.usedCount))}${line("stack", l.sYours(W.nowYours.length))}${line("sparkles", l.sNew(W.newCount))}</div>`;
      }
      case "talk":
        return kick(l.talks, "waveform") + big(W.talkMin, l.min) +
          `<div class="up">${sf("arrowUpR")}<span>${esc(l.more(W.talkMin - W.prevMin))}</span></div>` +
          `<div class="box tl">${W.talks.map(([t, d, m, ic]) => `<div class="tr"><span class="ic">${sf(ic)}</span><div><b>${esc(t)}</b><small>${esc(l.talkSub(wd(d), m))}</small></div></div>`).join("")}</div>`;
      case "used":
        return kick(l.usedK, "sealFill", "green") + big(W.usedCount) + t3(l.usedT) +
          `<div class="list">${W.used.map(([w, s]) => `<div class="ent"><b>${esc(w)}</b><span>${q(s)}</span></div>`).join("")}</div>`;
      case "review":
        return kick(l.practice, "stackFill") + big(W.nowYours.length) + t3(l.yoursT) +
          `<div class="chips">${W.nowYours.map(w => `<span>${esc(w)}</span>`).join("")}</div>` +
          `<div class="sec"><h6>${esc(l.got(W.sentencesGot.length))}</h6>${W.sentencesGot.map(s => `<div class="ck">${sf("check")}<span>${esc(s)}</span></div>`).join("")}</div>` +
          `<div class="stat"><div class="line"><span class="ic">${sf("waveMic")}</span><span>${esc(l.takes(W.shadowTakes))} <span class="d">·</span> ${esc(l.avg(W.shadowAvg))} <span class="g">+${W.shadowAvg - W.prevShadowAvg}</span></span></div>` +
          `<div class="line"><span class="ic">${sf("playRect")}</span><span>${esc(l.scenes(W.scenes))}</span></div></div>`;
      case "fresh":
        return kick(l.freshK, "sparkles") + big(W.newCount) + t3(l.freshT) +
          `<div class="list" style="gap:12px">${W.newExpr.map(([w, s]) => `<div class="box pad ent" style="gap:4px"><b>${esc(w)}</b><span>${q(s)}</span></div>`).join("")}</div>` +
          `<div class="note">${esc(l.waiting)}</div>` +
          `<div class="line" style="font-weight:500"><span class="ic" style="color:#000">${sf("stackPlus")}</span><span>${esc(l.cards(W.newCards))}</span></div>`;
      case "stumbles":
        return kick(l.stuckK, "cycle", "orange") + t3(l.stuckT) +
          W.stumbles.map(([was, now, n]) => `<div class="box pad" style="gap:6px"><div class="body strike">${esc(was)}</div><div class="rowx"><span class="hd">${esc(now)}</span><span class="cnt">×${n}</span></div></div>`).join("") +
          `<div class="lab">${sf("checklist")}<span>${esc(l.lastTest(W.testScore, W.testTotal, W.testTotal - W.testScore))}</span></div>`;
      case "grammar":
        return kick(l.gramK, "textCheck", "orange") + t3(l.gramT) +
          W.coach.grammar.map(g => `<div class="box pad gp"><div class="hd">${esc(g.rule)}</div>` +
            g.ex.map(([was, now]) => `<div class="pair"><span class="strike">${esc(was)}</span><span class="n">${esc(now)}</span></div>`).join("") +
            `<div class="tip">${sf("bulb")}<span>${esc(g.tip)}</span></div></div>`).join("");
      case "words":
        return kick(l.wordsK, "upFwd") + t3(l.wordsT) +
          W.coach.upgrades.map(u => `<div class="box pad up2"><div class="upg"><span class="w">${esc(u.instead)}</span><small>×${u.count}</small>${sf("arrowR")}<b>${esc(u.better)}</b></div>` +
            `<div class="pair"><span style="color:#8A8A8E">${q(u.original)}</span><span>${q(u.rewritten)}</span></div>` +
            `<div class="note">${esc(u.note)}</div></div>`).join("");
      case "coach":
        return kick(l.coachK, "quote") + `<div class="t2">${esc(W.coach.headline)}</div>` +
          `<div class="sec"><h6>${esc(l.how)}</h6><div class="sec" style="gap:8px"><div class="body">${esc(W.coach.insight)}</div><div class="sub">${q(W.coach.insightQuote)}</div></div></div>` +
          `<div class="plan"><h6>${esc(l.plan)}</h6>${W.coach.plan.map((s, i) => `<p><i>${i + 1}</i><span>${esc(s)}</span></p>`).join("")}</div>`;
      case "test":
        return kick(l.testK, "checklist") + `<div class="bigck">${sf("checkCircle")}</div>` + t3(l.testT) +
          `<div class="rem"><div class="bord">${sf("bell")}<span>${esc(l.remind)}</span></div><div class="onl">${sf("bellFill")}<span>${esc(l.arrives)}</span></div></div>`;
    }
    return "";
  }

  archiveHTML() {
    const l = this.l, w = this._wk;
    return `<div class="navt">${esc(l.title)}</div><div class="glass">${esc(l.done)}</div>
      <div class="sh" style="top:126px">${esc(l.inProg)}</div>
      <div class="grp" style="top:156px"><div class="ar"><span class="ic g">${sf("hourglass")}</span><div class="tx"><b>${esc(l.ready)}</b><small>${esc(l.rowSub(2, 0))}</small></div></div></div>
      <div class="sh" style="top:248px">${esc(l.past)}</div>
      <div class="grp" style="top:278px">
        <div class="ar"><span class="ic">${sf("stack")}</span><div class="tx"><b>${esc(l.range)}</b><small>${esc(l.rowSub(w.activeDays.filter(Boolean).length, w.talkMin))}</small></div><em>${esc(l.newB)}</em>${sf("chevron", "sf chev")}</div>
        <div class="ar"><span class="ic">${sf("stack")}</span><div class="tx"><b>${esc(l.range2)}</b><small>${esc(l.rowSub(w.prevDays ?? 3, w.prevMin))}</small></div>${sf("chevron", "sf chev")}</div>
      </div>`;
  }

  /* Deal the deck: one card element per page, the current one centred. */
  deal(quiet = false) {
    const pages = quiet ? ["cover", "coach", "test"] : PAGES;
    this._pages = pages;
    this.$(".segs").innerHTML = pages.map(() => "<i></i>").join("");
    this.$(".stage").innerHTML = pages.map((p, i) => `<div class="card r" data-p="${p}"><div class="in">${this.cardHTML(p, quiet && p === "cover")}</div></div>`).join("");
    if (quiet) { // a quiet week's coach: no read, a fallback plan (WeekRecapSheet.coach, hasActivity false)
      const ko = this.t === STR.ko;
      this.$('.card[data-p="coach"] .in').innerHTML = `<div class="kick">${sf("quote")}<span>${esc(this.l.coachK)}</span></div>` +
        `<div class="t3">${ko ? "새 주가 시작됐어요. 가볍게 시작해요." : "A new week starts now. Start small."}</div>` +
        `<div class="plan"><h6>${esc(this.l.plan)}</h6><p><i>1</i><span>${ko ? "대화 한 번, 몇 분이면 충분해요." : "One talk, a few minutes. That's the whole plan."}</span></p></div>`;
    }
  }

  go(i) {
    this._page = i;
    this.$$(".card").forEach((c, k) => {
      c.classList.toggle("l", k < i); c.classList.toggle("r", k > i);
      if (k === i) c.classList.add("shown");
    });
    this.$$(".segs i").forEach((s, k) => s.classList.toggle("on", k <= i));
    const last = this._pages[i] === "test";
    this.$(".btn").textContent = last ? this.l.start : this.l.next;
  }

  reset() {
    if (!this._built) return;
    this.$(".s").classList.remove("archive");
    this.$(".arch").innerHTML = this.archiveHTML();
    this.deal(false);
    this.go(0);
  }

  async pose(name) {
    this.reset();
    if (name === "archive") { this.$(".s").classList.add("archive"); return; }
    if (name === "quiet") { this.deal(true); this.go(0); return; }
    const i = PAGES.indexOf(name);
    this.go(i < 0 ? 0 : i);
  }

  async tap(el) { el.classList.add("press"); await this.sleep(160); el.classList.remove("press"); }
  async next() { await this.tap(this.$(".btn")); this.go(this._page + 1); await this.sleep(500); }
  /** On the test card: "Tell me when next week's is ready" tapped → "Next week's arrives …". */
  async remind() { const c = this.$('.card[data-p="test"]'); if (!c) return; await this.tap(c.querySelector(".bord")); c.querySelector(".rem").classList.add("on"); await this.sleep(400); }
  /** "Start this week's test" pressed. The deck is a sheet that hands over to the test: given `test`
   *  (an <nw-weeklytest> laid over this one), the deck fades down and the test rises in its place. */
  async startTest(test) {
    await this.tap(this.$(".btn"));
    if (!test) return;
    test.style.transition = "none"; test.style.opacity = "0"; test.style.transform = "translateY(40px)"; test.style.visibility = "";
    void test.offsetWidth;
    test.style.transition = "opacity .4s ease, transform .5s cubic-bezier(.32,.72,0,1)"; test.style.opacity = "1"; test.style.transform = "none";
    await this.sleep(520);
  }
  /* scroll the current card's content (the card is a ScrollView) */
  async scrollCard(px, ms = 900) {
    const inn = this.$(".card.shown:not(.l):not(.r) .in");
    inn.style.transition = `opacity .4s ease-out, transform ${ms}ms ease-in-out`;
    inn.style.transform = `translateY(${-px}px)`;
    await this.sleep(ms + 100);
  }

  async demo() {
    await this.sleep(400);
    /* beat 1 — the week at a glance: days, streak, the summary lines */
    this.beat(1);
    const dots = this.$$('.card[data-p="cover"] .dots i');
    dots.forEach(d => d.classList.remove("on"));
    for (let k = 0; k < 7; k++) { await this.sleep(160); if (this._wk.activeDays[k]) dots[k].classList.add("on"); }
    await this.sleep(1400);
    /* beat 2 — what I said, what became mine (the deck advances like the app's Next) */
    this.beat(2);
    await this.next(); await this.sleep(800);    // talks
    await this.next(); await this.sleep(1200);   // used what you practiced
    await this.next(); await this.sleep(1200);   // became yours
    await this.next(); await this.sleep(800);    // new from your fluent self
    await this.next(); await this.sleep(400);    // where you got stuck
    /* beat 3 — the coach: a grammar point and a better word, in my own lines */
    this.beat(3);
    await this.next(); await this.sleep(1200);   // grammar that keeps slipping
    await this.scrollCard(110, 700);
    await this.next(); await this.sleep(1500);   // words to level up
    await this.next(); await this.sleep(900);    // from your coach
    /* beat 4 — the last card: the test, next week's notice, and the hand-off */
    this.beat(4);
    await this.next(); await this.sleep(700);
    await this.tap(this.$('.card[data-p="test"] .bord'));
    this.$('.card[data-p="test"] .rem').classList.add("on");
    await this.sleep(1000);
    await this.tap(this.$(".btn"));
    await this.sleep(700);
  }
}

export { NwWeekReport };
