/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* ═══════════════════════════ <nw-people> — Watch tab, your people ═══════════════════════════
 * Drawn from WatchTab.swift (people row · two doors · "Your scenarios" grid), PersonBubble, and
 * CounterpartDetailView.swift for a person's card (with the form's "How you two talk" rows from
 * CounterpartFormView, so the card can show the register). Points throughout; accent sampled
 * from the capture (#0A5CF5).
 *   poses: watchtab (real/watchtab.png) · row · card · scenarios */

/* SF Symbols, traced */
const SY = {
  // person.2 — two outlined people, the right one larger (toolbar, regular)
  people: '<svg viewBox="0 0 31 20" width="31" height="20"><g fill="none" stroke="currentColor" stroke-width="1.75"><circle cx="9.3" cy="5.4" r="3.6"/><path d="M1.6 17.6c0-3.6 3.3-6.2 7.7-6.2 1.4 0 2.7.3 3.8.8"/><circle cx="20.6" cy="5.1" r="4.1"/><path d="M11.4 18.4h18.4c.5 0 .8-.4.7-.9-.7-3.6-4.6-6.2-9.9-6.2s-9.2 2.6-9.9 6.2c-.1.5.2.9.7.9z"/></g></svg>',
  plus: '<svg viewBox="0 0 20 20" width="20" height="20"><path d="M10 3v14M3 10h14" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"/></svg>',
  // square.and.pencil
  pencil: '<svg viewBox="0 0 22 22" width="22" height="22"><g fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M10 3.6H5.6A2.6 2.6 0 0 0 3 6.2v10.2A2.6 2.6 0 0 0 5.6 19h10.2a2.6 2.6 0 0 0 2.6-2.6V12"/><path d="M17.2 2.2l2.6 2.6-8.6 8.6-3.4.8.8-3.4z"/></g></svg>',
  // square.grid.2x2
  grid: '<svg viewBox="0 0 22 22" width="22" height="22"><g fill="none" stroke="currentColor" stroke-width="1.7"><rect x="2.5" y="2.5" width="7.2" height="7.2" rx="1.8"/><rect x="12.3" y="2.5" width="7.2" height="7.2" rx="1.8"/><rect x="2.5" y="12.3" width="7.2" height="7.2" rx="1.8"/><rect x="12.3" y="12.3" width="7.2" height="7.2" rx="1.8"/></g></svg>',
  // briefcase.fill
  brief: '<svg viewBox="0 0 26 22" width="26" height="22"><path fill="currentColor" fill-rule="evenodd" d="M9 3.4C9 2 10 1 11.4 1h3.2C16 1 17 2 17 3.4V5h5.3C24 5 25 6 25 7.7v3.6H1V7.7C1 6 2 5 3.7 5H9zm1.9 0v1.6h4.2V3.4c0-.3-.2-.5-.5-.5h-3.2c-.3 0-.5.2-.5.5zM1 12.9h10.2v1c0 .6.4 1 1 1h1.6c.6 0 1-.4 1-1v-1H25v5.5c0 1.6-1 2.6-2.7 2.6H3.7C2 21 1 20 1 18.4z"/></svg>',
  // cup.and.saucer.fill
  cup: '<svg viewBox="0 0 30 22" width="30" height="22"><g fill="currentColor"><path fill-rule="evenodd" d="M5 2.2C5 1.5 5.5 1 6.2 1h14.6c.7 0 1.2.5 1.2 1.2v1.2h1.4c2.5 0 4.3 1.6 4.3 3.8s-1.8 3.9-4.3 3.9h-2.2c-1.5 2.5-4.1 4.2-7.7 4.2C8.3 15.3 5 11.6 5 6.6zm17 3.3v.5c0 1.2-.1 2.3-.4 3.3h.8c1.2 0 2.1-.8 2.1-1.9s-.9-1.9-2.1-1.9zM8 3.6v1.6c1.3.8 3 1.2 5.5 1.2s4.2-.4 5.5-1.2V3.6z"/><path d="M1.2 16.6c-.6 0-1 .6-.7 1.2C1.6 19.9 5.6 21.4 13.5 21.4s11.9-1.5 13-3.6c.3-.6-.1-1.2-.7-1.2-1.6 0-3.4 1.4-12.3 1.4S2.8 16.6 1.2 16.6z"/></g></svg>',
  // cross.case.fill
  cross: '<svg viewBox="0 0 26 22" width="26" height="22"><path fill="currentColor" fill-rule="evenodd" d="M9 3.4C9 2 10 1 11.4 1h3.2C16 1 17 2 17 3.4V5h5.3C24 5 25 6 25 7.7v10.7c0 1.6-1 2.6-2.7 2.6H3.7C2 21 1 20 1 18.4V7.7C1 6 2 5 3.7 5H9zm1.9 0v1.6h4.2V3.4c0-.3-.2-.5-.5-.5h-3.2c-.3 0-.5.2-.5.5zM11.6 9v3h-3c-.5 0-.8.3-.8.8v1.4c0 .5.3.8.8.8h3v3c0 .5.3.8.8.8h1.4c.5 0 .8-.3.8-.8v-3h3c.5 0 .8-.3.8-.8v-1.4c0-.5-.3-.8-.8-.8h-3V9c0-.5-.3-.8-.8-.8h-1.4c-.5 0-.8.3-.8.8z"/></svg>',
  // play.circle.fill
  play: '<svg viewBox="0 0 20 20" width="20" height="20"><circle cx="10" cy="10" r="10" fill="currentColor"/><path d="M7.6 5.9v8.2c0 .5.5.8.9.5l6.3-4.1c.4-.3.4-.8 0-1L8.5 5.4c-.4-.3-.9 0-.9.5z" fill="#fff"/></svg>',
  // person.crop.circle.fill
  personCircle: '<svg viewBox="0 0 48 48" width="48" height="48"><defs><clipPath id="pc"><circle cx="24" cy="24" r="23"/></clipPath></defs><circle cx="24" cy="24" r="23" fill="currentColor"/><g clip-path="url(#pc)" fill="#fff"><circle cx="24" cy="18.5" r="8"/><path d="M8 41c2.6-6.6 8.6-10.4 16-10.4S37.4 34.4 40 41c-4 4.4-9.6 6.6-16 6.6S12 45.4 8 41z"/></g></svg>',
  chev: '<svg viewBox="0 0 8 13" width="8" height="13"><path d="M1.5 1.5l5 5-5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  // chevron.up.chevron.down (menu picker)
  updown: '<svg viewBox="0 0 9 15" width="9" height="15"><path d="M1.5 5.2L4.5 2l3 3.2M1.5 9.8l3 3.2 3-3.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  // arrow.clockwise
  refresh: '<svg viewBox="0 0 16 18" width="16" height="18"><g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13.6 10.4A5.8 5.8 0 1 1 8 4.4h2.6"/><path d="M8.6 1.6l2.8 2.8-2.8 2.8"/></g></svg>',
};

class NwPeople extends NwScreen {
  constructor() {
    super(`
      :host{background:#F2F2F7;--acc:#0A5CF5;--sec:rgba(60,60,67,.6);--ter:rgba(60,60,67,.3);--fillT:rgba(118,118,128,.12)}
      .s{background:#F2F2F7}
      /* nav: inline-large title (the app's pixel nav face) + the person.2 glass button */
      .lt{position:absolute;left:18px;top:58px;height:44px;display:flex;align-items:center;font-family:var(--pixel);font-size:34px;line-height:1;letter-spacing:0;z-index:6}
      .ppb{position:absolute;right:16px;top:62px;width:48px;height:44px;border-radius:22px;background:rgba(255,255,255,.9);box-shadow:0 6px 22px rgba(0,0,0,.07),0 1px 3px rgba(0,0,0,.04),inset 0 0 0 .5px rgba(255,255,255,.9);display:grid;place-items:center;color:var(--acc);z-index:6}
      .edge{position:absolute;left:0;right:0;top:0;height:134px;z-index:5;pointer-events:none;background:linear-gradient(#F2F2F7 80%,rgba(242,242,247,0));opacity:0;transition:opacity .4s}
      .edge.on{opacity:1}
      .pg{position:absolute;left:20px;right:20px;top:122px;display:flex;flex-direction:column;gap:28px;transition:transform .9s cubic-bezier(.45,0,.2,1)}
      .sec{display:flex;flex-direction:column;gap:8px}
      .sec.g12{gap:12px}
      .sh{font-size:20px;line-height:24px;font-weight:600;color:var(--sec);letter-spacing:-.3px}
      /* people row */
      .row{display:flex;gap:16px;padding:6px 0;margin-right:-20px;overflow:hidden}
      .pb{flex:0 0 68px;display:flex;flex-direction:column;align-items:center;gap:6px}
      .pb .cir{width:64px;height:64px;border-radius:50%;display:grid;place-items:center;background:rgba(10,92,245,.15);box-shadow:inset 0 0 0 1.5px rgba(10,92,245,.35);color:var(--acc);font-size:17px;font-weight:700;letter-spacing:0}
      .pb .nm{width:68px;text-align:center;font-size:12px;line-height:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .pb.add .cir{background:none;box-shadow:none;color:#8A8A8E;position:relative}
      .pb.add .cir svg.dc{position:absolute;inset:0}
      .pb.add .nm{color:var(--sec)}
      .pb.p{opacity:0;transform:scale(.6);transition:opacity .35s,transform .45s cubic-bezier(.3,1.3,.5,1)}
      .pb.p.in{opacity:1;transform:none}
      .pb.p.tap .cir{filter:brightness(.88)}
      /* the two doors */
      .doors{display:flex;gap:10px}
      .door{flex:1;min-height:72px;border-radius:18px;background:#fff;padding:14px;display:flex;gap:10px;align-items:flex-start}
      .door.pr{background:rgba(10,92,245,.12)}
      .door .ic{flex:0 0 auto;color:#8A8A8E;margin-top:-1px}
      .door.pr .ic{color:var(--acc)}
      .door b{display:block;font-size:15px;line-height:20px;font-weight:600;letter-spacing:-.2px}
      .door small{display:block;font-size:12px;line-height:16px;color:var(--sec);margin-top:2px;letter-spacing:0}
      /* your scenarios */
      .grid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:12px}
      .gc{background:#fff;border-radius:16px;padding:16px;display:flex;flex-direction:column;gap:10px;min-height:208px;transition:opacity .4s,transform .4s}
      .gc.new{opacity:0;transform:scale(.94)}
      .gc.new.in{opacity:1;transform:none}
      .gc .top{display:flex;justify-content:space-between;align-items:flex-start;color:var(--acc);height:25px}
      .gc .top .ini{font-size:20px;line-height:25px;font-weight:700}
      .gc .tx{display:flex;flex-direction:column;gap:3px}
      .gc .cat{font-size:11px;line-height:13px;font-weight:600;color:var(--sec);letter-spacing:.1px}
      .gc h6{margin:0;font-size:17px;line-height:22px;font-weight:600;letter-spacing:-.25px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
      .gc p{margin:0;font-size:12px;line-height:16px;color:var(--sec);letter-spacing:0;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
      .gc .ft{margin-top:auto;display:flex;gap:4px;font-size:11px;line-height:13px;color:var(--ter);white-space:nowrap;min-width:0;letter-spacing:.1px}
      .gc .ft span:first-child{overflow:hidden;text-overflow:ellipsis;min-width:0}
      /* a person's card — a sheet holding CounterpartDetailView (insetGrouped list) */
      .dim{position:absolute;inset:0;background:rgba(0,0,0,.2);opacity:0;transition:opacity .4s;z-index:20}
      .dim.on{opacity:1}
      .sheet{position:absolute;left:0;right:0;top:58px;bottom:0;border-radius:38px 38px 0 0;background:#F2F2F7;z-index:21;transform:translateY(105%);transition:transform .5s cubic-bezier(.32,.72,0,1);overflow:hidden}
      .sheet.on{transform:none}
      .sheet .g{position:absolute;top:16px;height:44px;min-width:44px;padding:0 15px;border-radius:22px;background:rgba(255,255,255,.92);box-shadow:0 6px 22px rgba(0,0,0,.07),0 1px 3px rgba(0,0,0,.04);display:flex;align-items:center;font-size:17px;color:var(--acc);letter-spacing:-.4px}
      .sheet .nt{position:absolute;left:0;right:0;top:16px;height:44px;display:flex;align-items:center;justify-content:center;font-family:var(--pixel);font-size:17px;letter-spacing:0}
      .sheet .ls{position:absolute;left:16px;right:16px;top:76px}
      .sheet .hd{display:flex;align-items:center;justify-content:space-between;font-size:17px;line-height:22px;font-weight:600;color:var(--sec);margin:20px 16px 8px;letter-spacing:-.4px}
      .sheet .hd .rf{color:var(--acc);display:flex}
      .sheet .card{background:#fff;border-radius:26px;overflow:hidden}
      .sheet .r{position:relative;padding:11px 16px;min-height:52px;display:flex;align-items:center;gap:8px;font-size:17px;line-height:22px;letter-spacing:-.4px}
      .sheet .r + .r::before{content:"";position:absolute;left:16px;right:0;top:0;border-top:.5px solid #DCDCDF}
      .sheet .r .col{flex:1;min-width:0;display:flex;flex-direction:column;gap:4px}
      .sheet .r .lab{font-size:12px;line-height:16px;color:var(--sec);letter-spacing:0}
      .sheet .r .ft{font-size:13px;line-height:18px;color:var(--sec);letter-spacing:-.1px}
      .sheet .r .val{margin-left:auto;display:flex;align-items:center;gap:5px;color:var(--acc)}
      .sheet .r .ch{color:#C4C4C7;display:flex}
      .sheet .r.tap{background:#E5E5EA}
      .sheet .who{gap:14px;padding:15px 16px}
      .sheet .who .pc{color:var(--acc);display:flex}
      .sheet .who b{display:block;font-size:22px;line-height:28px;font-weight:600;letter-spacing:-.3px}
      .sheet .who .rel{font-size:13px;line-height:18px;color:var(--sec);letter-spacing:-.1px}
      .sheet .who .vo{font-size:12px;line-height:16px;color:var(--ter);letter-spacing:0}
      .sheet .fo{font-size:13px;line-height:18px;color:var(--sec);margin:7px 16px 0;letter-spacing:-.1px}
    `, `
      <div class="pg">
        <div class="sec"><div class="sh" data-k="people"></div><div class="row"></div></div>
        <div class="sec g12"><div class="sh" data-k="new"></div>
          <div class="doors"><div class="door pr"><span class="ic">${SY.pencil}</span><span><b class="d1"></b><small class="d1s"></small></span></div>
            <div class="door"><span class="ic">${SY.grid}</span><span><b class="d2"></b><small class="d2s"></small></span></div></div></div>
        <div class="sec g12"><div class="sh" data-k="mine"></div><div class="grid"></div></div>
      </div>
      <div class="edge"></div>
      <div class="lt"></div><div class="ppb">${SY.people}</div>
      <div class="dim"></div>
      <div class="sheet"></div>`);
  }

  get ko() { return this.t === STR.ko; }

  build() {
    const ko = this.ko;
    this.$(".lt").textContent = ko ? "상황연습" : "Watch";
    const K = ko ? { people: "사람", new: "새 상황", mine: "내 상황" } : { people: "People", new: "New situation", mine: "Your scenarios" };
    this.$$(".sh").forEach(s => s.textContent = K[s.dataset.k]);
    this.$(".d1").textContent = ko ? "내 상황 만들기" : "Your own situation";
    this.$(".d1s").textContent = ko ? "한 줄, 그리고 내 자료" : "One line, plus your material";
    this.$(".d2").textContent = ko ? "흔한 상황" : "Common situations";
    this.$(".d2s").textContent = ko ? "카테고리에서 고르기" : "Pick from categories";

    // people the learner made (initials on the tinted circle — PersonBubble without a photo)
    this._P = ["Sarah", "Mark", "Lena", "Jun"];
    this.$(".row").innerHTML = `<div class="pb add"><div class="cir"><svg class="dc" viewBox="0 0 64 64" width="64" height="64"><circle cx="32" cy="32" r="31.25" fill="none" stroke="#D1D1D6" stroke-width="1.5" stroke-dasharray="5 5"/></svg>${SY.plus}</div><div class="nm">${ko ? "만들기" : "Create"}</div></div>`
      + this._P.map(n => `<div class="pb p"><div class="cir">${n[0]}</div><div class="nm">${esc(n)}</div></div>`).join("");

    // "Your scenarios" — the capture's four cards, plus one made with Mark (shown at beat 3)
    const w = x => (ko ? `상대: ${x}` : `with ${x}`);
    const G = [
      ["brief", "Work", "Job interview · panel round", "A panel interview: introducing myself, walking through my experience, and answering questions about the role.", w("Interviewer"), ""],
      ["cup", "Cafe", "Café · catching up", "At the café with Sarah: catching up after months apart — she asks what I've been up to.", w("Sarah (close friend)"), ko ? "5시간 전" : "5 hours ago"],
      ["cross", "Health", "Doctor's visit", "At the doctor's office: describing a symptom I've had for a week and asking what the options are.", w("Doctor"), ko ? "그저께" : "2 days ago"],
      ["cross", "Health", "Pharmacy · picking up a prescription", "At the pharmacy: picking up a prescription, and the pharmacist has questions about other medication.", w("Pharmacist"), ko ? "지난주" : "last week"],
    ];
    const card = ([ic, cat, h, p, who, when], cls = "") => `<div class="gc ${cls}"><div class="top">${ic.length === 1 ? `<span class="ini">${ic}</span>` : SY[ic]}${SY.play}</div>
      <div class="tx">${cat ? `<div class="cat">${esc(cat)}</div>` : ""}<h6>${esc(h)}</h6><p>${esc(p)}</p></div>
      <div class="ft"><span>${esc(who)}</span>${when ? `<span>·</span><span>${esc(when)}</span>` : ""}</div></div>`;
    this._markCard = card(["M", "", "Asking for a raise", "Asking Mark for a raise in our next one-on-one, with the numbers ready.", w("Mark"), ko ? "지금" : "now"], "new");
    this.$(".grid").innerHTML = G.map(g => card(g)).join("");

    this._sheet();
    this.reset();
  }

  /* CounterpartDetailView for Mark, as the sheet the row opens. */
  _sheet() {
    const ko = this.ko;
    const ideas = [
      ["Asking for a raise", "Bring the numbers to your next one-on-one and ask for a raise."],
      ["Pushing back on a deadline", "The launch date is unrealistic — tell him, and offer a plan."],
      ["Feedback on a design", "He asks for your honest take on a teammate's work."],
    ];
    this.$(".sheet").innerHTML = `
      <div class="g" style="left:16px">${ko ? "완료" : "Done"}</div><div class="nt">Mark</div><div class="g" style="right:16px">${ko ? "편집" : "Edit"}</div>
      <div class="ls">
        <div class="card"><div class="r who"><span class="pc">${SY.personCircle}</span><div><b>Mark</b><div class="rel">${ko ? "팀장" : "Manager"}</div><div class="vo">${ko ? "목소리: Paige" : "voiced by Paige"}</div></div></div></div>
        <div class="hd">${ko ? "서로의 말투" : "How you two talk"}</div>
        <div class="card">
          <div class="r"><span>${ko ? "내 말투" : "You talk to them"}</span><span class="val">${ko ? "예의 있게" : "Polite"}${SY.updown}</span></div>
          <div class="r"><span>${ko ? "상대의 말투" : "They talk to you"}</span><span class="val">${ko ? "편하게" : "Casual"}${SY.updown}</span></div>
        </div>
        <div class="hd">${ko ? "메모" : "Notes"}</div>
        <div class="card"><div class="r"><span>${ko ? "숫자에 엄격하고, 결론부터 듣고 싶어 함. 회의는 늘 15분 안에 끝냄." : "Big on numbers, wants the bottom line first. Keeps every meeting under 15 minutes."}</span></div></div>
        <div class="hd"><span>${ko ? "상황 아이디어" : "Situation ideas"}</span><span class="rf">${SY.refresh}</span></div>
        <div class="card">${ideas.map(([t, b]) => `<div class="r idea"><div class="col"><span>${esc(t)}</span><span class="ft">${esc(b)}</span></div><span class="ch">${SY.chev}</span></div>`).join("")}</div>
        <div class="fo">${ko ? "하나를 누르면 그 상황으로 바로 만들 수 있어요." : "Tap one to make it a situation with Mark."}</div>
      </div>`;
  }

  reset() {
    this.$$(".pb.p").forEach(e => e.classList.remove("in", "tap"));
    this.$(".grid .gc.new")?.remove();
    this.$(".dim").classList.remove("on"); this.$(".sheet").classList.remove("on");
    this.$$(".sheet .r").forEach(r => r.classList.remove("tap"));
    this.$(".pg").style.transform = "none"; this.$(".edge").classList.remove("on");
  }

  static poses = ["watchtab", "row", "card", "scenarios"];
  async pose(name) {
    this.stop(); this.reset();
    if (name === "watchtab") return;
    this.$$(".pb.p").forEach(e => e.classList.add("in"));
    if (name === "card") { this.$(".dim").classList.add("on"); this.$(".sheet").classList.add("on"); }
    if (name === "scenarios") this._showMark(true);
  }

  _showMark(now) {
    const g = this.$(".grid"); g.insertAdjacentHTML("afterbegin", this._markCard);
    const c = g.firstElementChild; if (now) c.classList.add("in"); else { void c.offsetWidth; c.classList.add("in"); }
    this.$(".pg").style.transform = "translateY(-300px)"; this.$(".edge").classList.add("on");
  }

  async demo() {
    await this.sleep(700); this.beat(1);
    for (const p of this.$$(".pb.p")) { p.classList.add("in"); await this.sleep(300); }
    await this.sleep(700);
    const mark = this.$$(".pb.p")[1];
    mark.classList.add("tap"); await this.sleep(220); mark.classList.remove("tap");
    this.beat(2); this.$(".dim").classList.add("on"); this.$(".sheet").classList.add("on");
    await this.sleep(2600);
    const idea = this.$(".sheet .r.idea"); idea.classList.add("tap"); await this.sleep(350); idea.classList.remove("tap");
    await this.sleep(400);
    this.$(".dim").classList.remove("on"); this.$(".sheet").classList.remove("on"); await this.sleep(600);
    this.beat(3); this.$(".pg").style.transform = "translateY(-300px)"; this.$(".edge").classList.add("on");
    await this.sleep(950);
    const g = this.$(".grid"); g.insertAdjacentHTML("afterbegin", this._markCard);
    const c = g.firstElementChild; void c.offsetWidth; c.classList.add("in");
    await this.sleep(2800);
  }
}

export { NwPeople };
