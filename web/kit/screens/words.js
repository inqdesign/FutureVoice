/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc } from "../core.js";

/* ═══════════════════════════ <nw-words> — the word cloud, the word card, the day's word deck ═══════════════════════════
 * VocabularyView.swift: the level's words packed into a cloud (21pt rounded semibold at one level),
 * faded by an elliptical vignette; a word the learner has used or knows goes `.secondary` regular
 * with a green check at its leading top corner, a kept (studying) word wears a bookmark.fill there.
 * The cloud draws used and known ALIKE (`store.records[word] != nil`); only the word list
 * (WordsView) tells them apart, and the app hides both by default ("Hide words I know"). The
 * notebook sheet rests at its 220pt peek: bookmark · check | "My words · N" | up · down, then
 * headword, part of speech and the first meaning. Positions are read off the simulator capture
 * (B1, iPhone 17).
 *
 * Built from the Swift source (no simulator capture yet — `-capture wordcard` / a daily-words capture
 * would confirm them):
 *  - the FULL word card (WordCard.fullCard, the sheet at .large): headword 34 rounded bold, part of
 *    speech, the 46pt pronounce button (the learner's OWN cloned voice), MEANING / EXAMPLE /
 *    FROM YOUR TALKS (section titles are a verbatim `String` in the app, so English in every
 *    language), the CardButtons bar Keep · I know · ↑ · ↓.
 *  - the day's word deck (DailyWordsView → StudyDeckView): the accent card ("Say it out loud — do you
 *    know it?" → tap → meaning + "Hear it"), the drag hint, the four folder chips, and mid-drag the
 *    cancel circle + 10 min · Tomorrow · 3 days · Got it.
 *
 *   words.story()                         the cloud carries the interview book's words (compelling ·
 *                                         perspective · prioritize · initiative) and the sheet opens on "compelling"
 *   words.mark(word, "used"|"known"|"study"|"")   the cloud's badge, no animation
 *   await words.select(word)              tap a cloud word → the peek shows it
 *   await words.openCard(word?)           the sheet pulls to full height on the word's whole card
 *   await words.play()                    the pronounce button pressed (it plays the clone; the app draws a
 *                                         spinner only while the take is first made: play({ loading:true }))
 *   await words.know() / words.keep()     the card's verdict buttons (toggle)
 *   await words.collapse()                back to the peek
 *   await words.openDeck(["prioritize","compelling",…], { folders:[0,0,0,0] })   the day's deck slides up
 *   await words.reveal(); await words.hear(); await words.file(1)   flip · "Hear it" · drag into Tomorrow
 *   await words.closeDeck()
 *   words.cards = { word: { ko:[pos, [[pos, meaning]…], [[example, meaning]…]], en:[…], talk:"line" } }  add/override entries
 * Poses: cloud · card · deck · deck-revealed · deck-tray · story · story-card. */

const SF = {
  back: '<path d="M15 4.5L7.5 12l7.5 7.5" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>',
  filter: '<circle cx="12" cy="12" r="9.6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M7.3 8.9h9.4M8.9 12.2h6.2M10.6 15.5h2.8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  bookmarkFill: '<path d="M6.3 2.8h11.4c.8 0 1.4.6 1.4 1.4v16.3c0 .7-.8 1.1-1.4.7L12 17.1l-5.7 4.1c-.6.4-1.4 0-1.4-.7V4.2c0-.8.6-1.4 1.4-1.4z" fill="currentColor"/>',
  bookmark: '<path d="M6.5 3.6h11c.6 0 1 .4 1 1v15.3c0 .5-.6.8-1 .5L12 16.6l-5.5 3.8c-.4.3-1 0-1-.5V4.6c0-.6.4-1 1-1z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  check: '<circle cx="12" cy="12" r="9.6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M7.6 12.3l3 3.1 5.8-6.6" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
  checkFill: '<circle cx="12" cy="12" r="10.4" fill="currentColor"/><path d="M7.6 12.3l3 3.1 5.8-6.6" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>',
  up: '<path d="M4.5 16L12 8.5l7.5 7.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
  down: '<path d="M4.5 8.5L12 16l7.5-7.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
  tick: '<path d="M3.5 12.8l5.5 5.5L20.5 6" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>',
  speaker: '<path d="M3 9.2h3.4L11.2 5c.6-.5 1.5-.1 1.5.7v12.6c0 .8-.9 1.2-1.5.7l-4.8-4.2H3c-.6 0-1-.4-1-1V10.2c0-.6.4-1 1-1z" fill="currentColor"/><path d="M15.6 8.6a4.6 4.6 0 0 1 0 6.8M18.4 5.8a8.6 8.6 0 0 1 0 12.4" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/>',
  play: '<circle cx="12" cy="12" r="9.4" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M10 8.3v7.4c0 .5.5.8.9.5l5.6-3.7c.4-.3.4-.8 0-1L10.9 7.8c-.4-.3-.9 0-.9.5z" fill="currentColor"/>',
  waveMic: '<path d="M2.6 10v4M5.6 7v10M8.6 3.6v16.8M11.6 7.4v9.2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><rect x="15.3" y="9.6" width="4.4" height="8" rx="2.2" fill="currentColor"/><path d="M13.6 15.6a3.9 3.9 0 0 0 7.8 0M17.5 19.6v2.2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  eye: '<path d="M1.8 12C4.3 7.1 7.9 4.8 12 4.8s7.7 2.3 10.2 7.2c-2.5 4.9-6.1 7.2-10.2 7.2S4.3 16.9 1.8 12z" fill="none" stroke="currentColor" stroke-width="1.9"/><circle cx="12" cy="12" r="3.5" fill="currentColor"/>',
  handDraw: '<path d="M8.4 10.8V4.3a1.5 1.5 0 0 1 3 0v5.3m0-.7V7.4a1.5 1.5 0 0 1 3 0v2.2m0-1a1.5 1.5 0 0 1 3 0v1.6m0-.5a1.5 1.5 0 0 1 3 .4v4.6c0 3.5-2.3 6.1-5.8 6.1h-1.2c-2.1 0-3.6-1-4.8-2.8l-3.1-4.8a1.4 1.4 0 0 1 2.2-1.7l1.3 1.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M1.6 4.4c1.2-1.6 2.6-1.6 3.6 0" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  xmark: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"/>',
  /* DrillBin.icon: clock · sunrise · calendar · checkmark.circle.fill */
  clock: '<circle cx="12" cy="12" r="9.2" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M12 6.6V12l3.5 2.2" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/>',
  rise: '<path d="M2.6 19.2h18.8M6.2 16a5.8 5.8 0 0 1 11.6 0M12 2.8v5.6M9.3 5.4L12 2.8l2.7 2.6M3.4 10.6l1.7 1.2M20.6 10.6l-1.7 1.2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  cal: '<path fill="currentColor" fill-rule="evenodd" d="M6.3 3.2h11.4a3 3 0 0 1 3 3v11.6a3 3 0 0 1-3 3H6.3a3 3 0 0 1-3-3V6.2a3 3 0 0 1 3-3zM5 8.6v9.2c0 .8.6 1.4 1.4 1.4h11.2c.8 0 1.4-.6 1.4-1.4V8.6z"/><g fill="currentColor">' + [[9.4, 11.2], [12.4, 11.2], [15.4, 11.2], [6.6, 14], [9.4, 14], [12.4, 14], [15.4, 14], [6.6, 16.8], [9.4, 16.8], [12.4, 16.8]].map(([x, y]) => `<circle cx="${x + .6}" cy="${y}" r=".9"/>`).join("") + "</g>",
  okFill: '<circle cx="12" cy="12" r="10" fill="currentColor"/><path d="M7.4 12.3l3.1 3 6-6.6" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>',
};
const sf = n => `<svg class="g" viewBox="0 0 24 24" aria-hidden="true">${SF[n]}</svg>`;
const SPIN = s => `<span class="spin" style="width:${s}px;height:${s}px">${[...Array(8)].map((_, i) => `<i style="transform:rotate(${i * 45}deg);opacity:${(.25 + .75 * (8 - i) / 8).toFixed(2)}"></i>`).join("")}</span>`;

