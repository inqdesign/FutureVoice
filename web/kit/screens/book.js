/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc } from "../core.js";

/* ═══════════════════════════ <nw-book> — Review tab, Studying page ═══════════════════════════
 * PracticeTab.studyingPage: the pixel title and the week's header icons, the shelf chips, the four
 * library tiles, then every unfinished book newest first — TalkBookCard / ScenarioBookCard with
 * BookChapterButtons (Words · Expressions · Grammar · Shadowing) under it.
 *   await book.arrive()   a just-finished talk's book lands on top; its chapter bars and the tiles count up
 * Laid out in points from real/practice-studying.png (iPhone 17, ko). */

const SF = {
  /* header */
  stack: `<svg viewBox="0 0 23 24"><g fill="none" stroke="currentColor" stroke-linecap="round"><rect x="1.3" y="8.4" width="20.4" height="14.3" rx="3.2" stroke-width="2.1"/><path d="M2.8 5.1h17.4M4.6 1.8h13.8" stroke-width="1.6"/></g></svg>`,
  calendar: `<svg viewBox="0 0 22 20"><path fill-rule="evenodd" fill="currentColor" d="M3.9 0h14.2A3.9 3.9 0 0 1 22 3.9v12.2a3.9 3.9 0 0 1-3.9 3.9H3.9A3.9 3.9 0 0 1 0 16.1V3.9A3.9 3.9 0 0 1 3.9 0zM3.7 5.3h14.6a1.6 1.6 0 0 1 1.6 1.6v9.2a1.6 1.6 0 0 1-1.6 1.6H3.7a1.6 1.6 0 0 1-1.6-1.6V6.9a1.6 1.6 0 0 1 1.6-1.6z"/><g fill="currentColor">${[[9.1,8.4],[12.5,8.4],[16,8.4],[5.6,11.6],[9.1,11.6],[12.5,11.6],[16,11.6],[5.6,14.8],[9.1,14.8],[12.5,14.8]].map(([x, y]) => `<rect x="${x - .85}" y="${y - .85}" width="1.7" height="1.7" rx=".4"/>`).join("")}</g></svg>`,
  /* chapters (StudyIcon) */
  words: `<svg viewBox="0 0 17 21"><path fill="currentColor" fill-rule="evenodd" d="M3.4 0h11.4c1 0 1.7.7 1.7 1.7v14.4c0 .8-.6 1.4-1.4 1.4H3.6c-.7 0-1.3.5-1.3 1.2s.6 1.2 1.3 1.2h12c.5 0 .9.4.9.9s-.4.8-.9.8H3.5C1.6 21.6 0 20.1 0 18.4V3.4C0 1.5 1.5 0 3.4 0zm.9 1.8c-.3 0-.5.2-.5.5v13.3c0 .3.2.5.5.5h.2c.3 0 .5-.2.5-.5V2.3c0-.3-.2-.5-.5-.5zm3.4 2.6c-.4 0-.6.3-.6.6s.2.6.6.6h5.6c.4 0 .6-.3.6-.6s-.2-.6-.6-.6zm0 3c-.4 0-.6.3-.6.6s.2.6.6.6h5.6c.4 0 .6-.3.6-.6s-.2-.6-.6-.6z"/></svg>`,
  quote: `<svg viewBox="0 0 22 21"><path fill="currentColor" fill-rule="evenodd" d="M4 0h14c2.2 0 4 1.8 4 4v8.3c0 2.2-1.8 4-4 4H9.6l-4.4 3.9c-.6.5-1.4.1-1.4-.6v-3.3C1.7 16 0 14.3 0 12.3V4c0-2.2 1.8-4 4-4zm4.3 4.6c-1.3 0-2.2.9-2.2 2.1 0 1.1.8 2 1.9 2 .2 0 .4 0 .5-.1-.3.9-1 1.6-2 2-.3.1-.4.4-.3.6.1.3.4.4.7.3 2-.7 3.4-2.4 3.4-4.4 0-1.5-.8-2.5-2-2.5zm5.7 0c-1.3 0-2.2.9-2.2 2.1 0 1.1.8 2 1.9 2 .2 0 .4 0 .5-.1-.3.9-1 1.6-2 2-.3.1-.4.4-.3.6.1.3.4.4.7.3 2-.7 3.4-2.4 3.4-4.4 0-1.5-.8-2.5-2-2.5z"/></svg>`,
  check: `<svg viewBox="0 0 22 21"><path fill="currentColor" fill-rule="evenodd" d="M4 0h14c2.2 0 4 1.8 4 4v8.3c0 2.2-1.8 4-4 4H9.6l-4.4 3.9c-.6.5-1.4.1-1.4-.6v-3.3C1.7 16 0 14.3 0 12.3V4c0-2.2 1.8-4 4-4zm11.7 3.3c-.4-.3-.9-.2-1.2.2l-4.6 6.9-2.5-2.7c-.3-.4-.9-.4-1.2 0-.4.3-.4.8-.1 1.2l3.3 3.6c.4.4 1 .3 1.3-.1l5.2-7.9c.3-.4.2-.9-.2-1.2z"/></svg>`,
  shadow: `<svg viewBox="0 0 22 22"><g fill="none" stroke="currentColor" stroke-linecap="round"><path stroke-width="1.6" d="M1 8.6v4.8M4.2 5.4v11.2M7.4 1v20M10.6 4.4v13.2M13.8 2.6v9.4"/></g><g fill="currentColor"><rect x="15.6" y="9.6" width="4" height="7.6" rx="2"/><path d="M14 14.6c0-.4.3-.7.7-.7s.7.3.7.7c0 1.4 1.1 2.5 2.4 2.5s2.4-1.1 2.4-2.5c0-.4.3-.7.7-.7s.7.3.7.7c0 1.9-1.4 3.5-3.1 3.8v1.6h1.6c.4 0 .7.3.7.7s-.3.7-.7.7h-4.7c-.4 0-.7-.3-.7-.7s.3-.7.7-.7h1.6v-1.6C15.4 18.1 14 16.5 14 14.6z"/></g></svg>`,
  /* book covers */
  bubbles: `<svg viewBox="0 0 28 23"><g fill="currentColor"><path d="M4.4 0h11.1c2.2 0 4 1.7 4.1 3.9h-6.8c-2.9 0-5.2 2.3-5.2 5.2v5.2H6.3l-2.6 2.6c-.5.5-1.3.1-1.3-.5v-2.3C.9 13.7 0 12.3 0 10.6V4.4C0 2 2 0 4.4 0z"/><path d="M12.9 5.5h10.7c2.4 0 4.4 2 4.4 4.4v6.3c0 1.7-1 3.2-2.4 3.9v2.3c0 .7-.8 1-1.3.5l-2.6-2.6h-8.8c-2.4 0-4.4-2-4.4-4.4V9.9c0-2.4 2-4.4 4.4-4.4z"/></g></svg>`,
  newspaper: `<svg viewBox="0 0 22 21"><path fill="currentColor" fill-rule="evenodd" d="M6.3 0h13.2C20.9 0 22 1.1 22 2.5v15.6c0 1.6-1.3 2.9-2.9 2.9H5.4c.6-.6.9-1.4.9-2.3zM9.8 3.5c-.4 0-.6.3-.6.6s.2.6.6.6h8.8c.4 0 .6-.3.6-.6s-.2-.6-.6-.6zm0 3.1c-.4 0-.6.3-.6.6s.2.6.6.6h8.8c.4 0 .6-.3.6-.6s-.2-.6-.6-.6zm.4 3c-.6 0-1 .4-1 1v3c0 .6.4 1 1 1h3c.6 0 1-.4 1-1v-3c0-.6-.4-1-1-1zm5.6.6c-.4 0-.6.3-.6.6s.2.6.6.6h2.8c.4 0 .6-.3.6-.6s-.2-.6-.6-.6zm0 3c-.4 0-.6.3-.6.6s.2.6.6.6h2.8c.4 0 .6-.3.6-.6s-.2-.6-.6-.6zM2.2 6.3h1.7c.3 0 .5.2.5.5v11.9c0 1-.8 1.8-1.8 1.8S.8 19.7.8 18.7V7.7c0-.8.6-1.4 1.4-1.4z"/></svg>`,
};
const sz = (svg, w, h, cls = "") => svg.replace("<svg ", `<svg width="${w}" height="${h}"${cls ? ` class="${cls}"` : ""} `);
const CH = [["words", 16.7, 21], ["quote", 21.7, 20.7], ["check", 21.3, 20.3], ["shadow", 21.7, 21.7]];

