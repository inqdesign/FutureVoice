/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* ═══════════════════════════ <nw-voice> — making the voice ═══════════════════════════
 * VoiceCloneOnboardingView, three of its acts in the default blue theme, light mode, laid out from
 * `-onboardingPreview voice -cloneStage recording|uploading|meet` captures (iPhone 17 Pro):
 *   recording  "It's listening": the mosaic orb inside a red progress ring, the timer, the script
 *   uploading  "Becoming you": the orb thinking, one line about what it is doing
 *   meet       "Meet your fluent self": play the greeting, then the colour row, the pace pills
 *              and the accent pills (`accentSection`), and "Save this voice"
 * Beats: 1 recording · 2 making · 3 hearing it · 4 picking the accent. */

const PLAY = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4.5v15l12.5-7.5z" fill="currentColor"/></svg>';
const WAVE = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10v4M8 7v10M12 4v16M16 8v8M20 10v4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
const RESTART = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12a7 7 0 1 0 2.1-5M5 4v4h4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

const L = {
  ko: {
    listening: "듣고 있어요", making: "나를 익히는 중", meet: "유창해진 나와 만나기",
    script: ["안녕하세요. 저와 똑같은 목소리로, 훨씬 더 유창하게 말하는 제가 생긴다니 조금 신기하네요. 저는 궁금한 게 많고, 참을성도 있는 편이에요. 지금보다 조금만 더 당당한 저였으면 좋겠어요.",
      "이번 주에 있었던 일을 하나 이야기해 볼게요. 날씨가 생각보다 쌀쌀해져서 옷깃을 여미고 걸었어요. 걷다가 문득, 눈에 보이는 것과 마음에 떠오르는 생각이 서로 다른 말이라는 걸 느꼈어요."],
    restart: "처음부터", more: n => `계속 읽어 주세요. ${n}초만 더요`,
    steps: ["한 마디씩 다시 듣는 중…", "모음을 익히는 중…", "내 목소리를 만드는 중…"], half: "30초쯤 걸려요.", cloning: "목소리를 만드는 중…",
    mine: "내 목소리", tutor: "AI 튜터", notMe: "내 목소리 같지 않나요?",
    you: "유창해진 나예요.", pick: "유창해진 나의 모습과 말하는 속도를 골라요.",
    themes: ["블루", "모노", "에메랄드", "앰버", "코랄", "아쿠아"],
    pace: ["보통", "여유있게", "천천히"], accent: "억양", accents: ["그대로", "미국식", "영국식", "호주식"],
    later: "둘 다 나중에 설정에서 바꿀 수 있어요.", save: "이 목소리 저장하기",
    hello: "안녕, 나야. 몇 년 뒤의 너. 이제 영어로 편하게 말해.",
  },
  en: {
    listening: "It's listening", making: "Becoming you", meet: "Meet your fluent self",
    script: ["Hi. I'm recording this so my fluent self can sound like me. I'm curious. I'm patient. I want to sound like me — just a more confident version.",
      "Let me describe a moment from this week. The weather turned cooler than I expected. I was walking and caught myself thinking in two languages at once."],
    restart: "Start over", more: n => `Keep going — ${n}s more`,
    steps: ["Listening back to every word…", "Learning your vowels…", "Building your voice…"], half: "About half a minute.", cloning: "Cloning your voice…",
    mine: "My voice", tutor: "AI tutor", notMe: "Doesn't sound like you?",
    you: "It's you — fluent.", pick: "Pick how your fluent self looks and sounds.",
    themes: ["Blue", "Mono", "Emerald", "Amber", "Coral", "Aqua"],
    pace: ["Normal", "Relaxed", "Slow"], accent: "Accent", accents: ["Original", "American", "British", "Australian"],
    later: "You can change both later in settings.", save: "Save this voice",
    hello: "Hey, it's me. You, a few years on. Fluent now.",
  },
};
/* the colour row's swatches: the theme's two cells on the light ground (FutureselfTheme) */
const THEMES = [["#2F6BFF", "#9CC0FF"], ["#7A7A7E", "#E8E8EA"], ["#1E8F5E", "#7BE0B0"], ["#E07B1F", "#FFC062"], ["#D8344A", "#FF9AA6"], ["#1F9DB3", "#86E6F5"]];

