/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* ═══════════════════════════ <nw-watch> — your own situation, then the scene ═══════════════════════════
 * The box: ScenarioComposerSheet.customBox (Mode.custom) as the sheet it is — pixel nav title, Cancel,
 * the CTA circle in the header, heading + note, SituationReel rolling through the empty middle
 * (80pt rows, 4.5 s a row, faded top and bottom), then the box: material chips, the files note,
 * SpeakOrTypeField with + · the person chip on the left and the dictation language · mic on the right.
 * The scene: WatchView — "Watching" + level, counterpart · place, title, blurb, DialogueLine rows
 * (current line ringed), "Shadow this" / "Save phrase" under each, and the bar (Restart · Pause while
 * playing, Watch again · Study this at the end).
 *   poses: composer-attached (shots/device-composer-attached.jpg) · dictating · scene (real/scene-end.png) · playing */

const SY = {
  plus: '<svg viewBox="0 0 20 20" width="20" height="20"><path d="M10 2.8v14.4M2.8 10h14.4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  mic: '<svg viewBox="0 0 14 20" width="14" height="20"><rect x="3.6" y="0.6" width="6.8" height="12.2" rx="3.4" fill="currentColor"/><path d="M1.2 8.6a5.8 5.8 0 0 0 11.6 0M7 14.4v3.6M4.2 18.6h5.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  stop: '<svg viewBox="0 0 14 14" width="13" height="13"><rect x="1" y="1" width="12" height="12" rx="2.2" fill="currentColor"/></svg>',
  doc: '<svg viewBox="0 0 12 15" width="11" height="14"><g fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"><path d="M2.2.9h4.9l3.9 3.9v8.1c0 .7-.5 1.2-1.2 1.2H2.2c-.7 0-1.2-.5-1.2-1.2V2.1C1 1.4 1.5.9 2.2.9z"/><path d="M7 1v3.8h3.9" /><path d="M3.4 8h5.2M3.4 10.4h5.2" stroke-linecap="round"/></g></svg>',
  x: '<svg viewBox="0 0 10 10" width="9" height="9"><path d="M1.5 1.5l7 7M8.5 1.5l-7 7" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  updown: '<svg viewBox="0 0 9 15" width="8" height="13"><path d="M1.5 5.2L4.5 2l3 3.2M1.5 9.8l3 3.2 3-3.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  playFill: '<svg viewBox="0 0 16 18" width="17" height="19"><path d="M2 2.3v13.4c0 1 1 1.6 1.9 1.1l11-6.7c.8-.5.8-1.7 0-2.2l-11-6.7C3 .7 2 1.3 2 2.3z" fill="currentColor"/></svg>',
  chev: '<svg viewBox="0 0 6 10" width="5" height="9"><path d="M1 1l4 4-4 4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  // waveform.badge.mic
  wavemic: '<svg viewBox="0 0 16 16" width="15" height="15"><g fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round"><path d="M1 6.5v3M3.5 4v8M6 2v12M8.5 4.5v7"/></g><rect x="10.4" y="7" width="3.2" height="5" rx="1.6" fill="currentColor"/><path d="M9.4 10.6a2.6 2.6 0 0 0 5.2 0M12 13.2v1.6" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>',
  // plus.circle
  pluscircle: '<svg viewBox="0 0 16 16" width="14" height="14"><circle cx="8" cy="8" r="7" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M8 4.6v6.8M4.6 8h6.8" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>',
  // arrow.counterclockwise
  again: '<svg viewBox="0 0 20 22" width="18" height="20"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5.2 6.6A7.6 7.6 0 1 1 3 12.6"/><path d="M5.6 1.8v5h5"/></g></svg>',
  // books.vertical.fill
  books: '<svg viewBox="0 0 22 20" width="21" height="19"><g fill="currentColor"><rect x="1" y="3" width="5" height="16" rx="1"/><rect x="7.2" y="1" width="5" height="18" rx="1"/><path d="M13.6 3.6l3.9-1 3.6 15.4-3.9 1z"/></g><g fill="#fff" opacity=".9"><rect x="2" y="6" width="3" height="1.4"/><rect x="8.2" y="4" width="3" height="1.4"/></g></svg>',
  // backward.end.fill
  restart: '<svg viewBox="0 0 18 16" width="16" height="15"><rect x="1" y="1.5" width="2.6" height="13" rx="1" fill="currentColor"/><path d="M16.6 2.4v11.2c0 .9-1 1.4-1.7.9L6 8.9c-.6-.4-.6-1.4 0-1.8l8.9-5.6c.7-.5 1.7 0 1.7.9z" fill="currentColor"/></svg>',
  pause: '<svg viewBox="0 0 14 16" width="13" height="15"><rect x="1" y="1" width="4.2" height="14" rx="1.2" fill="currentColor"/><rect x="8.8" y="1" width="4.2" height="14" rx="1.2" fill="currentColor"/></svg>',
};

