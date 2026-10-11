/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc } from "../core.js";

/* ═══════════════════════════ <nw-words> — the word cloud ═══════════════════════════
 * VocabularyView.swift: the level's words packed into a cloud (21pt rounded semibold at one level),
 * faded by an elliptical vignette; a word the learner has used or knows goes `.secondary` regular
 * with a green check at its leading top corner (bookmark = studying). The notebook sheet rests at
 * its 220pt peek: bookmark · check | "My words · N" | up · down, then headword, part of speech and
 * the first meaning. Positions are read off the simulator capture (B1, iPhone 17). */

const SF = {
  back: '<path d="M15 4.5L7.5 12l7.5 7.5" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>',
  filter: '<circle cx="12" cy="12" r="9.6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M7.3 8.9h9.4M8.9 12.2h6.2M10.6 15.5h2.8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  bookmarkFill: '<path d="M6.3 2.8h11.4c.8 0 1.4.6 1.4 1.4v16.3c0 .7-.8 1.1-1.4.7L12 17.1l-5.7 4.1c-.6.4-1.4 0-1.4-.7V4.2c0-.8.6-1.4 1.4-1.4z" fill="currentColor"/>',
  bookmark: '<path d="M6.5 3.6h11c.6 0 1 .4 1 1v15.3c0 .5-.6.8-1 .5L12 16.6l-5.5 3.8c-.4.3-1 0-1-.5V4.6c0-.6.4-1 1-1z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  check: '<circle cx="12" cy="12" r="9.6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M7.6 12.3l3 3.1 5.8-6.6" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
  checkFill: '<circle cx="12" cy="12" r="10.4" fill="currentColor"/><path d="M7.6 12.3l3 3.1 5.8-6.6" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>',
  up: '<path d="M4.5 16L12 8.5l7.5 7.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
  down: '<path d="M4.5 8.5L12 16l7.5-7.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
  tick: '<path d="M3.5 12.8l5.5 5.5L20.5 6" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>',
};
const sf = n => `<svg class="g" viewBox="0 0 24 24" aria-hidden="true">${SF[n]}</svg>`;

/* The B1 cloud as the capture shows it — centre x, y in points. Rows below y≈620 sit under the sheet. */
const CLOUD = [
  ["bet", 212, 133], ["improvement", 330, 139], ["severe", 34, 158], ["needle", 130, 175], ["administration", 349, 198],
  ["compound", 60, 223], ["guarantee", 182, 224], ["curiously", 31, 280], ["substantial", 178, 302], ["mud", 293, 288],
  ["mount", 376, 282], ["neighborhood", 63, 347], ["heel", 190, 363], ["heal", 266, 375], ["builder", 364, 365],
  ["disabled", 32, 436], ["salesman", 150, 443], ["storyteller", 291, 435], ["inject", 391, 451], ["register", 31, 518],
  ["clip", 129, 501], ["operation", 227, 505], ["companion", 347, 518], ["tremendous", 40, 586], ["latecomer", 195, 579],
  ["forbidden", 319, 572], ["overwhelmed", 52, 655], ["negotiate", 196, 648], ["genuinely", 336, 662],
  ["deadline", 22, 728], ["commute", 158, 736], ["landlord", 280, 724], ["chore", 392, 733],
  ["exhausting", 96, 806], ["boiler", 238, 798], ["sublet", 352, 812],
];
const CX = 201, CY = 480, HX = 201, HY = 365;   // the vignette's ellipse, fitted to the capture
const hash = s => { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0; return h; };

const CARDS = {
  exhausting: { ko: ["형용사", "매우 피곤하게 만드는, 기진맥진하게 하는"], en: ["adjective", "making you feel extremely tired"], studying: true },
  substantial: { ko: ["형용사", "상당한, (양·가치·중요성이) 큰"], en: ["adjective", "large in size, value or importance"], studying: false },
};

