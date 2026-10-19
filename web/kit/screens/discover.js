/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc } from "../core.js";

/* ═══════════════════════════ <nw-discover> — Talk settings ═══════════════════════════
 * DiscoverSettingsSheet.swift: the one settings page behind Talk's sliders button. "Why are you
 * learning?" (PurposePickerRows: eight rows, numbered in the order tapped, max three, an accordion
 * field under a picked purpose that has more to say), then Interests (ChipFlow: picked first with ×,
 * then the presets; a text field + plus.circle.fill), Cancel / "Talk settings" / Save.
 * Laid out in points from marketing/captures/discover-settings-job(-scrolled)(-en).png (iPhone 17).
 *
 *   d.purposes = ["job","travel"]   keys: start hobby exam study job work abroad travel
 *                                   (aliases: interview / "job interview" → job, fun → hobby, career → job)
 *   d.role = "backend developer"    the job row's field (details.target); d.details = {target, job, role, school, subject}
 *   d.exam = "IELTS"                the exam row's picker value
 *   d.interests = ["technology","the job market"]   presets by their English key (shown translated), typed ones verbatim
 *   await d.togglePurpose("job")    tap: number badge, the accordion opens/closes
 *   await d.typeRole("backend developer")      types into the open field (opens the purpose first if needed)
 *   await d.addInterest("the job market")      scrolls to the field, types, taps +, the chip lands
 *   await d.toggleInterest("AI / tech")        tap a preset (adds) or a picked chip (removes)
 *   await d.save()                  Save pressed; in sheet mode the sheet goes down
 *   d.scrollTo(y) / await d.scrollToInterests()
 * Sheet presentation (over <nw-home> in the same <nw-phone>):
 *   <nw-discover sheet over="prev">   transparent until presented; over = "prev" (previous sibling) or a selector,
 *                                     the presenting screen recedes while the sheet is up
 *   await d.present(); await d.dismiss(); await d.openFrom(home)   (home.tapTool("sliders"), then present)
 * Beats in demo(): 1 purpose picked · 2 role typed · 3 interest added · 4 saved. */

const PURPOSES = ["start", "hobby", "exam", "study", "job", "work", "abroad", "travel"];
const ALIAS = { interview: "job", "job interview": "job", "job hunt": "job", career: "job", fun: "hobby", exams: "exam", studies: "study", school: "study", life: "abroad", speaking: "start" };
const key = k => { k = String(k).toLowerCase().trim(); return PURPOSES.includes(k) ? k : ALIAS[k] || k; };
const TINT = { start: "#0088FF", hobby: "#FF2D55", exam: "#FF8D28", study: "#00C3D0", job: "#CB30E0", work: "#AC7F5E", abroad: "#34C759", travel: "#00C0E8" };

