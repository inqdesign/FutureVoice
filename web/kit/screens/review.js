/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc } from "../core.js";

/* ═══════════════════════════ <nw-review> — the Review tab, end to end ═══════════════════════════
 * The navigation the app really has, from PracticeTab:
 *   Studying page (<nw-book>) → tap the talk's BOOK CARD → ConversationDetailView PUSHED
 *   (`talkCard` is a NavigationLink) — the review book (<nw-bookpage>) on its cover →
 *   the Words and Expressions ribbons → the Drill ribbon → "Review this talk" → DrillView(.session) PUSHED
 *   (`NavigationLink { sessionDeck }`, titled "Review") → a card answered out loud, tapped to check,
 *   filed into Tomorrow.
 * The deck (DrillView): card 16–386 × 156–751pt in the theme blue, the 12pt labels, the hint and the
 * folder chips under it, the 10 min · Tomorrow · 3 days · Got it tray — measured from the `drills` /
 * `drills-tray` captures. The poses `card` / `revealed` are that capture (the Sentences sheet).
 *
 * Beats: 1 the book opens from its shelf card · 2 the Words / Expressions chapters · 3 the Drill
 * chapter (struck line → fixed line, the fix highlighted, why) · 4 a card answered aloud, checked, filed. */
const T = {
  ko: { title: "문장", review: "복습", done: "완료", said: "내가 한 말", ask: "유창한 사람이라면 어떻게 말할까요?",
        reveal: "눌러서 보기", hint: "소리 내어 말한 뒤 카드를 눌러 확인하세요", trySay: "이렇게 말해 보세요", why: "이유",
        count: (a, b) => `${a} / ${b}`, waiting: n => ` · ${n}명 대기 중`,
        f: ["10분", "내일", "3일", "알아요"], date: "2026년 10월 10일 오후 8:20" },
  en: { title: "Sentences", review: "Review", done: "Done", said: "You said", ask: "How would a fluent speaker say it?",
        reveal: "Tap to reveal", hint: "Say it out loud, then tap the card to check", trySay: "Try saying", why: "Why",
        count: (a, b) => `${a} of ${b}`, waiting: n => ` · ${n} waiting`,
        f: ["10 min", "Tomorrow", "3 days", "Got it"], date: "Oct 10, 2026 at 8:20 PM" },
};
/* The talk on the shelf (<nw-book>'s top card): its book, and the cards its Drill chapter minted. */
const TALK = {
  title: "“Honestly, it went really well. I…”", turns: 6, mastered: 0, total: 13,
  words: [["initiative"], ["perspective"], ["attainable"], ["compelling"], ["prioritize"]],
  mine: [["prepared", ""], ["relaxed", "known"]],
  shadow: ["That's a compelling perspective — you clearly took the initiative to prioritize what mattered."],
  tabs: { words: [0, 5], expressions: [0, 4], drill: [0, 3], shadow: [0, 1] },
};
const CARDS = [
  { said: "Honestly, it go really well. I felt prepared.", fix: "Honestly, it <b>went</b> really well — I felt prepared.", why: { ko: "지난 일이라 과거형이에요.", en: "It already happened, so past tense." } },
  { said: "How relaxed I stayed, even on hard question.", fix: "How relaxed I stayed, even on <b>the</b> hard <b>questions</b>.", why: { ko: "the를 붙이고 복수형으로.", en: "Add “the” and make it plural." } },
];
/* the `drills` capture's own card (the Sentences sheet) */
const CAP = { said: "Feel something around Nirvana the app that I'm gonna be working on", fix: "I'm <b>working on</b> an app called Nirvana.", why: { ko: "현재 진행 중인 일은 현재진행형으로.", en: "Something under way: present continuous." } };

