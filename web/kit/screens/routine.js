/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* SF Symbols this screen draws, traced at their sizes (24-unit boxes). */
const SF = {
  phone: '<path fill="currentColor" d="M7.2 3.1c.6-.1 1.1.2 1.4.7l1.6 3c.3.6.2 1.2-.2 1.7L8.8 9.7c-.2.2-.2.5-.1.8.9 1.8 2.9 3.8 4.7 4.7.3.1.6.1.8-.1l1.2-1.2c.5-.4 1.1-.5 1.7-.2l3 1.6c.5.3.8.8.7 1.4-.3 2.3-2.2 4.1-4.6 3.9C10.4 20.1 3.9 13.6 3.3 7.7c-.2-2.4 1.6-4.3 3.9-4.6z"/>',
  again: '<g fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"><path d="M10.2 5.3A7.2 7.2 0 1 1 5.2 11"/></g><path fill="currentColor" d="M12.6 1.9v7.2L7.6 5.5z"/>',
  seal: (() => { let d = ""; const n = 12; for (let i = 0; i <= n * 2; i++) { const a = Math.PI * i / n - Math.PI / 2, r = i % 2 ? 8.6 : 10.2; d += `${i ? "L" : "M"}${(12 + r * Math.cos(a)).toFixed(2)} ${(12 + r * Math.sin(a)).toFixed(2)}`; } return `<path fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" d="${d}Z"/><path d="M8.2 12.3l2.6 2.6 5-5.4" fill="none" stroke="var(--tile,#fff)" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>`; })(),
  stack: '<g fill="currentColor"><rect x="6" y="3.2" width="12" height="2" rx="1"/><rect x="4.3" y="6.6" width="15.4" height="2.2" rx="1.1"/><rect x="2.8" y="10" width="18.4" height="11" rx="2.6"/></g>',
  wave: '<path d="M3.5 10.5v3M7.2 7v10M10.9 3.5v17M14.6 7.5v9M18.3 9.5v5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>',
  checkFill: '<circle cx="12" cy="12" r="11" fill="currentColor"/><path d="M7 12.4l3.3 3.3L17.2 8.6" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
  xFill: '<circle cx="12" cy="12" r="11" fill="currentColor"/><path d="M8.2 8.2l7.6 7.6M15.8 8.2l-7.6 7.6" fill="none" stroke="#fff" stroke-width="2.3" stroke-linecap="round"/>',
  flame: '<path fill="currentColor" d="M12.4 1.8c.4 3.1 2.3 4.7 4 6.6 1.6 1.8 3 3.8 3 6.7 0 4.2-3.2 7.1-7.3 7.1S4.6 19.4 4.6 15.4c0-2.5 1.1-4.4 2.5-5.9.3-.3.8-.1.8.3.1 1.2.6 2.3 1.4 2.9-.2-4.5 1-8.3 3.1-10.9zM12.2 13c-1.6 1.6-2.7 3.1-2.7 4.9 0 1.6 1.2 2.8 2.7 2.8s2.7-1.2 2.7-2.8c0-1.8-1-3.3-2.7-4.9z"/>',
  book: '<path fill="currentColor" d="M6.3 2.5h11c1 0 1.8.8 1.8 1.8v13.4c0 .5-.4.9-.9.9H7.3c-.6 0-1 .4-1 1s.4 1 1 1h10.9c.5 0 .9.4.9.9s-.4.9-.9.9H7.3c-1.7 0-2.9-1.3-2.9-2.9V4.4c0-1 .8-1.9 1.9-1.9zm3 3.6c-.4 0-.7.3-.7.7s.3.7.7.7h6.1c.4 0 .7-.3.7-.7s-.3-.7-.7-.7zm0 3c-.4 0-.7.3-.7.7s.3.7.7.7h4.1c.4 0 .7-.3.7-.7s-.3-.7-.7-.7z"/>',
  share: '<g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2.8v12.4M8.2 6.4L12 2.6l3.8 3.8"/><path d="M8.6 9.3H7.2c-1.2 0-2 .9-2 2v8c0 1.1.8 2 2 2h9.6c1.2 0 2-.9 2-2v-8c0-1.1-.8-2-2-2h-1.4"/></g>',
};
const sf = (n, cls = "sf") => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${SF[n]}</svg>`;

/* Kind colours (StudyPlan.Kind.color — iOS 26 system colours as the simulator draws them) */
const KIND = {
  talk: ["phone", "#0088FF"], again: ["again", "#00C3D0"], test: ["seal", "#FF8D28"],
  review: ["stack", "#34C759"], shadow: ["wave", "#FFCC00"],
};

const L = {
  ko: { title: "나의 루틴", edit: "편집", seg: ["일", "월", "연"], date: "10월 10일 (토)", wd: ["수", "목", "금", "토", "일", "월", "화"],
    keepFirst: "오늘 지키면 1일째", kept: n => `${n}일째 지키는 중`, extra: "계획 밖", share: "카드 공유", talkTime: "통화 시간", talks: "통화",
    test: "주간 테스트", done: "완료", which: "어떤 단어의 뜻일까요?", right: "정답", cont: "계속",
    plan: [["talk", "대화 10분", "8:00"], ["again", "다시 말하기", "8:20", "대화 고르기"], ["test", "주간 테스트", "10:00"], ["review", "복습 20개", "12:30", "약 18개 기다리는 중"], ["shadow", "섀도잉 5문장", "18:00"]] },
  en: { title: "My routine", edit: "Edit", seg: ["Day", "Month", "Year"], date: "Sat, Oct 10", wd: ["W", "T", "F", "S", "S", "M", "T"],
    keepFirst: "Keep it today for day 1", kept: n => `Kept for ${n} days`, extra: "Extra", share: "Share card", talkTime: "Talk time", talks: "Talks",
    test: "Weekly test", done: "Done", which: "Which word means this?", right: "Right", cont: "Continue",
    plan: [["talk", "Talk 10 min", "8:00"], ["again", "Say it again", "8:20", "Pick a talk"], ["test", "Weekly test", "10:00"], ["review", "Review 20 items", "12:30", "About 18 waiting"], ["shadow", "Shadowing 5 lines", "18:00"]] },
};

/* The capture's day: what happened, mostly outside the plan. */
const CAP_ROWS = l => [["talk", "Coffee with Sarah", "8:02–8:14", l.extra, 1], ["again", l.ko ? "다시 말하기" : "Say it again", "8:20–8:25", l.extra, 1],
  ["test", l.test, "10:00", null, 0, true], ["talk", "How the interview went", "21:11–21:21", l.extra, 1],
  ["talk", "How the interview went", "21:11–21:21", l.extra, 1], ["talk", "Weekend plans", "21:40–21:52", l.extra, 1],
  ["talk", "How the interview went", "23:11–23:21", l.extra, 1], ["talk", "How the interview went", "23:12–23:22", l.extra, 1]];

const TEST_CAP = { prompt: "In a loose or not taut manner; without tension.", opts: ["that", "mover", "mine", "initiative"], n: "1/13", right: -1 };
const TEST_DEMO = { prompt: "Feeling like you have too much to deal with.", opts: ["tremendous", "overwhelmed", "forbidden", "substantial"], n: "3/13", right: 1 };

/* ═══════════════════════════ <nw-routine> — my routine, and the weekly test ═══════════════════════════ */
class NwRoutine extends NwScreen {
  static poses = ["day", "day-plan", "day-kept", "test", "test-right"];
  constructor() {
    super(`
      :host{background:#F2F2F7}
      .sf{width:1em;height:1em;display:block;flex:0 0 auto}
      .navt{position:absolute;left:0;right:0;top:71px;text-align:center;font-family:var(--pixel);font-size:17px;line-height:22px;z-index:3;letter-spacing:0}
      .glass{right:17px!important;color:#0A5CF5;font-weight:500;padding:0 16px;background:rgba(255,255,255,.75)}
      .l-day{background:#F2F2F7}
      .seg{position:absolute;left:20px;right:20px;top:124px;height:32px;border-radius:16px;background:#E3E3E8;display:flex;padding:2px}
      .seg span{flex:1;display:grid;place-items:center;font-size:14px;font-weight:400;border-radius:14px}
      .seg span.on{background:#fff;box-shadow:0 2px 6px rgba(0,0,0,.08),0 0 0 .5px rgba(0,0,0,.04)}
      .day{position:absolute;left:20px;top:168px;font-size:20px;font-weight:700;line-height:25px;letter-spacing:-.3px}
      .streak{position:absolute;left:20px;top:194px;font-size:15px;line-height:20px;color:#8A8A8E;display:flex;align-items:center;gap:10px;letter-spacing:0}
      .streak .sf{width:16px;height:19px;color:#8A8A8E;transition:color .3s}
      .streak.lit .sf{color:#FF8D28}
      .strip{position:absolute;left:0;right:0;top:225px;height:76px;-webkit-mask:linear-gradient(90deg,transparent 0,#000 12%,#000 88%,transparent);mask:linear-gradient(90deg,transparent 0,#000 12%,#000 88%,transparent)}
      .cell{position:absolute;top:2px;width:52px;height:72px;border-radius:16px;display:flex;flex-direction:column;align-items:center;padding-top:9px;gap:6px}
      .cell.sel{background:#fff;box-shadow:inset 0 0 0 .5px rgba(60,60,67,.29)}
      .cell small{font-size:11px;line-height:13px;color:#8A8A8E}
      .cell.sel small{color:#000;font-weight:600}
      .dc{position:relative;width:32px;height:32px;display:grid;place-items:center}
      .dc svg{position:absolute;inset:0;width:32px;height:32px;overflow:visible}
      .dc b{position:relative;font-size:13px;font-weight:600;font-variant-numeric:tabular-nums;color:#8A8A8E;transition:color .3s}
      .dc .fillc{opacity:0;transition:opacity .35s}
      .dc.kept .fillc{opacity:1} .dc.kept b{color:#fff}
      .dc.today b{color:#000} .dc.rest b{color:#BDBDC2}
      .panel{position:absolute;left:0;right:0;top:315px;height:620px;background:#fff;border-radius:28px 28px 0 0;box-shadow:0 -2px 12px rgba(0,0,0,.06);padding:8px 20px 0}
      .row{position:relative;display:flex;align-items:center;gap:12px;padding:8px 0;height:54.2px}
      .row+.row::before{content:"";position:absolute;left:48px;right:0;top:0;height:.5px;background:rgba(60,60,67,.22)}
      .tile{width:36px;height:36px;border-radius:10px;display:grid;place-items:center;flex:0 0 auto}
      .tile .sf{width:17px;height:17px}
      .tx{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
      .tx b{font-size:17px;font-weight:500;line-height:21px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;letter-spacing:-.2px}
      .tx small{font-size:13px;line-height:17px;color:#8A8A8E;font-variant-numeric:tabular-nums;white-space:nowrap;letter-spacing:-.1px}
      .row.faded b{color:#8A8A8E}
      .ring{position:relative;width:22px;height:22px;flex:0 0 auto;margin-right:2px}
      .ring svg{position:absolute;inset:0;width:22px;height:22px;overflow:visible}
      .ring .ck{position:absolute;inset:0;width:22px;height:22px;color:#34C759;opacity:0;transform:scale(.6);transition:opacity .25s,transform .3s}
      .ring.on .ck{opacity:1;transform:none} .ring.on .tr{opacity:0}
      .ring .arc{transition:stroke-dashoffset .6s ease}
      .foot{position:absolute;left:20px;right:20px;top:785px;border-top:.5px solid rgba(60,60,67,.22);padding-top:15px;display:flex;gap:16px}
      .foot .pic{width:132px;height:165px;border-radius:16px;background:#141310;flex:0 0 auto}
      .foot .st{flex:1;display:flex;flex-direction:column;gap:12px;padding-left:2px}
      .foot .sh{align-self:flex-end;display:flex;align-items:center;gap:8px;color:#0A5CF5;font-size:17px;line-height:22px}
      .foot .sh .sf{width:19px;height:21px}
      .foot .kv{display:flex;justify-content:space-between;font-size:17px;line-height:22px}
      .foot .kv span{color:#8A8A8E} .foot .kv b{font-weight:500;font-variant-numeric:tabular-nums}
      /* weekly test */
      .l-test{background:#fff}
      .host{position:absolute;left:162.6px;top:130px;width:76.8px;height:76.8px;border-radius:20px;background:#F2F2F7}
      .eye{position:absolute;width:10.5px;height:14.3px;margin:-7.15px 0 0 -5.25px;border-radius:3.4px;background:#1A1A1A;transition:transform .32s cubic-bezier(.3,.7,.3,1.3)}
      .cap{position:absolute;left:20px;right:20px;top:228px;display:flex;align-items:center;justify-content:space-between;color:#8A8A8E}
      .cap span{display:flex;align-items:center;gap:9px;font-size:15px;font-weight:600;line-height:20px;letter-spacing:-.25px}
      .cap .sf{width:17px;height:19px}
      .cap em{font-style:normal;font-size:13px;font-weight:600;font-variant-numeric:tabular-nums;letter-spacing:.2px}
      .qq{position:absolute;left:20px;width:262px;top:265px;font-size:22px;font-weight:600;line-height:28px;letter-spacing:0}
      .opts{position:absolute;left:20px;right:20px;top:341.6px;display:flex;flex-direction:column;gap:10.6px}
      .opt{height:62px;border-radius:31px;background:#D3E2FD;color:#0A5CF5;display:flex;align-items:center;padding:0 20px;font-size:17px;letter-spacing:-.3px;transition:background .3s,color .3s}
      .opt span{flex:1}
      .opt .sf{width:20px;height:20px;opacity:0;transition:opacity .25s}
      .opt.right{background:rgba(52,199,89,.16);color:#1F9E44} .opt.right .sf{opacity:1;color:#34C759}
      .opt.dim{background:rgba(142,142,147,.14);color:#6D6D72}
      .bar{position:absolute;left:0;right:0;bottom:0;padding:12px 20px 46px;background:#fff;display:flex;flex-direction:column;gap:12px;transform:translateY(100%);opacity:0;transition:transform .3s ease,opacity .3s}
      .bar.on{transform:none;opacity:1}
      .bar .vr{display:flex;align-items:center;gap:10px;font-size:15px;font-weight:600}
      .bar .vr .sf{width:22px;height:22px;color:#34C759}
      .bar .go{height:50px;border-radius:25px;background:#34C759;color:#fff;display:grid;place-items:center;font-size:17px;font-weight:600}
    `, `
      <div class="layer l-day on">
        <div class="glass gl1"></div><div class="navt t1"></div>
        <div class="seg"></div><div class="day"></div><div class="streak">${sf("flame")}<span></span></div>
        <div class="strip"></div>
        <div class="panel"><div class="rows"></div></div>
        <div class="foot"><div class="pic"></div><div class="st"><span class="sh">${sf("share")}<span class="shl"></span></span>
          <div class="kv"><span class="k1"></span><b>00:00</b></div><div class="kv"><span class="k2"></span><b>6</b></div></div></div>
      </div>
      <div class="layer l-test">
        <div class="glass gl2"></div><div class="navt t2"></div>
        <div class="host"><i class="eye"></i><i class="eye"></i></div>
        <div class="cap"><span>${sf("book")}<span class="cq"></span></span><em></em></div>
        <div class="qq"></div>
        <div class="opts"></div>
        <div class="bar"><div class="vr">${sf("checkFill")}<span class="rl"></span></div><div class="go"></div></div>
      </div>`);
  }
  get l() { const ko = this.t === STR.ko; return { ...L[ko ? "ko" : "en"], ko }; }
  build() {
    const l = this.l;
    this.$(".gl1").textContent = l.edit; this.$(".gl2").textContent = l.done;
    this.$(".t1").textContent = l.title; this.$(".t2").textContent = l.test;
    this.$(".seg").innerHTML = l.seg.map((x, i) => `<span class="${i ? "" : "on"}">${x}</span>`).join("");
    this.$(".day").textContent = l.date;
    this.$(".shl").textContent = l.share; this.$(".k1").textContent = l.talkTime; this.$(".k2").textContent = l.talks;
    this.$(".cq").textContent = l.which; this.$(".rl").textContent = l.right; this.$(".go").textContent = l.cont;
    // strip: seven cells, 52pt wide on a 58pt pitch, Saturday held in the middle
    const C = 2 * Math.PI * 14.5;
    this.$(".strip").innerHTML = l.wd.map((w, i) => `<div class="cell${i === 3 ? " sel" : ""}" style="left:${175 + (i - 3) * 58}px"><small>${w}</small>
      <div class="dc"><svg viewBox="0 0 32 32"><circle class="fillc" cx="16" cy="16" r="16" fill="#34C759"/>
        <circle class="ringc" cx="16" cy="16" r="15" fill="none"/><circle class="arcc" cx="16" cy="16" r="14.5" fill="none" stroke="#34C759" stroke-width="3" stroke-linecap="round"
        stroke-dasharray="${C}" stroke-dashoffset="${C}" transform="rotate(-90 16 16)" style="transition:stroke-dashoffset .5s"/></svg><b>${7 + i}</b></div></div>`).join("");
    this.reset();
  }
  /* one circle's face: kept · missed · today(progress) · rest · ahead(planned) */
  _mark(i, kind, p = 0, planned = true) {
    const dc = this.$$(".dc")[i], ring = dc.querySelector(".ringc"), arc = dc.querySelector(".arcc"), C = 2 * Math.PI * 14.5;
    dc.className = "dc " + kind;
    ring.removeAttribute("stroke-dasharray"); ring.setAttribute("r", 15); ring.setAttribute("stroke-width", 2); ring.setAttribute("stroke", "none");
    arc.style.opacity = 0;
    if (kind === "missed") ring.setAttribute("stroke", "#D1D1D6");
    if (kind === "today") { ring.setAttribute("r", 14.5); ring.setAttribute("stroke-width", 3); ring.setAttribute("stroke", "#E5E5EA"); arc.style.opacity = 1; arc.setAttribute("stroke-dashoffset", C * (1 - Math.max(.001, p))); }
    if (kind === "ahead" && planned) { ring.setAttribute("r", 15.25); ring.setAttribute("stroke-width", 1.5); ring.setAttribute("stroke", "#D1D1D6"); ring.setAttribute("stroke-dasharray", "3 3"); }
  }
  _streak(text, lit) { this.$(".streak span").textContent = text; this.$(".streak").classList.toggle("lit", !!lit); }
  _rows(rows) {
    const R = 2 * Math.PI * 10;
    this.$(".rows").innerHTML = rows.map(([k, title, time, detail, done, faded]) => {
      const [sym, col] = KIND[k], c = faded ? "#8A8A8E" : col;
      return `<div class="row${faded ? " faded" : ""}"><span class="tile" style="background:${c}24;color:${c}">${sf(sym)}</span>
        <span class="tx"><b>${esc(title)}</b><small>${esc([time, detail].filter(Boolean).join(" · "))}</small></span>
        <span class="ring${done ? " on" : ""}"><svg class="tr" viewBox="0 0 22 22"><circle cx="11" cy="11" r="10" fill="none" stroke="#D1D1D6" stroke-opacity="${faded ? .6 : 1}" stroke-width="2"/>
          <circle class="arc" cx="11" cy="11" r="10" fill="none" stroke="#34C759" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="${R}" stroke-dashoffset="${R}" transform="rotate(-90 11 11)"/></svg>${sf("checkFill", "sf ck")}</span></div>`;
    }).join("");
  }
  /* p of a planned block done: the ring fills; a talk's detail reads "4/10분" while it runs; done drops the detail */
  _fill(i, p) {
    const row = this.$$(".row")[i], ring = row.querySelector(".ring"), arc = ring.querySelector(".arc"), R = 2 * Math.PI * 10;
    const plan = this.l.plan[i], small = row.querySelector("small");
    if (p >= 1) { ring.classList.add("on"); if (plan) small.textContent = plan[2]; return; }
    arc.setAttribute("stroke-dashoffset", R * (1 - p));
    if (plan && plan[0] === "talk") small.textContent = `${plan[2]} · ${this.l.ko ? `${Math.floor(p * 10)}/10분` : `${Math.floor(p * 10)} of 10 min`}`;
  }
  _test(q) {
    this.$(".qq").textContent = q.prompt; this.$(".cap em").textContent = q.n;
    this.$(".opts").innerHTML = q.opts.map(o => `<div class="opt"><span>${esc(o)}</span>${sf("checkFill")}</div>`).join("");
    this.$(".bar").classList.remove("on"); this._eyes(1, 0);
  }
  /* the host's two eyes, offset in cells from rest (WeeklyTestCharacter: 12.8pt cells, 2 apart, row 2.5) */
  _eyes(dx, dy, sy = 1) {
    this.$$(".eye").forEach((e, i) => {
      e.style.left = `${38.4 + (i ? 12.8 : -12.8)}px`; e.style.top = "32px";
      e.style.transform = `translate(${dx * 12.8}px,${dy * 12.8}px) scaleY(${sy})`;
    });
  }
  _answer(q) {
    this.$$(".opt").forEach((o, i) => o.classList.add(i === q.right ? "right" : "dim"));
    this.$(".bar").classList.add("on"); this._eyes(0, -.6);
  }
  _show(test) { this.$$(".layer").forEach(x => x.classList.toggle("on", x.classList.contains(test ? "l-test" : "l-day"))); }
  /* demo state: a planned day, three days kept behind it */
  reset() {
    const l = this.l;
    this._show(false);
    this.$(".foot").style.display = "none";
    this._rows(l.plan.map(([k, t, time, d]) => [k, t, time, d, 0]));
    [0, 1, 2].forEach(i => this._mark(i, "kept")); this._mark(3, "today", 0); this._mark(4, "rest"); this._mark(5, "ahead"); this._mark(6, "ahead");
    this._streak(l.kept(3), true);
    this._test(TEST_DEMO);
  }
  async pose(name) {
    const l = this.l;
    this.reset();
    if (name === "day") {
      this._rows(CAP_ROWS(l)); this.$(".foot").style.display = "";
      [0, 1, 2].forEach(i => this._mark(i, "missed")); this._mark(3, "today", 0); this._mark(4, "ahead", 0, false);
      this._streak(l.keepFirst, false);
    }
    if (name === "day-kept") { for (let i = 0; i < 5; i++) this._fill(i, 1); this._mark(3, "kept"); this._streak(l.kept(4), true); }
    if (name === "test" || name === "test-right") { this._show(true); this._test(name === "test" ? TEST_CAP : TEST_DEMO); }
    if (name === "test-right") this._answer(TEST_DEMO);
  }
  async demo() {
    const l = this.l;
    await this.sleep(800); this.beat(1); await this.sleep(1300);
    this.beat(2);
    // the morning talk fills by its minutes, then the rest tick as they happen
    for (const p of [.4, .8, 1]) { this._fill(0, p); this._mark(3, "today", p * .2); await this.sleep(420); }
    for (let i = 1; i < 5; i++) { this._fill(i, 1); this._mark(3, "today", (i + 1) / 5); await this.sleep(650); }
    this.beat(3); this._mark(3, "kept"); this._streak(l.kept(4), true);
    await this.sleep(1700);
    this.beat(4); this._show(true);
    await this.sleep(700); this._eyes(-1, 0); await this.sleep(600); this._eyes(.5, .2); await this.sleep(700);
    this._answer(TEST_DEMO);
    await this.sleep(2600);
  }
}

export { NwRoutine };