/* SF Symbols, traced white on the 30pt tile (30-unit boxes). `var(--t)` is the tile colour (knock-outs). */
const GLYPH = {
  start: '<path fill="#fff" d="M7.6 6.4h9.6a3 3 0 0 1 3 3v5.2a3 3 0 0 1-3 3h-6.4l-3 2.6c-.4.3-.9 0-.9-.4v-2.3a3 3 0 0 1-2.3-2.9V9.4a3 3 0 0 1 3-3z"/><path fill="#fff" stroke="var(--t)" stroke-width="1.3" d="M13.4 10.8h8.4a3 3 0 0 1 3 3v4.6a3 3 0 0 1-2.3 2.9v2.1c0 .4-.5.7-.9.4l-2.8-2.4h-5.4a3 3 0 0 1-3-3v-4.6a3 3 0 0 1 3-3z"/>',
  hobby: '<path fill="#fff" d="M15 23.2s-8.3-4.9-8.3-10.6c0-2.7 2-4.6 4.4-4.6 1.7 0 3.1.9 3.9 2.3.8-1.4 2.2-2.3 3.9-2.3 2.4 0 4.4 1.9 4.4 4.6 0 5.7-8.3 10.6-8.3 10.6z"/>',
  exam: '<g fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="10.4" cy="10.6" r="2.8"/><path d="M9 10.6l1 1 1.7-2"/><circle cx="10.4" cy="19.4" r="2.8"/><path d="M15.6 10.6h7.4M15.6 19.4h7.4"/></g>',
  study: '<path fill="#fff" d="M15 6.8l10 4.2-10 4.3-10-4.3z"/><path fill="#fff" d="M9 14.4l6 2.6 6-2.6v4.2c0 1.7-2.7 3.1-6 3.1s-6-1.4-6-3.1z"/><path fill="none" stroke="#fff" stroke-width="1.1" d="M15 11l-6.6 1.9v6"/><rect fill="#fff" x="7.4" y="18.4" width="2" height="4" rx="1"/>',
  job: '<rect fill="#fff" x="6" y="8.8" width="18" height="12.6" rx="2.2"/><g fill="var(--t)"><circle cx="11.2" cy="13.2" r="1.9"/><path d="M7.9 18.6c.3-1.8 1.6-2.8 3.3-2.8s3 1 3.3 2.8z"/><rect x="16" y="11.9" width="5.4" height="1.3" rx=".65"/><rect x="16" y="14.5" width="5.4" height="1.3" rx=".65"/><rect x="16" y="17.1" width="5.4" height="1.3" rx=".65"/></g>',
  work: '<path fill="none" stroke="#fff" stroke-width="1.6" d="M12 10V8.4c0-.6.4-1 1-1h4c.6 0 1 .4 1 1V10"/><path fill="#fff" d="M8.2 10.2h13.6a2.4 2.4 0 0 1 2.4 2.4v2.9H5.8v-2.9a2.4 2.4 0 0 1 2.4-2.4zM5.8 16.6h7.6v.4c0 .5.4.9.9.9h1.4c.5 0 .9-.4.9-.9v-.4h7.6v3.4a2.4 2.4 0 0 1-2.4 2.4H8.2A2.4 2.4 0 0 1 5.8 20z"/>',
  abroad: '<path fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M5.6 15.2L15 7.2l9.4 8"/><path fill="#fff" d="M20.2 8.2h1.8v4.2l-1.8-1.5zM8.6 15.4L15 10l6.4 5.4v6.2c0 .7-.5 1.2-1.2 1.2H9.8c-.7 0-1.2-.5-1.2-1.2z"/><rect fill="var(--t)" x="13.4" y="17.6" width="3.2" height="5.2"/>',
  travel: '<path fill="#fff" d="M23.6 13.6c.9 0 1.6.6 1.6 1.4s-.7 1.4-1.6 1.4h-4.4l-4 6.2c-.2.3-.5.4-.8.4h-1.1c-.3 0-.5-.3-.4-.6l1.8-6h-4l-1.4 1.8c-.1.2-.3.3-.6.3H7.6c-.3 0-.5-.3-.4-.6l.9-3-.9-3c-.1-.3.1-.6.4-.6h1.1c.3 0 .5.1.6.3l1.4 1.8h4l-1.8-6c-.1-.3.1-.6.4-.6h1.1c.3 0 .6.1.8.4l4 6.2z"/>',
};
const PRESETS = ["AI / tech", "parenting", "language learning", "music", "podcasts", "cooking", "travel", "sports", "fashion", "finance", "science", "art"];

