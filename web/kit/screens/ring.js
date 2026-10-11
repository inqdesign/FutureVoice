/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc, icon, wordsHTML, mmss } from "../core.js";

/* ═══════════════════════════ <nw-ring> — the daily call ═══════════════════════════
 * The AlarmKit alert as it rings on a locked phone (DailyCallAlarm): the title is the caller
 * (`voiceDisplayName` — "Future <name>", never localised), the app name under the clock, the
 * secondary button "Answer" (tint = accent, text green; the phone.fill glyph is not drawn by the
 * system — see shots/device-daily-call.jpg) and the system's own "slide to stop", which is how a
 * call is declined. Then the call it opens.
 *
 *   ring.answer() → the <nw-call> it opens (lang follows the page)
 * Beats: 1 ring · 2 answer · 3 the call's first question · 4 declined → the next time rings anyway
 * (a decline settles nothing while a later slot is left today — DailyCallStore.times). */

const ALARM = '<svg viewBox="0 0 28 28" aria-hidden="true"><g fill="currentColor"><path d="M4.1 8.6a4.6 4.6 0 0 1 6.4-5.9A11.2 11.2 0 0 0 4.1 8.6zM23.9 8.6a4.6 4.6 0 0 0-6.4-5.9 11.2 11.2 0 0 1 6.4 5.9z"/><circle cx="14" cy="15" r="10.2"/><path d="M6.2 22.3l-2 2.5a1 1 0 0 0 1.6 1.2l2.1-2.6zM21.8 22.3l2 2.5a1 1 0 0 1-1.6 1.2l-2.1-2.6z"/></g><path d="M14 9.2V15h-4.3" fill="none" stroke="#000" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/></svg>';

