/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc, icon, wordsHTML, mmss } from "../core.js";

/* ═══════════════════════════ <nw-call> ═══════════════════════════
 * The live call (ConversationView). Script it:
 *   await call.say("Hey, it's you…")       fluent self speaks (pill blooms, words light up)
 *   await call.listen()                      the learner's turn (the empty "Listening…" bubble)
 *   await call.user("I go to three…")        their words arrive (then "thinking")
 *   call.fix({ text: "I <b>went</b> to…", note: "Past tense",
 *              fixes: [{ was: "I go to", now: "I went to", why: "" }] })   the correction card
 *   call.coach({ line: "It was <u>a busy</u> week.", gloss: "…", word: "busy week" }) / call.coach(null)
 *   call.goals(["busy week", "catch up"]); call.tick(0)
 * Attributes: title, level (default B2), autoplay.
 *
 * Drawn from the app, point for point:
 *   toolbar     ✕ (Label "Close", xmark) · LevelHeaderTitle (headline + "B2 ›" caption2 semibold
 *               secondary, "· 0:25" once the learner has spoken) · End (semibold)
 *   chips       TalkGoalChipsRow: footnote text, caption2 circle / checkmark.circle.fill (green),
 *               capsule secondarySystemBackground, 10×5 padding, spacing 8, row padding 20×7,
 *               Divider at 0.15 opacity
 *   feed        LazyVStack spacing 18, padding 20 / top 12, bottom-anchored (defaultScrollAnchor)
 *   lines       DialogueLine .call: name caption secondary (the app passes "You"/"Future self" as
 *               String, so they are never localised), title3 (20pt) text, padding 14×10, radius 14,
 *               fill secondarySystemBackground / accent 18%, 40pt opposite gutter
 *   accessory   "Meaning" (character.bubble, caption, secondary) then SuggestionChip
 *   card        SuggestionChip: sparkles (footnote, tint) + [alternative (subheadline, changed words
 *               accent semibold) · reason (caption, secondary) · TurnFixRows (✕ red / ✓ green,
 *               caption) · "Explain in my language" (caption2, tint)], padding 12×8, radius 12
 *   bottom bar  CoachReplyLabel (caption / body semibold / subheadline) · CoachHintLine
 *               (subheadline: lightbulb · "Try using" · word bold) · 156×64 Futureself pill with the
 *               call-settings button (44pt circle, slider.horizontal.3) pinned left · footnote hint;
 *               spacing 10, padding top 14 / bottom 20 above the home indicator */

const S = {
  xmark: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4.2 4.2l11.6 11.6M15.8 4.2L4.2 15.8" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  chev: '<svg viewBox="0 0 8 8" aria-hidden="true"><path d="M2.6 1.2L5.4 4 2.6 6.8" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  circle: '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="8.6" fill="none" stroke="currentColor" stroke-width="1.3"/></svg>',
  checkFill: '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="9.3" fill="currentColor"/><path d="M5.9 10.3l2.7 2.7 5.5-6" fill="none" stroke="#fff" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  sparkles: '<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="currentColor"><path d="M14.6 6.2c.55 4.3 2.35 6.1 6.6 6.65-4.25.55-6.05 2.35-6.6 6.65-.55-4.3-2.35-6.1-6.6-6.65 4.25-.55 6.05-2.35 6.6-6.65z"/><path d="M6.6 2.2c.3 2.1 1.15 2.95 3.25 3.25-2.1.3-2.95 1.15-3.25 3.25-.3-2.1-1.15-2.95-3.25-3.25 2.1-.3 2.95-1.15 3.25-3.25z"/><path d="M6.2 14.6c.2 1.5.8 2.1 2.3 2.3-1.5.2-2.1.8-2.3 2.3-.2-1.5-.8-2.1-2.3-2.3 1.5-.2 2.1-.8 2.3-2.3z"/></g></svg>',
  bubble: g => `<svg viewBox="0 0 22 20" aria-hidden="true"><path d="M5 2.2h12a3.2 3.2 0 0 1 3.2 3.2v6.4a3.2 3.2 0 0 1-3.2 3.2h-6.3l-4.4 3.3c-.5.4-1.1 0-1.1-.5v-2.8H5a3.2 3.2 0 0 1-3.2-3.2V5.4A3.2 3.2 0 0 1 5 2.2z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><text x="11" y="11.9" text-anchor="middle" font-size="${g === "A" ? 8.6 : 7.6}" font-weight="600" fill="currentColor" font-family="-apple-system,'Apple SD Gothic Neo',sans-serif">${g}</text></svg>`,
  x: '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.6 2.6l6.8 6.8M9.4 2.6L2.6 9.4" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
  check: '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 6.6l2.6 2.6L10 3.2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  bulb: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 2.2a5.6 5.6 0 0 0-3.3 10.1c.6.5.9 1.1.9 1.8v.4h4.8v-.4c0-.7.3-1.3.9-1.8A5.6 5.6 0 0 0 10 2.2z" fill="none" stroke="currentColor" stroke-width="1.45" stroke-linejoin="round"/><path d="M7.7 16.6h4.6M8.4 18.6h3.2" stroke="currentColor" stroke-width="1.45" stroke-linecap="round"/></svg>',
  sliders: '<svg viewBox="0 0 22 20" aria-hidden="true"><g stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"><path d="M2 4.5h18M2 10h18M2 15.5h18"/></g><g fill="#F2F2F7" stroke="currentColor" stroke-width="2"><circle cx="14.5" cy="4.5" r="2.4"/><circle cx="7.5" cy="10" r="2.4"/><circle cx="12" cy="15.5" r="2.4"/></g></svg>',
};