/* The B1 cloud as the capture shows it — centre x, y in points. Rows below y≈620 sit under the sheet. */
const CLOUD = [
  ["bet", 212, 133], ["improvement", 330, 139], ["severe", 34, 158], ["needle", 130, 175], ["administration", 349, 198],
  ["compound", 60, 223], ["guarantee", 182, 224], ["curiously", 31, 280], ["substantial", 178, 302], ["mud", 293, 288],
  ["mount", 376, 282], ["neighborhood", 63, 347], ["heel", 190, 363], ["heal", 266, 375], ["builder", 364, 365],
  ["disabled", 32, 436], ["salesman", 150, 443], ["storyteller", 291, 435], ["inject", 391, 451], ["register", 31, 518],
  ["clip", 129, 501], ["operation", 227, 505], ["companion", 347, 518], ["tremendous", 40, 586], ["latecomer", 195, 579],
  ["forbidden", 319, 572], ["overwhelmed", 52, 655], ["negotiate", 196, 648], ["genuinely", 336, 662],
  ["deadline", 22, 728], ["commute", 158, 736], ["landlord", 280, 724], ["chore", 392, 733],
  ["exhausting", 96, 806], ["boiler", 238, 798], ["sublet", 352, 812],
];
/* story(): the interview book's Words chapter takes the slots of words of about its length, so the packing holds */
const STORY = { substantial: "compelling", storyteller: "perspective", operation: "prioritize", guarantee: "initiative" };
const CX = 201, CY = 480, HX = 201, HY = 365;   // the vignette's ellipse, fitted to the capture
const hash = s => { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0; return h; };

/* WordLore entries (sample data — the app writes them with a model, in the native language):
   [subtitle pos, [[sense pos, meaning]…], [[example, its meaning]…]]; `talk` = a fluent-self line it came from */