const L = {
  ko: { title: "대화 설정", cancel: "취소", save: "저장", why: "왜 배워요?", interests: "관심사",
    whyFoot: "세 개까지 골라요. 대화 탭의 칩이 고른 순서대로 놓이고, 아래에 적은 내용으로 그 칩의 주제를 만들어요.",
    intFoot: "뉴스 칩에서 관심사마다 이번 주 기사를 가져와요.", draft: "회사, 팀, 사람… 뭐든 적어 보세요",
    p: { start: ["말문을 트고 싶어요", "아직 말이 잘 안 나와요"], hobby: ["취미로", "좋아하는 걸 마음껏 이야기"], exam: ["시험 준비", "IELTS, OPIc, TOEIC Speaking…"],
      study: ["대학·공부", "수업 토론, 발표, 내 전공 이야기"], job: ["취업·이직 준비", "면접, 지원하는 업계 이야기"], work: ["일에서 써야 해요", "회의, 발표, 고객 통화"],
      abroad: ["해외에서 살아요", "집주인, 관공서, 병원, 아이 학교"], travel: ["여행 가요", "공항, 호텔, 식당"] },
    which: "어느 시험이에요?", school: "학교 이름", subject: "전공 — 예: 기계공학",
    target: "지원하는 직무 — 예: 백엔드 개발자", job: "하는 일 — 예: 프로덕트 매니저", role: "그 일에서 맡은 것 — 예: 모바일 팀을 이끌어요",
    preset: { "AI / tech": "AI · 기술", parenting: "육아", "language learning": "외국어 공부", music: "음악", podcasts: "팟캐스트", cooking: "요리", travel: "여행",
      sports: "스포츠", fashion: "패션", finance: "재테크", science: "과학", art: "예술" } },
  en: { title: "Talk settings", cancel: "Cancel", save: "Save", why: "Why are you learning?", interests: "Interests",
    whyFoot: "Up to three. The chips under Talk follow them in the order you picked, and what you write under one shapes its topics.",
    intFoot: "The News chip brings this week's stories for each one.", draft: "A company, a team, a person — anything",
    p: { start: ["I want to start speaking", "Words don't come out yet"], hobby: ["For fun", "Talk about what I like"], exam: ["For an exam", "IELTS, OPIc, TOEIC Speaking…"],
      study: ["For my studies", "Seminars, presentations, my subject"], job: ["For a job hunt", "Interviews, the field I'm applying to"], work: ["I need it at work", "Meetings, presentations, client calls"],
      abroad: ["I live abroad", "Landlord, town hall, doctor, my kid's school"], travel: ["For travel", "Airport, hotel, restaurants"] },
    which: "Which exam?", school: "School or university", subject: "Subject — e.g. mechanical engineering",
    target: "Role you're applying for — e.g. backend developer", job: "Your job — e.g. product manager", role: "What you do in it — e.g. I run the mobile team",
    preset: {} },
};
/* the accordion under a picked purpose: [field key | "exam"] */
const DETAIL = { exam: ["exam"], study: ["school", "subject"], job: ["target"], work: ["job", "role"] };

const XMARK = '<svg class="xm" viewBox="0 0 10 10"><path d="M1.4 1.4l7.2 7.2M8.6 1.4L1.4 8.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';
const PLUS = '<svg class="pl" viewBox="0 0 20 20"><circle cx="10" cy="10" r="9.6" fill="currentColor"/><path d="M10 5.6v8.8M5.6 10h8.8" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg>';
const CHEV = '<svg class="ud" viewBox="0 0 10 16"><path d="M2 6l3-3 3 3M2 10l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';

/* page geometry (points, scroll 0) — from the capture */
const TOP = 125, ROW = 66.7, FIELD = 51.3, SHEET_TOP = 64, SHEET_SHIFT = 46;