class NwWatch extends NwScreen {
  constructor() {
    super(`
      :host{background:#C1C0C5;--acc:#0A5CF5;--sec:rgba(60,60,67,.6);--ter:rgba(60,60,67,.3);--fillT:rgba(118,118,128,.12)}
      .gl{position:absolute;height:44px;min-width:44px;padding:0 15px;border-radius:22px;background:rgba(255,255,255,.92);box-shadow:0 6px 22px rgba(0,0,0,.07),0 1px 3px rgba(0,0,0,.04);display:flex;align-items:center;justify-content:center;font-size:17px;letter-spacing:-.4px;color:var(--acc);z-index:4}
      /* ── the box (a sheet over Watch) ── */
      .l-box{background:#C1C0C5}
      .sht{position:absolute;left:0;right:0;top:62px;bottom:0;border-radius:38px 38px 0 0;background:#F2F2F7;overflow:hidden}
      .sht .gl.cn{left:15px;top:16px}
      .sht .nt{position:absolute;left:0;right:0;top:16px;height:44px;display:flex;align-items:center;justify-content:center;font-family:var(--pixel);font-size:17px;letter-spacing:0}
      .cta{position:absolute;right:17px;top:16px;width:44px;height:44px;border-radius:22px;display:grid;place-items:center;background:#BEBEC2;color:rgba(255,255,255,.95);transition:background .3s,transform .15s;z-index:4}
      .cta svg{margin-left:3px}
      .cta.on{background:var(--acc);color:#fff}
      .cta.tap{transform:scale(.92)}
      .hd{position:absolute;left:32px;right:32px;top:89px;text-align:center;word-break:keep-all}
      .hd b{display:block;font-size:20px;line-height:25px;font-weight:600;letter-spacing:-.3px}
      .hd p{margin:6px 0 0;font-size:15px;line-height:20px;color:var(--sec);letter-spacing:-.2px}
      .reel{position:absolute;left:0;right:0;top:254.5px;height:240px;overflow:hidden;-webkit-mask-image:linear-gradient(transparent,#000 33.3%,#000 66.7%,transparent);mask-image:linear-gradient(transparent,#000 33.3%,#000 66.7%,transparent);transition:opacity .25s}
      .reel.off{opacity:0}
      .reel .tr{transform:translateY(-94.5px);animation:roll 27s linear infinite;animation-delay:-5.3s}
      @keyframes roll{from{transform:translateY(0)}to{transform:translateY(-480px)}}
      .reel .rw{word-break:keep-all;height:80px;padding:0 44px;display:flex;align-items:center;justify-content:center;text-align:center;font-size:17px;line-height:22px;color:var(--sec);letter-spacing:-.4px}
      .reel .rw span{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
      .box{position:absolute;left:12px;right:12px;bottom:46px;border-radius:24px;background:#fff;padding:6px 0}
      .chips{display:flex;gap:8px;padding:0 14px}
      .chip{display:flex;align-items:center;gap:6px;height:28px;padding:0 10px;border-radius:10px;background:var(--fillT);font-size:12px;font-weight:500;letter-spacing:0}
      .chip .d{color:var(--acc);display:flex}
      .chip .x{color:var(--sec);display:flex}
      .box.bare .chips,.box.bare .note{display:none}
      .note{word-break:keep-all;padding:0 14px;margin-top:8px;font-size:12px;line-height:16px;color:var(--sec);letter-spacing:0}
      .fld{word-break:keep-all;margin-top:8px;padding:14px;font-size:17px;line-height:22px;letter-spacing:-.4px;color:#000;min-height:50px}
      .fld.ph{color:rgba(60,60,67,.3)}
      .tools{height:44px;margin:0 14px 8px;display:flex;align-items:center;gap:8px}
      .tools .pl{width:40px;height:40px;border-radius:20px;background:var(--fillT);display:grid;place-items:center;color:var(--acc);flex:0 0 auto}
      .tools .who{height:40px;border-radius:20px;background:var(--fillT);display:flex;align-items:center;gap:6px;padding:0 12px 0 6px;font-size:15px;font-weight:500;letter-spacing:-.2px}
      .tools .av{width:28px;height:28px;border-radius:50%;background:rgba(10,92,245,.15);color:var(--acc);display:grid;place-items:center;font-size:9.5px;font-weight:600;font-style:normal}
      .tools .rec{display:none;align-items:center;gap:5px;font-size:12px;color:var(--sec);white-space:nowrap;letter-spacing:0}
      .tools .rec i{width:7px;height:7px;border-radius:50%;background:#FF3B30}
      .tools .sp{flex:1}
      .tools .lg{height:36px;border-radius:18px;background:var(--fillT);display:flex;align-items:center;gap:7px;padding:0 14px;font-size:17px;color:var(--sec);letter-spacing:-.3px}
      .tools .mic{width:40px;height:40px;border-radius:20px;background:var(--fillT);display:grid;place-items:center;color:#000;flex:0 0 auto;transition:background .2s,color .2s}
      .box.recording .rec{display:flex}
      .box.recording .lg{display:none}
      .box.recording .mic{background:#FF3B30;color:#fff;animation:breathe 1.8s ease-in-out infinite}
      @keyframes breathe{50%{transform:scale(1.08)}}
      /* ── the scene ── */
      .l-scene{background:#fff}
      .wt{position:absolute;left:0;right:0;top:64px;text-align:center;z-index:4}
      .wt b{display:block;font-size:17px;line-height:22px;font-weight:600;letter-spacing:-.4px}
      .wt span{display:inline-flex;align-items:center;gap:3px;font-size:11px;line-height:13px;font-weight:600;color:var(--sec);margin-top:1px;letter-spacing:.1px}
      .navfade{position:absolute;left:0;right:0;top:0;height:118px;z-index:3;background:linear-gradient(#fff 78%,rgba(255,255,255,0));pointer-events:none}
      .sc{position:absolute;left:16px;right:16px;top:132px;display:flex;flex-direction:column;gap:14px;transition:transform .6s cubic-bezier(.45,0,.2,1)}
      .shd{display:flex;flex-direction:column;gap:4px;padding-bottom:8px}
      .shd small{font-size:12px;line-height:16px;color:var(--sec);letter-spacing:0}
      .shd b{font-size:20px;line-height:25px;font-weight:600;letter-spacing:-.3px}
      .shd p{margin:0;font-size:13px;line-height:18px;color:var(--sec);letter-spacing:-.1px}
      .ld{display:flex;align-items:center;gap:10px;padding:12px 0;color:var(--sec);font-size:17px}
      .spin{width:20px;height:20px;border-radius:50%;background:conic-gradient(rgba(60,60,67,.6),rgba(60,60,67,.08));-webkit-mask:radial-gradient(circle,transparent 6px,#000 6.5px);mask:radial-gradient(circle,transparent 6px,#000 6.5px);animation:sp 1s linear infinite}
      @keyframes sp{to{transform:rotate(1turn)}}
      .ln{display:flex;flex-direction:column;align-items:flex-start;gap:4px;padding-right:40px;transition:opacity .35s,transform .35s}
      .ln.me{align-items:flex-end;padding:0 0 0 40px}
      .ln.new{opacity:0;transform:translateY(8px)}
      .ln .nm{font-size:12px;line-height:15px;color:var(--sec);letter-spacing:0}
      .ln .bub{padding:9px 14px;border-radius:14px;background:#F2F2F7;font-size:17px;line-height:22px;letter-spacing:-.1px;box-shadow:0 0 0 0 transparent;transition:box-shadow .25s}
      .ln.me .bub{background:rgba(10,92,245,.18)}
      .ln.now .bub{box-shadow:0 0 0 1px var(--acc),inset 0 0 0 1px var(--acc)}
      .ln .acc{display:flex;gap:16px;font-size:12px;line-height:15px;color:var(--acc);letter-spacing:0}
      .ln .acc span{display:flex;align-items:center;gap:6px;transition:opacity .15s}
      .ln .acc span.tap{opacity:.35}
      .bar{position:absolute;left:0;right:0;bottom:0;height:106px;background:rgba(249,249,249,.94);-webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);box-shadow:0 -.5px 0 rgba(0,0,0,.08);z-index:4}
      .bar .bs{position:absolute;left:16px;right:16px;top:11px;display:flex;gap:16px}
      .bar .bs>span{flex:1;height:51px;border-radius:26px;display:flex;align-items:center;justify-content:center;gap:9px;font-size:17px;letter-spacing:-.4px;background:rgba(10,92,245,.15);color:var(--acc)}
      .bar .bs>span.p{background:var(--acc);color:#fff}
      .bar .bs.off>span{opacity:.45}
    `, `
      <div class="layer l-box on"><div class="sht">
        <div class="gl cn"></div><div class="nt"></div><div class="cta">${SY.playFill}</div>
        <div class="hd"><b></b><p></p></div>
        <div class="reel"><div class="tr"></div></div>
      </div>
        <div class="box">
          <div class="chips"><span class="chip"><span class="d">${SY.doc}</span><span class="fn">Job posting.pdf</span><span class="x">${SY.x}</span></span></div>
          <div class="note"></div>
          <div class="fld ph"></div>
          <div class="tools"><span class="pl">${SY.plus}</span><span class="who"><i class="av"></i><span class="wn"></span></span><span class="rec"><i></i><span></span></span><span class="sp"></span><span class="lg"><span></span>${SY.updown}</span><span class="mic">${SY.mic}</span></div>
        </div>
      </div>
      <div class="layer l-scene">
        <div class="sc"><div class="shd"><small></small><b></b><p></p></div></div>
        <div class="navfade"></div>
        <div class="wt"><b>Watching</b><span>B1 ${SY.chev}</span></div>
        <div class="bar"><div class="bs"><span class="b1"></span><span class="p b2"></span></div></div>
      </div>`);
  }