/* SF Symbols, traced */
const SF = {
  eye: '<path d="M1.5 10C3.6 5.9 6.6 4 10 4s6.4 1.9 8.5 6c-2.1 4.1-5.1 6-8.5 6s-6.4-1.9-8.5-6z" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="10" cy="10" r="2.9" fill="currentColor"/>',
  hand: '<path d="M7 9V3.6a1.3 1.3 0 0 1 2.6 0V8m0-.6V6.2a1.3 1.3 0 0 1 2.6 0V8m0-.9a1.3 1.3 0 0 1 2.6 0v1.4m0-.4a1.3 1.3 0 0 1 2.6.3v3.9c0 3-2 5.2-5 5.2h-1c-1.8 0-3.1-.9-4.1-2.4L4 11.3a1.2 1.2 0 0 1 1.9-1.4L7 11" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>',
  clock: '<circle cx="10" cy="10" r="7.6" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M10 5.6V10l2.9 1.8" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>',
  rise: '<path d="M3 15.5h14M5.4 13a4.6 4.6 0 0 1 9.2 0M10 2.8v4.4M7.8 5L10 2.8 12.2 5M3.6 8.6l1.4 1M16.4 8.6l-1.4 1" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',
  cal: '<path fill="currentColor" fill-rule="evenodd" d="M5.4 3h9.2A2.4 2.4 0 0 1 17 5.4v9.2a2.4 2.4 0 0 1-2.4 2.4H5.4A2.4 2.4 0 0 1 3 14.6V5.4A2.4 2.4 0 0 1 5.4 3zM4.4 7.4v7a1.2 1.2 0 0 0 1.2 1.2h8.8a1.2 1.2 0 0 0 1.2-1.2v-7z"/><g fill="currentColor">' + [[8, 9.4], [10.4, 9.4], [12.8, 9.4], [5.6, 11.6], [8, 11.6], [10.4, 11.6], [12.8, 11.6], [5.6, 13.8], [8, 13.8], [10.4, 13.8]].map(([x, y]) => `<circle cx="${x + .6}" cy="${y}" r=".75"/>`).join("") + "</g>",
  check: '<circle cx="10" cy="10" r="8" fill="currentColor"/><path d="M6.4 10.2l2.5 2.4 4.8-5" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  chevL: '<path d="M13 3.2L6.4 10l6.6 6.8" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>',
};
const sf = (n, s = 18) => `<svg viewBox="0 0 20 20" width="${s}" height="${s}" aria-hidden="true" style="display:block">${SF[n]}</svg>`;
const FOLD = [["clock", "#FF8D28"], ["rise", "#0088FF"], ["cal", "#6155F5"], ["check", "#34C759"]];
const PUSH = "transform .5s cubic-bezier(.32,.72,0,1)";

