/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc, mmss } from "../core.js";

/* ═══════════════════════════ <nw-speech> ═══════════════════════════
 * Speech tab → prompter (camera off / on, recording) → result → the board's moment sheet.
 *   await speech.open(); await speech.camera(true); await speech.record(4600, 21);
 *   await speech.result(81); await speech.rankUp(14, 8)
 * Built from SpeechTab.swift (List, inline-large title), SpeechPrompterView.swift (prompter,
 * camera card, controls), SpeechResultView.swift + SpeechChallengeViews.swift (gauge, coach line,
 * challenge entry, SpeechChallengeMomentSheet). Points = CSS px; positions measured off the
 * simulator captures (iPhone 17, 402×874).
 * Attributes: autoplay; nochallenges — the tab as shipped before challenges (SpeechTab /
 * SpeechResultView at 34e25c0e..HEAD): no Challenges section, the bundled sample is the first row
 * under Scripts ("· Sample"), open() taps it, the result has no challenge entry (the playback
 * section moves up into its place), rankUp() is a no-op and demo() ends on the result.
 * The learner's OWN script (unset = the fixed samples, unchanged):
 *   <nw-speech script-title="My interview intro" script-text="Para one.\nPara two." script-seconds="60">
 *   or speech.script = { title, text, seconds }  (text: "\n"-separated paragraphs, or an array).
 * It becomes the newest row under Scripts (SpeechStore.reload: saved scripts newest first, after the
 * sample when there is no challenge), pencil.line + "N sec · My script"; open() taps that row, the
 * prompter reads its text (no camera note: only a challenge asks for the camera), the result is
 * titled with it and has no challenge entry; demo() then stays mic-only and ends on the result.
 * open("challenge") still opens the challenge. */