const CARDS = {
  exhausting: { ko: ["형용사", [["형용사", "매우 피곤하게 만드는, 기진맥진하게 하는"]], [["Moving house is exhausting.", "이사는 정말 진이 빠지는 일이다."]]],
    en: ["adjective", [["adjective", "making you feel extremely tired"]], [["Moving house is exhausting.", null]]], studying: true },
  substantial: { ko: ["형용사", [["형용사", "상당한, (양·가치·중요성이) 큰"]], [["They made a substantial offer.", "그들은 상당한 금액을 제안했다."]]],
    en: ["adjective", [["adjective", "large in size, value or importance"]], [["They made a substantial offer.", null]]], studying: false },
  compelling: { ko: ["형용사", [["형용사", "설득력 있는"], ["형용사", "눈을 뗄 수 없는, 강렬한"]], [["She made a compelling case for the new plan.", "그녀는 새 계획에 대해 설득력 있는 주장을 펼쳤다."]]],
    en: ["adjective", [["adjective", "convincing; hard to argue with"], ["adjective", "so interesting you can't stop paying attention"]], [["She made a compelling case for the new plan.", null]]],
    talk: "That's a compelling perspective. You clearly took the initiative and prioritized what mattered.", studying: true },
  perspective: { ko: ["명사", [["명사", "관점, 시각"], ["명사", "(무엇이 중요한지에 대한) 균형 잡힌 판단"]], [["Living abroad gave me a new perspective.", "외국에서 살면서 새로운 시각을 얻었다."]]],
    en: ["noun", [["noun", "a particular way of looking at something"], ["noun", "a sensible sense of what really matters"]], [["Living abroad gave me a new perspective.", null]]],
    talk: "That's a compelling perspective. You clearly took the initiative and prioritized what mattered.", studying: true },
  prioritize: { ko: ["동사", [["동사", "우선순위를 정하다"], ["동사", "~을 우선시하다"]], [["You need to prioritize your tasks.", "할 일의 우선순위를 정해야 한다."]]],
    en: ["verb", [["verb", "to decide which things matter most and do them first"], ["verb", "to treat one thing as more important than others"]], [["You need to prioritize your tasks.", null]]],
    talk: "That's a compelling perspective. You clearly took the initiative and prioritized what mattered.", studying: true },
  initiative: { ko: ["명사", [["명사", "주도성, 진취성"], ["명사", "(새로운) 계획, 운동"]], [["She took the initiative and called the client herself.", "그녀는 먼저 나서서 직접 고객에게 전화했다."]]],
    en: ["noun", [["noun", "the ability to act without being told"], ["noun", "a new plan for dealing with a problem"]], [["She took the initiative and called the client herself.", null]]],
    talk: "That's a compelling perspective. You clearly took the initiative and prioritized what mattered.", studying: true },
};

const T = {
  ko: { notebook: n => `내 단어 · ${n}`, more: n => `+뜻 ${n}개 더`, keep: "공부", know: "알아요", listen: "듣기", shadow: "섀도잉",
        deck: "단어", done: "완료", of: (a, b) => `${a} / ${b}`, front: "소리 내어 말해 보세요 — 알고 있나요?", back: "언제 다시 볼까요?",
        tap: "눌러서 뜻 확인", meaning: "뜻", example: "예문", examples: "예문", hear: "들어보기", loading: "불러오는 중…",
        drag: "카드를 폴더로 끌어다 놓으세요", drop: "폴더 위에 놓으세요",
        bins: ["10분", "내일", "3일", "알아요"], hints: ["10분 뒤에 다시 나와요", "내일 다시 나와요", "3일 뒤에 다시 나와요", "아는 것으로 표시됨"] },
  en: { notebook: n => `My words · ${n}`, more: n => n === 1 ? "+1 more meaning" : `+${n} more meanings`, keep: "Keep", know: "I know", listen: "Listen", shadow: "Shadow",
        deck: "Words", done: "Done", of: (a, b) => `${a} of ${b}`, front: "Say it out loud — do you know it?", back: "When should it come back?",
        tap: "Tap to check the meaning", meaning: "Meaning", example: "Example", examples: "Examples", hear: "Hear it", loading: "Loading…",
        drag: "Drag the card into a folder", drop: "Drop it on a folder",
        bins: ["10 min", "Tomorrow", "3 days", "Got it"], hints: ["Back in 10 minutes", "Back tomorrow", "Back in 3 days", "Marked as known"] },
};
/* DrillBin: icon + tint (iOS 26 system orange / blue / indigo / green) */
const BIN = [["clock", "#FF8D28"], ["rise", "#0088FF"], ["cal", "#6155F5"], ["okFill", "#34C759"]];
/* StudyDeckView geometry (points): nav 62–106; the deck body fills 106–840, its furniture centred around the card */
const CARD_TOP = 126, CARD_H = 616, SLOT_TOP = 742, SLOT_H = 64, SLOT_W = 88.5;