  get ko() { return this.t === STR.ko; }

  build() {
    const ko = this.ko;
    this.$(".cn").textContent = ko ? "취소" : "Cancel";
    this.$(".nt").textContent = ko ? "내 상황" : "Your situation";
    this.$(".hd b").textContent = ko ? "그 일을 미리 한 번 겪어 보세요" : "Go through it before it happens";
    this.$(".hd p").textContent = ko ? "자세히 적을수록 장면이 실제에 가까워져요. 공고나 이력서가 있으면 ＋로 가져오세요." : "The more you write, the closer the scene lands. Tap ＋ to bring the posting, the listing, your CV.";
    const R = ko ? ["다음 주 목요일 최종 면접. 공고를 쓴 하이어링 매니저와 영어로.", "집주인에게 보일러가 3주째 고장이라고 말하고, 언제 고쳐 줄지 날짜를 받아 내기.", "애인의 부모님을 처음 뵙는 자리. 그 집에서 저녁을 먹으면서.", "일주일째 있는 증상을 의사에게 설명하고, 어떤 방법이 있는지 물어보기.", "다음 1:1에서 팀장에게 연봉 인상을 요청하기. 근거가 될 숫자를 들고.", "영수증 없이 비싼 물건을 환불받기. 점원은 받아 주기 싫어하는 상황."]
      : ["A final-round interview next Thursday, in English, with the hiring manager who wrote the job ad.", "Telling my landlord the heating has been broken for three weeks, and getting a date out of them.", "Meeting my partner's parents for the first time over dinner at their place.", "Explaining a symptom I've had for a week to a doctor, and asking what the options are.", "Asking my manager for a raise in our next one-on-one, with the numbers ready.", "Returning something expensive without the receipt, to a clerk who doesn't want to take it."];
    this.$(".reel .tr").innerHTML = [...R, ...R].map(x => `<div class="rw"><span>${esc(x)}</span></div>`).join("");
    this.$(".note").textContent = ko ? "파일은 폰에 그대로 있어요. 앱에는 읽은 내용만 남아요." : "Your files stay on your phone. Only what was read is kept here.";
    this.$(".av").textContent = "P"; this.$(".wn").textContent = "Paige";
    this.$(".rec span").textContent = ko ? "듣는 중 · 누르면 끝" : "Listening — tap to finish";
    this.$(".lg span").textContent = ko ? "한국어" : "English";
    this.reset();
  }