/* SF Symbols, traced at 24×24. */
const SF = {
  plus: '<path d="M12 4.5v15M4.5 12h15" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"/>',
  chevR: '<path d="M9 5.5l6.5 6.5L9 18.5" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>',
  trophy: '<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"><path d="M7.2 3.5h9.6v5.6a4.8 4.8 0 0 1-9.6 0z"/><path d="M7.2 5.3H4.6v1.3a3.6 3.6 0 0 0 3.1 3.6M16.8 5.3h2.6v1.3a3.6 3.6 0 0 1-3.1 3.6"/><path d="M12 13.9v3.3M9.6 17.2h4.8l.7 3.3H8.9z"/></g>',
  trophyFill: '<g fill="currentColor"><path d="M7 3h10v6.2a5 5 0 0 1-10 0z"/><path d="M8.4 17h7.2l.9 4H7.5zM11 13.5h2V17h-2z"/></g><path d="M7.3 5.2H4.5v1.4a3.7 3.7 0 0 0 3.3 3.7M16.7 5.2h2.8v1.4a3.7 3.7 0 0 1-3.3 3.7" fill="none" stroke="currentColor" stroke-width="1.7"/>',
  person: '<defs><clipPath id="pc"><rect x="3.5" y="3.5" width="17" height="17" rx="3.6"/></clipPath></defs><rect x="3.5" y="3.5" width="17" height="17" rx="3.6" fill="none" stroke="currentColor" stroke-width="1.7"/><g clip-path="url(#pc)" fill="currentColor"><circle cx="12" cy="10.2" r="3.3"/><path d="M5 21.5c.6-3.8 3.4-6.1 7-6.1s6.4 2.3 7 6.1z"/></g>',
  bulb: '<g fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2.8a6.2 6.2 0 0 0-3.7 11.2c.8.6 1.2 1.4 1.2 2.4v.6h5v-.6c0-1 .4-1.8 1.2-2.4A6.2 6.2 0 0 0 12 2.8z"/><path d="M9.6 19.1h4.8M10.2 21.3h3.6"/></g>',
  pencilLine: '<g fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M15.8 3.9l3.3 3.3-9.8 9.8-4.3 1 1-4.3z"/><path d="M13.7 6l3.3 3.3M4 21h16"/></g>',
  xmark: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"/>',
  doc: '<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"><path d="M7.6 2.8h6l4.8 4.8v11.3a2.3 2.3 0 0 1-2.3 2.3H7.6a2.3 2.3 0 0 1-2.3-2.3V5.1a2.3 2.3 0 0 1 2.3-2.3z"/><path d="M13.3 3v3.6a1.4 1.4 0 0 0 1.4 1.4h3.6M8.8 12.3h6.4M8.8 15.3h6.4M8.8 18.2h4"/></g>',
  history: '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.6 10.4A7.8 7.8 0 1 1 5.3 16"/><path d="M12 7.6V12l3 2.1"/></g><path d="M1.6 9.2l3.6 4.3 3.4-4.4z" fill="currentColor"/>',
  mic: '<rect x="8.6" y="1.8" width="6.8" height="12.6" rx="3.4" fill="currentColor"/><g fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M5.2 10.6a6.8 6.8 0 0 0 13.6 0M12 17.4v3.3M8.2 20.9h7.6"/></g>',
  videoSlash: '<path d="M3.2 7.6c0-1 .8-1.8 1.8-1.8h9.3c1 0 1.8.8 1.8 1.8v8.8c0 1-.8 1.8-1.8 1.8H5c-1 0-1.8-.8-1.8-1.8zM17.4 10.3l3.4-2.4c.5-.3 1 0 1 .6v7c0 .6-.5.9-1 .6l-3.4-2.4z" fill="currentColor"/><path d="M3.6 3.4l17 17.6" stroke="#CFDBF7" stroke-width="3.6" stroke-linecap="round"/><path d="M3.6 3.4l17 17.6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  video: '<path d="M2.6 7.6c0-1 .8-1.8 1.8-1.8h9.6c1 0 1.8.8 1.8 1.8v8.8c0 1-.8 1.8-1.8 1.8H4.4c-1 0-1.8-.8-1.8-1.8zM17.2 10.3l3.5-2.4c.5-.3 1 0 1 .6v7c0 .6-.5.9-1 .6l-3.5-2.4z" fill="currentColor"/>',
  waveform: '<path d="M3 11v2M6 8.5v7M9 5.5v13M12 9v6M15 3.5v17M18 7.5v9M21 10.5v3" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
  restart: '<path d="M8.3 5.6A7.4 7.4 0 1 1 5.4 15" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><path d="M9.6 2.2L7.3 6.5l4.6 1.3" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
  record: '<circle cx="12" cy="12" r="8.6" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="12" r="4" fill="currentColor"/>',
  arrowFwd: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M7.5 12h8.6M12.6 8.4l3.6 3.6-3.6 3.6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',
  arrowUpFill: '<circle cx="12" cy="12" r="10" fill="currentColor"/><path d="M12 17.2V7.4M7.8 11.4L12 7.2l4.2 4.2" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
  play: '<path d="M8 5.2v13.6c0 .7.8 1.1 1.4.7l10.3-6.8c.5-.3.5-1.1 0-1.4L9.4 4.5C8.8 4.1 8 4.5 8 5.2z" fill="currentColor"/>',
  speedometer: '<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M4.2 16.8a8.6 8.6 0 1 1 15.6 0"/><path d="M12 13.6l3.6-4.4M5.6 12.2h1.3M12 5.3v1.3M18.4 12.2h-1.3M7.4 7.7l.9.9"/></g><circle cx="12" cy="13.8" r="1.6" fill="currentColor"/>',
  textCheck: '<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h12M3 10.5h12M3 15h6.5"/><path d="M12.8 17.4l2.6 2.6 5.4-6"/></g>',
  pauseCircle: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M9.8 8.4v7.2M14.2 8.4v7.2" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/>',
  ellBubble: '<path d="M12 3.6c5 0 9 3.3 9 7.4s-4 7.4-9 7.4c-.9 0-1.8-.1-2.6-.3L5 20.3l.9-3.6C4 15.3 3 13.3 3 11c0-4.1 4-7.4 9-7.4z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><g fill="currentColor"><circle cx="8.2" cy="11" r="1.2"/><circle cx="12" cy="11" r="1.2"/><circle cx="15.8" cy="11" r="1.2"/></g>',
  wavePath: '<path d="M2.5 12c1.3 0 1.6-3.6 2.8-3.6S6.8 16 8.1 16s1.6-11 2.9-11 1.6 14 2.9 14 1.6-10.2 2.9-10.2 1.5 6.4 2.8 6.4 1.4-3.2 2.9-3.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
  save: '<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.5v11M8 10.6l4 4 4-4"/><path d="M7 8H5.6A1.6 1.6 0 0 0 4 9.6v9.3a1.6 1.6 0 0 0 1.6 1.6h12.8a1.6 1.6 0 0 0 1.6-1.6V9.6A1.6 1.6 0 0 0 18.4 8H17"/></g>',
};
/* medal.fill, traced from the capture at 64pt (its own 24×29 box) */
const MEDAL = `<svg class="g" viewBox="0 0 24 29" style="width:57px;height:69px" aria-hidden="true"><g fill="currentColor" stroke="currentColor" stroke-width=".5" stroke-linejoin="round">
  <path d="M5.3 .2h13.4L14.8 6.9H9.2z"/><path d="M3.5 1.1l5.7 10.2-5 3.3L.2 6.7z"/><path d="M20.5 1.1l-5.7 10.2 5 3.3 4-7.9z"/></g>
  <circle cx="12" cy="20.8" r="8.1" fill="currentColor" stroke="#F2F2F7" stroke-width="2.2" paint-order="stroke"/>
  <path d="M12 15.9l1.45 2.95 3.25.47-2.35 2.3.55 3.24L12 23.33l-2.9 1.53.55-3.24-2.35-2.3 3.25-.47z" fill="#fff" stroke="#fff" stroke-width=".7" stroke-linejoin="round"/></svg>`;
