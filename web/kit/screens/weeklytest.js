/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* ═══════════════════════════ <nw-weeklytest> — the weekly test ═══════════════════════════
 * WeeklyTestView.swift: a sheet titled "Weekly test" with Done; the host (WeeklyTestCharacter —
 * two pixel eyes on a 76.8pt rounded tile) alone at the top; under it the item: a caption
 * (subheadline semibold, secondary, the kind's SF Symbol) with "n/N" at its trailing edge, the
 * prompt, the answer area (bordered large buttons for meaning/gap/upgrade, word tiles in a dashed
 * box for translate/grammar/listen, a round mic for speak), and a bottom bar that grades (a verdict
 * row + Continue, green on a right answer). The result is a grouped List: the host, the headline,
 * "N of M", the missed items with their kind's icon, a footer, and "Try the missed ones again".
 * The run-of-right-answers flame CLAUDE.md mentions was pulled from the source (progressLabel's
 * comment, 2026-09-23), so it is not drawn. Geometry read off the simulator captures (ko, iPhone 17). */

const SF = {
  book: '<path d="M6.2 2.6h11.3c.9 0 1.6.7 1.6 1.6v14.1c0 .5-.4.9-.9.9H7.4c-.6 0-1 .4-1 1s.4 1 1 1h10.8c.5 0 .9.4.9.9s-.4.9-.9.9H7.3c-1.6 0-2.9-1.3-2.9-2.9V4.4c0-1 .8-1.8 1.8-1.8z" fill="currentColor"/><path d="M8.6 6.4h6.8M8.6 9.4h4.6" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/>',
  quote: '<path d="M5.4 3.6h13.2c1.6 0 2.9 1.3 2.9 2.9v8.2c0 1.6-1.3 2.9-2.9 2.9h-7.4l-4.6 3.6c-.5.4-1.1 0-1.1-.6v-3H5.4c-1.6 0-2.9-1.3-2.9-2.9V6.5c0-1.6 1.3-2.9 2.9-2.9z" fill="currentColor"/><path d="M8.3 8.2a1.5 1.5 0 1 1 1.4 2c-.2 1-.9 1.7-1.8 2M12.6 8.2a1.5 1.5 0 1 1 1.4 2c-.2 1-.9 1.7-1.8 2" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/>',
  charBubble: (g) => `<path d="M5.6 3.5h12.8c1.7 0 3 1.3 3 3v8.3c0 1.7-1.3 3-3 3h-6.9l-4.1 3.4c-.5.4-1 .1-1-.5v-2.9h-.8c-1.7 0-3-1.3-3-3V6.5c0-1.7 1.3-3 3-3z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><text x="12" y="14.2" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" font-family="-apple-system,'Apple SD Gothic Neo',sans-serif">${g}</text>`,
  cycle: '<path d="M5.2 10.4A7 7 0 0 1 18 7.6M18.8 13.6A7 7 0 0 1 6 16.4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M19.6 3.8l-.6 5.4-5.2-1.2zM4.4 20.2l.6-5.4 5.2 1.2z" fill="currentColor"/>',
  upCircle: '<circle cx="12" cy="12" r="9.3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 16.8V7.6M8.2 11.2L12 7.4l3.8 3.8" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
  ear: '<path d="M7 9.6a5.6 5.6 0 0 1 11.2 0c0 3-2.2 3.9-3 5.6-.6 1.2-.6 2.5-1.4 3.7a3.4 3.4 0 0 1-5.6-.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M9.8 10a3 3 0 0 1 5.6-1.2c.5 1.2-.3 2.2-1.2 2.6-.9.5-1.2 1.4-1.2 2.4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>',
  waveMic: '<path d="M2.6 10v4M5.6 7v10M8.6 3.6v16.8M11.6 7.4v9.2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><rect x="15.3" y="9.6" width="4.4" height="8" rx="2.2" fill="currentColor"/><path d="M13.6 15.6a3.9 3.9 0 0 0 7.8 0M17.5 19.6v2.2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  stack: '<rect x="3.6" y="8.6" width="16.8" height="12" rx="2.4" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M5.6 5.8h12.8M7.4 3.2h9.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>',
  bulb: '<path d="M12 3.2a5.6 5.6 0 0 0-3.4 10c.7.6 1 1.3 1 2.2v.8h4.8v-.8c0-.9.4-1.6 1-2.2a5.6 5.6 0 0 0-3.4-10z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M9.8 19h4.4M10.4 21.4h3.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>',
  checkFill: '<circle cx="12" cy="12" r="10.2" fill="currentColor"/><path d="M7.4 12.4l3.1 3.1 6-6.8" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>',
  xFill: '<circle cx="12" cy="12" r="10.2" fill="currentColor"/><path d="M8.6 8.6l6.8 6.8M15.4 8.6l-6.8 6.8" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round"/>',
  play: '<path d="M7.6 4.6c0-1 1.1-1.6 1.9-1.1l10.4 6.9c.8.5.8 1.7 0 2.2L9.5 19.5c-.8.5-1.9-.1-1.9-1.1z" fill="currentColor"/>',
  mic: '<rect x="8.7" y="2.6" width="6.6" height="12.2" rx="3.3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M5.4 11.4a6.6 6.6 0 0 0 13.2 0M12 18v3.4M8.6 21.4h6.8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
};
const sf = (n, arg) => `<svg class="g" viewBox="0 0 24 24" aria-hidden="true">${typeof SF[n] === "function" ? SF[n](arg) : SF[n]}</svg>`;

/* Chrome — the catalog's ko values (Localizable.xcstrings) beside the English keys. */
const T = {
  ko: { title: "주간 테스트", done: "완료", meaning: "어떤 단어의 뜻일까요?", gap: "빈칸 채우기", listen: "듣고 그대로 조립하기",
    speak: "소리 내어 말해 보세요", grammar: "자주 틀리는 문법", upgrade: "더 나은 표현", translate: "영어로 말하기",
    build: "문장 고치기", hint: "힌트 보기", write: "맞는 문장으로 만들어 봐요.", traps: "함정 단어도 있어요. 모든 단어를 다 쓰지 않아도 돼요.",
    lastTime: "지난번엔 이렇게 말했어요", trapsMine: "함정 단어 · 내 실수에서 나온 말", trapsBefore: "함정 단어 · 고치기 전에 쓴 말",
    right: "정답", notThis: "이번엔 아니에요", cont: "계속", seeResult: "결과 보기", check: "확인", youSaid: "내가 한 말",
    tapOrder: "단어를 순서대로 눌러요", speakHint: "누르고, 문장을 말하고, 다시 눌러요", skip: "건너뛰기",
    fluent: "유창한 표현", tip: "팁", why: "이 문장을 고친 이유", natural: f => `“${f}” 대신 더 자연스러운 말은?`,
    strong: "훌륭한 한 주예요", good: "잘한 한 주예요", inBook: "이번 주도 기록했어요", of: (a, b) => `${a} / ${b}`,
    missed: "틀린 것", backDue: "이것들은 복습으로 돌아가서 지금 바로 나와요.", retry: "틀린 것 다시 풀기", youSaidC: p => `내가 한 말: ${p}`,
    tapPlaced: "놓은 단어를 누르면 그 뒤에 넣어요. 한 번 더 누르면 빼요.", glyph: "가" },
  en: { title: "Weekly test", done: "Done", meaning: "Which word means this?", gap: "Fill the blank", listen: "Listen and build it",
    speak: "Say it out loud", grammar: "A mistake you keep making", upgrade: "A better word", translate: "Say it in English",
    build: "Fix the sentence", hint: "Show a hint", write: "Write it as a correct sentence.", traps: "Some words are traps — you don't have to use them all.",
    lastTime: "Last time you said", trapsMine: "Trap words — from your mistake", trapsBefore: "Trap words — what you said before the fix",
    right: "Right", notThis: "Not this time", cont: "Continue", seeResult: "See result", check: "Check", youSaid: "You said",
    tapOrder: "Tap the words in order", speakHint: "Tap, say the line, tap again", skip: "Skip",
    fluent: "Fluent version", tip: "Tip", why: "Why it was corrected", natural: f => `A more natural choice than “${f}”?`,
    strong: "A strong week", good: "A good week", inBook: "The week is in the book", of: (a, b) => `${a} of ${b}`,
    missed: "Missed", backDue: "These are back in your review, due now.", retry: "Try the missed ones again", youSaidC: p => `You said: ${p}`,
    tapPlaced: "Tap a placed word to add after it. Tap it again to take it out.", glyph: "A" },
};
const ICONS = { meaning: "book", gap: "quote", translate: "charBubble", grammar: "cycle", upgrade: "upCircle", listen: "ear", speak: "waveMic", build: "stack" };

/* ── the host: a port of WeeklyTestCharacter's pose maths ── */
const CELL = 12.8, SIZE = CELL * 6, EASE = 0.28, CLOSED = 2.5;
const EW = CELL * 0.82, EH = CELL * 1.12, ER = 3.4;
const REST_L = [SIZE / 2 - CELL, CELL * 2.5], REST_R = [SIZE / 2 + CELL, CELL * 2.5];
const smooth = x => { const v = Math.min(Math.max(x, 0), 1); return v * v * (3 - 2 * v); };
const fhash = x => { const v = Math.sin(x * 12.9898 + 78.233) * 43758.5453; return v - Math.floor(v); };
const pulse = (x, up, hold, down) => x < 0 ? 0 : x < up ? smooth(x / up) : x < up + hold ? 1 : x < up + hold + down ? 1 - smooth((x - up - hold) / down) : 0;
function mkPose([ox, oy], { lid = 0, sy = 1, sx = 1, tilt = 0, apart = 0 } = {}) {
  const dx = ox * CELL, dy = oy * CELL, a = apart * CELL / 2;
  return { l: { x: REST_L[0] + dx - a, y: REST_L[1] + dy, lid, sy, sx, tilt },
           r: { x: REST_R[0] + dx + a, y: REST_R[1] + dy, lid, sy, sx, tilt: -tilt } };
}
const mixE = (a, b, k) => Object.fromEntries(Object.keys(a).map(n => [n, a[n] + (b[n] - a[n]) * k]));
const mixP = (a, b, k) => ({ l: mixE(a.l, b.l, k), r: mixE(a.r, b.r, k) });
const SETTLED = {
  happy: () => mkPose([0, -0.6]),
  sad: () => mkPose([0, 0.6], { lid: 0.15, sy: 0.6, sx: 1.45, tilt: -0.2 }),
  angry: () => mkPose([0, 0.1], { sy: 0.34, sx: 1.55, tilt: 0.36, apart: -0.3 }),
  waiting: () => mkPose([0, 0]), thinking: () => mkPose([0, 0]),
};
function blink(t, every, seed) {
  const n = Math.floor(t / every);
  const period = every * (0.75 + 0.5 * fhash(n + seed));
  const phase = t % period;
  const first = pulse(phase, 0.08, 0.07, 0.11);
  const dbl = fhash(n + seed + 9) < 0.25 ? pulse(phase - 0.34, 0.08, 0.07, 0.11) : 0;
  return Math.max(first, dbl);
}
function gaze(t) {
  const hold = 1.6, seg = Math.floor(t / hold);
  const target = s => { const h1 = fhash(s + 0.5), h2 = fhash(s + 17.3);
    return [[-1, -0.5, 0, 0, 0, 0.5, 1][Math.floor(h1 * 7) % 7], h2 < 0.15 ? -0.5 : (h2 > 0.9 ? 0.25 : 0)]; };
  const f = target(seg - 1), to = target(seg), k = smooth((t - seg * hold) / 0.25);
  return [f[0] + (to[0] - f[0]) * k, f[1] + (to[1] - f[1]) * k];
}
function facePose(mood, t, el) {
  const neutral = mkPose(gaze(t), { lid: blink(t, 3.8, 0) });
  const k = smooth(el / EASE);
  if (mood === "waiting") return neutral;
  if (mood === "thinking") return mixP(neutral, mkPose([Math.sin(t * 1.4), 0], { lid: blink(t, 5.0, 3.1) }), k);
  const tg = SETTLED[mood]();
  if (mood === "happy") {
    const fl = Math.max(pulse(el - 0.10, .06, .04, .08), pulse(el - 0.36, .06, .04, .08), pulse(el - 0.62, .06, .04, .08));
    const b = el < 1.4 ? -0.18 * Math.sin(el * 8) * Math.exp(-el * 2.6) : 0;
    tg.l.lid = tg.r.lid = fl; tg.l.y += b * CELL; tg.r.y += b * CELL;
  } else if (mood === "sad") {
    const s = pulse(el - 0.7, 0.15, 0.2, 0.2); tg.l.lid = Math.max(tg.l.lid, s); tg.r.lid = Math.max(tg.r.lid, s);
  } else if (mood === "angry") {
    const sh = el < 0.5 ? 0.12 * Math.sin(el * 40) * Math.exp(-el * 7) : 0; tg.l.x += sh * CELL; tg.r.x += sh * CELL;
  }
  return mixP(neutral, tg, k);
}

/* ── the items: the capture's own paper (debug seed), plus the demo's ── */
const ITEMS = {
  word: { kind: "meaning", n: 1, of: 13, prompt: "In a loose or not taut manner; without tension.", options: ["that", "mover", "mine", "initiative"], gaze: [1, 0] },
  wordRight: { kind: "meaning", n: 2, of: 13, prompt: "In a loose or not taut manner; without tension.", options: ["relief", "perspective", "mine", "mover"], answer: "perspective", chosen: "perspective" },
  gap: { kind: "gap", n: 1, of: 13, prompt: "_____?", options: ["what surprised you most", "a chore", "how did it go", "catch up on"], gaze: [0, 0.25] },
  gapWrong: { kind: "gap", n: 2, of: 13, prompt: "_____?", options: ["end up", "what surprised you most", "how did it go", "felt prepared"], answer: "what surprised you most", chosen: "end up" },
  translate: { kind: "translate", n: 1, of: 14, prompt: "나 이 스타트업에서 2년째 일하고 있어.",
    options: ["startup", "at", "two", "years.", "I've", "for", "been", "this", "am", "since", "working"],
    answer: "I've been working at this startup for two years.", decoys: ["am", "since"],
    rule: "현재완료 진행형 + for", note: "과거부터 지금까지 이어지는 일은 have been -ing와 for를 써요.",
    was: "I am working in a startup since three years", fixed: "I've been working at a startup for three years", gaze: [0, 0.25] },
  grammar: { kind: "grammar", n: 1, of: 13, rule: "Past tense drops out halfway through a story", prompt: "I end up carrying most boxes myself.", focus: "I end up carrying",
    options: ["end", "up", "boxes", "carrying", "ended", "I", "myself.", "most"], answer: "I ended up carrying most boxes myself.", decoys: ["end"], note: "Keep the story in the past.", gaze: [-0.5, 0.25] },
  upgrade: { kind: "upgrade", n: 1, of: 13, prompt: "The flat is good for the price.", focus: "good", options: ["ambiguous", "exhausted", "decent", "sparkling"], answer: "decent", gaze: [-0.5, 0.25] },
  upgradeRight: { kind: "upgrade", n: 2, of: 13, prompt: "I was very tired after the move.", focus: "very tired", options: ["exhausted", "insufficient", "impartial", "decent"], answer: "exhausted", chosen: "exhausted",
    example: "I was exhausted after the move.", exNote: "One word does the work of two. Use it when tired isn't strong enough." },
  listen: { kind: "listen", n: 1, of: 13, options: ["Honestly,", "on", "doing", "sounds", "next", "I'd", "That", "alone.", "push", "time", "back", "it", "exhausting."], answer: "Honestly, I'd push back on doing it alone.", gaze: [0, 0.25] },
  speak: { kind: "speak", n: 1, of: 13, answer: "That's a compelling perspective — you clearly took the initiative to prioritize what mattered.", gaze: [-0.5, 0.25] },
};
/* The demo's paper: a word, a phrase, a mistake — all from this learner's own week. */
const DEMO = {
  word: { kind: "meaning", n: 1, of: 7, prompt: "Making you feel extremely tired.", options: ["relief", "exhausting", "perspective", "mover"], answer: "exhausting" },
  gap: { kind: "gap", n: 2, of: 7, prompt: "Honestly, I'd _____ doing it alone.", options: ["catch up on", "push back on", "end up", "how did it go"], answer: "push back on" },
  translate: { ...ITEMS.translate, n: 3, of: 7, options: ["working", "two", "this", "since", "I've", "for", "am", "been", "years.", "startup", "at"] },
};

class NwWeeklyTest extends NwScreen {
  static poses = ["word", "word-right", "gap", "gap-wrong", "translate", "translate-right", "translate-wrong", "grammar", "grammar-right",
    "upgrade", "upgrade-right", "listen", "speak", "result"];
  constructor() {
    super(`
      :host{--acc:#0A5CF5;--accFill:#D3E2FD;--green:#34C759;--greenFill:#DAF5E1;--red:#FF383C;--redFill:#FFDBDC;--grayT:#8E8E93;--grayFill:#EBEBEC;--sec:#8A8A8E;--ter:#C4C4C6}
      .g{width:1em;height:1em;display:block;flex:0 0 auto}
      .root{position:absolute;inset:0;background:#fff;transition:background .35s}
      .root.list{background:#F2F2F7}
      .nav{position:absolute;left:0;right:0;top:62px;height:44px;z-index:5}
      .nav .c{position:absolute;left:0;right:0;top:0;line-height:44px;text-align:center;font-family:var(--pixel);font-size:17px;letter-spacing:0}
      .nav .r{position:absolute;right:16px;top:0;height:44px;padding:0 14px;border-radius:22px;background:rgba(253,253,253,.94);box-shadow:0 1px 14px rgba(0,0,0,.07),inset 0 0 0 .5px rgba(0,0,0,.04);display:grid;place-items:center;color:var(--acc);font-size:17px;min-width:61px}
      .host{position:absolute;left:162.6px;top:130px;width:${SIZE}px;height:${SIZE}px;border-radius:20px;background:#F2F2F7;transition:top .45s cubic-bezier(.3,.8,.2,1),background .35s}
      .list .host{top:174.5px;background:#fff}
      .eye{position:absolute;left:0;top:0;background:#1A1A1A}
      .play{position:absolute;left:0;right:0;top:0;bottom:0;transition:opacity .3s}
      .scroll{position:absolute;left:0;right:0;top:226px;bottom:var(--bar,74px);overflow:hidden;padding:0 20px}
      .capl{display:flex;align-items:center;gap:12px;height:20px;margin-top:0;color:var(--sec);font-size:15px;font-weight:600}
      .capl .lb{display:flex;align-items:center;gap:8px;flex:1}
      .capl .lb .g{font-size:20px}
      .capl .pg{font-size:13px;font-weight:600;font-variant-numeric:tabular-nums;letter-spacing:.3px}
      .v{display:flex;flex-direction:column;gap:18px;padding-top:0}
      .stack{display:flex;flex-direction:column}
      .p-title2{font-size:23px;line-height:28px;font-weight:600;letter-spacing:0;text-wrap:balance}
      .p-title3{font-size:20px;line-height:25px;letter-spacing:-.4px;text-wrap:balance}
      .w6{font-weight:600}.w5{font-weight:500}
      .cap{font-size:12px;line-height:16px;font-weight:600;color:var(--sec)}
      .body{font-size:17px;line-height:22px;letter-spacing:-.4px}
      .foot{font-size:13px;line-height:18px;letter-spacing:-.1px}
      .sub{font-size:15px;line-height:20px;letter-spacing:-.2px}
      .sec{color:var(--sec)}
      u{text-decoration-thickness:1.5px;text-underline-offset:3px}
      .opts{display:flex;flex-direction:column;gap:10.4px}
      .opt{height:61.6px;border-radius:30.8px;background:var(--accFill);color:var(--acc);display:flex;align-items:center;padding:0 20px;font-size:17px;letter-spacing:-.4px;transition:background .25s,color .25s,transform .12s}
      .opt span{flex:1}.opt .g{font-size:22px;width:22px;opacity:0;transition:opacity .25s}
      .opt.ok{background:var(--greenFill);color:var(--green)}.opt.ok .g{opacity:1}
      .opt.bad{background:var(--redFill);color:var(--red)}.opt.bad .g{opacity:1}
      .opt.off{background:var(--grayFill);color:var(--grayT)}
      .opt.tap,.tile.tap{transform:scale(.96)}
      .hintb{align-self:flex-start;display:inline-flex;align-items:center;gap:4px;height:26px;padding:0 10px;border-radius:13px;background:var(--accFill);color:var(--acc);font-size:13px;font-weight:600}
      .hintb .g{font-size:15px}
      .area{display:flex;flex-direction:column;gap:16px}
      .box{position:relative;min-height:80px;padding:12px;border-radius:14px;display:flex;flex-wrap:wrap;gap:10px 8px;align-content:flex-start;
        background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='100%25' height='100%25'%3E%3Crect x='.5' y='.5' width='calc(100%25 - 1px)' height='calc(100%25 - 1px)' rx='13.5' fill='none' stroke='%23C4C4C6' stroke-width='1' stroke-dasharray='6 5'/%3E%3C/svg%3E")}
      .box .ph{position:absolute;left:20px;top:20px;font-size:15px;color:var(--ter)}
      .tray{display:flex;flex-wrap:wrap;gap:10px 8px}
      .tile{height:50.3px;padding:0 24px;border-radius:24.7px;display:inline-flex;align-items:center;font-size:17px;font-weight:500;letter-spacing:-.4px;background:var(--accFill);color:var(--acc);transition:background .25s,color .25s,transform .12s}
      .tile.ok{background:var(--greenFill);color:var(--green)}.tile.bad{background:var(--redFill);color:var(--red)}.tile.off{background:var(--grayFill);color:var(--grayT)}
      .strike{text-decoration:line-through}
      .bigc{align-self:center;width:90px;height:90px;border-radius:45px;background:var(--acc);color:#fff;display:grid;place-items:center;font-size:30px}
      .center{display:flex;flex-direction:column;align-items:center;gap:14px}
      .bar{position:absolute;left:0;right:0;bottom:34px;padding:12px 20px;background:#fff;display:flex;flex-direction:column;gap:12px}
      .verdict{display:flex;align-items:center;gap:10px;opacity:0;transform:translateY(12px);transition:opacity .22s,transform .22s;display:none}
      .verdict.on{display:flex;opacity:1;transform:none}
      .verdict .g{font-size:24px}
      .btn{height:49.6px;border-radius:24.8px;background:var(--acc);color:#fff;display:grid;place-items:center;font-size:17px;letter-spacing:-.4px;transition:background .25s,color .25s}
      .btn.green{background:var(--green)}
      .btn.dis{background:#E0E0E3;color:#B7B7BB}
      .btn.hide{visibility:hidden}
      .fade{opacity:0;transition:opacity .3s}.fade.on{opacity:1}
      /* result */
      .res{position:absolute;inset:0;opacity:0;pointer-events:none;transition:opacity .35s}
      .list .res{opacity:1}
      .list .play{opacity:0}
      .res .hd{position:absolute;left:0;right:0;top:262px;text-align:center}
      .res .h{font-size:22px;line-height:28px;font-weight:600;letter-spacing:-.2px}
      .res .sc{font-size:17px;line-height:22px;color:var(--sec);margin-top:4px;font-variant-numeric:tabular-nums}
      .res .shd{position:absolute;left:32px;top:364px;font-size:17px;font-weight:600;color:var(--sec);line-height:24px}
      .card{position:absolute;left:16.6px;right:16.6px;top:397px;background:#fff;border-radius:26px;padding:0}
      .row{position:relative;display:flex;gap:12px;padding:13px 16px 12px 24px}
      .row + .row::before{content:"";position:absolute;left:66px;right:16px;top:0;height:1px;background:#E5E5EA}
      .row .ic{width:22px;color:var(--sec);font-size:19px;padding-top:2px;display:flex;justify-content:center}
      .row .tx{flex:1}
            .row .t1{font-size:17px;line-height:22px;letter-spacing:-.4px}
      .row .t2{font-size:12px;line-height:16px;color:var(--sec);margin-top:3px}
      .res .ft{position:absolute;left:32px;right:32px;font-size:13px;line-height:18px;color:var(--sec)}
      .res .btn{position:absolute;left:20px;right:20px;bottom:47px}
    `, `<div class="root">
      <div class="nav"><span class="c"></span><span class="r"></span></div>
      <div class="host"><i class="eye l"></i><i class="eye r"></i></div>
      <div class="play"><div class="scroll" lang="en"></div>
        <div class="bar" lang="en"><div class="verdict"><span class="vi"></span><div><div class="sub w6 vt"></div><div class="sub sec va"></div></div></div><div class="btn"></div></div></div>
      <div class="res" lang="en"></div></div>`);
  }

  get L() { return this.t === STR.ko ? T.ko : T.en; }

  build() {
    this.$(".nav .c").textContent = this.L.title;
    this.$(".nav .r").textContent = this.L.done;
    this._mood = "waiting"; this._since = 0; this._held = null;
    this._t0 = performance.now();
    this._eyeTimer = setInterval(() => this._drawEyes(), 1000 / 30);
    this.reset();
  }
  disconnectedCallback() { super.disconnectedCallback(); }

  /* ── the host ── */
  _now() { return (performance.now() - this._t0) / 1000; }
  mood(m) { if (m !== this._mood) { this._mood = m; this._since = this._now(); } this._held = null; this._drawEyes(); }
  _drawEyes() {
    if (!this.isConnected) return;
    const t = this._now() + 100;
    const p = this._held || facePose(this._mood, t, this._now() - this._since);
    [[this.$(".eye.l"), p.l], [this.$(".eye.r"), p.r]].forEach(([el, e]) => {
      const full = EH * e.sy, h = Math.max(CLOSED, full - (full - CLOSED) * e.lid), w = EW * e.sx;
      el.style.width = w + "px"; el.style.height = h + "px"; el.style.borderRadius = Math.min(ER, h / 2) + "px";
      el.style.transform = `translate(${e.x - w / 2}px,${e.y - h / 2}px) rotate(${e.tilt}rad)`;
      el.style.transformOrigin = `${w / 2}px ${h / 2}px`;
    });
  }
  hold(mood, gz = [0, 0], lid = 0) {
    this._mood = mood;
    this._held = mood === "waiting" ? mkPose(gz, { lid }) : SETTLED[mood]();
    this._drawEyes();
  }

  /* ── an item ── */
  show(it) {
    const L = this.L, k = it.kind;
    this._it = it; this._laid = []; this._chosen = null;
    this.$(".root").classList.remove("list");
    const cap = k === "translate" ? L.translate : L[k];
    let prompt = "", area = "";
    const quote = (s, f) => { const i = f ? s.toLowerCase().indexOf(f.toLowerCase()) : -1;
      return i < 0 ? esc(s) : esc(s.slice(0, i)) + `<b><u>${esc(s.slice(i, i + f.length))}</u></b>` + esc(s.slice(i + f.length)); };
    if (k === "meaning") prompt = `<div class="p-title2">${esc(it.prompt)}</div>`;
    if (k === "gap") prompt = `<div class="p-title3 gapq">${this._gapHTML(it)}</div>`;
    if (k === "translate") prompt = `<div class="stack" style="gap:12px"><div class="p-title3 w6">${esc(it.prompt)}</div><div class="tx-after"><span class="hintb">${sf("bulb")}${esc(L.hint)}</span></div></div>`;
    if (k === "grammar") prompt = `<div class="stack" style="gap:12px"><div class="p-title3 w6">${esc(it.rule)}</div><div class="stack" style="gap:6px"><div class="cap">${esc(L.youSaid)}</div><div class="body sec">“${quote(it.prompt, it.focus)}”</div></div></div>`;
    if (k === "upgrade") prompt = `<div class="stack" style="gap:12px"><div class="stack" style="gap:6px"><div class="cap">${esc(L.youSaid)}</div><div class="p-title3">“${quote(it.prompt, it.focus)}”</div></div>
      <div class="sub w6">${esc(L.natural(it.focus))}</div><div class="stack ex fade" style="gap:4px;display:none"><div class="body w5" style="color:var(--green)">${esc(it.example || "")}</div><div class="foot sec">${esc(it.exNote || "")}</div></div></div>`;
    if (k === "listen") prompt = `<div style="padding:8px 0;display:flex;justify-content:center"><div class="bigc" style="font-size:34px">${sf("play")}</div></div>`;
    if (k === "speak") prompt = `<div class="p-title3 w5">${esc(it.answer)}</div>`;
    if (k === "meaning" || k === "gap" || k === "upgrade")
      area = `<div class="opts">${it.options.map(o => `<div class="opt" data-o="${esc(o)}"><span>${esc(o)}</span><i class="vk">${sf("xFill")}</i></div>`).join("")}</div>`;
    if (k === "translate" || k === "grammar" || k === "listen") {
      const fixes = k !== "listen";
      area = `<div class="area">${fixes ? `<div class="stack instr" style="gap:2px"><div class="sub w6">${esc(L.write)}</div>${it.decoys?.length ? `<div class="foot sec">${esc(L.traps)}</div>` : ""}</div>` : ""}
        <div class="box">${k === "listen" ? `<span class="ph">${esc(L.tapOrder)}</span>` : ""}</div>
        <div class="tray">${it.options.map((o, i) => `<span class="tile" data-i="${i}">${esc(o)}</span>`).join("")}</div><div class="after"></div></div>`;
    }
    if (k === "speak") area = `<div class="center" style="padding-top:8px"><div class="bigc">${sf("mic")}</div><div class="foot sec">${esc(L.speakHint)}</div><div class="foot sec">${esc(L.skip)}</div></div>`;
    const icn = k === "translate" ? sf("charBubble", L.glyph) : sf(ICONS[k]);
    this.$(".scroll").innerHTML = `<div class="v"><div class="capl"><span class="lb">${icn}<span>${esc(cap)}</span></span><span class="pg">${it.n}/${it.of}</span></div>${prompt}${area}</div>`;
    const needsCheck = ["translate", "grammar", "listen"].includes(k);
    const btn = this.$(".btn");
    btn.className = "btn" + (needsCheck ? " dis" : " hide"); btn.textContent = L.check;
    this.$(".verdict").className = "verdict";
    this._barH();
    this.mood("waiting");
  }
  _gapHTML(it) {
    const [a, b] = it.prompt.split("_____");
    const c = this._chosen;
    const col = this._outcome == null ? "var(--acc)" : this._outcome ? "var(--green)" : "var(--red)";
    const fill = c ? `<b style="color:${col}">${esc(c)}</b>` : `<span style="color:var(--ter)">_____</span>`;
    return esc(a) + fill + esc(b ?? "");
  }
  _barH() {
    const bar = this.$(".bar"); this.$(".scroll").style.setProperty("--bar", "0px");
    this.$(".scroll").style.bottom = (34 + bar.offsetHeight) + "px";
  }
  /* meaning / gap / upgrade */
  async choose(o) {
    const it = this._it; this._chosen = o; this._outcome = o === it.answer;
    this.$$(".opt").forEach(el => {
      const v = el.dataset.o, isA = v === it.answer, isC = v === o;
      el.classList.add(isA ? "ok" : isC ? "bad" : "off");
      el.querySelector(".vk").innerHTML = sf(isA ? "checkFill" : "xFill");
    });
    if (it.kind === "gap") this.$(".gapq").innerHTML = this._gapHTML(it);
    if (it.kind === "upgrade") { const ex = this.$(".ex"); if (ex) { ex.style.display = ""; ex.offsetWidth; ex.classList.add("on"); } }
    this.settle(this._outcome, it.kind === "gap" || it.kind === "meaning" || it.kind === "upgrade" ? it.answer : "");
  }
  /* tiles */
  lay(i) {
    const t = this.$(`.tray .tile[data-i="${i}"]`); if (!t) return;
    this.$(".box").append(t); this._laid.push(i);
    const ph = this.$(".box .ph"); if (ph) ph.remove();
    this.$(".btn").classList.remove("dis");
  }
  check(verdicts) {
    const it = this._it, L = this.L;
    const laid = this._laid.map(i => it.options[i]).join(" ");
    const ok = verdicts ? false : laid === it.answer;
    this._outcome = ok;
    this.$$(".box .tile").forEach((t, j) => t.classList.add(ok ? "ok" : (verdicts?.[j] === false ? "bad" : "ok")));
    this.$$(".tray .tile").forEach(t => t.classList.add("off"));
    const instr = this.$(".instr"); if (instr) instr.remove();
    if (it.kind === "translate") {
      this.$(".tx-after").innerHTML = `<div class="stack" style="gap:4px"><div class="foot w6">${esc(it.rule)}</div><div class="foot sec">${esc(it.note)}</div></div>
        <div class="stack" style="gap:4px;margin-top:10px"><div class="cap">${esc(L.lastTime)}</div><div class="foot sec" style="white-space:pre-wrap"><span class="strike">${esc(it.was)}</span>  →  <b style="font-weight:600">${esc(it.fixed)}</b></div></div>`;
    }
    if (it.decoys?.length) {
      this.$(".after").innerHTML = `<div class="stack" style="gap:4px"><div class="cap" style="font-weight:500">${esc(it.kind === "translate" ? L.trapsMine : L.trapsBefore)}</div>${ok ? "" : `<div class="foot sec strike">${esc(it.decoys.join(" · "))}</div>`}</div>`;
    }
    this.settle(ok, "");
  }
  settle(ok, answer) {
    const L = this.L, v = this.$(".verdict");
    v.querySelector(".vi").innerHTML = `<span style="color:${ok ? "var(--green)" : "var(--red)"}">${sf(ok ? "checkFill" : "xFill")}</span>`;
    v.querySelector(".vt").textContent = ok ? L.right : L.notThis;
    v.querySelector(".va").textContent = ok ? "" : answer;
    v.querySelector(".va").style.display = ok || !answer ? "none" : "";
    v.className = "verdict on";
    const btn = this.$(".btn");
    btn.className = "btn" + (ok ? " green" : "");
    btn.textContent = this._it.n === this._it.of ? L.seeResult : L.cont;
    this._barH();
    this.mood(ok ? "happy" : "sad");
  }

  /* ── the result ── */
  result({ score = 6, total = 7, missed = [] } = {}) {
    const L = this.L, ratio = score / total;
    const head = ratio >= 0.9 ? L.strong : ratio >= 0.6 ? L.good : L.inBook;
    this.$(".res").innerHTML = `<div class="hd"><div class="h">${esc(head)}</div><div class="sc">${L.of(`<span class="n">${score}</span>`, total)}</div></div>
      <div class="shd">${esc(L.missed)}</div>
      <div class="card">${missed.map(m => `<div class="row"><span class="ic">${sf(ICONS[m.kind])}</span><div class="tx" style="padding-top:${0}px"><div class="t1">${esc(m.answer)}</div>${m.sub ? `<div class="t2">${esc(m.kind === "meaning" ? m.sub : L.youSaidC(m.sub))}</div>` : ""}</div></div>`).join("")}</div>
      <div class="ft">${esc(L.backDue)}</div>
      <div class="btn">${esc(L.retry)}</div>`;
    this.$(".root").classList.add("list");
    const card = this.$(".card");
    this.$(".res .ft").style.top = (card.offsetTop + card.offsetHeight + 7) + "px";
    this.mood(ratio >= 0.8 ? "happy" : "waiting");
  }

  reset() {
    this._outcome = null;
    this.$(".res").innerHTML = "";
    this.show(DEMO.word);
  }

  async pose(name) {
    if (name === "demo") { this.removeAttribute("static"); this.loop(); return; }   // dev check: plays the demo under the harness
    const P = name.replace(/-(\w)/g, (_, c) => c.toUpperCase());
    if (name === "result") {
      this.result({ score: 5, total: 7, missed: [
        { kind: "meaning", answer: "exhausting", sub: "Making you feel very tired." },
        { kind: "build", answer: "I ended up carrying most of the boxes myself.", sub: "I end up carrying most boxes myself." }] });
      this.hold("waiting", [0, 0], 0.92);
      return;
    }
    const base = { translateRight: "translate", translateWrong: "translate", grammarRight: "grammar" }[P];
    const it = ITEMS[base || P];
    if (base) { this.show({ ...it, n: 2 }); }
    else this.show(it);
    if (it.chosen) this.choose(it.chosen);
    if (P === "translateRight" || P === "translateWrong") {
      const order = P === "translateRight" ? ["I've", "been", "working", "at", "this", "startup", "for", "two", "years."]
        : ["years.", "been", "working", "at", "this", "startup", "for", "two", "I've"];
      order.forEach(w => this.lay(it.options.indexOf(w)));
      this.check(P === "translateWrong" ? [false, true, true, true, true, true, true, true, false] : null);
    }
    if (P === "grammarRight") {
      ["I", "ended", "up", "carrying", "most", "boxes", "myself."].forEach(w => this.lay(it.options.indexOf(w)));
      this.check(null);
    }
    if (this._outcome == null) this.hold("waiting", it.gaze || [0, 0]);
    else this.hold(this._outcome ? "happy" : "sad");
  }

  async tapOpt(o) { const el = this.$(`.opt[data-o="${CSS.escape(o)}"]`); el?.classList.add("tap"); await this.sleep(140); el?.classList.remove("tap"); }
  async tapTile(w) {
    const i = this._it.options.indexOf(w), el = this.$(`.tray .tile[data-i="${i}"]`);
    el?.classList.add("tap"); await this.sleep(110); el?.classList.remove("tap"); this.lay(i);
  }
  async tapBtn() { const b = this.$(".btn"); b.style.opacity = ".7"; await this.sleep(150); b.style.opacity = ""; }

  async demo() {
    /* beat 1 — a word from my own week, answered right */
    this.beat(1);
    this.show(DEMO.word);
    await this.sleep(1600);
    await this.tapOpt("exhausting"); this.choose("exhausting");
    await this.sleep(1900);
    await this.tapBtn();
    /* beat 2 — a phrase the fluent self used, the blank filled */
    this.beat(2); this._outcome = null;
    this.show(DEMO.gap);
    await this.sleep(1700);
    await this.tapOpt("push back on"); this.choose("push back on");
    await this.sleep(1900);
    await this.tapBtn();
    /* beat 3 — my own repeated mistake, built right from tiles */
    this.beat(3); this._outcome = null;
    this.show(DEMO.translate);
    await this.sleep(1500);
    for (const w of ["I've", "been", "working", "at", "this", "startup", "for", "two", "years."]) await this.tapTile(w), await this.sleep(150);
    await this.sleep(400);
    await this.tapBtn(); this.check(null);
    await this.sleep(3200);
    await this.tapBtn();
    /* beat 4 — the result; the miss comes back */
    this.beat(4);
    this.result({ score: 6, total: 7, missed: [{ kind: "build", answer: "I ended up carrying most of the boxes myself.", sub: "I end up carrying most boxes myself." }] });
    const n = this.$(".res .sc .n");
    if (n) await this.countUp(n, 6, 900);
    await this.sleep(3600);
  }
}

export { NwWeeklyTest };
