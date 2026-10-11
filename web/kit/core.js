/* nawana UI kit — the app's own surfaces as web components, for the site and for video.
 *
 *   <script type="module" src="/kit/nawana-ui.js"></script>
 *
 *   <nw-futureself mode="speaking" level="voice"></nw-futureself>   the mosaic (pill or circle)
 *   <nw-phone><nw-call autoplay></nw-call></nw-phone>                 an iPhone with a live screen
 *   <nw-home autoplay>, <nw-speech autoplay>                          the other two screens
 *   <nw-bubble who="self">…</nw-bubble>, <nw-fix>…</nw-fix>           single lines, at any size
 *
 * Everything is drawn from the iOS app, not invented: the mosaic is a line-by-line port of
 * FutureselfPixels.swift / Futureself.metal (hash-driven cells, centre-out ignition, 5-step ramp,
 * dithered snap, 1pt gap, capsule-SDF inner shadow), screens are laid out in iOS points (402×874)
 * from simulator captures and scale to whatever width the host gets. Chrome text follows the
 * nearest lang attribute (ko → Korean, anything else → English); material stays English.
 *
 * Screens are scriptable (await call.say("…"), call.listen(), call.user("…"), call.fix({…}))
 * and `autoplay` loops the built-in demo while the element is on screen. Video capture records
 * the same elements, so the site and the reels can never drift apart.
 *
 * Embedding in a page's own phone frame:
 *   fill        the screen covers its positioned parent (e.g. a .screen with the 402:874 aspect)
 *   statusbar   draw 09:41 + signal/battery (no island — the frame has its own)
 *   active      play while set (and visible); removing it stops and resets — for scroll-driven steps
 *   beats="#sel" while playing, elements [data-beat=N] inside #sel get .nw-beat-on when the scene
 *               reaches beat N, and #sel gets .nw-beating — so a section's bullets follow the screen
 *   el.scene = async s => {…}   replace the built-in demo with the page's own script */