class NwDiscover extends NwScreen {
  static poses = ["top", "scrolled", "default", "sheet"];
  constructor() {
    super(`
      :host{background:#F2F2F7}
      :host([sheet]){background:transparent}
      .dim{position:absolute;inset:0;background:#000;opacity:0;transition:opacity .4s ease;pointer-events:none}
      .sheet{position:absolute;left:0;right:0;top:0;bottom:0;background:#F2F2F7;overflow:hidden}
      :host([sheet]) .sheet{top:${SHEET_TOP}px;border-radius:38px 38px 0 0;transform:translateY(105%);transition:transform .5s cubic-bezier(.32,.72,0,1);box-shadow:0 -1px 0 rgba(0,0,0,.04)}
      :host([sheet]) .sheet.on{transform:none}
      :host([sheet]) .frame{transform:translateY(-${SHEET_SHIFT}px)}
      :host([sheet]) .grab{display:block}
      .grab{display:none;position:absolute;left:50%;top:5px;width:36px;height:5px;margin-left:-18px;border-radius:3px;background:rgba(60,60,67,.3);z-index:8}
      .frame{position:absolute;left:0;right:0;top:0;height:874px}
      .sc{position:absolute;left:0;right:0;top:0;transition:transform .7s cubic-bezier(.45,0,.2,1)}
      .ct{padding-top:${TOP}px;padding-bottom:60px}
      /* nav — iOS 26 glass, pixel title */
      .nav{position:absolute;left:0;right:0;top:62px;height:44px;z-index:6}
      .gl{position:absolute;top:0;height:44px;border-radius:22px;background:#FBFBFE;padding:0 16.5px;display:flex;align-items:center;
        box-shadow:inset 0 0 0 1px rgba(255,255,255,.95),0 0 0 .5px rgba(0,0,0,.035),0 4px 16px rgba(0,0,0,.065);font-size:17px;color:#0A5CF5;letter-spacing:-.4px;transition:background .15s}
      .gl.cn{left:16px} .gl.sv{right:16px;font-weight:600}
      .gl.pr{background:#E4E4EA}
      .ttl{position:absolute;left:100px;right:100px;top:0;line-height:44px;text-align:center;font-family:var(--pixel);font-size:17px;letter-spacing:0}
      .edge{position:absolute;left:0;right:0;top:0;height:136px;z-index:5;pointer-events:none;opacity:0;transition:opacity .3s;
        backdrop-filter:blur(7px);-webkit-backdrop-filter:blur(7px);
        -webkit-mask-image:linear-gradient(#000 0,#000 45%,transparent 100%);mask-image:linear-gradient(#000 0,#000 45%,transparent 100%);
        background:linear-gradient(rgba(242,242,247,.92),rgba(242,242,247,.8) 50%,rgba(242,242,247,0))}
      .edge.on{opacity:1}
      /* sections */
      .hd{margin:0 34px 0 32px;height:22px;line-height:22px;font-size:17px;font-weight:600;color:rgba(60,60,67,.6);display:flex;justify-content:space-between;letter-spacing:-.4px}
      .hd b{font-weight:600;font-variant-numeric:tabular-nums}
      .card{margin:9.3px 16px 0;background:#fff;border-radius:26px;overflow:hidden}
      .ft{margin:6.8px 32px 0;word-break:keep-all;font-size:13px;line-height:15.7px;color:rgba(60,60,67,.6);letter-spacing:-.2px}
      .ft+.hd{margin-top:17px}
      /* purpose rows */
      .pr0{position:relative;height:${ROW}px;display:flex;align-items:center;gap:12px;padding:0 16px;transition:opacity .2s,background .2s}
      .pr0.off{opacity:.4}
      .pr0.tap{background:#E5E5EA}
      .sep::before{content:"";position:absolute;left:58px;right:16px;top:0;height:1px;background:#E8E8E8}
      .card>:first-child.sep::before{display:none}
      .tile{width:30px;height:30px;border-radius:7px;flex:0 0 auto;display:grid;place-items:center}
      .tile svg{width:30px;height:30px;display:block}
      .tx{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px;padding-top:1px}
      .tx b{font-weight:400;font-size:17px;line-height:21px;letter-spacing:-.4px;white-space:nowrap}
      .tx small{font-size:12px;line-height:15px;color:rgba(60,60,67,.6);letter-spacing:-.1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .rad{position:relative;width:24px;height:24px;flex:0 0 auto;border-radius:50%;box-shadow:inset 0 0 0 1.5px #C5C5C7;display:grid;place-items:center;transition:background .2s,box-shadow .2s}
      .rad i{font-style:normal;font-size:13px;font-weight:700;color:#fff;opacity:0;transition:opacity .2s}
      .rad.on{background:#0A5CF5;box-shadow:none}
      .rad.on i{opacity:1}
      /* accordion field rows */
      .fd{position:relative;height:0;overflow:hidden;transition:height .2s ease-out}
      .fd.open{height:${FIELD}px}
      .fd .in{position:absolute;left:58px;right:16px;top:0;height:${FIELD}px;display:flex;align-items:center;font-size:15px;letter-spacing:-.25px;white-space:nowrap;overflow:hidden}
      .fd .ph{color:rgba(60,60,67,.3)}
      .fd .pk{justify-content:space-between;font-size:17px;letter-spacing:-.4px}
      .fd .pk span{display:flex;align-items:center;gap:6px;color:rgba(60,60,67,.6)}
      .ud{width:9px;height:14px}
      .caret{display:inline-block;width:2px;height:20px;margin-left:1px;background:#0A5CF5;border-radius:1px;vertical-align:middle;animation:blink 1s steps(1) infinite}
      @keyframes blink{50%{opacity:0}}
      /* interests */
      .chips{display:flex;flex-wrap:wrap;gap:8px;padding:19px 16px 18px}
      .chip{height:32px;padding:0 12px;border-radius:16px;display:flex;align-items:center;gap:4px;font-size:15px;letter-spacing:.1px;white-space:nowrap;background:rgba(118,118,128,.12);color:#000;transition:background .2s,color .2s,transform .2s}
      .chip.on{background:#0A5CF5;color:#fff}
      .chip.dis{color:rgba(60,60,67,.6)}
      .chip.tap{transform:scale(.94)}
      .chip.new{animation:pop .3s ease-out}
      @keyframes pop{from{transform:scale(.6);opacity:0}}
      .xm{width:10px;height:10px;margin-left:1px}
      .add{position:relative;height:52px;display:flex;align-items:center;padding:0 16px 0 32px;font-size:17px;letter-spacing:-.4px}
      .add::before{content:"";position:absolute;left:28px;right:16px;top:0;height:1px;background:#E8E8E8}
      .add .tf{flex:1;min-width:0;white-space:nowrap;overflow:hidden;margin-left:-16px}
      .add .tf.ph{color:rgba(60,60,67,.3)}
      .pl{width:20px;height:20px;color:rgba(60,60,67,.3);transition:color .2s,transform .15s}
      .add.live .pl{color:#0A5CF5}
      .pl.tap{transform:scale(.85)}
    `, `
      <div class="dim"></div>
      <div class="sheet"><div class="grab"></div><div class="frame">
        <div class="sc"><div class="ct">
          <div class="hd"><span class="h1"></span></div>
          <div class="card pc"></div>
          <p class="ft f1"></p>
          <div class="hd"><span class="h2"></span><b class="cnt"></b></div>
          <div class="card ic"><div class="chips"></div><div class="add"><span class="tf ph"></span>${PLUS}</div></div>
          <p class="ft f2"></p>
        </div></div>
        <div class="edge"></div>
        <div class="nav"><span class="gl cn"></span><span class="ttl"></span><span class="gl sv"></span></div>
      </div></div>`);
    this._purposes = []; this._details = {}; this._exam = "IELTS"; this._interests = []; this._y = 0;
  }
  get L() { return this.t === STR.ko ? L.ko : L.en; }
  build() {
    const l = this.L;
    this.$(".cn").textContent = l.cancel; this.$(".sv").textContent = l.save; this.$(".ttl").textContent = l.title;
    this.$(".h1").textContent = l.why; this.$(".h2").textContent = l.interests; this.$(".f1").textContent = l.whyFoot; this.$(".f2").textContent = l.intFoot;
    this.$(".pc").innerHTML = PURPOSES.map(p => `
      <div class="pr0 sep" data-p="${p}"><span class="tile" style="background:${TINT[p]};--t:${TINT[p]}"><svg viewBox="0 0 30 30">${GLYPH[p]}</svg></span>
        <span class="tx"><b>${esc(l.p[p][0])}</b><small>${esc(l.p[p][1])}</small></span><span class="rad"><i></i></span></div>
      ${(DETAIL[p] || []).map(f => `<div class="fd sep" data-p="${p}" data-f="${f}"><span class="in${f === "exam" ? " pk" : ""}"></span></div>`).join("")}`).join("");
    this.reset();
  }
  reset() {
    this._purposes = [...(this._initial?.purposes ?? [])]; this._details = { ...(this._initial?.details || {}) }; this._interests = [...(this._initial?.interests ?? ["technology"])];
    this._typing = null; this._draft = "";
    this._render(); this.scrollTo(0);
    if (this.hasAttribute("sheet")) this._presented(false);
  }
  /* the state demo() starts from: whatever the page set before the first loop */
  _remember() { this._initial = { purposes: [...this._purposes], details: { ...this._details }, interests: [...this._interests] }; }

