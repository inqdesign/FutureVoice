/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, RM, esc } from "../core.js";

/* ═══════════════════════════ <nw-watch> — your own situation, then the scene ═══════════════════════════
 * The tab: WatchTab's people map (PeopleSky) — the pixel "Watch" title, the filter · stack · people
 * toolbar, me in the middle on dashed rings, my people around, "New situation" floating at the bottom.
 * Tapping it is WatchCreation.creating: the map stays, the header gets Cancel, category chips and the
 * dock box rise over it (real/app-watchtab-sky + -dockCreate captures, 2026-10-24). Me is the learner's
 * initial in the tint, PeopleSkyView.me's no-photo face, the same letter as nw-home's avatar (`initial`).
 * The box: ScenarioComposerSheet.customBox (Mode.custom) as the sheet it is — pixel nav title, Cancel,
 * the CTA circle in the header, heading + note, SituationReel rolling through the empty middle
 * (80pt rows, 4.5 s a row, faded top and bottom), then the box: material chips, the files note,
 * SpeakOrTypeField with + · the person chip on the left and the dictation language · mic on the right.
 * The scene: WatchView — "Watching" + level, counterpart · place, title, blurb, DialogueLine rows
 * (current line ringed), "Shadow this" / "Save phrase" under each, and the bar (Restart · Pause while
 * playing, Watch again · Study this at the end).
 *   poses: map · map-new · composer-attached (shots/device-composer-attached.jpg) · dictating · scene (real/scene-end.png) · playing */

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
  /* the map's toolbar: line.3.horizontal.decrease.circle · rectangle.stack · person.2 */
  filter: '<svg viewBox="0 0 24 24" width="23" height="23"><circle cx="12" cy="12" r="10.4" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M6.6 8.6h10.8M8.4 12h7.2M10.2 15.4h3.6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  stack: '<svg viewBox="0 0 20 24" width="19" height="23"><g fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><rect x="1.8" y="6.6" width="16.4" height="16" rx="3"/><path d="M4.2 3.8h11.6M6.6 1.2h6.8"/></g></svg>',
  people: '<svg viewBox="0 0 31 20" width="30" height="20"><g fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="9.3" cy="5.4" r="3.6"/><path d="M1.6 17.6c0-3.6 3.3-6.2 7.7-6.2 1.4 0 2.7.3 3.8.8"/><circle cx="20.6" cy="5.1" r="4.1"/><path d="M11.4 18.4h18.4c.5 0 .8-.4.7-.9-.7-3.6-4.6-6.2-9.9-6.2s-9.2 2.6-9.9 6.2c-.1.5.2.9.7.9z"/></g></svg>',
  /* square.and.pencil (New situation) */
  pencil: '<svg viewBox="0 0 22 22" width="20" height="20"><g fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M10 3.6H5.6A2.6 2.6 0 0 0 3 6.2v10.2A2.6 2.6 0 0 0 5.6 19h10.2a2.6 2.6 0 0 0 2.6-2.6V12"/><path d="M17.2 2.2l2.6 2.6-8.6 8.6-3.4.8.8-3.4z"/></g></svg>',
  /* relationship glyphs on the bubbles (filled, white) */
  house: '<svg viewBox="0 0 24 22" width="100%" height="100%"><g fill="currentColor"><path d="M17.6 2.4h2.2v4.4l-2.2-1.9z"/><path fill-rule="evenodd" d="M12 4.6l7.6 6.6v8c0 1-.8 1.8-1.8 1.8H6.2c-1 0-1.8-.8-1.8-1.8v-8zm-1.6 9.6v6.8h3.2v-6.8z"/><path d="M11.2 1.3c.5-.4 1.1-.4 1.6 0l10 8.6c.4.3.4.9.1 1.2-.3.4-.9.4-1.2.1L12 2.9l-9.7 8.3c-.4.3-.9.3-1.2-.1-.3-.3-.3-.9.1-1.2z"/></g></svg>',
  brief: '<svg viewBox="0 0 24 20" width="100%" height="100%"><path fill="currentColor" fill-rule="evenodd" d="M8 4V3c0-1.1.9-2 2-2h4c1.1 0 2 .9 2 2v1h4.3C22 4 23 5 23 6.7V10H1V6.7C1 5 2 4 3.7 4zm1.6 0h4.8v-.8c0-.2-.2-.4-.4-.4H10c-.2 0-.4.2-.4.4zM1 11.4h9.6v.9c0 .5.4.9.9.9h1c.5 0 .9-.4.9-.9v-.9H23v4.9c0 1.6-1.1 2.7-2.7 2.7H3.7C2 19 1 18 1 16.3z"/></svg>',
  cap: '<svg viewBox="0 0 26 20" width="100%" height="100%"><g fill="currentColor"><path d="M12.2 1.2c.5-.2 1.1-.2 1.6 0l10.8 4.6c.7.3.7 1.3 0 1.6L13.8 12c-.5.2-1.1.2-1.6 0L1.4 7.4c-.7-.3-.7-1.3 0-1.6z"/><path d="M5.6 10.4l6.6 2.8c.5.2 1.1.2 1.6 0l6.6-2.8v4.2c0 2.2-3.4 4-7.4 4s-7.4-1.8-7.4-4z"/><rect x="21.4" y="7" width="1.6" height="7.6" rx=".8"/></g></svg>',
  people2: '<svg viewBox="0 0 26 18" width="100%" height="100%"><g fill="currentColor"><circle cx="7.6" cy="5.2" r="3.3"/><circle cx="17.6" cy="4.6" r="3.9"/><path d="M1 16.2c0-2.8 2.9-5.2 6.6-5.2 1.5 0 2.8.4 3.9 1-1.2 1.1-2 2.5-2.2 4.2H1.6c-.4 0-.6-.2-.6-.6z"/><path d="M10.6 16.4c0-3.4 3.1-5.7 7-5.7s7 2.3 7 5.7c0 .4-.3.6-.7.6H11.3c-.4 0-.7-.2-.7-.6z"/></g></svg>',
  heart: '<svg viewBox="0 0 22 20" width="100%" height="100%"><path fill="currentColor" d="M11 19.4S1 13.6 1 6.6C1 3.4 3.4 1 6.4 1c2 0 3.7 1 4.6 2.6C11.9 2 13.6 1 15.6 1 18.6 1 21 3.4 21 6.6c0 7-10 12.8-10 12.8z"/></svg>',
  plane: '<svg viewBox="0 0 22 22" width="100%" height="100%"><path fill="currentColor" d="M19.6 2.4c.9.9.6 2.4-.5 3.5l-3.6 3.5 2.2 9.6c.1.4 0 .8-.3 1.1l-.8.8c-.4.4-1 .3-1.3-.2l-4.3-8.1-3.5 3.4.4 2.9c0 .3-.1.6-.3.8l-.6.6c-.3.3-.9.3-1.1-.1l-1.9-3.3-3.3-1.9c-.4-.2-.4-.8-.1-1.1l.6-.6c.2-.2.5-.3.8-.3l2.9.4 3.4-3.5-8.1-4.3c-.5-.3-.6-.9-.2-1.3l.8-.8c.3-.3.7-.4 1.1-.3l9.6 2.2 3.5-3.6c1.1-1.1 2.6-1.4 3.5-.5z"/></svg>',
  /* the creation chips' glyphs (cup.and.saucer.fill · airplane · briefcase.fill · cross.case.fill), black */
  cup: '<svg viewBox="0 0 30 22" width="22" height="16"><g fill="currentColor"><path fill-rule="evenodd" d="M5 2.2C5 1.5 5.5 1 6.2 1h14.6c.7 0 1.2.5 1.2 1.2v1.2h1.4c2.5 0 4.3 1.6 4.3 3.8s-1.8 3.9-4.3 3.9h-2.2c-1.5 2.5-4.1 4.2-7.7 4.2C8.3 15.3 5 11.6 5 6.6zm17 3.3v.5c0 1.2-.1 2.3-.4 3.3h.8c1.2 0 2.1-.8 2.1-1.9s-.9-1.9-2.1-1.9zM8 3.6v1.6c1.3.8 3 1.2 5.5 1.2s4.2-.4 5.5-1.2V3.6z"/><path d="M1.2 16.6c-.6 0-1 .6-.7 1.2C1.6 19.9 5.6 21.4 13.5 21.4s11.9-1.5 13-3.6c.3-.6-.1-1.2-.7-1.2-1.6 0-3.4 1.4-12.3 1.4S2.8 16.6 1.2 16.6z"/></g></svg>',
  cross: '<svg viewBox="0 0 24 20" width="19" height="16"><path fill="currentColor" fill-rule="evenodd" d="M8 4V3c0-1.1.9-2 2-2h4c1.1 0 2 .9 2 2v1h4.3C22 4 23 5 23 6.7v9.6c0 1.6-1.1 2.7-2.7 2.7H3.7C2 19 1 18 1 16.3V6.7C1 5 2 4 3.7 4zm1.6 0h4.8v-.8c0-.2-.2-.4-.4-.4H10c-.2 0-.4.2-.4.4zm1.2 5.1V7.6c0-.4.3-.7.7-.7h1c.4 0 .7.3.7.7v1.5h1.5c.4 0 .7.3.7.7v1c0 .4-.3.7-.7.7h-1.5v1.5c0 .4-.3.7-.7.7h-1c-.4 0-.7-.3-.7-.7v-1.5H9.3c-.4 0-.7-.3-.7-.7v-1c0-.4.3-.7.7-.7z"/></svg>',
  /* person.fill.questionmark on the dock's person chip */
  whoQ: '<svg viewBox="0 0 20 18" width="15" height="14"><g fill="currentColor"><circle cx="7.4" cy="5" r="3.8"/><path d="M.6 16.4c0-3.4 3-5.8 6.8-5.8s6.8 2.4 6.8 5.8c0 .5-.4.9-.9.9H1.5c-.5 0-.9-.4-.9-.9z"/><path d="M14.6 1.4c1.8 0 3 1 3 2.5 0 1-.6 1.6-1.4 2.1-.5.3-.7.6-.7 1.1v.2h-1.7v-.4c0-.9.4-1.5 1.1-1.9.6-.4.9-.6.9-1.1 0-.5-.5-.9-1.2-.9s-1.2.4-1.3 1h-1.7c.1-1.5 1.3-2.6 3-2.6zm-.9 7.3c0-.5.4-.9.9-.9s.9.4.9.9-.4.9-.9.9-.9-.4-.9-.9z"/></g></svg>',
};