  reset() {
    const ko = this.ko;
    this.$$(".layer").forEach(l => l.classList.toggle("on", l.classList.contains("l-box")));
    const f = this.$(".fld"); f.className = "fld ph"; f.textContent = ko ? "어떤 상황을 만들어 볼까요? 자세할수록 좋아요." : "What situation should we build? The more detail, the better.";
    this.$(".box").classList.remove("recording"); this.$(".reel").classList.remove("off");
    /* material="none": nothing attached, so no chips and no files note (the sheet draws both only when
       the scenario has sources). Default keeps the attached posting. */
    this.$(".box").classList.toggle("bare", this.getAttribute("material") === "none");
    this.$(".cta").classList.remove("on", "tap");
    this.$$(".sc .ln,.sc .ld").forEach(e => e.remove()); this.$(".sc").style.transform = "none";
    this._bar("play"); this.$(".bs").classList.add("off");
  }

  _bar(state) {
    const ko = this.ko, bs = this.$(".bs"); bs.classList.remove("off");
    if (state === "end") {
      this.$(".b1").innerHTML = `${SY.again}<span>${ko ? "다시 보기" : "Watch again"}</span>`;
      this.$(".b2").innerHTML = `${SY.books}<span>Study this</span>`;
    } else {
      this.$(".b1").innerHTML = `${SY.restart}<span>${ko ? "다시 시작" : "Restart"}</span>`;
      this.$(".b2").innerHTML = `${SY.pause}<span>${ko ? "일시정지" : "Pause"}</span>`;
    }
  }

