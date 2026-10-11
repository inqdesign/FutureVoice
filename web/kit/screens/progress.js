/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* SF Symbols this screen draws (24-unit boxes). */
const SF = {
  cal: '<g fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2.8" y="4.2" width="18.4" height="16" rx="3"/></g><path d="M2.8 7.2c0-1.7 1.3-3 3-3h12.4c1.7 0 3 1.3 3 3v1.6H2.8z" fill="currentColor" opacity=".55"/><g fill="currentColor">' +
    [11.4, 14.2, 17].map((y, r) => [6.6, 9.3, 12, 14.7, 17.4].filter((_, c) => !(r === 0 && c < 2) && !(r === 2 && c > 2)).map(x => `<rect x="${x - .75}" y="${y - .75}" width="1.5" height="1.5" rx=".3"/>`).join("")).join("") + "</g>",
  info: '<circle cx="12" cy="12" r="9.6" fill="none" stroke="currentColor" stroke-width="1.7"/><circle cx="12" cy="7.6" r="1.25" fill="currentColor"/><path d="M10.2 10.6h2.3v6.2M10 16.8h4.6" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
  chev: '<path d="M9 5.5l6.5 6.5L9 18.5" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>',
};
const sf = (n, cls = "sf") => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${SF[n]}</svg>`;

const L = {
  ko: { title: "성장", est: "추정 레벨", next: "다음 평가", how: "판정 방식", growth: "성장", across: "영역별",
    can: { B1: "익숙한 주제는 무리 없이 이야기하고, 간단한 이야기도 들려줄 수 있어요.", B2: "추상적인 주제까지 포함해 여러 주제를 분명하고 자세히 말할 수 있어요." },
    assessed: "1초 전에 최근 대화로 평가했어요. 어휘·문법·유창성·표현을 함께 봤어요.",
    assessedOld: "2주 전에 최근 대화로 평가했어요. 어휘·문법·유창성·표현을 함께 봤어요.",
    newTalk: (a, b) => `새 대화 ${a}/${b}분`, days: n => `${n} more days`, more: n => `${n}분 더 대화하면 그동안 새로 말한 걸 전부 모아 레벨을 다시 판정해요.`,
    curve: "성장 곡선은 두 번째 평가부터 그려져요. 평가할 때마다 점이 하나씩 찍히고, 레벨은 평가로만 움직여요." },
  en: { title: "Progress", est: "Estimated level", next: "Next assessment", how: "How this is assessed", growth: "Growth", across: "Across skills",
    can: { B1: "Familiar topics fluently enough to get by, and tell a simple story.", B2: "Clear, detailed talk on many topics, including some abstract ones." },
    assessed: "Assessed 1 second ago from your recent talk — vocabulary, grammar, fluency and expression together.",
    assessedOld: "Assessed 2 weeks ago from your recent talk — vocabulary, grammar, fluency and expression together.",
    newTalk: (a, b) => `${a}/${b} min new talk`, days: n => `${n} more days`, more: n => `Talk ${n} more minutes and this level gets re-read from everything new you've said.`,
    curve: "Your growth curve starts at your second assessment — every assessment adds a point here, and only assessments move your level." },
};
/* skill rows (Dim.short is not localized in the app — the chips and rows read English in every language) */
const SKILLS = [["Vocabulary", "B1"], ["Fluency", "≈A1"], ["Grammar", "≈B1"], ["Expressiveness", "≈B1"]];