/* The map in points (402×874), from the -capture watchtab-sky screenshot: me at (201,541) on three dashed
 * rings; [x, y, diameter, colour, glyph, role, name, depth] — depth 0 is the person in the middle of the
 * screen (full colour), 1 the ring around, 2 the far edge. */
const MAP_ME = [201, 541, 103];
const MAP_RINGS = [168, 282, 412];
const MAP_PEOPLE = ko => [
  [186.6, 362.7, 82, "#1DCAB5", "house", "Mother", "Mom", 0],
  [35.8, 321, 73, "#F6CFAE", "brief", "Colleague", "Sarah", 1],
  [351, 313, 73, "#A5CCF4", "cap", "Yoga teacher", "Mia", 1],
  [60.3, 521, 82, "#DCC8BC", "people2", "Best friend", "Minho", 1],
  [351.7, 528, 82, "#A5CCF4", "heart", "Partner", "Jisu", 1],
  [239, 654, 82, "#EACBEF", "people2", "Friend from school", "Harin", 1],
  [58.5, 157, 64, "#E3E3E8", "cap", ko ? "학원 강사" : "Tutor", ko ? "민정 선생님" : "Ms. Kim", 2],
  [346, 144, 64, "#E3E3E8", "plane", "Berlin", "Emine", 2],
  [212, 104, 60, "#E3E3E8", "people2", "Singapore", "Joy", 2],
];