const sf = (n, cls = "g") => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${SF[n]}</svg>`;

/* Chrome strings, from Localizable.xcstrings (ko) and the English keys. */
const TX = {
  ko: {
    speech: "스피치", challenges: "챌린지", challenge: "챌린지", scripts: "원고",
    boardNote: "모두 같은 원고로 겨뤄요. 가장 잘한 기록이 순위에 올라가요.",
    taking: n => `${n}명 도전 중`, sec: n => `${n}초`, min: n => `${n}분`,
    camNote: "카메라를 켜야 순위에 올라가요. 영상은 내 폰에만 남아요.",
    up: (r, n) => `${n}명 중 ${r}위로 올라갔어요`,
    upTitle: (a, b) => `${a}위 → ${b}위`, podium: r => `${r}위예요`,
    toNext: (p, r) => `${r}위까지 ${p}점 남았어요`, ahead: p => `2위보다 ${p}점 앞서 있어요`,
    you: "나", board: "리더보드 보기", done: "완료", date: "10월 10일 오후 8:20",
    save: "사진에 저장", aa: "가가", sample: "예시",
    /* SpeechCoach writes these in the learner's native language — one sentence, one instruction. */
    head: "이 원고를 지금까지 읽은 것 중 가장 또렷하고 안정적이에요.", tip: "마지막 문장은 마침표에서 확실히 끝내 보세요.",
    playTake: "내 녹음 듣기", measured: "측정 결과", heard: "마이크가 들은 내용",
    m: { acc: "정확도", pace: "말하기 속도", pauses: "쉼", fillers: "군말", steady: "목소리 안정감",
      wpm: n => `분당 ${n}단어`, band: (a, b) => `적정 범위 ${a}–${b}`, of: (a, b) => `${a} / ${b}`,
      breaths: "문장 끝에서 쉰 횟수", hold: "문장 끝까지 목소리에 힘이 있었는지" },
    genre: { person: "인물", explainer: "설명", own: "내 원고" },
  },
  en: {
    speech: "Speech", challenges: "Challenges", challenge: "Challenge", scripts: "Scripts",
    boardNote: "Everyone reads the same script. Your best take goes on the board.",
    taking: n => `${n} taking part`, sec: n => `${n} sec`, min: n => `${n} min`,
    camNote: "The board only takes camera takes. Your video stays on your phone.",
    up: (r, n) => `Up to #${r} of ${n}`,
    upTitle: (a, b) => `#${a} → #${b}`, podium: r => `You're #${r}`,
    toNext: (p, r) => `${p} point${p === 1 ? "" : "s"} to #${r}`, ahead: p => `${p} point${p === 1 ? "" : "s"} ahead of #2`,
    you: "You", board: "See the leaderboard", done: "Done", date: "Oct 10, 8:20 PM",
    save: "Save to Photos", aa: "", sample: "Sample",
    head: "Steady and clear — your best read of this one yet.", tip: "Land the last sentence on a full stop.",
    playTake: "Play your take", measured: "Measured", heard: "What the mic heard",
    m: { acc: "Accuracy", pace: "Pace", pauses: "Pauses", fillers: "Fillers", steady: "Steady voice",
      wpm: n => `${n} words/min`, band: (a, b) => `Comfortable: ${a}–${b}`, of: (a, b) => `${a} of ${b}`,
      breaths: "Breaths at sentence ends", hold: "Holding your volume to the end of each sentence" },
    genre: { person: "Person", explainer: "Explainer", own: "My script" },
  },
};

/* The bundled sample, the first challenge (SpeechLibrary.builtInBodies.en). */
const BODY = [
  "Have you ever had the perfect sentence in your head, only to watch it fall apart the moment you said it?",
  "Speaking is a skill, not just knowledge. You can know the words and the grammar, but if your mouth has never actually built the sentence, it tends to let you down when it matters. That's why practice has to happen out loud.",
  "Saying things aloud also helps them stick. Research suggests we remember what we've said better than what we've only read.",
];
const SAMPLE = "Why practise out loud?";   // SpeechLibrary.builtInTitles.en — BODY's title
const ME = "Jiwoo";   // a sample learner — never a real person's name in public material

