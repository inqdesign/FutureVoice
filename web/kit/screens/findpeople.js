/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc } from "../core.js";

/* ═══════════════════════════ <nw-findpeople> — the Find people sheet ═══════════════════════════
 * FindPeopleSheet.swift, the "People" page behind Watch's person.2 button: your people on top
 * (the "New person" row), the People | Characters segmented control with its one-line footer, then
 * STRANGERS — the shared pool, each row the published portrait a person chose to show: a 44pt
 * PersonBubble (initial on an accent-tinted circle), the name (.body medium), the occupation·place
 * facet (.caption), and the interests line (.caption). A floating search field is pinned at the
 * bottom. The intro/facet line is the point of the screen — it's who you're about to call, in the
 * language you're learning, read before you tap Talk.
 *
 * Laid out in iOS points from marketing/captures/people.png (iPhone 17, 1206×2622 ÷ 3). Accent
 * #0A5CF5. Sample people only — never a real learner's published profile.
 *
 *   p.scrollTo(y)            scroll the list under the fixed nav/search
 *   await p.scrollToRow(i)   bring stranger i to a comfortable reading position
 *   p.focusRow(i) / p.clearFocus()   lift one row and fade the rest — pull a sticker from it
 *   poses: list (scroll 0, the capture) · scrolled · focus */

/* SF Symbols, traced */
const SF = {
  // plus.circle.fill — filled accent disc, white plus (New person row)
  plusCircle: '<svg viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="12" r="11" fill="currentColor"/><path d="M12 6.8v10.4M6.8 12h10.4" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"/></svg>',
  // magnifyingglass — search field leading
  glass: '<svg viewBox="0 0 22 22" width="22" height="22"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="9.3" cy="9.3" r="6.4"/><path d="M14.2 14.2l5 5"/></g></svg>',
  // chevron.forward — list disclosure, light gray
  chev: '<svg viewBox="0 0 9 15" width="9" height="15"><path d="M1.6 1.4l6 6.1-6 6.1" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
};

/* The pool, exactly as the capture shows it — a facet line (occupation OR place) and an interests
 * line, both the person's own published words in the target language. Sample data, not real people.
 *   [name, initial, facet, interests] */
const POOL = [
  ["holly", "H", "Former project manager in the healthcare sector", "AI / tech, language learning, cooking"],
  ["Dong", "D", "seoul, korea", "AI / tech, language learning, podcasts, travel, music"],
  ["Mark", "M", "부산", "language learning, podcasts, sports, AI / tech, cooking"],
  ["Sunny", "S", "Langley, Canada", "cooking, parenting, travel, podcasts, language learning"],
  ["Emma", "E", "Marketing professional focused on performance", "podcasts, finance, language learning, travel"],
  ["진", "진", "서울", "music, cooking, language learning, art"],
  ["Noah", "N", "A software engineer who just moved to Berlin", "AI / tech, science, language learning, sports"],
  ["Priya", "P", "A nurse, back to studying at thirty", "parenting, cooking, language learning, podcasts"],
];

const T = {
  ko: { title: "사람", done: "완료", mine: "내 사람들", add: "사람 추가", people: "사람", chars: "가상 인물",
        strangers: "낯선 사람", search: "이름, 관심사, 지역…",
        foot: "소개를 공개한 다른 학습자들이에요. 대화해도 상대에게 알림이 가지 않아요 — 그 사람의 소개를 AI가 기본 목소리로 말하는 것이고, 본인 목소리는 쓰이지 않아요." },
  en: { title: "People", done: "Done", mine: "Your people", add: "New person", people: "People", chars: "Characters",
        strangers: "Strangers", search: "Name, interests, place…",
        foot: "Other learners who published an introduction. Talking with someone doesn't notify them — it's an AI speaking their introduction, in a stock voice, never theirs." },
};

