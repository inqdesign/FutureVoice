/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* ═══════════════════════════ <nw-shadow> — sync shadowing ═══════════════════════════
 * ShadowDrillView.swift + ShadowTimelinePlayer.swift. A NavigationStack page ("Shadow", Close on the
 * leading side, the bookmark on the trailing side); a ScrollView (padding 20, top 16, spacing 20)
 * holding the target line — tappable words, each with its beat-dot row under it — then, after a
 * take, the Target / You / Pace cells and "Your take" (score, the diff, what was heard, the playback
 * buttons). The bottom bar is the trimmer card (track with loop handles, time labels, play · loop ·
 * mic · speed · back), or the bare 64pt mic while there is no timeline (recording, a line with no
 * audio). Points from real/shadow.png and shots/device-shadow-{result,loop}.jpg.
 *
 *   sh.line = { text, times?: [[start,end]…] s per word (omit = estimated), phrase?: [a,b] }
 *   sh.take = { heard, score, rhythm?: n|null, dev?: [ms|null per word], target?, you?, pace? }
 *   attributes: line="…" times='[[…]]' heard="…" score="72" rhythm="88"|"none" dev='[…]'
 *   await sh.playTarget(rate)          the target plays: playhead + karaoke
 *   await sh.record(take?)             3·2·1 → the take (red 64pt mic, karaoke on the learner's clock) → result
 *   sh.showResult(take?)               the result, no animation
 *   await sh.both()                    scrolls "Both at once" into view, taps it: the duet plays (transport + karaoke from the first word)
 *   await sh.scrollTo(y)               scroll the result (points)
 *   await sh.loop(a, b, {rate, times}) pick words a..b, loop them, at rate (0.5 · 0.75 · 1 · 1.25)
 *   every awaited method takes { speed } (time compression for video, 1 = real time). */

const SVG = (body, cls = "ic") => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
const ST = 'fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"';
const I = {
  bookmark: SVG(`<path ${ST} stroke-width="2" d="M7.2 3h9.6a1.2 1.2 0 0 1 1.2 1.2V21l-6-4.3L6 21V4.2A1.2 1.2 0 0 1 7.2 3z"/>`),
  mic: SVG('<rect x="8.6" y="2" width="6.8" height="12.6" rx="3.4" fill="currentColor"/><path d="M5.4 11.2a6.6 6.6 0 0 0 13.2 0M12 17.8V21M8.4 21.4h7.2" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
  redo: SVG(`<g ${ST} stroke-width="2.3"><path d="M12 4.3a8 8 0 1 1-7 4.1"/><path d="M12.9 1.6L10.1 4.3l2.8 2.7"/></g>`),
  xmark: SVG(`<path ${ST} stroke-width="2.6" d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>`),
  ellipsis: SVG('<g fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></g>'),
  play: SVG('<circle cx="12" cy="12" r="11" fill="currentColor"/><path d="M9.6 7.4v9.2l7.4-4.6z" fill="#fff" stroke="#fff" stroke-width=".8" stroke-linejoin="round"/>'),
  pause: SVG('<circle cx="12" cy="12" r="11" fill="currentColor"/><rect x="8.4" y="7.4" width="2.6" height="9.2" rx=".8" fill="#fff"/><rect x="13" y="7.4" width="2.6" height="9.2" rx=".8" fill="#fff"/>'),
  repeat: SVG(`<circle cx="12" cy="12" r="10.3" fill="none" stroke="currentColor" stroke-width="1.4"/><g ${ST} stroke-width="1.6"><path d="M7.3 11.4V10.6a1.8 1.8 0 0 1 1.8-1.8h7.4M14.7 6.9l1.9 1.9-1.9 1.9M16.7 12.6v.8a1.8 1.8 0 0 1-1.8 1.8H7.5M9.3 17.1l-1.9-1.9 1.9-1.9"/></g>`),
  repeatOn: SVG(`<circle cx="12" cy="12" r="11" fill="currentColor"/><g fill="none" stroke="#fff" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.7"><path d="M7.3 11.4V10.6a1.8 1.8 0 0 1 1.8-1.8h7.4M14.7 6.9l1.9 1.9-1.9 1.9M16.7 12.6v.8a1.8 1.8 0 0 1-1.8 1.8H7.5M9.3 17.1l-1.9-1.9 1.9-1.9"/></g>`),
  uturn: SVG(`<circle cx="12" cy="12" r="10.3" fill="none" stroke="currentColor" stroke-width="1.4"/><g ${ST} stroke-width="1.6"><path d="M7.6 10.4h6.2a3.3 3.3 0 0 1 0 6.6h-2.6"/><path d="M10.2 7.6L7.4 10.4l2.8 2.8"/></g>`),
  metronome: SVG(`<g ${ST} stroke-width="1.8"><path d="M9.6 3.4h4.8l4 17.2H5.6z"/><path d="M5.9 16.2h12.2M12 16.2l5.4-9.6"/></g>`),
  gauge: SVG(`<circle cx="12" cy="12" r="9.6" fill="none" stroke="currentColor" stroke-width="1.7"/><g fill="currentColor"><circle cx="7.3" cy="14.4" r="1"/><circle cx="7.6" cy="9.4" r="1"/><circle cx="12" cy="6.9" r="1"/></g><path d="M12 13.2l4.2-4.6" ${ST} stroke-width="1.9"/><circle cx="12" cy="13.6" r="1.6" fill="currentColor"/>`),
  alignleft: SVG(`<g ${ST} stroke-width="1.9"><path d="M3.5 5.5h17M3.5 10h11M3.5 14.5h17M3.5 19h9"/></g>`),
  playCircle: SVG(`<circle cx="12" cy="12" r="9.6" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M10 8.2v7.6l6-3.8z" fill="currentColor" stroke="currentColor" stroke-width=".8" stroke-linejoin="round"/>`),
  personWave: SVG(`<g ${ST} stroke-width="1.6"><circle cx="8.6" cy="8.4" r="3.3"/><path d="M2.6 20.2c.5-3.6 2.9-5.6 6-5.6s5.5 2 6 5.6zM15.6 5.4a4.2 4.2 0 0 1 0 6M18.4 3.4a7.4 7.4 0 0 1 0 10"/></g>`),
  persons: SVG(`<g ${ST} stroke-width="1.5"><circle cx="8.2" cy="9" r="2.8"/><circle cx="14.2" cy="9" r="2.8"/><path d="M3 19.4c.4-3 2.4-4.7 5.2-4.7s4.8 1.7 5.2 4.7zM11.2 15c.8-.2 1.9-.3 3-.3 2.8 0 4.8 1.7 5.2 4.7h-4.5M2 6.2a4 4 0 0 0 0 5.6M20.4 6.2a4 4 0 0 1 0 5.6"/></g>`),
};

/* The demo line and its measured shape (deviation ms per word, null = not timed). The website's
   defaults; a page swaps them through `line` / `take`. */
const LINE = {
  text: "Hearing a fluent version of your own voice makes the goal feel so much more attainable and real.",
  times: [[.03, .42], [.45, .52], [.55, .85], [.88, 1.25], [1.28, 1.40], [1.50, 1.66], [1.70, 1.88], [1.92, 2.25], [2.30, 2.58],
    [2.62, 2.72], [2.76, 2.98], [3.00, 3.20], [3.30, 3.50], [3.55, 3.80], [3.85, 4.10], [4.15, 4.85], [4.90, 5.05], [5.10, 5.55]],
  phrase: [5, 11],
};
const TAKE = {
  heard: "hearing a fluent version of your own voice makes the goal feel so much more attainable and real",
  score: 96, rhythm: 88, dev: [40, null, 60, 210, 30, 70, -170, 220, 50, 230, 40, 190, 200, 20, null, 210, null, 50],
  target: 5.7, you: 6.5, pace: 1.13,
};
const CAP = { text: "I really appreciate you taking the time to help me.", sel: [2, 4] };
const tl = s => `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, "0")}`;
/* no word timings given: share the line out by letters, as estimatedTimings does (not measured) */
const estimate = text => {
  let t = .05;
  return text.split(" ").map(w => { const d = .12 + .055 * w.replace(/[^\p{L}\p{N}]/gu, "").length, r = [+t.toFixed(2), +(t + d).toFixed(2)]; t += d + .05; return r; });
};
/* ShadowEngine's word diff: target vs what was heard, case and punctuation folded.
   Steps: match · sub (said differently) · del (skipped) · ins (extra word). */
function align(target, heard) {
  const n = w => w.toLowerCase().replace(/[’]/g, "'").replace(/[^\p{L}\p{N}']/gu, "");
  const T = target.split(" "), H = heard.trim() ? heard.trim().split(/\s+/) : [];
  const a = T.map(n), b = H.map(n), m = a.length, k = b.length;
  const D = Array.from({ length: m + 1 }, (_, i) => Array.from({ length: k + 1 }, (_, j) => i + j));
  for (let i = 1; i <= m; i++) for (let j = 1; j <= k; j++)
    D[i][j] = Math.min(D[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1), D[i - 1][j] + 1, D[i][j - 1] + 1);
  const out = [];
  for (let i = m, j = k; i > 0 || j > 0;) {
    if (i && j && D[i][j] === D[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)) { out.push({ op: a[i - 1] === b[j - 1] ? "match" : "sub", t: T[i - 1], ti: i - 1, h: H[j - 1] }); i--; j--; }
    else if (i && D[i][j] === D[i - 1][j] + 1) { out.push({ op: "del", t: T[i - 1], ti: i - 1 }); i--; }
    else { out.push({ op: "ins", h: H[j - 1] }); j--; }
  }
  return out.reverse();
}
const scoreColor = v => v >= 80 ? "var(--gr)" : v >= 50 ? "var(--ac)" : "var(--or)";
const paceColor = r => r >= .85 && r <= 1.25 ? "var(--gr)" : r >= .7 && r <= 1.5 ? "var(--or)" : "var(--rd)";
const json = v => { try { return v ? JSON.parse(v) : undefined; } catch { return undefined; } };

const L = {
  ko: {
    title: "섀도잉", close: "닫기", target: "원본 문장", tap: "단어를 탭해 구간을 고르세요", picked: "선택한 구간을 연습해요",
    t: "원본", y: "나", pace: "말하기 속도", take: "이번 시도", wordsOnly: "단어만", match: "일치도", heard: "들린 내용",
    hearT: "원본 듣기", hearMe: "내 녹음 듣기", both: "겹쳐 듣기",
    bothNote: "원본 위에 내 녹음을 겹쳐서, 둘 다 첫 단어에서 시작해요. 어디서부터 밀리는지 들어보세요.",
    loop: (a, b) => `구간 ${a}–${b} 반복`,
  },
  en: {
    title: "Shadow", close: "Close", target: "Target line", tap: "Tap words to pick a phrase", picked: "Practicing the selected phrase",
    t: "Target", y: "You", pace: "Pace", take: "Your take", wordsOnly: "words only", match: "Your match", heard: "What I heard",
    hearT: "Hear target", hearMe: "Hear my attempt", both: "Both at once",
    bothNote: "Your take over the line, both starting on their first word. Hear where you drift.",
    loop: (a, b) => `loop ${a}–${b}`,
  },
};

class NwShadow extends NwScreen {
  static poses = ["selection", "result", "loop"];
  constructor() {
    super(`
      .s{letter-spacing:0}
      :host{--ac:#0A5CF5;--sec:#8A8A8E;--ter:#C5C5C7;--or:#FF8D28;--gr:#34C759;--rd:#FF3B30}
      .ic{width:1em;height:1em;display:block;flex:0 0 auto}
      .navt{position:absolute;left:0;right:0;top:71px;height:22px;text-align:center;font-family:var(--pixel);font-size:17px;line-height:22px;z-index:6}
      .gl{position:absolute;top:62px;height:44px;border-radius:22px;background:#fff;box-shadow:0 8px 30px rgba(0,0,0,.075);display:flex;align-items:center;justify-content:center;color:var(--ac);font-size:17px;z-index:6}
      .close{left:16px;padding:0 16px}
      .bm{right:17px;width:44px;font-size:27px}
      .edge{position:absolute;left:0;right:0;top:0;height:118px;background:linear-gradient(#fff 80%,rgba(255,255,255,0));z-index:5;pointer-events:none}
      .page{position:absolute;left:20px;right:20px;top:130px;display:flex;flex-direction:column;gap:20px}
      .hd{display:flex;align-items:center;justify-content:space-between;height:16px;font-size:12px;line-height:16px;color:var(--sec)}
      .hd .r{display:flex;align-items:center;gap:6px;font-size:11px;color:var(--ter)}
      .hd .rs{display:flex;align-items:center;gap:5px;font-size:12px;font-weight:600;color:var(--gr)}
      .hd .rs .ic{font-size:13px}
      .tgt{display:flex;flex-direction:column;gap:8px}
      .words{display:flex;flex-wrap:wrap;gap:4px 1px}
      .wd{display:flex;flex-direction:column;align-items:stretch}
      .wd b{display:block;padding:1px 2px;border-radius:4px;font-size:22px;line-height:26.3px;font-weight:600;-webkit-font-smoothing:antialiased;color:rgba(60,60,67,.6)}
      .wd.sel b{background:rgba(10,92,245,.22)}
      .wd.done b{color:#000}.wd.now b{color:var(--ac)}.wd.sub b{color:var(--or)}.wd.del b{color:rgba(60,60,67,.6)}
      .bt{position:relative;height:6px}
      .bt i,.bt u{position:absolute;top:.5px;opacity:0;transition:opacity .35s}
      .bt i{left:50%;width:5px;height:5px;margin-left:-2.5px;border-radius:50%}
      .bt u{top:3px;height:1px}
      .graded .bt i,.graded .bt u{opacity:1}
      .dur{display:none;gap:12px}
      .dur div{flex:1;padding:10px 14px;border-radius:10px;background:#F2F2F7;display:flex;flex-direction:column;gap:4px}
      .dur span{font-size:12px;line-height:16px;color:var(--sec)}
      .dur strong{font-size:17px;line-height:22px;font-weight:600;font-variant-numeric:tabular-nums}
      .dur strong.g{color:var(--gr)}
      .fb{display:none;flex-direction:column;gap:16px}
      .graded .dur{display:flex}.graded .fb{display:flex}
      .fb .fh{display:flex;justify-content:space-between;align-items:center;font-size:12px;line-height:16px;color:var(--sec)}
      .fb .fh b{display:flex;align-items:center;gap:5px;font-size:13px;font-weight:600;color:var(--gr)}
      .fb .fh b .ic{font-size:14px}
      .fb .fh .sc{display:flex;align-items:center;gap:6px}
      .fb .fh .wo{font-size:11px;color:var(--ter)}
      .diff p.m .xs{color:var(--or)}.diff p.m .xd{color:var(--sec);text-decoration:line-through}
      .pb>.btn{flex:none}
      .btn{transition:background .12s}.btn.press{background:rgba(10,92,245,.26)}
      .diff{display:flex;gap:12px;align-items:flex-start}
      .diff>.ic{width:20px;font-size:17px;color:var(--ac);margin-top:-1px}
      .diff div{flex:1;display:flex;flex-direction:column;gap:6px}
      .diff small{font-size:12px;line-height:16px;color:var(--sec)}
      .diff p{margin:0;font-size:17px;line-height:22px;letter-spacing:-.25px}
      .diff p.h{font-size:16px;line-height:21px;color:var(--sec);letter-spacing:-.2px}
      .diff small.h{padding-top:4px}
      .pb{display:flex;flex-direction:column;gap:8px}
      .pb .row{display:flex;gap:10px}
      .btn{flex:1;height:34px;border-radius:17px;background:rgba(10,92,245,.13);color:var(--ac);display:flex;align-items:center;justify-content:center;gap:6px;font-size:16px;white-space:nowrap}
      .btn .ic{font-size:17px}
      .pb small{font-size:11px;line-height:13px;color:var(--ter)}
      /* bottom bar */
      .bar{position:absolute;left:8px;right:8px;bottom:34px;z-index:4}
      .bar::before{content:"";position:absolute;left:-8px;right:-8px;bottom:100%;height:72px;background:linear-gradient(rgba(255,255,255,0),#fff 78%);pointer-events:none}
      .bar::after{content:"";position:absolute;left:-8px;right:-8px;top:0;bottom:-34px;background:#fff;z-index:-1}
      .card{position:relative;border-radius:28px;background:rgba(244,244,246,.86);-webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);box-shadow:inset 0 0 0 .5px rgba(60,60,67,.12);padding:20px 18px;display:flex;flex-direction:column;gap:16px}
      .nocard .card{display:none}
      .trk{position:relative;height:54px;margin:0 4px}
      .trk .bg{position:absolute;inset:0;border-radius:8px;background:rgba(118,118,128,.12)}
      .trk .mk{position:absolute;top:19px;width:1.5px;height:16px;background:rgba(60,60,67,.18)}
      .trk .sf{position:absolute;top:0;bottom:0;border-radius:8px;background:rgba(10,92,245,.18)}
      .trk .hn{position:absolute;top:0;width:14px;height:54px;margin-left:-7px;border-radius:5px;background:var(--ac)}
      .trk .hn::after{content:"";position:absolute;left:6px;top:19px;width:2px;height:16px;border-radius:1px;background:rgba(255,255,255,.9)}
      .trk .ph{position:absolute;top:-4px;width:2.5px;height:62px;border-radius:2px;background:#000;box-shadow:0 0 1px #fff}
      .lb{display:flex;justify-content:space-between;font-size:12px;line-height:16px;color:var(--sec);font-variant-numeric:tabular-nums}
      .lb .lp{color:var(--ac)}
      .ct{position:relative;display:flex;align-items:center;gap:20px;height:44px}
      .ct .g{width:44px;height:44px;font-size:44px;color:var(--ac)}
      .ct .lpb{color:var(--sec)}.ct .lpb.on{color:var(--ac)}
      .ct .sp{margin-left:auto;height:38px;padding:0 12px;border-radius:19px;background:rgba(118,118,128,.12);display:flex;align-items:center;font-size:15px;font-weight:600;font-variant-numeric:tabular-nums}
      .ct .sp.on{color:var(--ac)}
      .ct .ut{color:var(--sec)}
      .mic{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);border-radius:50%;background:var(--ac);color:#fff;display:grid;place-items:center;transition:background .25s,transform .25s,opacity .25s}
      .mic.m60{width:60px;height:60px;font-size:27px}
      .mic.m64{width:64px;height:64px;font-size:29px}
      .mic.rec{background:var(--rd)}
      .mic.rec.m64{animation:breathe 1.8s ease-in-out infinite}
      @keyframes breathe{50%{transform:translate(-50%,-50%) scale(1.06)}}
      .mic.dim{opacity:.4}
      .solo{position:absolute;left:0;right:0;bottom:34px;height:84px;display:none;z-index:4}
      .solo .mic{top:auto;bottom:1.92px;transform:translateX(-50%)}
      @keyframes breathe2{50%{transform:translateX(-50%) scale(1.06)}}
      .solo .mic.rec{animation:breathe2 1.8s ease-in-out infinite}
      .nocard .solo{display:block}
      .cd{position:absolute;inset:0;background:rgba(0,0,0,.5);display:grid;place-items:center;z-index:20;opacity:0;transition:opacity .2s;pointer-events:none}
      .cd.on{opacity:1}
      .cd span{font:800 120px/1 ui-rounded,"SF Pro Rounded",-apple-system,sans-serif;color:#fff}
    `, `
      <div class="edge"></div>
      <div class="gl close"></div><div class="navt"></div><div class="gl bm">${I.bookmark}</div>
      <div class="page">
        <div class="tgt"><div class="hd"><span class="tl"></span><span class="r"></span></div><div class="words"></div></div>
        <div class="dur"><div><span class="a"></span><strong class="dt"></strong></div><div><span class="b"></span><strong class="dy"></strong></div><div><span class="c"></span><strong class="dp"></strong></div></div>
        <div class="fb">
          <div class="fh"><span class="tk"></span><span class="sc"><span class="wo"></span><b>${I.gauge}<span class="sv"></span></b></span></div>
          <div class="diff">${I.alignleft}<div><small class="mt"></small><p class="m"></p><small class="h hd2"></small><p class="h"></p></div></div>
          <div class="pb"><div class="row"><span class="btn">${I.playCircle}<span class="h1"></span></span><span class="btn">${I.personWave}<span class="h2"></span></span></div>
            <span class="btn bo">${I.persons}<span class="h3"></span></span><small class="h4"></small></div>
        </div>
      </div>
      <div class="bar"><div class="card">
        <div class="trk"><div class="bg"></div><span class="mks"></span><div class="sf"></div><div class="hn h0"></div><div class="hn h1"></div><div class="ph"></div></div>
        <div class="lb"><span class="cur">0:00.0</span><span class="lp"></span><span class="tot"></span></div>
        <div class="ct"><span class="g pl">${I.play}</span><span class="g lpb">${I.repeat}</span><span class="sp">1×</span><span class="g ut">${I.uturn}</span><span class="mic m60">${I.mic}</span></div>
      </div></div>
      <div class="solo"><span class="mic m64">${I.mic}</span></div>
      <div class="cd"><span></span></div>`);
  }
  get L() { return this.t === STR.ko ? L.ko : L.en; }

  /* ── the line and the take (see the header for the shapes) ── */
  get line() { return this._line; }
  set line(v) {
    const o = typeof v === "string" ? { text: v } : { ...v };
    o.estimated = !o.times || o.times.length !== o.text.split(" ").length;
    if (o.estimated) o.times = estimate(o.text);
    o.phrase ??= [0, Math.min(2, o.times.length - 1)];
    this._line = o;
    if (!this._takeSet) this._take = { heard: o.text.toLowerCase().replace(/[.,!?;:]/g, ""), score: 96, rhythm: null };
    if (this._built) { this._layout(); this.reset(); }
  }
  get take() { return this._take; }
  set take(v) { this._takeSet = true; this._take = { ...v }; if (this._built) this._fill(); }
  get _end() { return this._line.times.at(-1)[1] + .14; }   // the track ends where the speech does, + tail release
  _fromAttrs() {
    const a = k => this.getAttribute(k);
    if (a("line")) this.line = { text: a("line"), times: json(a("times")) };
    if (a("heard") != null || a("score")) {
      const r = a("rhythm");
      this.take = { ...this._take, heard: a("heard") ?? this._take.heard, score: a("score") != null ? +a("score") : this._take.score,
        rhythm: r == null ? this._take.rhythm : r === "none" ? null : +r, dev: json(a("dev")) ?? (a("line") ? undefined : this._take.dev) };
    }
  }
  /* what depends on the line: the track's word marks and its length */
  _layout() {
    const E = this._end;
    this.$(".trk .mks").innerHTML = this._line.times.map(t => `<i class="mk" style="left:${(t[0] / E * 100).toFixed(2)}%"></i>`).join("");
    this.$(".lb .tot").textContent = tl(E);
  }
  /* what depends on the take: the score, "words only", the cells, the diff and what was heard */
  _fill() {
    const k = this._take, ln = this._line, l = this.L;
    const b = this.$(".fh b"); this.$(".fh .sv").textContent = k.score; b.style.color = scoreColor(k.score);
    this.$(".fh .wo").textContent = k.rhythm == null ? l.wordsOnly : "";
    const tgt = k.target ?? (ln.times.at(-1)[1] - ln.times[0][0]);
    const pace = k.pace ?? (k.you != null ? k.you / tgt : 1);
    const you = k.you ?? tgt * pace;
    this.$(".dt").textContent = `${tgt.toFixed(1)}s`; this.$(".dy").textContent = `${you.toFixed(1)}s`;
    const dp = this.$(".dp"); dp.textContent = `${pace.toFixed(2)}x`; dp.style.color = paceColor(pace);
    this._steps = align(ln.text, k.heard ?? "");
    this.$(".diff p.m").innerHTML = this._steps.map(x => x.op === "match" ? esc(x.t) : x.op === "sub" ? `<span class="xs">${esc(x.t)}</span>`
      : x.op === "del" ? `<span class="xd">${esc(x.t)}</span>` : `<span class="xs">(+${esc(x.h)})</span>`).join(" ");
    const hp = this.$(".diff p.h"), hs = this.$(".diff .hd2"), has = !!(k.heard ?? "").trim();
    hp.textContent = k.heard ?? ""; hp.style.display = hs.style.display = has ? "" : "none";
    if (this._ws?.length === ln.times.length && this.$(".page").classList.contains("graded")) { this._words(ln.text); this._graded(true); this._hdRight("score"); }
  }

  build() {
    const l = this.L;
    this.$(".close").textContent = l.close;
    this.$(".navt").textContent = l.title;
    this.$(".tgt .tl").textContent = l.target;
    this.$(".dur .a").textContent = l.t; this.$(".dur .b").textContent = l.y; this.$(".dur .c").textContent = l.pace;
    this.$(".fb .tk").textContent = l.take; this.$(".diff .mt").textContent = l.match; this.$(".diff .hd2").textContent = l.heard;
    this.$(".h1").textContent = l.hearT; this.$(".h2").textContent = l.hearMe; this.$(".h3").textContent = l.both; this.$(".h4").textContent = l.bothNote;
    if (!this._line) { this._line = { ...LINE, estimated: false }; this._take = { ...TAKE }; }
    this._fromAttrs();
    this._layout(); this._fill();
    this.reset();
  }

  /* ── state helpers ── */
  _words(text) {
    const dev = text === this._line.text && !this._line.estimated ? this._take.dev : null;
    // a redraw of the same line (a new take) keeps the loop range: ShadowDrillView's selectedWordRange survives an attempt
    const keep = this._wsText === text ? (this._ws ?? []).map(w => w.classList.contains("sel")) : null;
    this._wsText = text;
    this.$(".words").innerHTML = text.split(" ").map((w, i) => {
      const d = dev?.[i] ?? null;
      let dot = "";
      if (d != null) {
        const off = Math.max(-24, Math.min(24, d * .06)), g = Math.abs(d) <= 120 ? 2 : Math.abs(d) <= 300 ? 1 : 0;
        const c = g === 2 ? "rgba(52,199,89,.55)" : g === 1 ? "rgba(255,141,40,1)" : "var(--rd)", tc = g === 1 ? "rgba(255,141,40,.5)" : "rgba(255,59,48,.5)";
        dot = (g === 2 ? "" : `<u style="left:calc(50% + ${Math.min(0, off)}px);width:${Math.abs(off)}px;background:${tc}"></u>`) +
          `<i style="background:${c};transform:translateX(${off}px)"></i>`;
      }
      return `<span class="wd"><b>${esc(w)}</b><span class="bt">${dot}</span></span>`;
    }).join("");
    this._ws = this.$$(".wd");
    if (keep) this._ws.forEach((w, i) => w.classList.toggle("sel", !!keep[i]));
  }
  /* the target header's right side: the rhythm score (and N/M when it stands on fewer than all words) */
  _hdRight(kind) {
    const r = this.$(".tgt .r"), l = this.L, k = this._take;
    if (kind === "score") {
      const dev = this._line.estimated ? null : k.dev, judged = dev ? dev.filter(d => d != null).length : 0, total = this._line.times.length;
      r.innerHTML = k.rhythm == null ? "" : `${judged < total ? `<span>${judged}/${total}</span>` : ""}<span class="rs" style="color:${scoreColor(k.rhythm)}">${I.metronome}${k.rhythm}</span>`;
    } else r.textContent = kind === "picked" ? l.picked : l.tap;
  }
  _select(a, b) {
    const T = this._line.times, E = this._end;
    this._ws.forEach((w, i) => w.classList.toggle("sel", a != null && i >= a && i <= b));
    if (a == null || this._ws.length !== T.length) return;
    const s = T[a][0], e = b === T.length - 1 ? E : T[b][1];
    const x0 = s / E * 100, x1 = e / E * 100;
    Object.assign(this.$(".trk .sf").style, { left: `${x0}%`, width: `${x1 - x0}%` });
    this.$(".trk .h0").style.left = `${x0}%`; this.$(".trk .h1").style.left = `${x1}%`;
    this.$(".lp").textContent = this.L.loop(tl(s), tl(e));
  }
  _ph(t, ms = 0) {
    const p = this.$(".trk .ph"), E = this._end;
    p.style.transition = ms ? `left ${ms}ms linear` : "none";
    p.style.left = `calc(${(t / E * 100).toFixed(3)}% - ${t >= E - .01 ? 2.5 : 0}px)`;
    if (!ms) this.$(".lb .cur").textContent = tl(t);
  }
  _mic(glyph, cls = "") {
    this.$$(".mic").forEach(m => { m.innerHTML = I[glyph]; m.classList.remove("rec", "dim"); if (cls) m.classList.add(cls); });
  }
  _timeline(on) { this.$(".s").classList.toggle("nocard", !on); }
  _color(i, c) { const w = this._ws[i]; if (!w) return; w.classList.remove("done", "now", "sub", "del"); if (c) w.classList.add(c); }
  /* after a take the target wears the diff: said differently = orange, skipped = secondary */
  _diffColors() {
    const op = []; for (const x of this._steps ?? []) if (x.ti != null) op[x.ti] = x.op;
    this._ws.forEach((w, i) => this._color(i, op[i] === "sub" ? "sub" : op[i] === "del" ? "del" : "done"));
  }
  _graded(on) {
    this.$(".page").classList.toggle("graded", on);
    this.$(".words").parentElement.classList.toggle("graded", on);
    if (on) this._diffColors();
  }

  reset() {
    const T = this._line.times;
    this._words(this._line.text);
    this._graded(false); this._hdRight("tap");
    this._timeline(true); this._select(0, T.length - 1); this._ph(0);   // the trimmer opens on the whole line (ShadowTimelinePlayer.onAppear sets selectedWordRange = 0…n), so every word wears the loop tile
    this._mic("mic");
    this.$(".pl").innerHTML = I.play;
    this.$(".lpb").innerHTML = I.repeat; this.$(".lpb").classList.remove("on");
    this.$(".sp").textContent = "1×"; this.$(".sp").classList.remove("on");
    this.$(".ut").style.color = "var(--ter)";
    this.$(".cd").classList.remove("on");
    this.$(".bo").classList.remove("press");
    this._sy = 0; this.$(".page").style.transform = "";
  }
  _result() {
    this._graded(true); this._hdRight("score");
    this._timeline(true); this._mic("redo"); this._ph(0);
  }
  _loopSetup(loopOn, phrase = this._line.phrase) {
    const [a, b] = phrase;
    this._select(a, b);
    this.$(".ut").style.color = "var(--sec)";     // there is a region to step back from now
    if (loopOn) { this.$(".lpb").innerHTML = I.repeatOn; this.$(".lpb").classList.add("on"); }
  }

  async pose(name) {
    this.stop(); this.reset();
    const n = this._line.times.length;
    if (name === "selection") {
      this._words(CAP.text); this._timeline(false);
      this._ws.forEach((w, i) => w.classList.toggle("sel", i >= CAP.sel[0] && i <= CAP.sel[1]));
      this._hdRight("picked");
    } else if (name === "result") {
      this._result(); this._ph(0);
    } else if (name === "loop") {
      this._result(); this._loopSetup(false); this._ph(0);
    } else if (name === "recording") {          // mid-take: card gone, the red 64pt mic alone at the bottom (the loop range, and its tiles, stay)
      this._timeline(false); this._mic("xmark", "rec");
      const h = Math.floor(n / 2); for (let i = 0; i < h; i++) this._color(i, "done"); this._color(h, "now");
    } else if (name === "both") {               // the duet playing: transport playing, karaoke on the target
      this._result();
      const k = this.$(".s").getBoundingClientRect().height / 874, over = (this.$(".h4").getBoundingClientRect().bottom - this.$(".bar").getBoundingClientRect().top) / k + 60;
      if (over > 0) { this._sy = over; this.$(".page").style.transform = `translateY(${-over}px)`; }
      const h = Math.floor(n / 2), t = this._line.times[h][0];
      this.$(".pl").innerHTML = I.pause; this._ph(t);
      this._ws.forEach((w, i) => this._color(i, i < h ? "done" : i === h ? "now" : ""));
    }
  }

  /* karaoke over [a..b] at `rate`: passed = primary, current = accent, upcoming = secondary */
  async _karaoke(a, b, rate, from) {
    const T = this._line.times, t0 = from ?? T[a][0];
    for (let i = a; i <= b; i++) this._color(i, "");
    let t = t0;
    for (let i = a; i <= b; i++) {
      const [s, e] = T[i];
      await this.sleep(Math.max(0, (s - t) * 1000 / rate)); this._color(i, "now");
      await this.sleep((e - s) * 1000 / rate); this._color(i, "done"); t = e;
    }
  }
  async _play(a, b, rate = 1, from) {
    const T = this._line.times, E = this._end;
    const s = from ?? T[a][0], e = b === T.length - 1 ? E : T[b][1];
    this.$(".pl").innerHTML = I.pause;
    this._ph(s); void this.$(".trk .ph").offsetWidth; this._ph(e, (e - s) * 1000 / rate);
    // the app colours EVERY word by the audio clock while it plays (wordColor → positionalColor), so a
    // phrase's words before it read as passed and the rest as upcoming — the diff colours step aside
    for (let i = 0; i < T.length; i++) if (i < a || i > b) this._color(i, i < a ? "done" : "");
    await this._karaoke(a, b, rate, s);
    await this.sleep(Math.max(0, (e - T[b][1]) * 1000 / rate));
    this.$(".pl").innerHTML = I.play;
  }
  async _press(el, speed = 1) { el.classList.add("press"); await this.sleep(180 / speed); el.classList.remove("press"); }

  /** Scroll the result (points, positive = down), as a finger would. */
  async scrollTo(y, { ms = 600, speed = 1 } = {}) {
    const pg = this.$(".page"); this._sy = y;
    pg.style.transition = `transform ${ms / speed}ms cubic-bezier(.3,.8,.2,1)`; pg.style.transform = y ? `translateY(${-y}px)` : "";
    await this.sleep(ms / speed); pg.style.transition = "";
  }
  /* scroll just enough that `el` clears the bottom bar */
  async _reveal(el, speed = 1) {
    const k = this.$(".s").getBoundingClientRect().height / 874;
    const over = (el.getBoundingClientRect().bottom - this.$(".bar").getBoundingClientRect().top) / k + 60;
    if (over > 0) await this.scrollTo((this._sy || 0) + over, { speed });
  }

  /* ── the scriptable API ── */
  /** The target plays at `rate` (the speed pill), karaoke + playhead. After a take the diff colours come back. */
  async playTarget(rate = 1, { speed = 1 } = {}) {
    const n = this._line.times.length - 1, graded = this.$(".page").classList.contains("graded");
    if (rate !== 1) { this.$(".sp").textContent = `${rate}×`; this.$(".sp").classList.add("on"); }
    await this._play(0, n, rate * speed);
    this._ph(0);
    if (graded) this._diffColors(); else this._ws.forEach((w, i) => this._color(i, ""));
  }
  /** 3·2·1 → the take (the card gives way to the red 64pt mic, as the app draws it, at the bottom;
   *  karaoke on the learner's clock) → "…" → the result for `take`. */
  async record(take, { speed = 1 } = {}) {
    if (take) this.take = take;
    const n = this._line.times.length - 1, k = this._take;
    this._graded(false); this._hdRight("tap"); this._ws.forEach((w, i) => this._color(i, ""));
    this._ph(0);
    const cd = this.$(".cd"), num = cd.querySelector("span");
    cd.classList.add("on");
    for (const c of [3, 2, 1]) { num.textContent = c; await this.sleep(650 / speed); }
    cd.classList.remove("on");
    this._timeline(false); this._mic("xmark", "rec");
    const pace = k.pace ?? (k.you != null ? k.you / (k.target ?? (this._line.times.at(-1)[1] - this._line.times[0][0])) : 1);
    await this._karaoke(0, n, speed / pace, 0);
    await this.sleep(600 / speed);
    this._mic("ellipsis", "dim"); await this.sleep(900 / speed);
    this._result();
  }
  /** The result for `take` (or the current one), no animation. */
  showResult(take) { if (take) this.take = take; this._result(); }
  /** "Both at once": the button presses, then the two takes play from their first words. On screen that
   *  is the app's playing state: the transport shows pause, the playhead runs, the target karaokes. The
   *  app's button itself does not stay lit (ShadowDrillView.playbackRow). Speeds are not matched. */
  async both({ speed = 1 } = {}) {
    await this._reveal(this.$(".h4"), speed);   // the learner scrolls the button + its note above the bar first
    await this._press(this.$(".bo"), speed);
    const T = this._line.times, n = T.length - 1;
    await this._play(0, n, speed, T[0][0]);
    this._ph(0); this._diffColors();
  }
  /** Tap words a and b, loop the phrase, set the speed pill, play it `times` times. */
  async loop(a, b, { rate = .5, times = 2, speed = 1 } = {}) {
    this._ws[a].classList.add("sel"); this._ws.forEach((w, i) => i !== a && w.classList.remove("sel"));
    await this.sleep(500 / speed);
    this._loopSetup(false, [a, b]); await this.sleep(600 / speed);
    this._loopSetup(true, [a, b]); await this.sleep(500 / speed);
    this.$(".sp").textContent = `${rate}×`; this.$(".sp").classList.toggle("on", rate !== 1); await this.sleep(500 / speed);
    for (let k = 0; k < times; k++) { await this._play(a, b, rate * speed); this.$(".pl").innerHTML = I.pause; }
    this.$(".pl").innerHTML = I.play;
    if (this.$(".page").classList.contains("graded")) this._diffColors(); else this._ws.forEach((w, i) => this._color(i, ""));
  }

  async demo() {
    await this.sleep(900);
    // 1 — the target plays: the playhead runs, the words light up as they are said
    this.beat(1);
    await this.playTarget(1);
    await this.sleep(700);
    // 2 — the mic: 3·2·1, the take (karaoke on the learner's own clock), then the grade
    this.beat(2);
    await this.record(null);
    await this.sleep(2600);
    // 3 — pick a phrase, loop it, slow it to half speed
    this.beat(3);
    const [a, b] = this._line.phrase;
    await this.loop(a, b, { rate: .5, times: 2 });
    await this.sleep(1200);   // at rest the line wears the diff again, as the app's does
  }
}

export { NwShadow };