class NwWatch extends NwScreen {
  constructor() {
    super(`
      :host{background:#C1C0C5;--acc:#0A5CF5;--sec:rgba(60,60,67,.6);--ter:rgba(60,60,67,.3);--fillT:rgba(118,118,128,.12)}
      .gl{position:absolute;height:44px;min-width:44px;padding:0 15px;border-radius:22px;background:rgba(255,255,255,.92);box-shadow:0 6px 22px rgba(0,0,0,.07),0 1px 3px rgba(0,0,0,.04);display:flex;align-items:center;justify-content:center;font-size:17px;letter-spacing:-.4px;color:var(--acc);z-index:4}
      /* ── the tab: the people map ── */
      .l-map{background:#F2F2F7}
      .mp{position:absolute;inset:0;transition:opacity .4s}
      .l-map.mk .mp{opacity:.55}
      .rg{position:absolute;border-radius:50%;border:1.2px dashed rgba(60,60,67,.16)}
      .pp{position:absolute;display:flex;flex-direction:column;align-items:center;text-align:center;white-space:nowrap}
      .pp .bb{border-radius:50%;display:grid;place-items:center;color:#fff}
      .pp .bb i{display:block;width:44%;height:44%}
      .pp small{margin-top:6px;font-size:12.5px;line-height:16px;color:rgba(60,60,67,.32);letter-spacing:0}
      .pp b{font-size:15.5px;line-height:20px;font-weight:600;color:rgba(60,60,67,.5);letter-spacing:-.2px}
      .pp.d1 .bb{opacity:.6}
      .pp.d2{opacity:.5} .pp.d2 .bb{color:rgba(60,60,67,.3)}
      .pp.d0 small{color:rgba(60,60,67,.6)} .pp.d0 b{color:#000}
      .pp.me .bb{background:#fff;box-shadow:inset 0 0 0 3.4px #2E6CF6,0 8px 24px rgba(0,0,0,.07);color:var(--acc);font-size:27px;font-weight:700;letter-spacing:0}
      .pp.me b{margin-top:8px;color:#000;font-weight:500}
      .mfade{position:absolute;left:0;right:0;top:0;height:132px;background:linear-gradient(#F2F2F7 55%,rgba(242,242,247,0));pointer-events:none}
      .ttl{position:absolute;left:18px;top:60px;font-family:var(--pixel);font-size:36px;line-height:46px;letter-spacing:0;transition:opacity .3s;z-index:4}
      .tb{position:absolute;right:16.6px;top:62px;width:168px;height:44px;border-radius:22px;background:rgba(255,255,255,.92);box-shadow:0 6px 22px rgba(0,0,0,.07),0 1px 3px rgba(0,0,0,.04);display:flex;align-items:center;justify-content:space-around;padding:0 6px;color:var(--acc);z-index:4;transition:opacity .25s}
      .nb{position:absolute;left:137px;width:129px;top:765px;height:59px;border-radius:30px;background:rgba(255,255,255,.95);box-shadow:0 8px 26px rgba(0,0,0,.08),0 1px 3px rgba(0,0,0,.04);display:flex;gap:9px;align-items:center;justify-content:center;color:var(--acc);font-size:17px;font-weight:600;letter-spacing:-.4px;transition:transform .15s,opacity .3s;z-index:4}
      .nb.tap{transform:scale(.93)}
      .l-map .gl.cn{left:16px;top:62px;opacity:0;transition:opacity .3s}
      /* chips and box stack from the bottom, so a two-line placeholder pushes the chips up, never under */
      .dk{position:absolute;left:0;right:0;bottom:41px;display:flex;flex-direction:column;gap:12px;z-index:4}
      .cats{padding-left:16px;display:flex;gap:10px;white-space:nowrap}
      .cats span{height:40px;padding:0 16px;border-radius:20px;background:rgba(255,255,255,.94);box-shadow:0 4px 14px rgba(0,0,0,.06);display:flex;align-items:center;gap:9px;font-size:17px;letter-spacing:-.4px;color:#000}
      .l-map .box{position:relative;left:auto;right:auto;bottom:auto;margin:0 12px}
      .l-map .who .wn{max-width:118px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .l-map .cats,.l-map .box{opacity:0;transform:translateY(150px);transition:opacity .35s,transform .5s cubic-bezier(.2,.8,.2,1)}
      .l-map.mk .cats,.l-map.mk .box{opacity:1;transform:none}
      .l-map.mk .ttl,.l-map.mk .nb{opacity:0}
      .l-map.mk .gl.cn{opacity:1}
      .l-map .cta{top:62px;opacity:0;transition:opacity .25s,background .3s,transform .15s}
      .l-map.typed .cta{opacity:1} .l-map.typed .tb{opacity:0}
      .l-map.inst,.l-map.inst *{transition:none!important}
      .tools .who.q .av{background:rgba(10,92,245,.15);font-style:normal}
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
      <div class="layer l-map on">
        <div class="mp"></div><div class="mfade"></div>
        <div class="ttl"></div><div class="gl cn"></div>
        <div class="tb"><span>${SY.filter}</span><span>${SY.stack}</span><span>${SY.people}</span></div>
        <div class="cta">${SY.playFill}</div>
        <div class="nb">${SY.pencil}<span></span></div>
        <div class="dk"><div class="cats"></div>
        <div class="box bare">
          <div class="fld ph"></div>
          <div class="tools"><span class="pl">${SY.plus}</span><span class="who q"><i class="av">${SY.whoQ}</i><span class="wn"></span></span><span class="rec"><i></i><span></span></span><span class="sp"></span><span class="lg"><span></span>${SY.updown}</span><span class="mic">${SY.mic}</span></div>
        </div></div>
      </div>
      <div class="layer l-box"><div class="sht">
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
  /* `.l-map` comes first in the DOM, so everything of the sheet's is looked up inside `.l-box` */
  B(sel) { return this.$(`.l-box ${sel}`); }
  M(sel) { return this.$(`.l-map ${sel}`); }

  build() {
    const ko = this.ko;
    this.B(".cn").textContent = ko ? "취소" : "Cancel";
    this.$(".nt").textContent = ko ? "내 상황" : "Your situation";
    this.$(".hd b").textContent = ko ? "그 일을 미리 한 번 겪어 보세요" : "Go through it before it happens";
    this.$(".hd p").textContent = ko ? "자세히 적을수록 장면이 실제에 가까워져요. 공고나 이력서가 있으면 ＋로 가져오세요." : "The more you write, the closer the scene lands. Tap ＋ to bring the posting, the listing, your CV.";
    const R = ko ? ["다음 주 목요일 최종 면접. 공고를 쓴 하이어링 매니저와 영어로.", "집주인에게 보일러가 3주째 고장이라고 말하고, 언제 고쳐 줄지 날짜를 받아 내기.", "애인의 부모님을 처음 뵙는 자리. 그 집에서 저녁을 먹으면서.", "일주일째 있는 증상을 의사에게 설명하고, 어떤 방법이 있는지 물어보기.", "다음 1:1에서 팀장에게 연봉 인상을 요청하기. 근거가 될 숫자를 들고.", "영수증 없이 비싼 물건을 환불받기. 점원은 받아 주기 싫어하는 상황."]
      : ["A final-round interview next Thursday, in English, with the hiring manager who wrote the job ad.", "Telling my landlord the heating has been broken for three weeks, and getting a date out of them.", "Meeting my partner's parents for the first time over dinner at their place.", "Explaining a symptom I've had for a week to a doctor, and asking what the options are.", "Asking my manager for a raise in our next one-on-one, with the numbers ready.", "Returning something expensive without the receipt, to a clerk who doesn't want to take it."];
    this.$(".reel .tr").innerHTML = [...R, ...R].map(x => `<div class="rw"><span>${esc(x)}</span></div>`).join("");
    this.$(".note").textContent = ko ? "파일은 폰에 그대로 있어요. 앱에는 읽은 내용만 남아요." : "Your files stay on your phone. Only what was read is kept here.";
    this.B(".av").textContent = "P"; this.B(".wn").textContent = "Paige";
    this.$(".wt b").textContent = ko ? "보는 중" : "Watching";
    for (const sel of [".l-box", ".l-map"]) {
      this.$(`${sel} .rec span`).textContent = ko ? "듣는 중 · 누르면 끝" : "Listening, tap to finish";
      this.$(`${sel} .lg span`).textContent = ko ? "한국어" : "English";
    }
    this._buildMap();
    this.reset();
  }

  _buildMap() {
    const ko = this.ko, ring = d => `<div class="rg" style="left:${MAP_ME[0] - d}px;top:${MAP_ME[1] - d}px;width:${2 * d}px;height:${2 * d}px"></div>`;
    const person = ([x, y, d, c, g, role, name, depth]) =>
      `<div class="pp d${depth}" style="left:${x - 70}px;width:140px;top:${y - d / 2}px"><span class="bb" style="width:${d}px;height:${d}px;background:${c}"><i>${SY[g]}</i></span><small>${esc(role)}</small><b>${esc(name)}</b></div>`;
    const [mx, my, md] = MAP_ME;
    this.M(".mp").innerHTML = MAP_RINGS.map(ring).join("") + MAP_PEOPLE(ko).map(person).join("")
      + `<div class="pp me" style="left:${mx - 70}px;width:140px;top:${my - md / 2}px"><span class="bb" style="width:${md}px;height:${md}px">${esc(this.getAttribute("initial") || (ko ? "하" : "H"))}</span><b>${ko ? "나" : "Me"}</b></div>`;
    this.M(".ttl").textContent = ko ? "상황연습" : "Watch";
    this.M(".cn").textContent = ko ? "취소" : "Cancel";
    this.M(".nb span").textContent = ko ? "새 상황" : "New situation";
    if (!ko) { const nb = this.M(".nb"); nb.style.left = "118px"; nb.style.width = "166px"; }
    const C = ko ? [["cup", "카페"], ["plane", "여행"], ["brief", "일"], ["cross", "건강"]] : [["cup", "Cafe"], ["plane", "Travel"], ["brief", "Work"], ["cross", "Health"]];
    this.M(".cats").innerHTML = C.map(([g, t]) => `<span>${g === "plane" || g === "brief" ? SY[g].replace('width="100%" height="100%"', 'width="19" height="17"') : SY[g]}${esc(t)}</span>`).join("");
    this.M(".wn").textContent = ko ? "상황에 맞는…" : "From the situation";
  }

  reset() {
    const ko = this.ko, ph = ko ? "어떤 상황을 만들어 볼까요? 자세할수록 좋아요." : "What situation should we build? The more detail, the better.";
    // the tab first (`start="box"` keeps the old sheet-first demo for pages built on it)
    const first = this.getAttribute("start") === "box" ? "l-box" : "l-map";
    this.$$(".layer").forEach(l => l.classList.toggle("on", l.classList.contains(first)));
    for (const f of this.$$(".fld")) { f.className = "fld ph"; f.textContent = ph; }
    this.$$(".box").forEach(b => b.classList.remove("recording")); this.$(".reel").classList.remove("off");
    /* material="none": nothing attached, so no chips and no files note (the sheet draws both only when
       the scenario has sources). Default keeps the attached posting. */
    this.B(".box").classList.toggle("bare", this.getAttribute("material") === "none");
    this.$$(".cta").forEach(c => c.classList.remove("on", "tap"));
    this.$(".l-map").classList.remove("mk", "typed", "inst"); this.M(".nb").classList.remove("tap");
    this.$$(".sc .ln,.sc .ld").forEach(e => e.remove()); this.$(".sc").style.transform = "none";
    this._bar("play"); this.$(".bs").classList.add("off");
  }

  _bar(state) {
    const ko = this.ko, bs = this.$(".bs"); bs.classList.remove("off");
    if (state === "end") {
      this.$(".b1").innerHTML = `${SY.again}<span>${ko ? "다시 보기" : "Watch again"}</span>`;
      this.$(".b2").innerHTML = `${SY.books}<span>${ko ? "교재로 공부하기" : "Study this"}</span>`;
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

  _show(layer) { this.$$(".layer").forEach(l => l.classList.toggle("on", l.classList.contains(layer))); }

  static poses = ["map", "map-new", "composer-attached", "dictating", "scene", "playing"];
  async pose(name) {
    this.stop(); this.reset();
    if (name === "map") this._show("l-map");
    if (name === "map-new") { this._show("l-map"); this.$(".l-map").classList.add("inst", "mk"); }
    if (name === "composer-attached" || name === "dictating") this._show("l-box");
    if (name === "composer-attached") this.B(".box").classList.remove("bare");
    if (name === "dictating") {
      this.B(".box").classList.add("recording"); this.$(".reel").classList.add("off");
      const f = this.B(".fld"); f.className = "fld"; f.textContent = this._said().slice(0, 30);
    }
    if (name === "scene" || name === "playing") {
      this._show("l-scene");
      if (name === "scene") {
        this._header("Barista · at the cafe", "The wrong order", "My order came out wrong and I point it out politely.");
        this._scene([["Barista", "Hi! What can I get you today?", false], ["Future self", "A flat white, please. For here.", true],
          ["Barista", "Coming right up. Here you go!", false], ["Future self", "Sorry, I think this is a latte, not a flat white.", true],
          ["Barista", "Oh, you're right. Let me remake that for you.", false]], 0);
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
    const fromBox = this.getAttribute("start") === "box";
    const L = fromBox ? ".l-box" : ".l-map", f = this.$(`${L} .fld`), box = this.$(`${L} .box`), cta = this.$(`${L} .cta`);
    if (!fromBox) {
      // the tab: my people around me, then "New situation" — the box rises over the map
      await this.sleep(1700);
      const nb = this.M(".nb"); nb.classList.add("tap"); await this.sleep(170); nb.classList.remove("tap");
      this.$(".l-map").classList.add("mk"); await this.sleep(1000);
    } else await this.sleep(1400);
    this.beat(1);
    // dictate the situation into the box: mic → live partials → mic again
    box.classList.add("recording"); await this.sleep(500);
    this.$(".reel").classList.add("off"); f.className = "fld";
    const words = this._said().split(" "); let said = "";
    for (const w of words) { said += (said ? " " : "") + w; f.textContent = said; await this.sleep(190); }
    await this.sleep(500); box.classList.remove("recording");
    this.$(".l-map").classList.add("typed");
    cta.classList.add("on"); await this.sleep(800);
    cta.classList.add("tap"); await this.sleep(160); cta.classList.remove("tap");
    // the scene: written, then played
    this._header(...this._interviewHead());
    const ld = document.createElement("div"); ld.className = "ld"; ld.innerHTML = `<i class="spin"></i>${this.ko ? "대화를 쓰는 중…" : "Writing the dialogue…"}`;
    this.$(".sc").append(ld);
    this._show("l-scene");
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