class NwWords extends NwScreen {
  static poses = ["cloud", "card", "deck", "deck-revealed", "deck-tray", "story", "story-card"];
  constructor() {
    super(`
      :host{--acc:#0A5CF5;--sys:#0088FF;--green:#34C759;--sec:rgba(60,60,67,.6);--ter:rgba(60,60,67,.3)}
      .g{width:1em;height:1em;display:block;flex:0 0 auto}
      .nav{position:absolute;left:0;right:0;top:62px;height:44px;z-index:3}
      .nav .c{position:absolute;left:0;right:0;top:0;line-height:44px;text-align:center;font-family:var(--pixel);font-size:17px;letter-spacing:0}
      .nav .l,.nav .r{position:absolute;top:0;width:44px;height:44px;border-radius:22px;background:rgba(253,253,253,.94);box-shadow:0 1px 14px rgba(0,0,0,.07),inset 0 0 0 .5px rgba(0,0,0,.04);display:grid;place-items:center;color:var(--acc)}
      .nav .l{left:16px;font-size:24px}.nav .r{right:16px;font-size:25px}
      .cloud{position:absolute;inset:0;overflow:hidden}
      .wd{position:absolute;white-space:nowrap;font-family:ui-rounded,"SF Pro Rounded",var(--sans);font-size:21px;line-height:25px;font-weight:600;color:#000;letter-spacing:0;transform:translate(-50%,-50%);
        transition:left 2.4s linear,top 2.4s linear,opacity 2.4s linear,color .4s,font-weight .4s}
      .wd .bd{position:absolute;left:-4px;top:-8.8px;font-size:8.8px;color:var(--green);opacity:0;transition:opacity .3s,transform .3s;transform:scale(.4)}
      .wd .bd .bk{display:none}
      .wd.used{color:#8A8A8E;font-weight:400}
      .wd.used .bd{opacity:1;transform:none}
      .wd.study .bd{opacity:1;transform:none;color:var(--acc)}
      .wd.study .bd .tk{display:none}.wd.study .bd .bk{display:block}
      .wd.tap{transform:translate(-50%,-50%) scale(.94);transition:transform .12s}
      .sheet{position:absolute;left:9px;right:9px;top:623px;bottom:8px;border-radius:38px 38px 54px 54px;background:rgba(252,252,252,.84);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);
        box-shadow:0 0 0 .5px rgba(0,0,0,.04),0 -4px 28px rgba(0,0,0,.06);z-index:4;transform:translateY(110%);overflow:hidden;
        transition:transform .55s cubic-bezier(.3,.8,.2,1),top .5s cubic-bezier(.3,.8,.2,1),left .5s cubic-bezier(.3,.8,.2,1),right .5s cubic-bezier(.3,.8,.2,1),bottom .5s cubic-bezier(.3,.8,.2,1),border-radius .5s,background .5s}
      .sheet.on{transform:none}
      /* .large: the sheet takes the screen (WordCard.fullCard) */
      .sheet.big{top:64px;left:0;right:0;bottom:0;border-radius:38px 38px 0 0;background:#fff}
      .grab{position:absolute;left:50%;top:3.5px;width:36px;height:5px;margin-left:-18px;border-radius:3px;background:#BABABD;z-index:2}
      .cap{position:absolute;top:14px;height:44px;border-radius:22px;background:rgba(236,236,236,.75);display:flex;align-items:center;justify-content:space-around;font-size:22px;transition:opacity .25s}
      .cap.lead{left:15px;width:96px}.cap.trail{right:15px;width:95px}
      .cap .bm{color:var(--sys);font-size:20px}
      .cap .ck{color:#6C6C6C;font-size:25px;transition:color .3s}
      .cap .ck.on{color:var(--green)}
      .cap .up{color:#A9A9A9}.cap .dn{color:var(--acc)}
      .big .cap{opacity:0}
      .ttl{position:absolute;left:111px;right:111px;top:14px;line-height:44px;text-align:center;font-family:var(--pixel);font-size:17px;letter-spacing:0;z-index:2}
      .body{position:absolute;left:22px;right:22px;top:71px;transition:opacity .2s}
      .big .body{opacity:0!important;pointer-events:none}
      .body h4{margin:0;font-family:ui-rounded,"SF Pro Rounded",var(--sans);font-size:30px;line-height:36px;font-weight:700;letter-spacing:0}
      .body .pos{margin-top:0;font-size:15px;line-height:20px;color:#8A8A8E}
      .body p{margin:7px 0 0;font-size:17px;line-height:22px;letter-spacing:-.3px}
      .body .more{margin-top:3px;font-size:12px;line-height:16px;color:var(--sec);letter-spacing:0}
      /* the full card */
      .full{position:absolute;left:0;right:0;top:66px;bottom:0;padding:0 22px;opacity:0;transition:opacity .3s .1s;pointer-events:none}
      .big .full{opacity:1}
      .hw{display:flex;align-items:center;gap:14px}
      .hw .t{flex:1;min-width:0;display:flex;flex-direction:column;gap:5px}
      .hw h3{margin:0;font-family:ui-rounded,"SF Pro Rounded",var(--sans);font-size:34px;line-height:41px;font-weight:700;letter-spacing:0}
      .hw .ps{font-size:15px;line-height:20px;color:var(--sec);letter-spacing:-.2px}
      .say{flex:0 0 auto;width:46px;height:46px;border-radius:50%;background:rgba(10,92,245,.12);color:var(--acc);display:grid;place-items:center;font-size:21px;transition:transform .15s,background .15s}
      .say.pr{transform:scale(.9);background:rgba(10,92,245,.22)}
      .say .spin i{background:#8E8E93}
      .sec{margin-top:26px}
      .sec h5{margin:0 0 10px;font-size:11px;line-height:13px;font-weight:700;letter-spacing:.6px;color:var(--ter)}
      .sense{display:flex;gap:12px;align-items:flex-start}
      .sense+.sense{margin-top:16px}
      .num{flex:0 0 auto;width:22px;height:22px;border-radius:50%;background:rgba(10,92,245,.12);color:var(--acc);display:grid;place-items:center;font-size:12px;font-weight:700;font-variant-numeric:tabular-nums}
      .sense .sp{font-size:11px;line-height:13px;font-weight:600;color:var(--sec);text-transform:uppercase;letter-spacing:.06px}
      .sense .sm{margin-top:4px;font-size:20px;line-height:25px;font-weight:600;letter-spacing:-.45px}
      .ex{display:flex;gap:12px}
      .ex+.ex{margin-top:14px}
      .ex .bar{flex:0 0 3px;border-radius:2px;background:rgba(10,92,245,.35)}
      .ex .et{font-size:16px;line-height:21px;letter-spacing:-.3px}
      .ex .em{margin-top:4px;font-size:13px;line-height:18px;color:var(--sec);letter-spacing:-.1px}
      .src{padding:10px;border-radius:12px;background:rgba(118,118,128,.12)}
      .src .st{font-size:15px;line-height:20px;letter-spacing:-.2px}
      .src .sr{margin-top:6px;display:flex;align-items:center;gap:14px;font-size:12px;font-weight:600;color:var(--acc)}
      .src .sr .so{margin-right:auto;font-size:11px;font-weight:400;color:var(--sec)}
      .src .sr span{display:flex;align-items:center;gap:4px}
      .src .sr .g{font-size:14px}
      .acts{position:absolute;left:14px;right:14px;bottom:44px;display:flex;gap:8px;opacity:0;transition:opacity .3s .15s;pointer-events:none}
      .big .acts{opacity:1}
      .acts span{height:50px;border-radius:25px;background:rgba(255,255,255,.82);-webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px);
        box-shadow:0 0 0 .5px rgba(0,0,0,.05),0 4px 16px rgba(0,0,0,.08);display:flex;align-items:center;justify-content:center;gap:6px;font-size:15px;font-weight:600;letter-spacing:-.2px;transition:transform .15s,color .25s}
      .acts .a{flex:1}.acts .stp{flex:0 0 48px;font-size:15px}
      .acts .g{font-size:17px}
      .acts .on.kp{color:var(--acc)}.acts .on.kn{color:var(--green)}
      .acts .stp.off{color:var(--ter)}
      .acts span.pr{transform:scale(.94)}
      /* the day's word deck */
      .dk{position:absolute;inset:0;background:#fff;z-index:8;transform:translateY(102%);transition:transform .55s cubic-bezier(.3,.8,.2,1)}
      .dk.on{transform:none}
      .dk .hd{position:absolute;left:0;right:0;top:62px;height:44px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1px}
      .dk .hd b{font-size:17px;line-height:22px;font-weight:600;letter-spacing:-.4px}
      .dk .hd small{font-size:11px;line-height:13px;color:var(--sec);font-variant-numeric:tabular-nums;letter-spacing:.06px}
      .dk .dn{position:absolute;right:16px;top:62px;height:44px;padding:0 15px;border-radius:22px;background:rgba(255,255,255,.95);box-shadow:0 2px 12px rgba(0,0,0,.08),inset 0 0 0 .5px rgba(0,0,0,.05);display:grid;place-items:center;font-size:17px;color:var(--acc)}
      .card{position:absolute;left:16px;width:370px;top:${CARD_TOP}px;height:${CARD_H}px;border-radius:18px;background:var(--acc);color:#fff;box-sizing:border-box;padding:24px;
        box-shadow:inset 0 0 0 1px rgba(255,255,255,.14),0 4px 8px rgba(10,92,245,.28);transform-origin:50% 50%;
        transition:transform .5s cubic-bezier(.3,.8,.2,1),opacity .4s;display:flex;flex-direction:column;gap:18px}
      .card.next{transform:translateY(14px) scale(.95);opacity:.45;transition:none}
      .card .lb{font-size:12px;line-height:16px;color:rgba(255,255,255,.72);letter-spacing:0}
      .card .lb+*{margin-top:6px}
      .card .wv{font-size:28px;line-height:34px;font-weight:600;letter-spacing:.2px}
      .card .mb{display:none;flex-direction:column;gap:16px}
      .card.rev .mb{display:flex}
      .card .mb .num{background:rgba(255,255,255,.2);color:#fff}
      .card .mb .sense+.sense{margin-top:12px}
      .card .mb .sense .sp{color:rgba(255,255,255,.72)}
      .card .mb .sense .sm{margin-top:3px}
      .card .mb .ex .bar{background:rgba(255,255,255,.35)}
      .card .mb .ex .em{color:rgba(255,255,255,.72);margin-top:3px}
      .card .ft{margin-top:auto}
      .card .tp{display:flex;justify-content:center;align-items:center;gap:6px;font-size:13px;line-height:18px;font-weight:500;color:#fff}
      .card .tp .g{font-size:15px}
      .card .hr{display:none;height:38px;border-radius:19px;background:rgba(255,255,255,.18);align-items:center;justify-content:center;gap:5px;font-size:13px;font-weight:600;transition:background .15s}
      .card .hr .g{font-size:14px}
      .card .hr.pr{background:rgba(255,255,255,.3)}
      .card .hr .spin i{background:#fff}
      .card.rev .tp{display:none}.card.rev .hr{display:flex}
      .hint{position:absolute;left:0;right:0;top:756px;display:flex;justify-content:center;align-items:center;gap:5px;font-size:12px;line-height:16px;color:var(--sec);transition:opacity .2s}
      .hint .g{font-size:14px}
      .chips{position:absolute;left:0;right:0;top:794px;display:flex;justify-content:center;gap:8px;transition:opacity .2s}
      .chips span{height:30px;padding:0 12px;border-radius:15px;background:rgba(118,118,128,.12);display:flex;align-items:center;gap:5px;font-size:12px;font-weight:600;font-variant-numeric:tabular-nums;transition:transform .25s}
      .chips span .g{font-size:12px}
      .chips span.hit{transform:scale(1.12)}
      .drag .hint,.drag .chips{opacity:0}
      .tray{position:absolute;left:0;right:0;top:672px;height:160px;opacity:0;transform:translateY(40px);transition:transform .3s cubic-bezier(.3,.8,.2,1),opacity .25s;pointer-events:none;z-index:2}
      .drag .tray{opacity:1;transform:none}
      .tray .cx{position:absolute;left:178px;top:14px;width:46px;height:46px;border-radius:50%;background:rgba(242,242,247,.86);-webkit-backdrop-filter:blur(12px);backdrop-filter:blur(12px);display:grid;place-items:center;color:var(--sec);font-size:15px}
      .tray .sl{position:absolute;top:${SLOT_TOP - 672}px;width:${SLOT_W}px;height:${SLOT_H}px;border-radius:14px;background:rgba(242,242,247,.86);-webkit-backdrop-filter:blur(12px);backdrop-filter:blur(12px);
        display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px;color:var(--sec);font-size:11px;font-weight:500;transition:transform .25s,background .2s,color .2s}
      .tray .sl .g{font-size:21px}
      .tray .sl.act{color:#fff;transform:scale(1.08)}
      .tray .tl{position:absolute;left:0;right:0;top:144px;text-align:center;font-size:12px;line-height:16px;color:var(--sec)}
      .spin{position:relative;display:inline-block;flex:0 0 auto;animation:sp .8s steps(8) infinite}
      .spin i{position:absolute;left:45.5%;top:0;width:9%;height:28%;border-radius:9px;background:#8E8E93;transform-origin:50% 178.5%}
      @keyframes sp{to{transform:rotate(360deg)}}
    `, `
      <div class="cloud"></div>
      <div class="nav"><span class="l">${sf("back")}</span><span class="c">B1 · 16 / 2113</span><span class="r">${sf("filter")}</span></div>
      <div class="sheet on"><div class="grab"></div>
        <div class="cap lead"><span class="bm"></span><span class="ck">${sf("check")}</span></div>
        <div class="ttl"></div>
        <div class="cap trail"><span class="up">${sf("up")}</span><span class="dn">${sf("down")}</span></div>
        <div class="body"><h4></h4><div class="pos"></div><p></p><div class="more"></div></div>
        <div class="full"></div>
        <div class="acts"></div></div>
      <div class="dk"><div class="hd"><b></b><small></small></div><div class="dn"></div>
        <div class="cards"></div>
        <div class="hint">${sf("handDraw")}<span></span></div>
        <div class="chips"></div>
        <div class="tray"><div class="cx">${sf("xmark")}</div><div class="tl"></div></div></div>`);
    this.cards = {};
    this._word = "exhausting"; this._known = {}; this._kept = {};
  }
  get L() { return this.t === STR.ko ? T.ko : T.en; }
  _entry(w) { return this.cards[w] || CARDS[w] || { ko: ["", [], []], en: ["", [], []] }; }
  build() {
    this.$(".cloud").innerHTML = CLOUD.map(([w]) => `<span class="wd" data-w="${w}" data-slot="${w}"><span class="bd"><span class="tk">${sf("tick")}</span><span class="bk">${sf("bookmarkFill")}</span></span><span class="tx">${esc(w)}</span></span>`).join("");
    this.$(".ttl").textContent = this.L.notebook(9);
    const L = this.L;
    this.$(".dk .dn").textContent = L.done; this.$(".dk .hd b").textContent = L.deck;
    this.$(".hint span").textContent = L.drag;
    this.$(".tray").insertAdjacentHTML("beforeend", BIN.map(([n, c], i) =>
      `<div class="sl" data-i="${i}" style="left:${12 + i * (SLOT_W + 8)}px" data-c="${c}">${sf(n)}<span>${L.bins[i]}</span></div>`).join(""));
    this.reset();
  }
  /* ── the cloud ── */
  /* Parallax pan, as cloud(in:) does it: offset from the centre scaled by a per-word depth (0.9–1.1). */
  place(px = 0, py = 0) {
    for (const el of this.$$(".wd")) {
      const [w, x, y] = CLOUD.find(c => c[0] === el.dataset.slot);
      const d = .9 + (hash(w) % 1000) / 1000 * .2;
      const sx = x + px * d, sy = y + py * d;
      el.style.left = sx + "px"; el.style.top = sy + "px";
      el.style.opacity = Math.max(0, Math.min(1, 1.25 - Math.hypot((sx - CX) / HX, (sy - CY) / HY))).toFixed(3);
    }
  }
  _wd(w) { return this.$(`.wd[data-w="${w}"]`); }
  /** The cloud carries the interview book's words. */
  story(on = true) {
    for (const el of this.$$(".wd")) {
      const w = on && STORY[el.dataset.slot] || el.dataset.slot;
      el.dataset.w = w; el.querySelector(".tx").textContent = w;
    }
    this._story = on;
    if (on) this.card("compelling");
  }
  mark(word, state = "") {
    const e = this._wd(word); if (!e) return;
    e.classList.toggle("used", state === "used" || state === "known");
    e.classList.toggle("study", state === "study");
  }
  async select(word) {
    const e = this._wd(word);
    if (e) { e.classList.add("tap"); await this.sleep(140); e.classList.remove("tap"); }
    const b = this.$(".body"); b.style.opacity = 0; await this.sleep(180); this.card(word); b.style.opacity = "";
  }
  /* ── the notebook sheet: peek + full card ── */
  card(word) {
    this._word = word;
    const c = this._entry(word), ko = this.t === STR.ko, [pos, senses] = (ko ? c.ko : c.en);
    this.$(".body h4").textContent = word;
    this.$(".body .pos").textContent = pos;
    this.$(".body p").textContent = senses[0]?.[1] || "";
    this.$(".body .more").textContent = senses.length > 1 ? this.L.more(senses.length - 1) : "";
    const kept = this._kept[word] ?? !!c.studying;
    this.$(".cap .bm").innerHTML = sf(kept ? "bookmarkFill" : "bookmark");
    this.$(".cap .bm").style.color = kept ? "" : "#6C6C6C";
    const known = !!this._known[word];
    this.$(".ck").classList.toggle("on", known); this.$(".ck").innerHTML = sf(known ? "checkFill" : "check");
    this._full();
  }
  _full(loading = false) {
    const w = this._word, c = this._entry(w), ko = this.t === STR.ko, L = this.L, [pos, senses, exs] = (ko ? c.ko : c.en);
    this.$(".full").innerHTML = `
      <div class="hw"><div class="t"><h3>${esc(w)}</h3><div class="ps">${esc(pos)}</div></div><span class="say">${loading ? SPIN(20) : sf("speaker")}</span></div>
      <div class="sec"><h5>MEANING</h5>${senses.map(([p, m], i) => `<div class="sense"><span class="num">${i + 1}</span><div><div class="sp">${esc(p)}</div><div class="sm">${esc(m)}</div></div></div>`).join("")}</div>
      ${exs.length ? `<div class="sec"><h5>${exs.length === 1 ? "EXAMPLE" : "EXAMPLES"}</h5>${exs.map(([t, m]) => `<div class="ex"><span class="bar"></span><div><div class="et">${esc(t)}</div>${m ? `<div class="em">${esc(m)}</div>` : ""}</div></div>`).join("")}</div>` : ""}
      ${c.talk ? `<div class="sec"><h5>FROM YOUR TALKS</h5><div class="src"><div class="st">${esc(c.talk)}</div><div class="sr"><span class="so">Talk</span><span>${sf("play")}${L.listen}</span><span>${sf("waveMic")}${L.shadow}</span></div></div></div>` : ""}`;
    const kept = this._kept[w] ?? !!c.studying, known = !!this._known[w];
    const list = this._story ? Object.values(STORY) : [w], i = list.indexOf(w);
    this.$(".acts").innerHTML = `<span class="a kp${kept ? " on" : ""}">${sf(kept ? "bookmarkFill" : "bookmark")}${L.keep}</span>
      <span class="a kn${known ? " on" : ""}">${sf(known ? "checkFill" : "check")}${L.know}</span>
      <span class="stp${i <= 0 ? " off" : ""}">${sf("up")}</span><span class="stp${i < 0 || i >= list.length - 1 ? " off" : ""}">${sf("down")}</span>`;
  }
  async openCard(word) {
    if (word && word !== this._word) await this.select(word);
    this.$(".sheet").classList.add("big"); await this.sleep(650);
  }
  async collapse() { this.$(".sheet").classList.remove("big"); await this.sleep(600); }
  async play({ loading = false } = {}) {
    const s = () => this.$(".say");
    s().classList.add("pr"); await this.sleep(160); s().classList.remove("pr");
    if (loading) { this._full(true); await this.sleep(900); this._full(); }
    await this.sleep(200);
  }
  async _press(sel) { const b = this.$(sel); if (!b) return; b.classList.add("pr"); await this.sleep(160); b.classList.remove("pr"); }
  async know() { await this._press(".acts .kn"); const w = this._word; this._known[w] = !this._known[w]; this.card(w); if (this._known[w]) this.mark(w, "known"); }
  async keep() { await this._press(".acts .kp"); const w = this._word, c = this._entry(w); this._kept[w] = !(this._kept[w] ?? !!c.studying); this.card(w); }
  /* ── the day's deck (DailyWordsView → StudyDeckView) ── */
  _cardHTML(w, cls) {
    const c = this._entry(w), ko = this.t === STR.ko, L = this.L, [, senses, exs] = (ko ? c.ko : c.en);
    return `<div class="card ${cls}" data-w="${esc(w)}"><div><div class="lb fl">${L.front}</div><div class="wv">${esc(w)}</div></div>
      <div class="mb"><div><div class="lb">${L.meaning}</div><div>${senses.slice(0, 2).map(([p, m], i) => `<div class="sense"><span class="num">${i + 1}</span><div><div class="sp">${esc(p)}</div><div class="sm">${esc(m)}</div></div></div>`).join("")}</div></div>
        ${exs.length ? `<div><div class="lb">${exs.length === 1 ? L.example : L.examples}</div><div>${exs.slice(0, 1).map(([t, m]) => `<div class="ex"><span class="bar"></span><div><div class="et">${esc(t)}</div>${m ? `<div class="em">${esc(m)}</div>` : ""}</div></div>`).join("")}</div></div>` : ""}</div>
      <div class="ft"><div class="tp">${sf("eye")}${L.tap}</div><div class="hr">${sf("speaker")}<span>${L.hear}</span></div></div></div>`;
  }
  _deal() {
    const q = this._queue, L = this.L;
    this.$(".cards").innerHTML = (q[1] ? this._cardHTML(q[1], "next") : "") + (q[0] ? this._cardHTML(q[0], "top") : "");
    this.$(".dk .hd small").textContent = L.of(Math.min(this._done + 1, this._total), this._total);
  }
  _chips(hit = -1) {
    this.$(".chips").innerHTML = BIN.map(([n, c], i) => `<span class="${i === hit ? "hit" : ""}" style="color:${this._folders[i] ? c : "rgba(60,60,67,.3)"}">${sf(n)}${this._folders[i]}</span>`).join("");
  }
  async openDeck(list = ["prioritize", "compelling", "perspective", "initiative"], { folders = [0, 0, 0, 0], instant = false } = {}) {
    this._queue = [...list]; this._total = list.length; this._done = 0; this._folders = [...folders];
    const dk = this.$(".dk"); dk.classList.remove("drag");
    this._deal(); this._chips();
    if (instant) { dk.style.transition = "none"; dk.classList.add("on"); void dk.offsetWidth; dk.style.transition = ""; }
    else { dk.classList.add("on"); await this.sleep(600); }
  }
  async closeDeck() { this.$(".dk").classList.remove("on"); await this.sleep(600); }
  _top() { return this.$(".cards .top"); }
  async reveal() {
    const c = this._top(); if (!c) return;
    c.style.transform = "scale(.98)"; await this.sleep(120); c.style.transform = "";
    c.classList.add("rev"); c.querySelector(".fl").textContent = this.L.back; await this.sleep(300);
  }
  async hear({ loading = false } = {}) {
    const h = this._top()?.querySelector(".hr"); if (!h) return;
    h.classList.add("pr"); await this.sleep(160); h.classList.remove("pr");
    if (loading) { const was = h.innerHTML; h.innerHTML = `${SPIN(13)}<span>${this.L.loading}</span>`; await this.sleep(900); h.innerHTML = was; }
    await this.sleep(200);
  }
  _aim(bin) {
    const dk = this.$(".dk"), L = this.L;
    this.$$(".tray .sl").forEach(s => { const on = +s.dataset.i === bin; s.classList.toggle("act", on); s.style.background = on ? s.dataset.c : ""; });
    this.$(".tray .tl").textContent = bin < 0 ? L.drop : L.hints[bin];
    dk.classList.toggle("drag", true);
  }
  /** Drag the top card onto a folder (0 10 min · 1 Tomorrow · 2 3 days · 3 Got it); the next card comes up. */
  async file(bin = 1) {
    if (typeof bin === "string") bin = Math.max(0, ["10min", "tomorrow", "3days", "gotit"].indexOf(bin.toLowerCase().replace(/\s/g, "")));
    const c = this._top(); if (!c) return;
    const sx = 12 + bin * (SLOT_W + 8) + SLOT_W / 2, dx = sx - 201;
    // pick up: the finger drags the card down toward the folders, the tray rises
    c.style.transition = "transform .45s cubic-bezier(.3,.8,.2,1)";
    c.style.transform = `translate(${dx * .35}px, 140px) rotate(${dx * .35 / 20}deg)`;
    this._aim(-1); await this.sleep(450);
    c.style.transform = `translate(${dx * .8}px, 330px) rotate(${dx * .8 / 20}deg)`; await this.sleep(220);
    this._aim(bin); await this.sleep(420);
    // drop: into the folder
    c.style.transition = "transform .35s cubic-bezier(.4,0,.6,1),opacity .3s";
    c.style.transform = `translate(${dx}px, ${SLOT_TOP + SLOT_H / 2 - CARD_TOP - CARD_H / 2}px) rotate(${dx / 20}deg) scale(.16)`; c.style.opacity = 0;
    await this.sleep(360);
    this.$$(".tray .sl").forEach(s => { s.classList.remove("act"); s.style.background = ""; }); this.$(".dk").classList.remove("drag");
    this._folders[bin]++; this._chips(bin); this._done++; this._queue.shift();
    const next = this.$(".cards .next");
    if (next) { next.style.transition = "transform .4s cubic-bezier(.3,.8,.2,1),opacity .3s"; next.classList.remove("next"); next.style.transform = ""; next.style.opacity = 1; }
    await this.sleep(420); this._deal(); await this.sleep(150); this._chips();
  }
  /* ── lifecycle ── */
  reset() {
    this.$$(".wd").forEach(w => { w.style.transition = "none"; w.classList.remove("used", "tap", "study"); });
    this.story(false);
    this.place(0, 0); void this.$(".cloud").offsetWidth;
    this.$$(".wd").forEach(w => w.style.transition = "");
    this._known = {}; this._kept = {};
    this.$(".body").style.opacity = "";
    this.card("exhausting");
    const sh = this.$(".sheet"); sh.style.transition = "none"; sh.classList.remove("big"); sh.classList.add("on"); void sh.offsetWidth; sh.style.transition = "";
    const dk = this.$(".dk"); dk.style.transition = "none"; dk.classList.remove("on", "drag"); void dk.offsetWidth; dk.style.transition = "";
  }
  async pose(name) {
    this.stop(); this.reset();
    if (name === "story" || name === "story-card") {
      this.story(); this.mark("initiative", "used"); this.mark("perspective", "study");
      if (name === "story-card") this.$(".sheet").classList.add("big");
    } else if (name === "card") this.$(".sheet").classList.add("big");
    else if (name.startsWith("deck")) {
      await this.openDeck(["prioritize", "compelling", "perspective", "initiative"], { folders: [1, 2, 0, 1], instant: true });
      if (name !== "deck") { const c = this._top(); c.classList.add("rev"); c.querySelector(".fl").textContent = this.L.back; }
      if (name === "deck-tray") { const c = this._top(); c.style.transform = "translate(-40px, 330px) rotate(-2deg)"; this._aim(1); }
    }
  }
  async demo() {
    await this.sleep(500);
    this.place(14, 22);                                  // the learner drags the cloud a little
    await this.sleep(1000);
    this.beat(1);                                        // words said in talks get the check
    for (const w of ["guarantee", "storyteller", "operation"]) { this.$(`[data-w="${w}"]`).classList.add("used"); await this.sleep(480); }
    await this.sleep(700); this.beat(2);                 // a word opens on the card
    const e = this.$('[data-w="substantial"]');
    e.classList.add("tap"); await this.sleep(140); e.classList.remove("tap");
    const b = this.$(".body"); b.style.opacity = 0; await this.sleep(180); this.card("substantial"); b.style.opacity = 1;
    await this.sleep(1500);
    this.beat(3);                                        // check = known
    const ck = this.$(".ck"); ck.innerHTML = sf("checkFill"); ck.classList.add("on"); e.classList.add("used");
    await this.sleep(2600);
  }
}

export { NwWords };