  _header(who, title, blurb) {
    this.$(".shd small").textContent = who; this.$(".shd b").textContent = title; this.$(".shd p").textContent = blurb;
  }

  _line(who, text, me) {
    const ko = this.ko, d = document.createElement("div");
    d.className = `ln${me ? " me" : ""}`;
    d.innerHTML = `<div class="nm">${esc(who)}</div><div class="bub">${esc(text)}</div><div class="acc"><span class="sh">${SY.wavemic}${ko ? "이 문장 섀도잉" : "Shadow this"}</span><span>${SY.pluscircle}${ko ? "표현 저장" : "Save phrase"}</span></div>`;
    this.$(".sc").append(d); return d;
  }

  _scene(S, current) {
    this.$$(".sc .ln").forEach(e => e.remove());
    S.forEach(([w, t, me], i) => { const l = this._line(w, t, me); if (i === current) l.classList.add("now"); });
  }

  static poses = ["composer-attached", "dictating", "scene", "playing"];
  async pose(name) {
    this.stop(); this.reset();
    const ko = this.ko;
    if (name === "composer-attached") this.$(".box").classList.remove("bare");
    if (name === "dictating") {
      this.$(".box").classList.add("recording"); this.$(".reel").classList.add("off");
      const f = this.$(".fld"); f.className = "fld"; f.textContent = this._said().slice(0, 30);
    }
    if (name === "scene" || name === "playing") {
      this.$$(".layer").forEach(l => l.classList.toggle("on", l.classList.contains("l-scene")));
      if (name === "scene") {
        this._header("Barista · at the cafe", "The wrong order", "My order came out wrong and I point it out politely.");
        this._scene([["Barista", "Hi! What can I get you today?", false], ["Future self", "A flat white, please — for here.", true],
          ["Barista", "Coming right up. Here you go!", false], ["Future self", "Sorry, I think this is a latte, not a flat white.", true],
          ["Barista", "Oh, you're right — let me remake that for you.", false]], 0);
        this._bar("end");
      } else {
        this._header(...this._interviewHead());
        this._scene(this._interview().slice(0, 2), 1); this._bar("play");
      }
    }
  }