  /* ── state ── */
  set purposes(v) { this._purposes = [...new Set((v || []).map(key))].filter(p => PURPOSES.includes(p)).slice(0, 3); this._remember(); this._render(); }
  get purposes() { return [...this._purposes]; }
  set role(v) { this._details.target = v || ""; this._remember(); this._render(); }
  get role() { return this._details.target || ""; }
  set details(v) { this._details = { ...(v || {}) }; this._remember(); this._render(); }
  set exam(v) { this._exam = v; this._render(); }
  set interests(v) { this._interests = [...(v || [])].slice(0, 6); this._remember(); this._render(); }
  get interests() { return [...this._interests]; }

  _label(tag) { return this.L.preset[tag] || tag; }
  _render() {
    if (!this._built) return;
    const l = this.L, picked = this._purposes, full = picked.length >= 3;
    this.$$(".pr0").forEach(r => {
      const p = r.dataset.p, n = picked.indexOf(p);
      r.querySelector(".rad").classList.toggle("on", n >= 0); r.querySelector(".rad i").textContent = n >= 0 ? n + 1 : "";
      r.classList.toggle("off", n < 0 && full);
    });
    this.$$(".fd").forEach(f => {
      const on = picked.includes(f.dataset.p), k = f.dataset.f, in_ = f.querySelector(".in");
      f.classList.toggle("open", on);
      if (k === "exam") { in_.innerHTML = `${esc(l.which)}<span>${esc(this._exam)}${CHEV}</span>`; return; }
      const v = this._details[k] || "", typing = this._typing === k;
      in_.innerHTML = v ? `${esc(v)}${typing ? '<i class="caret"></i>' : ""}` : `${typing ? '<i class="caret" style="margin:0 1px 0 0"></i>' : ""}<span class="ph">${esc(l[k])}</span>`;
    });
    const can = this._interests.length < 6;
    this.$(".chips").innerHTML = this._interests.map(t => `<span class="chip on" data-t="${esc(t)}">${esc(this._label(t))}${XMARK}</span>`).join("")
      + PRESETS.filter(t => !this._interests.includes(t)).map(t => `<span class="chip${can ? "" : " dis"}" data-t="${esc(t)}">${esc(this._label(t))}</span>`).join("");
    this.$(".cnt").textContent = `${this._interests.length} / 6`;
    const tf = this.$(".tf"), d = this._draft;
    tf.classList.toggle("ph", !d);
    tf.innerHTML = d ? `${esc(d)}${this._typing === "draft" ? '<i class="caret"></i>' : ""}` : `${this._typing === "draft" ? '<i class="caret" style="margin:0 1px 0 0"></i>' : ""}${esc(l.draft)}`;
    this.$(".add").classList.toggle("live", !!d.trim() && can);
  }