class NwVoice extends NwScreen {
  static poses = ["recording", "making", "meet"];
  constructor() {
    super(`
      :host{background:#fff;color:#000;--vb:#0A5CF5;--vbd:#D6E4FB}
      .ttl{position:absolute;left:0;right:0;top:82px;text-align:center;font-family:var(--pixel);font-size:29px;line-height:36px;letter-spacing:0}
      .act{position:absolute;inset:0;opacity:0;transition:opacity .5s ease}
      .act.on{opacity:1}
      /* recording */
      .orbw{position:absolute;left:111px;top:146px;width:180px;height:180px}
      .orbw nw-futureself{position:absolute;left:12px;top:12px;width:156px;height:156px}
      .orbw svg{position:absolute;inset:0;width:100%;height:100%;transform:rotate(-90deg)}
      .orbw circle{fill:none;stroke-width:5}
      .orbw .tr{stroke:#E5E5EA} .orbw .pr{stroke:#FF3B30;stroke-linecap:round;transition:stroke-dashoffset .9s linear}
      .tm{position:absolute;left:0;right:0;top:323px;text-align:center;font-family:var(--pixel);font-size:16px;color:#8E8E93;font-variant-numeric:tabular-nums}
      .scr{position:absolute;left:26px;right:26px;top:384px;height:356px;overflow:hidden;font-size:18.5px;line-height:28px;letter-spacing:-.3px;word-break:keep-all;-webkit-mask:linear-gradient(#000 78%,transparent)}
      .scr p{margin:0 0 14px}
      .scr .w{color:#B9BDC6;transition:color .25s}
      .scr .w.on{color:#000}
      .bot{position:absolute;left:0;right:0;bottom:0;height:126px;background:#F7F7F9}
      .btn{position:absolute;left:16px;right:16px;top:20px;height:50px;border-radius:25px;display:flex;align-items:center;justify-content:center;gap:8px;font-size:17px;font-weight:500}
      .btn svg{width:19px;height:19px}
      .r-btn{background:var(--vbd);color:var(--vb)}
      .bnote{position:absolute;left:0;right:0;top:80px;text-align:center;font-size:12.5px;color:#8E8E93}
      /* making */
      .mk{position:absolute;left:131px;top:158px;width:140px;height:140px}
      .mkl{position:absolute;left:0;right:0;top:396px;text-align:center;font-size:18px;color:#8E8E93;transition:opacity .35s}
      .mkl.fade{opacity:0}
      .mks{position:absolute;left:0;right:0;top:428px;text-align:center;font-size:11.5px;color:#AEAEB2}
      .m-btn{background:#F2F2F7;color:#C7C7CC;top:28px;height:48px;left:24px;right:24px}
      /* meet */
      .seg{position:absolute;left:24px;right:24px;top:142px;height:31px;border-radius:16px;background:#EBEBEE;display:flex;padding:2px}
      .seg span{flex:1;display:grid;place-items:center;font-size:13.5px;font-weight:500;border-radius:14px}
      .seg span.on{background:#fff;box-shadow:0 1px 4px rgba(0,0,0,.12)}
      .play{position:absolute;left:134px;top:199px;width:134px;height:134px;cursor:default}
      .play nw-futureself{width:100%;height:100%}
      .play .pl{position:absolute;inset:0;display:grid;place-items:center;color:var(--vb);transition:opacity .3s}
      .play .pl svg{width:34px;height:34px}
      .play.on .pl{opacity:0}
      .nm{position:absolute;left:0;right:0;top:362px;display:flex;justify-content:center;align-items:center;gap:7px;color:var(--vb);font-size:13px}
      .nm svg{width:15px;height:15px}
      .cap{position:absolute;left:30px;right:30px;top:362px;text-align:center;font-size:14px;line-height:20px;color:#000;opacity:0;transition:opacity .35s}
      .cap.on{opacity:1}
      .you{position:absolute;left:0;right:0;top:412px;text-align:center;font-size:21px;font-weight:700;letter-spacing:-.4px}
      .pick{position:absolute;left:40px;right:40px;top:448px;text-align:center;font-size:14.5px;line-height:20px;color:#8E8E93;word-break:keep-all}
      .th{position:absolute;left:24px;right:24px;top:499px;display:flex;justify-content:space-between}
      .th div{width:56px;display:flex;flex-direction:column;align-items:center;gap:8px;font-size:11.5px;color:#8E8E93}
      .th i{width:40px;height:40px;border-radius:50%;background:#EDEDF0;position:relative;overflow:hidden;box-shadow:inset 0 0 0 .5px rgba(60,60,67,.18)}
      .th i::before{content:"";position:absolute;left:16px;top:9px;width:8px;height:8px;background:var(--hi)}
      .th i::after{content:"";position:absolute;left:16px;top:18px;width:8px;height:8px;background:var(--lo)}
      .th div.on{color:#000;font-weight:600} .th div.on i{box-shadow:0 0 0 2.5px var(--vb);background:#9CC0FF}
      .pills{position:absolute;left:24px;right:24px;display:flex;gap:8px}
      .pills span{flex:1;height:31px;border-radius:16px;background:var(--vbd);color:var(--vb);display:grid;place-items:center;font-size:14.5px;transition:background .25s,color .25s,transform .18s;white-space:nowrap}
      .pills span.on{background:var(--vb);color:#fff}
      .pills span.tap{transform:scale(.95)}
      .pills span.load{animation:pulse .8s ease-in-out infinite}
      @keyframes pulse{50%{opacity:.5}}
      .pace{top:586px}
      .pace span{height:31px}
      .acl{position:absolute;left:0;right:0;top:638px;text-align:center;font-size:12.5px;color:#8E8E93}
      .acc{top:663px}
      .acc span{height:29px;font-size:14px}
      .s-note{position:absolute;left:0;right:0;top:14px;text-align:center;font-size:11.5px;color:#AEAEB2}
      .s-btn{background:var(--vb);color:#fff;top:34px;height:50px;transition:transform .18s,filter .18s}
      .s-btn.tap{transform:scale(.97);filter:brightness(.9)}
    `, `
      <div class="act rec">
        <div class="ttl t-rec"></div>
        <div class="orbw"><nw-futureself shape="circle" mode="listening" level="0.4"></nw-futureself>
          <svg viewBox="0 0 180 180"><circle class="tr" cx="90" cy="90" r="86"/><circle class="pr" cx="90" cy="90" r="86"/></svg></div>
        <div class="tm">0:00</div>
        <div class="scr"></div>
        <div class="bot"><div class="btn r-btn">${RESTART}<span class="t-restart"></span></div><div class="bnote"></div></div>
      </div>
      <div class="act mak">
        <div class="ttl t-mak"></div>
        <nw-futureself class="mk" shape="circle" mode="thinking"></nw-futureself>
        <div class="mkl"></div><div class="mks"></div>
        <div class="bot"><div class="btn m-btn">${WAVE}<span class="t-cloning"></span></div></div>
      </div>
      <div class="act met">
        <div class="ttl t-met"></div>
        <div class="seg"><span class="on t-mine"></span><span class="t-tutor"></span></div>
        <div class="play"><nw-futureself shape="circle" mode="idle" level="0"></nw-futureself><div class="pl">${PLAY}</div></div>
        <div class="nm">${WAVE}<span class="t-notme"></span></div>
        <div class="cap"></div>
        <div class="you"></div><div class="pick"></div>
        <div class="th"></div>
        <div class="pills pace"></div>
        <div class="acl"></div>
        <div class="pills acc"></div>
        <div class="bot"><div class="s-note"></div><div class="btn s-btn"><span class="t-save"></span></div></div>
      </div>`);
  }
  get l() { return this.t === STR.ko ? L.ko : L.en; }
  build() {
    const l = this.l, set = (s, v) => { this.$(s).textContent = v; };
    set(".t-rec", l.listening); set(".t-mak", l.making); set(".t-met", l.meet);
    set(".t-restart", l.restart); set(".mks", l.half); set(".t-cloning", l.cloning);
    set(".t-mine", l.mine); set(".t-tutor", l.tutor); set(".t-notme", l.notMe);
    set(".you", l.you); set(".pick", l.pick); set(".acl", l.accent); set(".s-note", l.later); set(".t-save", l.save);
    set(".cap", l.hello);
    this.$(".scr").innerHTML = l.script.map(p => `<p>${p.split(/\s+/).map(w => `<span class="w">${esc(w)}</span>`).join(" ")}</p>`).join("");
    this.$(".th").innerHTML = l.themes.map((n, i) => `<div${i ? "" : ' class="on"'}><i style="--hi:${THEMES[i][1]};--lo:${THEMES[i][0]}"></i>${esc(n)}</div>`).join("");
    this.$(".pace").innerHTML = l.pace.map((n, i) => `<span${i === 1 ? ' class="on"' : ""}>${esc(n)}</span>`).join("");
    this.$(".acc").innerHTML = l.accents.map((n, i) => `<span${i ? "" : ' class="on"'}>${esc(n)}</span>`).join("");
    const C = 2 * Math.PI * 86; this._C = C;
    this.$(".pr").style.strokeDasharray = C;
    this.reset();
  }
  _act(name) { for (const a of ["rec", "mak", "met"]) this.$("." + a).classList.toggle("on", a === name); }
  _ring(p) { this.$(".pr").style.strokeDashoffset = this._C * (1 - p); }
  _time(s) { this.$(".tm").textContent = `0:${String(s).padStart(2, "0")}`; this.$(".bnote").textContent = this.l.more(Math.max(0, 60 - s)); }
  reset() {
    this._act("rec"); this._ring(0); this._time(0);
    this.$$(".scr .w").forEach(w => w.classList.remove("on")); this.$(".scr").scrollTop = 0;
    this.$(".mkl").textContent = this.l.steps[0];
    this.$(".play").classList.remove("on"); this.$(".play nw-futureself").setAttribute("mode", "idle");
    this.$(".cap").classList.remove("on"); this.$(".nm").style.opacity = 1;
    this.$$(".acc span").forEach((s, i) => { s.classList.toggle("on", i === 0); s.classList.remove("load", "tap"); });
  }
  async tap(el) { el.classList.add("tap"); await this.sleep(180); el.classList.remove("tap"); }
  async demo() {
    const l = this.l;
    // 1 · recording: the ring fills while the script is read
    this.beat(1); this._act("rec");
    const words = this.$$(".scr .w"), secs = 47;
    for (let i = 0; i < words.length; i++) {
      await this.sleep(105);
      words[i].classList.add("on");
      const p = (i + 1) / words.length;
      this._ring(p * .78); this._time(Math.round(p * secs));
      const scr = this.$(".scr"), top = words[i].offsetTop;
      if (top > scr.scrollTop + 230) scr.scrollTop = top - 120;
    }
    await this.sleep(600);
    // 2 · making the voice
    this.beat(2); this._act("mak");
    for (const s of l.steps) {
      const el = this.$(".mkl"); el.classList.add("fade"); await this.sleep(300);
      el.textContent = s; el.classList.remove("fade"); await this.sleep(1300);
    }
    // 3 · meet: the greeting, in your own voice
    this.beat(3); this._act("met"); await this.sleep(900);
    const play = this.$(".play"); await this.tap(play);
    play.classList.add("on"); play.querySelector("nw-futureself").setAttribute("mode", "speaking");
    play.querySelector("nw-futureself").setAttribute("level", "voice");
    this.$(".nm").style.opacity = 0; this.$(".cap").classList.add("on");
    await this.sleep(2800);
    play.querySelector("nw-futureself").setAttribute("mode", "idle");
    this.$(".cap").classList.remove("on"); this.$(".nm").style.opacity = 1;
    // 4 · pick an accent: the same voice, told to speak British
    this.beat(4); await this.sleep(500);
    const acc = this.$$(".acc span"), br = acc[2];
    await this.tap(br); br.classList.add("load"); await this.sleep(1300);
    acc.forEach(s => s.classList.remove("on")); br.classList.remove("load"); br.classList.add("on");
    play.classList.add("on"); play.querySelector("nw-futureself").setAttribute("mode", "speaking");
    await this.sleep(2200);
    play.querySelector("nw-futureself").setAttribute("mode", "idle"); play.classList.remove("on");
    await this.sleep(600);
    await this.tap(this.$(".s-btn")); await this.sleep(1400);
  }
  async pose(name) {
    this.stop(); this.reset();
    if (name === "making") { this._act("mak"); return; }
    if (name === "meet") { this._act("met"); return; }
    this.$$(".scr .w").slice(0, 40).forEach(w => w.classList.add("on")); this._ring(.6); this._time(47);
  }
}

export { NwVoice };