class NwWords extends NwScreen {
  static poses = ["cloud"];
  constructor() {
    super(`
      :host{--acc:#0A5CF5;--sys:#0088FF;--green:#34C759}
      .g{width:1em;height:1em;display:block;flex:0 0 auto}
      .nav{position:absolute;left:0;right:0;top:62px;height:44px;z-index:3}
      .nav .c{position:absolute;left:0;right:0;top:0;line-height:44px;text-align:center;font-family:var(--pixel);font-size:17px;letter-spacing:0}
      .nav .l,.nav .r{position:absolute;top:0;width:44px;height:44px;border-radius:22px;background:rgba(253,253,253,.94);box-shadow:0 1px 14px rgba(0,0,0,.07),inset 0 0 0 .5px rgba(0,0,0,.04);display:grid;place-items:center;color:var(--acc)}
      .nav .l{left:16px;font-size:24px}.nav .r{right:16px;font-size:25px}
      .cloud{position:absolute;inset:0;overflow:hidden}
      .wd{position:absolute;white-space:nowrap;font-family:ui-rounded,"SF Pro Rounded",var(--sans);font-size:21px;line-height:25px;font-weight:600;color:#000;letter-spacing:0;transform:translate(-50%,-50%);
        transition:left 2.4s linear,top 2.4s linear,opacity 2.4s linear,color .4s,font-weight .4s}
      .wd .bd{position:absolute;left:-4px;top:-8.8px;font-size:8.8px;color:var(--green);opacity:0;transition:opacity .3s,transform .3s;transform:scale(.4)}
      .wd.used{color:#8A8A8E;font-weight:400}
      .wd.used .bd{opacity:1;transform:none}
      .wd.study .bd{opacity:1;transform:none;color:var(--sys)}
      .wd.tap{transform:translate(-50%,-50%) scale(.94);transition:transform .12s}
      .sheet{position:absolute;left:9px;right:9px;top:623px;bottom:8px;border-radius:38px 38px 54px 54px;background:rgba(252,252,252,.84);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);
        box-shadow:0 0 0 .5px rgba(0,0,0,.04),0 -4px 28px rgba(0,0,0,.06);z-index:4;transform:translateY(110%);transition:transform .55s cubic-bezier(.3,.8,.2,1)}
      .sheet.on{transform:none}
      .grab{position:absolute;left:50%;top:3.5px;width:36px;height:5px;margin-left:-18px;border-radius:3px;background:#BABABD}
      .cap{position:absolute;top:14px;height:44px;border-radius:22px;background:rgba(236,236,236,.75);display:flex;align-items:center;justify-content:space-around;font-size:22px}
      .cap.lead{left:15px;width:96px}.cap.trail{right:15px;width:95px}
      .cap .bm{color:var(--sys);font-size:20px}
      .cap .ck{color:#6C6C6C;font-size:25px;transition:color .3s}
      .cap .ck.on{color:var(--green)}
      .cap .up{color:#A9A9A9}.cap .dn{color:var(--acc)}
      .ttl{position:absolute;left:111px;right:111px;top:14px;line-height:44px;text-align:center;font-family:var(--pixel);font-size:17px;letter-spacing:0}
      .body{position:absolute;left:22px;right:22px;top:71px;transition:opacity .2s}
      .body h4{margin:0;font-family:ui-rounded,"SF Pro Rounded",var(--sans);font-size:30px;line-height:36px;font-weight:700;letter-spacing:0}
      .body .pos{margin-top:0;font-size:15px;line-height:20px;color:#8A8A8E}
      .body p{margin:7px 0 0;font-size:17px;line-height:22px;letter-spacing:-.3px}
    `, `
      <div class="cloud"></div>
      <div class="nav"><span class="l">${sf("back")}</span><span class="c">B1 · 16 / 2113</span><span class="r">${sf("filter")}</span></div>
      <div class="sheet on"><div class="grab"></div>
        <div class="cap lead"><span class="bm"></span><span class="ck">${sf("check")}</span></div>
        <div class="ttl"></div>
        <div class="cap trail"><span class="up">${sf("up")}</span><span class="dn">${sf("down")}</span></div>
        <div class="body"><h4></h4><div class="pos"></div><p></p></div></div>`);
  }
  build() {
    this.$(".cloud").innerHTML = CLOUD.map(([w]) => `<span class="wd" data-w="${w}"><span class="bd">${sf("tick")}</span>${esc(w)}</span>`).join("");
    this.$(".ttl").textContent = this.t === STR.ko ? "내 단어 · 9" : "My words · 9";
    this.reset();
  }
  /* Parallax pan, as cloud(in:) does it: offset from the centre scaled by a per-word depth (0.9–1.1). */
  place(px = 0, py = 0) {
    for (const el of this.$$(".wd")) {
      const [w, x, y] = CLOUD.find(c => c[0] === el.dataset.w);
      const d = .9 + (hash(w) % 1000) / 1000 * .2;
      const sx = x + px * d, sy = y + py * d;
      el.style.left = sx + "px"; el.style.top = sy + "px";
      el.style.opacity = Math.max(0, Math.min(1, 1.25 - Math.hypot((sx - CX) / HX, (sy - CY) / HY))).toFixed(3);
    }
  }
  card(word) {
    const c = CARDS[word], ko = this.t === STR.ko;
    this.$(".body h4").textContent = word;
    [this.$(".body .pos").textContent, this.$(".body p").textContent] = ko ? c.ko : c.en;
    this.$(".bm").innerHTML = sf(c.studying ? "bookmarkFill" : "bookmark");
    this.$(".bm").style.color = c.studying ? "" : "#6C6C6C";
    this.$(".ck").classList.remove("on"); this.$(".ck").innerHTML = sf("check");
  }
  reset() {
    this.$$(".wd").forEach(w => { w.style.transition = "none"; w.classList.remove("used", "tap"); });
    this.place(0, 0); void this.$(".cloud").offsetWidth;
    this.$$(".wd").forEach(w => w.style.transition = "");
    this.card("exhausting");
    this.$(".sheet").classList.add("on");
  }
  async pose(name) { this.stop(); this.reset(); }
  async demo() {
    await this.sleep(500);
    this.place(14, 22);                                  // the learner drags the cloud a little
    await this.sleep(1000);
    this.beat(1);                                        // words said in talks get the check
    for (const w of ["guarantee", "storyteller", "operation"]) { this.$(`[data-w="${w}"]`).classList.add("used"); await this.sleep(480); }
    await this.sleep(700); this.beat(2);                 // a word opens on the card
    const e = this.$('[data-w="substantial"]');
    e.classList.add("tap"); await this.sleep(140); e.classList.remove("tap");
    const b = this.$(".body"); b.style.opacity = 0; await this.sleep(180); this.card("substantial"); b.style.opacity = 1;
    await this.sleep(1500);
    this.beat(3);                                        // check = known
    const ck = this.$(".ck"); ck.innerHTML = sf("checkFill"); ck.classList.add("on"); e.classList.add("used");
    await this.sleep(2600);
  }
}

export { NwWords };