class NwFindPeople extends NwScreen {
  static poses = ["list", "scrolled", "focus"];
  constructor() {
    super(`
      :host{background:#F2F2F7;--acc:#0A5CF5;--sec:#8A8A8E;--sep:#D3D3D7;letter-spacing:-.2px}
      .s{background:#F2F2F7}
      /* scrolling list */
      .sc{position:absolute;left:0;right:0;top:0;transition:transform .7s cubic-bezier(.45,0,.2,1)}
      .ct{padding:118px 0 128px}
      .hd{margin:0 0 0 32px;font-size:17px;line-height:22px;color:var(--sec);letter-spacing:-.3px}
      .hd.two{margin-top:17px}
      .card{margin:12px 16px 0;background:#fff;border-radius:13px;overflow:hidden}
      /* new-person row */
      .add{display:flex;align-items:center;gap:13px;min-height:52px;padding:0 16px 0 16px;color:var(--acc)}
      .add .ic{flex:0 0 auto;color:var(--acc);display:flex}
      .add b{font-size:17px;font-weight:500;letter-spacing:-.4px}
      /* segmented control */
      .seg{margin:48px 32px 0;height:32px;border-radius:9px;background:rgba(118,118,128,.12);display:flex;padding:2px;position:relative}
      .seg .sl{position:absolute;top:2px;left:2px;width:calc(50% - 2px);height:28px;border-radius:7px;background:#fff;box-shadow:0 3px 8px rgba(0,0,0,.12),0 1px 1px rgba(0,0,0,.04)}
      .seg span{position:relative;flex:1;display:flex;align-items:center;justify-content:center;font-size:13px;letter-spacing:-.2px;color:#000;z-index:1}
      .seg span.on{font-weight:600}
      .foot{margin:12px 32px 0;font-size:13px;line-height:16px;color:var(--sec);letter-spacing:-.1px;word-break:keep-all}
      /* person rows */
      .pr{position:relative;display:flex;align-items:center;gap:13px;padding:9px 14px 9px 16px;min-height:87px}
      .pr + .pr::before{content:"";position:absolute;left:33px;right:15px;top:0;border-top:.5px solid var(--sep)}
      .av{flex:0 0 44px;width:44px;height:44px;border-radius:50%;display:grid;place-items:center;
        background:rgba(10,92,245,.15);box-shadow:inset 0 0 0 1.5px rgba(10,92,245,.35);
        color:var(--acc);font-size:15px;font-weight:600;letter-spacing:0}
      .col{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
      .col .nm{font-size:17px;font-weight:500;letter-spacing:-.4px;line-height:21px}
      .col .fc,.col .it{font-size:12px;line-height:15px;color:var(--sec);letter-spacing:-.1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .ch{flex:0 0 auto;color:#C2C2C6;display:flex;margin-right:2px}
      /* focus: lift one row, fade the rest */
      .card.focusing .pr{opacity:.22;transition:opacity .45s}
      .card.focusing .pr.foc{opacity:1;background:#fff;border-radius:16px;transform:scale(1.015);
        box-shadow:0 12px 34px rgba(0,0,0,.14),0 2px 6px rgba(0,0,0,.06);z-index:2}
      .card.focusing .pr.foc::before,.card.focusing .pr.foc + .pr::before{border-color:transparent}
      /* fixed nav (glass) */
      .nav{position:absolute;left:0;right:0;top:62px;height:44px;z-index:6}
      .ttl{position:absolute;left:100px;right:100px;top:0;height:44px;line-height:44px;text-align:center;
        font-family:var(--pixel);font-size:18px;letter-spacing:0}
      .done{position:absolute;right:16px;top:0;height:44px;padding:0 16px;border-radius:22px;background:#FBFBFE;
        box-shadow:inset 0 0 0 1px rgba(255,255,255,.95),0 0 0 .5px rgba(0,0,0,.035),0 4px 16px rgba(0,0,0,.065);
        display:flex;align-items:center;font-size:17px;color:var(--acc);letter-spacing:-.4px}
      .edge{position:absolute;left:0;right:0;top:0;height:122px;z-index:5;pointer-events:none;opacity:0;transition:opacity .3s;
        background:linear-gradient(#F2F2F7 0,#F2F2F7 86%,rgba(242,242,247,.5) 94%,rgba(242,242,247,0))}
      .edge.on{opacity:1}
      /* floating search, pinned bottom */
      .sbar{position:absolute;left:0;right:0;bottom:0;height:96px;z-index:5;pointer-events:none;
        -webkit-mask-image:linear-gradient(transparent,#000 42%);mask-image:linear-gradient(transparent,#000 42%);
        background:linear-gradient(rgba(242,242,247,0),rgba(242,242,247,.82) 55%,rgba(242,242,247,.96))}
      .search{position:absolute;left:16px;right:16px;bottom:28px;height:49px;border-radius:24.5px;background:#FFF;z-index:6;
        box-shadow:0 1px 0 rgba(255,255,255,.9) inset,0 8px 26px rgba(0,0,0,.1),0 1px 4px rgba(0,0,0,.05);
        display:flex;align-items:center;gap:7px;padding:0 15px;color:#8A8A8E}
      .search .ic{display:flex;flex:0 0 auto}
      .search .ph{font-size:17px;letter-spacing:-.3px;color:#8A8A8E}
    `, `
      <div class="sc"><div class="ct">
        <div class="hd one h1"></div>
        <div class="card"><div class="add"><span class="ic">${SF.plusCircle}</span><b class="addl"></b></div></div>
        <div class="seg"><div class="sl"></div><span class="on s1"></span><span class="s2"></span></div>
        <p class="foot"></p>
        <div class="hd two h2"></div>
        <div class="card strangers"></div>
      </div></div>
      <div class="edge"></div>
      <div class="sbar"></div>
      <div class="search"><span class="ic">${SF.glass}</span><span class="ph"></span></div>
      <div class="nav"><span class="ttl"></span><span class="done"></span></div>`);
    this._y = 0; this._foc = -1;
  }