  _said() {
    return this.ko ? "다음 주 목요일 디자인 직무 패널 면접. 포트폴리오에서 제일 어려웠던 프로젝트를 물어볼 것 같아."
      : "A panel interview for a design role next Thursday. They'll ask about the hardest project in my portfolio.";
  }
  /* the counterpart is the person picked in the box (Paige → Scenario.counterpartId), and WatchView
     labels the lines and the header with counterpart.name */
  _interviewHead() { return ["Paige", "Job interview · panel round", "A panel interview for a design role: walking through the hardest project in my portfolio."]; }
  _interview() {
    return [["Paige", "Walk me through the project you're proudest of.", false], ["Future self", "Sure. Last year I led the redesign of our booking app, end to end.", true],
      ["Paige", "What was the hardest call you had to make?", false], ["Future self", "Cutting a feature the team loved. The data said it confused new users.", true]];
  }

  async demo() {
    const f = this.$(".fld"), box = this.$(".box");
    await this.sleep(1400); this.beat(1);
    // dictate the situation into the box: mic → live partials → mic again
    box.classList.add("recording"); await this.sleep(500);
    this.$(".reel").classList.add("off"); f.className = "fld";
    const words = this._said().split(" "); let said = "";
    for (const w of words) { said += (said ? " " : "") + w; f.textContent = said; await this.sleep(190); }
    await this.sleep(500); box.classList.remove("recording");
    this.$(".cta").classList.add("on"); await this.sleep(800);
    this.$(".cta").classList.add("tap"); await this.sleep(160); this.$(".cta").classList.remove("tap");
    // the scene: written, then played
    this._header(...this._interviewHead());
    const ld = document.createElement("div"); ld.className = "ld"; ld.innerHTML = `<i class="spin"></i>${this.ko ? "대화를 쓰는 중…" : "Writing the dialogue…"}`;
    this.$(".sc").append(ld);
    this.$$(".layer").forEach(l => l.classList.toggle("on", l.classList.contains("l-scene")));
    await this.sleep(1300); ld.remove(); this._bar("play"); this.beat(2);
    let prev = null;
    for (const [w, t, me] of this._interview()) {
      const l = this._line(w, t, me); l.classList.add("new"); void l.offsetWidth; l.classList.remove("new"); l.classList.add("now");
      prev?.classList.remove("now"); prev = l;
      const sc = this.$(".sc"), over = sc.offsetTop + sc.scrollHeight - 750; sc.style.transform = over > 0 ? `translateY(${-over}px)` : "none";
      await this.sleep(1900);
    }
    prev.classList.remove("now"); this._bar("end");
    await this.sleep(600); this.beat(3);
    const sh = prev.querySelector(".sh"); sh.classList.add("tap"); await this.sleep(500); sh.classList.remove("tap");
    await this.sleep(2200);
  }
}

export { NwWatch };