  /* ── scrolling ── */
  /* the Form's end: the interests card's bottom stops at 810pt (its footer and the home indicator below) */
  _maxScroll() { const c = this.$(".ic"); return Math.max(0, c.offsetTop + c.offsetHeight - 810 + (this.hasAttribute("sheet") ? SHEET_TOP - SHEET_SHIFT : 0)); }
  scrollTo(y) {
    y = Math.max(0, Math.min(y, this._maxScroll())); this._y = y;
    this.$(".sc").style.transform = y ? `translateY(${-y}px)` : "none";
    this.$(".edge").classList.toggle("on", y > 8);
    return y;
  }
  /** The interests card centred, as the app scrolls to it (proxy.scrollTo("interestGrid", .center)). */
  async scrollToInterests() { this.scrollTo(1e4); await this.sleep(750); }   // centring it lands on the Form's end

  /* ── scripted taps ── */
  async _press(el, ms = 200) { if (!el) return; el.classList.add("tap"); await this.sleep(ms); el.classList.remove("tap"); }
  async togglePurpose(p) {
    p = key(p); const r = this.$(`.pr0[data-p="${p}"]`); if (!r) return;
    const n = this._purposes.indexOf(p);
    if (n < 0 && this._purposes.length >= 3) return;
    await this._press(r, 180);
    if (n >= 0) this._purposes.splice(n, 1); else this._purposes.push(p);
    this._render(); await this.sleep(260);
  }
  /** Types into a purpose's field (default: the job row's role). Opens the purpose first. */
  async typeRole(text, field = "target", per = 70) {
    const p = Object.keys(DETAIL).find(k => DETAIL[k].includes(field)); if (!p) return;
    if (!this._purposes.includes(p)) await this.togglePurpose(p);
    this._typing = field; this._details[field] = ""; this._render(); await this.sleep(400);
    for (const ch of text) { this._details[field] += ch; this._render(); await this.sleep(per); }
    await this.sleep(300); this._typing = null; this._render();
  }
  async toggleInterest(tag) {
    const c = this.$$(".chip").find(e => e.dataset.t === tag);
    const on = this._interests.includes(tag);
    if (!on && this._interests.length >= 6) return;
    await this._press(c, 160);
    if (on) this._interests = this._interests.filter(t => t !== tag); else this._interests.push(tag);
    this._render(); this.$$(".chip").find(e => e.dataset.t === tag)?.classList.add("new"); await this.sleep(250);
  }
  /** Scrolls to the interests, types into the field, taps +: the chip joins the picked ones. */
  async addInterest(text, per = 70) {
    if (this._y < 100) await this.scrollToInterests();
    this._typing = "draft"; this._draft = ""; this._render(); await this.sleep(400);
    for (const ch of text) { this._draft += ch; this._render(); await this.sleep(per); }
    await this.sleep(350); const pl = this.$(".pl"); pl.classList.add("tap"); await this.sleep(150); pl.classList.remove("tap");
    if (this._interests.length < 6 && !this._interests.some(t => t.toLowerCase() === text.toLowerCase())) this._interests.push(text);
    this._draft = ""; this._typing = null; this._render();
    this.$$(".chip").find(e => e.dataset.t === text)?.classList.add("new"); await this.sleep(350);
  }
  async save() {
    const b = this.$(".sv"); b.classList.add("pr"); await this.sleep(200); b.classList.remove("pr");
    if (this.hasAttribute("sheet")) await this.dismiss(); else await this.sleep(200);
  }

