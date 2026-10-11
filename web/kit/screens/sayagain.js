/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* ═══════════════════════════ <nw-sayagain> — the whole talk, said again ═══════════════════════════
 * SayItAgainView.swift: a NavigationStack sheet ("Say it again", Close on the trailing side), the
 * conversation so far as DialogueLine rows (LazyVStack spacing 14, padding 20, anchored to the
 * bottom), and the prompter in a `fadingBottomBar` (padding 20 × 14) that is, by phase: the intro's
 * Start button, "<other> is answering" + Skip, the teleprompter card, or the finished summary.
 * Laid out in iOS points from real/say-again*.png. */

/* SF Symbols, traced (24-unit boxes). */
const SVG = (body, cls = "ic") => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
const I = {
  viewfinder: SVG('<g fill="none" stroke="currentColor" stroke-width="1.85" stroke-linecap="round"><path d="M2.6 8.2V6.4a3.8 3.8 0 0 1 3.8-3.8h1.9M15.7 2.6h1.9a3.8 3.8 0 0 1 3.8 3.8v1.8M21.4 15.8v1.8a3.8 3.8 0 0 1-3.8 3.8h-1.9M8.3 21.4H6.4a3.8 3.8 0 0 1-3.8-3.8v-1.8"/><path d="M7.6 8.7h8.8M7.6 12h8.8M7.6 15.3h6.2"/></g>'),
  sparkles: SVG('<g fill="currentColor"><path d="M14.6 8.4c.55 3.9 2.3 5.65 6.2 6.2-3.9.55-5.65 2.3-6.2 6.2-.55-3.9-2.3-5.65-6.2-6.2 3.9-.55 5.65-2.3 6.2-6.2z"/><path d="M6.4 5.6c.3 2.05 1.2 2.95 3.25 3.25-2.05.3-2.95 1.2-3.25 3.25-.3-2.05-1.2-2.95-3.25-3.25 2.05-.3 2.95-1.2 3.25-3.25z"/><path d="M12.1 1.6c.16 1.05.62 1.5 1.67 1.67-1.05.16-1.5.62-1.67 1.67-.16-1.05-.62-1.5-1.67-1.67 1.05-.16 1.5-.62 1.67-1.67z"/></g>'),
  waveform: SVG('<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M3 10.5v3M6.2 8v8M9.4 4.5v15M12.6 7v10M15.8 9v6M19 6v12M22 10.5v3"/></g>'),
  check: SVG('<circle cx="12" cy="12" r="10" fill="currentColor"/><path d="M7.4 12.3l3.1 3.1 6.1-6.6" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'),
  retry: SVG('<g fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4.3a8 8 0 1 1-7 4.1"/><path d="M12.9 1.6L10.1 4.3l2.8 2.7"/></g>'),
  dot: SVG('<circle cx="12" cy="12" r="12" fill="currentColor"/>'),
};
/* checkmark.seal.fill — a 12-lobed rosette with the check knocked out. */
const SEAL = (() => {
  const pts = [];
  for (let i = 0; i < 24; i++) {
    const a = (i / 24) * Math.PI * 2 - Math.PI / 2, r = i % 2 ? 9.3 : 11.2;
    pts.push([12 + r * Math.cos(a), 12 + r * Math.sin(a)]);
  }
  const mid = (p, q) => `${((p[0] + q[0]) / 2).toFixed(2)} ${((p[1] + q[1]) / 2).toFixed(2)}`;
  let d = `M${mid(pts[0], pts[1])}`;
  for (let i = 1; i <= 24; i++) { const p = pts[i % 24], q = pts[(i + 1) % 24]; d += `Q${p[0].toFixed(2)} ${p[1].toFixed(2)} ${mid(p, q)}`; }
  return SVG(`<path d="${d}Z" fill="currentColor"/><path d="M7.6 12.3l3 3 5.8-6.2" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>`);
})();

/* The demo talk (the capture's own lines). `fix` marks the words the correction changed —
 * `highlightedCorrection` paints them accent + semibold. */
const STEPS = [
  { who: "self", text: "So — how did the interview go yesterday?" },
  { who: "me", text: "Honestly, it [went] really well — I felt prepared.", note: { ko: "지난 일이라 과거형이에요", en: "It already happened, so past tense." }, score: 92 },
  { who: "self", text: "Nice! What surprised you most?" },   // asks what the next line answers — one call, start to end
  { who: "me", text: "How relaxed I stayed, even on [the] hard [questions.]", note: { ko: "질문이 여러 개라 복수예요", en: "More than one question, so plural." }, score: 61, heard: "How relaxed I stay, even on hard question." },
];
const fixHTML = s => esc(s).replace(/\[([^\]]+)\]/g, "<b>$1</b>");