class NwBook extends NwScreen {
  static poses = ["studying", "before", "arrived"];
  constructor() {
    super(`
      :host{background:#F2F2F7;--blue:#0A5CF5;--sysblue:#0088FF;--sysorange:#FF8D28;--sec:rgba(60,60,67,.6)}
      /* the chip bar's material, feathered out at its foot (PracticeTab safeAreaInset .bar) */
      .bar{position:absolute;left:0;right:0;top:0;height:174px;z-index:4;pointer-events:none;
        background:linear-gradient(rgba(250,251,253,.98) 0,rgba(250,251,253,.98) 78%,rgba(250,251,253,.55) 88%,rgba(250,251,253,0) 100%)}
      .foot{position:absolute;left:0;right:0;bottom:0;height:126px;z-index:4;pointer-events:none;
        background:linear-gradient(rgba(250,250,250,0) 0,rgba(250,250,250,.2) 25%,rgba(250,250,250,.55) 45%,rgba(250,250,250,.8) 56%,rgba(249,249,249,.95) 63%,rgba(242,243,243,1) 66%,rgba(242,243,243,1) 100%)}
      .lt{position:absolute;left:20.3px;top:62.27px;z-index:5;font-family:"Geist Pixel","Galmuri14",monospace;font-size:34px;line-height:44px;letter-spacing:0}
      .gl{position:absolute;top:62px;height:44px;border-radius:22px;background:#FEFEFF;z-index:5;
        box-shadow:inset 0 0 0 1px rgba(255,255,255,.95),0 0 0 .5px rgba(0,0,0,.03),0 4px 16px rgba(0,0,0,.06)}
      .wk{left:214.7px;width:107.3px}
      .wk .s1{position:absolute;left:13.6px;top:9px;width:23px;height:24px;color:#000}
      .wk .s2{position:absolute;left:72px;top:11.2px;width:21.7px;height:19.7px;color:#000}
      .dot{position:absolute;width:7px;height:7px;border-radius:50%;background:var(--blue)}
      .wk .dot{left:88.3px;top:5.5px}
      .ts{left:334px;width:52px}
      .ts .tile{position:absolute;left:10px;top:6px;width:32px;height:32px;border-radius:8px;background:rgba(118,118,128,.12)}
      .ts .tile i{position:absolute;top:10.3px;width:4.4px;height:6px;border-radius:1.4px;background:#1C1C1E}
      .ts .dot{left:38px;top:4px}
      .chips{position:absolute;left:18.3px;top:124px;z-index:5;display:flex;gap:8px;white-space:nowrap}
      .chips span{height:37.7px;padding:0 16px;border-radius:19px;background:#fff;display:flex;align-items:flex-start;gap:4px;font-size:17px;font-weight:500;letter-spacing:-.4px;padding-top:8.6px;transition:background .25s,color .25s}
      .chips span sup{font-size:11px;font-weight:600;opacity:.55;line-height:13px;top:0;margin-top:-1px;letter-spacing:0;font-variant-numeric:tabular-nums}
      .chips span.on{background:#000;color:#fff}
      .pg{position:absolute;left:18px;right:18px;top:180.33px}
      .tiles{height:94.33px;border-radius:16px;background:#fff;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));padding:12px 6px;margin-bottom:20px}
      .tiles div{display:flex;flex-direction:column;align-items:center;gap:4px}
      .tiles .ic{height:24px;display:grid;place-items:center;color:#000}
      .tiles b{font-size:20px;line-height:24px;font-weight:600;font-variant-numeric:tabular-nums;letter-spacing:-.3px}
      .tiles small{font-size:12px;line-height:14.3px;color:var(--sec)}
      .slot{display:grid;grid-template-rows:1fr;transition:grid-template-rows .65s cubic-bezier(.3,.8,.2,1),opacity .5s .15s}
      .slot>div{overflow:hidden;min-height:0}
      .slot.in{grid-template-rows:0fr;opacity:0}
      .bk{background:#fff;border-radius:18px;margin-bottom:12px;position:relative}
      .bk .top{padding:14px 14px 14px;position:relative}
      .disc{width:44px;height:44px;border-radius:50%;display:grid;place-items:center}
      .kt .disc{background:rgba(0,136,255,.14);color:var(--sysblue)} .ks .disc{background:rgba(255,141,40,.14);color:var(--sysorange)}
      .score{position:absolute;right:14px;top:14px;width:30px;height:30px;border-radius:50%;box-shadow:inset 0 0 0 2px rgba(60,60,67,.12);display:grid;place-items:center;
        font-size:12px;font-weight:700;color:var(--sec);font-variant-numeric:tabular-nums;letter-spacing:.2px}
      .tx{margin-top:8px;display:flex;flex-direction:column;gap:2px}
      .tx .og{font-size:11px;line-height:13.4px;font-weight:500;color:var(--sec);letter-spacing:-.1px}
      .tx b{font-size:15px;line-height:20px;margin:-1px 0;font-weight:600;letter-spacing:-.2px;max-width:296px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
      .tx small{font-size:12px;line-height:14.3px;color:var(--sec);letter-spacing:0;white-space:nowrap}
      .chap{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;padding:0 14px 14px}
      .chap div{height:60px;border-radius:12px;background:rgba(116,116,128,.08);padding:12px 10px;display:flex;flex-direction:column;align-items:center;gap:8px}
      .chap div.off{opacity:.4}
      .chap div.off .ic{color:#757575}
      .chap .ic{height:24px;display:grid;place-items:center;color:#000}
      .chap i{display:block;width:100%;height:4px;border-radius:2px;background:rgba(120,120,128,.16);overflow:hidden}
      .chap i b{display:block;height:100%;width:0;border-radius:2px;background:var(--c);transition:width 1.1s cubic-bezier(.3,.7,.2,1)}
      .kt .chap{--c:var(--sysblue)} .ks .chap{--c:var(--sysorange)}
    `, `
      <div class="bar"></div>
      <div class="lt"></div>
      <div class="gl wk">${sz(SF.stack, 23, 24, "s1")}${sz(SF.calendar, 21.7, 19.7, "s2")}<span class="dot"></span></div>
      <div class="gl ts"><span class="tile"><i style="left:8.4px"></i><i style="left:19.2px"></i></span><span class="dot"></span></div>
      <div class="chips"></div>
      <div class="pg"><div class="tiles"></div><div class="shelf"></div></div>
      <div class="foot"></div>`);
  }
  get _ko() { return this.t === STR.ko; }
  build() {
    this.$(".tiles").innerHTML = CH.map(([n, w, h]) => `<div><span class="ic">${sz(SF[n], w, h)}</span><b>0</b><small></small></div>`).join("");
    this.reset();
  }
  /* chrome strings, re-read on every reset: a host (<nw-review>) can set our lang after we were built */
  _labels() {
    const ko = this._ko;
    this.$(".lt").textContent = ko ? "복습" : "Review";
    this._L = ko ? ["단어", "표현", "문장", "섀도잉"] : ["Words", "Expressions", "Sentences", "Shadowing"];
    this.$$(".tiles small").forEach((e, i) => e.textContent = this._L[i]);
  }
  _chips(n) {
    const ko = this._ko, names = ko ? ["학습 중", "대화", "상황연습", "완료"] : ["Studying", "Talk", "Watch", "Finished"];
    this.$(".chips").innerHTML = names.map((nm, i) => `<span class="${i ? "" : "on"}">${nm}<sup>${n[i]}</sup></span>`).join("");
  }
  _tiles(v) { this.$$(".tiles b").forEach((b, i) => b.textContent = v[i]); }
  /* bars: fraction 0…1 per chapter, or -1 for a chapter this book has nothing in (dimmed in place) */
  _card({ kind, tag, title, sub, score, bars }) {
    const cover = kind === "t" ? sz(SF.bubbles, 28, 23) : sz(SF.newspaper, 22, 21);
    return `<div class="slot"><div><div class="bk k${kind}"><div class="top"><span class="disc">${cover}</span>${score ? `<span class="score">${score}</span>` : ""}
      <div class="tx"><span class="og">${esc(tag)}</span><b>${esc(title)}</b><small>${esc(sub)}</small></div></div>
      <div class="chap">${CH.map(([n, w, h], i) => `<div class="${bars[i] < 0 ? "off" : ""}"><span class="ic">${sz(SF[n], w, h)}</span><i><b data-v="${Math.max(0, bars[i])}"></b></i></div>`).join("")}</div></div></div></div>`;
  }
  _talk(sub, bars) {
    const ko = this._ko;
    return this._card({ kind: "t", tag: ko ? "대화 · 자유 대화" : "Talk · Free talk", title: "“Honestly, it went really well. I…”", sub, score: 75, bars });
  }
  _scenes() {
    const ko = this._ko, w = r => ko ? `상대: ${r}` : `with ${r}`, tag = ko ? "상황연습 · 뉴스" : "Watch · News";
    return this._card({ kind: "s", tag, title: "Germany weighs a nationwide four-day work week", sub: w("the discussion"), bars: [.66, 0, -1, 0] })
      + this._card({ kind: "s", tag, title: "AI tutors are reshaping how adults learn languages", sub: w("the discussion"), bars: [.3, 0, -1, 0] })
      + this._card({ kind: "s", tag, title: "Why night trains are quietly making a comeback in Europe", sub: w("the discussion"), bars: [.12, 0, -1, 0] });
  }
  _fillBars(root = this.shadowRoot) { root.querySelectorAll(".chap b").forEach(b => b.style.width = b.dataset.v * 100 + "%"); }
  /** Before the talk: the scene books only. */
  reset() {
    this._labels(); this._chips([32, 25, 8, 1]); this._tiles([84, 3, 0, 0]);
    this.$(".shelf").innerHTML = this._scenes(); this._fillBars();
  }
  async pose(name) {
    this.stop();
    if (name === "before") { this.reset(); return; }
    if (name === "arrived") { this.reset(); await this.arrive(); return; }   // where demo() ends
    // real/practice-studying.png — the capture's own texts (its clock put the talk "in 1 hour")
    this._labels(); this._chips([33, 26, 8, 1]); this._tiles([89, 5, 0, 0]);
    this.$(".shelf").innerHTML = this._talk(this._ko ? "1시간 후 학습함" : "Studied in 1 hour", [0, 0, 0, 0]) + this._scenes(); this._fillBars();
  }
  async arrive() {
    const ko = this._ko, d = document.createElement("div");
    d.innerHTML = this._talk(ko ? "지금 학습함" : "Studied now", [.24, .15, -1, 0]);
    const slot = d.firstElementChild; slot.classList.add("in");
    slot.querySelectorAll(".chap b").forEach(b => b.style.width = "0");
    this.$(".shelf").prepend(slot);
    this._chips([33, 26, 8, 1]);
    slot.offsetHeight; slot.classList.remove("in");
    await this.sleep(800);
    this._fillBars(slot);
    const tiles = this.$$(".tiles b"), from = [84, 3, 0, 0], to = [89, 5, 0, 0];
    await Promise.all(tiles.map((b, i) => to[i] === from[i] ? null : this.countUp(b, to[i] - from[i], 1100, v => from[i] + v)));
  }
  async demo() { await this.sleep(900); this.beat(1); await this.arrive(); await this.sleep(3200); }
}

export { NwBook };