class NwSpeech extends NwScreen {
  static poses = ["list", "open", "camera", "prompter", "result", "challenge", "rank-up"];
  constructor() {
    super(`
      :host{--blue:#0A5CF5;--sys:#0088FF;--red:#FF383C;--green:#34C759;--orange:#FF8D28;--sec:#8A8A8E;--sep:#C6C6C8}
      .g{width:1em;height:1em;display:block;flex:0 0 auto}
      .press{transition:transform .12s ease-out}
      .press.dn{transform:scale(.92)}

      /* ── Speech tab: List(.insetGrouped), inline-large title ── */
      .l-list{background:#F2F2F7}
      .lt{position:absolute;left:16px;top:62px;height:44px;line-height:44px;font-family:var(--pixel);font-size:34px;letter-spacing:0}
      .nb{position:absolute;right:16px;top:62px;width:44px;height:44px;border-radius:22px;background:rgba(255,255,255,.9);box-shadow:0 2px 14px rgba(0,0,0,.07),inset 0 0 0 .5px rgba(0,0,0,.05);display:grid;place-items:center;color:#000;font-size:21px}
      .hd{position:absolute;left:36px;font-size:17px;font-weight:600;color:var(--sec);transform:translateY(-50%)}
      .ft{position:absolute;left:36px;right:36px;font-size:13px;line-height:18px;color:var(--sec);transform:translateY(-50%)}
      .grp{position:absolute;left:16px;right:16px;background:#fff;border-radius:26px;overflow:hidden}
      .srow{position:relative;height:73px;display:flex;align-items:center;transition:background .2s}
      .srow+.srow::before{content:"";position:absolute;left:75px;right:0;top:0;height:.5px;background:var(--sep)}
      .srow .si{position:absolute;left:15px;width:32px;display:grid;place-items:center;color:var(--blue);font-size:24px}
      .srow .st{position:absolute;left:59px;right:40px;top:16px;font-size:17px;line-height:22px;font-weight:500;letter-spacing:-.25px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .srow .sm{position:absolute;left:59px;top:39px;font-size:13px;line-height:18px;color:var(--sec);display:flex;gap:6px;align-items:center}
      .srow .ch{position:absolute;right:16px;color:#BCBCC0;font-size:15px}
      .srow.tap{background:#E5E5EA}
      .faces{display:flex;margin-right:1px}
      .faces i{width:22px;height:22px;border-radius:50%;background:#E3E3E8;box-shadow:0 0 0 2px #fff;font:600 10px/22px ui-rounded,var(--sans);color:var(--sec);text-align:center;font-style:normal;margin-right:-7px;position:relative}
      .faces i:last-child{margin-right:0}
      /* nochallenges: the tab and result page as shipped before challenges */
      .noch .ch-only,.noch .ehd,.noch .entry{display:none}
      .noch .shd{top:135px!important}.noch .scripts{top:156px!important}
      .noch .vid{top:366px}
      .ownr .ehd,.ownr .entry{display:none}.ownr .vid,.ownr .aud{top:366px}   /* an own script: no challenge section, playback moves up */

      /* ── Prompter (SpeechPrompterView) ── */
      .l-prompt{background:#fff}
      .pm{position:absolute;left:0;right:0;top:50px;height:400px;overflow:hidden;
        -webkit-mask-image:linear-gradient(transparent 0,#000 1.5%,#000 86%,transparent 100%);mask-image:linear-gradient(transparent 0,#000 1.5%,#000 86%,transparent 100%)}
      .pt{position:absolute;left:24px;width:354px;top:58.4px;font-size:28px;line-height:43.2px;font-weight:600;letter-spacing:.2px;transition:transform .9s ease}
      .pt p{margin:0 0 15.4px}
      .card{position:absolute;left:8px;right:8px;top:451px;bottom:8px;border-radius:24px 24px 54px 54px;overflow:hidden;background:#F2F2F7}
      .cam{position:absolute;inset:0;background:linear-gradient(rgb(191,191,191),rgb(140,107,89),rgb(51,51,51));opacity:0;transition:opacity .45s}
      .cam.on{opacity:1}
      .micb{position:absolute;left:0;right:0;top:0;bottom:70px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;transition:opacity .3s}
      .micb .mg{color:#8A8A8E;font-size:41px;transition:color .2s,transform .12s}
      .micb .mg.rec{color:var(--red)}
      .micb .note{font-size:13px;line-height:18px;color:var(--sec);text-align:center;padding:0 32px;display:none}
      .micb.note-on .note{display:block}
      .tb{position:absolute;left:20px;right:20px;top:461px;height:36px;display:flex;align-items:center;justify-content:space-between}
      .tb .grpb{display:flex;gap:8px}
      .cb{width:36px;height:36px;border-radius:50%;background:#CFDBF7;color:var(--blue);display:grid;place-items:center;font-size:26px;transition:opacity .2s,background .3s,color .3s}
      .cb .aa{font-size:16px;font-weight:600;letter-spacing:-1px}
      .cb .aa small{font-size:12px}
      .tb .hide{transition:opacity .2s}
      .rec-on .tb .hide{opacity:0}
      .chip{position:absolute;left:50%;top:461px;height:36px;transform:translateX(-50%);display:flex;align-items:center;gap:6px;padding:0 12px;border-radius:18px;background:rgba(255,255,255,.2);color:var(--red);font-size:15px;font-weight:600;font-variant-numeric:tabular-nums;opacity:0;transition:opacity .2s}
      .chip .g{font-size:21px}
      .rec-on .chip{opacity:1}
      .ctl{position:absolute;left:0;right:0;top:756px;height:76px;display:flex;justify-content:center;align-items:center;gap:36px}
      .rb{width:52px;height:52px;border-radius:50%;background:#CFDBF7;color:var(--blue);display:grid;place-items:center;font-size:29px;position:relative;transition:background .3s,color .3s}
      .rb .g{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);transition:opacity .2s}
      .rb .alt{opacity:0}
      .rec-on .rb .alt{opacity:1}.rec-on .rb .pri{opacity:0}
      .recb{position:relative;width:76px;height:76px;border-radius:50%;box-shadow:inset 0 0 0 4px rgba(120,120,128,.42),0 2px 6px rgba(0,0,0,.2);transition:box-shadow .3s}
      .recb i{position:absolute;left:50%;top:50%;width:62px;height:62px;margin:-31px 0 0 -31px;border-radius:31px;background:var(--red);transition:all .25s ease}
      .rec-on .recb i{width:30px;height:30px;margin:-15px 0 0 -15px;border-radius:6px}
      .cam-on .cb,.cam-on .rb{background:rgba(40,40,40,.55);color:#fff;-webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px)}
      .cam-on .recb{box-shadow:inset 0 0 0 4px #fff,0 2px 6px rgba(0,0,0,.2)}
      .cam-on .micb{opacity:0}
      .cam-on .chip{background:rgba(255,255,255,.55)}

      /* ── Result (SpeechResultView, List insetGrouped) ── */
      .l-result{background:#F2F2F7}
      .rdate{position:absolute;left:0;right:0;top:62px;height:44px;line-height:44px;text-align:center;font-family:var(--pixel);font-size:17px;letter-spacing:0}
      .rcard{position:absolute;left:16px;right:16px;top:156px;height:174px;border-radius:26px;background:#fff}
      .gauge{position:absolute;left:34px;top:23.5px;width:75px;height:75px}
      .gauge svg{width:100%;height:100%;transform:rotate(-90deg)}
      .gauge .arc{transition:stroke-dashoffset 1.1s cubic-bezier(.3,.7,.2,1)}
      .gauge b{position:absolute;inset:0;display:grid;place-items:center;font-size:29px;font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:-.5px}
      .head{position:absolute;left:114px;right:16px;top:39px;font-size:17px;line-height:22.5px;font-weight:500;letter-spacing:-.3px}
      .rsep{position:absolute;left:114px;right:16px;top:121px;height:.5px;background:var(--sep)}
      .tip{position:absolute;left:18px;right:16px;top:137px;height:24px;display:flex;align-items:center;gap:18px;font-size:15px;letter-spacing:-.2px}
      .tip .g{font-size:22px;color:var(--blue)}
      .entry{position:absolute;left:16px;right:16px;top:389px;height:52px;border-radius:26px;background:#fff;display:flex;align-items:center;gap:12px;padding:0 18px;color:var(--green);font-size:17px;font-weight:600}
      .entry .g{font-size:22px}
      .vid{position:absolute;left:16px;right:16px;top:477px;height:440px;border-radius:26px;background:#fff;padding:8px}
      /* a camera take: the picture is the prompter's camera stand-in (SpeechTakeVideo: play.fill 30pt in a 68pt dark material circle) */
      .vid div{height:100%;border-radius:12px;background:linear-gradient(rgb(191,191,191),rgb(140,107,89),rgb(51,51,51));display:grid;place-items:center}
      .vid span{width:68px;height:68px;border-radius:50%;background:rgba(40,40,40,.45);-webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);display:grid;place-items:center;color:#fff;font-size:30px}
      /* a mic-only take (playbackSection's else-branch): Play your take, then Measured, then the transcript disclosure */
      .aud{position:absolute;left:16px;right:16px;top:477px;display:none}
      .noch .aud{top:366px}
      .aud.on{display:block}
      .acard{background:#fff;border-radius:26px;overflow:hidden}
      .arow{position:relative;min-height:52px;box-sizing:border-box;padding:11px 16px 11px 58px;display:flex;align-items:center;gap:8px;font-size:17px;letter-spacing:-.25px}
      .arow+.arow::before{content:"";position:absolute;left:58px;right:0;top:0;height:.5px;background:var(--sep)}
      .arow>.g{position:absolute;left:18px;top:15px;font-size:22px;color:var(--blue)}
      .arow.two>.g{top:11px}   /* Label's icon sits on the title's line, not the row's middle */
      .arow.btn{color:var(--blue)}
      .arow .lb{flex:1;align-self:flex-start;line-height:22px}
      .arow .vv{text-align:right;line-height:22px;font-variant-numeric:tabular-nums}
      .arow .vv small{display:block;font-size:12px;line-height:16px;color:var(--sec);margin-top:2px;max-width:200px;margin-left:auto}
      .arow .vv.ok{color:var(--green)}.arow .vv.mid{color:var(--orange)}.arow .vv.bad{color:var(--red)}
      .arow .vv.ok small,.arow .vv.mid small,.arow .vv.bad small{color:var(--sec)}
      .arow.dg{padding-left:16px}.arow.dg .g{position:static;margin:0;font-size:14px;color:var(--blue)}
      .ahd{height:59px;position:relative}.ahd span{position:absolute;left:17px;top:38px;transform:translateY(-50%);font-size:17px;font-weight:600;color:var(--sec)}
      .agap{height:36px}
      .dim{position:absolute;inset:0;background:rgba(0,0,0,.2);opacity:0;transition:opacity .4s;z-index:5}
      .dim.on{opacity:1}
      .sheet{position:absolute;left:8.5px;right:8.5px;top:415px;bottom:8px;border-radius:40px 40px 54px 54px;background:#F2F2F7;transform:translateY(110%);transition:transform .55s cubic-bezier(.3,.8,.2,1);z-index:6;text-align:center;box-shadow:0 0 24px rgba(0,0,0,.06)}
      .sheet.on{transform:none}
      .grab{position:absolute;left:50%;top:5px;width:36px;height:5px;margin-left:-18px;border-radius:3px;background:#C3C3C7}
      .mi{position:absolute;left:50%;top:24px;width:62px;height:62px;margin-left:-31px;font-size:62px;display:grid;place-items:center;color:var(--green);transition:transform .35s cubic-bezier(.3,1.6,.5,1)}
      .mi.med{top:31px;height:69px}
      .sheet.pod h4{top:117px}.sheet.pod .sub{top:153px}.sheet.pod .rk{top:192px}
      .mi.pop{transform:scale(1.12)}
      .sheet h4{position:absolute;left:24px;right:24px;top:107px;margin:0;font-size:28px;line-height:34px;font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:-.2px}
      .sheet .sub{position:absolute;left:24px;right:24px;top:143px;font-size:17px;line-height:22px;color:var(--sec)}
      .rk{position:absolute;left:16px;right:16px;top:182px;border-radius:14px;overflow:hidden;background:#fff;text-align:left}
      .rk .r{position:relative;height:41px;display:flex;align-items:center;gap:12px;padding:0 16px;font-size:17px;font-variant-numeric:tabular-nums}
      .rk .r+.r::before{content:"";position:absolute;left:56px;right:0;top:0;height:.5px;background:var(--sep)}
      .rk .r.me{background:#E0F1FF}
      .rk .n{min-width:28px;color:#6E6E73}
      .rk .n.top{color:var(--blue);font-weight:700}
      .rk .nm{flex:1;display:flex;gap:12px;align-items:baseline}
      .rk .me .nm b{font-weight:600}
      .rk .nm small{font-size:12px;font-weight:600;color:var(--sys)}
      .rk .sc{font-weight:600;color:var(--green)}
      .sbtn{position:absolute;left:16px;right:16px;bottom:67px;height:44px;border-radius:22px;background:var(--blue);color:#fff;display:grid;place-items:center;font-size:17px;font-weight:600}
      .sdone{position:absolute;left:0;right:0;bottom:36px;font-size:17px;color:var(--blue)}
    `, `
      <div class="layer l-list on">
        <div class="lt"></div><span class="nb">${sf("plus")}</span>
        <div class="hd ch-only" style="top:135px" data-x="challenges"></div>
        <div class="grp ch-only" style="top:156px"><div class="srow chal"><span class="si">${sf("trophy")}</span>
          <span class="st">Why practise out loud?</span><span class="sm ct"></span><span class="ch">${sf("chevR")}</span></div></div>
        <div class="ft ch-only" style="top:244px" data-x="boardNote"></div>
        <div class="hd shd" style="top:278px" data-x="scripts"></div>
        <div class="grp scripts" style="top:299px"></div>
      </div>
      <div class="layer l-prompt">
        <div class="pm"><div class="pt">${BODY.map(p => `<p>${esc(p)}</p>`).join("")}</div></div>
        <div class="card"><div class="cam"></div>
          <div class="micb"><span class="mg">${sf("mic")}</span><span class="note"></span></div></div>
        <div class="tb"><span class="cb hide">${sf("xmark")}</span>
          <span class="grpb hide"><span class="cb">${sf("doc")}</span><span class="cb">${sf("history")}</span><span class="cb aaa"></span></span></div>
        <div class="chip">${sf("record")}<span class="tm">0:00</span></div>
        <div class="ctl"><span class="rb press camb"><span class="pri">${sf("videoSlash")}</span><span class="pri on-ic" style="display:none">${sf("video")}</span><span class="alt">${sf("xmark")}</span></span>
          <span class="recb press"><i></i></span>
          <span class="rb"><span class="pri">${sf("waveform")}</span><span class="alt">${sf("restart")}</span></span></div>
      </div>
      <div class="layer l-result">
        <div class="rdate"></div>
        <div class="hd rtitle" style="top:136px;left:33px">How noise-cancelling headphones work</div>
        <div class="rcard"><div class="gauge"><svg viewBox="0 0 75 75"><circle class="trk" cx="37.5" cy="37.5" r="34.25" fill="none" stroke="var(--orange)" stroke-opacity=".35" stroke-width="6.5"/><circle class="arc" cx="37.5" cy="37.5" r="34.25" fill="none" stroke="var(--orange)" stroke-width="6.5" stroke-linecap="round" stroke-dasharray="215.2" stroke-dashoffset="215.2"/></svg><b>0</b></div>
          <div class="head"></div>
          <div class="rsep"></div>
          <div class="tip">${sf("arrowFwd")}<span class="tipt"></span></div></div>
        <div class="hd ehd" style="top:368px;left:33px" data-x="challenge"></div>
        <div class="entry">${sf("arrowUpFill")}<span class="et"></span></div>
        <div class="vid"><div><span>${sf("play")}</span></div></div>
        <div class="aud"></div>
        <div class="dim"></div>
        <div class="sheet"><div class="grab"></div><span class="mi"></span><h4></h4><div class="sub"></div><div class="rk"></div>
          <div class="sbtn" data-x="board"></div><div class="sdone" data-x="done"></div></div>
      </div>`);
  }
  get x() { return this.t === STR.ko ? TX.ko : TX.en; }
  get noCh() { return this.hasAttribute("nochallenges"); }
  static observedAttributes = ["active", "script-title", "script-text", "script-seconds"];
  attributeChangedCallback(name) {
    if (name.startsWith("script-")) { if (this._built) this._scriptFromAttrs(true); return; }
    super.attributeChangedCallback();
  }
  /** The learner's own script: { title, text, seconds } or null for the samples. */
  get script() { return this._own || null; }
  set script(v) {
    if (v) {
      const paras = (Array.isArray(v.text) ? v.text : String(v.text || "").split(/\n+/)).map(p => p.trim()).filter(Boolean);
      // seconds: the script's own length; else ~2.5 words a second (Hangul/kana: ~6 characters)
      const n = paras.join(" "), words = /[\u3040-\u30ff\uac00-\ud7af\u4e00-\u9fff]/.test(n) ? n.replace(/\s/g, "").length / 2.4 : n.split(/\s+/).length;
      this._own = { title: v.title || "", paras, seconds: +v.seconds || Math.max(5, Math.round(words / 2.5)) };
    } else this._own = null;
    if (this._built) { this._applyScript(); this.reset(); }
  }
  _scriptFromAttrs(force) {
    const a = k => this.getAttribute(k);
    if (a("script-title") != null || a("script-text") != null) this.script = { title: a("script-title"), text: a("script-text"), seconds: a("script-seconds") };
    else if (force) this.script = null;
  }
  /* what depends on the script: the prompter's text and the Scripts list */
  _applyScript() {
    const paras = this._own?.paras.length ? this._own.paras : BODY;
    this.$(".pt").innerHTML = paras.map(p => `<p>${esc(p)}</p>`).join("");
    this.scripts(this._rows);
  }
  build() {
    const x = this.x;
    this.$(".lt").textContent = x.speech;
    this.$$("[data-x]").forEach(e => e.textContent = x[e.dataset.x]);
    this.$(".note").textContent = x.camNote;
    this.$(".rdate").textContent = x.date;
    this.$(".head").textContent = x.head;
    this.$(".tipt").textContent = x.tip;
    this.$(".l-list").parentNode.classList.toggle("noch", this.noCh);
    if (this.noCh) this.$(".rtitle").textContent = SAMPLE;
    this.$(".aaa").innerHTML = x.aa ? `<span class="aa">${x.aa}</span>` : `<span class="aa"><small>A</small>A</span>`;
    this._rtitle = this.$(".rtitle").textContent;
    this._scriptFromAttrs();
    this._applyScript();
    this.audio();
    this.taking(41);
    this.reset();
  }
  /* The challenge row: "N taking part · 1 min", the board's top three as initials once there is a board. */
  taking(n) {
    const x = this.x;
    const faces = n > 0 ? `<span class="faces"><i style="z-index:3">C</i><i style="z-index:2">H</i><i style="z-index:1">M</i></span>` : "";
    this.$(".ct").innerHTML = `${faces}<span>${x.taking(n)}</span><span>·</span><span>${x.min(1)}</span>`;
  }
  scripts(rows) {
    const x = this.x, g = x.genre;
    this._rows = rows;
    rows ??= [["person", "Marie Curie, twice a Nobel winner", 27, g.person], ["bulb", "Why the sky is blue", 11, g.explainer],
      ["bulb", "How noise-cancelling works", 32, g.explainer], ["pencilLine", "My team intro for Monday", 45, g.own],
      ["person", "Ada Lovelace and the first program", 38, g.person], ["bulb", "Why bread rises", 24, g.explainer],
      ["person", "Nelson Mandela's long walk", 41, g.person], ["pencilLine", "A toast for Sam's leaving drinks", 30, g.own]];
    // Before challenges the bundled sample was an ordinary row, always first (SpeechStore.reload).
    // The learner's own script is the newest save, so the first saved row (SpeechStore.reload).
    if (this._own) rows = [["pencilLine", this._own.title, this._own.seconds, g.own, false, true], ...rows.slice(0, -1)];
    if (this.noCh) rows = [["bulb", SAMPLE, 0, g.explainer, true], ...rows.slice(0, -1)];
    this.$(".scripts").innerHTML = rows.map(([i, ti, s, b, sample, own]) =>
      `<div class="srow${own ? " own" : ""}"><span class="si">${sf(i)}</span><span class="st">${esc(ti)}</span><span class="sm"><span>${sample ? x.min(1) : x.sec(s)}</span><span>·</span><span>${esc(b)}</span>${sample ? `<span>·</span><span>${esc(x.sample)}</span>` : ""}</span></div>`).join("");
  }
  /* SpeechResultView for a take with no video: playbackSection's audio row, "Measured" (metricRow ×5,
   * value tinted by SpeechScoreColor: ≥85 green, ≥65 orange, else red), the transcript disclosure.
   * A sample English read: 148 words/min inside 120–160 (SpeechLibrary.rateBand), so Pace reads green. */
  audio() {
    const x = this.x, m = x.m;
    const tone = s => s >= 85 ? "ok" : s >= 65 ? "mid" : "bad";
    const row = (icon, label, value, score, detail) =>
      `<div class="arow${detail ? " two" : ""}">${sf(icon)}<span class="lb">${esc(label)}</span><span class="vv ${tone(score)}">${esc(value)}${detail ? `<small>${esc(detail)}</small>` : ""}</span></div>`;
    this.$(".aud").innerHTML =
      `<div class="acard"><div class="arow btn">${sf("play")}<span class="lb">${esc(x.playTake)}</span></div></div>
      <div class="ahd"><span>${esc(x.measured)}</span></div>
      <div class="acard">${row("textCheck", m.acc, "94%", 94)}${row("speedometer", m.pace, m.wpm(148), 100, m.band(120, 160))}${row("pauseCircle", m.pauses, m.of(4, 5), 80, m.breaths)}${row("ellBubble", m.fillers, "2", 80)}${row("wavePath", m.steady, "76", 76, m.hold)}</div>
      <div class="agap"></div>
      <div class="acard"><div class="arow dg"><span class="lb">${esc(x.heard)}</span>${sf("chevR")}</div></div>`;
  }
  /** The gauge's arc and track take SpeechScoreColor.color(overall) (SpeechTab.swift): ≥85 green, ≥65 orange, else red.
   * Set from the FINAL score before the count-up, so the ring never changes colour mid-animation. */
  tint(score) {
    const c = score >= 85 ? "var(--green)" : score >= 65 ? "var(--orange)" : "var(--red)";
    this.$(".arc").setAttribute("stroke", c); this.$(".gauge .trk").setAttribute("stroke", c);
  }
  /** The result's lower half follows the take: a camera take shows its video, a mic-only take the audio row + Measured. */
  takeKind(camera) { this.$(".vid").style.visibility = camera ? "" : "hidden"; this.$(".aud").classList.toggle("on", !camera); }
  show(name) { this.$$(".layer").forEach(l => l.classList.toggle("on", l.classList.contains("l-" + name))); }
  setCamera(on) {
    const p = this.$(".l-prompt");
    p.classList.toggle("cam-on", on); this.$(".cam").classList.toggle("on", on);
    const [off, onI] = this.$$(".camb .pri"); off.style.display = on ? "none" : ""; onI.style.display = on ? "" : "none";
    this.$(".micb").classList.toggle("note-on", !on && this._challenge && !p.classList.contains("rec-on"));
  }
  setRecording(on) {
    this.$(".l-prompt").classList.toggle("rec-on", on);
    this.$(".mg").classList.toggle("rec", on);
    this.$(".micb").classList.toggle("note-on", !on && this._challenge && !this.$(".l-prompt").classList.contains("cam-on"));
  }
  reset() {
    this.show("list"); this.$$(".srow").forEach(r => r.classList.remove("tap"));
    this.$(".pt").style.transform = "none"; this.$(".tm").textContent = "0:00";
    this._challenge = !this.noCh; this._opened = null; this.setRecording(false); this.setCamera(false);
    this.$(".rtitle").textContent = this.noCh ? SAMPLE : this._rtitle; this._ownResult(false);
    this.$(".arc").style.strokeDashoffset = 215.2; this.$(".gauge b").textContent = "0";
    this.$(".entry").style.visibility = "hidden"; this.takeKind(true);
    this.$(".dim").classList.remove("on"); this.$(".sheet").classList.remove("on");
  }
  _ownResult(on) {
    this.$(".l-result").classList.toggle("ownr", !!on);
    if (on) this.$(".rtitle").textContent = this._own.title;
  }
  async tap(el, ms = 160) { el.classList.add("dn"); await this.sleep(ms); el.classList.remove("dn"); }
  /** Tap a row and open the prompter. which: "own" (the default when a script is set) or "challenge". */
  async open(which) {
    const own = this._own && which !== "challenge";
    const r = own ? this.$(".scripts .srow.own") : this.noCh ? this.$(".scripts .srow") : this.$(".chal");
    r.classList.add("tap"); await this.sleep(260); r.classList.remove("tap");
    this._opened = own ? "own" : null;
    this._ownResult(own);
    this._challenge = !this.noCh && !own; this.setRecording(false); this.setCamera(false);
    this.show("prompt"); await this.sleep(500);
  }
  /** Turn the camera on (or off) from the card's left button — only offered before a take. */
  async camera(on = true) { await this.tap(this.$(".camb")); this.setCamera(on); await this.sleep(500); }
  async record(ms = 4600, seconds = 21) {
    await this.tap(this.$(".recb"), 140); this.setRecording(true);
    this.countUp(this.$(".tm"), seconds, ms, mmss);
    const steps = 4; for (let s = 1; s <= steps; s++) { await this.sleep(ms / (steps + .5)); this.$(".pt").style.transform = `translateY(${-s * 43.2}px)`; }
    await this.sleep(ms / (steps + .5) / 2);
  }
  async result(score = 81, rank = 14, of = 41) {
    if (!this.noCh && this._opened !== "own") { this.$(".et").textContent = this.x.up(rank, of); this.$(".entry").style.visibility = ""; }
    this.takeKind(this.$(".l-prompt").classList.contains("cam-on"));
    this.show("result"); await this.sleep(400);
    this.tint(score);
    this.$(".arc").style.strokeDashoffset = 215.2 * (1 - score / 100);
    await this.countUp(this.$(".gauge b"), score, 1100);
  }
  /** SpeechChallengeMomentSheet. kind: "up" (moved up, outside the top three) or "podium" (rank 1–3). */
  moment({ kind = "up", rank, from, rows }) {
    const x = this.x;
    const medal = { 1: "#FFCC00", 2: "#8E8E93", 3: "#A2785C" }[rank] || "#A2785C";
    const mi = this.$(".mi");
    mi.innerHTML = kind === "podium" ? MEDAL : sf("arrowUpFill");
    mi.style.color = kind === "podium" ? medal : "var(--green)"; mi.classList.toggle("med", kind === "podium"); this.$(".sheet").classList.toggle("pod", kind === "podium");
    this.$(".sheet h4").textContent = kind === "podium" ? x.podium(rank) : x.upTitle(from, rank);
    const meI = rows.findIndex(([n]) => !n), me = rows[meI], above = rows[meI - 1], below = rows[meI + 1];
    this.$(".sub").textContent = rank === 1 && below ? x.ahead(me[1] - below[1]) : above ? x.toNext(Math.max(1, above[1] - me[1]), rank - 1) : "";
    this.$(".rk").innerHTML = rows.map(([n, s], i) => {
      const r = rank - meI + i;
      return `<div class="r${n ? "" : " me"}"><span class="n${r <= 3 ? " top" : ""}">${r}</span><span class="nm">${n ? esc(n) : `<b>${ME}</b><small>${esc(x.you)}</small>`}</span><span class="sc">${s}</span></div>`;
    }).join("");
  }
  async rankUp(from = 14, to = 8, rows = [["Camille", 88], [null, 87], ["Yuna", 85]]) {
    if (this.noCh || this._opened === "own") return;   // no board before challenges, none on an own script
    this.moment({ kind: to <= 3 ? "podium" : "up", rank: to, from, rows });
    this.$(".dim").classList.add("on"); this.$(".sheet").classList.add("on");
    await this.sleep(560); const mi = this.$(".mi"); mi.classList.add("pop"); await this.sleep(240); mi.classList.remove("pop");
  }
  async pose(name) {
    this.stop(); this.reset();
    const ko = this.t === STR.ko;
    if (name === "list") { this.taking(0); return; }
    if (["open", "camera", "prompter"].includes(name)) {
      this.show("prompt"); this._challenge = false;
      if (name === "camera") this.setCamera(true);
      if (name === "prompter") { this.setRecording(true); this.$(".tm").textContent = "0:21"; }
      else this.setRecording(false);
      return;
    }
    // result page under the moment sheet
    this.show("result"); this.$(".et").textContent = this.x.up(14, 41); this.$(".entry").style.visibility = "";
    this.tint(81); this.$(".arc").style.strokeDashoffset = 215.2 * (1 - .81); this.$(".gauge b").textContent = "81";
    if (name === "result") this.moment({ kind: "podium", rank: 3, rows: [["Haruto", 94], [null, 93], ["Lena", 91]] });
    if (name === "challenge") this.moment({ kind: "podium", rank: 1, rows: [[null, 97], ["Minji", 96]] });
    if (name === "rank-up") this.moment({ kind: "up", rank: 8, from: 14, rows: [["Camille", 88], [null, 87], ["Yuna", 85]] });
    this.takeKind(false); // the simulator takes are mic-only: the audio row + Measured, as under the capture's sheet
    // an own script's result: its title, no challenge entry, no sheet
    if (this._own && name === "result") { this._opened = "own"; this._ownResult(true); return; }
    if (this.noCh) { this.$(".entry").style.visibility = "hidden"; return; }   // every result pose: the page alone
    this.$(".dim").classList.add("on"); this.$(".sheet").classList.add("on");
    void ko;
  }
  async demo() {
    await this.sleep(1300); await this.open(); await this.sleep(600);
    // With challenges the board only takes camera takes, so the camera goes on. Before challenges
    // nothing asked for it and the default is off (SpeechPrompterView), so that take is mic-only.
    const board = !this.noCh && this._opened !== "own";
    if (board) { await this.camera(true); await this.sleep(500); }
    this.beat(1); await this.record();
    await this.sleep(500); this.beat(2); await this.result(81); await this.sleep(900);
    if (!board) { await this.sleep(2400); return; }
    await this.rankUp(14, 8); await this.sleep(3200);
  }
}

export { NwSpeech };