const L = {
  ko: {
    title: "다시 말하기", close: "닫기", self: "미래의 나", you: "나",
    intro: "이 대화를 처음부터 다시 해요. 내 차례엔 교정된 말로 말해 보세요. 대답은 그때 그대로 나와요.",
    count: (n, c) => `${n}문장 · ${c}개 교정됨`, start: "시작",
    fixed: "고친 대로 말해 보세요", skip: "건너뛰기", moves: "말을 마치면 다음으로 넘어가요",
    answering: n => `${n} 대답 중`, retry: "다시 시도", heard: "들린 말",
    sum: (r, n, a) => `${n}문장 중 ${r}문장 읽음 · 평균 ${a}점`, again: "처음부터 다시", done: "완료",
  },
  en: {
    title: "Say it again", close: "Close", self: "Future self", you: "You",
    intro: "Do this talk again from the start, and say your part the corrected way. The answers play just as they did.",
    count: (n, c) => `${n} lines · ${c} corrected`, start: "Start",
    fixed: "Say it the fixed way", skip: "Skip", moves: "Moves on when you finish",
    answering: n => `${n} is answering`, retry: "Retry", heard: "Heard",
    sum: (r, n, a) => `${r} of ${n} lines read · ${a} average`, again: "Run again", done: "Done",
  },
};