/* The chrome the call writes (Localizable.xcstrings ko values). */
const L = {
  ko: { talk: "대화하기", end: "종료", meaning: "뜻", explain: "내 언어로 설명", trySaying: "이렇게 말해 보세요",
    tryUsing: "써 볼 단어", usedIt: "썼어요", listening: "듣는 중…", thinking: "유창해진 내가 생각하는 중…",
    hintListen: "듣는 중 · 잠깐 멈추면 전송 · 누르면 종료", hintThink: "생각하는 중 · 누르면 종료",
    hintSpeak: "말하는 중… · 끼어들어도 돼요 · 탭하면 멈춤", hintIdle: "통화 중 · 누르면 종료" },
  en: { talk: "Let's talk", end: "End", meaning: "Meaning", explain: "Explain in my language", trySaying: "Try saying",
    tryUsing: "Try using", usedIt: "Used it", listening: "Listening…", thinking: "Future self is thinking…",
    hintListen: "Listening · pause to send · tap to stop", hintThink: "Thinking… · tap to stop",
    hintSpeak: "Speaking… · talk over it · tap to stop", hintIdle: "On call · tap to stop" },
};

class NwCall extends NwScreen {
  static poses = ["coach", "fix", "speaking"];
  constructor() {
    super(`
      :host{--sec:rgba(60,60,67,.6);--ter:rgba(60,60,67,.3);--sys2:#F2F2F7;--acc:#007AFF}
      .navt{position:absolute;left:80px;right:80px;top:66px;z-index:6;display:flex;flex-direction:column;align-items:center;gap:1px}
      .navt b{font-size:17px;line-height:22px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:240px;letter-spacing:-.4px}
      .navt i{font-style:normal}
      .navt span{display:flex;align-items:center;gap:3px;font-size:11px;line-height:13px;font-weight:600;color:var(--sec);letter-spacing:.05px}
      .navt span svg{width:8px;height:8px}
      .navt .clk{display:none;font-variant-numeric:tabular-nums}
      .navt.on .clk{display:inline}
      .glass{z-index:6;color:var(--acc)}
      .close{left:16px;width:44px;padding:0}
      .close svg{width:19px;height:19px}
      .end{right:16px}
      .head{position:absolute;left:0;right:0;top:0;height:156px;z-index:4;background:#fff}
      .goals{position:absolute;z-index:5;left:0;right:0;top:116px;height:39px;padding:7px 20px;display:flex;gap:8px;white-space:nowrap;overflow:hidden}
      .goal{flex:0 0 auto;display:flex;align-items:center;gap:5px;height:25.7px;padding:0 10px;border-radius:13px;background:var(--sys2);font-size:13px;letter-spacing:-.08px;transition:color .25s}
      .goal svg{width:12.5px;height:12.5px;color:var(--sec);display:block}
      .goal.done{color:var(--sec)}
      .goal.done svg{color:var(--green)}
      .div{position:absolute;z-index:5;left:0;right:0;top:155.4px;height:.6px;background:rgba(60,60,67,.05)}
      .goals:empty,.goals:empty+.div{display:none}
      .clip{position:absolute;z-index:1;left:0;right:0;top:156px;bottom:0;overflow:hidden}
      .noch .clip{top:116px}
      .feed{position:absolute;left:0;right:0;top:0;padding:12px 20px 12px;display:flex;flex-direction:column;gap:18px;transition:transform .25s ease-out}
      .ln{display:flex;flex-direction:column;align-items:flex-start;gap:4px;padding-right:40px;opacity:0;transition:opacity .25s}
      .ln.in{opacity:1}
      .ln.me{align-items:flex-end;padding:0 0 0 40px}
      .who{font-size:12px;line-height:16px;color:var(--sec);margin:0}
      .bub{max-width:100%;padding:10px 14px;border-radius:14px;font-size:20px;line-height:25px;letter-spacing:0;background:var(--sys2)}
      .ln.me .bub{background:var(--me)}
      .bub.listen{color:var(--sec)}
      :host(:not(:lang(ko))) .bub.listen{font-style:italic}
      .acc{display:flex;flex-direction:column;align-items:flex-start;gap:6px;align-self:stretch}
      .ln.me .acc{align-items:flex-end}
      .acc:empty{display:none}
      .mean{display:flex;align-items:center;gap:4px;font-size:12px;line-height:16px;color:var(--sec)}
      .mean svg{width:15px;height:14px}
      .think{display:flex;align-items:center;gap:6px;font-size:13px;line-height:18px;color:var(--sec);opacity:0;transition:opacity .25s}
      .think.in{opacity:1}
      .spin{width:14px;height:14px;border-radius:50%;background:conic-gradient(from 0deg,rgba(60,60,67,.08),rgba(60,60,67,.6));-webkit-mask:radial-gradient(circle,transparent 4.2px,#000 4.6px);animation:spin 1s steps(8) infinite}
      @keyframes spin{to{transform:rotate(1turn)}}
      .card{align-self:stretch;display:flex;gap:8px;align-items:flex-start;padding:8px 12px;border-radius:12px;background:var(--sys2);text-align:left;opacity:0;transform:translateY(6px);transition:opacity .25s,transform .25s}
      .card.in{opacity:1;transform:none}
      .card>svg{width:15px;height:15px;color:var(--acc);flex:0 0 auto;margin-top:3px}
      .card .col{flex:1;min-width:0;display:flex;flex-direction:column;gap:4px}
      .alt{font-size:15px;line-height:20px;letter-spacing:-.23px}
      .alt b{color:var(--acc);font-weight:600}
      .why{font-size:12px;line-height:16px;color:var(--sec)}
      .fixes{display:flex;flex-direction:column;gap:6px;margin-top:2px}
      .fx{display:flex;flex-direction:column;gap:2px}
      .fx p{margin:0;display:flex;gap:6px;align-items:baseline;font-size:12px;line-height:16px}
      .fx p svg{width:10px;height:10px;flex:0 0 auto;position:relative;top:1px}
      .fx .was{color:var(--sec);text-decoration:line-through}
      .fx .was svg{color:var(--red)}
      .fx .now svg{color:var(--green)}
      .fx small{font-size:11px;line-height:13px;color:var(--ter);padding-left:18px}
      .exp{display:flex;align-items:center;gap:4px;font-size:11px;line-height:13px;color:var(--acc)}
      .exp svg{width:14px;height:13px}
      .bar{position:absolute;z-index:3;left:0;right:0;bottom:34px;padding:14px 0 20px;display:flex;flex-direction:column;align-items:center;gap:10px}
      .bar::before{content:"";position:absolute;left:0;right:0;top:-36px;bottom:-34px;z-index:-1;background:linear-gradient(rgba(255,255,255,0),#fff 36px)}
      .cr,.ch{display:none;opacity:0;transition:opacity .25s}
      .cr.in,.ch.in{display:flex;opacity:1}
      .cr{flex-direction:column;align-items:center;gap:4px;padding:0 32px;text-align:center}
      .cr small{font-size:12px;line-height:16px;color:var(--sec)}
      .cr p{margin:0;font-size:17px;line-height:22px;font-weight:600;letter-spacing:-.41px}
      .cr em{font-style:normal;font-size:15px;line-height:20px;color:var(--sec);letter-spacing:-.23px}
      .cr u{color:rgba(60,60,67,.3);text-decoration:underline;text-decoration-color:rgba(60,60,67,.3);text-decoration-thickness:1px;text-underline-offset:2px}
      .ch{align-items:center;gap:6px;font-size:15px;line-height:20px;letter-spacing:-.23px}
      .ch svg{width:16px;height:17px;color:var(--acc)}
      .ch .lab{color:var(--sec)} .ch .dot{color:var(--ter)} .ch b{font-weight:600}
      .ch.used svg{color:var(--green)}
      .row{position:relative;width:100%;height:64px;display:flex;justify-content:center}
      nw-futureself{width:156px;height:64px}
      .set{position:absolute;left:24px;top:10px;width:44px;height:44px;border-radius:50%;background:var(--sys2);color:var(--sec);display:grid;place-items:center}
      .set svg{width:19px;height:17px}
      .hint{height:16px;font-size:13px;line-height:16px;color:var(--sec);letter-spacing:-.08px}
    `, `
      <div class="head"></div>
      <div class="glass close">${S.xmark}</div>
      <div class="navt"><b></b><span><i class="lv"></i>${S.chev}<i class="clk"></i></span></div>
      <div class="glass end"></div>
      <div class="goals"></div><div class="div"></div>
      <div class="clip"><div class="feed"></div></div>
      <div class="bar">
        <div class="cr"></div>
        <div class="ch"></div>
        <div class="row"><nw-futureself mode="idle" level="0"></nw-futureself><div class="set">${S.sliders}</div></div>
        <div class="hint"></div>
      </div>`);
  }
  get l() { return this.t === STR.ko ? L.ko : L.en; }
  build() {
    this.$(".navt b").textContent = this.getAttribute("title") || this.l.talk;
    this.$(".lv").textContent = (this.getAttribute("level") || "B2").toUpperCase();
    this.$(".end").textContent = this.l.end;
    this.reset();
  }
  reset() {
    clearInterval(this._clockT); this._secs = 0; this._spoke = false;
    this.$(".navt").classList.remove("on"); this.$(".clk").textContent = "";
    this.$(".feed").innerHTML = ""; this._meLn = null; this._think = null;
    this.coach(null);
    this._pill("idle"); this._hint("hintListen");
    this.goals([]);
    this._follow();
  }
  _hint(k) { this.$(".hint").textContent = this.l[k]; }
  _pill(mode) { const p = this.$("nw-futureself"); p.mode = mode; p.level = mode === "speaking" || mode === "listening" ? "voice" : "0"; }
  /* the call clock joins the title from the learner's first line (LevelHeaderTitle callClock) */
  _clock(start) {
    if (this._spoke) return; this._spoke = true; this._secs = start ?? 0;
    const c = this.$(".clk"), set = () => (c.textContent = `· ${mmss(this._secs)}`);
    this.$(".navt").classList.add("on"); set();
    const g = this.alive; clearInterval(this._clockT);
    this._clockT = setInterval(() => { if (!g()) return clearInterval(this._clockT); this._secs++; set(); }, 1000);
  }
  goals(list) {
    this._goalList = list;
    this.$(".goals").innerHTML = list.map(g => `<span class="goal">${S.circle}<span>${esc(g)}</span></span>`).join("");
    this.shadowRoot.querySelector(".s").classList.toggle("noch", !list.length);
  }
  tick(i) {
    const g = this.$$(".goal")[i]; if (!g || g.classList.contains("done")) return;
    g.classList.add("done"); g.querySelector("svg").outerHTML = S.checkFill;
    const ch = this.$(".ch"); if (ch.dataset.word === this._goalList?.[i]) this._hintLine(ch.dataset.word, true);
  }
  _meaning() { return `<span class="mean">${S.bubble(this.t === STR.ko ? "가" : "A")}${esc(this.l.meaning)}</span>`; }
  _add(html, instant) {
    const d = document.createElement("div"); d.innerHTML = html.trim(); const el = d.firstChild;
    this.$(".feed").append(el);
    if (instant) el.classList.add("in"); else { void el.offsetWidth; el.classList.add("in"); }
    this._follow(); return el;
  }
  /* defaultScrollAnchor(.bottom): the feed's end sits on the bar, short content included */
  _follow() {
    const feed = this.$(".feed"), clip = this.$(".clip"), bar = this.$(".bar");
    const room = bar.offsetTop - clip.offsetTop;
    feed.style.transform = `translateY(${room - feed.offsetHeight}px)`;
  }
  _line(who, text, { me = false, sing = false } = {}) {
    const body = sing ? `<div class="bub k">${wordsHTML(text)}</div>` : `<div class="bub">${esc(text)}</div>`;
    return this._add(`<div class="ln${me ? " me" : ""}"><p class="who">${esc(who)}</p>${body}<div class="acc"></div></div>`, !sing && !me);
  }
  _dropThink() { this._think?.remove(); this._think = null; }
  async say(text, { who, per = 160 } = {}) {
    this._dropThink(); this.coach(null);
    this._pill("speaking"); this._hint("hintSpeak");
    const el = this._line(who || "Future self", text, { sing: true });
    await this.sleep(250);
    await this.sing(el.querySelector(".bub"), per);
    el.querySelector(".acc").innerHTML = this._meaning(); this._follow();
    await this.sleep(250);
  }
  async listen() {
    this._pill("listening"); this._hint("hintListen");
    this._meLn = this._line("You", this.l.listening, { me: true });
    this._meLn.querySelector(".bub").classList.add("listen");
    await this.sleep(400);
  }
  async user(text) {
    if (!this._meLn) await this.listen();
    this._clock(9);
    const ln = this._meLn, b = ln.querySelector(".bub"); b.classList.remove("listen");
    await this.typeInto(b, text); this._meLn = null; this._follow();
    this.coach(null);
    ln.querySelector(".acc").innerHTML = this._meaning();
    this._pill("thinking"); this._hint("hintThink");
    this._think = this._add(`<div class="think"><i class="spin"></i>${esc(this.l.thinking)}</div>`);
    await this.sleep(500);
  }
  /* SuggestionChip, under the learner's last line. `text` is the whole turn re-said with the
   * changed words in <b>; `note` the reason; `fixes` [{was, now, why}] the ✕/✓ rows
   * (`was` + `now` alone make one row). `shadow` is accepted and ignored: the live call's card
   * has no Shadow button (that one is on the book page). */
  fix({ text, note = "", fixes, was, now, explain = true } = {}, instant = false) {
    this._dropThink();
    const rows = fixes || (was && now ? [{ was, now }] : []);
    const html = `<div class="card">${S.sparkles}<div class="col">
      <div class="alt">${text}</div>
      ${note ? `<div class="why">${esc(note)}</div>` : ""}
      ${rows.length ? `<div class="fixes">${rows.map(f => `<div class="fx"><p class="was">${S.x}<span>${esc(f.was)}</span></p><p class="now">${S.check}<span>${esc(f.now)}</span></p>${f.why ? `<small>${esc(f.why)}</small>` : ""}</div>`).join("")}</div>` : ""}
      ${explain ? `<span class="exp">${S.bubble(this.t === STR.ko ? "가" : "A")}${esc(this.l.explain)}</span>` : ""}
    </div></div>`;
    const host = [...this.$$(".ln.me")].pop()?.querySelector(".acc");
    const d = document.createElement("div"); d.innerHTML = html.trim(); const card = d.firstChild;
    if (host) host.append(card); else { const ln = this._add(`<div class="ln me in"><div class="acc"></div></div>`, true); ln.firstChild.append(card); }
    if (instant || RM) card.classList.add("in"); else { void card.offsetWidth; card.classList.add("in"); }
    this._follow();
  }
  _hintLine(word, used) {
    const ch = this.$(".ch"); ch.dataset.word = word; ch.classList.toggle("used", used);
    ch.innerHTML = `${used ? S.checkFill : S.bulb}<span class="lab">${esc(used ? this.l.usedIt : this.l.tryUsing)}</span><span class="dot">·</span><b>${esc(word)}</b>`;
  }
  /* CoachReplyLabel (+ CoachHintLine when `word` is set). <u>…</u> = the learner's own fact,
   * drawn faded and underlined like the app's [brackets]. */
  coach(c) {
    const cr = this.$(".cr"), ch = this.$(".ch");
    if (!c) { cr.classList.remove("in"); ch.classList.remove("in"); ch.dataset.word = ""; this._follow(); return; }
    cr.innerHTML = `<small>${esc(this.l.trySaying)}</small><p>${c.line}</p>${c.gloss ? `<em>${c.gloss}</em>` : ""}`;
    cr.classList.add("in");
    if (c.word) { this._hintLine(c.word, false); ch.classList.add("in"); } else ch.classList.remove("in");
    this._follow();
  }
  done() { this._dropThink(); this._pill("listening"); this._hint("hintListen"); }