class NwReview extends NwScreen {
  static poses = ["studying", "bookcover", "words", "expressions", "drillchapter", "card", "revealed"];
  constructor() {
    super(`
      :host{background:#F2F2F7;letter-spacing:0}
      nw-book,nw-bookpage{position:absolute;inset:0;width:100%;height:100%}
      .lay{position:absolute;inset:0;transition:${PUSH};will-change:transform}
      .lay.right{transform:translateX(100%)}
      .lay.left{transform:translateX(-30%)}
      .shade{position:absolute;inset:0;background:rgba(0,0,0,.1);opacity:0;transition:opacity .5s;pointer-events:none}
      .lay.left>.shade{opacity:1}
      .book .shade,.bp .shade{z-index:30}
      .dim{position:absolute;inset:0;background:rgba(0,0,0,.2);opacity:0;transition:opacity .4s;pointer-events:none;z-index:4}
      .dim.on{opacity:1}
      .sheet{position:absolute;left:0;right:0;top:0;bottom:0;transform:translateY(102%);transition:transform .55s cubic-bezier(.3,.8,.2,1);z-index:5;overflow:hidden;border-radius:38px 38px 0 0}
      .sheet.on{transform:none}
      .tapc{position:absolute;width:56px;height:56px;margin:-28px 0 0 -28px;border-radius:50%;background:rgba(0,0,0,.12);transform:scale(.4);opacity:0;z-index:9;pointer-events:none;transition:transform .3s,opacity .3s}
      .tapc.on{transform:scale(1);opacity:1}
      /* the deck — a sheet (the capture) or pushed from the book (.pushed) */
      .deck{background:#fff;border-radius:0}
      .deck.sheet.pushed{transform:translateX(100%);transition:${PUSH};border-radius:0}
      .deck.sheet.pushed.on{transform:none}
      .nav{position:absolute;left:0;right:0;top:62px;height:44px;display:flex;align-items:center;justify-content:center;font-family:var(--pixel);font-size:17px;z-index:3}
      .done{position:absolute;right:16px;top:62px;height:44px;padding:0 15px;border-radius:22px;background:rgba(255,255,255,.95);box-shadow:0 2px 12px rgba(0,0,0,.08),inset 0 0 0 .5px rgba(0,0,0,.05);display:grid;place-items:center;font-size:17px;color:var(--blue);z-index:3}
      .bk{position:absolute;left:16px;top:62px;width:44px;height:44px;border-radius:22px;background:#FDFDFE;box-shadow:0 0 0 .5px rgba(0,0,0,.025),0 6px 22px rgba(0,0,0,.065);display:none;place-items:center;color:#000;z-index:3}
      .pushed .bk{display:grid}.pushed .done{display:none}
      .cnt{position:absolute;left:0;right:0;top:126px;text-align:center;font-size:13px;line-height:18px;color:rgba(60,60,67,.6);font-variant-numeric:tabular-nums}
      .cnt i{font-style:normal;color:rgba(60,60,67,.3)}
      .card{position:absolute;left:16px;top:156px;width:370px;height:595px;border-radius:26px;background:var(--blue);color:#fff;transform-origin:50% 100%;box-shadow:0 6px 24px rgba(10,92,245,.16);transition:transform .6s cubic-bezier(.4,0,.2,1),opacity .4s}
      .card .face{position:absolute;inset:0;padding:22px 24px;transition:opacity .3s}
      .card .back{opacity:0}
      .card.flip .front{opacity:0}.card.flip .back{opacity:1}
      .lab{font-size:13px;line-height:16px;color:rgba(255,255,255,.75)}
      .said{margin-top:6.5px;font-size:17px;line-height:20.7px;letter-spacing:-.3px;color:rgba(255,255,255,.78)}
      .ask{margin-top:16.5px}
      .bar{height:15.3px;border-radius:3px;background:rgba(255,255,255,.16);margin-top:12.7px}
      .bar.b1{margin-top:12.7px}
      .rev{position:absolute;left:0;right:0;bottom:24px;display:flex;justify-content:center;align-items:center;gap:6px;font-size:15px;font-weight:500}
      .back .said{color:rgba(255,255,255,.62);text-decoration:line-through;text-decoration-color:rgba(255,255,255,.62)}
      .fixd{margin-top:8px;font-size:22px;line-height:27px;font-weight:600;letter-spacing:-.2px}
      .fixd b{font-weight:600}
      .reason{margin-top:6px;font-size:15px;line-height:20px;color:rgba(255,255,255,.86)}
      .hint{position:absolute;left:0;right:0;top:770px;text-align:center;font-size:13px;color:rgba(60,60,67,.6);display:flex;justify-content:center;gap:5px;align-items:center;transition:color .3s}
      .hint.say{color:var(--blue)}
      .chips{position:absolute;left:0;right:0;top:803px;display:flex;justify-content:center;gap:8px}
      .chips span{height:28px;padding:0 12px;border-radius:14px;background:#EFEFF0;display:flex;align-items:center;gap:6px;font-size:15px;font-weight:600;font-variant-numeric:tabular-nums;transition:background .3s}
      .chips span.hit{background:#DCE8FE}
      .tray{position:absolute;left:12px;right:12px;top:700px;display:grid;grid-template-columns:repeat(4,1fr);gap:8px;transform:translateY(200px);transition:transform .45s cubic-bezier(.3,.8,.2,1);z-index:6}
      .tray.on{transform:none}
      .tray span{height:76px;border-radius:18px;background:rgba(242,242,247,.96);box-shadow:0 2px 10px rgba(0,0,0,.08);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;font-size:13px;color:rgba(60,60,67,.85);transition:background .25s,color .25s}
      .tray span.pick{background:var(--blue);color:#fff}
      .tray span.pick i{color:#fff!important}
      .listen{position:absolute;left:50%;top:742px;margin-left:-60px;width:120px;height:20px;display:flex;align-items:center;justify-content:center;gap:3px;opacity:0;transition:opacity .3s}
      .listen.on{opacity:1}
      .listen i{width:3px;height:100%;border-radius:2px;background:var(--blue);transform:scaleY(.2);animation:lv .6s ease-in-out infinite alternate}
      @keyframes lv{to{transform:scaleY(var(--h))}}
    `, `
      <div class="lay book"><nw-book></nw-book><div class="shade"></div></div>
      <div class="lay bp right"><nw-bookpage></nw-bookpage><div class="shade"></div></div>
      <div class="dim"></div>
      <div class="sheet dk deck">
        <div class="bk">${sf("chevL", 22)}</div><div class="nav"></div><div class="done"></div><div class="cnt"></div>
        <div class="card"><div class="face front"><div class="lab l1"></div><div class="said s1"></div><div class="lab ask l2"></div><div class="bar b1"></div><div class="bar"></div><div class="bar" style="width:44.7%"></div><div class="rev">${sf("eye")}<span></span></div></div>
          <div class="face back"><div class="lab l1"></div><div class="said s2"></div><div class="lab ask l3"></div><div class="fixd"></div><div class="lab ask l4"></div><div class="reason"></div></div></div>
        <div class="listen">${[.5, .9, .6, 1, .7, .4, .8, .55, .9, .45].map((h, i) => `<i style="--h:${h};animation-delay:${-i * .07}s"></i>`).join("")}</div>
        <div class="hint">${sf("hand", 14)}<span></span></div>
        <div class="chips"></div>
        <div class="tray"></div>
      </div>
      <div class="tapc"></div>`);
  }
  get L() { return this.t === STR.ko ? T.ko : T.en; }
  get lang() { return this.t === STR.ko ? "ko" : "en"; }
  stop() { super.stop(); this.shadowRoot?.querySelectorAll("nw-bookpage,nw-book").forEach(e => e.stop?.()); }
  build() {
    const L = this.L;
    this.$$("nw-book,nw-bookpage").forEach(e => { e.setAttribute("lang", this.lang); e.setAttribute("fill", ""); });
    this.$(".done").textContent = L.done;
    this.$$(".l1").forEach(e => e.textContent = L.said); this.$(".l2").textContent = L.ask;
    this.$(".l3").textContent = L.trySay; this.$(".l4").textContent = L.why;
    this.$(".rev span").textContent = L.reveal; this.$(".hint span").textContent = L.hint;
    this.$(".tray").innerHTML = FOLD.map(([n, c], i) => `<span data-i="${i}"><i style="color:${c};display:flex">${sf(n, 22)}</i>${L.f[i]}</span>`).join("");
    this.reset();
  }
  _chips(v, hit = -1) {
    this.$(".chips").innerHTML = FOLD.map(([n, c], i) => `<span class="${i === hit ? "hit" : ""}" style="color:${v[i] ? c : "rgba(60,60,67,.3)"}">${sf(n, 15)}${v[i]}</span>`).join("");
  }
  /* the deck: the Sentences sheet (capture) or this talk's run, pushed from the book */
  _deck(pushed) {
    const dk = this.$(".dk"), L = this.L;
    dk.style.transition = "none"; dk.classList.remove("on"); dk.classList.toggle("pushed", pushed); void dk.offsetWidth; dk.style.transition = "";
    this.$(".nav").textContent = pushed ? L.review : L.title;
  }
  _card(c, a, b, waiting) {
    const card = this.$(".card"), L = this.L;
    card.style.transition = "none"; card.style.transform = "none"; card.style.opacity = 1; card.classList.remove("flip"); void card.offsetWidth; card.style.transition = "";
    this.$(".s1").textContent = c.said; this.$(".s2").textContent = c.said; this.$(".fixd").innerHTML = c.fix; this.$(".reason").textContent = c.why[this.lang];
    this.$(".cnt").innerHTML = esc(L.count(a, b)) + (waiting ? `<i>${esc(L.waiting(waiting))}</i>` : "");
  }
  _bookPage() {
    const bp = this.$("nw-bookpage");
    bp.book = { ...TALK, date: { ko: T.ko.date, en: T.en.date } };
    bp._browsing = true; bp._pushed = true; bp._runRow = true; bp._ch = "cover"; bp._render();
    return bp;
  }
  _lay(sel, cls) { const l = this.$(sel); l.classList.remove("right", "left"); if (cls) l.classList.add(cls); }
  _instant(fn) { const ls = this.$$(".lay"); ls.forEach(l => l.style.transition = "none"); fn(); ls.forEach(l => void l.offsetWidth); ls.forEach(l => l.style.transition = ""); }
  reset() {
    this._instant(() => { this._lay(".book", ""); this._lay(".bp", "right"); });
    this.$$(".sheet").forEach(s => s.classList.remove("on")); this.$(".dim").classList.remove("on");
    this.$(".tray").classList.remove("on"); this.$$(".tray span").forEach(s => s.classList.remove("pick"));
    this.$(".hint").classList.remove("say"); this.$(".listen").classList.remove("on");
    this._deck(false); this._card(CAP, 1, 20, 6); this._chips([2, 4, 2, 2]);
    const book = this.$("nw-book"); if (book._built) book.pose("studying");
    const bp = this.$("nw-bookpage"); if (bp._built) this._bookPage();
  }
  async _tap(x, y) { const t = this.$(".tapc"); t.style.left = x + "px"; t.style.top = y + "px"; t.classList.add("on"); await this.sleep(240); t.classList.remove("on"); }
  /* centre of an element inside a nested screen, in this screen's points */
  _at(el) { const r = el.getBoundingClientRect(), me = this.$(".s").getBoundingClientRect(), k = me.width / 402; return [(r.left + r.width / 2 - me.left) / k, (r.top + r.height / 2 - me.top) / k]; }
  async pose(name) {
    this.stop(); this.reset();
    if (name === "card" || name === "revealed") {
      this.$(".dk").classList.add("on"); this.$(".dim").classList.add("on");
      if (name === "revealed") this.$(".card").classList.add("flip");
    } else if (["bookcover", "words", "expressions", "drillchapter"].includes(name)) {
      await customElements.whenDefined("nw-bookpage");
      const bp = this._bookPage(); if (name !== "bookcover") { bp._ch = name === "drillchapter" ? "drill" : name; bp._render(); }
      this._instant(() => { this._lay(".book", "left"); this._lay(".bp", ""); });
    }
  }
  async demo() {
    const book = this.$("nw-book"), bp = this.$("nw-bookpage");
    await customElements.whenDefined("nw-book"); await book.pose("studying");
    this._bookPage();
    await this.sleep(1200);
    // 1 — the talk's book card on the shelf → the book is pushed, open on its cover
    this.beat(1);
    const card = book.shadowRoot.querySelector(".shelf .bk");
    if (card) await this._tap(...this._at(card));
    this._lay(".book", "left"); this._lay(".bp", ""); await this.sleep(2200);
    // 2 — the ribbon bookmarks: Words, then Expressions
    this.beat(2);
    await bp.open("words"); await this.sleep(2200);
    await bp.open("expressions"); await this.sleep(2200);
    // 3 — the Drill chapter: what was said, struck; the fixed line; why
    this.beat(3);
    await bp.open("drill"); await this.sleep(3200);
    // 4 — "Review this talk" pushes the run of this talk's cards: answer it out loud, then check
    await bp.tapLine("run");
    this._deck(true); this._card(CARDS[0], 1, 3, 0); this._chips([0, 0, 0, 0]);
    this._lay(".bp", "left"); this.$(".dk").classList.add("on");
    this.beat(4); await this.sleep(1100);
    this.$(".hint").classList.add("say"); this.$(".listen").classList.add("on"); await this.sleep(2200);
    this.$(".listen").classList.remove("on"); this.$(".hint").classList.remove("say");
    await this._tap(201, 450); this.$(".card").classList.add("flip"); await this.sleep(2000);
    // file it: Tomorrow
    this.$(".tray").classList.add("on"); await this.sleep(500);
    const pick = this.$('.tray span[data-i="1"]'); pick.classList.add("pick");
    this.$(".card").style.transform = "translate(-60px, 520px) scale(.18) rotate(-6deg)"; this.$(".card").style.opacity = 0;
    await this.sleep(650); this.$(".tray").classList.remove("on"); pick.classList.remove("pick"); this._chips([0, 1, 0, 0], 1);
    await this.sleep(400); this._card(CARDS[1], 2, 3, 0); await this.sleep(2000);
  }
}

export { NwReview };