class NwSayAgain extends NwScreen {
  static poses = ["intro", "reading", "done"];
  constructor() {
    super(`
       .s{letter-spacing:0}
      :host{--ac:#0A5CF5;--acw:#D3E2FD;--ink:#052E7A;--sec:#8A8A8E;--or:#FF8D28}
      .ic{width:1em;height:1em;display:block;flex:0 0 auto}
      .navt{position:absolute;left:0;right:0;top:71px;height:22px;text-align:center;font-family:var(--pixel);font-size:17px;line-height:22px;font-weight:400;letter-spacing:0;z-index:6}
      .close{position:absolute;right:17px;top:62px;height:44px;padding:0 16px;border-radius:22px;background:#fff;
        box-shadow:0 8px 30px rgba(0,0,0,.075);display:flex;align-items:center;font-size:17px;color:var(--ac);z-index:6}
      .edge{position:absolute;left:0;right:0;top:0;height:118px;background:linear-gradient(#fff 72%,rgba(255,255,255,0));z-index:5;pointer-events:none}
      /* the conversation — bottom-anchored like .defaultScrollAnchor(.bottom) */
      .feed{position:absolute;left:20px;right:20px;bottom:240px;display:flex;flex-direction:column;gap:14px;transition:bottom .3s ease}
      .ln{display:flex;flex-direction:column;align-items:flex-start;gap:4px;opacity:0;transition:opacity .35s}
      .ln.in{opacity:1}
      .ln.me{align-items:flex-end}
      .ln .who{font-size:12px;line-height:16px;color:var(--sec);letter-spacing:0}
      .bub{max-width:322px;padding:10px 14px;border-radius:14px;background:#F2F2F7;font-size:17px;line-height:21px;letter-spacing:-.12px;box-shadow:inset 0 0 0 2px transparent;transition:box-shadow .2s}
      .ln.me .bub{background:var(--acw)}
      .ln.cur .bub{box-shadow:inset 0 0 0 2px var(--ac)}
      .bub b{color:var(--ac);font-weight:600}
      .acc{display:flex;align-items:center;gap:8px;height:26px}
      .score{display:flex;align-items:center;gap:8px;font-size:12px;font-weight:600;font-variant-numeric:tabular-nums;letter-spacing:0}
      .score .ic{font-size:14.5px}
      .score.g{color:#34C759}.score.a{color:var(--ac)}.score.o{color:var(--or)}
      .spin{width:12px;height:12px;border-radius:50%;border:1.6px solid #C7C7CC;border-top-color:transparent;animation:spin .8s linear infinite}
      @keyframes spin{to{transform:rotate(360deg)}}
      .rt{display:flex;align-items:center;gap:6px;height:26px;padding:0 10px;border-radius:13px;background:var(--acw);color:var(--ac);font-size:12px;font-weight:600;letter-spacing:0}
      .rt .ic{font-size:14px}
      .heard{align-self:stretch;text-align:right;font-size:12px;line-height:16px;color:var(--sec);letter-spacing:0;opacity:0;transition:opacity .35s}
      .heard.in{opacity:1}
      /* intro cover, also bottom-anchored */
      .hero{position:absolute;left:28px;right:28px;bottom:112px;display:flex;flex-direction:column;align-items:center;gap:14px;text-align:center}
      .hero.off{display:none}
      .hero .vf{font-size:49px;margin:-4px 0;color:var(--ac)}
      .hero h3{margin:0;font-size:20px;line-height:25px;font-weight:600;}
      .hero p{margin:0;font-size:15px;line-height:20px;color:var(--sec);}
      .hero .cnt{display:flex;align-items:center;gap:6px;font-size:13px;line-height:18px;font-weight:500;color:var(--sec);}
      .hero .cnt .ic{font-size:18px}
      /* the bottom bar */
      .bar{position:absolute;left:0;right:0;bottom:34px;padding:14px 20px;z-index:4}
      .pn{display:none}
      .pn.on{display:block;animation:pin .3s ease}
      @keyframes pin{from{opacity:0;transform:translateY(10px)}}
      .big{height:50px;border-radius:25px;display:flex;align-items:center;justify-content:center;gap:8px;font-size:17px;}
      .big.p{background:var(--ac);color:#fff}
      .big.b{background:var(--acw);color:var(--ac)}
      .big .ic{font-size:19px}
      .lis{display:flex;align-items:center;gap:12px;height:32px}
      .lis .wv{font-size:20px;color:var(--ac)}
      .lis .wv .ic{animation:vc 1.2s ease-in-out infinite}
      @keyframes vc{50%{opacity:.45}}
      .lis .who{flex:1;font-size:15px;color:var(--sec);}
      .lis i{font-style:normal;height:28px;padding:0 12px;border-radius:14px;background:var(--acw);color:var(--ac);font-size:15px;display:flex;align-items:center;}
      .card{border-radius:22px;background:#DDE8FE;box-shadow:inset 0 0 0 1px #A2C1FB;padding:18px 20px;display:flex;flex-direction:column;align-items:center;gap:14px;text-align:center}
      .card .hd{align-self:stretch;display:flex;align-items:center;gap:6px;font-size:12px;line-height:14px;font-weight:600;color:rgba(5,46,122,.7);letter-spacing:0}
      .card .hd .ic{font-size:8px;color:#FF3B30;animation:pulse 1.4s ease-in-out infinite}
      @keyframes pulse{50%{opacity:.35}}
      .card .hd .sp{flex:1}
      .card .hd .fx{flex:0 1 auto}
      .card .line{margin:-2px 0;text-wrap:balance;font-size:22px;line-height:31px;font-weight:600;color:var(--ink);}
      .card .line b{color:var(--ac);font-weight:600}
      .card .note{margin:0;font-size:13px;line-height:16px;color:rgba(5,46,122,.7);}
      .card .ft{display:flex;align-items:center;gap:6px;font-size:12px;line-height:14px;color:rgba(5,46,122,.5);letter-spacing:0}
      .card .ft .ic{font-size:13px}
      .fin{display:flex;flex-direction:column;gap:10px}
      .fin .sum{display:flex;align-items:center;justify-content:center;gap:7px;font-size:15px;line-height:20px;font-weight:600;color:#34C759;}
      .fin .sum .ic{font-size:18px}
      .fin .bt{display:flex;gap:10px}
      .fin .bt .big{flex:1}
    `, `
      <div class="edge"></div>
      <div class="navt"></div><div class="close"></div>
      <div class="hero"><span class="vf">${I.viewfinder}</span><h3>Job interview</h3><p class="ip"></p><span class="cnt">${I.sparkles}<span></span></span></div>
      <div class="feed"></div>
      <div class="bar">
        <div class="pn p-intro"><div class="big p">${I.viewfinder}<span class="st"></span></div></div>
        <div class="pn p-lis"><div class="lis"><span class="wv">${I.waveform}</span><span class="who"></span><i class="sk"></i></div></div>
        <div class="pn p-read"><div class="card">
          <div class="hd">${I.dot}<span class="fx"></span><span class="sp"></span><span class="sk"></span></div>
          <p class="line"></p><p class="note"></p>
          <div class="ft">${I.waveform}<span class="mv"></span></div></div></div>
        <div class="pn p-fin"><div class="fin"><div class="sum">${SEAL}<span></span></div>
          <div class="bt"><div class="big b">${I.retry}<span class="ag"></span></div><div class="big p"><span class="dn"></span></div></div></div></div>
      </div>`);
  }
  get L() { return this.t === STR.ko ? L.ko : L.en; }
  build() {
    const l = this.L;
    this.$(".navt").textContent = l.title;
    this.$(".close").textContent = l.close;
    this.$(".hero .ip").textContent = l.intro;
    this.$(".hero .cnt span").textContent = l.count(2, 2);
    this.$(".p-intro .st").textContent = l.start;
    this.$(".p-lis .who").textContent = l.answering(l.self);
    this.$$(".sk").forEach(e => e.textContent = l.skip);
    this.$(".p-read .fx").textContent = l.fixed;
    this.$(".p-read .mv").textContent = l.moves;
    this.$(".p-fin .ag").textContent = l.again;
    this.$(".p-fin .dn").textContent = l.done;
    this.reset();
  }
  reset() {
    this.$(".feed").innerHTML = "";
    this.$(".hero").classList.remove("off");
    this._panel("intro");
  }
  /* which bottom-bar panel shows; the conversation (or the cover) sits 20pt above it */
  _panel(name) {
    this.$$(".pn").forEach(p => p.classList.toggle("on", p.classList.contains("p-" + name)));
    this._layout();
  }
  _layout() {
    const top = this.$(".bar").offsetTop;
    this.$(".feed").style.bottom = `${874 - top + 20}px`;
    this.$(".hero").style.bottom = `${874 - top}px`;
  }
  /* A SwiftUI Text hugs its widest wrapped line; a CSS box with max-width doesn't. */
  _hug(b) {
    b.style.width = "";
    const k = this.$(".s").getBoundingClientRect().width / 402 || 1, r = document.createRange();
    r.selectNodeContents(b);
    let lo = Infinity, hi = -Infinity;
    for (const q of r.getClientRects()) { if (q.width < 1) continue; lo = Math.min(lo, q.left); hi = Math.max(hi, q.right); }
    if (hi > lo) b.style.width = `${Math.ceil((hi - lo) / k) + 28 + 1}px`;
  }
  _row(step, { cur = false, take } = {}) {
    const l = this.L, me = step.who === "me";
    const d = document.createElement("div");
    d.className = `ln ${me ? "me" : ""} ${cur ? "cur" : ""}`;
    d.innerHTML = `<span class="who">${me ? l.you : l.self}</span><div class="bub">${me ? fixHTML(step.text) : esc(step.text)}</div>${me ? `<div class="acc"><span class="spin"></span></div>` : ""}`;
    this.$(".feed").append(d);
    this._hug(d.querySelector(".bub"));
    void d.offsetWidth; d.classList.add("in");
    if (take && me) this._score(d, step);
    return d;
  }
  _score(d, step) {
    const l = this.L, s = step.score, cls = s >= 80 ? "g" : s >= 75 ? "a" : "o";
    d.querySelector(".acc").innerHTML = `<span class="score ${cls}">${s >= 80 ? I.check : I.waveform}${s}</span><span class="rt">${I.retry}${l.retry}</span>`;
    if (s < 75 && step.heard) {
      const h = document.createElement("div"); h.className = "heard";
      h.textContent = `${l.heard}: ${step.heard}`;
      d.after(h); void h.offsetWidth; h.classList.add("in");
    }
  }
  _reading(step) {
    const lang = this.t === STR.ko ? "ko" : "en";
    this.$(".p-read .line").innerHTML = fixHTML(step.text);
    this.$(".p-read .note").textContent = step.note[lang];
    this._panel("read");
  }
  _finish() {
    const l = this.L, sc = STEPS.filter(s => s.who === "me").map(s => s.score);
    this.$(".p-fin .sum span").textContent = l.sum(sc.length, sc.length, Math.floor(sc.reduce((a, b) => a + b, 0) / sc.length));
    this._panel("fin");
  }
  _uncur() { this.$$(".ln.cur").forEach(e => e.classList.remove("cur")); }

  async pose(name) {
    this.stop(); this.reset();
    if (name === "intro") return;
    this.$(".hero").classList.add("off");
    if (name === "reading") { this._row(STEPS[0]); this._reading(STEPS[1]); return; }
    if (name === "done") { STEPS.forEach(s => this._row(s, { take: true })); this._finish(); }
  }

  async demo() {
    await this.sleep(1400);
    // Start: the cover gives way to the run
    this.$(".hero").classList.add("off"); await this.sleep(250);
    for (let i = 0; i < STEPS.length; i++) {
      const step = STEPS[i];
      if (step.who === "self") {
        this.beat(i === 0 ? 1 : 3);
        this._panel("lis"); this._row(step, { cur: true });
        await this.sleep(i === 0 ? 2200 : 2800);
        this._uncur();
      } else {
        this.beat(2);
        this._reading(step);
        await this.sleep(3200);
        // the take ends when they go quiet: the line joins the conversation, graded in the pause
        this._panel("lis");
        const row = this._row(step);
        await this.sleep(700);
        this._score(row, step);
        await this.sleep(500);
      }
    }
    this.beat(4); this._finish(); await this.sleep(3600);
  }
}

export { NwSayAgain };