const KIT = new URL(".", import.meta.url);
const RM = matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ───────────────────────── fonts (document-level; shadow trees inherit them) ───────────────────────── */
(function loadFonts() {
  const faces = [
    ["Geist Pixel", new URL("../GeistPixel.ttf", KIT)],
    ["Galmuri14", new URL("../Galmuri14.woff2", KIT)],
  ];
  for (const [family, url] of faces) {
    if ([...document.fonts].some(f => f.family.replace(/"/g, "") === family)) continue;
    const f = new FontFace(family, `url(${url})`, { display: "swap" });
    document.fonts.add(f);
    f.load().catch(() => {});
  }
})();

/* ───────────────────────── strings: chrome follows the page language ───────────────────────── */
const STR = {
  ko: {
    talk: "대화하기", end: "종료", self: "Future self", you: "You", listening: "듣는 중…", speaking: "말하는 중…",
    hintListen: "듣는 중 · 잠깐 멈추면 전송 · 누르면 종료", hintThink: "생각하는 중 · 누르면 종료",
    natural: "더 자연스럽게", trySaying: "이렇게 말해 보세요", shadow: "섀도잉",
    activity: "활동", news: "뉴스", everyday: "일상", scenarios: "상황", goal: "오늘 목표 10분",
    aboutMe: "나에 대해 더 알려주기", aboutMeSub: "일상을 알려주실수록 대화가 더 진짜 같아져요.", me: "나",
    speech: "스피치", challenges: "챌린지", scripts: "원고", board: "리더보드 보기",
    boardNote: "모두 같은 원고로 겨뤄요. 가장 잘한 기록이 순위에 올라가요.",
    taking: n => `${n}명 도전 중`, min: n => `${n}분`, sec: n => `${n}초`,
    rankUp: (a, b) => `${a}위 → ${b}위`, toNext: (r, p) => `${r}위까지 ${p}점 남았어요`,
    date: "10월 10일 오후 8:20",
  },
  en: {
    talk: "Let's talk", end: "End", self: "Future self", you: "You", listening: "Listening…", speaking: "Speaking…",
    hintListen: "Listening · pause to send · tap to stop", hintThink: "Thinking… · tap to stop",
    natural: "More natural", trySaying: "Try saying", shadow: "Shadow",
    activity: "Activity", news: "News", everyday: "Everyday", scenarios: "Scenarios", goal: "Today's goal 10 min",
    aboutMe: "Tell me more about you", aboutMeSub: "Talks get more real when I know your life.", me: "Me",
    speech: "Speech", challenges: "Challenges", scripts: "Scripts", board: "See the leaderboard",
    boardNote: "Everyone reads the same script. Your best take goes on the board.",
    taking: n => `${n} taking it`, min: n => `${n} min`, sec: n => `${n}s`,
    rankUp: (a, b) => `#${a} → #${b}`, toNext: (r, p) => `${p} point${p === 1 ? "" : "s"} to #${r}`,
    date: "Oct 10, 8:20 PM",
  },
};
function strings(el) {
  const l = (el.getAttribute("lang") || el.closest("[lang]")?.getAttribute("lang") || document.documentElement.lang || "en").toLowerCase();
  return l.startsWith("ko") ? STR.ko : STR.en;
}

/* ───────────────────────── small helpers ───────────────────────── */
const esc = s => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const wordsHTML = text => text.trim().split(/\s+/).map(w => `<span class="w">${esc(w)}</span>`).join(" ");
const mmss = s => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

const ICON = {
  x: '<path d="M5 5l14 14M19 5L5 19" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>',
  chev: '<path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
  globe: '<g fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18"/></g>',
  cal: '<g fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17"/></g><g fill="currentColor"><circle cx="8" cy="13.5" r="1"/><circle cx="12" cy="13.5" r="1"/><circle cx="16" cy="13.5" r="1"/><circle cx="8" cy="17" r="1"/><circle cx="12" cy="17" r="1"/></g>',
  sliders: '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/><circle cx="15" cy="7" r="2" fill="#F2F2F7"/><circle cx="8" cy="12" r="2" fill="#F2F2F7"/><circle cx="13" cy="17" r="2" fill="#F2F2F7"/></g>',
  refresh: '<path d="M19 12a7 7 0 1 1-2.1-5M19 4v4h-4" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
  chip: '<g fill="none" stroke="currentColor" stroke-width="1.7"><rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/></g>',
  leaf: '<path d="M5 19C5 10 11 5 20 4c0 9-5 15-13 15M5 19l7-7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  ball: '<g fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5l4 3-1.5 4.5h-5L8 10.5z"/></g>',
  cup: '<path d="M4 9h13v4a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM17 10h1.5a2.5 2.5 0 0 1 0 5H17M7 4c0 1.5 1 1.5 1 3M11 4c0 1.5 1 1.5 1 3" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
  fork: '<path d="M7 3v7a2 2 0 0 0 4 0V3M9 10v11M16 21V3c-2 1-3 4-3 7h3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  hosp: '<g fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3.5" y="6.5" width="17" height="13" rx="3"/><path d="M9 6.5V4.5h6v2M12 10v6M9 13h6" stroke-linecap="round"/></g>',
  brief: '<g fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3.5" y="7" width="17" height="12" rx="2.5"/><path d="M9 7V5h6v2M3.5 12h17"/></g>',
  plus: '<path d="M12 5v14M5 12h14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  home: '<path d="M4 11l8-6 8 6v8H4z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  trophy: '<path d="M7 4h10v5a5 5 0 0 1-10 0zM7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4M12 14v4M8 20h8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
  person: '<g fill="none" stroke="currentColor" stroke-width="1.7"><rect x="4" y="4" width="16" height="16" rx="3"/><circle cx="12" cy="10" r="2.6"/><path d="M7.5 17.5c.8-2.3 2.5-3.4 4.5-3.4s3.7 1.1 4.5 3.4"/></g>',
  bulb: '<path d="M9 17h6M10 20h4M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.3 1 2.1h5c0-.8.4-1.6 1-2.1A6 6 0 0 0 12 3z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
  doc: '<path d="M7 3h7l4 4v14H7zM14 3v4h4M9.5 12h6M9.5 15.5h6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>',
  retry: '<path d="M5 12a7 7 0 1 0 2.1-5M5 4v4h4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
  next: '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M8 12h8M13 9l3 3-3 3"/></g>',
  spark: '<path d="M12 3c.6 4.2 2.8 6.4 7 7-4.2.6-6.4 2.8-7 7-.6-4.2-2.8-6.4-7-7 4.2-.6 6.4-2.8 7-7zM19 16c.3 1.6 1 2.3 2.5 2.5-1.5.2-2.2 1-2.5 2.5-.3-1.5-1-2.3-2.5-2.5 1.5-.2 2.2-.9 2.5-2.5z" fill="currentColor"/>',
  wave: '<path d="M4 10v4M8 7v10M12 4v16M16 8v8M20 10v4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  user: '<g fill="currentColor"><circle cx="12" cy="8" r="4.2"/><path d="M3.5 21c.8-4.4 4.2-7 8.5-7s7.7 2.6 8.5 7z"/></g>',
};
const icon = (n, cls = "ico") => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICON[n] || ""}</svg>`;

/* iOS system values sampled from the app's own screenshots (light). */
const IOS_CSS = `
  :host{--bg:#FFFFFF;--grouped:#F2F2F7;--fill:#EFEFF4;--gray:#8E8E93;--gray3:#C7C7CC;--sep:#D8D8DC;
    --blue:#0A5CF5;--me:#D3E2FD;--fixbg:#EBF2FE;--tint:#D6E4FB;--red:#FF3B30;--green:#34C759;--orange:#E07B1F;
    --sans:-apple-system,BlinkMacSystemFont,"SF Pro Text","Apple SD Gothic Neo","Noto Sans KR",system-ui,sans-serif;
    --pixel:"Geist Pixel","Galmuri14","Apple SD Gothic Neo",monospace}
  *{box-sizing:border-box}
  .ico{width:1em;height:1em;display:inline-block;vertical-align:-.12em;flex:0 0 auto}
  .k .w{color:#B9BDC6;transition:color .12s}
  .k .w.on{color:inherit}
  .k.done .w{color:inherit}
`;

/* ───────────────────────── one shared clock, visible elements only ───────────────────────── */
const ticking = new Set();
let rafOn = false;
function tick(ts) {
  for (const el of ticking) el._frame(RM ? 3.2 : ts / 1000);
  rafOn = ticking.size > 0 && !RM;
  if (rafOn) requestAnimationFrame(tick);
}
function setTicking(el, on) {
  on ? ticking.add(el) : ticking.delete(el);
  if (on && !rafOn) { rafOn = true; requestAnimationFrame(tick); }
}
const viewIO = new IntersectionObserver(entries => {
  for (const e of entries) e.target._visible(e.isIntersecting);
}, { rootMargin: "120px" });

/* ═══════════════════════════ <nw-futureself> ═══════════════════════════
 * mode   idle | listening | thinking | speaking      (default speaking)
 * level  0…1, or "voice" for a syllable-like envelope (default voice when speaking)
 * shape  pill | circle                                (default pill)
 * cell   cell edge in px (default: height / 5, the shader's rule)
 * ring   home-ring treatment: page wash + blurred inner ring (ConversationHome)
 * Size it with CSS. Properties .mode and .level are live. */
const RAMP = [[.965, .972, 1], [.900, .922, .970], [.720, .830, 1], [.450, .680, 1], [.030, .340, .950]];
const RAMP_DARK = [[.020, .028, .060], [.080, .095, .130], [.020, .130, .400], [.040, .360, .960], [.480, .720, 1]];
const fract = v => v - Math.floor(v);
function hash21(x, y) {
  let qx = fract(x * 123.34), qy = fract(y * 456.21);
  const d = qx * (qx + 45.32) + qy * (qy + 45.32);
  qx += d; qy += d;
  return fract(qx * qy);
}
const smooth = (e0, e1, x) => { const t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t); };
const MODES = { idle: 0, listening: 1, thinking: 2, speaking: 3 };

class NwFutureself extends HTMLElement {
  static observedAttributes = ["mode", "level", "shape", "cell", "ring", "dark"];
  constructor() {
    super();
    this.attachShadow({ mode: "open" }).innerHTML = `<style>
      :host{display:inline-block;position:relative;width:156px;height:64px;border-radius:999px;overflow:hidden;contain:paint;vertical-align:middle}
      :host([shape=circle]){border-radius:50%}
      canvas{display:block;width:100%;height:100%}
      .rim{position:absolute;inset:0;border-radius:inherit;box-shadow:inset 0 0 0 .5px rgba(60,60,67,.18);pointer-events:none}
      .wash,.vig{position:absolute;inset:0;border-radius:inherit;pointer-events:none;display:none}
      :host([ring]) .wash{display:block;background:rgba(242,242,247,.35)}
      :host([ring]) .vig{display:block;border:var(--vig-w,10px) solid rgba(0,0,0,.15);filter:blur(var(--vig-b,6px))}
      :host([ring]) .rim{display:none}
    </style><canvas></canvas><div class="wash"></div><div class="vig"></div><div class="rim"></div>`;
    this._c = this.shadowRoot.querySelector("canvas");
    this._ctx = this._c.getContext("2d");
    this._lvl = 0; this._last = 0; this._seed = Math.random() * 40; this._shown = false;
  }
  get mode() { return this.getAttribute("mode") || "speaking"; }
  set mode(v) { this.setAttribute("mode", v); }
  get level() { return this.getAttribute("level") ?? (this.mode === "speaking" ? "voice" : "0"); }
  set level(v) { this.setAttribute("level", v); }
  connectedCallback() { viewIO.observe(this); }
  disconnectedCallback() { viewIO.unobserve(this); setTicking(this, false); }
  attributeChangedCallback() { if (RM || !this._shown) this._frame(3.2); }
  _visible(v) { this._shown = v; setTicking(this, v); if (v) this._frame(performance.now() / 1000); }
  _target(t) {
    const l = this.level;
    if (l === "voice") {
      const syl = Math.max(0, Math.sin(t * 9.1 + this._seed) * .5 + Math.sin(t * 5.3 + this._seed * 2) * .35 + .25);
      return Math.min(1, .18 + .62 * syl * (.55 + .45 * Math.sin(t * 1.3 + this._seed)));
    }
    return Math.min(Math.max(parseFloat(l) || 0, 0), 1);
  }
  _frame(t) {
    const cw = this._c.offsetWidth, ch = this._c.offsetHeight; if (!cw || !ch) return;
    const k = this._c.getBoundingClientRect().width / cw * devicePixelRatio;
    const W = Math.max(1, Math.round(cw * k)), H = Math.max(1, Math.round(ch * k));
    if (this._c.width !== W || this._c.height !== H) { this._c.width = W; this._c.height = H; this._rc = null; }
    // LevelSmoother: ~60 ms attack, ~350 ms release
    const dt = this._last ? Math.min(.1, Math.max(0, t - this._last)) : 1 / 60; this._last = t;
    const target = RM ? (this.level === "voice" ? .36 : this._target(t)) : this._target(t);
    this._lvl += (target - this._lvl) * (1 - Math.exp(-dt / (target > this._lvl ? .06 : .35)));
    if (RM) this._lvl = target;
    if (this.hasAttribute("ring")) { this.style.setProperty("--vig-w", `${10 * ch / 260}px`); this.style.setProperty("--vig-b", `${6 * ch / 260}px`); }

    const ctx = this._ctx, mode = MODES[this.mode] ?? 3, dark = this.hasAttribute("dark"), ramp = dark ? RAMP_DARK : RAMP;
    ctx.setTransform(k, 0, 0, k, 0, 0);
    ctx.fillStyle = `rgb(${ramp[0].map(c => Math.round(c * 255)).join(",")})`; ctx.fillRect(0, 0, cw, ch);
    const cell = parseFloat(this.getAttribute("cell")) || ch / 5;
    const cols = Math.ceil(cw / cell), rows = Math.ceil(ch / cell);
    const ox = (cw - cols * cell) / 2, oy = (ch - rows * cell) / 2;
    const drive = Math.min(Math.max(this._lvl, 0), 1) * 1.15, gap = Math.max(.5, Math.min(1, cell / 12.8));
    for (let cy = 0; cy < rows; cy++) for (let cx = 0; cx < cols; cx++) {
      const x = ox + cx * cell, y = oy + cy * cell, ux = (x + cell / 2) / cw, uy = (y + cell / 2) / ch;
      const r1 = hash21(cx + .13, cy + .13), r2 = hash21(cx + 7.77, cy + 7.77), r3 = hash21(cx + 23.19, cy + 23.19);
      let v = .16 + .14 * Math.sin(t * (.35 + .55 * r2) + r3 * 2 * Math.PI);
      const bias = mode === 3 ? Math.abs(ux - .5) * 2 : 1 - uy;
      const order = Math.min(Math.max(r1 + (bias - r1) * .45, 0), 1);
      const ig = smooth(order, order + .22, drive);
      v += ig * (.55 + .30 * r2) + ig * .08 * Math.sin(t * (2 + 3 * r1) + r2 * 2 * Math.PI);
      if (mode === 2) { const sx = .5 + .46 * Math.sin(t * 1.4); v += Math.exp(-Math.pow((ux - sx) * 3.5, 2)) * (.45 + .35 * r1); }
      if (mode === 0) v *= .7;
      const step = Math.min(Math.max(Math.floor(v * 4 + (r3 - .5) * .9 + .5), 0), 4);
      ctx.fillStyle = `rgb(${ramp[step].map(c => Math.round(c * 255)).join(",")})`;
      ctx.fillRect(x + gap / 2, y + gap / 2, cell - gap, cell - gap);
    }
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(this._recess(W, H, k * Math.max(1, ch / 64), dark), 0, 0);
  }
  /* The shader's inner shadow, per pixel: capsule SDF, 7pt falloff, pooled along the top edge,
     a faint rim light along the bottom lip. Light-mode strengths. Cached per size. */
  _recess(W, H, pxPerPt, darkMode) {
    if (this._rc && this._rc.width === W && this._rc.height === H && this._rcDark === darkMode) return this._rc;
    this._rcDark = darkMode;
    const c = document.createElement("canvas"); c.width = W; c.height = H;
    const g = c.getContext("2d"), img = g.createImageData(W, H), d = img.data;
    const rad = H / 2, ax = Math.max(W / 2 - rad, 0), fall = 7 * pxPerPt;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const px = x + .5 - W / 2, py = y + .5 - H / 2, qx = Math.min(Math.max(px, -ax), ax);
      const rim = Math.exp(-Math.max(rad - Math.hypot(px - qx, py), 0) / fall);
      const topW = Math.min(Math.max(.5 - py / H, 0), 1);
      const dark = rim * (.14 + .34 * topW) * (darkMode ? .85 : .45), lift = rim * (1 - topW) * (darkMode ? .06 : .05), i = (y * W + x) * 4;
      const a = dark - lift, v = a >= 0 ? 0 : 255;
      d[i] = d[i + 1] = d[i + 2] = v; d[i + 3] = Math.round(Math.abs(a) * 255);
    }
    g.putImageData(img, 0, 0); this._rc = c; return c;
  }
}

/* ═══════════════════════════ <nw-phone> ═══════════════════════════
 * iPhone 17 Pro, drawn to its own proportions: a 402×874pt screen (55pt corners) inside a
 * 14pt black bezel and a thin titanium band, the Dynamic Island, the status bar laid out
 * either side of the island, and the side buttons. Size it by width; put one screen (or an
 * <img>) inside — every child fills the screen, later children on top. */
class NwPhone extends HTMLElement {
  static observedAttributes = ["time"];
  constructor() {
    super();
    const u = n => `calc(100cqw * ${n} / 430)`;
    this.attachShadow({ mode: "open" }).innerHTML = `<style>${IOS_CSS}
      :host{display:block;width:330px;aspect-ratio:430/902;position:relative;container-type:inline-size}
      .body{position:absolute;inset:0;border-radius:${u(69)};background:#0B0B0C;
        box-shadow:inset 0 0 0 ${u(2.2)} #6E7076,inset 0 0 0 ${u(3.4)} #2A2B2E,0 ${u(30)} ${u(70)} rgba(10,30,70,.22),0 ${u(6)} ${u(14)} rgba(0,0,0,.18)}
      .btn{position:absolute;width:${u(3.2)};background:linear-gradient(90deg,#4A4C51,#76797F);border-radius:${u(2)}}
      .b1{left:${u(-2.4)};top:${u(150)};height:${u(34)}} .b2{left:${u(-2.4)};top:${u(214)};height:${u(62)}} .b3{left:${u(-2.4)};top:${u(290)};height:${u(62)}}
      .b4{right:${u(-2.4)};top:${u(250)};height:${u(96)};background:linear-gradient(270deg,#4A4C51,#76797F)}
      .scr{position:absolute;left:${u(14)};top:${u(14)};right:${u(14)};bottom:${u(14)};border-radius:${u(55)};overflow:hidden;background:#fff;isolation:isolate}
      ::slotted(*){position:absolute!important;inset:0;width:100%!important;height:100%!important;max-width:none!important;object-fit:cover}
      .di{position:absolute;left:50%;top:${u(11)};width:${u(124)};height:${u(37)};transform:translateX(-50%);border-radius:999px;background:#000;z-index:60}
      .sb{position:absolute;left:0;right:0;top:0;height:${u(54)};z-index:59;pointer-events:none;font-family:var(--sans);color:var(--sbc,#000)}
      :host([dark]) .sb{--sbc:#fff}
      .t{position:absolute;left:0;width:${u(148)};top:${u(21)};text-align:center;font-size:${u(17)};font-weight:600;letter-spacing:-.012em;line-height:${u(22)}}
      .ic{position:absolute;right:0;width:${u(148)};top:${u(26)};display:flex;gap:${u(6)};align-items:center;justify-content:center}
      .ic svg{display:block;height:${u(12)};width:auto}
      .bat{position:relative;width:${u(27)};height:${u(13)};border-radius:${u(4.2)};border:${u(1.2)} solid currentColor;opacity:.45}
      .batf{position:absolute;width:${u(21.4)};height:${u(7.4)};border-radius:${u(2.4)};background:currentColor}
      .batw{position:relative;display:flex;align-items:center}
      .batw .batf{left:${u(2.8)};right:auto}
      .batw::after{content:"";position:absolute;right:${u(-3.6)};width:${u(1.6)};height:${u(4.2)};border-radius:0 ${u(1)} ${u(1)} 0;background:currentColor;opacity:.45}
      :host([nostatus]) .sb{display:none}
    </style>
    <span class="btn b1"></span><span class="btn b2"></span><span class="btn b3"></span><span class="btn b4"></span>
    <div class="body"></div>
    <div class="scr"><slot></slot>
      <div class="di"></div>
      <div class="sb"><span class="t"></span><span class="ic">
        <svg viewBox="0 0 18 12"><g fill="currentColor"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></g></svg>
        <svg viewBox="0 0 16 12"><path d="M8 11.5l2.3-2.7a3.4 3.4 0 0 0-4.6 0zM3.9 6.7a6.3 6.3 0 0 1 8.2 0l1.6-1.9a8.8 8.8 0 0 0-11.4 0zM.6 2.9l1.6 1.9a8.9 8.9 0 0 1 11.6 0l1.6-1.9a11.4 11.4 0 0 0-14.8 0z" fill="currentColor"/></svg>
        <span class="batw"><span class="bat"></span><span class="batf"></span></span></span></div>
    </div>`;
  }
  connectedCallback() { this.attributeChangedCallback(); }
  /* a Korean phone runs the 24-hour clock, as every ko capture shows */
  attributeChangedCallback() { this.shadowRoot.querySelector(".t").textContent = this.getAttribute("time") || (strings(this) === STR.ko ? "09:41" : "9:41"); }
}

/* ═══════════════════════════ screen base ═══════════════════════════
 * A screen is 402×874 iOS points, scaled to the host's width. `autoplay` loops demo() while visible.
 * Every scripted method is awaitable and stops when stop() is called or the screen leaves view. */
class NwScreen extends HTMLElement {
  constructor(css, html) {
    super();
    this.attachShadow({ mode: "open" }).innerHTML = `<style>${IOS_CSS}
      :host{display:block;position:relative;width:402px;aspect-ratio:402/874;overflow:hidden;background:var(--bg);font-family:var(--sans);color:#000;letter-spacing:-.2px}
      :host([fill]){position:absolute;inset:0;width:100%;height:100%;aspect-ratio:auto}
      :host([static]) *,:host([static]) *::before,:host([static]) *::after{transition:none!important;animation:none!important}
      .sb{position:absolute;left:0;right:0;top:0;height:54px;z-index:40;pointer-events:none;display:none}
      :host([statusbar]) .sb{display:block}
      .sb .st{position:absolute;left:0;width:148px;top:21px;text-align:center;font-size:17px;line-height:22px;font-weight:600;letter-spacing:-.2px}
      .sb .si{position:absolute;right:0;width:148px;top:26px;display:flex;gap:6px;align-items:center;justify-content:center}
      .sb .si svg{display:block}
      .sb .bat{position:relative;width:27px;height:13px;border-radius:4.2px;border:1.2px solid rgba(60,60,67,.45);padding:1.6px}
      .sb .bat i{display:block;height:100%;width:100%;border-radius:2.4px;background:#000}
      .sb .bat::after{content:"";position:absolute;right:-3.6px;top:3.4px;width:1.6px;height:4.2px;border-radius:0 1px 1px 0;background:rgba(60,60,67,.45)}
      .s{position:absolute;left:0;top:0;width:402px;height:874px;transform-origin:0 0;transform:scale(var(--k,1))}
      .glass{position:absolute;top:62px;height:44px;min-width:44px;border-radius:22px;background:rgba(255,255,255,.92);box-shadow:0 2px 12px rgba(0,0,0,.08),inset 0 0 0 .5px rgba(0,0,0,.06);display:flex;align-items:center;justify-content:center;gap:6px;padding:0 14px;font-size:17px;font-weight:600;z-index:3}
      .layer{position:absolute;inset:0;opacity:0;transition:opacity .45s ease;pointer-events:none}
      .layer.on{opacity:1}
      ${css}</style><div class="s">${html}<div class="sb"><span class="st">9:41</span><span class="si">
        <svg width="18" height="12" viewBox="0 0 18 12"><g fill="#000"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></g></svg>
        <svg width="16" height="12" viewBox="0 0 16 12"><path d="M8 11.5l2.3-2.7a3.4 3.4 0 0 0-4.6 0zM3.9 6.7a6.3 6.3 0 0 1 8.2 0l1.6-1.9a8.8 8.8 0 0 0-11.4 0zM.6 2.9l1.6 1.9a8.9 8.9 0 0 1 11.6 0l1.6-1.9a11.4 11.4 0 0 0-14.8 0z" fill="#000"/></svg>
        <span class="bat"><i></i></span></span></div></div>`;
    this.$ = s => this.shadowRoot.querySelector(s);
    this.$$ = s => [...this.shadowRoot.querySelectorAll(s)];
    this._gen = 0; this._looping = false;
    new ResizeObserver(() => this.style.setProperty("--k", this.clientWidth / 402)).observe(this);
  }
  static observedAttributes = ["active"];
  get t() { return strings(this); }
  connectedCallback() {
    if (!this._built) { this._built = true; this.$(".sb .st").textContent = this.t === STR.ko ? "09:41" : "9:41"; this.build(); }
    viewIO.observe(this);
  }
  disconnectedCallback() { viewIO.unobserve(this); this.stop(); }
  attributeChangedCallback() { this._sync(); }
  _visible(v) { this._seen = v; this._sync(); }
  /* plays while (autoplay or active) and on screen; anything else stops and rewinds */
  _sync() {
    if (!this._built) return;
    const want = this._seen && (this.hasAttribute("autoplay") || this.hasAttribute("active"));
    if (want && !this._looping) this.loop();
    else if (!want && this._looping) { this.stop(); this.reset(); this.beat(0); }
  }
  /** Mark the scene's progress for the page: [data-beat=n] inside the `beats` target lights up. 0 clears. */
  beat(n) {
    this.dispatchEvent(new CustomEvent("nw-beat", { detail: { beat: n }, bubbles: true, composed: true }));
    const sel = this.getAttribute("beats"); if (!sel) return;
    /* two screens can share one list: beat-offset="10" turns this screen's beat 2 into data-beat 12 */
    const off = +(this.getAttribute("beat-offset") || 0); if (n > 0) n += off;
    const host = document.querySelector(sel); if (!host) return;
    host.classList.toggle("nw-beating", n > 0);
    host.querySelectorAll("[data-beat]").forEach(e => e.classList.toggle("nw-beat-on", String(n) !== "0" && e.dataset.beat.split(/[ ,]+/).includes(String(n))));
  }
  /** Stop whatever is running; awaited steps resolve and bail out. */
  stop() { this._gen++; this._looping = false; }
  get alive() { const g = this._gen; return () => g === this._gen; }
  sleep(ms) { const g = this._gen; return new Promise((res, rej) => setTimeout(() => g === this._gen ? res() : rej(STOP), RM ? 0 : ms)); }
  async loop() {
    this.stop(); this._looping = true; const g = this._gen;
    try { while (g === this._gen) { this.reset(); this.beat(0); await (this.scene ? this.scene(this) : this.demo()); if (RM) break; } }
    catch (e) { if (e !== STOP) throw e; }
  }
  /** Run a one-off script: an async function given this screen. Resolves when done or stopped. */
  async run(fn) { this.stop(); this.reset(); try { await fn(this); } catch (e) { if (e !== STOP) throw e; } }
  async sing(el, per = 160) { el.classList.remove("done"); for (const w of el.querySelectorAll(".w")) { await this.sleep(per); w.classList.add("on"); } el.classList.add("done"); }
  async typeInto(el, text, per = 38) { if (RM) { el.textContent = text; return; } el.textContent = ""; for (const ch of text) { await this.sleep(per); el.textContent += ch; } }
  countUp(el, to, ms, fmt = v => v) {
    const g = this._gen, t0 = performance.now();
    return new Promise(res => {
      const step = now => {
        if (g !== this._gen) return res();
        const p = RM ? 1 : Math.max(0, Math.min(1, (now - t0) / ms));
        el.textContent = fmt(Math.round(to * (1 - Math.pow(1 - p, 3))));
        p < 1 ? setTimeout(() => step(performance.now()), 16) : res();
      };
      setTimeout(() => step(performance.now()), 0);
    });
  }
  build() {} reset() {} async demo() {}
  /** Put the screen straight into a named state, no animation — the state a capture shows.
   *  Used by kit/_harness.html to compare against the app, and as a still for reduced motion.
   *  Each screen lists its poses in `static poses`. */
  static poses = [];
  async pose(name) {}
}
const STOP = Symbol("stopped");

/* ═══════════════════════════ <nw-bubble> / <nw-fix> ═══════════════════════════
 * Single lines at any size (font-size on the host scales everything; 17px = the app).
 *   <nw-bubble who="self">Hey, it's you…</nw-bubble>   who = self | me ; label="…" overrides
 *   bubble.play()  lights the words like the call does
 *   <nw-fix note="Past tense">I <b>went</b> to three meetings.</nw-fix> */
class NwBubble extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" }).innerHTML = `<style>${IOS_CSS}
      :host{display:block;font-family:var(--sans);font-size:17px;color:#000;letter-spacing:-.01em}
      :host([who=me]){text-align:right}
      .who{font-size:.765em;color:var(--gray);margin:0 0 .25em}
      .bub{display:inline-block;text-align:left;max-width:var(--max,82%);padding:.53em .82em .59em;border-radius:1.06em;line-height:1.3;background:var(--grouped)}
      :host([who=me]) .bub{background:var(--me)}
    </style><p class="who"></p><div class="bub"></div>`;
  }
  connectedCallback() {
    const t = strings(this), me = this.getAttribute("who") === "me";
    this.shadowRoot.querySelector(".who").textContent = this.getAttribute("label") ?? (me ? t.you : t.self);
    if (this.hasAttribute("nolabel")) this.shadowRoot.querySelector(".who").remove();
    this._text = this.textContent.trim();
    this.shadowRoot.querySelector(".bub").innerHTML = esc(this._text);
  }
  async play(per = 160) {
    const b = this.shadowRoot.querySelector(".bub"); b.classList.add("k"); b.classList.remove("done"); b.innerHTML = wordsHTML(this._text);
    for (const w of b.querySelectorAll(".w")) { await new Promise(r => setTimeout(r, RM ? 0 : per)); w.classList.add("on"); }
    b.classList.add("done");
  }
}
class NwFix extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" }).innerHTML = `<style>${IOS_CSS}
      :host{display:block;font-family:var(--sans);font-size:17px;color:#000}
      .c{border-radius:.94em;background:var(--fixbg);padding:.7em .82em;line-height:1.3}
      .h{font-size:.765em;color:var(--blue);margin-bottom:.45em;display:flex;gap:.35em;align-items:center}
      ::slotted(b),b{color:var(--blue);font-weight:400}
      small{display:block;font-size:.765em;color:var(--gray);margin-top:.45em}
      .sh{display:inline-flex;align-items:center;gap:.35em;margin-top:.7em;height:2.2em;padding:0 .85em;border-radius:1.1em;background:var(--tint);font-size:.765em;color:var(--blue);font-weight:600}
    </style><div class="c"><div class="h">${icon("spark")}<span class="lbl"></span></div><slot></slot><small></small></div>`;
  }
  connectedCallback() {
    const t = strings(this), r = this.shadowRoot;
    r.querySelector(".lbl").textContent = t.natural;
    const note = this.getAttribute("note"); if (note) r.querySelector("small").textContent = note; else r.querySelector("small").remove();
    if (!this.hasAttribute("noshadow") && !r.querySelector(".sh")) r.querySelector(".c").insertAdjacentHTML("beforeend", `<span class="sh">${icon("wave")}${esc(t.shadow)}</span>`);
  }
}

export { STR, RM, strings, esc, wordsHTML, mmss, icon, IOS_CSS, STOP, NwScreen, NwFutureself, NwPhone, NwBubble, NwFix };