class NwRing extends NwScreen {
  static poses = ["ring", "answered", "again"];
  constructor() {
    super(`
      :host(.lit) .sb .st{color:#fff}
      :host(.lit) .sb svg g,:host(.lit) .sb svg path{fill:#fff}
      :host(.lit) .sb .bat{border-color:rgba(255,255,255,.4)} :host(.lit) .sb .bat i{background:#fff}
      .lock{position:absolute;inset:0;z-index:2;background:#000;color:#fff;transition:opacity .5s}
      .lock.off{opacity:0;pointer-events:none}
      .alert{transition:opacity .45s}
      .alert.off{opacity:0}
      .who{position:absolute;left:0;right:0;top:165px;height:36px;display:flex;justify-content:center;align-items:center;gap:10px;font-size:29px;font-weight:500;letter-spacing:.2px;color:#9E9EA0}
      .who svg{width:31px;height:31px;color:#9E9EA0}
      .clock{position:absolute;left:0;right:0;top:210px;text-align:center;font-family:ui-rounded,"SF Pro Rounded",var(--sans);font-size:153px;font-weight:700;letter-spacing:-5px;line-height:162px;transition:opacity .3s}
      .app{position:absolute;left:0;right:0;top:386px;text-align:center;font-size:15px;line-height:20px;color:rgba(255,255,255,.62)}
      .ans{position:absolute;left:16px;right:16px;top:578px;height:104px;border-radius:52px;background:#3F8EF7;display:grid;place-items:center;font-size:27px;font-weight:500;color:#5FD36C;transition:transform .2s,filter .2s}
      .ans.tap{transform:scale(.97);filter:brightness(.9)}
      .stop{position:absolute;left:16px;right:16px;top:707px;height:102px;border-radius:51px;background:#191919;overflow:hidden}
      .stop span{position:absolute;left:118px;top:0;bottom:0;display:flex;align-items:center;font-size:22px;letter-spacing:.2px;color:#8E8E93;transition:opacity .3s}
      .knob{position:absolute;left:2px;top:2px;width:98px;height:98px;border-radius:50%;background:radial-gradient(circle at 50% 60%,#2A2A2A,#202020 70%);box-shadow:inset 1.5px 1.5px 0 rgba(90,170,255,.55),inset 0 0 6px rgba(90,170,255,.12);display:grid;place-items:center;transition:transform .7s cubic-bezier(.45,0,.2,1)}
      .knob i{width:33px;height:33px;border-radius:6px;background:#fff}
      .stop.slid .knob{transform:translateX(270px)}
      .stop.slid span{opacity:0}
      nw-call{position:absolute;inset:0;width:100%;height:100%;opacity:0;transition:opacity .5s}
      nw-call.on{opacity:1}
    `, `
      <nw-call class="call"></nw-call>
      <div class="lock">
        <div class="clock">8:00</div>
        <div class="alert">
          <div class="who">${ALARM}<span class="nm"></span></div>
          <div class="app">nawana</div>
          <div class="ans"></div>
          <div class="stop"><div class="knob"><i></i></div><span class="sts"></span></div>
        </div>
      </div>`);
  }
  stop() { super.stop(); this.shadowRoot?.querySelector("nw-call")?.stop(); }
  build() {
    const ko = this.t === STR.ko;
    this.$(".nm").textContent = this.getAttribute("caller") || "Future Jiwoo";   // the app shows "Future <name>"; a sample name in public material
    this.$(".ans").textContent = ko ? "받기" : "Answer";
    this.$(".sts").textContent = ko ? "밀어서 중단" : "slide to stop";   // the system's own button: ClockAngel.app SLIDE_TO_STOP (iOS 26.2 ko/en)
    this.$("nw-call").setAttribute("lang", ko ? "ko" : "en");
    this.reset();
  }
  _dark(on) { this.closest("nw-phone")?.toggleAttribute("dark", on); this.classList.toggle("lit", on); }
  _ringing(time) {
    this.$(".lock").classList.remove("off"); this.$(".alert").classList.remove("off");
    this.$(".stop").classList.remove("slid"); this.$(".clock").textContent = time;
    this._dark(true);
  }
  reset() {
    this.$("nw-call").classList.remove("on");
    this._ringing("8:00");
    const c = this.$("nw-call"); if (c._built) c.reset();
  }
  async answer() {
    const a = this.$(".ans"); a.classList.add("tap"); await this.sleep(260); a.classList.remove("tap");
    const c = this.$("nw-call"); c.stop(); c.reset(); c.classList.add("on"); this.$(".lock").classList.add("off");
    this._dark(false);
    return c;
  }
  async pose(name) {
    this.stop(); this.reset();
    const c = this.$("nw-call");
    if (name === "ring") this._ringing("12:08");               // shots/device-daily-call.jpg
    else if (name === "again") this._ringing("13:00");
    else if (name === "answered") {
      if (this.hasAttribute("static")) c.setAttribute("static", "");
      c.reset(); c.classList.add("on"); this.$(".lock").classList.add("off"); this._dark(false);
      await c.pose("speaking");
      const b = c.shadowRoot.querySelector(".ln .bub"); if (b) b.textContent = "Morning! You had the interview yesterday, right? How did it go?";
      c._follow();
    }
  }
  async demo() {
    const c = this.$("nw-call");
    this.beat(1); await this.sleep(2200);
    this.beat(2); await this.answer(); await this.sleep(500);
    this.beat(3);
    await c.say("Morning! You had the interview yesterday, right? How did it go?");
    await c.listen(); await this.sleep(1500);
    await c.user("It went really well, I think!");
    await c.say("I knew it. What was the hardest question?");
    c.done(); await this.sleep(1600);
    // Another morning: they slide it away. Nothing nags — the next time they set rings anyway.
    this.beat(4);
    c.classList.remove("on"); this._ringing("8:00");
    await this.sleep(1300);
    this.$(".stop").classList.add("slid"); await this.sleep(800);
    this.$(".alert").classList.add("off"); await this.sleep(1100);
    this.$(".clock").textContent = "13:00"; await this.sleep(500);
    this.$(".stop").classList.remove("slid"); this.$(".alert").classList.remove("off");
    await this.sleep(2600);
  }
}

export { NwRing };