  /* ── poses: the states the captures show ── */
  async pose(name) {
    this.stop(); this.reset();
    const ko = this.t === STR.ko;
    if (name === "coach") {                      // real/call-coach.png
      this.goals(["total", "battery", "next"]); this.tick(2);
      this._line("You", "Not yet, but I want to go there next week.", { me: true }).classList.add("in");
      this._line("Future self", "Oh, nice! Next week will be here before you know it. Do you have a specific place in mind?");
      this._meLn = this._line("You", this.l.listening, { me: true }); this._meLn.classList.add("in");
      this._meLn.querySelector(".bub").classList.add("listen");
      this.$$(".ln:not(:last-child) .acc").forEach(a => (a.innerHTML = this._meaning()));
      this._pill("listening");
      this.coach({ line: "Yes, I want to try <u>the one in Sinjeon</u>.", gloss: ko ? "응, <u>신전떡볶이</u> 먹어보고 싶어." : "" });
      this._clock(25); clearInterval(this._clockT);
    } else if (name === "fix") {                 // shots/device-call-coach.jpg — the card under the line
      this.goals(["flame", "love your take on", "splinter", "take it all in"]);
      this._line("You", "Everything looks okay, and I am just having a cup of coffee to get it sorted.", { me: true }).classList.add("in");
      this.$(".ln.me .acc").innerHTML = this._meaning();
      this.fix({ text: "Everything looks okay, and <b>I'm</b> just having a cup of coffee to get <b>things</b> sorted.",
        note: ko ? "get it sorted 대신 get things sorted를 쓰는 것이 자연스럽습니다." : "“Get things sorted” is the natural way to say it here.",
        fixes: [{ was: "and just having a cup of coffee to get it sorted", now: "and I'm just having a cup of coffee to get things sorted",
          why: ko ? "막연한 상황 정리에는 get it sorted보다 get things sorted가 맞습니다." : "For things in general, “get things sorted” fits better than “get it sorted”." }] }, true);
      this._line("Future self", "Ah, nice. There's nothing better than that first cup of coffee to get your mind right for the day. Are you planning out your work schedule while you drink it, or just taking a moment to relax?")
        .querySelector(".acc").innerHTML = this._meaning();
      this._meLn = this._line("You", this.l.listening, { me: true }); this._meLn.classList.add("in");
      this._meLn.querySelector(".bub").classList.add("listen");
      this._pill("listening");
      this._clock(25); clearInterval(this._clockT);
    } else if (name === "speaking") {
      this.goals(["busy week", "catch up", "no wonder"]);
      const el = this._line("Future self", "Hey, it's you, a few years from now. So, how was your week?");
      el.querySelector(".acc").innerHTML = this._meaning();
      this._pill("speaking"); this._hint("hintSpeak");
    }
    this._follow();
  }

  async demo() {
    const ko = this.t === STR.ko;
    this.goals(["busy week", "catch up", "no wonder"]);
    await this.sleep(600);
    this.beat(1);
    await this.say("Hey, it's you, a few years from now. So, how was your week?");
    this.beat(2);
    await this.listen();
    this.coach({ line: "It was a busy week. I had <u>a lot of meetings</u>.", gloss: ko ? "바쁜 한 주였어. <u>회의가 많았어</u>." : "", word: "busy week" });
    await this.sleep(1800);
    await this.user("It was a busy week. I go to three meetings a day.");
    this.tick(0);
    await this.sleep(700);
    this.beat(3);
    this._dropThink();
    this.fix({ text: "It was a busy week. I <b>went</b> to three meetings a day.",
      note: ko ? "지난 일이라 과거형이에요" : "It already happened, so past tense.",
      fixes: [{ was: "I go to three meetings a day", now: "I went to three meetings a day" }] });
    await this.sleep(500);
    await this.say("Three a day? No wonder you sound tired. Which one went best?");
    this.tick(2); this.done();
    await this.sleep(2600);
  }
}

export { NwCall };