  /* ── sheet presentation ── */
  _over() {
    const o = this.getAttribute("over"); if (!o) return null;
    return o === "prev" ? this.previousElementSibling : (this.getRootNode().querySelector?.(o) || document.querySelector(o));
  }
  _presented(on) {
    this.$(".sheet").classList.toggle("on", on); this.$(".dim").style.opacity = on ? .18 : 0;
    this.style.pointerEvents = on ? "" : "none";
    const o = this._over();
    if (o) {
      o.style.transition = "transform .5s cubic-bezier(.32,.72,0,1),border-radius .5s,filter .5s";
      o.style.transformOrigin = "50% 0"; o.style.transform = on ? "translateY(calc(var(--k,1) * 52px)) scale(.92)" : "";
      o.style.borderRadius = on ? "calc(var(--k,1) * 38px)" : ""; o.style.overflow = "hidden";
      // the window behind a receded screen is black (box-shadow fills around the scaled card)
      o.style.boxShadow = on ? "0 0 0 200px #000" : "";
    }
    // …so the status bar goes white while the sheet is up
    const ph = this.closest("nw-phone");
    if (ph && o) { if (on) { if (this._phDark == null) this._phDark = ph.hasAttribute("dark"); ph.setAttribute("dark", ""); }
      else if (this._phDark != null) { if (!this._phDark) ph.removeAttribute("dark"); this._phDark = null; } }
  }
  async present() { this._presented(true); await this.sleep(600); }
  async dismiss() { this._presented(false); await this.sleep(550); }
  /** Talk's sliders button, then this sheet comes up. */
  async openFrom(home) { if (home?.tapTool) await home.tapTool("sliders"); await this.present(); }

  async pose(name) {
    this.stop();
    this._typing = null; this._draft = "";
    if (name === "default") { this._purposes = ["travel"]; this._details = {}; this._interests = ["AI / tech", "parenting"]; }
    else { this._purposes = ["job", "travel"]; this._details = { target: "backend developer" }; this._interests = ["technology", "the job market"]; }
    this._render();
    if (this.hasAttribute("sheet") || name === "sheet") { this.setAttribute("sheet", ""); this._presented(true); }
    this.scrollTo(name === "scrolled" ? 1e4 : 0);
  }
  async demo() {
    if (this.hasAttribute("sheet")) { await this.sleep(700); await this.present(); }
    await this.sleep(900);
    this.beat(1); await this.togglePurpose("job"); await this.sleep(500);
    this.beat(2); await this.typeRole(this.getAttribute("role") || "backend developer"); await this.sleep(700);
    this.beat(3); await this.addInterest(this.getAttribute("interest") || "the job market"); await this.sleep(900);
    this.beat(4); await this.save(); await this.sleep(1200);
  }
}

export { NwDiscover };