/* ═══════════════════════════ <nw-progress> — measured level ═══════════════════════════ */
class NwProgress extends NwScreen {
  static poses = ["overall", "before"];
  constructor() {
    super(`
      :host{background:#F2F2F7}
      .sf{width:1em;height:1em;display:block;flex:0 0 auto}
      .pg{position:absolute;inset:0;background:#F2F2F7;word-break:keep-all;line-break:strict}
      .hdr{position:absolute;left:0;right:0;top:0;height:200px;background:linear-gradient(#FAFAFD 0,#FAFAFD 150px,rgba(250,250,253,0) 200px);z-index:2;pointer-events:none}
      .lt{position:absolute;left:18px;top:57px;font-family:var(--pixel);font-size:34px;line-height:40px;letter-spacing:0;z-index:3}
      .chips{position:absolute;left:18px;top:124.5px;display:flex;gap:8px;white-space:nowrap;z-index:3}
      .chips span{height:37px;padding:0 16px;border-radius:19px;background:#fff;display:flex;align-items:center;font-size:17px;font-weight:500;letter-spacing:-.15px}
      .chips span.on{background:#000;color:#fff}
      .col{position:absolute;left:18px;right:18px;top:180.4px;display:flex;flex-direction:column;gap:16px}
      .card{position:relative;border-radius:20px;background:#fff;padding:18px;display:flex;flex-direction:column;gap:12px}
      .cap{font-size:12px;line-height:16px;font-weight:600;color:#8A8A8E}
      .lvl{position:relative;height:62px;margin:0}
      .lvl b{position:absolute;left:0;top:0;font-family:var(--pixel);font-weight:400;font-size:52px;line-height:62px;color:#0A5CF5;letter-spacing:2px;transition:opacity .5s,transform .5s}
      .lvl b.out{opacity:0;transform:translateY(-14px)} .lvl b.wait{opacity:0;transform:translateY(14px)}
      .can{font-size:16px;line-height:22px;letter-spacing:-.25px;transition:opacity .4s}
      .can.fade{opacity:0}
      .note{font-size:12px;line-height:16px;color:#8A8A8E;margin-top:-1px;letter-spacing:0}
      .n1{padding-right:42px}
      .div{height:.5px;background:rgba(60,60,67,.16);margin:0}
      .bar{display:flex;align-items:center;gap:10px;margin-top:-3px}
      .bar i{flex:1;height:4px;border-radius:2px;background:#E4E4E6;overflow:hidden}
      .bar i b{display:block;height:100%;width:40%;border-radius:2px;background:#0A5CF5;transition:width 1.2s cubic-bezier(.3,.7,.2,1)}
      .bar span{letter-spacing:0;font-size:12px;line-height:16px;color:#8A8A8E;font-variant-numeric:tabular-nums;white-space:nowrap}
      .cond{display:flex;align-items:center;gap:8px;font-size:15px;line-height:20px;margin-top:-2px}
      .cond .ic{width:22px;display:grid;place-items:center;color:#8A8A8E}
      .cond .sf{width:16px;height:16px}
      .how{display:flex;align-items:center;gap:7px;color:#0A5CF5;font-size:13px;font-weight:500;line-height:18px;margin-top:-2px}
      .how .sf{width:15px;height:15px}
      .c2{gap:12px}
      .hd{font-size:17px;font-weight:600;line-height:22px;letter-spacing:-.4px}
      .sec{font-size:16px;line-height:21px;color:#8A8A8E;letter-spacing:0;word-break:normal;padding-right:4px}
      .c3{gap:12px}
      .sk+.sk{margin-top:12px}
      .sk{display:flex;align-items:center;padding:7px 0;font-size:15px;line-height:20px}
      .sk span{flex:1}
      .sk b{font-weight:600;color:#8A8A8E;transition:opacity .35s}
      .sk b.hide{opacity:0}
      .sk .sf{width:12px;height:12px;color:#C4C4C7;margin-left:8px}
      .fade-b{position:absolute;left:0;right:0;bottom:0;height:120px;background:linear-gradient(rgba(247,247,249,0),rgba(247,247,249,.8) 40%,rgba(247,248,249,.97) 60%,#F7F8F9);z-index:2;pointer-events:none}
    `, `
      <div class="pg">
        <div class="hdr"></div><div class="lt"></div>
        <div class="chips"><span class="on">Overall</span><span>Vocabulary</span><span>Grammar</span><span>Fluency</span><span>Expressiveness</span></div>
        <div class="col"><div class="card c1"><div class="cap k1"></div><div class="lvl"><b class="a">B1</b><b class="b wait">B2</b></div>
          <div class="can"></div><div class="note n1"></div><div class="div"></div>
          <div class="cap k2"></div><div class="bar"><i><b></b></i><span class="k3"></span></div>
          <div class="cond"><span class="ic">${sf("cal")}</span><span class="k4"></span></div>
          <div class="note k5"></div>
          <div class="how">${sf("info")}<span class="k6"></span></div></div>
        <div class="card c2"><div class="hd g1"></div><div class="sec g2"></div></div>
        <div class="card c3"><div class="hd s1"></div><div class="rows"></div></div></div>
        <div class="fade-b"></div>
      </div>`);
  }
  get l() { return L[this.t === STR.ko ? "ko" : "en"]; }
  build() {
    const l = this.l;
    this.$(".lt").textContent = l.title; this.$(".k1").textContent = l.est; this.$(".k2").textContent = l.next;
    this.$(".k4").textContent = l.days(7); this.$(".k6").textContent = l.how;
    this.$(".g1").textContent = l.growth; this.$(".g2").textContent = l.curve; this.$(".s1").textContent = l.across;
    this.$(".rows").innerHTML = SKILLS.map(([n, v]) => `<div class="sk"><span>${n}</span><b>${v}</b>${sf("chev")}</div>`).join("");
    this.reset();
  }
  _talk(min) { // the next-assessment bar: min of 10 new minutes talked
    const l = this.l;
    this.$(".bar b").style.width = `${min * 10}%`; this.$(".k3").textContent = l.newTalk(min, 10);
    this.$(".k5").textContent = l.more(10 - min); this.$(".k5").style.display = min < 10 ? "" : "none";
  }
  _level(lv, assessedNow) {
    const l = this.l, b2 = lv === "B2";
    this.$(".lvl .a").className = b2 ? "a out" : "a"; this.$(".lvl .b").className = b2 ? "b" : "b wait";
    this.$(".can").textContent = l.can[lv]; this.$(".n1").textContent = assessedNow ? l.assessed : l.assessedOld;
  }
  /* demo start: B1 from two weeks ago, nothing new talked yet */
  reset() {
    this._level("B1", false); this._talk(0);
    this.$$(".sk b").forEach(b => b.classList.add("hide"));
  }
  async pose(name) {
    this.reset();
    if (name === "overall") { this._level("B2", true); this._talk(4); this.$$(".sk b").forEach(b => b.classList.remove("hide")); }
  }
  async demo() {
    await this.sleep(700); this.beat(1);
    this.$$(".sk b").forEach((b, i) => setTimeout(() => b.classList.remove("hide"), RM ? 0 : i * 160));
    for (const m of [2, 4, 7, 10]) { this._talk(m); await this.sleep(520); }
    await this.sleep(700);
    this.beat(2);
    const can = this.$(".can"); can.classList.add("fade");
    this.$(".lvl .a").className = "a out"; this.$(".lvl .b").className = "b";
    await this.sleep(400);
    this._level("B2", true); can.classList.remove("fade"); this._talk(0);
    await this.sleep(3000);
  }
}

export { NwProgress };