  get L() { return this.t === STR.ko ? T.ko : T.en; }

  build() {
    const L = this.L;
    this.$(".ttl").textContent = L.title;
    this.$(".done").textContent = L.done;
    this.$(".h1").textContent = L.mine;
    this.$(".addl").textContent = L.add;
    this.$(".s1").textContent = L.people;
    this.$(".s2").textContent = L.chars;
    this.$(".foot").textContent = L.foot;
    this.$(".h2").textContent = L.strangers;
    this.$(".ph").textContent = L.search;
    this.$(".strangers").innerHTML = POOL.map(([nm, ini, fc, it], i) => `
      <div class="pr" data-i="${i}">
        <span class="av">${esc(ini)}</span>
        <span class="col"><span class="nm">${esc(nm)}</span><span class="fc">${esc(fc)}</span><span class="it">${esc(it)}</span></span>
        <span class="ch">${SF.chev}</span>
      </div>`).join("");
    this.reset();
  }

  reset() { this.clearFocus(); this.scrollTo(0); }

  /* ── scrolling ── */
  _maxScroll() {
    const ct = this.$(".ct"); if (!ct) return 0;
    // last row's bottom should clear the search pill (its top ≈ 797pt)
    return Math.max(0, ct.scrollHeight - 797);
  }
  scrollTo(y) {
    y = Math.max(0, Math.min(y, this._maxScroll())); this._y = y;
    this.$(".sc").style.transform = y ? `translateY(${-y}px)` : "none";
    this.$(".edge").classList.toggle("on", y > 6);
    return y;
  }
  /** Bring stranger `i` up to a comfortable reading spot under the nav. */
  async scrollToRow(i, settle = 700) {
    const row = this.$(`.pr[data-i="${i}"]`); if (!row) return;
    const ct = this.$(".ct");
    const top = row.offsetTop + ct.offsetTop;   // row top within the scroll content
    this.scrollTo(top - 150);                   // sit it just below the nav
    await this.sleep(settle);
  }

  /* ── focus (pull a sticker) ── */
  focusRow(i) {
    this._foc = i;
    this.$(".strangers").classList.add("focusing");
    this.$$(".pr").forEach(r => r.classList.toggle("foc", +r.dataset.i === i));
  }
  clearFocus() {
    this._foc = -1;
    this.$(".strangers")?.classList.remove("focusing");
    this.$$(".pr").forEach(r => r.classList.remove("foc"));
  }

  async pose(name) {
    this.stop(); this.clearFocus();
    if (name === "list") return this.scrollTo(0);
    if (name === "scrolled") return this.scrollTo(260);
    if (name === "focus") { this.scrollTo(150); this.focusRow(1); return; }
  }

  async demo() {
    this.scrollTo(0); this.clearFocus();
    await this.sleep(1400);
    // 1 — the pool, read at rest
    this.beat(1); await this.sleep(1600);
    // 2 — a slow scroll down the strangers
    this.beat(2);
    this.scrollTo(200); await this.sleep(1700);
    this.scrollTo(400); await this.sleep(1700);
    this.scrollTo(220); await this.sleep(1400);
    // 3 — read ONE person, their own words
    this.beat(3);
    await this.scrollToRow(2, 750);
    this.focusRow(2); await this.sleep(2600);
    this.clearFocus(); await this.sleep(900);
  }
}

export { NwFindPeople };
